# SD Card Driver Improvements Tracking

**Driver**: OB4269 FAT32 SD Card Driver (modified)
**Original Author**: Chris Gadd
**Modifications**: Iron Sheep Productions
**Date Started**: 2026-01-16

---

## Overview

This document tracks all modifications made to the SD card driver to improve:
1. **OS Compatibility** - Ensure cards modified by the P2 work correctly with Windows/macOS/Linux
2. **Power-Loss Resilience** - Minimize data corruption risk if power is lost during operations
3. **Specification Compliance** - Follow Microsoft FAT32 specification more closely

---

## Issue Tracking

### Issue #1: Inconsistent FAT Mirroring

**Status**: ✅ FIXED (2026-01-16)
**Priority**: HIGH
**Category**: OS Compatibility, Data Integrity

**Problem**:
FAT32 requires two identical FAT tables (FAT1 and FAT2). The driver updates both in `allocateCluster()` but only updates FAT1 in `deleteFile()`.

**Current Code** (`deleteFile()`):
```spin2
' Only writes to FAT1:
writeSector(p_cluster >> 7 + fat_sec)
' FAT2 NOT updated!
```

**Required Fix**:
```spin2
' Write to both FAT tables:
writeSector(p_cluster >> 7 + fat_sec)
writeSector(p_cluster >> 7 + fat2_sec)    ' ADD THIS
```

**Impact if not fixed**:
- FAT1 and FAT2 become inconsistent after file deletion
- If FAT1 corrupts, recovery from FAT2 would show deleted files as allocated
- Some OS filesystem checks may flag inconsistency

**Files Modified**: `micro_sd_fat32_fs.spin2`
**Functions Modified**: `deleteFile()`

---

### Issue #2: FAT Entry High 4 Bits Not Preserved

**Status**: ✅ FIXED (2026-01-16)
**Priority**: MEDIUM
**Category**: OS Compatibility

**Problem**:
FAT32 entries are 32 bits, but only the low 28 bits are the cluster number. The high 4 bits are reserved and must be preserved when writing.

**Current Code**:
```spin2
' Overwrites all 32 bits:
long[@buf + p_cluster << 2 & 511] := 0              ' deleteFile - clears reserved bits!
long[@buf + fat_idx & 511] := $0FFF_FFFF            ' allocateCluster - overwrites reserved bits!
```

**Required Fix**:
```spin2
' Preserve high 4 bits, modify only low 28 bits:
long[@buf + idx] := (long[@buf + idx] & $F000_0000) | new_value
```

**Impact if not fixed**:
- Reserved bits destroyed on every FAT write
- Some OS implementations or future specs may use those bits
- Could trigger filesystem repair warnings

**Files Modified**: `micro_sd_fat32_fs.spin2`
**Functions Modified**: `deleteFile()`, `allocateCluster()`

---

### Issue #3: FSInfo Sector Not Supported

**Status**: ✅ FIXED (2026-01-16)
**Priority**: MEDIUM
**Category**: OS Compatibility

**Problem**:
FAT32 volumes have an FSInfo sector (typically sector 1) containing:
- `FSI_Free_Count` (offset 488): Number of free clusters
- `FSI_Nxt_Free` (offset 492): Hint for next free cluster

The driver never reads or updates this sector.

**FSInfo Structure**:
```
Offset   Size   Value           Description
0        4      0x41615252      Lead signature
484      4      0x61417272      Structure signature
488      4      variable        Free cluster count (0xFFFFFFFF = unknown)
492      4      variable        Next free cluster hint (0xFFFFFFFF = unknown)
508      4      0xAA550000      Trail signature
```

**Required Fix**:
1. Read FSInfo sector location from VBR offset 48 (`BPB_FSInfo`)
2. On mount: Read FSInfo, cache `FSI_Free_Count` and `FSI_Nxt_Free`
3. On unmount: Update FSInfo with current values
4. Use `FSI_Nxt_Free` as starting point in `allocateCluster()` for performance

**Memory Impact**:
- +4 bytes: `fsinfo_sec` (sector number)
- +4 bytes: `fsi_free_count` (cached value)
- +4 bytes: `fsi_nxt_free` (cached value)
- Total: +12 bytes VAR

**Impact if not fixed**:
- Other OSes show incorrect free space after P2 modifies card
- Slower cluster allocation (always searches from cluster 2)
- Stale metadata visible to users

**Files Modified**: `micro_sd_fat32_fs.spin2`
**Functions Modified**: `mount()`, new `unmount()`, `allocateCluster()`, `freeSpace()`

---

### Issue #4: No Proper Unmount Sequence

