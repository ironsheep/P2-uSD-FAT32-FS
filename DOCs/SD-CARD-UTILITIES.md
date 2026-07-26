# SD Card Utilities

This document describes the standalone utility programs included with the P2 SD Card Driver. These utilities help with card formatting, characterization, performance testing, and filesystem validation.

## Overview

The utilities are located in `src/UTILS/` and can be run independently using the test runner from the `tools/` directory.

### Utility Summary

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **SD_format_card.spin2** | FAT32 card formatter (standalone) | Yes |
| **SD_card_identify.spin2** | Two-line card identification | No |
| **SD_card_characterize.spin2** | Card register reader | No |
| **SD_performance_benchmark.spin2** | Throughput measurement | Yes* |
| **SD_FAT32_audit.spin2** | Deep filesystem scan, read-only (same engine as fsck) | No |
| **SD_FAT32_fsck.spin2** | Filesystem check & repair | Yes |

*Creates temporary test files that are deleted after testing.

---

## Running Utilities

All utilities are run from the `tools/` directory using the test runner:

```bash
cd tools/
./run_test.sh ../src/UTILS/<utility>.spin2 [-t timeout]
```

---

## Utility Details

### 1. SD_format_card.spin2

**Purpose:** Format an SD card with a FAT32 filesystem.

Uses `isp_format_utility.spin2` (library) which provides the formatting logic.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_format_card.spin2 -t 120
```

**WARNING:** This will **ERASE ALL DATA** on the SD card!

**Creates:**
- MBR with single FAT32 LBA partition (type $0C)
- 4MB-aligned partition start (sector 8192)
- VBR (Volume Boot Record) with standard BPB
- Backup VBR at sector 6
- FSInfo sector with free cluster tracking
- Backup FSInfo at sector 7
- Dual FAT tables (FAT1 and FAT2)
- Root directory with volume label entry

**Cross-OS Compatibility:**
- Windows, macOS, and Linux compatible
- Follows Microsoft FAT32 specification
- Uses standard sector sizes and alignments

**Output:**
```
======================================================
  SD Card Format Utility
======================================================

WARNING: This will ERASE ALL DATA on the card!

Formatting card with label 'P2-BENCH'...

FORMAT SUCCESSFUL!

END_SESSION
```

---

### 2. SD_card_characterize.spin2

**Purpose:** Extract and display all card register information.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 60
```

**Reads and Displays:**

| Register | Size | Information |
|----------|------|-------------|
| **CID** | 16 bytes | Manufacturer ID, OEM ID, Product Name, Revision, Serial Number, Manufacturing Date |
| **CSD** | 16 bytes | Card capacity, transfer speeds, command classes, read/write block sizes |
| **SCR** | 8 bytes | SD specification version, security features, bus widths supported |
| **OCR** | 4 bytes | Operating voltage ranges, card capacity status |
| **VBR/BPB** | 512 bytes | FAT32 filesystem parameters |

**Sample Output** — banner and section structure verified against
`src/UTILS/SD_card_characterize.spin2` (v1.6.1). Field **values** below are
illustrative, not a captured run; every field marker and label is real. Registers
are tagged `[USED]` where the driver acts on the field and `[INFO]` where it is
reported only.

```
##############################################
#  SD Card Characterization Report V3       #
#  All register fields - comprehensive      #
##############################################

Initializing SD card (no-mount mode)...
Card initialized successfully.

--- Reading Card Registers ---
  CID: OK (16 bytes)
  CSD: OK (16 bytes)
  SCR: OK (8 bytes)
  OCR: OK (4 bytes)
  SD Status: OK (64 bytes)

======== CID REGISTER (Card Identification) ========
[USED] = Field used by V3 driver
[INFO] = Informational only

[USED] MID (Manufacturer ID):     $03 (SanDisk)
[INFO] OID (OEM/Application ID): $53 $44
[INFO] PNM (Product Name):        [SD64G]
[INFO] PRV (Product Revision):    8.0
[INFO] PSN (Serial Number):       $1234_5678
[INFO] MDT (Manufacturing Date): 2023-06
[INFO] CRC7:                      $6A

======== CSD REGISTER (Card Specific Data) ========

[USED] CSD_STRUCTURE:        1 (CSD Version 2.0)
       Card Type:            SDHC/SDXC (High Capacity)

--- Timing Parameters ---
[USED] TRAN_SPEED:           $32 (25 MHz max)
[USED] R2W_FACTOR:           2 (write time = read time x 4)
       Read Timeout:         1_000 ms (calculated)
       Write Timeout:        4_000 ms (calculated)

--- Capacity ---
       ... capacity, block, and feature fields follow ...
```

