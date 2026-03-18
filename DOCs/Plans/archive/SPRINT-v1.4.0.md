# Sprint Plan: v1.4.0

**Date**: 2026-03-15
**Baseline**: v1.3.2 (427 tests, 20 suites, all passing)

---

## Release Theme

v1.4.0 transforms the driver from a blocking-only filesystem into an embedded-ready platform: auto-protecting data against card removal, providing real timestamps on files, enabling caller cogs to overlap computation with SD I/O, and hardening the test suite with multi-cog isolation and stress tests.

---

## Features

| ID | Feature | Conditional Flag | New PUB Methods | New Tests |
|----|---------|-----------------|-----------------|-----------|
| F1 | Worker main loop restructure | Core (always) | 0 | 0 (existing tests validate) |
| F2 | Date/time timestamps | Core (always) | 1 new (getDate), setDate enhanced | ~6 |
| F3 | Auto-flush on idle | Core (always) | 0 | ~3 |
| F4 | Non-blocking file I/O | `SD_INCLUDE_ASYNC` | 5 | ~6 |
| F5 | Tier 4 regression tests | N/A (test-only) | 0 | ~9 |

---

## Dependency Graph

```
F5: Tier 4 Tests (FIRST — establish baseline before any driver changes)
 │
 ├── O-18: Per-cog CWD isolation (tests existing behavior)
 ├── O-19: Stress tests (tests existing behavior)
 └── O-20: Mutation testing pass 1 (Categories A-C against v1.3.2 baseline)

Then:

F1: Worker Main Loop Restructure
 │
 ├──► F2: Date/Time Timestamps (needs POLLCT1 in loop)
 │
 ├──► F3: Auto-Flush on Idle (needs idle detection in loop)
 │
 └──► F4: Non-Blocking I/O (caller-side only, no loop changes)

Then:

O-20: Mutation testing pass 2 (Category D concurrency, plus any survivors from pass 1)
```

---

## Why Tests First

O-18 (per-cog CWD) and O-19 (concurrent read/write stress) test **existing driver behavior** that has **zero coverage today**. Running them before any driver changes serves two purposes:

1. **Find latent bugs now.** If there's a bug in per-cog CWD isolation or multi-cog data integrity, we want to discover it against the stable v1.3.2 baseline — not after restructuring the worker loop, when we can't tell whether the failure is old or new.

2. **Establish regression anchors.** Once O-18 and O-19 pass on v1.3.2, they become anchors for every subsequent step. Each feature (F1, F2, F3, F4) runs all 22 suites. If a worker loop change breaks multi-cog CWD isolation, we catch it on the step that caused it.

O-20 mutation testing splits naturally: Categories A-C (off-by-one, wrong-value, error-path) can run against the v1.3.2 codebase with O-18/O-19 in place. Category D (concurrency mutations) runs after all features are done, as the final validation.

---

## Phase 1: Test Hardening (against v1.3.2 baseline)

### Step 1: O-18 — Per-Cog CWD Isolation Tests

**New file**: `src/regression-tests/SD_RT_cogcwd_tests.spin2`
**Source plan**: PLAN-TIER4-REGRESSION-TESTS.md

5 tests verifying that `cog_dir_sec[pb_caller]` correctly isolates working directories across cogs:
- Two cogs in different directories see different files
- One cog's changeDirectory doesn't affect another cog's CWD
- Both cogs create files in their own CWD (cross-verified)
- CWD survives repeated file operations
- CWD isolation when one cog resets to root

**Timeout**: `-t 120`
**Validation**: All 5 new tests pass + all 20 existing suites still pass

### Step 2: O-19 — Concurrent Reader + Writer Stress Tests

**New file**: `src/regression-tests/SD_RT_stress_tests.spin2`
**Source plan**: PLAN-TIER4-REGRESSION-TESTS.md

4 tests verifying data integrity under sustained concurrent access:
- Reader integrity during concurrent writing (50 iterations, 500 sector reads)
- Writer integrity post-verification
- Both cogs reading same file simultaneously
- Rapid open/close cycles under contention

**Timeout**: `-t 120`
**Validation**: All 4 new tests pass + all 21 suites (including O-18) still pass

### Step 3: O-20 Pass 1 — Mutation Testing (Categories A-C)

**Deliverable**: `DOCs/Analysis/MUTATION-TEST-RESULTS.md` (initial)

10 mutations (Categories A-C: off-by-one, wrong-value, error-path). Each applied individually to the driver, tested against the relevant suites from the now-22-suite collection, documented as killed or survived. Any survivors get new or strengthened tests immediately.

