# Regression Test Coverage Improvement Plan

**Status:** Complete — all phases implemented and verified on hardware (2026-02-27)
**Created:** 2026-01-31
**Updated:** 2026-02-27
**Target:** Increase test coverage from ~40% to ~90%

## Executive Summary

The regression test suite has strong success-path coverage but significant gaps in error condition testing, recovery scenarios, and boundary case validation. This plan addresses those gaps systematically, prioritized from least complex to most complex.

| Phase | Category | New Files | Augments | Effort | Coverage Gain |
|-------|----------|-----------|----------|--------|---------------|
| 1 | Parameter Validation | 0 | 3 files | 2-3 hrs | +15% |
| 2 | Filesystem Error Codes | 1 new file | 0 | 3-4 hrs | +12% |
| 3 | Boundary Conditions | 0 | 4 files | 4-6 hrs | +10% |
| 4 | CRC/Write Validation | 1 new file | driver | 6-8 hrs | +8% |
| 5 | Recovery Scenarios | 1 new file | 0 | 8-10 hrs | +5% |
| **Total** | | **3 new** | **7 augments** | **23-31 hrs** | **+50%** |

---

## Current State

### Error Code Coverage: 35% (8 of 23 tested)

**Currently Tested:**
- E_NOT_MOUNTED (-20) - mount_tests: openFileRead/createFileNew before mount
- E_FILE_NOT_FOUND (-40) - file_ops_tests, directory_tests
- E_FILE_EXISTS (-41) - file_ops_tests, directory_tests
- E_NOT_A_DIR (-43) - directory_tests: changeDirectory() on file
- E_NOT_A_DIR_HANDLE (-93) - handle type guards on directory handles
- E_TOO_MANY_FILES (-90) - multihandle_tests
- E_INVALID_HANDLE (-91) - partial
- E_FILE_ALREADY_OPEN (-92) - multihandle_tests

**NOT Tested (15 codes):**
- E_CRC_ERROR (-4), E_TIMEOUT (-1), E_NO_RESPONSE (-2), E_BAD_RESPONSE (-3)
- E_WRITE_REJECTED (-5), E_CARD_BUSY (-6), E_IO_ERROR (-7)
- E_INIT_FAILED (-21), E_NOT_FAT32 (-22), E_BAD_SECTOR_SIZE (-23)
- E_NOT_A_FILE (-42), E_DISK_FULL (-60), E_NO_LOCK (-64)
- E_FILE_NOT_OPEN (-45), E_END_OF_FILE (-46)

---

## Phase 1: Parameter Validation (Lowest Complexity) -- COMPLETE

**Effort:** 2-3 hours | **Coverage gain:** +15%

No driver changes required - just call existing APIs with invalid parameters.

### 1.1 Augment: `SD_RT_multihandle_tests.spin2` -- TODO

Add tests for invalid handle parameters:

| Test | Action | Expected |
|------|--------|----------|
| readHandle(-1) | Call with -1 | E_INVALID_HANDLE (-91) |
| readHandle(99) | Call with 99 | E_INVALID_HANDLE (-91) |
| writeHandle on closed | Close then write | E_INVALID_HANDLE (-91) |
| seekHandle invalid | Invalid handle | E_INVALID_HANDLE (-91) |
| Double close | closeFileHandle twice | E_INVALID_HANDLE (-91) |
| tellHandle invalid | Invalid handle | E_INVALID_HANDLE (-91) |
| fileSizeHandle invalid | Invalid handle | E_INVALID_HANDLE (-91) |
| syncHandle invalid | Invalid handle | E_INVALID_HANDLE (-91) |
| eofHandle invalid | Invalid handle | E_INVALID_HANDLE (-91) |

**Tests added: 9**

### 1.2 Augment: `SD_RT_file_ops_tests.spin2` -- TODO (E_NOT_A_FILE)

Add tests for type mismatches:

