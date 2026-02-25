# SD Card Driver Benchmark Results

**Document Purpose**: Record actual performance measurements from benchmark testing
**Test Program**: `src/UTILS/SD_performance_benchmark.spin2` (v2.0)
**Standard Protocol**: 350 MHz and 250 MHz sysclk, both producing exactly 25 MHz SPI clock
**Driver**: Smart Pin SPI + Multi-Sector (CMD18/CMD25) + TX Streamer Fix (commit d62e30d)

Detailed per-card benchmark data is in each card's page under [DOCs/cards/](cards/). This document provides cross-card comparisons and analysis.

---

## Test Configuration

- **Hardware**: P2 Edge Module with microSD slot
- **Pins**: CS=P60, MOSI=P59, MISO=P58, SCK=P61
- **Iterations**: 10 per test (averaged)
- **Standard Protocol**: 350 MHz and 250 MHz sysclk both produce exactly 25,000 kHz SPI clock — this isolates Spin2 inter-transfer overhead from SPI bus speed
- **Test Dates**: 2026-01-21 (bit-banged baseline), 2026-02-07 through 2026-02-25 (current driver)

---

## Current Driver Results (350 MHz, 25 MHz SPI)

Test program: `src/UTILS/SD_performance_benchmark.spin2` v2.0
Measurements across three levels: raw single-sector, raw multi-sector (CMD18/CMD25), and file-level (handle API).

### Cross-Card Comparison (350 MHz, 15 Cards)

All throughput values in KB/s. Ranked by composite score (see [SD-CARD-PERFORMANCE.md](../release-check/DOCs/SD-CARD-PERFORMANCE.md) for scoring methodology).

| Card | Score | File Rd | File Wr | Rd 64x | Wr 64x | Rd 1x | Wr 1x | Detail |
|------|------:|--------:|--------:|-------:|-------:|------:|------:|--------|
| Amazon Basics 64GB | **99** | 1,386 | **774** | 2,425 | 2,305 | 1,245 | **846** | [card](cards/amazon-basics-usd00-64gb.md) |
| Samsung PRO Endurance 128GB | **98** | 1,419 | 758 | **2,427** | **2,319** | **1,283** | 617 | [card](cards/samsung-jd1y7-128gb.md) |
| Lexar Blue 128GB | **91** | **1,444** | 616 | 2,420 | 2,275 | 819 | 680 | [card](cards/lexar-mssd0-128gb.md) |
| Lexar V30 64GB | **88** | 1,378 | 433 | 2,376 | 2,251 | 1,239 | 674 | [card](cards/lexar-mssd0-64gb.md) |
| SanDisk Extreme PRO 64GB | **80** | 1,101 | 437 | 2,408 | 2,210 | 998 | 428 | [card](cards/sandisk-aggce-64gb.md) |
| SanDisk Extreme PRO 128GB | **78** | 1,103 | 445 | 2,408 | 2,140 | 842 | 427 | [card](cards/sandisk-aggcf-128gb.md) |
| SanDisk Extreme 64GB | **76** | 1,040 | 378 | 2,408 | 2,150 | 1,005 | 331 | [card](cards/sandisk-sn64g-64gb.md) |
| SanDisk MAX Endurance 32GB | **76** | 1,036 | 367 | 2,407 | 2,154 | 998 | 330 | [card](cards/sandisk-sh32g-32gb.md) |
| SanDisk Switch 128GB | **75** | 1,016 | 378 | 2,406 | 2,152 | 887 | 332 | [card](cards/sandisk-sn128-128gb.md) |
| WD Purple 64GB | **74** | 990 | 362 | 2,403 | 2,148 | 920 | 333 | [card](cards/sandisk-wx64g-64gb.md) |
| Gigastone Camera+ 64GB | **72** | 1,091 | 293 | 2,134 | 2,142 | 915 | 349 | [card](cards/gigastone-astc-64gb.md) |
| Samsung EVO 128GB | **70** | 835 | 323 | 2,348 | 2,110 | 914 | 425 | [card](cards/samsung-gd4qt-128gb.md) |
| SanDisk Industrial 16GB | **68** | 869 | 264 | 2,387 | 2,166 | 824 | 235 | [card](cards/sandisk-sa16g-16gb.md) |
| Gigastone HE 16GB | **53** | 659 | 109 | 2,090 | 1,868 | 576 | 143 | [card](cards/gigastone-sd16g-16gb.md) |
| PNY 16GB | **52** | 747 | 192 | 2,376 | 1,037 | 734 | 50 | [card](cards/pny-sd16g-16gb.md) |