**Validation**: All 10 mutations killed. Any new tests added pass on the unmodified driver.

After Step 3, we have **22 suites, all green, with mutation-verified coverage**. This is our hardened baseline for feature work.

---

## Cross-Cutting Requirement: Sister Driver Engineering Guides

Every feature that changes the driver source code (`micro_sd_fat32_fs.spin2`) requires a corresponding engineering guide in `DOCs/Plans/ext-agents/`. These guides enable a separate agent to apply the same changes to the dual FS driver (the sister project) without re-deriving the design decisions.

The existing guides in `ext-agents/` (DEBUG-MASK-CHANNELS-GUIDE.md, NCO-WRITE-FIX-ENGINEERING-GUIDE.md, etc.) establish the format: what changed, why, prerequisites, step-by-step instructions with exact code patterns, and validation criteria.

### Required Guides for v1.4.0

| Step | Feature | Guide Filename | Scope |
|------|---------|---------------|-------|
| Step 4 | F1: Worker loop restructure | `WORKER-LOOP-RESTRUCTURE-GUIDE.md` | Loop transformation pattern, new structure, placeholder slots for clock/flush |
| Step 5 | F2: Date/time timestamps | `DATETIME-TIMESTAMPS-GUIDE.md` | CT1 clock, tick_clock(), setDate changes, close/sync modification timestamp writes |
| Step 6 | F3: Auto-flush on idle | `AUTO-FLUSH-IDLE-GUIDE.md` | 200ms threshold, do_idle_flush(), idle_timer reset, FSInfo write, pb_cmd abort check |
| Step 7 | F4: Non-blocking I/O | `NONBLOCKING-IO-GUIDE.md` | SD_INCLUDE_ASYNC flag, 5 PUB methods, async_active/caller DAT vars, lock hold pattern |

Each guide is written **as part of its step** — not deferred to the end. The guide captures the implementation decisions while they're fresh. It should contain:

1. **What changed and why** — the problem being solved, with reference to the analysis/plan document
2. **Prerequisites** — compiler version, driver version directive, any DAT variables that must exist
3. **Exact code patterns** — the new methods, the loop modifications, the DAT declarations, the CON constants. Not pseudocode — actual Spin2 that the sister driver can adapt
4. **Where to make changes** — which methods are modified, what to search for, what the before/after looks like
5. **What NOT to do** — anti-patterns, things that look tempting but break (e.g., auto-lock-release for async read/write)
6. **Validation criteria** — which tests to run, what to check, expected behavior
7. **Adaptation notes** — differences the sister driver may have (different buffer structure, different handle system, etc.) and how to adjust

Phase 1 (test hardening) does not change the driver, so no ext-agents guides are needed for Steps 1-3. O-18 and O-19 are test files, not driver changes.

---

## Phase 2: Foundation

### Step 4: F1 — Worker Main Loop Restructure

The worker cog's main loop (line 2113-2115) transforms from a tight `pb_cmd` poll to a structured multi-concern loop:

**Current:**
```spin2
repeat
  repeat until (cur_cmd := pb_cmd) <> CMD_NONE
  ' dispatch...
```

**New:**
```spin2
repeat
  ' --- Clock tick (F2 — placeholder, no-op until F2) ---
  if ct_active and POLLCT1()
    tick_clock()
    ADDCT1(clkfreq * 2)

  ' --- Filesystem command (Priority 1) ---
  if (cur_cmd := pb_cmd) <> CMD_NONE
    dispatch_command(cur_cmd)
    pb_cmd := CMD_NONE
    COGATN(1 << pb_caller)
    idle_timer := getct()
    flush_done := false

  ' --- Auto-flush (F3 — placeholder, no-op until F3) ---
  elseif not flush_done
    if (getct() - idle_timer) >= idle_flush_clocks
      do_idle_flush()
```

**Estimated size**: ~20 lines changed
**Validation**: All 22 suites pass. The loop change is purely structural; external behavior is identical.
**Risk**: Low. Mechanical transformation: unwinding the inner `repeat until` into a single-level `repeat` with `if/elseif`.
**Ext-agent guide**: `DOCs/Plans/ext-agents/WORKER-LOOP-RESTRUCTURE-GUIDE.md` — documents the before/after loop structure, placeholder slots, and the rationale for each concern's position in the loop.

---

## Phase 3: Core Features (sequential, each builds on the loop)

### Step 5: F2 — Date/Time Timestamps

**Source plan**: PLAN-DATETIME-TIMESTAMPS.md (Approach A: CT1-based live clock)

