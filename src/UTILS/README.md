# SD Card Driver Utilities

Standalone utility programs for card formatting, characterization, performance testing, and filesystem validation.

> **What belongs here:** standalone tools **the user** runs. A non-user-facing probe belongs in [`diagnostic-tests/`](../../diagnostic-tests/) (those are for us); an automated pass/fail suite belongs in [`src/regression-tests/`](../regression-tests/). The `isp_*` files here are **support libraries** these tools depend on, not standalone utilities.

## Overview

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

## Building and Running Utilities

### Prerequisites

- **pnut-ts** and **pnut-term-ts** - See detailed installation instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**
- Parallax Propeller 2 (P2 Edge or P2 board with microSD add-on) connected via USB

### Compile and Run

All utilities are run from the `tools/` directory using the test runner:

```bash
cd tools/
./run_test.sh ../src/UTILS/<utility>.spin2 [-t timeout]
```

The test runner compiles with `pnut-ts`, downloads to P2 hardware, captures debug output in headless mode, and saves logs to `tools/logs/`.

Alternatively, from this `UTILS/` directory:

```bash
# Compile a utility
pnut-ts -d -I .. <utility>.spin2

# Download and run on P2 (connects at 2 Mbit serial)
pnut-term-ts -r <utility>.bin
```

The `-I ..` flag tells the compiler to find the SD card driver in the parent directory.

---

## Utility Details

### 1. SD_format_card.spin2

**Purpose:** Format an SD card with a FAT32 filesystem.

Uses `isp_format_utility.spin2` (library) which provides the formatting logic.

**Compile and Run:**
```bash
pnut-ts -d -I .. SD_format_card.spin2
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

### 2. SD_card_characterize.spin2

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

**Sample Output:** see
[`DOCs/SD-CARD-UTILITIES.md`](../../DOCs/SD-CARD-UTILITIES.md) — that document holds
the canonical, capture-stamped transcript for this utility.

**Use Cases:**
- Identify card manufacturer and model
- Verify card capacity matches specification
- Check supported features before use
- Debug card compatibility issues
- Build a card database/catalog

---

### 3. SD_performance_benchmark.spin2

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

**Compile and Run:**
```bash
pnut-ts -d -I .. SD_FAT32_audit.spin2
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

**Sample Output:** see
[`DOCs/SD-CARD-UTILITIES.md`](../../DOCs/SD-CARD-UTILITIES.md) — that document holds
the canonical, capture-stamped transcript for this utility.

> Transcripts are maintained in one place on purpose. They used to be duplicated
> here, in `.release/src/UTILS/README.md`, and in `DOCs/SD-CARD-UTILITIES.md`; the
> three copies drifted apart and two of them documented output the tool had stopped
> printing. `tools/check_doc_claims.sh` now fails the release checklist on a
> duplicated transcript.

**Use Cases:**
- Verify filesystem after running tests
- Check card health before deployment
- Debug mount failures
- Validate format utility output

---

### 5. SD_FAT32_fsck.spin2

**Purpose:** Check and repair FAT32 filesystem corruption.

**Compile and Run:**
```bash
pnut-ts -d -I .. SD_FAT32_fsck.spin2
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

**Sample Output:** see
[`DOCs/SD-CARD-UTILITIES.md`](../../DOCs/SD-CARD-UTILITIES.md) — that document holds
the canonical, capture-stamped transcript for this utility.

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

## Recommended Workflow

### New Card Setup

From the `tools/` directory:

1. **Identify** - Quick two-line card summary
   ```bash
   ./run_test.sh ../src/UTILS/SD_card_identify.spin2
   ```

2. **Characterize** - Full register dump
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
