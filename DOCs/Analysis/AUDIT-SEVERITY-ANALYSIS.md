# Audit Severity Analysis: Partition Type, FSInfo, and VBR Backup Mismatches

An analysis of common FAT32 metadata inconsistencies found on real SD/USB media, their actual risk levels, and appropriate audit behavior.

**Date:** 2026-03-05

---

## Table of Contents

1. [Background](#1-background)
2. [Partition Type $0B vs $0C](#2-partition-type-0b-vs-0c)
3. [Backup FSInfo Mismatch](#3-backup-fsinfo-mismatch)
4. [Backup VBR Mismatch](#4-backup-vbr-mismatch)
5. [Risk Summary](#5-risk-summary)
6. [Current Audit Behavior](#6-current-audit-behavior)
7. [Current FSCK Behavior](#7-current-fsck-behavior)
8. [Recommended Changes](#8-recommended-changes)
9. [Other Checks to Monitor](#9-other-checks-to-monitor)

---

## 1. Background

A user reported two audit failures on an AData 16GB SDHC card formatted with Linux `mkfs.fat`:

1. `[FAIL] Partition type ($0C = FAT32 LBA)` — card has $0B
2. `[FAIL] Backup FSInfo matches primary` — primary and backup differ

Research confirms these are common, benign inconsistencies on real-world SD and USB media. Every mainstream OS mounts and uses such volumes without issue.

---

## 2. Partition Type $0B vs $0C

### What They Mean

- **$0B** = FAT32 with CHS addressing
- **$0C** = FAT32 with LBA addressing (using INT13 extensions)

Functionally, both are FAT32. The on-disk format is identical. $0C is essentially "same as $0B but explicitly LBA" — it is not a different filesystem layout.

### Why $0B Appears

- Linux `mkfs.fat` can produce either type depending on invocation options
- Some legacy devices only recognize $0B and fail with $0C
- SD cards and USB sticks ship from the factory with $0B and work fine

### Why It Doesn't Matter for Our Driver

The driver uses the LBA start sector field from the MBR partition entry to locate the filesystem. This is the correct modern behavior and works regardless of whether the type byte is $0B or $0C. Rejecting $0B is purely an audit policy choice, not a technical requirement.

### Risk: None

The partition type byte is metadata that describes the addressing convention used by BIOS INT13 calls. Our driver doesn't use BIOS calls — it reads LBA fields directly. The type byte has zero impact on driver operation.

---

## 3. Backup FSInfo Mismatch

### What FSInfo Contains

The FSInfo sector (typically at partition start + 1) holds two values:

- **Free cluster count** — how many clusters are unallocated
- **Next free cluster hint** — where to start searching for free space

These are **performance hints only**. The SD Physical Layer Specification and the FAT32 specification both state that these values may be stale and must not be trusted blindly. If wrong, the correct values are recoverable by scanning the FAT.

### What the Backup Is

The backup FSInfo sector (typically at partition start + 7) is a copy of the primary. It exists as a recovery mechanism in case the primary sector becomes physically unreadable.

### Why Mismatches Are Common

Windows and Linux both update the primary FSInfo during normal operation but do not always update the backup. This is standard OS behavior, not a card defect. Mismatches between primary and backup FSInfo are widely observed on FAT32 media across all platforms.

### Risk During Normal Operation: None

Nothing reads the backup FSInfo during normal operation. Our driver reads the primary FSInfo at mount and updates it on unmount. The backup is never accessed.

### Risk During Recovery: Negligible

If the primary FSInfo sector becomes physically unreadable, the backup would provide stale hints. However, since FSInfo values are just hints that can be recalculated by scanning the FAT, even a stale backup is minimally useful — the recovery process would need to rescan the FAT regardless.

---

## 4. Backup VBR Mismatch

### What the VBR Contains

The Volume Boot Record (primary boot sector at partition start) contains the BIOS Parameter Block (BPB) — the sole source of truth for interpreting the entire filesystem:

- Bytes per sector
- Sectors per cluster
- Reserved sector count
- Number of FATs
- Sectors per FAT
- Root cluster number
- Total sector count

Without a correct BPB, the FAT location, data region start, and cluster-to-sector mapping are all unknown. The filesystem cannot be read.

### What the Backup Is

The backup VBR (typically at partition start + 6) is a complete copy of the primary boot sector. It exists as a recovery mechanism in case the primary VBR is damaged.

### Why Mismatches Can Occur

Some formatting tools or OS operations may update the primary VBR without syncing the backup. This is less common than FSInfo mismatches but does occur on real media.

### Risk During Normal Operation: None

The backup VBR is never read during normal operation. Our driver reads the primary VBR at mount time to extract filesystem geometry.

### Risk During Recovery: Low but Real

If the primary VBR sector develops a read error (flash cell failure), the backup is the only way to recover the filesystem without external tools. A mismatched backup could contain stale or incorrect geometry — potentially pointing to wrong FAT locations, wrong cluster sizes, or wrong data region boundaries. Unlike FSInfo hints, VBR geometry cannot be recalculated from other on-disk data.

That said:
- Flash sector failures are rare on modern cards
- The backup is only used in disaster recovery scenarios
- FSCK already repairs this by copying primary to backup

---

## 5. Risk Summary

| Mismatch | Normal Operation | Recovery Scenario |
|----------|-----------------|-------------------|
| **Partition type $0B** | No risk — driver uses LBA fields | N/A |
| **FSInfo backup** | No risk — backup never read | Negligible — hints are recalculable from FAT |
| **VBR backup** | No risk — backup never read | Low but real — geometry not recoverable without VBR |

---

## 6. Current Audit Behavior

The audit reports all three as hard `[FAIL]`:

```
[FAIL] Partition type ($0C = FAT32 LBA)        — rejects $0B
[FAIL] Backup FSInfo matches primary            — common mismatch
[FAIL] Backup VBR matches primary               — less common, passed on test card
```

This overstates the severity. A user seeing `[FAIL]` on a working card may believe the card is defective or the filesystem is corrupted when neither is true.

### CHS Fields

The audit does **not** check CHS address fields in the MBR partition entry — it only checks the type byte and LBA start sector. This is already the correct behavior, since many tools ignore CHS entirely and only maintain LBA fields.

---

## 7. Current FSCK Behavior

FSCK handles both backup mismatches with automatic repair:

- **Backup VBR mismatch**: Copies primary VBR to backup sector (partition start + 6)
- **Backup FSInfo mismatch**: Copies primary FSInfo to backup sector (partition start + 7)

This is correct and appropriate — a repair tool should sync backups to match primaries.

FSCK does not check or modify the MBR partition type byte, which is also correct — changing $0B to $0C would be cosmetic and could break compatibility with legacy devices that only recognize $0B.

---

## 8. Recommended Changes

### 8.1 Partition Type: Accept Both $0B and $0C

Change the audit check from requiring exactly $0C to accepting either $0B or $0C:

**Current:**
```spin2
auditRunTest(@"Partition type ($0C = FAT32 LBA)", result == sd.PART_TYPE_FAT32_LBA)
```

**Proposed:**
```spin2
auditRunTest(@"Partition type FAT32 ($0B or $0C)", result == sd.PART_TYPE_FAT32_LBA OR result == PART_TYPE_FAT32_CHS)
```

### 8.2 Backup FSInfo Mismatch: Downgrade to Warning

Replace the `[FAIL]` with a `[WARN]` that increments `v_warningCount` instead of `v_failCount`:

**Current:**
```spin2
auditRunTest(@"Backup FSInfo matches primary", mismatch == false)
```

**Proposed:**
```spin2
if mismatch
    fifo.put(@"  [WARN] Backup FSInfo differs from primary (common, repaired by fsck)")
    v_warningCount++
else
    auditRunTest(@"Backup FSInfo matches primary", TRUE)
```

### 8.3 Backup VBR Mismatch: Keep as FAIL

The VBR backup mismatch should remain a `[FAIL]`. Unlike FSInfo, the VBR contains irreplaceable filesystem geometry (bytes/sector, sectors/cluster, FAT size, root cluster, total sectors). This data cannot be recalculated from other on-disk structures. A mismatched backup means the disaster recovery copy is stale — exactly the kind of issue the audit should flag so FSCK can repair it. No user report or research has identified VBR backup mismatches as a false positive problem.

### 8.4 Warning Infrastructure

The audit currently uses `auditRunTest()` which only produces `[PASS]` or `[FAIL]`. The proposed changes handle warnings inline. Alternatively, an `auditRunWarning()` helper could be added if more warning-level checks are needed in the future.

---

## 9. Other Checks to Monitor

Research identified additional classes of benign inconsistencies that may appear on real media:

| Check | Current Status | Risk |
|-------|---------------|------|
| **MBR boot flag** ($00 or $80) | Audit checks — could fail on non-standard media | Low — some tools produce non-standard flags |
| **CHS fields** | Not checked | N/A — correct to ignore |
| **MBR disk signature** | Not checked | N/A — not relevant to filesystem access |

The boot flag check has not triggered on any reported card, but if future user reports show failures on this check, it should be evaluated for downgrade to warning using the same reasoning applied here.

---

*Analysis produced 2026-03-05 from user reports, research, and driver/audit source code study.*