**What Changes:**
1. **New DAT variables**: 6 FIELD pointer LONGs (`fld_yr` through `fld_sec`), `ct_active` (BYTE), `days_table` (12 BYTEs)
2. **FIELD-based packed increment**: `tick_clock()` uses Spin2 FIELD operator to increment directly within the packed `date_stamp` LONG — no separate unpacked variables, no repacking step
3. **`setDate()` enhanced**: Writes fields directly into `date_stamp` via FIELD, arms CT1
4. **`getDate()` new**: Reads fields from `date_stamp` via FIELD, returns 6 values (year, month, day, hour, minute, second) — symmetric with setDate
5. **New PRI methods**: `tick_clock()` (~20 lines), `daysInMonth()`, `isLeapYear()` (~15 lines)
6. **`POLLCT1()` in worker loop**: Handler body for the slot prepared by F1
7. **`do_close_h()` and `do_sync_h()`**: Write `date_stamp` to `DE_WRT_TIME_OFFSET` alongside `DE_FILESIZE_OFFSET`

**NOT gated by conditional compilation.** Timestamps are core filesystem behavior. Every FAT32 implementation should produce valid timestamps. The CT1 cost is negligible.

**New tests** (new `SD_RT_timestamp_tests.spin2`):

| Test | What It Verifies |
|------|-----------------|
| setDate produces correct creation timestamp | Create file after setDate, read dir entry, verify date/time fields match |
| Modification timestamp updated on close | Write file, close, read dir entry, verify WrtTime/WrtDate set |
| Timestamps advance over time | setDate, wait 4 seconds, create file, verify timestamp differs from one created at time 0 |
| Default timestamp without setDate | Mount without calling setDate, create file, verify valid (not garbage) date |
| getDate round-trip | setDate(2026,3,15,14,30,0), then getDate(), verify all 6 values match |
| getDate advances | setDate(), wait 4 seconds, getDate(), verify second has advanced |

**Resolved design decisions:**
- **FIELD operator**: Increment directly in packed `date_stamp` — eliminates separate unpacked variables, no repack step, one representation always consistent
- **POLLCT1 over ISR**: 2-second granularity makes late-fire skew invisible; ISR adds complexity for no practical benefit
- **CrtTimeTenth**: Set to 0. Spec-compliant, low value for embedded use.
- **setDate validation**: No range validation — caller's responsibility, matches current behavior.
- **DIR_LstAccDate**: Not implemented. Per-close I/O cost not justified.

**Estimated size**: ~62 new lines, 37 bytes DAT
**Validation**: 6 new tests pass + all 22 existing suites pass
**Risk**: Low. Straightforward rollover logic. CT1 "late fire" during long SD operations causes a few seconds of skew that self-corrects.
**Ext-agent guide**: `DOCs/Plans/ext-agents/DATETIME-TIMESTAMPS-GUIDE.md` — FIELD pointer setup, tick_clock() in-place increment, setDate()/getDate() symmetric API, close/sync modification timestamp writes.

### Step 6: F3 — Card Removal Data Integrity (Auto-Flush on Idle)

**Source analysis**: CARD-REMOVAL-DATA-INTEGRITY-ANALYSIS.md

**What Changes:**
1. **New DAT variables**: `idle_timer` (LONG), `idle_flush_clocks` (LONG), `flush_done` (BYTE)
2. **Worker loop addition**: Reset `idle_timer` after each command. In the idle branch, check elapsed time and flush if 200ms threshold reached.
3. **New PRI method**: `do_idle_flush()` — scans `h_flags[]` for `HF_DIRTY` handles, calls `do_sync_h()` on each, then `updateFSInfo()` if stale. Checks `pb_cmd` between each handle sync to abort if a command arrives.
4. **`idle_flush_clocks` initialization**: Set in `do_mount()` to `clkfreq / 1000 * IDLE_FLUSH_MS`

**NOT gated by conditional compilation.** Data protection is not optional. Zero cost during active I/O. Negligible cost during idle.

**The 200ms threshold**: Long enough that a 10 Hz logger never triggers mid-burst, short enough that a developer reaching for the card (1-2 second human action) finds data already flushed. See CARD-REMOVAL-DATA-INTEGRITY-ANALYSIS.md for the full threshold analysis.

```spin2
CON
  IDLE_FLUSH_MS = 200

DAT
  idle_flush_clocks LONG  0     ' Set at mount time: clkfreq / 1000 * IDLE_FLUSH_MS
  idle_timer        LONG  0     ' getct() at last command completion
  flush_done        BYTE  false ' true after idle flush completes (reset on next command)
```

