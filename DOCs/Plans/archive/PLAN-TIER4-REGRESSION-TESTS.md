# Plan: Tier 4 Regression Tests

**Source**: REGRESSION-TEST-COVERAGE-ANALYSIS.md, Section 7 "Tier 4: Aspirational / Long-Term"
**Date**: 2026-03-15
**Prerequisite**: Tiers 1-3 fully implemented (427 tests across 20 suites, all passing)

---

## Overview

Tier 4 contains three test opportunities identified in the coverage analysis:

| ID | Name | Focus |
|----|------|-------|
| O-18 | Per-cog CWD isolation | Multi-cog directory independence |
| O-19 | Concurrent reader + writer stress | Sustained parallel I/O with data integrity verification |
| O-20 | Manual mutation testing | Deliberate bug injection to validate test suite sensitivity |

These are the most architecturally complex tests in the suite. O-18 and O-19 require multi-cog coordination with precise synchronization. O-20 is a meta-test — it tests the tests themselves.

---

## O-18: Per-Cog CWD Isolation Test

### What We're Verifying

The driver maintains `cog_dir_sec[8]` — a per-cog array of current working directory sectors (line 499 of the driver). When any cog calls `changeDirectory()`, the worker indexes this array by `pb_caller` (the calling cog's COGID) to store that cog's CWD. All subsequent file operations from that cog use its own CWD for relative path resolution.

This mechanism is architecturally critical: it allows multiple cogs to work in different directories simultaneously without interfering with each other. But no existing test verifies cross-cog isolation. All directory tests run from a single cog.

### What Could Go Wrong

- `pb_caller` not correctly passed through the mailbox for `changeDirectory()`
- Worker using a stale or wrong cog ID to index `cog_dir_sec[]`
- Race condition: cog A's `changeDirectory()` overwriting cog B's CWD slot
- File creation using the wrong cog's CWD for directory sector lookup
- `readDirectory()` enumerating the wrong cog's CWD

### Test Design

**New test file**: `src/regression-tests/SD_RT_cogcwd_tests.spin2`

**Rationale for a new file**: This test requires dedicated multi-cog infrastructure (worker stacks, synchronization barriers, shared status arrays) that would bloat an existing suite. The multicog_tests suite focuses on lock serialization and singleton verification — different concerns. A dedicated file keeps each suite focused.

**Hardware requirement**: Two subdirectories on card. Tests create `/CWDTEST1/` and `/CWDTEST2/` in setup, delete them in cleanup.

**Timeout**: `-t 120` (multi-cog coordination needs margin)

#### Test Group 1: Basic CWD Independence (3 tests)

**Test 1: Two cogs in different directories see different files**

```
Setup:
  Main cog creates /CWDTEST1/ and /CWDTEST2/
  Main cog creates /CWDTEST1/FILE_A.TXT (write known content "AAAA")
  Main cog creates /CWDTEST2/FILE_B.TXT (write known content "BBBB")
  Main cog returns to root: changeDirectory("/")

Test:
  Main cog launches worker cog
  sync_barrier releases both cogs simultaneously
  Main cog: changeDirectory("/CWDTEST1/")
  Worker cog: changeDirectory("/CWDTEST2/")
  Both cogs wait at second barrier (ensures both CDs complete)

  Main cog: handle := openFileRead("FILE_A.TXT")
    → should succeed (FILE_A.TXT is in CWDTEST1)
  Main cog: read 4 bytes → should be "AAAA"
  Main cog: closeFileHandle(handle)

  Worker cog: handle := openFileRead("FILE_B.TXT")
    → should succeed (FILE_B.TXT is in CWDTEST2)
  Worker cog: read 4 bytes, store in shared buffer
  Worker cog: closeFileHandle(handle)
  Worker cog: sets worker_status := STATUS_PASS/FAIL

  Main cog: waits for worker, checks worker read "BBBB"

Assertions:
  - Main cog's openFileRead succeeded (handle >= 0)
  - Main cog read "AAAA"
  - Worker cog's openFileRead succeeded
  - Worker cog read "BBBB" (verified from shared buffer)
```

**Test 2: One cog's changeDirectory does not affect another cog's CWD**

```
Setup: Same directory structure from Test 1

Test:
  Main cog: changeDirectory("/CWDTEST1/")
  Launch worker cog
  Worker cog: changeDirectory("/CWDTEST2/")
  Worker cog: signals done

  Main cog (after worker's CD completes):
    openFileRead("FILE_A.TXT") → should still succeed
    (proves main cog's CWD was not changed by worker's changeDirectory)

Assertions:
  - Main cog still sees FILE_A.TXT (CWD still /CWDTEST1/)
  - Worker completed without error
```

**Test 3: Both cogs create files in their own CWD**

```
Test:
  Main cog: changeDirectory("/CWDTEST1/")
  Worker cog: changeDirectory("/CWDTEST2/")
  Barrier: both CDs complete

  Main cog: createFileNew("COG0.TXT"), write "FROM_COG0", close
  Worker cog: createFileNew("COG1.TXT"), write "FROM_COG1", close
  Barrier: both creates complete

  Verification (main cog, sequentially):
    changeDirectory("/CWDTEST1/")
    openFileRead("COG0.TXT") → should succeed, content "FROM_COG0"
    openFileRead("COG1.TXT") → should fail (E_FILE_NOT_FOUND)

    changeDirectory("/CWDTEST2/")
    openFileRead("COG1.TXT") → should succeed, content "FROM_COG1"
    openFileRead("COG0.TXT") → should fail (E_FILE_NOT_FOUND)

Assertions (8 sub-checks):
  - COG0.TXT exists in CWDTEST1, not in CWDTEST2
  - COG1.TXT exists in CWDTEST2, not in CWDTEST1
  - Content matches for both files
```

#### Test Group 2: CWD Persistence Under Load (2 tests)

**Test 4: CWD survives repeated file operations**

```
Test:
  Main cog: changeDirectory("/CWDTEST1/")
  Worker cog: changeDirectory("/CWDTEST2/")

  repeat 10 times:
    Main cog: create file, write, close, delete
    Worker cog: create file, write, close, delete
    (All operations use relative paths)

  After 10 iterations:
    Main cog: still in /CWDTEST1/ (verify by creating a file and finding it there)
    Worker cog: still in /CWDTEST2/ (report via shared variable)

Assertions:
  - Main cog's CWD unchanged after 10 create/delete cycles
  - Worker cog's CWD unchanged after 10 create/delete cycles
```

**Test 5: CWD isolation with changeDirectory("/") reset on one cog**

```
Test:
  Main cog: changeDirectory("/CWDTEST1/")
  Worker cog: changeDirectory("/CWDTEST2/")
  Barrier

  Worker cog: changeDirectory("/")  (reset to root)
  Worker cog: signals done

  Main cog: openFileRead("FILE_A.TXT") → should still succeed
    (CWD still /CWDTEST1/ despite worker resetting to root)

Assertions:
  - Main cog's CWD unaffected by worker's cd to root
```

#### Cleanup

All tests delete COG0.TXT, COG1.TXT, FILE_A.TXT, FILE_B.TXT from both directories, then delete the directories themselves. Return to root.

#### Implementation Notes

- Follow the `SD_RT_multicog_tests.spin2` pattern exactly: `cogspin()`, shared `worker_status[]` array, `sync_barrier` hub variable, `waitForWorkers()` polling loop
- Worker cogs write results to shared DAT variables; main cog evaluates assertions
- Worker stacks: `STACK_SIZE = 128` longs per worker (same as multicog_tests)
- Only 1 worker cog needed (2 cogs total: main + worker)
- Feature flags needed: `SD_INCLUDE_ALL` (for debug if needed, but core file ops don't require it)

#### Estimated Test Count: 5 tests, ~16 sub-assertions

---

## O-19: Concurrent Reader + Writer Stress Test

### What We're Verifying

That the driver's lock-based serialization (`api_lock`) correctly protects data integrity when one cog writes continuously to one file while another cog reads continuously from a different file. Over many iterations, neither cog should see corrupted data, wrong byte counts, or stale cache contents.

### What Could Go Wrong

- Lock contention causing a cog to read a partially-written sector from hub cache
- Cross-buffer cache coherence failure: writer's `writeSector()` invalidates a cache entry that the reader's in-flight `readSector()` was about to use
- Per-handle buffer corruption: writer's `h_buf[handle_w]` bleeds into reader's `h_buf[handle_r]` (adjacent memory)
- Handle metadata corruption under concurrent access: `h_position`, `h_sector`, `h_size` for one handle corrupted by another handle's operation
- Worker cog dispatch using stale `pb_caller` or `pb_param` from a previous command (race in mailbox handoff)

### Test Design

**New test file**: `src/regression-tests/SD_RT_stress_tests.spin2`

**Rationale for a new file**: Stress tests run for many iterations and have different timeout requirements and failure modes than functional tests. A separate file keeps the fast-running functional suites fast.

**Timeout**: `-t 120` (many iterations of SD I/O)

#### Setup Phase (Main Cog)

```
1. Create STRESS_R.TXT (the read target):
   - Open for write
   - Write 10 sectors (5120 bytes) of known pattern:
     Sector 0: all $00, Sector 1: all $11, ... Sector 9: all $99
   - Close

2. Create STRESS_W.TXT as empty file (the write target):
   - createFileNew, close immediately
   - (Worker will open for write)
```

The read file is pre-populated with a predictable pattern where each sector has a distinct fill byte. This makes corruption immediately detectable — if a read returns $33 where $55 was expected, we know exactly which sector's data leaked.

#### Test Group 1: Sustained Concurrent Read + Write (2 tests)

**Test 6: Reader integrity under concurrent writing**

```
Constants:
  STRESS_ITERATIONS = 50
  READ_SIZE = 512              ' One sector per read
  WRITE_SIZE = 64              ' Small writes to maximize lock contention

Main cog (reader):
  handle_r := openFileRead("STRESS_R.TXT")
  repeat STRESS_ITERATIONS times:
    seekHandle(handle_r, 0)                  ' Rewind to start
    repeat sector_idx from 0 to 9:
      bytesRead := readHandle(handle_r, @read_buf, READ_SIZE)
      expected_fill := sector_idx * $11
      Verify all 512 bytes == expected_fill
      If any mismatch: record sector_idx, expected, actual, iteration
  closeFileHandle(handle_r)

Worker cog (writer):
  handle_w := openFileWrite("STRESS_W.TXT")
  repeat STRESS_ITERATIONS times:
    fillBufferWithPattern(@write_buf, WRITE_SIZE, iteration)
    bytesWritten := writeHandle(handle_w, @write_buf, WRITE_SIZE)
    if bytesWritten <> WRITE_SIZE:
      worker_errors++
  closeFileHandle(handle_w)
  worker_status := STATUS_PASS/FAIL

Synchronization:
  Both cogs start after barrier release
  Main cog waits for worker after its own loop completes

Assertions:
  - Zero data mismatches across all 50 * 10 = 500 sector reads
  - Worker reported zero write errors
  - Both handles closed successfully
```

**Test 7: Writer integrity verified after concurrent reading**

```
After Test 6 completes:
  Main cog opens STRESS_W.TXT for read
  Reads all written data back
  Verifies the pattern matches what the writer intended:
    Each 64-byte chunk should contain the iteration-based pattern

Assertions:
  - File size matches expected (STRESS_ITERATIONS * WRITE_SIZE)
  - Data pattern correct throughout
```

#### Test Group 2: High-Contention Interleaved Operations (2 tests)

**Test 8: Both cogs read the same file simultaneously**

```
Main cog and worker cog both open STRESS_R.TXT for read
(Multi-reader is allowed; single-writer is enforced)

Both cogs:
  repeat 20 times:
    seekHandle to random sector boundary (0, 512, 1024, ...)
    readHandle 512 bytes
    Verify pattern matches expected fill for that sector

Assertions:
  - Main cog: zero mismatches across 20 reads
  - Worker cog: zero mismatches across 20 reads
  - No handle interference (independent position tracking)
```

**Test 9: Rapid open/close cycles under contention**

```
Main cog: repeat 20 times:
  handle := openFileRead("STRESS_R.TXT")
  readHandle(handle, @buf, 64)
  closeFileHandle(handle)

Worker cog: repeat 20 times:
  handle := openFileRead("STRESS_R.TXT")
  readHandle(handle, @buf, 64)
  closeFileHandle(handle)

Both run concurrently. This stresses:
  - Handle allocation/deallocation under contention
  - Lock acquire/release cycling
  - Handle pool recycling correctness

Assertions:
  - Main cog: all 20 open/read/close cycles succeeded
  - Worker cog: all 20 open/read/close cycles succeeded
  - Data read matches expected pattern on every cycle
```

#### Cleanup

Delete STRESS_R.TXT and STRESS_W.TXT.

#### Implementation Notes

- Worker stacks: `STACK_SIZE = 128` longs (same as multicog_tests)
- Worker cog needs its own read/write buffer (64 bytes in shared DAT, indexed by worker_id)
- Main cog needs 512-byte read buffer plus 16-byte guard zone
- Use `fillBufferWithPattern()` and `verifyBufferPattern()` from isp_rt_utilities for pattern generation/checking
- For "random" seeks in Test 8, use a deterministic pseudo-random sequence (e.g., `?seed` in Spin2) so failures are reproducible
- Track iteration count in `worker_result[]` so that if the worker hangs, we know which iteration it reached

#### Estimated Test Count: 4 tests, ~12 sub-assertions

---

## O-20: Manual Mutation Testing

### What We're Verifying

That the existing test suite (Tiers 1-4) actually catches real bugs. Mutation testing introduces small, deliberate defects into the driver and checks whether at least one test fails for each mutation. If a mutation survives (all tests still pass), we have a gap.

### Why This Matters

A test suite with 100% pass rate is only as strong as the bugs it would catch. A test that checks `readHandle returns >= 0` would pass even if the driver returned the wrong byte count. Mutation testing reveals where assertions are too weak or too indirect to catch real defects.

### Approach

Unlike O-18 and O-19, this is NOT a new test file. It's a structured procedure performed against the existing driver code, documented as a matrix of mutations and results.

#### Phase 1: Define the Mutation Catalog

Each mutation is a single, minimal change to the driver that introduces a specific class of bug. The mutations target code that the test suite SHOULD catch:

**Category A: Off-By-One Mutations (boundary errors)**

| ID | Location | Mutation | What Should Catch It |
|----|----------|----------|---------------------|
| M-A1 | `do_write_h` sector-full check | Change `== 0` to `== 1` in position boundary test | read_write_tests boundary tests (O-12, O-14) |
| M-A2 | `do_read_h` bytes-available calc | Change `count <# available` to `count <# (available - 1)` | read_write_tests (short read detection) |
| M-A3 | `allocateCluster` FAT scan | Start scan at cluster 3 instead of cluster 2 | volume_tests disk-full (O-13), read_write_tests |
| M-A4 | `do_seek_h` position clamping | Change `pos <# h_size[handle]` to `pos <# (h_size[handle] - 1)` | seek_tests (seek to exact EOF) |

**Category B: Wrong Value Mutations (logic errors)**

| ID | Location | Mutation | What Should Catch It |
|----|----------|----------|---------------------|
| M-B1 | `do_close_h` size writeback | Write `h_size[handle] + 1` instead of `h_size[handle]` | read_write_tests (file size verification via fileSizeHandle) |
| M-B2 | `do_close_h` | Skip dirty buffer flush (comment out the `if HF_DIRTY` block) | read_write_tests (read-after-write round-trip) |
| M-B3 | `cog_dir_sec` indexing | Use `pb_caller + 1` instead of `pb_caller` in changeDirectory | cogcwd_tests (O-18) |
| M-B4 | `do_read_h` bytes_read return | Return `bytes_read - 1` | read_write_tests (byte count verification) |

**Category C: Error Path Mutations (error handling)**

| ID | Location | Mutation | What Should Catch It |
|----|----------|----------|---------------------|
| M-C1 | `validateHandle` | Always return TRUE | error_handling_tests (invalid handle), multihandle_tests (use-after-close) |
| M-C2 | `single-writer check` | Skip E_FILE_ALREADY_OPEN enforcement | multihandle_tests (single-writer test) |
| M-C3 | `do_open_read` file-not-found | Return handle 0 instead of E_FILE_NOT_FOUND | file_ops_tests, error_handling_tests |
| M-C4 | `do_sync_h` | Skip directory entry update (comment out the `if HF_WRITE` block) | volume_tests (sync verification), would also be caught by O-18/O-19 if file size checked after sync |

**Category D: Concurrency Mutations (multi-cog safety)**

| ID | Location | Mutation | What Should Catch It |
|----|----------|----------|---------------------|
| M-D1 | `send_command` | Remove `locktry(api_lock)` (no lock acquisition) | multicog_tests, stress_tests (O-19) |
| M-D2 | Worker dispatch | Don't clear `pb_cmd` after execution | All tests (driver hangs — detected by timeout) |
| M-D3 | `cog_dir_sec` init | Initialize to sector 0 instead of `root_sec` | cogcwd_tests (O-18), directory_tests |

#### Phase 2: Execute Each Mutation

For each mutation in the catalog:

1. Apply the single-character or single-line change to the driver
2. Compile: `cd src/regression-tests && pnut-ts -I .. -I ../UTILS -I ../DEMO -I . <test_file>.spin2`
   - If it doesn't compile, the mutation is detected at compile time (mark as "caught: compile")
3. If it compiles, run the specific test suite(s) listed in "What Should Catch It"
4. Record the result:
   - **Killed**: At least one test fails → mutation detected, suite is effective
   - **Survived**: All tests pass → GAP IDENTIFIED, need a new or stronger test
   - **Timeout**: Test hangs → mutation detected (but crudely)

#### Phase 3: Address Survivors

For each surviving mutation:

1. Analyze WHY no test caught it — is the assertion too weak? Is the postcondition unchecked?
2. Write a new test or strengthen an existing assertion to catch it
3. Re-run the mutation to confirm the new test kills it
4. Document the new test and what gap it closed

#### Execution Order

Mutations should be tested in this order, based on likelihood of revealing real gaps:

1. **First**: Category B (wrong values) — these are the mutations most likely to survive because they produce plausible-but-wrong results
2. **Second**: Category A (off-by-one) — boundary tests from Tier 3 should catch these, but mutation testing will verify
3. **Third**: Category C (error paths) — error_handling_tests should catch these
4. **Fourth**: Category D (concurrency) — requires O-18 and O-19 to be implemented first

#### Deliverable

A results matrix document: `DOCs/Analysis/MUTATION-TEST-RESULTS.md`

```markdown
| Mutation ID | Description | Test(s) Run | Result | Notes |
|-------------|-------------|-------------|--------|-------|
| M-A1 | Off-by-one in sector-full | read_write_tests | Killed | Test "512-byte boundary" failed |
| M-B2 | Skip dirty flush on close | read_write_tests | Killed | Round-trip test saw zeros |
| M-C1 | validateHandle always TRUE | error_handling | Killed | Invalid handle test failed |
| ... | ... | ... | ... | ... |
```

#### Implementation Notes

- Each mutation MUST be applied and reverted individually — never stack multiple mutations
- Use `git stash` or a working copy to manage mutations cleanly
- Do NOT commit any mutation to the repository
- Some mutations (M-D1: remove lock) may cause hardware hangs or non-deterministic failures — always use timeouts
- Category D mutations should be tested AFTER O-18 and O-19 are implemented and passing

#### Estimated Effort: 14 mutations, ~2-3 hours of manual testing

---

## Implementation Sequence

### Step 1: O-18 (Per-Cog CWD Isolation)

**Why first**: It's the most architecturally significant test in Tier 4. Per-cog CWD is a core design feature with zero test coverage today. It's also a prerequisite for mutation M-B3 and M-D3 in O-20.

**Deliverables**:
- New file: `src/regression-tests/SD_RT_cogcwd_tests.spin2`
- 5 tests, ~16 sub-assertions
- Added to `run_regression.sh` suite list (after multicog_tests)
- Updated THEORY-OF-OPERATIONS.md and README.md in regression-tests/

**Dependencies**: None beyond working multi-cog infrastructure (proven by multicog_tests)

### Step 2: O-19 (Concurrent Reader + Writer Stress)

**Why second**: Validates data integrity under sustained concurrent access — the highest-risk scenario for a multi-cog driver. Also a prerequisite for O-20 Category D mutations.

**Deliverables**:
- New file: `src/regression-tests/SD_RT_stress_tests.spin2`
- 4 tests, ~12 sub-assertions
- Added to `run_regression.sh` suite list (last, since it's slowest)
- Updated THEORY-OF-OPERATIONS.md and README.md

**Dependencies**: None beyond working multi-cog infrastructure

### Step 3: O-20 (Manual Mutation Testing)

**Why last**: It tests the tests. All other suites (including O-18 and O-19) must be implemented and passing before we can meaningfully evaluate mutation survival.

**Deliverables**:
- New document: `DOCs/Analysis/MUTATION-TEST-RESULTS.md`
- Any new tests or strengthened assertions identified by surviving mutations
- Updated REGRESSION-TEST-COVERAGE-ANALYSIS.md with final gap assessment

**Dependencies**: O-18 and O-19 implemented and passing. All 22 suites green.

---

## Post-Implementation Suite Summary

After Tier 4 implementation, the regression suite will be:

| Metric | Before (Tier 3) | After (Tier 4) |
|--------|-----------------|----------------|
| Test suites | 20 | 22 (+cogcwd, +stress) |
| Total tests | ~427 | ~436 (+5 +4) |
| Multi-cog suites | 1 (multicog) | 3 (+cogcwd, +stress) |
| Per-cog CWD coverage | None | 5 tests with cross-cog verification |
| Sustained concurrency testing | None | 50+ iterations of parallel read/write |
| Mutation test coverage | Unknown | 14 mutations cataloged, survivors addressed |

---

## Resolved Design Decisions

### D1: Iteration count for O-19 stress tests — 50 with manual override

**Decision**: 50 iterations for the regression suite, with `STRESS_ITERATIONS = 50` as a CON constant that can be manually increased for release qualification.

**Rationale**: The regression suite runs regularly as a gate on every release — test runtime matters. At 50 iterations, the stress test takes roughly 5-10 seconds of SPI time, comfortable within a 120-second timeout. At 200 iterations, it's 30+ seconds of SPI time, slow enough that developers skip it.

More importantly, the bugs these stress tests catch are **deterministic, not probabilistic**. Lock serialization either works or it doesn't. Per-handle buffer isolation either holds or it doesn't. The P2's hub access is deterministic (egg beater round-robin), and the driver's lock is a hardware lock. 50 iterations exercises the full lifecycle many times and catches any systematic corruption. If a bug requires 200 iterations to surface, it's a timing-dependent issue that needs a fundamentally different test approach (deliberately misaligned timing), not just more repetitions.

**Escape hatch**: For release qualification or after a significant driver change, manually set `STRESS_ITERATIONS` to 200 or 500 and run once. This keeps the daily regression fast while allowing deep runs on demand.

### D2: O-18 tests 2 cogs only — sufficient for proof

**Decision**: Main cog + 1 worker (2 cogs total). Do not test 3+ cogs.

**Rationale**: The isolation mechanism is `cog_dir_sec[pb_caller]` — a direct array index by cog ID. There is no interaction between entries. Cog 3's CWD slot cannot corrupt cog 5's slot because they are independent LONGs in an array. The only way this breaks is if `pb_caller` is wrong, and that failure mode is binary — it either indexes correctly or it doesn't. Testing with 2 cogs proves the indexing works. Testing with 3 or 4 cogs would re-prove the same thing with more stacks, more synchronization complexity, and more opportunity for test bugs to masquerade as driver bugs.

The one hypothetical concern would be aliasing — e.g., `pb_caller` masked to fewer bits, causing cog 4 to alias with cog 0. But `pb_caller` is a BYTE storing COGID (0-7), and the array is `LONG 0[8]`. No masking, truncation, or arithmetic could cause aliasing. Two cogs with different COGIDs is a complete proof.

### D3: O-20 subsumes O-17 — drop the assertion quality audit as a separate activity

**Decision**: O-17 (assertion quality audit from Tier 3) is folded into O-20's mutation testing. No separate audit pass.

**Rationale**: O-17 was "review assertions for overly wide ranges and tautological checks." Mutation testing achieves this more rigorously and with less subjectivity. A manual audit depends on the reviewer's judgment about whether `evaluateRange(result, msg, 0, 100)` is "too wide." Mutation testing answers the question empirically: if we change the return value from 50 to 99, does the test still pass? If yes, the range is too wide — and we have proof rather than opinion.

The audit approach also scales poorly — 427 tests with 300+ sub-assertions is a lot of manual review. Mutation testing targets the code paths that matter (the 14 mutations in the catalog) and only flags assertions that actually fail to catch realistic bugs.

**Caveat**: Mutation testing only checks assertions on the path of each mutation. Completely untested code paths with no mutation targeting them won't be found. But the coverage analysis (Section 4) already identified untested paths, so that concern is addressed separately.

### D4: Stress tests run on SP Elite daily, slow card at release only

**Decision**: Run the regression suite (including stress tests) on the SP Elite. Run stress tests on one additional slow card only during release qualification.

**Rationale**: Card-swapping is a manual physical operation that can't be automated. If stress tests require two cards, developers will skip them or only run on one. That defeats the purpose.

The SP Elite is the right daily driver: fast (minimizing test time), likely to be in the slot, and consistent timing makes results deterministic. A flaky slow card that occasionally times out would create false failures that erode trust in the suite.

For release qualification: pick one slower card from the 20-card catalog that has higher write latency — something that exercises timeout and busy-wait paths more aggressively. This is a manual, one-time step in the release checklist, not part of the automated suite.

The bugs these tests catch (data corruption, lock failures, cache coherence) are **not card-dependent** — they're driver logic bugs. Card-dependent bugs (timing, busy-wait thresholds) are better caught by the existing recovery_tests suite, which uses CRC fault injection to simulate card misbehavior without needing a specific physical card.
