# Driver Changes Needed

**Purpose:** Running log of driver modifications identified during test coverage improvement work.

**Created:** 2026-02-03
**Status:** Active - Updated as testing reveals needs

---

## Error Codes Catalog (from SD_card_driver.spin2)

| Code | Constant | Value | Testable? | Notes |
|------|----------|-------|-----------|-------|
| Hardware/Timing | E_TIMEOUT | -1 | No | Requires card removal |
| Hardware/Timing | E_NO_RESPONSE | -2 | No | Requires absent card |
| Hardware/Timing | E_BAD_RESPONSE | -3 | No | Hardware fault |
| Hardware/Timing | E_CRC_ERROR | -4 | With hooks | Needs test mode injection |
| Hardware/Timing | E_WRITE_REJECTED | -5 | With hooks | Needs test mode injection |
| Hardware/Timing | E_CARD_BUSY | -6 | No | Timing dependent |
| Hardware/Timing | E_IO_ERROR | -7 | No | Hardware fault |
| Mount | E_NOT_MOUNTED | -20 | **Yes** | Call APIs before mount |
| Mount | E_INIT_FAILED | -21 | No | Requires bad card |
| Mount | E_NOT_FAT32 | -22 | No | Requires non-FAT32 card |
| Mount | E_BAD_SECTOR_SIZE | -23 | No | Requires non-512 card |
| File | E_FILE_NOT_FOUND | -40 | **Yes** | Open non-existent |
| File | E_FILE_EXISTS | -41 | **Yes** | Create existing |
| File | E_NOT_A_FILE | -42 | **Yes** | Open dir as file |
| File | E_NOT_A_DIR | -43 | **Yes** | chdir to file |
| File | E_FILE_NOT_OPEN | -45 | **Yes** | Read without open |
| File | E_END_OF_FILE | -46 | **Yes** | Read past EOF |
| Disk | E_DISK_FULL | -60 | No | Requires full card |
| Lock | E_NO_LOCK | -64 | No | Requires all 16 locks used |
| Handle | E_TOO_MANY_FILES | -90 | **Yes** | Open 5th file |
| Handle | E_INVALID_HANDLE | -91 | **Yes** | Use bad handle |
| Handle | E_FILE_ALREADY_OPEN | -92 | **Yes** | Double write-open |

**Summary:** 12 of 22 error codes are testable without hardware manipulation or special cards.

---

## Driver Changes Identified

### During Phase 1 Testing

1. **BUG: changeDirectory() succeeds when given a file name**
   - **Found:** SD_RT_file_ops_tests.spin2 - Type Mismatch Errors tests
   - **Expected:** changeDirectory(@"RTFILE1.TXT") should return false (0)
   - **Actual:** Returns true (-1), incorrectly allowing "cd" into a file
   - **Location:** Worker cog's do_chdir() needs to check if entry is directory before allowing
   - **Impact:** E_NOT_A_DIR (-43) error code is never returned
   - **Action:** Modify do_chdir() to verify entry has ATTR_DIR before accepting

2. **ENHANCEMENT: Pre-mount operations should return E_NOT_MOUNTED**
   - **Found:** SD_RT_mount_tests.spin2 - Pre-Mount Error Validation tests
   - **Expected:** openFileRead(), createFileNew(), readSectorRaw() before mount should return E_NOT_MOUNTED (-20)
   - **Actual:** Returns 0 (success/no error) for all operations
   - **Location:** V3 handle-based API functions need mode checking at entry
   - **Impact:** E_NOT_MOUNTED (-20) error code is never returned; callers can't distinguish "not mounted" from other conditions
   - **Action:** Add mode/mount check at start of openFileRead(), createFileNew(), readSectorRaw() to return E_NOT_MOUNTED if not mounted

### During Phase 2 Testing

*(To be filled in as issues are discovered)*

### During Phase 3 Testing

*(To be filled in as issues are discovered)*

---

## Test Framework Notes

**Available evaluation functions (SD_RT_utilities.spin2):**
- `evaluateBool(result, pMessage, expected)` - Boolean comparison
- `evaluateSingleValue(result, pMessage, expected)` - Exact value match
- `evaluateSingleValueHex(result, pMessage, expected)` - Hex display
- `evaluateSubValue/evaluateSubBool` - Multiple checks per test
- `evaluateRange(result, pMessage, min, max)` - Range check
- `evaluateNotZero(result, pMessage)` - Non-zero check
- `evaluateStringMatch(pResult, pMessage, pExpected)` - String comparison
- `evaluateBufferMatch(pBuf1, pBuf2, length, pMessage)` - Buffer comparison
- `recordPass()` / `recordFail()` - Manual recording

**Test structure pattern:**
```spin2
utils.startTestGroup(@"Group Name")

utils.startTest(@"Test description")
result := sd.someOperation()
utils.evaluateSingleValue(result, @"operation result", E_EXPECTED_ERROR)

utils.ShowTestEndCounts()
debug("END_SESSION")
```

---

## Deferred Items (Require Driver Hooks)

These items from the test coverage plan require driver modifications:

1. **CRC Error Injection (Phase 4):** Add `setTestMode()` to force CRC failures
2. **Write Rejection Injection (Phase 4):** Add test mode to corrupt TX CRC
3. **CRC Statistics (Phase 4):** Add `getCRCMatchCount()`, `getMismatchCount()`

---

## Change Log

| Date | Phase | Finding | Action Needed |
|------|-------|---------|---------------|
| 2026-02-03 | Foundation | Cataloged all 22 error codes | None - documentation |
| 2026-02-03 | Phase 1.2 | changeDirectory() succeeds on file names | Fix do_chdir() to check ATTR_DIR |
| 2026-02-03 | Phase 1.3 | Pre-mount ops return 0 instead of E_NOT_MOUNTED | Add mount check to V3 APIs |