**Use Cases:**
- Identify card manufacturer and model
- Verify card capacity matches specification
- Check supported features before use
- Debug card compatibility issues
- Build a card database/catalog

---

### 3. SD_performance_benchmark.spin2

**Purpose:** Measure read/write throughput for real-world performance data.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
```

**Measurements:**

| Category | Tests |
|----------|-------|
| **Mount/Unmount** | Timing for card initialization and filesystem mount |
| **Raw Sector** | Hardware-level read/write bypassing filesystem |
| **Multi-Sector** | CMD18/CMD25 bulk transfers (8, 32, 64 sectors) |
| **Filesystem** | Real-world file read/write through driver API |
| **Overhead** | File open/close timing |

**Test Sizes (Based on Embedded Use Cases):**

| Size | Use Case |
|------|----------|
| 512 B | Single log entry |
| 4 KB | Configuration file |
| 32 KB | Icon or small data batch |
| 128 KB | Small display image |
| 256 KB | Larger display image |

**Output Format** — structure verified against
`src/UTILS/SD_performance_benchmark.spin2` (v1.6.1). Timings are **illustrative**:
throughput varies substantially by card, and quoting one card's numbers here would
read as a specification. Run it on your own card for figures you can rely on.

```
======================================================
  SD Card Performance Benchmark v2.0
======================================================

SysClk: 250 MHz
Iterations per test: 10

MOUNT:
  Mount time: 1_716.4 ms
  SPI Frequency: 20_833 kHz
  Volume: P2-BENCH
  Free: 1_915 MB (3_923_944 sectors)

------------------------------------------------------
  CARD IDENTIFICATION
------------------------------------------------------
  MID: $03  Product: SD64G
  CID: $03 $53 $44 $53 $44 $36 $34 $47
       $08 $12 $34 $56 $78 $01 $76 $00

------------------------------------------------------
  RAW SINGLE-SECTOR (1x512B per operation)
------------------------------------------------------

Single-Sector Read (10 iterations):
  1 sector(s) (512B): Min=731 Avg=753 Max=949 us => 679 KB/s

Single-Sector Write (10 iterations):
  1 sector(s) (512B): Min=1_131 Avg=1_133 Max=1_146 us => 451 KB/s

------------------------------------------------------
  RAW MULTI-SECTOR (CMD18/CMD25 bulk transfers)
------------------------------------------------------
  ... multi-sector, filesystem, and overhead sections follow ...
```

Every measurement reports `Min`/`Avg`/`Max` across its iterations, so a single slow
outlier is visible rather than averaged away.

**Statistics:**
- Each measurement repeated 10 times
- Reports min/avg/max values
- Calculates throughput in KB/s and MB/s

**Use Cases:**
- Establish performance baselines
- Compare different SD cards
- Measure impact of driver optimizations
- Verify production card performance

---

### 4. SD_FAT32_audit.spin2

**Purpose:** Verify FAT32 filesystem integrity without modifying the card.

`audit` and `fsck` are **two front-ends over one four-pass engine** — structural
integrity, chain validation, lost-cluster detection, and free-count verification.
The only difference is that `audit` suppresses every write: repair lines are
reported in the conditional -- each finding reads `needs repair: N lost clusters`,
and the run closes `Nothing was repaired -- run SD_FAT32_fsck to fix what is listed
above.` with `STATUS: REPAIRS NEEDED`. Nothing on the card is changed. Run `audit` first; run `fsck` when you want the repairs applied.

> **Since v1.6.0.** `audit` previously ran a shallower single-pass check and could
> report a damaged card as clean — notably a card carrying lost clusters from the
> pre-v1.6.0 write-path defect. It now runs the full scan. The separate
> check-only tool (`SD_FAT32_check`) is gone; `audit` supersedes it.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 60
```

**Read-Only:** This tool does NOT modify any data on the card.

**Checks Performed:**

| Structure | Validations |
|-----------|-------------|
| **MBR** | Boot signature, partition type, partition boundaries |
| **VBR** | Jump instruction, BPB fields, extended signature |
| **Backup VBR** | Matches primary VBR (sector 6) |
| **FSInfo** | All three signatures valid, free cluster count reasonable |
| **Backup FSInfo** | Matches primary FSInfo (sector 7) |
| **FAT Tables** | FAT1 and FAT2 match, media descriptor valid |
| **Root Directory** | Volume label present, structure valid |
| **Mount Test** | Driver can mount and read filesystem |

