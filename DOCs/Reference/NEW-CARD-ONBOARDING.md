# New Card Onboarding Pipeline

Complete procedure for characterizing, formatting, benchmarking, and cataloging a new microSD card for the P2 SD driver.

## Overview

When a new microSD card arrives, this pipeline identifies the card, formats it for P2 use, determines its SPI speed limits, and measures performance at two sysclk speeds. All results are recorded in a card catalog file under `DOCs/cards/`.

**Standard benchmark speeds:** 350 MHz and 250 MHz sysclk

These speeds were chosen because both produce **exact 25 MHz SPI** (the SD spec maximum):
- 350 MHz: half_period = 7, SPI = 350 / (2 * 7) = **25.000 MHz**
- 250 MHz: half_period = 5, SPI = 250 / (2 * 5) = **25.000 MHz**

Compare to the previous 320/270 MHz pair which produced sub-optimal SPI:
- 320 MHz: hp = 7, SPI = 320 / 14 = 22.857 MHz (-8.6% from spec max)
- 270 MHz: hp = 6, SPI = 270 / 12 = 22.500 MHz (-10.0% from spec max)

## Prerequisites

- P2 Edge Module with microSD socket wired
- `pnut-ts` and `pnut-term-ts` installed
- Card inserted in the P2's microSD socket
- Terminal connected (USB serial at 2 Mbps)
- All commands run from `tools/` directory

---

## Step 1: Card Characterization

**Utility:** `src/UTILS/SD_card_characterize.spin2`
**Purpose:** Read all card registers (CID, CSD, OCR, SCR) and filesystem info
**Sysclk:** 270 MHz (default, fine for characterization)

```bash
cd tools/
./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 60
```

**What to capture from the output:**
- Raw register hex dumps (CID, CSD, OCR, SCR)
- Manufacturer ID (MID) and product name (PNM)
- Unique Card ID string (generated at end)
- MBR partition type (identifies factory filesystem: $07 = exFAT, $0C = FAT32)
- VBR/BPB fields (if FAT32)

**Key decision:** If the partition type is $07 (exFAT/NTFS), the card needs formatting before it can be used with the P2 driver.

---

## Step 2: Create Card Catalog Entry

**Location:** `DOCs/cards/<manufacturer>-<product>-<size>.md`
**Naming convention:** lowercase, dashes, e.g. `lexar-mssd0-64gb.md`

Create the initial card file from the characterization output. Use an existing card file as template. Include:

1. Header with label, unique ID, test date
2. Raw registers section (hex dumps)
3. CID register table (all fields with [USED]/[INFO] annotations)
4. CSD register table (all fields)
5. OCR register table
6. SCR register table
7. Filesystem section (factory format info)
8. Test results table (characterization results)
9. Notes section (manufacturer info, speed class, features)

Leave placeholder sections for SPI speed characterization and benchmark results.

---

## Step 3: Filesystem Check and Format (if needed)

### 3a: Check Filesystem Health

**Utility:** `src/UTILS/SD_FAT32_fsck.spin2`
**Purpose:** Verify FAT32 filesystem integrity
**Sysclk:** 270 MHz (default)

```bash
cd tools/
./run_test.sh ../src/UTILS/SD_FAT32_fsck.spin2 -t 300
```

**Decision tree based on Step 1 characterization + fsck results:**
- **Card is already FAT32 and fsck passes** → Skip formatting, proceed to Step 4
- **Card is FAT32 but fsck reports errors** → Format (Step 3b)
- **Card is exFAT ($07) or other non-FAT32** → Format (Step 3b)

### 3b: Format with P2FMTER (only if needed)

**Utility:** `src/UTILS/SD_format_card.spin2`
**Purpose:** Format with FAT32 filesystem (label "P2-BENCH")
**Sysclk:** 270 MHz (default)

> **WARNING:** This erases all data on the card!

```bash
cd tools/
./run_test.sh ../src/UTILS/SD_format_card.spin2 -t 120
```

