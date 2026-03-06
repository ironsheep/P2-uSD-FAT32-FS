# Plan: O-1 through O-11 Test Strengthening

**Release:** v1.2.1
**Date:** 2026-03-05
**Source:** REGRESSION-TEST-COVERAGE-ANALYSIS.md, Tier 1 + Tier 2

---

## Summary

11 strengthening items across 6 existing test files. No new test files needed.
Estimated: ~45 new/modified tests, ~15 new sub-assertions.

---

## O-1: Boundary Value Tests for File Size at Sector Boundaries

**Status:** Mostly done. Tests exist for 0, 1, 512, 513, 64KB.
**Gap:** Missing 511-byte test (just under sector boundary).

**File:** `SD_RT_read_write_tests.spin2`
**Location:** Insert after the "Single byte file" test (line ~379), before "Exact sector boundary" test.

**New test:**
```spin2
' Test: Sector - 1 (511 bytes - just under boundary)
utils.startTest(@"Sector - 1 boundary - 511 bytes")
sd.deleteFile(@testBoundary)
handle := sd.createFileNew(@testBoundary)
if handle >= 0
    utils.fillBufferWithPattern(@writeBuffer, 511, $A0)
    sd.writeHandle(handle, @writeBuffer, 511)
    sd.closeFileHandle(handle)
handle := sd.openFileRead(@testBoundary)
if handle >= 0
    fileSize := sd.fileSizeHandle(handle)
    utils.evaluateSubValue(fileSize, @"fileSize 511 bytes", 511)
    bytefill(@readBuffer, 0, 512)
    utils.initGuard(@readBuffer_guard)
    bytesRead := sd.readHandle(handle, @readBuffer, 511)
    utils.checkGuard(@readBuffer_guard, @"readBuffer guard")
    utils.evaluateSubValue(bytesRead, @"read 511 bytes", 511)
    result := utils.verifyBufferPattern(@readBuffer, 511, $A0)
    utils.evaluateSubBool(result, @"511-byte pattern match", true)
    sd.closeFileHandle(handle)
```

**Impact:** +1 test, +3 sub-assertions.

---

## O-2: Postcondition Checks with tellHandle()

**File:** `SD_RT_read_write_tests.spin2`
**Approach:** Add `tellHandle()` checks after key write and read operations in existing tests.

**Modifications (4 insertions in existing tests):**

1. **After byte-level write (line ~125):** After writing 10 bytes, check `tellHandle() == 10`
2. **After buffer write (line ~200):** After writing 256 bytes, check `tellHandle() == 256`
3. **After 512-byte read (line ~396):** After reading 512 bytes, check `tellHandle() == 512`
4. **After 513-byte second read (line ~423):** After reading byte 513, check `tellHandle() == 513`

Each insertion is a single `utils.evaluateSubValue()` call. Existing tests already use `setCheckCountPerTest()` — need to increment those counts.

**Impact:** +4 sub-assertions in existing tests (no new tests).

---

## O-3: E_NOT_A_DIR_HANDLE Error Coverage

**File:** `SD_RT_dirhandle_tests.spin2`
**Location:** Add to existing "Error Conditions" test group (after line ~291).

**New tests (3):**

```spin2
' Test: readHandle on dir handle returns E_NOT_A_DIR_HANDLE
utils.startTest(@"readHandle on dir handle returns E_NOT_A_DIR_HANDLE")
hDir := sd.openDirectory(@".")
if hDir >= 0
    bytesRead := sd.readHandle(hDir, @readBuffer, 10)
    utils.evaluateSingleValue(bytesRead, @"readHandle(dirH)", sd.E_NOT_A_DIR_HANDLE)
    sd.closeDirectoryHandle(hDir)

' Test: writeHandle on dir handle returns E_NOT_A_DIR_HANDLE
utils.startTest(@"writeHandle on dir handle returns E_NOT_A_DIR_HANDLE")
hDir := sd.openDirectory(@".")
if hDir >= 0
    result := sd.writeHandle(hDir, @dhContent, 10)
    utils.evaluateSingleValue(result, @"writeHandle(dirH)", sd.E_NOT_A_DIR_HANDLE)
    sd.closeDirectoryHandle(hDir)

' Test: seekHandle on dir handle returns E_NOT_A_DIR_HANDLE
utils.startTest(@"seekHandle on dir handle returns E_NOT_A_DIR_HANDLE")
hDir := sd.openDirectory(@".")
if hDir >= 0
    result := sd.seekHandle(hDir, 0)
    utils.evaluateSingleValue(result, @"seekHandle(dirH)", sd.E_NOT_A_DIR_HANDLE)
    sd.closeDirectoryHandle(hDir)
```

**Also test reverse:** readDirectoryHandle on file handle (already tested — returns 0, line ~289).

**Impact:** +3 tests.

---

