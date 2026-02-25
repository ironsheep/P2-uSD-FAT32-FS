# Session Catch-Up: V2 Driver Development Status

**Date:** 2026-01-26 (Updated: Evening Session)
**Purpose:** Summary of uncommitted changes, current issues, and investigation status

---

## EVENING SESSION UPDATE: What Was Fixed Tonight

### Major Bug Fixed: Operator Precedence in searchDirectory()

**The Bug:**
```spin2
' WRONG - Spin2 evaluates as (@buf + i) & 511
p_entry := @buf + i & 511

' CORRECT - Fixed to:
p_entry := @buf + (i & 511)
```

**Impact:** This was causing 2-3 test failures per run consistently. After the fix, 5 out of 6 test runs showed 0 failures.

### Current Test Status

After 6 directory test runs:
- **5 runs:** Pass: 21, Fail: 0
- **1 run:** Pass: 19, Fail: 2 (intermittent)

The intermittent failure affects Tests #20-22 (Move File tests).

---

## CRITICAL OPEN QUESTION: Buffer Conflicts Between Sector Types

**Question posed:** Did we determine whether buffer conflicts between different sector types (data/dir/FAT) are a factor?

### Answer: NO - This was NOT fully investigated

The driver uses a **single 512-byte buffer** (`buf`) for ALL sector types:
- Directory sectors
- Data sectors
- FAT sectors

### The Concern in moveFile:

The moveFile operation involves complex sector interactions:

1. Read directory sector (find MOVEME) → buf contains source dir sector (38,688)
2. Save bookmark = entry_address
3. Search destination directory (RTDIR2) → may read different directory sectors
4. Call do_newfile() in destination → reads/writes RTDIR2's dir sector (63,572)
5. **Critical:** do_newfile() may allocate a cluster → reads/writes **FAT sectors**
6. Read source directory again (sector 38,688) to mark as deleted
7. Write sector 38,688
8. Call do_close() → may update FAT sectors again

### The Risk:

If step 5 (FAT allocation) or step 8 (close) reads a FAT sector into `buf`, and step 6's readSector() incorrectly thinks the buffer is still valid (cache mismatch), we get stale directory data that corrupts the write.

### Debug Output Showed Suspicious State:

```
[do_movefile] Reading sector 38_688 (sec_in_buf=63_572)
[do_movefile] After read: buf[128]=[garbage] buf[160]=[MOVEME  TXT]
```

The cache indicated sector 63,572 was in buffer, but we were about to read 38,688. The read DID occur (MOVEME was found correctly), so the cache check triggered a re-read. But the intermittent nature suggests sometimes the cache incorrectly matches.

### What Needs Investigation Tomorrow:

1. **Trace ALL sector operations during moveFile** - Log every readSector/writeSector call with sector number and type (dir/fat/data)

2. **Verify sec_in_buf consistency** - Is it correctly invalidated after EVERY write operation?

3. **Check FAT operations in do_newfile()** - Does allocating a cluster for the new directory entry read FAT sectors into buf?

4. **Check FAT operations in do_close()** - Does updating file size trigger FAT reads/writes?

5. **Look for paths that bypass writeSector()** - Any direct writes that don't invalidate cache?

### Hypothesis: Race Between Directory and FAT Sectors

When moveFile calls do_newfile() to create the entry in RTDIR2:
1. do_newfile() allocates a cluster for the new file (even though moveFile preserves the original cluster chain)
2. This allocation reads FAT sector into buf
3. Control returns to do_movefile()
4. do_movefile() reads source directory sector 38,688
5. The read happens (sec_in_buf was different), buf now has directory data
6. do_movefile() marks entry deleted, writes sector
7. do_movefile() calls do_close()
8. **do_close() may read FAT sectors to update allocation**
9. Now buf has FAT data, but sec_in_buf = FAT sector
10. If any subsequent directory operation checks sec_in_buf and finds a mismatch, it reads correctly
11. But if there's a code path where sec_in_buf incorrectly matches, stale data is used

The intermittent nature suggests timing-dependent behavior - maybe a race between when sec_in_buf is set vs when buf is actually filled.

---

## Part 1: Analysis of Changes Since Last Commit

### Overview

The uncommitted changes represent a significant pivot in the V2 driver approach: **moving away from streamer-based sector reads to smart-pin-only operation** due to reliability issues.

### Files Changed