**Sample Output** — captured on Card 1 (SharedOEM SDHC 7 GB), v1.6.1, 2026-07-26.
Abridged: the MBR and VBR check lines are elided by count.

```
==============================================
  FAT32 Audit (via isp_fsck_utility)
==============================================

=== FAT32 Filesystem Audit ===
Read-only -- nothing on this card is changed.
Card: 15218688 sectors (7431 MB)

  Geometry:
    Partition start:  8192
    Sectors/cluster:  8
    Sectors/FAT:      14854
    Total clusters:   1897594
    Root cluster:     2
    Data start:       37932

Checking MBR (sector 0)...
  [PASS] MBR boot signature ($AA55)
  ... 4 more MBR checks ...

Checking VBR (boot sector)...
  [PASS] VBR jump ($EB or $E9)
  ... 17 more VBR checks ...

--- Pass 1: Structural Integrity ---
  [OK] Backup VBR matches
  [OK] FSInfo signatures
  [OK] Backup FSInfo matches
  [OK] FAT[0] media type
  [OK] FAT[1] EOC marker
  [OK] FAT[2] root cluster
  Pass 1: 0 repairs

--- Pass 2: Directory & Chain Validation ---
  Dirs: 1  Files: 0
  [OK] No lost clusters
  Pass 2/3: 0 repairs

--- Pass 4: FAT Sync & Free Count ---
  [OK] FAT1 and FAT2 in sync
  Free clusters: 1897593
  [OK] FSInfo free count correct
  Pass 4: 0 repairs


=== AUDIT COMPLETE ===
Errors: 0  Repairs needed: 0
Warnings: 0
Structural checks: 23 pass, 0 fail
Directories: 1  Files: 0
This filesystem is healthy.
STATUS: CLEAN

END_SESSION
```

An audit reports what it *would* fix — `Repairs needed:`, and `needs repair:` on each
finding — because it writes nothing. `SD_FAT32_fsck` reports the same findings as
`repaired:` and closes `=== FSCK COMPLETE ===` / `STATUS: REPAIRED`. Lost-cluster
recovery has no banner of its own: it runs inside pass 2 per bitmap window, so its
counts appear as `Pass 2/3`.

**Use Cases:**
- Verify filesystem after running tests
- Check card health before deployment
- Debug mount failures
- Validate format utility output

---

### 5. SD_FAT32_fsck.spin2

**Purpose:** Check and repair FAT32 filesystem corruption.

**Usage:**
```bash
./run_test.sh ../src/UTILS/SD_FAT32_fsck.spin2 -t 300
```

**WARNING:** This tool **modifies the card** to repair detected problems. Run the audit tool first if you want a read-only check.

**Four-Pass Architecture:**

| Pass | Name | Purpose |
|------|------|---------|
| **Pass 1** | Structural Integrity | Repair VBR backup, FSInfo signatures/backup, FAT[0]/[1]/[2] entries |
| **Pass 2** | Directory & Chain Validation | Walk directory tree, validate cluster chains, detect cross-links (windowed) |
| **Pass 3** | Lost Cluster Recovery | Free allocated clusters not referenced by any file or directory (per window, interleaved with Pass 2) |
| **Pass 4** | FAT Sync & Free Count | Synchronize FAT1 -> FAT2, correct FSInfo free cluster count |

**Repairs Performed:**

| Category | Repairs |
|----------|---------|
| **VBR** | Restore backup VBR from primary |
| **FSInfo** | Fix lead/struct/trail signatures, restore backup |
| **FAT entries** | Fix media type (FAT[0]), EOC marker (FAT[1]), root cluster (FAT[2]) |
| **Cluster chains** | Truncate chains with bad references |
| **Cross-links** | Detect clusters referenced by multiple chains |
| **Lost clusters** | Free allocated but unreferenced clusters |
| **FAT sync** | Copy FAT1 to FAT2 where sectors differ |
| **Free count** | Recalculate and update FSInfo free cluster count |

**Memory Requirements:**

The cluster bitmap uses 256 KB of P2 hub RAM (LONG[65536]), covering up to 2,097,152 clusters per window. For cards exceeding 2 million clusters (approximately 64 GB), the utility uses windowed bitmap scanning -- processing the cluster space in 2M-cluster passes. The directory tree is re-walked for each window, and lost cluster recovery runs after each window. This extends full 4-pass validation to cards of any size.