**What to capture:**
- Total sectors and card size
- Sectors/cluster, sectors/FAT, total clusters
- Partition start, FAT1/FAT2 start, data start
- FORMAT COMPLETE confirmation

After formatting, re-run characterization to capture the new FAT32 filesystem details:
```bash
./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 60
```

Update the card catalog file with the FAT32 filesystem section.

---

## Step 4: SPI Frequency Sweep (New Cards Only)

**Utility:** `src/UTILS/SD_speed_characterize.spin2`
**Purpose:** Find maximum reliable SPI clock frequency
**Sysclk:** 200 MHz (default - provides clean SPI clock divisions)

> **Skip this step** if the card model has already been speed-characterized in a prior session. The SPI speed limit is a property of the card's controller silicon, not the individual unit. Check the card's existing file or CARD-CATALOG.md for prior results.

```bash
cd tools/
./run_test.sh ../src/UTILS/SD_speed_characterize.spin2 -t 300
```

**Test structure (per SPI speed level):**
- Phase 1: 1,000 single-sector reads with CRC-16 verification
- Phase 2: 10,000 single-sector reads (statistical confidence)
- Phase 3: 100 x 8-sector multi-block reads (sustained transfer)
- Total: 11,800 sector reads per speed level

**SPI speeds tested:** 18, 20, 22, 25, 27, 30, 33, 36, 40, 45, 50 MHz

**What to capture:**
- Pass/fail for each speed level and phase
- Maximum reliable speed (highest speed with 0% failure)
- CMD6 High Speed mode result
- Phase 2 duration at max speed (for internal throughput calculation)

**Key insight:** Most cards max out at 25 MHz. The CMD6 High Speed switch typically fails and renders the card unresponsive - this is the normal failure mode, not a gradual degradation.

Update the card catalog with the SPI Speed Characterization section.

---

## Step 5: Performance Benchmarking

**Utility:** `src/UTILS/SD_performance_benchmark.spin2`
**Purpose:** Measure throughput at raw, multi-sector, and file levels

Run at **two sysclk speeds** (350 MHz and 250 MHz):

### 350 MHz Run

1. Edit `src/UTILS/SD_performance_benchmark.spin2`:
   ```
   _CLKFREQ = 350_000_000
   ```

2. Run:
   ```bash
   cd tools/
   ./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 120
   ```

### 250 MHz Run

1. Edit `src/UTILS/SD_performance_benchmark.spin2`:
   ```
   _CLKFREQ = 250_000_000
   ```

2. Run:
   ```bash
   cd tools/
   ./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 120
   ```

### Restore default

After both runs, restore the standard clock speed:
```
_CLKFREQ = 350_000_000
```

**What to capture for each run:**
- SysClk and actual SPI frequency
- Mount time
- Raw single-sector read/write (Min/Avg/Max us, KB/s)
- Raw multi-sector read/write at 8, 32, 64 sectors
- File-level write at 512B, 4KB, 32KB
- File-level read at 4KB, 32KB, 128KB, 256KB
- File open/close overhead
- Multi-sector improvement percentage

Update the card catalog with both benchmark tables plus the Sysclk Effect comparison.

---

## Handling Flash Housekeeping Events

During benchmarking, some cards exhibit anomalous write latency caused by internal flash controller housekeeping — wear leveling, garbage collection (GC), or block remapping. These are card-state-dependent and unpredictable.

### How to Recognize

A flash housekeeping event looks like this in benchmark results:
- **Single-sector write avg wildly above normal**: e.g., 46,988 us instead of ~1,300 us
- **Huge Min/Max spread**: e.g., Min=32,874, Max=65,480 us (all iterations slow)
- **Multi-sector writes also affected**: cascading slowness across all write tests in that run
- **Read performance normal**: only writes are affected (flash programming is the bottleneck)