| File | Change Type | Summary |
|------|-------------|---------|
| `src/SD_card_driver_v2.spin2` | Modified | Major: Removed streamer from readSector, added debugging, bug fixes |
| `regression-tests/*.spin2` (5 files) | Modified | Switched from V1 to V2 driver for testing |
| `regression-tests-v2/*.spin2` (2 files) | Modified | Switched to `SD_format_utility_v2` |
| `src/UTILS/SD_format_utility_v2.spin2` | New | Format utility using V2 driver |
| `tools/SD_FAT32_audit.spin2` | New | FAT32 integrity audit tool |

---

### Detailed Change Analysis: SD_card_driver_v2.spin2

#### 1. CRITICAL: Streamer Removed from readSector()

**What was removed (lines 1936-1981 in diff):**
```spin2
' OLD: Streamer bulk transfer code
pinclear(_miso)                    ' Clear smart pin mode
pinf(_miso)                        ' Float pin (input mode)
stream_mode := STREAM_RX_BASE | (_miso << 17) | (512 * 8)
clk_count := 512 * 8 * 2
xfrq := $4000_0000 / spi_period
...
org
      setxfrq xfrq
      wrfast  #0, p_buf
      wypin   clk_count, _sck
      waitx   align_delay
      xinit   stream_mode, init_phase
      waitxfi
end
```

**What replaced it:**
```spin2
' NEW: Byte-by-byte using smart pins
repeat loop_ctr from 0 to 511
  buf[loop_ctr] := sp_transfer_8($FF)
```

**Why:** The streamer approach had sysclk-dependent timing issues causing data corruption at 270 MHz. The smart-pin-only approach is slower but more reliable and sysclk-independent.

---

#### 2. Smart Pin Sampling Mode Changed

**Before:** `%1_00111` (ON-edge sampling - exact edge, faster but less margin)
**After:** `%0_00111` (PRE-edge sampling - samples slightly before edge, more tolerant)

**Locations changed:**
- `initSPIPins()` line 1552: MISO initial config
- `sp_transfer_8()` line 1646: Per-transfer MISO config
- `readSectors()` line 2015: After streamer for CRC reads
- `writeSector()` line 2580: After write completion

**Why:** PRE-edge sampling provides more setup time margin, making the driver more tolerant of timing variations.

---

#### 3. sp_transfer_8() Rewritten for Robustness

**Changes:**
1. **Added smart pin reset before each transfer:**
   ```spin2
   fltl    _mosi                   ' Float TX to reset state
   fltl    _miso                   ' Float RX to reset state (clears IN flag)
   ```

2. **Moved `akpin` AFTER `rdpin`** (was before in old code):
   ```spin2
   rdpin   raw_result, _miso
   akpin   _miso                   ' Clear IN flag for next transfer
   ```

3. **Changed to `drvl` instead of `dirh` for enabling RX smart pin**

**Why:** Ensures clean state between transfers, preventing accumulation of stale IN flags that could cause synchronization issues.

---

#### 4. Operator Precedence Bug Fixes

Multiple instances of `@buf + x & 511` changed to `@buf + (x & 511)`:

```spin2
' Before (incorrect - & has lower precedence than +)
bytemove(@buf + entry_address & 511, @entry_buffer, 32)

' After (correct - parentheses enforce intended order)
bytemove(@buf + (entry_address & 511), @entry_buffer, 32)
```

**Locations fixed:**
- `do_write()` line 570
- `do_newdir()` line 632
- `do_delete()` line 698
- `do_sync()` line 728
- `do_rename()` line 739
- `do_movefile()` lines 749-750
- `do_readdir()` lines 764, 767, 773
- `countFreeClusters()` line 1318
- `searchDirectory()` lines 1360, 1362, 1369, 1370
- `readFat()` line 1421
- `allocateCluster()` line 1440
- `readNextSector()` line 1460

**Why:** Without parentheses, `@buf + x & 511` computes `(@buf + x) & 511` which truncates the buffer address to 511 bits - completely wrong! The intent is `@buf + (x & 511)` to index within the 512-byte buffer.

---

#### 5. Sector Cache Invalidation Fixed

**Before:**
```spin2
' Only invalidate if writing the cached sector
if sector == sec_in_buf
  sec_in_buf := -1
```

**After:**
```spin2
' CRITICAL: Always invalidate sector cache because writeSector uses buf
' The buf buffer is shared between read and write, so any write operation
' invalidates any cached read data, regardless of which sector we're writing
sec_in_buf := -1
```

