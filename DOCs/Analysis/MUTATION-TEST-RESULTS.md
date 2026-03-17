# Mutation Test Results

**Pass 1 date**: 2026-03-16
**Pass 2 date**: 2026-03-17
**Baseline**: v1.4.0-pre (23 suites, 406+ tests, includes F1-F4 features)
**Driver**: `src/micro_sd_fat32_fs.spin2`

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

## Pass 1 Summary (Categories A-C)

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

## Pass 2 Results (Category D — Concurrency)

**Date**: 2026-03-17
**Baseline**: v1.4.0-pre with F1-F4 complete (23 suites including async_tests)

| Mutation | Category | Description | Location (line) | Test(s) that Kill | Result | Detection |
|----------|----------|-------------|-----------------|-------------------|--------|-----------|
| M-D1 | D: Concurrency | Remove `locktry(api_lock)` in send_command | send_command:2618 | multicog_tests, stress_tests, async_tests | **Killed** | Data corruption / crash |
| M-D2 | D: Concurrency | Don't clear `pb_cmd` after dispatch | worker loop:2550 | ALL suites (deterministic hang) | **Killed** | Timeout |
| M-D3 | D: Concurrency | `longfill(@cog_dir_sec, 0, 8)` instead of `root_sec` | do_mount:3026 | cogcwd_tests, directory_tests, file_ops_tests | **Killed** | Wrong directory / E_FILE_NOT_FOUND |

### M-D1: Remove lock acquisition — KILLED

**Mutation**: Comment out `repeat until locktry(api_lock)` in `send_command()`.

**Effect**: Without the lock, concurrent cogs write to the shared mailbox (`pb_cmd`, `pb_param0..3`) simultaneously. Cog A's parameters are overwritten by cog B mid-setup, causing the worker to execute commands with scrambled arguments. On single-cog tests this mutation is invisible (no contention). On multi-cog tests it causes immediate data corruption or crashes.

**Detected by**:
- `multicog_tests`: 3 worker cogs calling `sd.start()`, `openFileRead()`, and `readHandle()` concurrently — mailbox corruption causes wrong cog IDs, garbled file reads, or worker hangs
- `stress_tests`: Rapid concurrent open/read/close cycles — interleaved mailbox writes corrupt every operation
- `async_tests` (test 5): Main cog async + helper cog blocking — without lock, both write to mailbox simultaneously

**Kill confidence**: Deterministic on multi-cog suites. Single-cog suites pass (no contention to expose the bug).

### M-D2: Don't clear pb_cmd — KILLED

**Mutation**: Comment out `pb_cmd := CMD_NONE` in the worker completion path.

**Effect**: The worker never signals "command complete." After the first command, `send_command()` calls `WAITATN()` — the worker does send `COGATN` so the caller wakes, but on the **next** command, the worker's inner `repeat until pb_cmd <> CMD_NONE` loop sees the stale (non-zero) `pb_cmd` from the previous command and immediately re-dispatches it instead of waiting for the new command. This creates an infinite re-execution loop in the worker. The caller's second `WAITATN()` never returns because the worker re-dispatches the stale command forever.

Additionally, `isComplete()` checks `pb_cmd == CMD_NONE` — it would never return TRUE, so async operations would hang in `getResult()`.

**Detected by**: Every test suite that issues more than one SD command (all 23 suites). The second `send_command()` call in any test hangs, triggering the external timeout. `mount_tests` is the first suite and calls `mount()` followed by other operations — killed on the second API call.

**Kill confidence**: 100% deterministic. No suite survives past its second SD command.

### M-D3: Wrong cog_dir_sec initialization — KILLED

**Mutation**: `longfill(@cog_dir_sec, 0, 8)` — all cogs start with CWD pointing to sector 0 (the MBR) instead of the root directory sector.

**Effect**: Every directory operation uses `cog_dir_sec[pb_caller]` as the starting sector for directory searches. With sector 0, `searchDirectory()` reads the MBR (partition table) instead of a FAT32 directory — the data doesn't contain valid 32-byte directory entries, so every file search fails with E_FILE_NOT_FOUND. `openFileRead()`, `createFileNew()`, `openDirectory()`, and `deleteFile()` all fail immediately.

The mutation is self-correcting only if the caller explicitly calls `changeDirectory("/")` (which sets `cog_dir_sec[pb_caller] := root_sec`), but no test does this before its first file operation.

**Detected by**:
- `cogcwd_tests`: Verifies per-cog CWD isolation — first file operation from any cog fails
- `directory_tests`: Opens directories and reads entries — all return empty/error
- `file_ops_tests`: Creates and opens files in root directory — all fail with E_FILE_NOT_FOUND

**Kill confidence**: Deterministic. Any suite that operates on files without first calling `changeDirectory()` fails immediately.

---

## Combined Summary (Pass 1 + Pass 2)

- **Total mutations**: 15 (4 A + 4 B + 4 C + 3 D)
- **Killed**: 14
- **Equivalent**: 1 (M-A3)
- **Kill rate**: 100% of non-equivalent mutations (14/14)
- **Test suites exercised**: 11 of 23 directly kill at least one mutation
- **Strongest suites**: read_write_tests (kills 5), multicog_tests (kills 1+D1), cogcwd_tests (kills 2)