**Best Read**: Samsung PRO Endurance 128GB — fastest single-sector (1,283 KB/s) and raw multi-sector reads (2,427 KB/s); Lexar Blue 128GB — fastest file-level reads (1,444 KB/s).
**Best Write**: Amazon Basics 64GB — fastest single-sector writes (846 KB/s) and file-level writes (774 KB/s); Samsung PRO Endurance 128GB — fastest raw multi-sector writes (2,319 KB/s).

★ Lexar Red label says A1; ACMD13 register reports A2 (both physical units).
‖ PNY single-sector write has enormous variance (Min=2,936, Max=14,654 µs) — Phison controller has unpredictable write commit latency.

---

### Sysclk Effect (350 vs 250 MHz at same 25 MHz SPI)

Both speeds produce identical 25 MHz SPI clock — differences are purely Spin2 inter-transfer overhead.

| Card | Raw Rd 64x | Raw Wr 64x | File Rd 256K | File Wr 32K |
|------|:----------:|:----------:|:------------:|:-----------:|
| Amazon Basics 64GB | +9% | +9% | +15% | +13% |
| Samsung PRO Endurance 128GB | +8% | +10% | +15% | +7% |
| Lexar Blue 128GB | +8% | +9% | +15% | +12% |
| Lexar V30 64GB | +9% | +10% | +16% | +9% |
| SanDisk Extreme PRO 64GB | +8% | +9% | +12% | +6% |
| SanDisk Extreme PRO 128GB | +8% | +6% | +12% | +6% |
| SanDisk Extreme 64GB | +8% | +9% | +11% | +5% |
| SanDisk MAX Endurance 32GB | +8% | +10% | +12% | +4% |
| SanDisk Switch 128GB | +8% | +12% | +11% | +5% |
| WD Purple 64GB | +8% | +8% | +16% | +5% |
| Gigastone Camera+ 64GB | +12% | +10% | +12% | +4% |
| Samsung EVO 128GB | +10% | +7% | -1% | -2% |
| SanDisk Industrial 16GB | +9% | +9% | +9% | +4% |
| Gigastone HE 16GB | +11% | +9% | +7% | +1% |
| PNY 16GB | +8% | +4% | +7% | +4% |

**Pattern**: Raw multi-sector operations gain ~8-12% from faster Spin2 processing between streamer transfers. File-level reads gain 7-16% from reduced FAT traversal overhead. File-level writes are card-dependent (1-13%) — cards with longer flash programming times are dominated by card latency rather than sysclk speed. Samsung EVO is the outlier: internal controller latency dominates, producing slightly *negative* file-level deltas at higher sysclk.

---

## Baseline Results (Bit-Banged SPI)

These measurements represent the driver performance **before** Smart Pin optimization.

### Summary Table

| Metric | Gigastone 32GB | PNY 16GB | SanDisk Extreme 64GB |
|--------|----------------|----------|----------------------|
| **Mount** | 138 ms | 139 ms | 152 ms |
| **File Open** | 326 µs | 14,136 µs | **293 µs** |
| **Write 512B** | 85 KB/s | 52 KB/s | **90 KB/s** |
| **Write 4KB** | 210 KB/s | 182 KB/s | **302 KB/s** |
| **Write 32KB** | 325 KB/s | 216 KB/s | **425 KB/s** |
| **Read 256KB** | 1,339 KB/s | 850 KB/s | **1,467 KB/s** |

**Best Overall**: SanDisk Extreme 64GB

---

### Detailed Baseline Card Results

#### Gigastone 32GB (Transcend Silicon, Class 10, U1)

**Card Identification**:
- MID: $74 (Transcend OEM — Gigastone-branded card using Transcend flash/controller)
- Product Name: "00000" (white-label)
- CID: `$74 $49 $54 $30 $30 $30 $30 $30 $1E $62 $4D $D6 $D1 $00 $E7 $E3`

**Note**: This is a different physical card than the Gigastone 32GB in CARD-CATALOG.md (different OID and serial number), but the same model with identical Transcend MID $74 silicon.

**Results**:
| Test | Value | Notes |
|------|-------|-------|
| Mount | 138.5 ms | Includes card init + MBR/VBR parsing |
| File Open | 326 µs | Create new file in root |
| Write 512B (×10) | 85 KB/s | Single sector writes |
| Write 4KB (×10) | 210 KB/s | 8-sector writes |
| Write 32KB (×10) | 325 KB/s | 64-sector writes |
| Read 256KB (×10) | 1,339 KB/s | Sequential read |

---

#### PNY 16GB (Phison Controller)

**Card Identification**:
- MID: $27 (Phison)
- Product Name: "SD16G"
- CID: `$27 $50 $48 $53 $44 $31 $36 $47 $40 $D0 $2C $93 $C2 $01 $4E $83`