The Samsung GD4QT 128GB exhibited this at 350 MHz: raw single-sector write avg of 46,988 us vs the clean 250 MHz run's 1,298 us. The 250 MHz run (done after the card settled) was normal.

### Standard Response

1. **Complete the current benchmark run** — don't abort. The read data and file-level data may still be valid.
2. **Check the 250 MHz run**: if it runs clean, the 350 MHz write anomaly was a housekeeping event, not a driver issue.
3. **If both runs show anomalous writes**:
   a. Wait 30-60 seconds (let the card finish internal operations)
   b. Run a quick throwaway write cycle (e.g., mount test) to trigger any pending GC
   c. Re-run the affected benchmark
4. **Record what happened**: annotate the affected results with a footnote (e.g., `\* Flash controller housekeeping pause — see 250 MHz run for representative write performance`)
5. **Use the clean run for cross-card comparisons**: if one run was affected and the other wasn't, use the clean run's write numbers in BENCHMARK-RESULTS.md comparison tables. Mark the affected run with `— †` and explain in a footnote.

### Pre-Conditioning (Optional)

For cards known to be housekeeping-prone (Samsung, large-capacity cards):
- Before benchmarking, run the format test (`SD_RT_format_tests.spin2`) — this does heavy write activity that may trigger GC
- Wait 30 seconds after the format test completes
- Then proceed with the benchmark

### Key Insight

Flash housekeeping is **not a driver bug**. It's the card's internal controller performing maintenance. The same card can produce clean or anomalous results depending on its internal state. Our response is to: detect it, annotate it, use clean data for comparisons, and re-run if needed.

---

## Step 6: Update Card Catalog

Add the following sections to the card catalog file:

1. **SPI Speed Characterization** - frequency sweep results table
2. **Internal Throughput** - calculated from Phase 2 duration
3. **Benchmark Results** - both clock speed runs with full tables
4. **Sysclk Effect** - comparison table (350 vs 250 MHz)
5. **Notes** - any interesting observations about the card's behavior

---

## Appendix A: Clock Speed / SPI Frequency Reference

The P2 SPI clock is derived from sysclk:

```
SPI_freq = sysclk / (2 * half_period)
half_period = ceil(sysclk / (2 * target_SPI))
```

| Sysclk (MHz) | half_period | Actual SPI (MHz) | Delta from 25 MHz |
|---------------|-------------|------------------|-------------------|
| **350** | **7** | **25.000** | **0.0%** |
| 320 | 7 | 22.857 | -8.6% |
| 300 | 6 | 25.000 | 0.0% |
| 270 | 6 | 22.500 | -10.0% |
| **250** | **5** | **25.000** | **0.0%** |
| 200 | 4 | 25.000 | 0.0% |

**Recommended benchmark pair:** 350 MHz / 250 MHz (both produce exact 25 MHz SPI)

This means performance differences between the two speeds are purely due to **Spin2 code execution speed** (driver overhead, FAT traversal, cluster allocation), not SPI transfer rate. This cleanly isolates the sysclk effect on driver overhead.

---

## Appendix B: Re-Running Benchmarks for Existing Cards

To benchmark an existing card at 350/250 MHz (e.g., to update catalog data from old 320/270 runs):

### Quick benchmark (performance only)

1. Insert the card
2. Edit `src/UTILS/SD_performance_benchmark.spin2`: set `_CLKFREQ = 350_000_000`
3. Run: `./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 120`
4. Save the log
5. Edit: set `_CLKFREQ = 250_000_000`
6. Run again, save the log
7. Restore: set `_CLKFREQ = 350_000_000`
8. Update the card's catalog file with both new benchmark tables

### Full re-characterization (benchmark + documentation)

Follow Steps 5-6 of this pipeline. Skip Steps 1-4 (card is already characterized and formatted).

### Batch update script (future)

A batch script could automate the _CLKFREQ edit-compile-run-restore cycle across all test files. For now, the manual process ensures each step is verified.