## O-4: Use-After-Close Comprehensive Test

**File:** `SD_RT_multihandle_tests.spin2`
**Location:** Add new test group after "Invalid Handle Parameters" (line ~440).

**New test group with 1 multi-check test:**

```spin2
' TEST GROUP: Use-After-Close (recently valid handle)
utils.startTestGroup(@"Use-After-Close")

' Create file, open, close, then test all 7 operations on stale handle
utils.startTest(@"All handle ops fail on closed handle")
utils.setCheckCountPerTest(7)
sd.deleteFile(@testfile1)
handle := sd.createFileNew(@testfile1)
if handle >= 0
    sd.writeHandle(handle, @content1, strsize(@content1))
    sd.closeFileHandle(handle)

    ' Now test each operation on the closed handle
    result := sd.readHandle(handle, @readBuffer, 10)
    utils.evaluateSubValue(result, @"readHandle(closed)", sd.E_INVALID_HANDLE)

    result := sd.writeHandle(handle, @content1, 5)
    utils.evaluateSubValue(result, @"writeHandle(closed)", sd.E_INVALID_HANDLE)

    result := sd.seekHandle(handle, 0)
    utils.evaluateSubValue(result, @"seekHandle(closed)", sd.E_INVALID_HANDLE)

    result := sd.tellHandle(handle)
    utils.evaluateSubValue(result, @"tellHandle(closed)", sd.E_INVALID_HANDLE)

    result := sd.fileSizeHandle(handle)
    utils.evaluateSubValue(result, @"fileSizeHandle(closed)", sd.E_INVALID_HANDLE)

    result := sd.eofHandle(handle)
    utils.evaluateSubValue(result, @"eofHandle(closed)", sd.E_INVALID_HANDLE)

    result := sd.syncHandle(handle)
    utils.evaluateSubValue(result, @"syncHandle(closed)", sd.E_INVALID_HANDLE)
utils.showSubTestResults()
utils.setCheckCountPerTest(1)
```

**Impact:** +1 test, +7 sub-assertions.

---

## O-5: Guard Zones for directory_tests and fifo_tests

### SD_RT_directory_tests.spin2

**DAT change:** Add guard after `readBuf`:
```spin2
readBuf         BYTE    0[32]
readBuf_guard   BYTE    0[16]
```

**Code changes:** Add `utils.initGuard(@readBuf_guard)` before reads into readBuf, `utils.checkGuard(@readBuf_guard, @"readBuf guard")` after. Grep for all `sd.readHandle(handle, @readBuf` calls and bracket each.

### SD_RT_fifo_tests.spin2

**DAT change:** Add guard after `resultBuf`:
```spin2
resultBuf       BYTE    0[256]
resultBuf_guard BYTE    0[16]
```

**Code changes:** Add `utils.initGuard(@resultBuf_guard)` before `fifo.get(@resultBuf)` calls, `utils.checkGuard(@resultBuf_guard, @"resultBuf guard")` after.

### SD_RT_subdir_ops_tests.spin2

**No buffers that receive data** — only string literals. No guard zones needed.

**Impact:** Guard zones added to 2 files. No new tests, but overflow protection for ~10 read operations.

---

## O-6: readHandle() at and Past EOF Behavior

**File:** `SD_RT_read_write_tests.spin2`
**Location:** Add to existing "Edge cases" test group (after line ~337) or as new sub-tests.

**New tests (3):**

```spin2
' Test: Read at exact EOF returns 0 bytes
utils.startTest(@"Read at exact EOF returns 0 bytes")
sd.deleteFile(@testBoundary)
handle := sd.createFileNew(@testBoundary)
if handle >= 0
    tempByte := $EE
    sd.writeHandle(handle, @tempByte, 1)
    sd.closeFileHandle(handle)
handle := sd.openFileRead(@testBoundary)
if handle >= 0
    utils.setCheckCountPerTest(3)
    bytesRead := sd.readHandle(handle, @readBuffer, 1)
    utils.evaluateSubValue(bytesRead, @"read 1 byte", 1)
    result := sd.eofHandle(handle)
    utils.evaluateSubBool(result <> 0, @"eofHandle at EOF", true)
    bytesRead := sd.readHandle(handle, @readBuffer, 1)
    utils.evaluateSubValue(bytesRead, @"read at EOF", 0)
    utils.showSubTestResults()
    utils.setCheckCountPerTest(1)
    sd.closeFileHandle(handle)

' Test: eofHandle FALSE before EOF
utils.startTest(@"eofHandle FALSE before EOF")
handle := sd.openFileRead(@testBoundary)
if handle >= 0
    result := sd.eofHandle(handle)
    utils.evaluateBool(result == 0, @"eofHandle before read", true)
    sd.closeFileHandle(handle)

' Test: Partial read when requesting more than remaining
utils.startTest(@"Partial read returns remaining bytes")
handle := sd.openFileRead(@testBoundary)
if handle >= 0
    utils.initGuard(@readBuffer_guard)
    bytesRead := sd.readHandle(handle, @readBuffer, 100)
    utils.checkGuard(@readBuffer_guard, @"readBuffer guard")
    utils.evaluateSingleValue(bytesRead, @"partial read", 1)
    sd.closeFileHandle(handle)
sd.deleteFile(@testBoundary)
```