**Status**: ✅ FIXED (2026-01-16)
**Priority**: HIGH
**Category**: Power-Loss Resilience, OS Compatibility

**Problem**:
There is no `unmount()` method. Users must call `closeFile()` manually, and FSInfo is never updated. Unclean shutdown leaves card in inconsistent state.

**Required Fix**:
Add `unmount()` method that:
1. Closes any open file (`closeFile()`)
2. Updates FSInfo sector with correct free count
3. Ensures all writes are flushed to card

```spin2
PUB unmount() : result
  closeFile()                           ' Flush any open file
  updateFSInfo()                        ' Update free space metadata
  ' Card is now in clean, consistent state
  result := true
```

**Impact if not fixed**:
- FSInfo always stale after P2 use
- No clean shutdown path
- Users must remember to call closeFile()

**Files Modified**: `micro_sd_fat32_fs.spin2`
**Functions Added**: `unmount()`, `updateFSInfo()`

---

### Issue #5: No Explicit Sync Method

**Status**: ✅ FIXED (2026-01-16)
**Priority**: LOW
**Category**: Power-Loss Resilience

**Problem**:
No way to force flush of buffered data without closing the file. Long-running applications that keep files open have no checkpoint mechanism.

**Required Fix**:
Add `sync()` method:
```spin2
PUB sync() : result
  if flags & F_NEWDATA
    writeSector(n_sec)                  ' Flush data buffer
  if flags & F_NEWDIR
    readSector(entry_address >> 9)
    bytemove(@buf + entry_address & 511, @entry_buffer, 32)
    writeSector(entry_address >> 9)     ' Flush directory entry
  result := true
```

**Impact if not fixed**:
- No way to checkpoint data without closing file
- Higher risk of data loss on power failure during long writes

**Files Modified**: `micro_sd_fat32_fs.spin2`
**Functions Added**: `sync()`

---

## Write Ordering for Power-Loss Resilience

### Current Write Order (Problematic)

```
1. allocateCluster()    → FAT modified (cluster marked used)
2. write()              → Data written to cluster
3. closeFile()          → Directory entry updated
```

**Problem**: If power lost after step 1 but before step 2, FAT shows cluster allocated but it contains garbage.

### Improved Write Order (Safer)

```
1. write()              → Data written to cluster FIRST
2. allocateCluster()    → FAT updated (both copies)
3. closeFile()          → Directory entry updated LAST
```

**Why this is safer**:
- Power loss after step 1: Data written but cluster not allocated → appears as free space, data orphaned (no corruption, minor space leak)
- Power loss after step 2: Cluster allocated, data present, but not linked → orphaned cluster (fsck can find)
- Power loss after step 3: Complete, consistent state

### Danger Window Analysis

| Operation | Danger Window | Recovery |
|-----------|---------------|----------|
| File create | FAT write → Directory write | Orphaned cluster, fsck repairs |
| File extend | FAT write → Directory size update | Orphaned cluster, fsck repairs |
| File delete | Directory mark → FAT clear | File appears deleted, space leaked |
| FAT mirror | FAT1 write → FAT2 write | One FAT intact, fsck uses good copy |

### Mitigation Strategies Implemented

1. **Always write both FAT copies together** - Minimizes FAT1/FAT2 divergence window
2. **Update directory entry last** - Already done in `closeFile()`
3. **Provide sync() for checkpointing** - Allows flush without close
4. **Provide unmount() for clean shutdown** - Ensures FSInfo updated

---

## Memory Impact Summary

| Change | VAR Bytes | Code Bytes (est) |
|--------|-----------|------------------|
| FAT mirroring fix | +0 | +20 |
| High 4 bits preservation | +0 | +40 |
| FSInfo support | +12 | +200 |
| unmount() method | +0 | +50 |
| sync() method | +0 | +80 |
| **TOTAL** | **+12** | **+390** |

Current driver: 616 bytes VAR, ~9.8 KB code
After fixes: 628 bytes VAR, ~10.2 KB code

---

## Testing Requirements

### Test 1: FAT Mirroring
- [ ] Delete a file on P2
- [ ] Read card on PC, compare FAT1 and FAT2 sectors
- [ ] Verify they are identical

### Test 2: FSInfo Accuracy
- [ ] Write files on P2, call unmount()
- [ ] Read card on PC, check reported free space
- [ ] Verify free space matches actual

### Test 3: High 4 Bits
- [ ] Create card with known high-bit pattern in FAT
- [ ] Modify files on P2
- [ ] Verify high bits preserved

### Test 4: Power-Loss Simulation
- [ ] Start file write
- [ ] Interrupt power mid-operation
- [ ] Verify card mounts on PC
- [ ] Run fsck/chkdsk, verify repairs are minor

