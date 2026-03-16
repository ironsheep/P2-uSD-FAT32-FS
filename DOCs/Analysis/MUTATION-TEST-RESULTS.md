# Mutation Test Results — Pass 1 (Categories A-C)

**Date**: 2026-03-16
**Baseline**: v1.3.2 + O-18 cogcwd_tests + O-19 stress_tests (22 suites, 390 tests)
**Driver**: `src/micro_sd_fat32_fs.spin2` (unmodified v1.3.2)

---

## Results Matrix

| Mutation | Category | Description | Location (line) | Test(s) Run | Result | Failures |
|----------|----------|-------------|-----------------|-------------|--------|----------|
| M-B1 | B: Wrong Value | Write `h_size + 1` on close | do_close_h:3120 | read_write_tests | **Killed** | 17/48 |
| M-B2 | B: Wrong Value | Skip dirty buffer flush on close | do_close_h:3107 | read_write_tests | **Killed** | 9/48 |
| M-B3 | B: Wrong Value | Index `cog_dir_sec[pb_caller+1]` | do_chdir:3775,3779 | cogcwd_tests | **Killed** | 1/5 |
| M-B4 | B: Wrong Value | Return `bytes_read - 1` | do_read_h:3227 | read_write_tests | **Killed** | 14/48 |
| M-A1 | A: Off-by-One | Sector-full check `== 1` instead of `== 0` | do_write_h:3323 | read_write_tests | **Killed** | 9/48 |
| M-A2 | A: Off-by-One | Clamp to `available - 1` | do_read_h:3157 | read_write_tests | **Killed** | 17/48 |
| M-A3 | A: Off-by-One | FAT scan starts at cluster 3 | allocateCluster:4349 | volume_tests, read_write_tests | **Equivalent** | — |
| M-A4 | A: Off-by-One | Seek clamp `> (size - 1)` | do_seek_h:3365 | seek_tests | **Killed** | 2/37 |
| M-C1 | C: Error Path | validateHandle always TRUE | validateHandle:2440 | error_handling_tests | **Killed** | 1/14 |
| M-C2 | C: Error Path | Skip single-writer enforcement | do_open_write:2971 | multihandle_tests | **Killed** | 3/21 |
| M-C3 | C: Error Path | Return handle 0 instead of E_FILE_NOT_FOUND | do_open_read:2922 | error_handling_tests, file_ops_tests | **Killed** | 3/26 (file_ops) |
| M-C4 | C: Error Path | Skip directory entry update in sync | do_sync_h:3442 | volume_tests | **Killed** | 1/28 (after fix) |

---

## Summary

- **Tested**: 12 mutations (4 per category)
- **Killed**: 11 (including M-C4 after strengthening)
- **Equivalent**: 1 (M-A3 — cannot produce different behavior)
- **Kill rate**: 100% of non-equivalent mutations

---

## Survivor Resolutions

### M-A3: allocateCluster starts at cluster 3 — EQUIVALENT MUTATION

**Classification**: Equivalent mutation (produces identical observable behavior).

**Analysis**: On FAT32, cluster 2 is always the root directory cluster. It is allocated at format time and never freed during normal filesystem operations. The `allocateCluster` scan searches for free clusters — cluster 2 is never free, so whether the scan starts at cluster 2 (fat_idx=8) or cluster 3 (fat_idx=12), the first free cluster found is always cluster 3 or higher. No test can distinguish between the original and mutated code because they produce identical allocation sequences on any valid FAT32 volume.

**Action**: None needed. Documented as equivalent mutation. The code is correct as written (starting at cluster 2 is the principled choice), but no test gap exists.

### M-C4: do_sync_h skips directory entry update — NOW KILLED

**Original gap**: All sync tests called `syncAllHandles()` then immediately closed the handle. `do_close_h` has its own independent directory entry write, masking the sync mutation.

**Fix applied**: Added test "syncAllHandles() persists dir entry to disk" to `SD_RT_volume_tests.spin2`. The test writes data, calls `syncAllHandles()`, then opens the same file with a **second read handle** and checks `fileSizeHandle()` on the second handle — all without closing the write handle first. Since the second handle's size comes from the on-disk directory entry (read at open time), skipping the sync directory write causes the second handle to see size 0 instead of the written size.

**Result after fix**: M-C4 now killed (1 failure in 28 tests). Volume test count increased from 27 to 28.

---

## Pass 2 (Category D — Concurrency)

Deferred to Phase 4, Step 8. Category D mutations (M-D1 through M-D3) require the full feature set to be complete.
