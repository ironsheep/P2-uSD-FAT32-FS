# OB4269 FAT32 Driver - Technical Adjustments

**Document Purpose**: Required code changes for cross-OS filesystem portability
**Driver**: Chris Gadd's FAT32 SD Card Driver (OBEX 4269)
**Date**: 2026-01-14

---

## Overview

This document specifies code changes required to ensure filesystems written by the P2 driver remain fully compatible when transferred between the P2 and host operating systems (Windows, macOS, Linux).

**Problem**: The current driver has three issues that can cause filesystem inconsistencies detectable by host OS filesystem checkers.

**Solution**: Three targeted fixes totaling ~50 lines of code.

---

## Fix 1: FAT Table Mirroring in deleteFile()

### Problem

When deleting files, the driver only updates FAT1, leaving FAT2 with stale data. Host OS filesystem checkers (`chkdsk`, `fsck.fat`) will report "FAT copies differ."

### Current Code (Line 183)

```spin2
PRI deleteFile(name_ptr) : result | cluster, p_cluster
  ' ... (lines 169-182 unchanged) ...
  repeat
    cluster := long[readFAT(p_cluster)]
    long[@buf + p_cluster << 2 & 511] := 0
    if cluster >> 7 - p_cluster >> 7 <> 0
      writeSector(p_cluster >> 7 + fat_Sec)      ' Only writes FAT1
    p_cluster := cluster
  until cluster >= $0FFF_FFF8
  return true
```

### Fixed Code

```spin2
PRI deleteFile(name_ptr) : result | cluster, p_cluster
  ' ... (lines 169-182 unchanged) ...
  repeat
    cluster := long[readFAT(p_cluster)]
    long[@buf + p_cluster << 2 & 511] := 0
    if cluster >> 7 - p_cluster >> 7 <> 0
      writeSector(p_cluster >> 7 + fat_sec)      ' Write FAT1
      writeSector(p_cluster >> 7 + fat2_sec)     ' Write FAT2 (ADDED)
    p_cluster := cluster
  until cluster >= $0FFF_FFF8
  return true
```

### Change Summary

| Location | Change |
|----------|--------|
| Line 183 | Add `writeSector(p_cluster >> 7 + fat2_sec)` after FAT1 write |

---

## Fix 2: Preserve Reserved Bits in FAT Entries

### Problem

FAT32 entries are 32 bits, but only the low 28 bits hold the cluster number. The high 4 bits are reserved and must be preserved when modifying entries. The current driver zeros all 32 bits when freeing clusters.

### Current Code (Line 181)

```spin2
long[@buf + p_cluster << 2 & 511] := 0           ' Zeros all 32 bits
```

### Fixed Code

```spin2
long[@buf + p_cluster << 2 & 511] &= $F000_0000  ' Preserve high 4 bits, clear low 28
```

### Change Summary

| Location | Change |
|----------|--------|
| Line 181 | Change `:= 0` to `&= $F000_0000` |

---

## Fix 3: FSInfo Sector Support

### Problem

FAT32 volumes have an FSInfo sector containing:
- `FSI_Free_Count`: Number of free clusters
- `FSI_Nxt_Free`: Hint for next free cluster allocation

The current driver never reads or updates this sector. After P2 operations, host systems may display incorrect free space until they recalculate.

### Implementation

#### 3.1 Add VAR Variables (after line 40)

```spin2
VAR
  ' ... existing variables ...
  long  fsinfo_sec          ' FSInfo sector number (typically VBR + 1)
  long  free_clusters       ' Cached free cluster count
  long  next_free_hint      ' Hint for next free cluster search
```

#### 3.2 Read FSInfo in mount() (after line 72)

Insert after `cluster_offset := root_sec // sec_per_clus`:

```spin2
    ' Read FSInfo sector
    fsinfo_sec := vbr_sec + word[@buf + $30]     ' BPB_FSInfo (typically 1)
    if fsinfo_sec > 0 and fsinfo_sec < reserved
      readSector(fsinfo_sec)
      if long[@buf + 0] == $4161_5252            ' FSI_LeadSig
        if long[@buf + 484] == $6141_7272        ' FSI_StrucSig
          free_clusters := long[@buf + 488]      ' FSI_Free_Count
          next_free_hint := long[@buf + 492]     ' FSI_Nxt_Free
          if free_clusters == $FFFF_FFFF         ' Unknown - will calculate on demand
            free_clusters := -1
          if next_free_hint == $FFFF_FFFF or next_free_hint < 2
            next_free_hint := 2
```