**Auto-flush includes FSInfo write.** Per the card removal analysis recommendation R3: after flushing all dirty handles, also write the FSInfo sector if the free cluster count has changed. This eliminates the "pull card before unmount shows wrong free space" issue at zero additional cost.

**New tests** (added to `SD_RT_volume_tests.spin2` — flush is a volume-level concern):

| Test | What It Verifies |
|------|-----------------|
| Auto-flush writes dirty handle after idle period | Write data, don't close, wait 300ms, unmount cleanly, remount, verify file size and data |
| Auto-flush updates directory entry | Write data, wait 300ms (no close), read dir entry from a second handle, verify size reflects writes |
| Auto-flush does not interfere with active I/O | Write in a tight loop (no >200ms gap), verify no unexpected sync mid-burst (performance not degraded) |

**Estimated size**: ~40 new lines, 13 bytes DAT
**Validation**: 3 new tests pass + all 23 suites pass
**Risk**: Medium. Key correctness requirement: `do_idle_flush()` checks `pb_cmd` between handle syncs to avoid adding latency to real operations.
**Ext-agent guide**: `DOCs/Plans/ext-agents/AUTO-FLUSH-IDLE-GUIDE.md` — 200ms threshold rationale, do_idle_flush() with pb_cmd abort check, FSInfo write, idle_timer reset pattern.

### Step 7: F4 — Non-Blocking File I/O

**Source plan**: PLAN-NONBLOCKING-FILE-IO.md

**What Changes:**
1. **New conditional flag**: `SD_INCLUDE_ASYNC`
2. **New CON**: `PENDING = 1`
3. **New DAT variables**: `async_active` (BYTE), `async_caller` (BYTE)
4. **5 new PUB methods**: `startReadHandle()`, `startWriteHandle()`, `isComplete()`, `getResult()`, `cancelAsync()`
5. **New error codes**: `E_ASYNC_BUSY = -95`, `E_NO_ASYNC_OP = -96`

**Gated by `SD_INCLUDE_ASYNC`.** The async API adds 5 PUB methods, 2 error codes, and a new usage pattern. Applications that don't need it shouldn't carry the API surface.

**Worker side: No changes.** The worker doesn't know or care whether the caller is blocking or async. It processes the command identically. The `COGATN(1 << pb_caller)` on completion is harmlessly ignored by an async caller that isn't in WAITATN.

**New tests** (new `SD_RT_async_tests.spin2`):

| Test | What It Verifies |
|------|-----------------|
| Async read matches blocking read | Write known data, startReadHandle + getResult, compare with blocking readHandle |
| Async write verified by blocking read | startWriteHandle known data + getResult, then blocking readHandle to verify |
| isComplete returns FALSE then TRUE | startReadHandle, immediately check isComplete (expect FALSE), poll until TRUE, getResult |
| cancelAsync releases lock | startReadHandle, cancelAsync, then blocking readHandle succeeds (lock was released) |
| Async + blocking interleave | Async read from cog A, blocking read from cog B (B blocks on lock until A calls getResult) |
| E_ASYNC_BUSY on double start | startReadHandle, then startWriteHandle without getResult — second should return E_ASYNC_BUSY |

**Estimated size**: ~80 new lines (5 PUB + 2 CON + 2 DAT)
**Validation**: 6 new async tests pass + all 23 suites pass (both with and without `SD_INCLUDE_ASYNC`)
**Risk**: Medium. Core mechanism is simple (skip WAITATN, hold lock, poll pb_cmd). Interaction with auto-flush: if an async op is in flight, the worker is busy, idle timer doesn't advance, auto-flush doesn't fire — no conflict.
**Ext-agent guide**: `DOCs/Plans/ext-agents/NONBLOCKING-IO-GUIDE.md` — SD_INCLUDE_ASYNC flag setup, 5 PUB methods with exact signatures, lock-hold pattern, why auto-lock-release doesn't work for read/write, worker-side "no changes needed" rationale.

---

## Phase 4: Final Validation and Release

### Step 8: O-20 Pass 2 — Mutation Testing (Category D + Survivors)

4 concurrency mutations (Category D) plus any survivors from Pass 1 that now have new tests to recheck. Category D mutations specifically benefit from the O-18 and O-19 suites being in place and the full feature set being complete.

**Deliverable**: Final `DOCs/Analysis/MUTATION-TEST-RESULTS.md`
**Validation**: All 14 mutations killed across both passes.

### Step 9: Release Preparation

