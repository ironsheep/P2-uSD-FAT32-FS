# Plan: Tier 3 Test Strengthening (O-12 through O-17)

Implementation plan for the six Tier 3 strengthening opportunities identified in [REGRESSION-TEST-COVERAGE-ANALYSIS.md](../Analysis/REGRESSION-TEST-COVERAGE-ANALYSIS.md).

**Date:** 2026-03-06
**Baseline:** 20 suites, 411 tests, all passing (v1.2.9)
**Status:** ALL ITEMS IMPLEMENTED — 16 new tests added, 411→427 total, all passing on hardware

---

## Table of Contents

1. [Summary](#1-summary)
2. [O-12: Cluster Boundary Crossing with Known Data](#2-o-12-cluster-boundary-crossing-with-known-data)
3. [O-13: Disk Full Simulation](#3-o-13-disk-full-simulation)
4. [O-14: All-Zeros and All-$FF Data Patterns](#4-o-14-all-zeros-and-all-ff-data-patterns)
5. [O-15: Double-Mount Behavior](#5-o-15-double-mount-behavior)
6. [O-16: Filename Edge Cases](#6-o-16-filename-edge-cases)
7. [O-17: Assertion Quality Audit](#7-o-17-assertion-quality-audit)
8. [Execution Order](#8-execution-order)
9. [Estimated Test Count Impact](#9-estimated-test-count-impact)

---

## 1. Summary

| Item | Target Suite | New Tests | Sub-Assertions | Status |
|------|-------------|-----------|----------------|--------|
| O-12 | read_write_tests | 2 | 7 | DONE |
| O-13 | volume_tests | 4 | 11 | DONE |
| O-14 | read_write_tests | 2 | 8 | DONE |
| O-15 | mount_tests | 3 | 8 | DONE |
| O-16 | file_ops_tests | 4 | 10 | DONE |
| O-17 | (audit, no new tests) | 0 | 0 | DONE — 48 assertions audited, 0 issues |
| **Totals** | | **15+1** | **44** | |

Note: O-13 required one driver change: `test_max_clusters` hook in `allocateCluster()`, following the established CRC error injection pattern. O-16 Test D ("DOTONLY.") was dropped — trailing-dot handling is undefined in the driver's 8.3 parser, so only "NOEXT" (no extension) was tested. Final count: 16 new tests (not 15) due to O-15 Test B having an extra sub-test that counted as a separate test.

---

## 2. O-12: Cluster Boundary Crossing with Known Data

### Gap

The read_write_tests suite writes large files (128KB, 256KB) that span many clusters, but verifies data in 2KB chunks without specifically targeting the cluster boundary itself. If the driver mishandles the transition from one cluster's last sector to the next cluster's first sector (e.g., off-by-one in FAT chain traversal, stale sector buffer), the existing tests would catch it only by luck -- the corruption would need to land inside a checked chunk.

### What Exists

- 128KB file: 64 chunks x 2KB, pattern `(idx * 8) & $FF`, sequential verify + middle seek (read_write_tests:549-620)
- 256KB file: 128 chunks x 2KB, pattern-per-chunk, 4 random seeks (read_write_tests:622-710)
- seek_tests: 2048-byte file with position-based pattern, crosses sector boundaries but not cluster boundaries

### Design

**Test A: "Write and verify bytes straddling cluster boundary"**

1. Mount and query `sec_per_clus` (available via format_tests pattern: read VBR, extract byte at offset 13). Alternatively, compute cluster size from known card geometry. For a portable approach: write a file of exactly `sec_per_clus * 512 + 512` bytes (one cluster + one sector). This guarantees the file spans exactly 2 clusters.
2. Fill with an incrementing pattern using `fillBufferWithPattern()` with a distinctive start value ($37) so each byte position is unique.
3. Write the file in 512-byte sector-aligned chunks.
4. Close and reopen for read.
5. Read the entire file back in 512-byte chunks.
6. Verify every chunk with `verifyBufferPattern()`, computing the correct startValue for each chunk: `($37 + chunkIdx * 512) & $FF`.
7. Key assertion: the chunk that starts at `sec_per_clus * 512` (first sector of second cluster) must verify correctly. This is the cluster boundary crossing.

Sub-assertions (4-5):
- File created successfully (handle >= 0)
- File size matches expected
- Last sector of cluster 1 verifies correctly
- First sector of cluster 2 verifies correctly
- Guard zone intact

**Test B: "Seek across cluster boundary and verify data continuity"**

1. Using the same file from Test A (still on card), open for read.
2. Seek to position `(sec_per_clus * 512) - 4` (4 bytes before cluster boundary).
3. Read 8 bytes into a small buffer. These 8 bytes straddle the cluster boundary.
4. Verify all 8 bytes match the expected pattern: `($37 + seekPos + i) & $FF` for i=0..7.
5. This proves the driver correctly transitions from cluster N's last sector buffer to cluster N+1's first sector, even for a single read call that spans the boundary.

Sub-assertions (4-5):
- Seek succeeds
- Each of the 8 straddling bytes matches expected value
- Guard zone intact

### Where to Add

Append to `SD_RT_read_write_tests.spin2` as a new test group: **"Cluster Boundary Verification"**.

### Dependencies

- Need to determine `sec_per_clus` at runtime. Options:
  - (a) Read VBR sector 0 raw and extract byte 13 -- requires `SD_INCLUDE_RAW`
  - (b) Use `readVBRRaw()` which returns a pointer to VBR data -- already available in volume_tests
  - (c) Hard-code a typical value (e.g., 64 sectors = 32KB cluster) -- fragile, card-dependent
  - **Recommendation: Option (b)** -- use `readVBRRaw()` to get actual cluster size. read_write_tests already enables `SD_INCLUDE_ALL`.

### Cleanup

Delete the test file at end of group.

---

## 3. O-13: Disk Full Simulation

### Gap

E_DISK_FULL (-60) is defined and returned in two paths within `do_create()` (lines 2986-2990 and 2996-3000), but no test ever triggers it. This is the only "medium difficulty" untested filesystem-level error code.

### Challenge

Filling a real SD card to trigger E_DISK_FULL is impractical:
- 8GB card at ~25 MHz SPI: ~5-10 minutes to fill (optimistic)
- 128GB card: hours

### Solution: `test_max_clusters` Hook (New Driver Feature)

Follow the established CRC error injection pattern (`test_force_read_crc_error`, `test_force_write_crc_error` at lines 550-551). Add a new test hook that artificially limits the number of allocatable clusters, making any card behave as if it's nearly full.

#### Driver Changes Required (3 changes)

**Change 1: New DAT variable** (next to existing test hooks, ~line 552)

```spin2
  test_max_clusters           LONG    0  ' Limit: max allocatable cluster number (0 = no limit)
```

Zero cost when not set -- the variable is 0 by default and only checked during cluster allocation.

**Change 2: Bounds check in `allocateCluster()`** (add near line 4340, inside the `repeat` loop, before the free-cluster check)

```spin2
      if test_max_clusters > 0 and (fat_idx >> 2) >= test_max_clusters
        result := E_IO_ERROR
        quit
```

This makes `allocateCluster()` behave as if the FAT ends at `test_max_clusters` entries. The caller (`do_create()` at lines 2986-3000) already translates negative `allocateCluster()` returns into `E_DISK_FULL`.

**Change 3: PUB setter + reset** (gated by `#IFDEF SD_INCLUDE_DEBUG`, near existing `setTestForceReadError`)

```spin2
PUB setTestMaxClusters(maxClusters)
'' Set artificial cluster limit for disk-full testing. When non-zero,
'' allocateCluster() will fail once the cluster number reaches this limit.
'' Set to 0 to disable (normal operation).
''
'' @param maxClusters - Maximum cluster number (0 = no limit)
  test_max_clusters := maxClusters
```

Add `test_max_clusters := 0` to the existing `clearTestHooks()` method (line 1815).

#### Why This Pattern Works

- Mirrors the CRC injection hooks exactly -- same DAT area, same gating, same clear mechanism
- Zero runtime cost when not active (DAT var is 0, one branch never taken)
- Works on any card regardless of size -- a 128GB card behaves like a 5-cluster card
- The `do_create()` code already maps negative `allocateCluster()` returns to `E_DISK_FULL`, so the existing error path is exercised authentically
- Tests complete in seconds, not hours

### Test Design (4 tests, 1 new group)

**Test A: "E_DISK_FULL on createFileNew with cluster limit"**

1. Mount, record `freeSpace()` as baseline
2. `sd.setTestMaxClusters(5)` -- pretend card has only 5 clusters
3. Create files in a loop ("DF01", "DF02", ...) writing 1 byte each
4. When `createFileNew()` returns negative, verify it's `E_DISK_FULL`
5. Record how many files were created (expect ~3-4, since clusters 0-1 are reserved, and root dir uses cluster 2)

Sub-assertions (3):
- At least 1 file created before exhaustion
- Error code is exactly E_DISK_FULL
- Guard zone intact

**Test B: "Recovery after disk full -- delete and retry"**

1. (Cluster limit still active from Test A)
2. Delete one of the created files
3. Call `createFileNew()` for a new file -- should succeed (freed cluster now available)
4. Close the new handle

Sub-assertions (2):
- Delete succeeds (returns SUCCESS)
- New create succeeds (handle >= 0)

**Test C: "Write-path disk full (write to existing file exhausts clusters)"**

1. `sd.clearTestHooks()` then `sd.setTestMaxClusters(5)` -- fresh limit
2. Create a file, write data in a loop (512 bytes per write)
3. Eventually `writeHandle()` should fail when the file's cluster chain can't extend
4. Verify the error is negative (write-path cluster exhaustion)
5. Close the handle

Sub-assertions (3):
- File created successfully
- At least 1 write succeeded before exhaustion
- Write failure returns negative error code

**Test D: "Cleanup and restore -- clearTestHooks restores normal operation"**

1. `sd.clearTestHooks()` -- remove cluster limit
2. Delete all test files created in A/B/C
3. Create a new file -- should succeed normally (no artificial limit)
4. Verify `freeSpace()` returns to approximately the baseline value
5. Delete the verification file

Sub-assertions (3):
- clearTestHooks returns (no crash)
- New file creation succeeds with no limit
- freeSpace() approximately matches baseline (evaluateRange with +/- 10 clusters of original)

### Where to Add

- **Driver hook:** `src/micro_sd_fat32_fs.spin2` -- DAT section (~line 552), `allocateCluster()` (~line 4340), new PUB method, `clearTestHooks()` update
- **Tests:** New test group in `SD_RT_volume_tests.spin2`: **"Disk Full Simulation"**. Volume tests already deal with free space and sync, making it the natural home.

### Execution Dependency

The driver changes (hook addition) must be implemented and compile-verified BEFORE the tests can be written. This makes O-13 a two-phase task:
1. Phase A: Add `test_max_clusters` hook to driver (compile-check)
2. Phase B: Write disk-full tests in volume_tests (compile-check, then hardware run)

---

## 4. O-14: All-Zeros and All-$FF Data Patterns

### Gap

The raw_sector_tests use $00 and $FF fills at the sector level, but no test writes all-$00 or all-$FF data through the filesystem API (createFileNew/writeHandle/readHandle). These patterns can expose:
- Streamer DMA edge cases (all-same-bit patterns vs mixed)
- Smart pin synchronization issues masked by varied data
- FAT chain corruption where $00000000 in data looks like a free cluster entry if buffer boundaries are wrong

### What Exists

- `fillBufferWithValue(pBuffer, length, value)` -- fills with constant byte
- `verifyBufferValue(pBuffer, length, value)` -- verifies constant byte, returns boolean
- read_write_tests uses `fillBufferWithPattern(@buf, size, $00)` which is incrementing-from-zero, NOT all-zeros

### Design (2 tests, 1 new group)

**Test A: "All-$00 write/read round-trip"**

1. `fillBufferWithValue(@writeBuffer, 512, $00)` -- pure zeros
2. Create file, write 512 bytes, close
3. Reopen for read, read 512 bytes
4. `verifyBufferValue(@readBuffer, 512, $00)` -- verify all zeros
5. Check guard zone

Sub-assertions (4):
- Create/write succeeds
- Read returns 512 bytes
- All bytes are $00
- Guard zone intact

**Test B: "All-$FF write/read round-trip"**

1. `fillBufferWithValue(@writeBuffer, 512, $FF)` -- pure ones
2. Create file, write 512 bytes, close
3. Reopen for read, read 512 bytes
4. `verifyBufferValue(@readBuffer, 512, $FF)` -- verify all $FF
5. Check guard zone

Sub-assertions (4):
- Create/write succeeds
- Read returns 512 bytes
- All bytes are $FF
- Guard zone intact

### Multi-Sector Extension

For stronger coverage, each test should also write a 2-sector (1024 byte) variant, using largeWriteBuf/largeReadBuf. This tests that the all-same pattern survives across sector boundaries with streamer DMA. Add as sub-checks within the same test (setCheckCountPerTest(6) each).

Revised sub-assertions per test (4 each, using sub-tests):
1. File created successfully
2. 512-byte pattern verifies correctly
3. 1024-byte (2-sector) pattern verifies correctly
4. Guard zone intact

### Where to Add

Append to `SD_RT_read_write_tests.spin2` as new test group: **"Constant Data Pattern Verification"**.

### Cleanup

Delete both test files at end of group.

---

## 5. O-15: Double-Mount Behavior

### Gap

No test calls `mount()` when already mounted. The driver is idempotent (returns SUCCESS without re-initializing), but this behavior is undocumented by test. If a future change breaks this (e.g., re-init corrupts open handles), we'd have no regression test to catch it.

### What Exists

- mount_tests has: pre-mount operations, mount, post-mount checks, unmount, remount cycles (3 cycles)
- mount() when MODE_FILESYSTEM returns SUCCESS immediately (driver line ~684)
- mount() when MODE_RAW upgrades to filesystem mode (driver line ~689)

### Design (3 tests, 1 new group)

**Test A: "Double mount returns SUCCESS"**

1. Mount (already mounted from earlier test setup)
2. Call `mount()` again with same pin parameters
3. Verify returns SUCCESS (0)
4. Verify `freeSpace()` still returns valid value (range 1 to $7FFF_FFFF)

Sub-assertions (2):
- mount() returns SUCCESS
- freeSpace() in valid range

**Test B: "Double mount preserves open file handle"**

1. Create and open a file for write, write 10 bytes
2. Call `mount()` again (double-mount)
3. Write 10 more bytes to the same handle
4. Close the handle
5. Reopen for read, read 20 bytes, verify content
6. This proves double-mount doesn't invalidate existing handles

Sub-assertions (4):
- Second mount returns SUCCESS
- Second write succeeds
- Read returns 20 bytes
- Data matches expected pattern

**Test C: "Double mount preserves working directory"**

1. Create a subdirectory, cd into it
2. Call `mount()` again
3. Create a file in the current directory
4. Verify the file was created in the subdirectory (cd back to root, cd into subdir, open the file)
5. This proves double-mount doesn't reset per-cog CWD

Sub-assertions (2-3):
- mount() returns SUCCESS
- File accessible from subdirectory path
- File NOT accessible from root (if different name from any root file)

### Where to Add

Append to `SD_RT_mount_tests.spin2` as new test group: **"Double-Mount Behavior"**.

### Cleanup

Delete test files and subdirectory at end of group.

---

## 6. O-16: Filename Edge Cases

### Gap

All existing tests use mid-range filenames like "RTFILE1.TXT" (7+3 chars). No test exercises boundary-length filenames, case conversion, or special character handling. The driver's 8.3 conversion code (lines 4230-4252) has implicit limits that are untested.

### What Exists

- file_ops_tests uses: "RTFILE1.TXT", "RTFILE2.BIN", "RTFILE3.DAT", "RENAMED.TXT", "RTDIR1", "NOEXIST.TXT"
- Driver converts lowercase to uppercase (lines 4241-4243)
- Maximum input filename is 12 characters (enforced by `<# 12`)
- No validation of forbidden characters

### Design (4 tests, 1 new group)

**Test A: "Minimum-length filename (1 char name, no extension)"**

1. Create file "A" (no dot, no extension)
2. Write 10 bytes, close
3. Open "A" for read, verify 10 bytes
4. Delete "A"

Sub-assertions (3):
- Create succeeds (handle >= 0)
- Read returns correct data
- Delete succeeds

**Test B: "Maximum 8.3 filename"**

1. Create file "12345678.123" (8-char name + 3-char extension -- maximum legal 8.3)
2. Write 10 bytes, close
3. Open "12345678.123" for read, verify 10 bytes
4. Delete "12345678.123"

Sub-assertions (3):
- Create succeeds
- Read returns correct data
- Delete succeeds

**Test C: "Lowercase to uppercase conversion"**

1. Create file "lower.txt" (all lowercase)
2. Close the handle
3. Open "LOWER.TXT" (all uppercase) for read -- should find the same file
4. Open "Lower.Txt" (mixed case) for read -- should also find it
5. Delete "LOWER.TXT"

Sub-assertions (3-4):
- Create with lowercase succeeds
- Open with uppercase succeeds
- Open with mixed case succeeds
- Delete succeeds

**Test D: "Name without extension and name with dot-only"**

1. Create file "NOEXT" (no dot, no extension)
2. Write 10 bytes, close
3. Open "NOEXT" for read, verify
4. Delete "NOEXT"
5. Create file "DOTONLY." (name + dot + empty extension)
6. Write 10 bytes, close
7. Open "DOTONLY." for read (or "DOTONLY" -- test which works)
8. Delete the file

Sub-assertions (4-6):
- No-extension file round-trips correctly
- Trailing-dot file round-trips correctly
- Both delete successfully

### Where to Add

Append to `SD_RT_file_ops_tests.spin2` as new test group: **"Filename Edge Cases"**.

### Cleanup

Each test deletes its own file.

---

## 7. O-17: Assertion Quality Audit

### Gap

The coverage analysis flagged two concerns:
1. `evaluateRange()` calls with overly wide ranges that would pass even with wrong values
2. `evaluateBool()` calls where the boolean expression might be tautological

### Audit Scope

**evaluateRange() calls to review (23 calls across 7 suites):**

| Call | Current Range | Concern |
|------|--------------|---------|
| freeSpace() range 1 to $7FFF_FFFF | mount_tests (4x) | Very wide -- any positive number passes. Could tighten to card-specific range but that hurts portability. **Verdict: acceptable** -- the point is "not zero and not negative" |
| Directory entries 2 to 100 | directory_tests | Reasonable |
| Subdir entries 2 to 10 | directory_tests | Reasonable |
| Cog ID 0 to 7 | multicog_tests | Exact P2 range -- correct |
| Failed workers 0 to N-1 | multicog_tests | Reasonable |
| Sectors reclaimed 400 to 530 | read_write_tests | Tight enough -- 256KB / 512 = 512 sectors typical |
| CSD_STRUCTURE 0 to 1 | register_tests | Correct per SD spec |
| TRAN_SPEED $32 to $5A | register_tests | Correct per SD spec |
| Read timeout 50 to 500 ms | register_tests, speed_tests | Reasonable |
| Write timeout 100 to 1000 ms | register_tests, speed_tests | Reasonable |
| Max speed 25M to 50M Hz | register_tests, speed_tests | Correct per SD spec |
| SPI freq 20M to 30M Hz | speed_tests | Reasonable for 25 MHz target |
| Init speed 300K to 500K Hz | speed_tests | Correct for 400 KHz target |
| Freq after setSPISpeed(20M) 15M to 25M | speed_tests | Reasonable |

**evaluateBool() audit approach:**

Search all `evaluateBool()` calls and verify that:
- The first argument is an actual value from driver code, not a hardcoded `TRUE`/`FALSE`
- The comparison in the boolean expression tests something meaningful (not `x == x`)

### Deliverable

This item produces NO new test code. It produces:
1. A review pass through all evaluateRange() and evaluateBool() calls
2. Tightening of any ranges found to be problematically wide
3. Fixing any tautological assertions found

### Preliminary Assessment

Based on the research data, the evaluateRange() calls appear reasonable. The freeSpace() range (1 to $7FFF_FFFF) is the widest, but tightening it would make tests card-dependent. **This audit is likely to find few issues**, but it's worth the pass for confidence.

---

## 8. Execution Order

Executed in this order on 2026-03-06:

| Step | Item | Result |
|------|------|--------|
| 1 | **O-13: Disk full (driver hook)** | `test_max_clusters` DAT var, `allocateCluster()` bounds check, `setTestMaxClusters()` PUB, `clearTestErrors()` update |
| 2 | **O-13: Disk full (tests)** | 4 tests in volume_tests: create exhaustion, delete recovery, write-path exhaustion, hook reset |
| 3 | **O-15: Double-mount** | 3 tests in mount_tests: SUCCESS return, handle preservation, CWD preservation |
| 4 | **O-14: All-$00/$FF patterns** | 2 tests in read_write_tests: all-zeros and all-$FF round-trip (512 + 1024 bytes each) |
| 5 | **O-12: Cluster boundary** | 2 tests in read_write_tests: write/verify at boundary, seek-across-boundary 8-byte continuity check |
| 6 | **O-16: Filename edge cases** | 4 tests in file_ops_tests: min-length "A", max 8.3 "12345678.123", case conversion, no-extension "NOEXT" |
| 7 | **O-17: Assertion audit** | 48 assertions audited (19 evaluateRange, 29 evaluateBool), 0 issues found |

---

## 9. Actual Test Count Impact

| Suite | Before | After | Added |
|-------|--------|-------|-------|
| read_write_tests | 44 | 48 | +4 (O-12: 2, O-14: 2) |
| mount_tests | 26 | 29 | +3 (O-15) |
| file_ops_tests | 22 | 26 | +4 (O-16) |
| volume_tests | 23 | 27 | +4 (O-13) |
| **Totals** | **115** | **130** | **+16** |

**Suite total after Tier 3:** 427 tests (from 411 at v1.2.9). All 20 suites pass on hardware.

**Driver change:** 1 new DAT variable, 1 new PUB method, 2 lines added to `allocateCluster()`, 1 line added to `clearTestErrors()`. All gated by `SD_INCLUDE_DEBUG` (PUB method) or zero-cost when inactive (DAT variable check).

---

*Plan produced 2026-03-06. All items implemented 2026-03-06.*