### Test 5: Clean Unmount
- [ ] Write files, call unmount()
- [ ] Verify no fsck errors on PC

---

## Implementation Log

| Date | Issue | Status | Notes |
|------|-------|--------|-------|
| 2026-01-16 | Document created | ✅ | Initial tracking document |
| 2026-01-16 | Issue #1 FAT Mirroring | ✅ | Fixed in `deleteFile()` - now writes to both FAT1 and FAT2 |
| 2026-01-16 | Issue #2 High 4 Bits | ✅ | Fixed in `allocateCluster()` - preserves reserved bits |
| 2026-01-16 | Issue #3 FSInfo | ✅ | Added read in `mount()`, update in `unmount()` |
| 2026-01-16 | Issue #4 unmount() | ✅ | Added `unmount()` method with FSInfo update |
| 2026-01-16 | Issue #5 sync() | ✅ | Added `sync()` method for checkpoint writes |
| 2026-01-16 | Additional fixes | ✅ | Also fixed FAT mirroring in `allocateCluster()` |

---

---

## Performance Improvements (Phase 1 Sprint)

### Issue #6: Smart Pin SPI Implementation

**Status**: 🔄 PLANNED (Phase 1)
**Priority**: HIGH
**Category**: Performance

**Problem**:
Current bit-banged SPI implementation:
- Achieves only ~60% efficiency (1.5 MB/s read vs 2.5 MB/s theoretical)
- Speed tied to sysclk setting
- ~20 MHz practical SPI clock

**Solution**:
Replace bit-banged SPI with P2 Smart Pins:

| Pin | Smart Pin Mode | Purpose |
|-----|----------------|---------|
| SCK | P_TRANSITION | Clock generation |
| MOSI | P_SYNC_TX | Synchronized transmit |
| MISO | P_SYNC_RX | Synchronized receive |
| CS | GPIO | Manual control (unchanged) |

**Expected Improvement**:
| Metric | Current | Target |
|--------|---------|--------|
| Read 256KB | 1,467 KB/s | 3,000+ KB/s |
| Write 32KB | 425 KB/s | 900+ KB/s |
| SPI Clock | ~20 MHz | 25-50 MHz |

**Implementation**: See `DOCs/Plans/PHASE1-SMARTPIN-SPI.md` Tasks 1.1-1.7

---

### Issue #7: Multi-Block Read/Write Operations

**Status**: 🔄 PLANNED (Phase 1)
**Priority**: HIGH
**Category**: Performance

**Problem**:
Current single-sector operations incur command overhead per sector:
- 8 sectors = 8× CMD17 commands
- Wastes ~10 bytes overhead per sector

**Solution**:
Implement multi-block operations:
- CMD18 (READ_MULTIPLE_BLOCK) + CMD12 (STOP_TRANSMISSION)
- CMD25 (WRITE_MULTIPLE_BLOCK) + $FD stop token

**New Functions**:
```spin2
readSectors(start, count, p_buffer)   ' CMD18 multi-block read
writeSectors(start, count, p_buffer)  ' CMD25 multi-block write
```

**Protocol Details**:
| Aspect | Single Block | Multi-Block |
|--------|--------------|-------------|
| Read command | CMD17 | CMD18 |
| Write command | CMD24 | CMD25 |
| Write data token | $FE | $FC |
| Write stop | Automatic | $FD token |
| Read stop | Automatic | CMD12 |

**Expected Improvement**:
| Operation | Gain |
|-----------|------|
| Read 8 sectors | 10-15% |
| Read 64 sectors | 15-25% |
| Write 8 sectors | 20-30% |
| Write 64 sectors | 30-40% |

**Implementation**: See `DOCs/Plans/PHASE1-SMARTPIN-SPI.md` Tasks 1.8-1.10

---

## Implementation Log (continued)

| Date | Issue | Status | Notes |
|------|-------|--------|-------|
| 2026-01-21 | Issue #6 Smart Pin SPI | 🔄 | Planned for Phase 1 implementation |
| 2026-01-21 | Issue #7 Multi-Block | 🔄 | Added to Phase 1 scope |
| 2026-01-21 | Baseline benchmarks | ✅ | Documented in Reference/BENCHMARK-RESULTS.md |

---

## References

- Microsoft FAT32 File System Specification v1.03
- SD Physical Layer Simplified Specification v9.10
- OB4269-FAT32-COMPLIANCE-ANALYSIS.md (detailed spec analysis)
- DOCs/Plans/Archive/PHASE1-SMARTPIN-SPI.md (implementation plan)
- DOCs/Reference/BENCHMARK-RESULTS.md (baseline performance data)