#### 3.3 Add updateFSInfo() Method (after closeFile)

```spin2
PRI updateFSInfo()                                '' write FSInfo sector to card
  if fsinfo_sec > 0
    readSector(fsinfo_sec)
    if long[@buf + 0] == $4161_5252              ' Verify signature
      long[@buf + 488] := free_clusters          ' FSI_Free_Count
      long[@buf + 492] := next_free_hint         ' FSI_Nxt_Free
      writeSector(fsinfo_sec)
```

#### 3.4 Update allocateCluster() (modify existing method)

Add at successful allocation (after line 420):

```spin2
      result := fat_idx >> 2
      if free_clusters > 0                       ' (ADDED)
        free_clusters--                          ' Decrement free count
      next_free_hint := result + 1               ' Update hint for next search
      writeSector(fat_sec + result >> 7)
```

Optimization - start search from hint (replace line 413):

```spin2
' Current:
  fat_idx := 0

' Optimized:
  fat_idx := (next_free_hint << 2) & (sec_per_fat << 9 - 1)
  if fat_idx < 8
    fat_idx := 8                                 ' Skip clusters 0 and 1
```

#### 3.5 Update deleteFile() - Increment Free Count

Add inside the repeat loop (after line 181):

```spin2
    long[@buf + p_cluster << 2 & 511] &= $F000_0000
    free_clusters++                              ' (ADDED) Increment free count
```

#### 3.6 Call updateFSInfo() in closeFile()

Add before clearing flags (line 165):

```spin2
  if flags & (F_NEWDIR | F_NEWDATA)
    readSector(entry_address >> 9)
    bytemove(@buf + entry_address & 511,@entry_buffer,32)
    writeSector(entry_address >> 9)
    updateFSInfo()                               ' (ADDED) Update FSInfo sector
```

---

## Complete deleteFile() After All Fixes

```spin2
PUB deleteFile(name_ptr) : result | cluster, p_cluster
  closeFile()
  if searchDirectory(name_ptr) == 0
    return
  if attributes() & %0001_1111
    return
  buf[entry_address & 511] := $E5
  writeSector(entry_address >> 9)

  p_cluster := firstCluster()
  repeat
    cluster := long[readFAT(p_cluster)]
    long[@buf + p_cluster << 2 & 511] &= $F000_0000  ' Preserve high 4 bits
    free_clusters++                                   ' Update free count
    if cluster >> 7 - p_cluster >> 7 <> 0
      writeSector(p_cluster >> 7 + fat_sec)          ' Write FAT1
      writeSector(p_cluster >> 7 + fat2_sec)         ' Write FAT2
    p_cluster := cluster
  until cluster >= $0FFF_FFF8
  updateFSInfo()                                      ' Write FSInfo
  return true
```

---

## Testing Checklist

After applying fixes, verify:

- [ ] Create file on P2, read on Windows - no chkdsk errors
- [ ] Delete file on P2, read on Windows - no "FAT copies differ"
- [ ] Create multiple files on P2 - free space shows correctly on host
- [ ] Fill card partially on P2 - free space accurate on host
- [ ] Round-trip: Host → P2 write → Host read - no filesystem errors

---

## Summary of Changes

| Fix | Lines Added | Lines Modified | Files |
|-----|-------------|----------------|-------|
| FAT2 mirroring | 1 | 0 | micro_sd_fat32_fs.spin2 |
| High 4 bits | 0 | 1 | micro_sd_fat32_fs.spin2 |
| FSInfo support | ~45 | ~5 | micro_sd_fat32_fs.spin2 |
| **Total** | **~46** | **~6** | **1 file** |

---

## Risk Assessment

| Fix | Risk | Mitigation |
|-----|------|------------|
| FAT2 mirroring | Very Low | Identical to existing FAT1 write |
| High 4 bits | Very Low | Standard bit masking operation |
| FSInfo | Low | Graceful fallback if sector invalid |

All fixes are backward compatible - cards formatted by previous driver versions will work correctly.

---

*Document prepared for P2 microSD FAT32 Filesystem project*