**Why:** `writeSector()` uses the shared `buf` buffer. Even if writing a different sector, the buffer contents are destroyed. This was causing stale data to be returned on subsequent reads.

---

#### 6. End-of-Chain Detection in readNextSector()

**Added:**
```spin2
if contents >= $0FFF_FFF8          ' end-of-chain marker detected
  bytefill(@buf, 0, 512)           ' fill buffer with zeros (marks end of directory)
  return                           ' don't read invalid sector
```

**Why:** Prevents attempting to read from an invalid cluster number when the FAT chain terminates. Without this, the driver could read garbage sectors and interpret them as valid directory entries.

---

#### 7. Directory Search Safety Loop

**Before:**
```spin2
repeat                             ' Infinite loop scanning directory
```

**After:**
```spin2
repeat 65536                       ' Max 65536 entries (2MB directory) as safety limit
```

**Why:** Prevents infinite loop if directory is corrupted. A FAT32 directory can have at most 65,536 32-byte entries (2MB), so this is a safe upper bound.

---

#### 8. "." and ".." Directory Entry Fix

**Before:**
```spin2
if strcomp(@entry_buffer,string("..")) == 0   ' exception for ".."
```

**After:**
```spin2
' Skip 8.3 conversion for "." (single dot) or ".." (double dot) directory entries
if not (entry_buffer[0] == "." and (entry_buffer[1] == 0 or (entry_buffer[1] == "." and entry_buffer[2] == 0)))
```

**Why:** The old check was incorrect (used `== 0` but strcomp returns 0 for mismatch). The new code correctly detects both "." and ".." entries and preserves them as-is without attempting 8.3 name conversion.

---

#### 9. FSInfo/Free Space Optimization

**Changes to `do_freespace()`:**
```spin2
' Use cached FSInfo free count if available (avoids slow FAT scan)
if fsi_free_count <> $FFFF_FFFF
  return fsi_free_count * sec_per_clus
' Fall back to scanning FAT (slow, but needed if FSInfo not available)
```

**Changes to `updateFSInfo()`:**
- No longer scans FAT on unmount (too slow with byte-at-a-time SPI)
- Uses cached `fsi_free_count` value from mount

**Why:** With the streamer removed, FAT scanning is very slow. Using cached FSInfo values is much faster for typical use.

---

#### 10. Added Settle Time Delays

Multiple `waitms()` and `waitus()` calls added:
- `do_close()`: 10ms after directory update
- `do_delete()`: 1ms after directory write, 1ms after FAT writes
- `do_sync()`: 1ms after directory update
- `readSector()`: 10us after CS deselect

**Why:** Some SD cards need time to complete internal operations. These delays improve reliability with sensitive cards (like PNY).

---

#### 11. Added Debug Output

Extensive debug statements added to:
- `do_mount()`: FSInfo read verification
- `do_open()`: File found confirmation
- `do_close()`: Buffer state tracking
- `readSector()`: Cache hit logging
- `writeSector()`: Success confirmation

**Why:** Debugging the reliability issues required visibility into internal state.

---

### Test File Changes

All regression tests switched from V1 to V2 driver:
```spin2
' Before
sd    : "SD_card_driver"

' After
sd    : "SD_card_driver_v2"
```

This allows running the full regression suite against the V2 driver.

---

### New Files

#### SD_format_utility_v2.spin2
A format utility that uses the V2 driver for low-level sector access. Creates properly formatted FAT32 filesystems for testing.

#### SD_FAT32_audit.spin2
Read-only filesystem integrity checker. Verifies:
- MBR structure and partition table
- VBR and backup copy
- FSInfo sector and signatures
- FAT1 == FAT2 consistency
- Root directory structure

---

## Part 2: Current Problems and Hypotheses

### Problem 1: Performance Regression

**Symptoms:**
- Single-sector reads now use `sp_transfer_8()` loop (512 iterations)
- Each iteration involves smart pin setup/teardown
- Estimated throughput: ~500 KB/s vs 2,400 KB/s with streamer

**Impact:**
- 4-5x slower for filesystem operations
- Makes FAT scanning impractical
- Mount time increased significantly

**Hypotheses:**
1. **Smart pin overhead:** Each `sp_transfer_8()` call resets both MOSI and MISO pins, adding significant overhead
2. **Spin2 loop overhead:** The repeat loop has interpreter overhead vs PASM streamer

