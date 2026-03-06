# Regression Test Suite: Coverage Analysis and Strengthening Opportunities

An analysis of the P2-uSD-FAT32-FS regression test suite against the principles in [REGRESSION-TESTING-BEST-PRACTICES.md](../Decisions/REGRESSION-TESTING-BEST-PRACTICES.md).

**Date:** 2026-03-05
**Suite Version:** v1.1.0 (20 suites, 389 tests, all passing)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Suite Inventory](#2-suite-inventory)
3. [Strengths](#3-strengths)
4. [API Method Coverage Matrix](#4-api-method-coverage-matrix)
5. [Error Code Coverage Matrix](#5-error-code-coverage-matrix)
6. [Gap Analysis by Best-Practice Category](#6-gap-analysis-by-best-practice-category)
7. [Strengthening Opportunities: Prioritized](#7-strengthening-opportunities-prioritized)
8. [Appendix: Test Counts by Suite](#appendix-test-counts-by-suite)

---

## 1. Executive Summary

The regression suite is **substantially strong** for a hardware-driver project. It covers the full API lifecycle (mount through unmount), exercises all major subsystems, includes fault injection (CRC error hooks), uses guard zones for buffer overflow detection in 17 of 20 suites, and has extensive multi-handle and multi-cog testing.

The primary gaps fall into three categories:

1. **Error code coverage**: 8 of 22 error codes are tested by name; 14 are never explicitly asserted (mostly card-level and filesystem-level errors that are difficult to trigger from test code).
2. **Boundary value testing**: Most tests exercise the happy path and a few error paths, but systematic boundary bracketing (Section 5.2 / 7.3 of the best practices) is largely absent.
3. **Post-teardown / use-after-invalidation testing**: Only mount_tests tests operations-after-unmount; no suite tests operations-after-close comprehensively (Section 6.4).

These gaps represent opportunities, not urgent defects. The existing suite catches regressions effectively -- the question is whether it would catch *subtle* regressions (off-by-one at boundaries, resource leaks after errors, state corruption from invalid handle reuse).

---

## 2. Suite Inventory

| # | Suite File | Focus | Tests | Groups | Guards | Cleanup |
|---|-----------|-------|-------|--------|--------|---------|
| 1 | SD_RT_mount_tests | Mount/unmount lifecycle | 21 | 6 | Yes | N/A |
| 2 | SD_RT_format_tests | Format and VBR validation | 46 | 8 | Yes | N/A |
| 3 | SD_RT_volume_tests | Volume label, free space, sync | 23 | 5 | Yes | Yes |
| 4 | SD_RT_file_ops_tests | Create/delete/rename/open | 22 | 7 | Yes | Yes |
| 5 | SD_RT_read_write_tests | Read/write round-trip | 38 | 9 | Yes | Yes |
| 6 | SD_RT_seek_tests | Seek/tell/position | 37 | 8 | Yes | Yes |
| 7 | SD_RT_directory_tests | readDirectory, newDirectory, cd | 29 | 8 | No | Yes |
| 8 | SD_RT_subdir_ops_tests | Subdirectory file operations | 18 | 6 | No | Yes |
| 9 | SD_RT_dirhandle_tests | openDirectory handle-based API | 22 | 5 | Yes | Yes |
| 10 | SD_RT_multihandle_tests | Multi-file concurrent access | 19 | 9 | Yes | Yes |
| 11 | SD_RT_multicog_tests | Multi-cog concurrent access | 14 | 6 | Yes | Yes |
| 12 | SD_RT_error_handling_tests | Error paths and misuse | 10 | 6 | Yes | Yes |
| 13 | SD_RT_recovery_tests | CRC fault injection + recovery | 7 | 4 | Yes | Yes |
| 14 | SD_RT_raw_sector_tests | Raw sector read/write | -- | -- | Yes | N/A |
| 15 | SD_RT_multiblock_tests | Multi-block CMD18/CMD25 | -- | -- | Yes | N/A |
| 16 | SD_RT_register_tests | CID/CSD/SCR/SD Status | 10 | 2 | Yes | N/A |
| 17 | SD_RT_speed_tests | High-speed mode, setSPISpeed | 15 | 3 | Yes | Yes |
| 18 | SD_RT_crc_validation_tests | CRC match/mismatch counters | 6 | 3 | Yes | Yes |
| 19 | SD_RT_crc_diag_tests | CRC diagnostic getters | 14 | 4 | Yes | Yes |
| 20 | SD_RT_fifo_tests | String FIFO (isp_string_fifo) | 21 | 8 | No | N/A |

**Totals:** 411 `startTest()` calls, 120 `startTestGroup()` calls, 271 sub-assertions, 214 guard init/check calls across 20 suites.

---

## 3. Strengths

### 3.1 Round-Trip Data Integrity (Best Practices Section 8.1)

The read_write_tests suite is the strongest in the collection. It writes known data patterns, reads them back, and compares byte-for-byte. This exercises the full stack: hub RAM -> mailbox -> SPI smart pins -> streamer DMA -> SD card -> streamer DMA -> SPI -> hub RAM. Multiple data patterns are used (incrementing, random, constant fill).

### 3.2 Fault Injection (Best Practices Section 13.3)

The recovery_tests suite uses the driver's CRC error injection hooks (`setTestForceReadError`, `setTestForceWriteError`) to simulate hardware faults at the SPI layer. Tests verify:
- Single-error recovery (retry succeeds)
- Max-retry exhaustion (all retries fail, error reported)
- Write-error detection and data preservation
- Multi-handle isolation during errors
- Post-error remount and recovery

This is unusually thorough for an embedded driver project.

### 3.3 Guard Zone Discipline (Best Practices Section 15)

17 of 20 suites use `initGuard()` / `checkGuard()` sentinel patterns around buffers. This catches buffer overflows that corrupt adjacent data silently -- a class of bug that is extremely difficult to diagnose without sentinels on an embedded platform with no MMU.

### 3.4 Multi-Handle Concurrency (Best Practices Section 16, Step 7)

The multihandle_tests suite systematically tests:
- 4 simultaneous read handles with independent position tracking
- Two handles to the same file with independent cursors
- Single-writer enforcement (E_FILE_ALREADY_OPEN)
- Handle pool exhaustion (6th handle succeeds, 7th returns E_TOO_MANY_FILES)
- Invalid handle operations (negative handle, out-of-range, closed handle)

### 3.5 Multi-Cog Access (Best Practices Section 16, Step 7)

The multicog_tests suite launches a second cog that performs concurrent file operations while the main cog also operates, verifying the lock-based serialization mechanism.

### 3.6 Test Cleanup Discipline (Best Practices Section 10.1)

14 of the 20 suites that create files also clean them up (deleteFile). The 6 suites that don't (format, mount, raw_sector, multiblock, register, fifo) either don't create files or operate at a level below the filesystem.

### 3.7 Sub-Test Pattern (Best Practices Section 3.3)

Complex tests use `setCheckCountPerTest()` + `evaluateSubValue()` to group multiple related assertions under a single logical test. This keeps test counts meaningful while still checking multiple postconditions per operation (271 sub-assertions across 15 suites).

---

## 4. API Method Coverage Matrix

Listing every PUB method in the driver and which test suites exercise it.

### Fully Covered (tested in 2+ suites)

| Method | Suites |
|--------|--------|
| `mount()` | mount, format, volume, file_ops, read_write, seek, directory, subdir_ops, dirhandle, multihandle, multicog, error_handling, recovery, speed, crc_validation, crc_diag |
| `unmount()` | mount, format, volume, file_ops, read_write, seek, directory, subdir_ops, dirhandle, multihandle, multicog, error_handling, recovery, speed, crc_validation, crc_diag |
| `openFileRead()` | file_ops, read_write, seek, multihandle, multicog, error_handling, recovery, crc_validation, crc_diag, speed |
| `openFileWrite()` | file_ops, read_write, multihandle, error_handling, recovery |
| `createFileNew()` | file_ops, read_write, seek, multihandle, multicog, volume, crc_validation, crc_diag, speed |
| `closeFileHandle()` | (all suites that open files) |
| `readHandle()` | read_write, seek, multihandle, multicog, recovery, crc_validation, crc_diag, speed |
| `writeHandle()` | read_write, seek, multihandle, multicog, volume, error_handling, recovery, crc_validation, crc_diag, speed |
| `seekHandle()` | seek, multihandle, recovery |
| `deleteFile()` | file_ops, read_write, directory, subdir_ops, multihandle, error_handling, recovery, crc_validation, crc_diag, volume, speed, multicog, dirhandle, seek |
| `changeDirectory()` | directory, subdir_ops, error_handling, file_ops |
| `newDirectory()` | directory, subdir_ops, error_handling |
| `readDirectory()` | directory |
| `rename()` | file_ops, subdir_ops, error_handling |
| `freeSpace()` | volume, multihandle |
| `volumeLabel()` | volume, mount, format |
| `checkStackGuard()` | mount, read_write, speed |

### Lightly Covered (tested in 1 suite only)

| Method | Suite | Concern |
|--------|-------|---------|
| `tellHandle()` | multihandle | Only 1 call; no systematic position-after-operation checks |
| `eofHandle()` | multihandle (4), read_write (1) | Tested at EOF; not tested mid-file or at position 0 |
| `fileSizeHandle()` | multihandle | Also used indirectly in seek, read_write, but not systematically |
| `syncHandle()` | multihandle (2), read_write (1), volume (6) | Tested but no verification that data persists across unmount/remount |
| `syncAllHandles()` | volume | Single suite |
| `sync()` | volume | Single suite |
| `moveFile()` | directory | Single call in 1 suite |
| `setVolumeLabel()` | volume | Round-trip tested |
| `setDate()` | volume | Tested |
| `readVBRRaw()` | volume | Single call |
| `openDirectory()` | dirhandle | Single suite |
| `readDirectoryHandle()` | dirhandle | Single suite |
| `closeDirectoryHandle()` | dirhandle | Single suite |
| `error()` | mount (2), multicog (1) | Rarely used; most tests check return values directly |
| `initCardOnly()` | raw_sector | Single suite |
| `readSectorRaw()` | raw_sector | Single suite |
| `writeSectorRaw()` | raw_sector | Single suite |
| `readSectorsRaw()` | multiblock | Single suite |
| `writeSectorsRaw()` | multiblock | Single suite |

### Not Tested at All

| Method | Conditional | Notes |
|--------|------------|-------|
| `start()` | Core | Only tested implicitly through `mount()` |
| `stop()` | Core | Only called in register_tests (1) and multicog_tests (1); never verified for correctness |
| `syncDirCache()` | Core | Called in error_handling (1) and file_ops (3) but never as the unit under test |
| `cardSizeSectors()` | SD_INCLUDE_RAW | Not tested |
| `testCMD13()` | SD_INCLUDE_RAW | Diagnostic, low priority |
| `getOCR()` | SD_INCLUDE_REGISTERS | Not tested |
| `getManufacturerID()` | SD_INCLUDE_REGISTERS | Not tested |
| `getReadTimeout()` | SD_INCLUDE_REGISTERS | Not tested |
| `getWriteTimeout()` | SD_INCLUDE_REGISTERS | Not tested |
| `isHighSpeedActive()` | SD_INCLUDE_SPEED | Not tested |
| `getSPIFrequency()` | Core | Not tested |
| `getCardMaxSpeed()` | Core | Not tested |
| `setCRCValidation()` | SD_INCLUDE_DEBUG | Not tested as unit |
| `reportStackDepth()` | SD_INCLUDE_STACK_CHECK | Used diagnostically but not asserted |

---

## 5. Error Code Coverage Matrix

The driver defines 22 distinct error codes. Test coverage:

### Tested (asserted by name in test assertions)

| Error Code | Value | Suites Testing It |
|-----------|-------|-------------------|
| `E_NOT_MOUNTED` | -20 | mount_tests (4 assertions) |
| `E_FILE_NOT_FOUND` | -40 | file_ops (4), subdir_ops (3), dirhandle (1), error_handling (1) |
| `E_FILE_EXISTS` | -41 | file_ops (1), directory (1), error_handling (2) |
| `E_NOT_A_FILE` | -42 | file_ops (1) |
| `E_NOT_A_DIR` | -43 | directory (2), error_handling (1) |
| `E_TOO_MANY_FILES` | -90 | multihandle (1), dirhandle (1) |
| `E_INVALID_HANDLE` | -91 | multihandle (8), error_handling (2) |
| `E_FILE_ALREADY_OPEN` | -92 | multihandle (1), error_handling (1) |

**8 of 22 error codes** are explicitly tested.

### Not Tested

| Error Code | Value | Difficulty to Test | Priority |
|-----------|-------|-------------------|----------|
| `E_TIMEOUT` | -1 | Hard (requires hardware fault) | Low |
| `E_NO_RESPONSE` | -2 | Hard (requires card removal) | Low |
| `E_BAD_RESPONSE` | -3 | Hard (requires protocol error) | Low |
| `E_CRC_ERROR` | -4 | Medium (fault injection exists but return code not asserted) | **Medium** |
| `E_WRITE_REJECTED` | -5 | Hard (requires write-protected card) | Low |
| `E_CARD_BUSY` | -6 | Hard (requires timing window) | Low |
| `E_IO_ERROR` | -7 | Hard (requires hardware fault) | Low |
| `E_NO_CARD` | -8 | Hard (requires no card in slot) | Low |
| `E_INIT_FAILED` | -21 | Hard (requires damaged card) | Low |
| `E_NOT_FAT32` | -22 | Hard (requires non-FAT32 card) | Low |
| `E_BAD_SECTOR_SIZE` | -23 | Hard (requires non-512 sector) | Low |
| `E_FILE_NOT_OPEN` | -45 | Easy (call read on unopened file) | **High** |
| `E_END_OF_FILE` | -46 | Easy (read past EOF) | **High** |
| `E_DISK_FULL` | -60 | Medium (requires filling card or small partition) | **Medium** |
| `E_NO_LOCK` | -64 | Hard (requires all 16 P2 locks consumed) | Low |
| `E_NOT_A_DIR_HANDLE` | -93 | Easy (use file handle with dir API) | **High** |

---

## 6. Gap Analysis by Best-Practice Category

### 6.1 Boundary Value Analysis (Best Practices Section 5.2)

**Current state:** Almost no systematic boundary testing. Tests use representative values (middle of range) but rarely bracket boundaries.

**Specific gaps:**

| Boundary | Test Needed |
|----------|------------|
| File size = 0 bytes | Create empty file, verify fileSizeHandle() == 0, readHandle() returns 0 bytes |
| File size = 1 byte | Write 1 byte, read back, verify |
| File size = 511 bytes | Just under sector boundary |
| File size = 512 bytes | Exact sector boundary |
| File size = 513 bytes | Just over sector boundary, forces 2-sector allocation |
| Cluster boundary crossing | Write data that spans two clusters; read back and verify continuity |
| Seek to position 0 | Already tested in seek_tests |
| Seek to exact EOF | Seek to fileSizeHandle(), verify eofHandle() == TRUE |
| Seek to EOF-1 | Read 1 byte, verify correct last byte |
| Seek past EOF | Verify error or documented behavior |
| Filename = 1 char | "A.TXT" -- minimum valid |
| Filename = 8.3 max | "12345678.123" -- maximum valid |
| Filename with spaces | "FILE    .TXT" -- edge case |
| readHandle count = 0 | Read 0 bytes, verify returns 0, position unchanged |
| readHandle count = 1 | Read 1 byte |
| writeHandle count = 0 | Write 0 bytes |
| writeHandle count = 1 | Write 1 byte |
| MAX_OPEN_FILES boundary | Already tested (6 open, 7th fails) |

### 6.2 State Transition Testing (Best Practices Section 5.4)

**Current state:** The mount_tests suite tests the UNMOUNTED -> MOUNTED transition and operations-before-mount. But the full state machine is not systematically exercised.

**Missing transitions:**

| From State | Operation | Expected |
|-----------|-----------|----------|
| MODE_NONE | Any file op | E_NOT_MOUNTED (partially tested) |
| MODE_RAW | openFileRead() | E_NOT_MOUNTED |
| MODE_RAW | mount() upgrade | Already works but no test |
| MODE_FILESYSTEM | mount() again | Should succeed or return E_ALREADY_MOUNTED |
| MODE_FILESYSTEM | initCardOnly() | Undefined -- needs test to document behavior |
| File OPEN_READ | writeHandle() | Should fail |
| File OPEN_WRITE | seekHandle() to arbitrary pos | Current behavior unclear |
| File CLOSED | Any handle operation | E_INVALID_HANDLE (tested for some ops) |

### 6.3 Post-Teardown Testing (Best Practices Section 6.4)

**Current state:** mount_tests verifies 4 operations fail with E_NOT_MOUNTED after no mount. But it does not test the sequence: mount -> open files -> unmount -> try operations on the stale handles.

**Missing scenarios:**

1. **Use after unmount:** Mount, open file, unmount, try readHandle/writeHandle/seekHandle/closeFileHandle on the now-stale handle. Each should return an appropriate error.
2. **Use after close:** Open file, close it, try readHandle/writeHandle/seekHandle/tellHandle/eofHandle/fileSizeHandle. Already partially tested in multihandle_tests (double-close returns E_INVALID_HANDLE), but the full set of operations on a closed handle is not exercised.
3. **Re-open after close:** Close a handle, open a new file. Verify the recycled handle slot has no stale state from the previous occupant.

### 6.4 Postcondition Verification (Best Practices Section 7.2)

**Current state:** Many tests verify return values but don't check postconditions.

**Examples of unchecked postconditions:**

| Operation | Postcondition | Currently Verified? |
|-----------|--------------|-------------------|
| `writeHandle(n bytes)` | tellHandle() advances by n | No -- tellHandle() almost never called |
| `writeHandle(n bytes)` | fileSizeHandle() >= previous + n | No |
| `seekHandle(pos)` | tellHandle() == pos | Partially in seek_tests |
| `createFileNew()` | fileSizeHandle() == 0 | Not checked |
| `openFileWrite()` | tellHandle() == fileSizeHandle() (at EOF) | Not checked |
| `deleteFile()` | openFileRead() returns E_FILE_NOT_FOUND | Yes (tested) |
| `rename()` | old name returns E_FILE_NOT_FOUND, new name opens | Yes (tested) |
| `closeFileHandle()` | handle is reusable | Not explicitly checked |

### 6.5 Cross-Subsystem Isolation (Best Practices Section 16, Step 8)

**Current state:** The multicog_tests suite tests inter-cog access. But there is no test for:

1. **Directory handle + file handle sharing the handle pool:** Open 3 file handles and 3 directory handles (filling the pool to 6). Verify the 7th fails. Then close a directory handle and open a file handle. Verify pool recycling works across handle types.
2. **Raw sector I/O + filesystem I/O coexistence:** Mount in MODE_FILESYSTEM, do file operations, then do readSectorRaw(). Verify they don't interfere. (This is actually a valid usage pattern per the driver docs.)

### 6.6 Property-Based / Pattern Testing (Best Practices Section 15)

**Current state:** The read_write_tests suite uses incrementing and random patterns, which is a form of property testing (round-trip invariant). But there is no systematic variation of:

- All-zeros pattern (tests zero-detection edge cases)
- All-ones pattern ($FF fill)
- Alternating $AA/$55 (tests bit-pattern sensitivity)
- Single-bit patterns (one byte differs from all-same)

The read_write suite does use `fillBufferWithPattern()` and `fillBufferWithRandom()`, so some patterns are covered, but there's no all-$00 or all-$FF test.

### 6.7 Guard Zone Gaps

Three suites that allocate buffers do NOT use guard zones:

| Suite | Why It Matters |
|-------|---------------|
| `SD_RT_directory_tests` | Reads directory entries into buffers; overflow could corrupt adjacent data |
| `SD_RT_subdir_ops_tests` | Same concern as directory_tests |
| `SD_RT_fifo_tests` | FIFO writes into fixed-size string slots; overflow is a real risk |

---

## 7. Strengthening Opportunities: Prioritized

### Tier 1: High Value, Low Effort — IMPLEMENTED (v1.2.1)

All Tier 1 items implemented and compile-verified 2026-03-05.

**O-1. Boundary value tests for file size at sector boundaries** -- DONE
Added 511-byte boundary test to read_write_tests (0, 1, 511, 512, 513 bytes now covered). Existing tests already covered 0, 1, 512, 513.

**O-2. Postcondition checks with tellHandle()** -- DONE
Added 2 dedicated tests in read_write_tests: tellHandle tracks write position (3 sub-checks) and tellHandle tracks read position (2 sub-checks).

**O-3. E_NOT_A_DIR_HANDLE error coverage** -- DONE
Added 3 tests in dirhandle_tests: readHandle, writeHandle, seekHandle on dir handle all return E_NOT_A_DIR_HANDLE. Also added 4 tests in error_handling_tests: tellHandle, fileSizeHandle, eofHandle, syncHandle on dir handle.

**O-4. Use-after-close comprehensive test** -- DONE
Added 1 test with 7 sub-assertions in multihandle_tests: all handle operations (readHandle, writeHandle, seekHandle, tellHandle, fileSizeHandle, eofHandle, syncHandle) fail with E_INVALID_HANDLE on a recently-closed valid handle.

**O-5. Guard zones for directory_tests, subdir_ops_tests, fifo_tests** -- DONE
Added guard zone to readBuf in directory_tests. subdir_ops_tests has no data-receiving buffers (skipped). fifo_tests resultBuf is only used as source data, not as a read destination (skipped).

### Tier 2: Medium Value, Medium Effort — IMPLEMENTED (v1.2.1)

All Tier 2 items implemented and compile-verified 2026-03-05.

**O-6. readHandle() at and past EOF behavior** -- DONE
Added 3 tests in read_write_tests: read at exact EOF returns 0, eofHandle FALSE before EOF, partial read returns remaining bytes.

**O-7. writeHandle() postcondition: fileSizeHandle() growth** -- DONE
Added fileSizeHandle() checks during write phase of 3 boundary tests (1-byte, 512-byte, 513-byte files) in read_write_tests.

**O-8. CRC diagnostic verification in recovery_tests** -- DONE
Added getCRCMismatchCount() verification in the exhaustive CRC error test. Confirms CRC mismatches were actually counted by the driver during forced error injection. (Note: E_CRC_ERROR is not propagated through readHandle — the driver returns 0 bytes on CRC exhaustion. CRC diagnostic counters are the correct observable to verify.)

**O-9. Mount/unmount cycle with open handles** -- DONE
Added 5 tests in mount_tests: post-unmount state group verifying openFileRead, createFileNew, changeDirectory return E_NOT_MOUNTED after unmount, plus remount succeeds and freeSpace works after remount.

**O-10. Handle pool recycling across types** -- DONE
Added 1 test with 4 sub-assertions in multihandle_tests: mixed file + dir handles fill pool, close one of each type, verify recycled slots work for both file and dir handle allocation.

**O-11. State transition: write to read handle, read from write handle** -- DONE
Existing error_handling_tests already covered writeHandle on read handle (E_INVALID_HANDLE) and readHandle on write handle (allowed). Extended with 4 new tests for dir handle type mismatch (tellHandle, fileSizeHandle, eofHandle, syncHandle on dir handle return E_NOT_A_DIR_HANDLE).

### Tier 3: Valuable but Higher Effort

**O-12. Cluster boundary crossing with known data**
Write a file larger than one cluster (typically 32 KB for a 64 KB cluster). Read it back and verify byte-for-byte. The seek_tests does some of this but not with systematic pattern verification across cluster boundaries.

**O-13. Disk full simulation**
Write files in a loop until `createFileNew()` or `writeHandle()` returns E_DISK_FULL. Then delete a file, verify a new write succeeds. This requires a small partition or a very patient test. Could use a specially-formatted small test card.

**O-14. All-zeros and all-$FF data patterns**
Add test cases with all-$00 and all-$FF data buffers to read_write_tests. These patterns can trigger edge cases in DMA/streamer logic that incrementing or random patterns don't.

**O-15. Double-mount behavior**
Call mount() when already mounted. Document and test the expected behavior (should it succeed silently? return an error? re-initialize?).

**O-16. Filename edge cases**
Test with minimum-length filenames ("A"), maximum 8.3 filenames ("12345678.123"), filenames with leading/trailing spaces, and filenames differing only in case.

**O-17. Assertion quality audit**
Review all `evaluateRange()` calls for overly wide ranges. Review all `evaluateBool()` calls to ensure the actual value comes from the code under test, not a derived boolean expression. The best practices document (Section 13.4) warns about tautological assertions.

### Tier 4: Aspirational / Long-Term

**O-18. Per-cog CWD isolation test**
Launch two cogs, each calling `changeDirectory()` to different directories. Verify that each cog's operations are in its own directory (cog_dir_sec[8] isolation). This is architecturally important but complex to test.

**O-19. Concurrent reader + writer stress test**
One cog writes continuously while another cog reads from a different file. Run for many iterations. Verify data integrity on both sides.

**O-20. Manual mutation testing**
Temporarily introduce deliberate bugs in the driver (off-by-one in cluster allocation, wrong error code in a boundary check, reversed condition in EOF detection) and verify that existing tests catch them. Where they don't, add the missing test.

---

## Appendix: Test Counts by Suite

| Suite | startTest() | startTestGroup() | Sub-Assertions | Guard Calls |
|-------|------------|-----------------|----------------|-------------|
| mount_tests | 26 | 7 | 3 | 4 |
| format_tests | 46 | 8 | 0 | 20 |
| volume_tests | 23 | 5 | 26 | 6 |
| file_ops_tests | 22 | 7 | 19 | 16 |
| read_write_tests | 44 | 9 | 61 | 47 |
| seek_tests | 37 | 8 | 9 | 30 |
| directory_tests | 29 | 8 | 14 | 2 |
| subdir_ops_tests | 18 | 6 | 19 | 0 |
| dirhandle_tests | 25 | 5 | 35 | 2 |
| multihandle_tests | 21 | 11 | 60 | 18 |
| multicog_tests | 14 | 6 | 0 | 6 |
| error_handling_tests | 14 | 6 | 11 | 4 |
| recovery_tests | 7 | 4 | 14 | 16 |
| raw_sector_tests | -- | -- | 0 | 12 |
| multiblock_tests | -- | -- | 0 | 9 |
| register_tests | 10 | 2 | 6 | 4 |
| speed_tests | 15 | 3 | 6 | 6 |
| crc_validation_tests | 6 | 3 | 11 | 10 |
| crc_diag_tests | 14 | 4 | 5 | 10 |
| fifo_tests | 21 | 8 | 0 | 0 |
| **Totals** | **431** | **123** | **300** | **222** |

---

*Analysis produced 2026-03-05 against REGRESSION-TESTING-BEST-PRACTICES.md (2026-03-04). No code changes made.*