**Impact:** +3 tests, +3 sub-assertions.

---

## O-7: writeHandle() Postcondition: fileSizeHandle() Growth

**File:** `SD_RT_read_write_tests.spin2`
**Approach:** Add `fileSizeHandle()` checks after writes in existing boundary tests.

**Modifications (3 insertions):**

1. **After 1-byte write (in single byte test):** Check `fileSizeHandle() == 1` before close
2. **After 512-byte write (in exact sector test):** Check `fileSizeHandle() == 512` before close
3. **After 513-byte write (in sector+1 test):** Check `fileSizeHandle() == 513` before close

Each is an `evaluateSubValue` call added before `sd.closeFileHandle(handle)` in the write phase.

**Impact:** +3 sub-assertions in existing tests.

---

## O-8: CRC Diagnostic Verification in recovery_tests

**File:** `SD_RT_recovery_tests.spin2`
**Location:** Modify "Seek and retry after exhaustive CRC error" test (line ~159).

**Approach:** The CRC error is not propagated as E_CRC_ERROR through readHandle (returns 0 bytes instead). But we CAN verify CRC errors were triggered using `getCRCMismatchCount()`.

**Modification:**
```spin2
' Before arming error:
result := sd.getCRCMismatchCount()  ' baseline

' After failed read (line 167):
utils.evaluateSubValue(bytesRead, @"read fails with 0", 0)

' NEW: Verify CRC mismatches were counted
idx := sd.getCRCMismatchCount()
utils.evaluateSubBool(idx > result, @"CRC mismatches counted", true)
```

Increment `setCheckCountPerTest` from 3 to 4.

**Impact:** +1 sub-assertion in existing test.

---

## O-9: Mount/Unmount Cycle with Open Handles

**File:** `SD_RT_mount_tests.spin2`
**Location:** Add new test group at end (before cleanup/END_SESSION).

**New test group:**

```spin2
' TEST GROUP: Use-After-Unmount
utils.startTestGroup(@"Use-After-Unmount")

' Mount, open file, unmount, try stale handle, remount
utils.startTest(@"Stale handle after unmount returns error")
utils.setCheckCountPerTest(3)
sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
handle := sd.openFileRead(@testFilename)

' Unmount while file is open
sd.unmount()

' Try operations on stale handle
result := sd.readHandle(handle, @readBuf, 10)
utils.evaluateSubValue(result, @"readHandle after unmount", sd.E_NOT_MOUNTED)

' Remount and verify clean state
result := sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
utils.evaluateSubValue(result, @"remount succeeds", sd.SUCCESS)

' Open same file on fresh mount
handle := sd.openFileRead(@testFilename)
utils.evaluateSubBool(handle >= 0, @"reopen after remount", true)
if handle >= 0
    sd.closeFileHandle(handle)
utils.showSubTestResults()
utils.setCheckCountPerTest(1)
sd.unmount()
```

**Note:** Need to verify what readHandle returns after unmount. It may be `E_NOT_MOUNTED` or `E_INVALID_HANDLE` depending on how unmount clears handle state. Will need to check driver behavior. If unmount frees handles, then handle becomes invalid -> E_INVALID_HANDLE. If unmount doesn't free handles but driver checks mount state first -> E_NOT_MOUNTED.

**Requires:** A test filename in mount_tests DAT section (may need to add one, or create a file first). Also need to check if mount_tests imports SD_INCLUDE_ALL or has readHandle available.

**Impact:** +1 test, +3 sub-assertions.

---

## O-10: Handle Pool Recycling Across Types

**File:** `SD_RT_multihandle_tests.spin2`
**Location:** Add new test group after "Use-After-Close".

**New test group:**

