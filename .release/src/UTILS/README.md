# SD Card Utilities

Standalone utility programs for preparing SD cards for embedded use, diagnosing filesystem problems, and characterizing untested cards.

## Overview

The primary utilities are for **card preparation and recovery**: formatting a card for use, validating the filesystem after normal operation, and repairing corruption after unexpected events like power loss during a write.

The characterization and benchmark utilities are for **evaluating untested cards** — identifying a card's registers and measuring its throughput when you're working with a card model that hasn't been used with the driver before.

### Utility Summary

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **SD_format_card.spin2** | FAT32 card formatter | Yes |
| **SD_FAT32_audit.spin2** | Filesystem validator (read-only) | No |
| **SD_FAT32_fsck.spin2** | Filesystem check & repair | Yes |
| **SD_card_identify.spin2** | Two-line card identification | No |
| **SD_card_characterize.spin2** | Card register reader | No |
| **SD_performance_benchmark.spin2** | Throughput measurement | Yes* |

*Creates temporary test files that are deleted after testing.

---

## Building and Running Utilities

See [Prerequisites](../../README.md#prerequisites) for toolchain and hardware requirements.

### Compile and Run

From this `UTILS/` directory:

```bash
# Simple utilities (only need driver path)
pnut-ts -d -I .. <utility>.spin2
pnut-term-ts -r <utility>.bin

# Utilities that use format or fsck libraries (also need DEMO/ for isp_mem_strings)
pnut-ts -d -I .. -I ../DEMO <utility>.spin2
pnut-term-ts -r <utility>.bin
```

The `-I ..` flag tells the compiler to find the SD card driver in the parent directory. The `-I ../DEMO` flag is needed by utilities that use `isp_format_utility` or `isp_fsck_utility` (which depend on `isp_mem_strings` in the DEMO/ directory).

---

## Utility Details

### 1. SD_format_card.spin2

**Purpose:** Format an SD card with a FAT32 filesystem.

Uses `isp_format_utility.spin2` (library) which provides the formatting logic.

**Compile and Run:**
```bash
pnut-ts -d -I .. -I ../DEMO SD_format_card.spin2
pnut-term-ts -r SD_format_card.bin
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

### 2. SD_card_identify.spin2

**Purpose:** Quick two-line card identification for catalog entries and benchmarking.

**Compile and Run:**
```bash
pnut-ts -d -I .. SD_card_identify.spin2
pnut-term-ts -r SD_card_identify.bin
```

**Output Format:**
```
L1: Samsung SE16G SDHC 14GB [FAT32] SD 3.x rev1.0 SN:4E3300C4 2018/07
L2: Class 6, U0, V0, SPI 25 MHz  [MSWIN4.1]
```

Line 1 contains identity: manufacturer, product name, card type, capacity, filesystem, SD spec version, firmware revision, serial number, and manufacturing date. Line 2 contains performance class and OEM formatter name.

**Use Cases:**
- Generate card catalog entries
- Identify unknown cards before benchmarking
- Quick card verification during testing

---

### 3. SD_card_characterize.spin2

**Purpose:** Extract and display all card register information.

**Compile and Run:**
```bash
pnut-ts -d -I .. SD_card_characterize.spin2
pnut-term-ts -r SD_card_characterize.bin
```

**Reads and Displays:**

| Register | Size | Information |
|----------|------|-------------|
| **CID** | 16 bytes | Manufacturer ID, OEM ID, Product Name, Revision, Serial Number, Manufacturing Date |
| **CSD** | 16 bytes | Card capacity, transfer speeds, command classes, read/write block sizes |
| **SCR** | 8 bytes | SD specification version, security features, bus widths supported |
| **OCR** | 4 bytes | Operating voltage ranges, card capacity status |
| **VBR/BPB** | 512 bytes | FAT32 filesystem parameters |

**Sample Output:**
```
┌──────────────────────────────────────────┐
│ SD Card Characterization Diagnostic      │
└──────────────────────────────────────────┘

========== CID (Card Identification) ==========
  Manufacturer ID:    $03 (SanDisk)
  OEM/Application ID: "SD"
  Product Name:       "SD64G"
  Product Revision:   8.0
  Serial Number:      $12345678
  Manufacturing Date: 2023/06

========== CSD (Card Specific Data) ==========
  CSD Version:        2.0 (SDHC/SDXC)
  Card Capacity:      59.48 GB
  Max Transfer Rate:  50 MHz
  Read Block Length:  512 bytes
  ...

========== Filesystem (VBR/BPB) ==========
  Volume Label:       P2-XFER
  Sectors per Cluster: 64
  Total Sectors:      124735488
  Free Space:         59.45 GB
```

**Use Cases:**
- Identify card manufacturer and model
- Verify card capacity matches specification
- Check supported features before use
- Debug card compatibility issues
- Build a card database/catalog

---

### 4. SD_performance_benchmark.spin2

**Purpose:** Measure read/write throughput for real-world performance data.

**Compile and Run:**
```bash
pnut-ts -d -I .. SD_performance_benchmark.spin2
pnut-term-ts -r SD_performance_benchmark.bin
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

**Output Format:**
```
SD Card Performance Benchmark
=============================
Card: Gigastone 32GB

Raw Sector Performance:
  Read:  512 bytes in 0.42 ms (1.19 MB/s)
  Write: 512 bytes in 2.31 ms (0.22 MB/s)

Multi-Sector Performance (64 sectors = 32KB):
  Read:  32768 bytes in 18.2 ms (1.76 MB/s)
  Write: 32768 bytes in 45.7 ms (0.70 MB/s)

Filesystem Performance:
  File Read (32KB):  62.3 ms (513 KB/s)
  File Write (32KB): 89.1 ms (359 KB/s)
  File Open:         12.4 ms
  File Close:        8.7 ms
```

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

### 5. SD_FAT32_audit.spin2

**Purpose:** Verify FAT32 filesystem integrity without modifying the card.

**Compile and Run:**
```bash
pnut-ts -d -I .. -I ../DEMO SD_FAT32_audit.spin2
pnut-term-ts -r SD_FAT32_audit.bin
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

**Sample Output:**
```
==============================================
  FAT32 Filesystem Audit Tool
  (Read-only - does not modify card)
==============================================

* Initializing card...
Card initialized successfully

=== MBR Structure ===
[PASS] Boot signature: $AA55
[PASS] Partition type: $0C (FAT32 LBA)
[PASS] Partition start: 8192 (4MB aligned)

=== VBR Structure ===
[PASS] Jump instruction: $EB
[PASS] Bytes per sector: 512
[PASS] Sectors per cluster: 64
[PASS] Reserved sectors: 32
...

=== FAT Consistency ===
[PASS] FAT1 media descriptor: $F8
[PASS] FAT2 matches FAT1

=== Summary ===
Tests: 24, Passed: 24, Failed: 0
Filesystem integrity: OK

END_SESSION
```

**Use Cases:**
- Verify filesystem after running tests
- Check card health before deployment
- Debug mount failures
- Validate format utility output

---

### 6. SD_FAT32_fsck.spin2

**Purpose:** Check and repair FAT32 filesystem corruption.

**Compile and Run:**
```bash
pnut-ts -d -I .. -I ../DEMO SD_FAT32_fsck.spin2
pnut-term-ts -r SD_FAT32_fsck.bin
```

**WARNING:** This tool **modifies the card** to repair detected problems. Run the audit tool first if you want a read-only check.

**Four-Pass Architecture:**

| Pass | Name | Purpose |
|------|------|---------|
| **Pass 1** | Structural Integrity | Repair VBR backup, FSInfo signatures/backup, FAT[0]/[1]/[2] entries |
| **Pass 2** | Directory & Chain Validation | Walk directory tree, validate cluster chains, detect cross-links |
| **Pass 3** | Lost Cluster Recovery | Free allocated clusters not referenced by any file or directory |
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

The cluster bitmap uses 256KB (LONG[65536]) covering 2,097,152 clusters per window. For cards up to approximately 64GB, a single window suffices. Larger cards are processed using multiple bitmap windows — the directory tree is re-walked for each window, and lost cluster recovery runs per window. All four passes execute regardless of card size.

**Sample Output:**
```
==============================================
  FAT32 Filesystem Check & Repair (FSCK)
==============================================

* Initializing card...
  Card: 31_207_424 sectors (15_238 MB)

  Geometry:
    Partition start:  8_192
    Sectors/cluster:  16
    Sectors/FAT:      15_234
    Total clusters:   1_948_045

--- Pass 1: Structural Integrity ---
  [OK] Backup VBR matches primary
  [OK] FSInfo signatures correct
  [OK] Backup FSInfo matches primary
  [OK] FAT[0] media type correct
  [OK] FAT[1] EOC marker correct
  [OK] FAT[2] root cluster allocated
  Pass 1: 0 repairs

--- Pass 2: Directory & Chain Validation ---
  Directories scanned: 1
  Files scanned:       0
  Pass 2: 0 repairs

--- Pass 3: Lost Cluster Recovery ---
  [OK] No lost clusters found
  Pass 3: 0 repairs

--- Pass 4: FAT Sync & Free Count ---
  [OK] FAT1 and FAT2 in sync
  Free clusters: 1_948_044
  [OK] FSInfo free count correct
  Pass 4: 0 repairs

==============================================
  FSCK COMPLETE
==============================================
  Errors found:  0
  Repairs made:  0
  Warnings:      0
  Directories:   1
  Files:         0

  FILESYSTEM STATUS: CLEAN
==============================================

END_SESSION
```

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
UTILS/
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

## Typical Workflows

### Preparing a Card for Use

Format the card, then verify the filesystem is clean. From this `UTILS/` directory:

1. **Format** - Create a clean FAT32 filesystem
   ```bash
   pnut-ts -d -I .. -I ../DEMO SD_format_card.spin2
   pnut-term-ts -r SD_format_card.bin
   ```

2. **Audit** - Verify the filesystem structure
   ```bash
   pnut-ts -d -I .. -I ../DEMO SD_FAT32_audit.spin2
   pnut-term-ts -r SD_FAT32_audit.bin
   ```

### Diagnosing and Repairing Problems

If your embedded system lost power during a write, or the card is behaving unexpectedly, run audit first to see what's wrong, then FSCK to repair:

```bash
pnut-ts -d -I .. -I ../DEMO SD_FAT32_audit.spin2
pnut-term-ts -r SD_FAT32_audit.bin
```

If the audit reports failures, run FSCK to auto-repair:
```bash
pnut-ts -d -I .. -I ../DEMO SD_FAT32_fsck.spin2
pnut-term-ts -r SD_FAT32_fsck.bin
```

### Characterizing an Untested Card

If you're working with a card model that hasn't been used with this driver before, identify it, then optionally run detailed characterization and benchmarking:

1. **Identify** - Quick two-line card summary for catalog
   ```bash
   pnut-ts -d -I .. SD_card_identify.spin2
   pnut-term-ts -r SD_card_identify.bin
   ```

2. **Characterize** - Full register dump (manufacturer, capacity, speed class)
   ```bash
   pnut-ts -d -I .. SD_card_characterize.spin2
   pnut-term-ts -r SD_card_characterize.bin
   ```

3. **Benchmark** - Measure read/write throughput
   ```bash
   pnut-ts -d -I .. SD_performance_benchmark.spin2
   pnut-term-ts -r SD_performance_benchmark.bin
   ```

---

## Hardware Configuration

The microSD add-on board connects to any 8-pin header group on the P2. Pins are defined as offsets from the base pin of the group:

| Offset | Signal | Description |
|--------|--------|-------------|
| +5 | CLK (SCK) | Serial Clock |
| +4 | CS (DAT3) | Chip Select |
| +3 | MOSI (CMD) | Master Out, Slave In |
| +2 | MISO (DAT0) | Master In, Slave Out |
| +1 | Insert Detect | Active low when card inserted (not used by driver) |

The default configuration uses base pin 56 (P2 Edge Module):

```spin2
CON
    SD_BASE = 56
    SD_SCK  = SD_BASE + 5    ' P61 - Serial Clock
    SD_CS   = SD_BASE + 4    ' P60 - Chip Select
    SD_MOSI = SD_BASE + 3    ' P59 - Master Out Slave In
    SD_MISO = SD_BASE + 2    ' P58 - Master In Slave Out
```

To use a different 8-pin group, change `SD_BASE` in the `CON` section of each utility.

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