- Update CHANGELOG.md
- Update version in driver header
- Update README.md feature list
- Update CONDITIONAL-COMPILATION-GUIDE.md with `SD_INCLUDE_ASYNC`
- Update REGRESSION-TEST-COVERAGE-ANALYSIS.md with Tier 4 status
- Update regression-tests/README.md and THEORY-OF-OPERATIONS.md
- Run `run_regression.sh` (all 24 suites)
- Run `run_regression.sh` with `SD_INCLUDE_ASYNC` enabled
- Tag v1.4.0

---

## Implementation Timeline

```
Phase 1 — Test Hardening (against v1.3.2, no driver changes):
  Step 1: O-18 (cogcwd tests) ──────────────────────────►
  Step 2: O-19 (stress tests) ──────────────────────────►
  Step 3: O-20 pass 1 (mutations A-C) ─────────────────►

Phase 2 — Foundation:
  Step 4: F1 (loop restructure) ────────────────────────►

Phase 3 — Core Features:
  Step 5: F2 (timestamps) ─────► Step 6: F3 (auto-flush) ─────► Step 7: F4 (async) ──►

Phase 4 — Final Validation:
  Step 8: O-20 pass 2 (mutations D + survivors) ───────►
  Step 9: Release prep + tag ──────────────────────────►
```

Each step runs the full suite before proceeding to the next. A failure at any step is investigated and fixed before moving forward.

---

## Post-v1.4.0 Suite Summary

| Metric | v1.3.2 | v1.4.0 |
|--------|--------|--------|
| Test suites | 20 | 24 (+cogcwd, +stress, +timestamp, +async) |
| Total tests | 427 | ~451 (+24) |
| Multi-cog suites | 1 | 3 (+cogcwd, +stress) |
| Conditional flags | 6 | 7 (+SD_INCLUDE_ASYNC) |
| Worker loop concerns | 1 (command poll) | 3 (command + clock tick + idle flush) |
| Data protection | Manual sync only | Auto-flush at 200ms idle |
| Timestamps | Static (set once) | Live auto-incrementing clock |
| Async I/O | None | startReadHandle, startWriteHandle |
| Mutation coverage | Unknown | 14 mutations cataloged, all killed |

---

## Resolved Design Decisions

### D1: Tests first, then features

O-18 and O-19 run against the v1.3.2 baseline before any driver changes. This establishes regression anchors and surfaces latent bugs against stable code. Every subsequent feature step runs all 22+ suites to catch regressions immediately.

### D2: Auto-flush is NOT behind a conditional flag

Auto-flush protects data by default. Requiring developers to opt in to data protection reverses the correct default. The cost is negligible (zero during active I/O, one flush cycle per quiet period). Embedded data is hard-won and irreplaceable.

### D3: Timestamps are NOT behind a conditional flag

Valid timestamps are core FAT32 behavior. A file created without a timestamp confuses users and tools on every other system that reads the card. The CT1 cost is one POLLCT1 check per loop iteration (2-9 cycles) and one tick_clock() call every 2 seconds.

### D4: Async I/O IS behind `SD_INCLUDE_ASYNC`

The async API adds 5 new PUB methods and a new usage pattern (two-phase start/poll/getResult). Applications that don't need it shouldn't carry the API surface. The blocking API remains the default.

### D5: Auto-flush includes FSInfo write

Per the card removal analysis recommendation R3: after flushing all dirty handles, also write the FSInfo sector if the free cluster count has changed. Eliminates the cosmetic "wrong free space" issue at zero additional cost.

### D6: Three new error codes

| Code | Value | Feature | Used By |
|------|-------|---------|---------|
| `E_INVALID_PARAM` | -94 | F2: Timestamps | `setDate()` range validation |
| `E_ASYNC_BUSY` | -95 | F4: Async I/O | `startReadHandle()`/`startWriteHandle()` when an async op is already active |
| `E_NO_ASYNC_OP` | -96 | F4: Async I/O | `getResult()` when no async op is pending |

These continue the handle-level error tier (-90 through -93) already in the driver.

### D7: New test suites vs. extending existing suites

- **Timestamp tests**: New suite `SD_RT_timestamp_tests.spin2` — distinct subsystem, specific setup requirements
- **Async tests**: New suite `SD_RT_async_tests.spin2` — requires `SD_INCLUDE_ASYNC` flag
- **Auto-flush tests**: Added to `SD_RT_volume_tests.spin2` — volume-level concern, fits with existing sync tests
- **CWD tests**: New suite `SD_RT_cogcwd_tests.spin2` — multi-cog infrastructure with dedicated stacks
- **Stress tests**: New suite `SD_RT_stress_tests.spin2` — long-running, separate timeout requirements