**Sample Output** — captured on Card 1 (SharedOEM SDHC 7 GB), v1.6.1, 2026-07-26.
Abridged: the MBR and VBR check lines are elided by count.

```
=== FAT32 Filesystem Check & Repair ===
Card: 15218688 sectors (7431 MB)

  Geometry:
    Partition start:  8192
    Sectors/cluster:  8
    Sectors/FAT:      14854
    Total clusters:   1897594
    Root cluster:     2
    Data start:       37932

Checking MBR (sector 0)...
  [PASS] MBR boot signature ($AA55)
  ... 4 more MBR checks ...

Checking VBR (boot sector)...
  [PASS] VBR jump ($EB or $E9)
  ... 17 more VBR checks ...

--- Pass 1: Structural Integrity ---
  [OK] FAT[2] root cluster
  Pass 1: 0 repairs

--- Pass 2: Directory & Chain Validation ---
  Dirs: 1  Files: 0
  [OK] No lost clusters
  Pass 2/3: 0 repairs

--- Pass 4: FAT Sync & Free Count ---
  [OK] FAT1 and FAT2 in sync
  Free clusters: 1897593
  [OK] FSInfo free count correct
  Pass 4: 0 repairs


=== FSCK COMPLETE ===
Errors: 0  Repairs: 0
Warnings: 0
Structural checks: 23 pass, 0 fail
Directories: 1  Files: 0
This filesystem is healthy.
STATUS: CLEAN

END_SESSION
```

Lost-cluster recovery has no pass banner of its own: it runs inside pass 2 per
bitmap window, so the counts report as `Pass 2/3`. A read-only `SD_FAT32_audit`
run prints the same passes but closes with `=== AUDIT COMPLETE ===`,
`Repairs needed:` in place of `Repairs:`, and — when there is anything to fix —
`STATUS: REPAIRS NEEDED` with a pointer to `SD_FAT32_fsck`.

**Status Messages:**
- **CLEAN** - No errors or repairs needed
- **REPAIRED** - Errors found and successfully repaired
- **ERRORS REMAIN** - Some errors could not be automatically repaired

**Use Cases:**
- Repair filesystem after unexpected power loss or reset
- Fix corruption after failed write operations
- Recover lost disk space from orphaned cluster chains
- Synchronize FAT1 and FAT2 after partial writes
- Verify and correct FSInfo free cluster count
- Run after audit reports failures to auto-repair them

---

## Directory Structure

```
src/UTILS/
├── SD_format_card.spin2            # FAT32 card formatter
├── SD_card_identify.spin2          # Two-line card identification
├── SD_card_characterize.spin2      # Card register reader
├── SD_performance_benchmark.spin2  # Throughput measurement
├── SD_FAT32_audit.spin2            # Filesystem validator
├── SD_FAT32_fsck.spin2             # Filesystem check & repair
├── isp_format_utility.spin2        # FAT32 format library (used by SD_format_card)
├── isp_fsck_utility.spin2          # Combined FSCK + Audit library (runs in temp cog)
└── isp_string_fifo.spin2           # Lock-free inter-cog string FIFO
```

---

## Recommended Workflow

### New Card Setup

1. **Identify** - Quick two-line card summary
   ```bash
   ./run_test.sh ../src/UTILS/SD_card_identify.spin2
   ```

2. **Characterize** - Read card registers to identify the card
   ```bash
   ./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 60
   ```

3. **Format** - Create clean FAT32 filesystem
   ```bash
   ./run_test.sh ../src/UTILS/SD_format_card.spin2 -t 120
   ```

4. **Audit** - Verify filesystem structure
   ```bash
   ./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 60
   ```

5. **Benchmark** - Measure performance baseline
   ```bash
   ./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
   ```

### After Testing

Run the audit tool to verify filesystem integrity:
```bash
./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 60
```

If the audit reports failures, run FSCK to auto-repair:
```bash
./run_test.sh ../src/UTILS/SD_FAT32_fsck.spin2 -t 300
```

---

## Hardware Configuration

All utilities use the P2 Edge default pin configuration:

```spin2
CON
    SD_CS   = 60    ' Chip Select
    SD_MOSI = 59    ' Master Out Slave In
    SD_MISO = 58    ' Master In Slave Out
    SD_SCK  = 61    ' Serial Clock
```

Modify the `CON` section in each utility if using different pins.

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
