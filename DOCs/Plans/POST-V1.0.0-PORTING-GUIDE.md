# Post-v1.0.0 Porting Guide

**Purpose**: Detailed implementation guide for porting all changes made to `P2-uSD-FAT32-FS` since the v1.0.0 release (Feb 25, 2026) into the flash-integrated driver variant.

**Baseline**: v1.0.0 tag (`54121d8`)
**Head**: Current `main` (Feb 27, 2026)
**Commits**: 10 + readVBRRaw cross-ifdef fix

---

## Table of Contents

1. [Bug Fix: readVBRRaw() calls SPI from wrong cog](#1-bug-fix-readvbrraw-calls-spi-from-wrong-cog)
2. [Bug Fix: Unsigned FAT32 end-of-chain comparisons](#2-bug-fix-unsigned-fat32-end-of-chain-comparisons)
3. [Enhancement: Volume label scan follows root cluster chain](#3-enhancement-volume-label-scan-follows-root-cluster-chain)
4. [Enhancement: entry_buffer typed as dir_entry_t struct](#4-enhancement-entry_buffer-typed-as-dir_entry_t-struct)
5. [Enhancement: Struct accessor doc comments](#5-enhancement-struct-accessor-doc-comments)
6. [Cleanup: CON section doc comments changed to regular comments](#6-cleanup-con-section-doc-comments-changed-to-regular-comments)
7. [Enhancement: Windowed bitmap FSCK for large cards](#7-enhancement-windowed-bitmap-fsck-for-large-cards)
8. [Cross-compiler: Multi-compiler PRAGMA blocks](#8-cross-compiler-multi-compiler-pragma-blocks)
9. [Cross-compiler: flexspin line-continuation workaround](#9-cross-compiler-flexspin-line-continuation-workaround)
10. [Test Fix: CRC diagnostic test expectation](#10-test-fix-crc-diagnostic-test-expectation)
11. [Test: New readVBRRaw() regression coverage](#11-test-new-readvbrraw-regression-coverage)
12. [Test: New windowed FSCK diagnostic test](#12-test-new-windowed-fsck-diagnostic-test)
13. [Misc: Version bump and .txt removal](#13-misc-version-bump-and-txt-removal)

---

## 1. Bug Fix: readVBRRaw() calls SPI from wrong cog

**Severity**: Critical (broken since introduced in commit `e785add`, Jan 20, 2026)
**Commits**: `8c410c6`, then refined in subsequent fix
**File**: `src/micro_sd_fat32_fs.spin2`

### Problem

`readVBRRaw()` called `readSector()` directly. But `readSector()` issues SPI commands, and SPI is owned by the worker cog. When a calling cog invokes `readVBRRaw()`, the SPI operations execute on the calling cog — which doesn't own the SPI pins. The call silently returns garbage data.

### Complication: Cross-ifdef dependency

`readVBRRaw()` lives inside `#IFDEF SD_INCLUDE_REGISTERS`. The initial fix called `readSectorRaw()`, but that public method is inside `#IFDEF SD_INCLUDE_RAW`. When a consumer defines `SD_INCLUDE_REGISTERS` + `SD_INCLUDE_SPEED` but NOT `SD_INCLUDE_RAW`, the compiler can't find `readSectorRaw()`. This caused SD_RT_speed_tests to fail to compile.

### Fix (three parts)

**Part A** — Move `CMD_READ_SECTOR_RAW` constant out of the `#IFDEF SD_INCLUDE_RAW` block to be always defined:

```spin2
' BEFORE: CMD_READ_SECTOR_RAW was inside #IFDEF SD_INCLUDE_RAW
' AFTER:  CMD_READ_SECTOR_RAW is unconditional (before the #IFDEF SD_INCLUDE_RAW block)
  CMD_READ_SECTOR_RAW  = 20 ' Raw single sector read (always available for readVBRRaw)

#IFDEF SD_INCLUDE_RAW
  CMD_INIT_CARD_ONLY = 22
  ...
  CMD_WRITE_SECTOR_RAW = 21  ' Write stays inside RAW ifdef
#ENDIF
```

**Part B** — Move the `CMD_READ_SECTOR_RAW` dispatch handler out of the `#IFDEF SD_INCLUDE_RAW` block in `fs_worker()`:

```spin2
' This handler is now BEFORE the #IFDEF SD_INCLUDE_RAW block in the case statement:
      CMD_READ_SECTOR_RAW:
        sec_in_buf := -1
        if readSector(pb_param0, BUF_DATA) == 0
          bytemove(pb_param1, @buf, 512)
          pb_status := SUCCESS
        else
          pb_status := E_IO_ERROR

#IFDEF SD_INCLUDE_RAW
      CMD_READ_SECTORS:
        ...
```

**Part C** — `readVBRRaw()` uses `send_command()` directly (not `readSectorRaw()`):

```spin2
' BEFORE (v1.0.0 — broken, direct SPI from calling cog):
PUB readVBRRaw(p_buf) : result
  if not (flags & F_MOUNTED)
    return false
  sec_in_buf := -1
  if readSector(vbr_sec, BUF_DATA) < 0
    return false
  bytemove(p_buf, @buf, 512)
  return true

' AFTER (fixed — routes through worker cog, no cross-ifdef dependency):
PUB readVBRRaw(p_buf) : result
  if not (flags & F_MOUNTED)
    debug("  [readVBRRaw] FAILED: Card not mounted")
    return false
  result := send_command(CMD_READ_SECTOR_RAW, vbr_sec, p_buf, 0, 0) == SUCCESS
```

### Why send_command() instead of readSectorRaw()

`readSectorRaw()` is a public API method gated behind `#IFDEF SD_INCLUDE_RAW`. But `send_command()` and `CMD_READ_SECTOR_RAW` are both unconditional (always compiled). This avoids any cross-ifdef dependency while still routing through the worker cog mailbox correctly.

### Location in driver

- **CON section**: `CMD_READ_SECTOR_RAW = 20` — moved before `#IFDEF SD_INCLUDE_RAW`
- **fs_worker() dispatch**: `CMD_READ_SECTOR_RAW:` handler — moved before `#IFDEF SD_INCLUDE_RAW`
- **readVBRRaw()**: Inside `#IFDEF SD_INCLUDE_REGISTERS`. Search for `PUB readVBRRaw`

---

## 2. Bug Fix: Unsigned FAT32 end-of-chain comparisons

**Severity**: High (potential misinterpretation of FAT entries on large cards)
**Commit**: `12e66ab`
**File**: `src/micro_sd_fat32_fs.spin2`

### Problem

FAT32 cluster values are unsigned 28-bit values. The end-of-chain markers are `$0FFF_FFF8` through `$0FFF_FFFF`. Spin2's `>=` and `<` operators are signed comparisons. On cards where cluster values or FAT entries have bit 31 set in the full 32-bit LONG (the upper 4 bits are "reserved" per the FAT spec), signed comparison gives wrong results.

### Fix

Change **8 locations** from signed to unsigned comparison operators:

| Signed (before) | Unsigned (after) | Meaning |
|---|---|---|
| `>= $0FFF_FFF8` | `+>= $0FFF_FFF8` | End-of-chain test |
| `< $0FFF_FFF8` | `+< $0FFF_FFF8` | Not-end-of-chain test |

### All 8 locations (search for these patterns)

1. **`do_open_write()`** — seeking to end of existing file's cluster chain:
   ```spin2
   ' BEFORE:  if current_cluster >= $0FFF_FFF8
   ' AFTER:   if current_cluster +>= $0FFF_FFF8
   ```

2. **`do_read_h()`** — boundary advance (first occurrence):
   ```spin2
   ' BEFORE:  if next_cluster >= $0FFF_FFF8
   ' AFTER:   if next_cluster +>= $0FFF_FFF8
   ```

3. **`do_read_h()`** — mid-read cluster advance (second occurrence):
   ```spin2
   ' BEFORE:  if next_cluster >= $0FFF_FFF8
   ' AFTER:   if next_cluster +>= $0FFF_FFF8
   ```

4. **`do_seek_h()`** — following chain to target cluster:
   ```spin2
   ' BEFORE:  if cluster >= $0FFF_FFF8
   ' AFTER:   if cluster +>= $0FFF_FFF8
   ```

5. **`do_read_dir_h()`** — advancing to next directory cluster:
   ```spin2
   ' BEFORE:  if next_cluster >= $0FFF_FFF8
   ' AFTER:   if next_cluster +>= $0FFF_FFF8
   ```

6. **`do_delete()`** — walking chain to free clusters:
   ```spin2
   ' BEFORE:  until cluster >= $0FFF_FFF8
   ' AFTER:   until cluster +>= $0FFF_FFF8
   ```

7. **`readNextSector()`** — detecting end-of-chain in sequential reads:
   ```spin2
   ' BEFORE:  if contents >= $0FFF_FFF8
   ' AFTER:   if contents +>= $0FFF_FFF8
   ```

8. **`followFatChain()`** — advancing the current chain pointer:
   ```spin2
   ' BEFORE:  if contents < $0FFF_FFF8
   ' AFTER:   if contents +< $0FFF_FFF8
   ```

### How to find them

Search for `$0FFF_FFF8` in the driver. Every comparison against this value must use unsigned operators (`+>=`, `+<`, `+>`). There should be zero instances of signed `>=` or `<` against this value.

---

## 3. Enhancement: Volume label scan follows root cluster chain

**Severity**: Enhancement (functional improvement)
**Commit**: `75aacef`
**File**: `src/micro_sd_fat32_fs.spin2`, method `do_mount()`

### Problem

`do_mount()` only read the volume label from the VBR's `volLabel` field. Windows format writes `"NO NAME    "` to the VBR even when the user sets a label. The authoritative volume label per the FAT32 spec is a directory entry with `ATTR_VOLUME_ID` (`$08`) in the root directory.

The previous code only searched the VBR. Additionally, on large cards the volume label entry may not be in the first cluster of the root directory (it can be in any cluster of the chain).

### Fix

After reading the VBR copy, scan root directory entries for `ATTR_VOLUME_ID`. Follow the root directory cluster chain (not just the first cluster). If found, overwrite `vol_label` with the root directory version.

### New code

Insert this block after the existing line `vol_label[11] := 0` and the VBR label debug message. This replaces the simple `debug("  [do_mount] Volume label: ", zstr(@vol_label))` line.

Additional local variables needed in `do_mount()`: `i, p_entry, cluster, sector, sec_idx, next_cluster, found`

```spin2
  debug("  [do_mount] VBR volume label: ", zstr(@vol_label))

  ' Check root directory for authoritative volume label entry (ATTR_VOLUME_ID)
  ' The root directory entry is the primary source per the FAT32 spec;
  ' the VBR copy is a fallback (Windows format may write "NO NAME" to VBR).
  ' Follow the root cluster chain so we find the label even if it's not in the first sector.
  cluster := 2
  found := false
  repeat while cluster >= 2 and cluster +< $0FFF_FFF8 and not found
    sector := clus2sec(cluster)
    repeat sec_idx from 0 to sec_per_clus - 1
      if readSector(sector + sec_idx, BUF_DIR) < 0
        debug("  [do_mount] Root dir read failed, using VBR label")
        found := true
        quit
      repeat i from 0 to 15
        p_entry := @dir_buf + (i * 32)
        if byte[p_entry] == $00                                                        '  end of directory
          found := true
          quit
        if byte[p_entry] <> $E5 and dirEntAttr(p_entry) == $08                         '  volume label entry
          bytemove(@vol_label, p_entry, 11)
          vol_label[11] := 0
          debug("  [do_mount] Root dir volume label: ", zstr(@vol_label))
          found := true
          quit
      if found
        quit
    ' Follow FAT chain to next cluster
    if not found
      if readSector(cluster >> 7 + fat_sec, BUF_FAT) < 0
        quit
      next_cluster := LONG[@fat_buf + ((cluster << 2) & 511)]
      cluster := next_cluster
```

### Notes

- The `cluster +< $0FFF_FFF8` uses the unsigned comparison from change #2.
- `cluster := 2` is the root directory start cluster (always cluster 2 in FAT32).
- The `found` flag is needed because Spin2 doesn't have `break` from nested loops.
- 16 entries per sector (512 / 32 = 16).
- `$E5` means deleted entry (skip), `$00` means end of directory.

---

## 4. Enhancement: entry_buffer typed as dir_entry_t struct

**Severity**: Enhancement (type safety, no behavioral change)
**Commit**: `8c410c6`
**File**: `src/micro_sd_fat32_fs.spin2`

### Problem

`entry_buffer` was declared as `BYTE 0[32]` in DAT. The struct accessors (`dirEntAttr()`, etc.) use typed pointers (`^dir_entry_t`), but code in `searchDirectory()` and `displayEntry()` accessed `entry_buffer` with raw byte indexing (`entry_buffer[i]`). This worked but was inconsistent and fragile.

### Fix — Part A: DAT declaration

**Before**:
```spin2
  entry_buffer  BYTE    0[32]           ' Directory entry buffer
```

**After**:
```spin2
  entry_buffer  dir_entry_t
                BYTE    0[14]           ' name[8], ext[3], attr, ntRes, crtTenth
                WORD    0[7]            ' crtTime, crtDate, accDate, clusHI, wrtTime, wrtDate, clusLO
                LONG    0              ' fileSize
```

The struct type tag (`dir_entry_t`) makes `@entry_buffer` return a typed pointer. The subsequent `BYTE`, `WORD`, `LONG` lines reserve the actual storage matching the struct layout (total = 32 bytes, same as before).

### Fix — Part B: searchDirectory() byte access

In `searchDirectory()`, 4 places change from `entry_buffer[i]` to `BYTE[@entry_buffer][i]`:

1. Uppercase conversion:
   ```spin2
   ' BEFORE:  case entry_buffer[i]
   '            "a".."z" : entry_buffer[i] -= $20
   ' AFTER:   case BYTE[@entry_buffer][i]
   '            "a".."z" : BYTE[@entry_buffer][i] -= $20
   ```

2. Extension dot search:
   ```spin2
   ' BEFORE:  if entry_buffer[i++] == "."
   ' AFTER:   if BYTE[@entry_buffer][i++] == "."
   ```

3. Null terminator:
   ```spin2
   ' BEFORE:  entry_buffer[11] := $00
   ' AFTER:   BYTE[@entry_buffer][11] := $00
   ```

### Fix — Part C: displayEntry() byte access

In `displayEntry()` (inside `#IFDEF SD_INCLUDE_DEBUG`):

```spin2
' BEFORE:  case char := (entry_buffer[address + i])
' AFTER:   case char := (BYTE[@entry_buffer][address + i])
```

### Why this matters

When `entry_buffer` is a raw `BYTE` array, `entry_buffer[i]` accesses byte `i` directly. When it's declared with a struct type, `entry_buffer[i]` would index by the struct size (32 bytes), not by byte. Using `BYTE[@entry_buffer][i]` explicitly dereferences by byte regardless of the declared type.

---

## 5. Enhancement: Struct accessor doc comments

**Severity**: Documentation only (no code change)
**Commit**: `8c410c6`
**File**: `src/micro_sd_fat32_fs.spin2`

### What changed

22 PRI struct accessor methods gained doc comments. These are the helper methods in the "STRUCT ACCESSOR HELPERS" section that wrap pnut-ts struct field access.

### Pattern

Each method got a comment block with `@param`, `@returns`, and description. Example:

```spin2
PRI partType(^mbr_partition_t pPart) : value
' Get partition type code from MBR partition entry.
'
' @param pPart - Pointer to MBR partition entry
' @returns value - Partition type code ($0B/$0C = FAT32)

  return pPart.partType
```

**Note**: These use single-apostrophe `'` (regular comments), not double-apostrophe `''` (doc comments), because they are PRI methods.

### Full list of methods that got doc comments

`partType`, `partLbaStart`, `vbrBytesPerSec`, `vbrSecPerClus`, `vbrReservedSec`, `vbrNumFats`, `vbrSecPerFat32`, `vbrFsInfoSec`, `vbrVolLabelAddr`, `fsiLeadSig`, `fsiStructSig`, `fsiFreeClusters`, `fsiNextFreeHint`, `fsiSetFreeClusters`, `fsiSetNextFreeHint`, `dirEntAttr`, `dirEntStartClus`, `dirEntFileSize`, `dirEntSetAttr`, `dirEntSetStartClus`, `dirEntSetFileSize`, `dirEntAddFileSize`, `dirEntSetCreateStamp`, `dirEntSetModifyStamp`

### Porting note

These are nice-to-have. If the flash-integrated driver has the same accessor methods, copy the comments. If the method signatures differ, adapt accordingly. This is **lowest priority** for porting.

---

## 6. Cleanup: CON section doc comments changed to regular comments

**Severity**: Documentation only (prevents leaking into .txt auto-docs)
**Commit**: `8c410c6`
**File**: `src/micro_sd_fat32_fs.spin2`

### What changed

All `CON` section header comments and separator lines were changed from `''` (doc comments) to `'` (regular comments). The pnut-ts compiler captures `''` comments in auto-generated `.txt` documentation files. CON section internal comments should not appear in user-facing docs.

### Scope

~26 locations throughout the driver. Every `CON '' ...` line becomes `CON ' ...`. Every `'' ═══` separator becomes `' ═══`.

### How to find them

Search for `CON  ''` or standalone `'' ═══` lines inside CON sections. Change `''` to `'`.

**Examples**:
```spin2
' BEFORE: CON  '' flags
' AFTER:  CON  ' flags

' BEFORE: CON '' error codes
' AFTER:  CON ' error codes

' BEFORE: '' ═══════════════════════════════════════════════════
' AFTER:  ' ═══════════════════════════════════════════════════
```

Also, the `#IFDEF SD_INCLUDE_ALL` block lost its indentation (2-space indent removed from `#IFNDEF`/`#DEFINE`/`#ENDIF` lines). This was a formatting cleanup done in the same commit.

### Porting note

**Low priority**. This is cosmetic and only matters if you generate `.txt` documentation from the driver. If the flash-integrated driver doesn't use auto-doc generation, skip this.

---

## 7. Enhancement: Windowed bitmap FSCK for large cards

**Severity**: Enhancement (enables FSCK on cards > 64 GB)
**Commit**: `dd33908`
**File**: `src/UTILS/isp_fsck_utility.spin2`

### Problem

The FSCK bitmap (`BITMAP_LONGS = 65536` = 256 KB) can track at most `65536 * 32 = 2,097,152` clusters. Cards > 64 GB have more clusters than this, so FSCK skipped passes 2 and 3 entirely with a warning.

### Solution: Windowed bitmap processing

Instead of requiring the bitmap to cover all clusters at once, process the cluster space in "windows" of up to 2M clusters each. For each window:

1. Clear the bitmap
2. Re-walk the entire directory tree, but only mark/check clusters that fall within the current window
3. Run lost-cluster recovery (pass 3) for that window
4. Move to next window

### Structural changes

**Removed variables**:
- `bitmapCapable` (no longer needed — all cards are supported)

**New variables** (in VAR section):
```spin2
LONG    v_lostCount           ' running count of lost clusters freed
LONG    windowStart           ' first cluster in current bitmap window
LONG    windowEnd             ' last cluster+1 in current window (exclusive)
LONG    currentWindow         ' current window index (0-based)
LONG    windowCount           ' total windows needed
```

**`runFsck()` changes**:
- Remove `bitmapCapable` logic and the "deep scan skipped" warning
- Remove separate calls to `fsckPass2()` and `fsckPass3()`
- Call only `fsckPass2()` (which now internally calls `fsckPass3Window()` per window)
- Remove `if bitmapCapable` guards around summary output

**`fsckPass2()` — major rewrite**:
- Compute `windowCount := (totalClusters + 2 + MAX_BITMAP_CLUSTERS - 1) / MAX_BITMAP_CLUSTERS`
- Outer loop: `repeat currentWindow from 0 to windowCount - 1`
- Per window: set `windowStart`, `windowEnd`, clear bitmap, mark clusters 0/1 only in first window
- Reset `v_dirCount`/`v_fileCount` only on first window
- Call `fsckValidateChain()` for root, then `fsckScanDir()`, then `fsckPass3Window()`
- After all windows: report lost cluster count, combined repair count

**`fsckScanDir()` — conditional on window index**:
- Only increment `v_dirCount`/`v_fileCount` on `currentWindow == 0`
- Only report errors on `currentWindow == 0`
- Bitmap marking always happens (every window)

**`fsckValidateChain()` — conditional on window index**:
- Only report errors and perform repairs on `currentWindow == 0`
- Bitmap marking always happens (every window)
- File chain length vs expected size check only on `currentWindow == 0`

**`fsckPass3()` renamed to `fsckPass3Window()`**:
- No longer prints its own header/summary (parent prints combined summary)
- Scans only `windowStart..windowEnd` range
- Uses `v_lostCount` (instance variable) instead of local `lostCount`
- Still calls `flushFAT()` after each window

**`setBit()` and `testBit()` — window-relative indexing**:
```spin2
PRI setBit(cluster) | idx
  if cluster < windowStart or cluster >= windowEnd
    return
  idx := cluster - windowStart
  bitmapData[idx >> 5] |= (1 << (idx & $1F))

PRI testBit(cluster) : result | idx
  if cluster < windowStart or cluster >= windowEnd
    return false
  idx := cluster - windowStart
  result := (bitmapData[idx >> 5] >> (idx & $1F)) & 1
```

### Porting note

If the flash-integrated driver has FSCK, this is a significant change. The key insight is: `setBit()` and `testBit()` now silently ignore clusters outside the current window, so the directory walk code doesn't need to know about windows — it just calls the same bitmap functions.

---

## 8. Cross-compiler: Multi-compiler PRAGMA blocks

**Severity**: Compatibility (enables building with Spin Tools IDE and flexspin)
**Commit**: `8adf4b5`
**Files**: All `.spin2` files that use `#PRAGMA EXPORTDEF`

### Problem

`#PRAGMA EXPORTDEF` is pnut-ts-specific. Spin Tools IDE uses `#DEFINE`, and flexspin uses `#define` (lowercase) plus `#pragma exportdef` (lowercase).

### Fix pattern

Every `#PRAGMA EXPORTDEF` gets wrapped in a compiler-detection block:

**Before**:
```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_ALL
```

**After**:
```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_ALL
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#ELSE
#PRAGMA EXPORTDEF SD_INCLUDE_ALL
#ENDIF
```

For files that export multiple flags, each flag needs its own `#define` + `#pragma exportdef` pair inside the `__FLEXSPIN__` block:

```spin2
#IFDEF __SPINTOOLS__
#DEFINE SD_INCLUDE_RAW
#DEFINE SD_INCLUDE_DEBUG
#ELSEIFDEF __FLEXSPIN__
#define SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG
#ELSE
#PRAGMA EXPORTDEF SD_INCLUDE_RAW
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG
#ENDIF
```

### Files affected (20 files total)

**Driver**: `src/micro_sd_fat32_fs.spin2` (the `#IFDEF SD_INCLUDE_ALL` expansion block — indentation removed)

**Regression tests** (11 files):
- `SD_RT_crc_diag_tests.spin2`
- `SD_RT_error_handling_tests.spin2`
- `SD_RT_file_ops_tests.spin2`
- `SD_RT_format_tests.spin2`
- `SD_RT_mount_tests.spin2`
- `SD_RT_multiblock_tests.spin2`
- `SD_RT_raw_sector_tests.spin2`
- `SD_RT_register_tests.spin2`
- `SD_RT_speed_tests.spin2`
- `SD_RT_subdir_ops_tests.spin2`
- `SD_RT_volume_tests.spin2`

**Diagnostic tests** (3 files):
- `SD_card_info_tests.spin2`
- `SD_freq_sweep_tests.spin2`
- `SD_spi_limit_test.spin2`

**Utilities** (5 files):
- `SD_card_characterize.spin2`
- `SD_format_card.spin2`
- `SD_frequency_characterize.spin2`
- `SD_performance_benchmark.spin2`
- `SD_speed_characterize.spin2`

**Libraries** (2 files):
- `isp_format_utility.spin2`
- `isp_fsck_utility.spin2`

**Demo**:
- `SD_demo_shell.spin2`

### Driver-specific change

In the driver itself, the `#IFDEF SD_INCLUDE_ALL` expansion block also had indentation removed (2-space indent stripped from `#IFNDEF`/`#DEFINE`/`#ENDIF` directives). This is cosmetic but notable if doing exact diffs.

---

## 9. Cross-compiler: flexspin line-continuation workaround

**Severity**: Compatibility (flexspin-specific)
**Commit**: `31348e4`
**File**: `src/UTILS/isp_format_utility.spin2`

### Problem

flexspin has a bug with the `...` line-continuation syntax inside `debug()` calls. Multi-line debug statements that use `...` fail to compile.

### Fix

Wrap the affected `debug()` calls in `#IFDEF __FLEXSPIN__` blocks that provide single-line alternatives:

```spin2
#IFDEF __FLEXSPIN__
    debug("  MBR readback: sig=$", uhex_word_(WORD[@verifyBuf + $1FE]), " type=$", uhex_byte_(verifyBuf[$1C2]), " start=", udec_(LONG[@verifyBuf + $1C6]))
    debug("  MBR read[0..7]: $", uhex_byte_(verifyBuf[0]), " $", uhex_byte_(verifyBuf[1]), " $", uhex_byte_(verifyBuf[2]), " $", uhex_byte_(verifyBuf[3]), " $", uhex_byte_(verifyBuf[4]), " $", uhex_byte_(verifyBuf[5]), " $", uhex_byte_(verifyBuf[6]), " $", uhex_byte_(verifyBuf[7]))
#ELSE
    debug("  MBR readback: sig=$", uhex_word_(WORD[@verifyBuf + $1FE]), ...
      " type=$", uhex_byte_(verifyBuf[$1C2]), ...
      " start=", udec_(LONG[@verifyBuf + $1C6]))
    debug("  MBR read[0..7]: $", uhex_byte_(verifyBuf[0]), " $", uhex_byte_(verifyBuf[1]), ...
      " $", uhex_byte_(verifyBuf[2]), " $", uhex_byte_(verifyBuf[3]), ...
      " $", uhex_byte_(verifyBuf[4]), " $", uhex_byte_(verifyBuf[5]), ...
      " $", uhex_byte_(verifyBuf[6]), " $", uhex_byte_(verifyBuf[7]))
#ENDIF
```

### Locations in isp_format_utility.spin2

Three `#IFDEF __FLEXSPIN__` blocks added:

1. **`doFormat()` — MBR readback verification** (~2 debug lines)
2. **`doFormat()` — VBR readback verification** (~1 debug line)
3. **`writeMBR()` — MBR write buffer diagnostic** (~2 debug lines)

### Porting note

Only needed if the flash-integrated driver includes `isp_format_utility.spin2` and you want flexspin compatibility.

---

## 10. Test Fix: CRC diagnostic test expectation

**Severity**: Test correctness
**Commit**: `8a5ad88` (partially — the diagnostic expectation was the fsck test; this CRC fix was in `8c410c6`)
**File**: `regression-tests/SD_RT_crc_diag_tests.spin2`

### Problem

The test checked `lastReceivedCRC != 0` after mount. But CRC can legitimately be `$0000` if the last sector read during mount happened to be all zeros (e.g., an empty FAT sector). The test was fragile.

### Fix

Instead of checking that the received CRC is non-zero, check that received CRC equals calculated CRC (i.e., the CRC pair is consistent):

**Before**:
```spin2
    ' Test: lastReceivedCRC != 0 (mount performed reads)
    utils.startTest(@"lastReceivedCRC != 0 after mount")
    lastRecvCRC := sd.getLastReceivedCRC()
    debug("   Last received CRC: $", uhex_(lastRecvCRC))
    utils.evaluateNotZero(lastRecvCRC, @"lastReceivedCRC")
```

**After**:
```spin2
    ' Test: lastReceivedCRC == lastCalculatedCRC (CRC pair consistent after mount)
    ' Note: CRC may be $0000 if last sector read was all zeros (e.g., empty FAT sector)
    utils.startTest(@"lastReceivedCRC == lastCalculatedCRC after mount")
    lastRecvCRC := sd.getLastReceivedCRC()
    lastCalcCRC := sd.getLastCalculatedCRC()
    debug("   Last received CRC: $", uhex_(lastRecvCRC), " calculated: $", uhex_(lastCalcCRC))
    utils.evaluateSingleValue(lastRecvCRC, @"recv == calc CRC", lastCalcCRC)
```

---

## 11. Test: New readVBRRaw() regression coverage

**Severity**: New test coverage
**Commit**: `8c410c6`
**File**: `regression-tests/SD_RT_volume_tests.spin2`

### Changes

1. **File header comment** updated: removed "readVBRRaw is broken" note, now says `readVBRRaw() and readSectorRaw()`

2. **New buffer** in DAT section:
   ```spin2
   vbrBuf2         BYTE    0[512]
   vbrBuf2_guard   BYTE    0[16]
   ```

3. **Test group renamed**: `"VBR Access via readSectorRaw"` → `"VBR Access"`

4. **Workaround comments removed**: The block that said "NOTE: readVBRRaw() is broken" was deleted.

5. **Two new tests added** after the existing VBR OEM name test:

   ```spin2
   ' Test: readVBRRaw() returns valid VBR
   utils.startTest(@"readVBRRaw() succeeds")
   bytefill(@vbrBuf2, 0, 512)
   utils.initGuard(@vbrBuf2_guard)
   result := sd.readVBRRaw(@vbrBuf2)
   utils.checkGuard(@vbrBuf2_guard, @"vbrBuf2 guard")
   utils.evaluateBool(result, @"readVBRRaw()", true)

   ' Test: readVBRRaw() data matches readSectorRaw VBR
   utils.startTest(@"readVBRRaw() matches readSectorRaw VBR")
   utils.evaluateBufferMatch(@vbrBuf, @vbrBuf2, 512, @"VBR data matches")
   ```

This brings the volume test suite from 21 to 23 tests.

---

## 12. Test: New windowed FSCK diagnostic test

**Severity**: New test file
**Commit**: `dd33908`
**File**: `diagnostic-tests/SD_diag_fsck_window_test.spin2` (new file, 394 lines)

### Purpose

Tests the windowed bitmap FSCK (change #7) on a 128 GB+ card. It:
1. Formats the card
2. Runs FSCK to confirm clean baseline
3. Injects 5 defects in window-2 cluster range (clusters > 2M)
4. Runs FSCK and verifies all defects are found and repaired
5. Runs FSCK again to confirm card is clean

### Porting note

This test file only needs porting if the flash-integrated driver includes the FSCK utility and you have access to 128 GB cards. The test is self-contained.

---

## 13. Misc: Version bump and .txt removal

**Commits**: `8c410c6`, `05fc726`

### Version bump (v1.0.0 → v1.1.0)

Two locations:
1. **Driver header**: `src/micro_sd_fat32_fs.spin2` line 3:
   ```
   │ SD card driver V3 — Release v1.1.0       │
   ```
2. **Demo shell**: `src/DEMO/SD_demo_shell.spin2`:
   ```spin2
   serial.fstr0(@"  SD Shell v1.1.0\r\n\r\n")
   ```

### Generated .txt removed from tracking

`src/micro_sd_fat32_fs.txt` was removed from git tracking and added to `.gitignore`. This file is auto-generated by the compiler. No porting action needed unless the flash-integrated repo also tracks it.

---

## Porting Priority Summary

| Priority | Change | Risk if skipped |
|----------|--------|-----------------|
| **P0 - Critical** | #1 readVBRRaw() bug fix | Silent data corruption |
| **P0 - Critical** | #2 Unsigned FAT comparisons | Incorrect behavior on large cards |
| **P1 - High** | #3 Volume label cluster chain scan | Wrong volume label on Windows-formatted cards |
| **P1 - High** | #4 entry_buffer struct typing | Potential indexing bugs if struct used elsewhere |
| **P1 - High** | #7 Windowed FSCK (if applicable) | FSCK broken on cards > 64 GB |
| **P2 - Medium** | #8 Cross-compiler PRAGMA blocks | Can't build with flexspin or Spin Tools |
| **P2 - Medium** | #9 flexspin line-continuation | Can't build format utility with flexspin |
| **P2 - Medium** | #10 CRC test fix | Flaky test on some cards |
| **P3 - Low** | #5 Struct accessor doc comments | Documentation quality |
| **P3 - Low** | #6 CON doc comment cleanup | .txt generation cleanliness |
| **P3 - Low** | #11 readVBRRaw() tests | Test coverage gap |
| **P3 - Low** | #12 Windowed FSCK diag test | Test coverage gap |
| **P4 - Skip** | #13 Version bump / .txt removal | Administrative |