| Test | Action | Expected | Status |
|------|--------|----------|--------|
| openFile on directory | Open "RTDIR1" as file | E_NOT_A_FILE (-42) | TODO |
| changeDirectory on file | chdir to "FILE1.TXT" | E_NOT_A_DIR (-43) | DONE (directory_tests) |
| openFileForWrite non-existent | Open missing file | E_FILE_NOT_FOUND (-40) | TODO |
| deleteFile non-existent | Delete missing file | E_FILE_NOT_FOUND (-40) | TODO |
| renameFile non-existent | Rename missing file | E_FILE_NOT_FOUND (-40) | TODO |

**Tests remaining: 4** (changeDirectory on file moved to directory_tests, verified passing)

### 1.3 Augment: `SD_RT_mount_tests.spin2` -- DONE

Pre-mount error validation:

| Test | Action | Expected | Status |
|------|--------|----------|--------|
| openFileRead before mount | Call without mount | E_NOT_MOUNTED (-20) | DONE |
| createFileNew before mount | Call without mount | E_NOT_MOUNTED (-20) | DONE |
| readSectorRaw before init | Call without init | false (0) | DONE |
| changeDirectory before mount | Call without mount | false | DONE |

**Driver fix applied:** `send_command()` and `fs_worker` mode enforcement now set `pb_data0 := E_NOT_MOUNTED` on early return, so handle-returning methods correctly propagate the error code.

### Phase 1 Remaining Work
- 1.1: 9 invalid handle tests (multihandle_tests)
- 1.2: 4 type mismatch tests (file_ops_tests)

---

## Phase 2: Filesystem Error Codes (Low-Medium Complexity)

**Effort:** 3-4 hours | **Coverage gain:** +12%

### 2.1 New File: `SD_RT_error_handling_tests.spin2`

Dedicated file for error conditions requiring specific setup:

#### Group: File State Errors

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| E_FILE_NOT_OPEN | No file open | read()/write()/seek() | E_FILE_NOT_OPEN (-45) |
| E_END_OF_FILE explicit | 10-byte file | Read 20 bytes | Returns 10, then E_END_OF_FILE (-46) |

#### Group: Directory Errors

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| Create existing dir | TESTDIR exists | newDirectory("TESTDIR") | E_FILE_EXISTS (-41) |
| File in missing dir | NODIR missing | createFileNew("/NODIR/FILE.TXT") | E_FILE_NOT_FOUND (-40) |

#### Group: Handle Patterns

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| Handle reuse pattern | Open 4, close #1, open new | All ops | Success (reuse works) |
| Write + read same file | Open for write | Open same for read | Success (allowed) |

**Tests added: 7**

### Phase 2 Totals
- New test files: 1
- New test cases: 7
- Error codes covered: +2 (E_FILE_NOT_OPEN, E_END_OF_FILE explicit)

---

## Phase 3: Boundary Conditions (Medium Complexity)

**Effort:** 4-6 hours | **Coverage gain:** +10%

### 3.1 Augment: `SD_RT_read_write_tests.spin2`

| Test | Description |
|------|-------------|
| Empty file | Create 0-byte file, verify size/EOF |
| Single byte file | Create 1-byte file, verify exact read |
| Exact sector (512) | Write exactly 512 bytes, verify |
| Sector + 1 (513) | Write 513 bytes (spans 2 sectors) |
| Large file (64KB) | 128 sectors, cluster chain traversal |
| Very large (1MB) | FAT chain integrity (optional) |

**Tests added: 6**

### 3.2 Augment: `SD_RT_seek_tests.spin2`

| Test | Description |
|------|-------------|
| Seek to 0 | Verify first byte read |
| Seek to EOF-1 | Verify last byte read |
| Seek to EOF | Verify 0 bytes read |
| Seek beyond EOF | Verify error or clamp |
| Seek in empty file | Test edge case |

**Tests added: 5**