**Potential Solutions:**
1. Add PASM-based `sp_transfer_512()` that reads full sector without pin reset per byte
2. Investigate why streamer failed and fix the actual issue
3. Use hybrid approach: smart pins for commands, optimized PASM for data

---

### Problem 2: Remaining Test Failures (from Certification)

**Symptom: File Ops Return Values (5 failures)**
- `openFile()` returns 0 instead of expected value in some cases
- `fileSize()` returns 0 unexpectedly

**Hypothesis:**
The operator precedence bug fixes may have exposed or introduced new issues. The `attributes()` check in `do_open()` may have incorrect logic:
```spin2
if attributes() & %0001_1110 == 0    ' This is (attributes() & %0001_1110) == 0
```

---

**Symptom: Seek Byte Mismatch (1 failure)**
- Test expects byte value 220, gets 254

**Hypothesis:**
The `do_seek()` function may have an off-by-one or buffer boundary issue. The sector cache invalidation fix could have changed behavior.

---

**Symptom: Raw Sector Tail Corruption (2 failures)**
- Last bytes of sector show pattern/ID mismatch

**Hypothesis:**
The `sp_transfer_8()` implementation may be losing the last byte or two. The `akpin` timing relative to `rdpin` could be dropping data:
```spin2
rdpin   raw_result, _miso
akpin   _miso           ' Is this happening too soon?
```

---

### Problem 3: 270 MHz Timing Failures

**Symptoms:**
- Sequential multi-block operations (write then read) fail
- 3,968 - 24,800 byte mismatches
- Same operations pass at 320 MHz

**Hypotheses:**

1. **NCO Phase Quantization:**
   - At 320 MHz: `xfrq = $4000_0000 / 7 = $0924_9249`
   - At 270 MHz: `xfrq = $4000_0000 / 6 = $0AAA_AAAA`
   - Different quantization errors produce different phase relationships

2. **Streamer-to-Card Timing:**
   - The streamer may be starting before the card is ready
   - `align_delay` calculation may not scale correctly

3. **FIFO vs Card Timing:**
   - `wrfast`/`rdfast` FIFO timing may have different behavior at different sysclks
   - Card internal timing is fixed, not relative to sysclk

**Note:** This problem may be moot now that streamer was removed, but it documents why the change was made.

---

### Problem 4: Cleanup Hangs

**Symptoms:**
- Tests pass but timeout during file deletion cleanup
- Card appears to go busy and not recover

**Hypotheses:**

1. **Missing Busy-Wait:**
   The delete operation modifies multiple FAT sectors. If the card isn't fully ready between writes, it may lock up.

2. **FAT Sector Write Timing:**
   The new `waitms(1)` delays in `do_delete()` may not be sufficient for all cards.

3. **Accumulated State:**
   After many operations, smart pin state may accumulate issues that aren't visible until delete.

---

## Part 3: Recommended Next Steps

### Immediate (Debug Current Issues)

1. **Run regression tests with current changes** to establish baseline
2. **Add more debugging to sp_transfer_8()** - log raw rdpin values
3. **Test with logic analyzer** - verify SPI timing matches expectations

### Short Term (Performance Recovery)

4. **Implement optimized PASM sector read** - avoid per-byte pin reset
5. **Investigate streamer issue root cause** - don't abandon 4.5x speedup without understanding why

### Medium Term (Production Readiness)

6. **Fix remaining test failures** - align with V1 behavior
7. **Add card recovery mechanism** - reset card if it hangs
8. **Document sysclk requirements** - until timing is fixed

---

## Quick Reference: Key Code Locations

| Issue | File | Line(s) | Function |
|-------|------|---------|----------|
| Smart pin 8-bit transfer | SD_card_driver_v2.spin2 | 1620-1668 | sp_transfer_8() |
| Sector read (no streamer) | SD_card_driver_v2.spin2 | 1909-1962 | readSector() |
| Sector cache invalidation | SD_card_driver_v2.spin2 | 2048-2055 | writeSector() |
| MISO pin config | SD_card_driver_v2.spin2 | 1550-1554 | initSPIPins() |
| PRE vs ON edge | SD_card_driver_v2.spin2 | 1552 | initSPIPins() |
| Directory search | SD_card_driver_v2.spin2 | 1327-1378 | searchDirectory() |
