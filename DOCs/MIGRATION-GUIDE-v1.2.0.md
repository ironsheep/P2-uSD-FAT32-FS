# Migration Guide -- P2-uSD-FAT32-FS v1.2.0

If you have code written for P2-uSD-FAT32-FS v1.0.0 or v1.1.0, this guide covers the changes needed for v1.2.0 compatibility.

---

## What Changed

Nine core filesystem PUB methods that previously returned `true` (success) or `false` (failure) now return `SUCCESS` (0) on success or a negative error code on failure. This makes them consistent with the handle-based API, which already returned error codes.

**The key behavior change:** `SUCCESS` is 0, which is **falsy** in Spin2. Code that tests `if sd.mount(...)` (expecting non-zero = success) will silently break because SUCCESS is now 0.

---

## Affected Methods

| Method | Old Return | New Return |
|--------|-----------|------------|
| `mount()` | `true` / `false` | `SUCCESS` (0) / negative error code |
| `unmount()` | `true` / `false` | `SUCCESS` (0) / negative error code |
| `sync()` | `true` / `false` | `SUCCESS` (0) / negative error code |
| `newDirectory()` | `true` / `false` | `SUCCESS` (0) / `E_FILE_EXISTS` / `E_FILE_NOT_FOUND` |
| `changeDirectory()` | `true` / `false` | `SUCCESS` (0) / `E_NOT_A_DIR` |
| `deleteFile()` | `true` / `false` | `SUCCESS` (0) / `E_FILE_NOT_FOUND` |
| `rename()` | `true` / `false` | `SUCCESS` (0) / `E_FILE_NOT_FOUND` / `E_FILE_EXISTS` |
| `moveFile()` | `true` / `false` | `SUCCESS` (0) / `E_FILE_NOT_FOUND` / `E_FILE_EXISTS` |
| `setVolumeLabel()` | `true` / `false` | `SUCCESS` (0) / `E_IO_ERROR` |

---

## How to Update Your Code

### Pattern 1: Success check after mount/unmount/sync

```spin2
' BEFORE (v1.0/v1.1):
result := sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
if result
    debug("Mounted!")

' AFTER (v1.2):
result := sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
if result == sd.SUCCESS
    debug("Mounted!")
```

### Pattern 2: Failure check with `if not`

```spin2
' BEFORE:
if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    debug("Mount failed!")
    return

' AFTER:
if sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK) < 0
    debug("Mount failed!")
    return
```

### Pattern 3: Inline failure check

```spin2
' BEFORE:
if sd.changeDirectory(@"LOGS") == false
    sd.newDirectory(@"LOGS")

' AFTER:
if sd.changeDirectory(@"LOGS") < 0
    sd.newDirectory(@"LOGS")
```

### Pattern 4: Specific error codes (new capability)

With v1.2.0, you can now distinguish *why* an operation failed without calling `sd.error()` separately:

```spin2
' NEW: Check specific error codes
result := sd.deleteFile(@"DATA.TXT")
if result == sd.E_FILE_NOT_FOUND
    debug("File doesn't exist -- nothing to delete")
elseif result < 0
    debug("Delete failed with error: ", sdec_(result))
```

### Pattern 5: Ignored return values (no change needed)

If you call a method without checking its return value, no change is required:

```spin2
' These are fine as-is:
sd.deleteFile(@"TEMP.TXT")        ' Cleanup -- don't care if it fails
sd.changeDirectory(@"..")          ' Navigate up -- no check
```

---

## Methods NOT Affected

These methods are unchanged:

- **Handle-based API** (`openFileRead`, `openFileWrite`, `createFileNew`, `readHandle`, `writeHandle`, `seekHandle`, `closeFileHandle`) -- already returned error codes
- **Boolean query methods** (`eofHandle`, `isHighSpeedActive`, `checkCMD6Support`, `checkHighSpeedCapability`, `attemptHighSpeed`, `checkStackGuard`) -- these ask true/false questions and remain boolean
- **Info methods** (`freeSpace`, `volumeLabel`, `error`, `fileSize`, etc.) -- unchanged

---

## Error Code Reference

The following error codes may be returned by the affected methods:

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `SUCCESS` | Operation completed successfully |
| -1 | `E_TIMEOUT` | Card did not respond in time |
| -7 | `E_IO_ERROR` | General I/O error during read/write |
| -20 | `E_NOT_MOUNTED` | Filesystem not mounted |
| -21 | `E_INIT_FAILED` | Card initialization failed |
| -22 | `E_NOT_FAT32` | Card not formatted as FAT32 |
| -40 | `E_FILE_NOT_FOUND` | File or directory does not exist |
| -41 | `E_FILE_EXISTS` | File or directory already exists |
| -43 | `E_NOT_A_DIR` | Expected directory, found file (or not found) |
| -60 | `E_DISK_FULL` | No free clusters available |
| -64 | `E_NO_LOCK` | Could not allocate hardware lock |

All error code constants are accessible as `sd.E_xxx` and `sd.SUCCESS` from the driver object.

---

## Quick Search-and-Replace Guide

Run these searches across your codebase to find patterns that need updating:

1. **`if sd.mount(`** or **`if (sd.mount(`** -- success check, needs `== sd.SUCCESS`
2. **`if not sd.mount(`** -- failure check, change to `sd.mount(...) < 0`
3. **`== true`** or **`== false`** after any affected method -- replace with `== sd.SUCCESS` or `< 0`
4. **`result := sd.mount(` ... `if result`** -- change guard to `if result == sd.SUCCESS`

---

## Conditionally-Compiled Methods

If you use `SD_INCLUDE_RAW` or `SD_INCLUDE_REGISTERS`, these methods also changed:

| Method | Gate Flag |
|--------|-----------|
| `initCardOnly()` | `SD_INCLUDE_RAW` |
| `readSectorRaw()` | `SD_INCLUDE_RAW` |
| `writeSectorRaw()` | `SD_INCLUDE_RAW` |
| `readVBRRaw()` | `SD_INCLUDE_RAW` |
| `readCIDRaw()` | `SD_INCLUDE_REGISTERS` |
| `readCSDRaw()` | `SD_INCLUDE_REGISTERS` |
| `readSCRRaw()` | `SD_INCLUDE_REGISTERS` |
| `readSDStatusRaw()` | `SD_INCLUDE_REGISTERS` |

Same pattern: `true`/`false` changed to `SUCCESS`/negative error code. Apply the same code transformations shown above.