### 3.3 Augment: `SD_RT_directory_tests.spin2` -- PARTIALLY DONE

| Test | Description | Status |
|------|-------------|--------|
| Deep nesting (5 levels) | A/B/C/D/E navigation | DONE (directory_tests) |
| Many files (50) | Directory with 50 files | TODO |
| Empty directory | Verify listing behavior | DONE (directory_tests) |
| Max filename (8.3) | "12345678.123" | DONE (directory_tests) |

**Tests remaining: 1** (many files test)

### 3.4 Augment: `SD_RT_raw_sector_tests.spin2`

| Test | Description |
|------|-------------|
| Sector 0 (MBR) | Read and verify $AA55 |
| High sector number | Test sector 1,000,000 |

**Tests added: 2**

### Phase 3 Totals
- New test files: 0
- Augmented files: 4
- New test cases: 17

---

## Phase 4: CRC and Write Validation (Medium-High Complexity)

**Effort:** 6-8 hours | **Coverage gain:** +8%

**Requires driver modifications for test hooks.**

### 4.1 Driver Modification: Test Hooks

Add to `micro_sd_fat32_fs.spin2`:

```spin2
CON '' test hooks (regression testing only)
  TEST_MODE_NORMAL        = 0
  TEST_MODE_CORRUPT_TX_CRC = 1   ' Send bad CRC on writes
  TEST_MODE_FORCE_CRC_FAIL = 2   ' Report CRC mismatch on reads

DAT
  test_mode    LONG    0

PUB setTestMode(mode)
  test_mode := mode

PUB getTestMode() : mode
  return test_mode
```

Modify `calcDataCRC()` to optionally corrupt CRC.
Modify `readSector()` to optionally force CRC mismatch and return E_CRC_ERROR.

### 4.2 New File: `SD_RT_crc_validation_tests.spin2`

#### Group: Read CRC Validation

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| Normal read | CRC enabled | Read sector | Success, match count++ |
| Forced CRC fail | TEST_MODE_FORCE_CRC_FAIL | Read sector | E_CRC_ERROR (-4) |
| CRC disabled | setCRCValidation(false) | Read sector | Success (not checked) |

#### Group: Write CRC Validation

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| Normal write | Normal mode | Write sector | DATA_ACCEPTED |
| Corrupt CRC | TEST_MODE_CORRUPT_TX_CRC | Write sector | E_WRITE_REJECTED (-5) |
| Recovery | After failure | Normal write | Success |

#### Group: CRC Statistics

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| Match counter | Clear, read 10 | getCRCMatchCount() | Returns 10 |
| Mismatch counter | Force 1 fail | getMismatchCount() | Returns 1 |

**Tests added: 8**

### Phase 4 Totals
- New test files: 1
- Driver modifications: ~30 lines
- New test cases: 8
- Error codes covered: +2 (E_CRC_ERROR, E_WRITE_REJECTED)

---

## Phase 5: Recovery Scenarios (High Complexity)

**Effort:** 8-10 hours | **Coverage gain:** +5%

### 5.1 New File: `SD_RT_recovery_tests.spin2`

#### Group: Recovery After Read Errors

| Test | Description |
|------|-------------|
| Continue after CRC error | Force fail, then normal read |
| Seek and retry | Force fail, seek elsewhere, read |

#### Group: Recovery After Write Errors

| Test | Description |
|------|-------------|
| File state after rejection | Verify original data intact |
| Retry write | Force fail, then successful retry |

#### Group: Mount/Unmount Recovery

| Test | Description |
|------|-------------|
| Remount after errors | Cause errors, unmount, remount |
| Handle cleanup | Verify handles released on unmount |

#### Group: Multi-Handle Recovery

| Test | Description |
|------|-------------|
| Isolation | Error on handle 1, handles 0,2 unaffected |
| Handle reuse after error | Error, close, reopen same slot |

**Tests added: 8**

### Phase 5 Totals
- New test files: 1
- New test cases: 8