```spin2
' TEST GROUP: Handle Pool Recycling (file + dir)
utils.startTestGroup(@"Handle Pool Recycling")

utils.startTest(@"Mixed file and dir handles recycle")
utils.setCheckCountPerTest(4)
' Open 4 file handles
h1 := sd.openFileRead(@testfile1)
h2 := sd.openFileRead(@testfile2)
h3 := sd.openFileRead(@testfile3)
h4 := sd.openFileRead(@testfile4)

' Open 2 dir handles (fills pool to 6)
h5 := sd.openDirectory(@".")
utils.evaluateSubBool(h5 >= 0, @"5th handle (dir)", true)

h6 := sd.openDirectory(@".")
utils.evaluateSubBool(h6 >= 0, @"6th handle (dir)", true)

' Close a dir handle and a file handle
sd.closeDirectoryHandle(h5)
sd.closeFileHandle(h2)

' Open new file handle - should get recycled slot
result := sd.openFileRead(@testfile2)
utils.evaluateSubBool(result >= 0, @"recycled file handle", true)
if result >= 0
    sd.closeFileHandle(result)

' Open new dir handle - should get recycled slot
result := sd.openDirectory(@".")
utils.evaluateSubBool(result >= 0, @"recycled dir handle", true)
if result >= 0
    sd.closeDirectoryHandle(result)

' Cleanup
sd.closeFileHandle(h1)
sd.closeFileHandle(h3)
sd.closeFileHandle(h4)
sd.closeDirectoryHandle(h6)
utils.showSubTestResults()
utils.setCheckCountPerTest(1)
```

**Impact:** +1 test, +4 sub-assertions.

---

## O-11: State Transition: Write to Read Handle, Read from Write Handle

**File:** `SD_RT_error_handling_tests.spin2`
**Status:** Partially done.

**Already tested:**
- `writeHandle on read-only handle returns error` -> E_INVALID_HANDLE (line 287)
- `readHandle on write handle allowed` -> returns >= 0 (line 296)

**Missing tests (2):**

```spin2
' Test: tellHandle on dir handle returns E_NOT_A_DIR_HANDLE
utils.startTest(@"tellHandle on dir handle returns error")
hDir := sd.openDirectory(@".")
if hDir >= 0
    result := sd.tellHandle(hDir)
    utils.evaluateSingleValue(result, @"tellHandle(dirH)", sd.E_NOT_A_DIR_HANDLE)
    sd.closeDirectoryHandle(hDir)

' Test: fileSizeHandle on dir handle returns E_NOT_A_DIR_HANDLE
utils.startTest(@"fileSizeHandle on dir handle returns error")
hDir := sd.openDirectory(@".")
if hDir >= 0
    result := sd.fileSizeHandle(hDir)
    utils.evaluateSingleValue(result, @"fileSizeHandle(dirH)", sd.E_NOT_A_DIR_HANDLE)
    sd.closeDirectoryHandle(hDir)
```

**Note:** These overlap with O-3 (dir handle misuse). Place them in error_handling_tests under "Handle Type Mismatch" group. Need to add `hDir` local variable.

**Impact:** +2 tests.

---

## Implementation Order

1. **O-5** — Guard zones (DAT changes, mechanical insertions)
2. **O-1** — 511-byte boundary test (single test addition)
3. **O-2** — tellHandle postconditions (sub-assertion additions)
4. **O-7** — fileSizeHandle postconditions (sub-assertion additions)
5. **O-6** — EOF behavior tests (new tests in read_write)
6. **O-3** — E_NOT_A_DIR_HANDLE tests (new tests in dirhandle)
7. **O-11** — Dir handle type mismatch in error_handling (new tests)
8. **O-4** — Use-after-close (new test group in multihandle)
9. **O-10** — Handle pool recycling (new test group in multihandle)
10. **O-8** — CRC diagnostic verification (modify existing test)
11. **O-9** — Use-after-unmount (new test group in mount_tests) - **do last**, needs most investigation

---

## Files Modified (6)

| File | Changes |
|------|---------|
| `SD_RT_read_write_tests.spin2` | O-1, O-2, O-6, O-7 |
| `SD_RT_multihandle_tests.spin2` | O-4, O-10 |
| `SD_RT_dirhandle_tests.spin2` | O-3 |
| `SD_RT_error_handling_tests.spin2` | O-11 |
| `SD_RT_recovery_tests.spin2` | O-8 |
| `SD_RT_mount_tests.spin2` | O-9 |
| `SD_RT_directory_tests.spin2` | O-5 (guards) |
| `SD_RT_fifo_tests.spin2` | O-5 (guards) |

---

## Pre-Implementation Checks Needed

1. **O-9:** What does readHandle() return after unmount? Check if unmount clears handles or if driver checks mount state first. Verify mount_tests has needed DAT variables and includes.
2. **O-5 (directory_tests):** Find all `readHandle(..., @readBuf, ...)` calls to bracket with guards.
3. **O-5 (fifo_tests):** Find all `fifo.get(@resultBuf)` calls to bracket with guards.

---

## Estimated Impact

| Metric | Before | Added | After |
|--------|--------|-------|-------|
| Tests | 397 | ~14 | ~411 |
| Sub-assertions | 271 | ~25 | ~296 |
| Guard-protected suites | 17/20 | +2 | 19/20 |
| Error codes tested | 8/22 | +1 (E_NOT_A_DIR_HANDLE) | 9/22 |

---

*Plan produced 2026-03-05. Implementation order optimized for mechanical-first, investigation-last.*