**Note**: This is a different physical PNY card (PRV 4.0) than the one used in the current-driver benchmarks below and in CARD-CATALOG.md (PRV 3.0, different serial number). Both are PNY 16GB with identical Phison MID $27 controllers.

**Results**:
| Test | Value | Notes |
|------|-------|-------|
| Mount | 139.2 ms | Similar to Gigastone |
| File Open | **14,136 µs** | **43× slower than Gigastone!** |
| Write 512B (×10) | 52 KB/s | Slowest write speed |
| Write 4KB (×10) | 182 KB/s | |
| Write 32KB (×10) | 216 KB/s | |
| Read 256KB (×10) | 850 KB/s | ~36% slower than Gigastone |

**Notes**: The PNY card shows significantly slower file operations. The 43× slower file open time suggests the card's internal controller has higher latency for metadata operations. This card required a writeSector() fix for busy-wait compatibility (see CARD-CATALOG.md).

---

#### SanDisk Extreme 64GB (SN64G, MID $03)

```
SanDisk SN64G SDXC 59GB [FAT32] SD 6.x rev8.6 SN:$7E65_0771 2022/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**Card Identification**:
- MID: $03 (SanDisk / Western Digital)
- Product Name: "SN64G"
- CID: `$03 $53 $44 $53 $4E $36 $34 $47 $86 $7E $65 $07 $71 $01 $6B $8D`
- Catalog ID: `SanDisk_SN64G_8.6_7E650771_202211`

**Results**:
| Test | Value | Notes |
|------|-------|-------|
| Mount | 152.3 ms | Slightly longer (larger FAT?) |
| File Open | **293 µs** | Fastest |
| Write 512B (×10) | **90 KB/s** | Fastest |
| Write 4KB (×10) | **302 KB/s** | Fastest |
| Write 32KB (×10) | **425 KB/s** | Fastest |
| Read 256KB (×10) | **1,467 KB/s** | Fastest |

**Notes**: Best overall performance. This is a UHS-I card with U3/V30 rating. Formatted as FAT32 by P2 format utility (originally shipped as exFAT).

---

## Performance Observations

### Card Controller Variance

The dramatic difference in file open times (128 µs vs 16,945 µs) demonstrates that SD card performance varies significantly based on the internal controller, not just the rated speed class.

### Write Speed Scaling (Baseline → Current)

Write throughput increases with block size due to:
1. Fewer command/response cycles
2. Better alignment with card's internal erase blocks
3. Reduced FAT update overhead

| Block Size | Baseline Best (SanDisk 64GB) | Current Best (Amazon Basics 64GB) | Improvement |
|------------|------------------------------|----------------------------------|-------------|
| 512B | 90 KB/s | 121 KB/s | +34% |
| 4KB | 302 KB/s | 483 KB/s | +60% |
| 32KB | 425 KB/s | 774 KB/s | +82% |

### Read Performance

Sequential read performance at file level (current driver, 350 MHz, File Read 256KB):
- Lexar Blue 128GB: **1,444 KB/s** (best)
- Samsung PRO Endurance 128GB: 1,419 KB/s
- Amazon Basics 64GB: 1,386 KB/s
- Lexar V30 64GB: 1,378 KB/s
- SanDisk Extreme PRO 128GB: 1,103 KB/s
- SanDisk Extreme PRO 64GB: 1,101 KB/s
- Gigastone Camera+ 64GB: 1,091 KB/s
- SanDisk Extreme 64GB: 1,040 KB/s
- SanDisk MAX Endurance 32GB: 1,036 KB/s
- SanDisk Switch 128GB: 1,016 KB/s
- WD Purple 64GB: 990 KB/s
- SanDisk Industrial 16GB: 869 KB/s
- Samsung EVO 128GB: 835 KB/s
- PNY 16GB: 747 KB/s
- Gigastone HE 16GB: 659 KB/s

### Multi-Sector Improvement

CMD18/CMD25 multi-sector operations provide 46-72% improvement over repeated single-sector commands:
- Cards with slower internal controllers benefit more (Gigastone HE: 72%, PNY: 69%, SanDisk Industrial: 67%)
- Fast cards benefit less (Samsung PRO Endurance: 46%, Lexar V30: 51%, Lexar Blue: 51%, Gigastone Camera+: 53%)
- The improvement comes from eliminating per-sector command overhead

### PNY Phison Controller Anomalies (350 MHz data)

The PNY card (MID $27 Phison) has distinctive behavior:
- **File open: 177 µs avg** on empty directory (clean format) — previously 16.9 ms with many files, showing directory scan dominates open time
- **Raw single-sector write: 50 KB/s** with enormous variance (Min=2,936, Max=14,654 µs) — slowest writer in collection
- **Multi-sector reads competitive**: 2,376 KB/s at 64 sectors — matching or exceeding many premium cards
- **Extremely consistent reads**: Min≈Max for single-sector (697 µs) at 350 MHz — zero variance
- **Multi-sector writes slow**: 1,037 KB/s at 64 sectors — roughly half of other cards

---

## Theoretical Limits

At 350 MHz sysclk with Smart Pin SPI:
- **SPI clock**: 25.0 MHz (exact — 350/25 = 14, integer divider)
- **Theoretical byte rate**: ~3,052 KB/s (25 MHz / 8 bits)
- **Best raw achieved**: 2,427 KB/s read, 2,319 KB/s write (80% / 76% efficiency)
- **Best file-level achieved**: 1,444 KB/s read, 774 KB/s write

The raw-to-theoretical gap is due to:
- Command/response framing per transfer
- CRC computation and checking
- Token wait time (especially on writes)

The file-to-raw gap is due to:
- FAT chain traversal during reads
- FAT + directory updates during writes
- Cluster boundary management
- Handle API overhead

---

## Efficiency Summary

| Level | Read (KB/s) | Write (KB/s) | Read % | Write % |
|-------|-------------|--------------|--------|---------|
| Theoretical (25 MHz SPI) | 3,052 | 3,052 | 100% | 100% |
| Raw multi-sector (best) | 2,427 | 2,319 | 80% | 76% |
| File-level (best) | 1,444 | 774 | 47% | 25% |

The raw SPI layer is reasonably efficient (~78% average). File-level write throughput is best with Amazon Basics 64GB (774 KB/s, 25% of theoretical), which edges out Samsung PRO Endurance (758 KB/s). FAT metadata updates still consume most of available bandwidth.

---

## Test History

| Date | Driver Version | Change | Notes |
|------|----------------|--------|-------|
| 2026-01-21 | Baseline (bit-banged) | Initial benchmark | 3 cards tested |
| 2026-02-07 | Smart pin + multi-sector | Benchmark v2.0 | SanDisk Industrial 16GB @ 320+270 MHz |
| 2026-02-08 | Smart pin + multi-sector | Benchmark v2.0 | Lexar V30 U3 64GB @ 320+270+350 MHz |
| 2026-02-08 | Smart pin + multi-sector | Benchmark v2.0 | Gigastone Camera Plus 64GB @ 320+270 MHz |
| 2026-02-08 | Smart pin + multi-sector | Benchmark v2.0 | Samsung EVO Select 128GB @ 320+270 MHz (raw sector errors) |
| 2026-02-08 | Smart pin + multi-sector | Benchmark v2.0 | Gigastone High Endurance 16GB @ 320+270 MHz |
| 2026-02-09 | Smart pin + multi-sector | Benchmark v2.0 | PNY 16GB @ 320+270 MHz |
| 2026-02-16 | TX streamer fix (797f913) | Standard protocol | SanDisk Industrial 16GB @ 350+250 MHz |
| 2026-02-16 | TX streamer fix (797f913) | Standard protocol | Lexar Blue 128GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Standard protocol | Samsung EVO Select 128GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Standard protocol | Lexar V30 U3 64GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Standard protocol | SanDisk Nintendo Switch 128GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Standard protocol | SanDisk Extreme 64GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Standard protocol | Samsung PRO Endurance 128GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Standard protocol | Amazon Basics 64GB @ 350+250 MHz |
| 2026-02-17 | TX streamer fix (797f913) | Re-benchmark | SanDisk Extreme 64GB @ 350+250 MHz (re-run) |
| 2026-02-17 | TX streamer fix (797f913) | Re-benchmark | PNY 16GB @ 350+250 MHz (re-run) |
| 2026-02-18 | TX streamer fix (797f913) | Standard protocol | SanDisk MAX Endurance 32GB @ 350+250 MHz |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | WD Purple 64GB @ 350+250 MHz |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | SanDisk Industrial 16GB @ 350+250 MHz (re-benchmark, clean data) |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | Samsung EVO Select 128GB @ 350+250 MHz (re-benchmark, clean write data) |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | Gigastone Camera Plus 64GB @ 350+250 MHz (re-benchmark from 320/270) |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | Gigastone High Endurance 16GB @ 350+250 MHz (re-benchmark from 320/270) |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | SanDisk Extreme PRO 64GB @ 350+250 MHz (new card) |
| 2026-02-25 | Current driver (d62e30d) | Standard protocol | SanDisk Extreme PRO 128GB @ 350+250 MHz (new card) |

---

*Document maintained as part of P2 microSD FAT32 Filesystem project*
*Last updated: 2026-02-25*