---

## Final Coverage Matrix

| Error Code | Current | After Plan |
|------------|---------|------------|
| E_TIMEOUT (-1) | :x: | :x: (hardware) |
| E_NO_RESPONSE (-2) | :x: | :x: (hardware) |
| E_BAD_RESPONSE (-3) | :x: | :x: (hardware) |
| E_CRC_ERROR (-4) | :x: | :white_check_mark: Phase 4 |
| E_WRITE_REJECTED (-5) | :x: | :white_check_mark: Phase 4 |
| E_CARD_BUSY (-6) | :x: | :x: (timing) |
| E_IO_ERROR (-7) | :x: | :x: (hardware) |
| E_NOT_MOUNTED (-20) | :white_check_mark: | :white_check_mark: (done) |
| E_INIT_FAILED (-21) | :x: | :x: (bad card) |
| E_NOT_FAT32 (-22) | :x: | :x: (bad card) |
| E_BAD_SECTOR_SIZE (-23) | :x: | :x: (bad card) |
| E_FILE_NOT_FOUND (-40) | :white_check_mark: | :white_check_mark: |
| E_FILE_EXISTS (-41) | :white_check_mark: | :white_check_mark: |
| E_NOT_A_FILE (-42) | :x: | :white_check_mark: Phase 1 |
| E_NOT_A_DIR (-43) | :white_check_mark: | :white_check_mark: (done) |
| E_FILE_NOT_OPEN (-45) | :x: | :white_check_mark: Phase 2 |
| E_END_OF_FILE (-46) | :warning: | :white_check_mark: Phase 2 |
| E_DISK_FULL (-60) | :x: | :x: (full card) |
| E_NO_LOCK (-64) | :x: | :x: (multi-cog) |
| E_TOO_MANY_FILES (-90) | :white_check_mark: | :white_check_mark: |
| E_INVALID_HANDLE (-91) | :warning: | :white_check_mark: Phase 1 |
| E_FILE_ALREADY_OPEN (-92) | :white_check_mark: | :white_check_mark: |
| E_NOT_A_DIR_HANDLE (-93) | :white_check_mark: | :white_check_mark: (done) |

**Testable codes: 15 of 23 (65%)**
**Currently tested: 8 of 15 (53%)**
**After plan: 13 of 15 testable covered (87%)**

---

## What Cannot Be Easily Tested

| Error Code | Reason | Possible Approach |
|------------|--------|-------------------|
| E_TIMEOUT | Card must stop responding | Physical card removal |
| E_NO_RESPONSE | Card must be absent | Test without card |
| E_INIT_FAILED | Card must fail init | Damaged/incompatible card |
| E_NOT_FAT32 | Need non-FAT32 card | Format as exFAT |
| E_DISK_FULL | Need completely full card | Fill card manually |
| E_NO_LOCK | All 16 locks exhausted | Complex multi-cog scenario |

---

## Implementation Checkpoints

1. **Phase 1 complete** - Parameter validation tests added to multihandle, file_ops, mount suites
2. **Phase 2 complete** - Error handling tests augmented with V1 legacy API, handle type mismatch, rename edge cases (13 tests)
3. **Phase 3 complete** - Directory stress test (20 files) added to directory_tests (29 tests)
4. **Phase 4 complete** - CRC error injection hooks added to driver, SD_RT_crc_validation_tests.spin2 created (6 tests)
5. **Phase 5 complete** - SD_RT_recovery_tests.spin2 created (7 tests)

All 20 suites (389 tests) verified passing on hardware 2026-02-27.

---

## References

- Audit performed: 2026-01-31, updated 2026-02-07
- Driver: `src/micro_sd_fat32_fs.spin2` (unified driver with GETCRC-based CRC)
- Test framework: `regression-tests/isp_rt_utilities.spin2`
- Test runner: `tools/run_test.sh` (execute from `tools/` directory)
