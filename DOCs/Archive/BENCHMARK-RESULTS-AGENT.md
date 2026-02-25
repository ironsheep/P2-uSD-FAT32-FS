# SD Card Driver Benchmark Results

**Document Purpose**: Record actual performance measurements from benchmark testing
**Test Program**: `src/UTILS/SD_performance_benchmark.spin2` (v2.0)
**System Clock**: 320 MHz (default), 270 MHz (comparison runs)

---

## Test Configuration

- **Hardware**: P2 Edge Module with microSD slot
- **Pins**: CS=P60, MOSI=P59, MISO=P58, SCK=P61
- **Iterations**: 10 per test (averaged)
- **Test Date**: 2026-01-21

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

## Detailed Card Results

### Gigastone 32GB (Class 10, U1)

**Card Identification**:
- MID: $74
- Product Name: "00000"
- CID: `$74 $49 $54 $30 $30 $30 $30 $30 $1E $62 $4D $D6 $D1 $00 $E7 $E3`

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

### PNY 16GB (Phison Controller)

**Card Identification**:
- MID: $27
- Product Name: "SD16G"
- CID: `$27 $50 $48 $53 $44 $31 $36 $47 $40 $D0 $2C $93 $C2 $01 $4E $83`

**Results**:
| Test | Value | Notes |
|------|-------|-------|
| Mount | 139.2 ms | Similar to Gigastone |
| File Open | **14,136 µs** | **43× slower than Gigastone!** |
| Write 512B (×10) | 52 KB/s | Slowest write speed |
| Write 4KB (×10) | 182 KB/s | |
| Write 32KB (×10) | 216 KB/s | |
| Read 256KB (×10) | 850 KB/s | ~36% slower than Gigastone |

**Notes**: The PNY card shows significantly slower file operations. The 43× slower file open time suggests the card's internal controller has higher latency for metadata operations. This card required a writeSector() fix for busy-wait compatibility (see ../cards/CARD-CATALOG.md).

---

### SanDisk Extreme 64GB

**Card Identification**:
- MID: $03 (SanDisk)
- Product Name: "SN64G"
- CID: `$03 $53 $44 $53 $4E $36 $34 $47 $86 $7E $65 $07 $71 $01 $6B $8D`

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

---

## Current Driver Results (Smart Pin SPI + Multi-Sector)

Test program: `src/UTILS/SD_performance_benchmark.spin2` v2.0
Measurements across three levels: raw single-sector, raw multi-sector (CMD18/CMD25), and file-level (handle API).

### SanDisk Industrial 16GB (SA16G, MID $03)

**Test Date**: 2026-02-07
**CID**: `$03 $53 $44 $53 $41 $31 $36 $47 $80 $93 $E9 $C0 $A1 $01 $9B $59`

#### 320 MHz Run

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 234.9 ms
**Log**: `tools/logs/SD_performance_benchmark_260207-231730.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 529 | 733 | 1,157 | **698** |
| Write 1x512B | 1,323 | 1,433 | 2,142 | **357** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,130 | 2,228 | 2,753 | **1,838** |
| Read 32 sectors (16 KB) | 7,613 | 7,807 | 8,237 | **2,098** |
| Read 64 sectors (32 KB) | 14,865 | 14,964 | 15,478 | **2,189** |
| Write 8 sectors (4 KB) | 2,702 | 3,023 | 3,631 | **1,354** |
| Write 32 sectors (16 KB) | 8,585 | 9,469 | 14,459 | **1,730** |
| Write 64 sectors (32 KB) | 16,112 | 16,414 | 17,277 | **1,996** |
| **File-Level** | | | | |
| File Write 512B | 8,213 | 8,473 | 9,569 | **60** |
| File Write 4 KB | 17,943 | 18,778 | 25,497 | **218** |
| File Write 32 KB | 100,761 | 101,954 | 102,412 | **321** |
| File Read 4 KB | 4,907 | 5,027 | 5,519 | **814** |
| File Read 32 KB | 38,157 | 38,279 | 38,785 | **856** |
| File Read 128 KB | 152,885 | 153,361 | 155,033 | **854** |
| File Read 256 KB | 312,611 | 313,629 | 315,305 | **835** |
| **Overhead** | | | | |
| File Open | 95 | 144 | 588 | — |
| File Close | 22 | 22 | 22 | — |
| Mount | — | 234,900 | — | — |

Multi-sector improvement: 64x single reads = 43,549 us vs 1x CMD18 = 14,870 us (**65% faster**)

#### 270 MHz Run

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 235.7 ms
**Log**: `tools/logs/SD_performance_benchmark_260207-234226.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 563 | 667 | 1,176 | **767** |
| Write 1x512B | 1,347 | 1,459 | 2,168 | **350** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,245 | 2,436 | 2,858 | **1,681** |
| Read 32 sectors (16 KB) | 7,984 | 8,085 | 8,598 | **2,026** |
| Read 64 sectors (32 KB) | 15,616 | 15,716 | 16,247 | **2,085** |
| Write 8 sectors (4 KB) | 2,929 | 3,228 | 3,966 | **1,268** |
| Write 32 sectors (16 KB) | 9,002 | 9,841 | 14,692 | **1,664** |
| Write 64 sectors (32 KB) | 16,994 | 17,209 | 17,937 | **1,904** |
| **File-Level** | | | | |
| File Write 512B | 7,688 | 9,356 | 16,512 | **54** |
| File Write 4 KB | 18,446 | 20,072 | 25,931 | **204** |
| File Write 32 KB | 102,787 | 106,053 | 114,192 | **308** |
| File Read 4 KB | 5,180 | 5,262 | 5,901 | **778** |
| File Read 32 KB | 40,224 | 40,353 | 40,868 | **812** |
| File Read 128 KB | 160,846 | 161,244 | 162,150 | **812** |
| File Read 256 KB | 328,164 | 329,147 | 330,276 | **796** |
| **Overhead** | | | | |
| File Open | 113 | 163 | 614 | — |
| File Close | 26 | 26 | 27 | — |
| Mount | — | 235,700 | — | — |

Multi-sector improvement: 64x single reads = 45,737 us vs 1x CMD18 = 15,622 us (**65% faster**)

#### Sysclk Effect (320 vs 270 MHz)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 698 | 767 | +9.9% |
| Raw Read 64x (32 KB) | 2,189 | 2,085 | -4.7% |
| Raw Write 64x (32 KB) | 1,996 | 1,904 | -4.6% |
| File Read 256 KB | 835 | 796 | -4.7% |
| File Write 32 KB | 321 | 308 | -4.0% |

SPI frequency changes slightly (22,857 vs 22,500 kHz = -1.6%) but the Spin2 overhead between SPI transfers runs slower at 270 MHz, accounting for the ~4-5% throughput reduction on multi-sector and file-level operations. The single-sector raw read anomaly (+9.9%) is within card latency variance.

---

### Lexar V30 U3 64GB (MSSD0, MID $AD)

**Test Date**: 2026-02-08
**CID**: `$AD $4C $53 $4D $53 $53 $44 $30 $61 $33 $54 $90 $24 $71 $8B $55`
**Note**: Card shipped as exFAT, reformatted to FAT32 with P2 format utility (label "P2-BENCH")

#### 320 MHz Run

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 212.3 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-025046.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 438 | 448 | 538 | **1,142** |
| Write 1x512B | 781 | 790 | 872 | **648** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,063 | 2,073 | 2,163 | **1,975** |
| Read 32 sectors (16 KB) | 7,637 | 7,647 | 7,737 | **2,142** |
| Read 64 sectors (32 KB) | 15,068 | 15,078 | 15,168 | **2,173** |
| Write 8 sectors (4 KB) | 2,398 | 2,400 | 2,402 | **1,706** |
| Write 32 sectors (16 KB) | 8,080 | 8,080 | 8,080 | **2,027** |
| Write 64 sectors (32 KB) | 15,912 | 15,912 | 15,916 | **2,059** |
| **File-Level** | | | | |
| File Write 512B | 4,950 | 5,723 | 6,101 | **89** |
| File Write 4 KB | 11,149 | 12,463 | 14,551 | **328** |
| File Write 32 KB | 59,684 | 65,391 | 71,017 | **501** |
| File Read 4 KB | 3,353 | 3,429 | 4,113 | **1,194** |
| File Read 32 KB | 25,810 | 25,888 | 26,590 | **1,265** |
| File Read 128 KB | 102,825 | 102,948 | 104,053 | **1,273** |
| File Read 256 KB | 205,513 | 205,648 | 206,863 | **1,274** |
| **Overhead** | | | | |
| File Open | 101 | 198 | 1,080 | — |
| File Close | 22 | 22 | 22 | — |
| Mount | — | 212,300 | — | — |

Multi-sector improvement: 64x single reads = 30,644 us vs 1x CMD18 = 15,068 us (**50% faster**)

#### 270 MHz Run

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 213.4 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-025603.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 473 | 483 | 573 | **1,060** |
| Write 1x512B | 811 | 820 | 901 | **624** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,185 | 2,195 | 2,285 | **1,866** |
| Read 32 sectors (16 KB) | 8,053 | 8,063 | 8,153 | **2,031** |
| Read 64 sectors (32 KB) | 15,889 | 15,898 | 15,988 | **2,061** |
| Write 8 sectors (4 KB) | 2,533 | 2,533 | 2,533 | **1,617** |
| Write 32 sectors (16 KB) | 8,543 | 8,543 | 8,544 | **1,917** |
| Write 64 sectors (32 KB) | 16,812 | 16,812 | 16,812 | **1,949** |
| **File-Level** | | | | |
| File Write 512B | 5,219 | 6,004 | 6,400 | **85** |
| File Write 4 KB | 13,139 | 13,899 | 14,618 | **294** |
| File Write 32 KB | 58,388 | 67,086 | 87,308 | **488** |
| File Read 4 KB | 3,611 | 3,677 | 4,271 | **1,113** |
| File Read 32 KB | 27,687 | 27,754 | 28,365 | **1,180** |
| File Read 128 KB | 110,258 | 110,373 | 111,413 | **1,187** |
| File Read 256 KB | 220,354 | 220,481 | 221,633 | **1,188** |
| **Overhead** | | | | |
| File Open | 120 | 207 | 999 | — |
| File Close | 26 | 26 | 27 | — |
| Mount | — | 213,400 | — | — |

Multi-sector improvement: 64x single reads = 32,857 us vs 1x CMD18 = 15,889 us (**51% faster**)

#### Sysclk Effect (320 vs 270 MHz)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 1,142 | 1,060 | -7.2% |
| Raw Read 64x (32 KB) | 2,173 | 2,061 | -5.2% |
| Raw Write 64x (32 KB) | 2,059 | 1,949 | -5.3% |
| File Read 256 KB | 1,274 | 1,188 | -6.7% |
| File Write 32 KB | 501 | 488 | -2.6% |

---

### Gigastone Camera Plus 64GB (ASTC, MID $12)

**Test Date**: 2026-02-08
**CID**: `$12 $34 $56 $41 $53 $54 $43 $00 $20 $00 $00 $0F $14 $01 $76 $4D`
**Note**: Card already FAT32 formatted (OEM "P2FMTER"), volume label "P2-XFER"

#### 320 MHz Run

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 202.0 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-114914.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 503 | 543 | 907 | **942** |
| Write 1x512B | 1,209 | 1,274 | 1,527 | **401** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,303 | 2,352 | 2,797 | **1,741** |
| Read 32 sectors (16 KB) | 8,475 | 8,524 | 8,974 | **1,922** |
| Read 64 sectors (32 KB) | 16,749 | 16,803 | 17,268 | **1,950** |
| Write 8 sectors (4 KB) | 2,839 | 3,270 | 5,746 | **1,252** |
| Write 32 sectors (16 KB) | 8,472 | 8,509 | 8,544 | **1,925** |
| Write 64 sectors (32 KB) | 16,372 | 16,638 | 18,387 | **1,969** |
| **File-Level** | | | | |
| File Write 512B | 8,631 | 9,304 | 11,544 | **55** |
| File Write 4 KB | 16,616 | 18,913 | 19,791 | **216** |
| File Write 32 KB | 87,504 | 89,198 | 91,386 | **367** |
| File Read 4 KB | 4,184 | 4,281 | 5,157 | **956** |
| File Read 32 KB | 32,320 | 32,411 | 33,228 | **1,011** |
| File Read 128 KB | 129,005 | 129,186 | 130,799 | **1,014** |
| File Read 256 KB | 254,456 | 254,628 | 256,143 | **1,029** |
| **Overhead** | | | | |
| File Open | 101 | 199 | 1,085 | — |
| File Close | 22 | 22 | 22 | — |
| Mount | — | 202,000 | — | — |

Multi-sector improvement: 64x single reads = 34,382 us vs 1x CMD18 = 16,754 us (**51% faster**)

#### 270 MHz Run

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 204.0 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-115429.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 584 | 639 | 1,128 | **801** |
| Write 1x512B | 1,136 | 1,493 | 3,962 | **342** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,500 | 2,547 | 2,973 | **1,608** |
| Read 32 sectors (16 KB) | 9,069 | 9,116 | 9,548 | **1,797** |
| Read 64 sectors (32 KB) | 17,815 | 17,864 | 18,312 | **1,834** |
| Write 8 sectors (4 KB) | 2,959 | 3,362 | 5,833 | **1,218** |
| Write 32 sectors (16 KB) | 8,922 | 8,960 | 9,024 | **1,828** |
| Write 64 sectors (32 KB) | 17,293 | 17,547 | 19,246 | **1,867** |
| **File-Level** | | | | |
| File Write 512B | 8,804 | 13,776 | 52,016 | **37** |
| File Write 4 KB | 16,886 | 23,028 | 60,152 | **177** |
| File Write 32 KB | 89,964 | 119,201 | 134,450 | **274** |
| File Read 4 KB | 4,340 | 4,441 | 5,356 | **922** |
| File Read 32 KB | 33,518 | 33,613 | 34,457 | **974** |
| File Read 128 KB | 133,583 | 133,775 | 135,435 | **979** |
| File Read 256 KB | 267,002 | 267,177 | 268,723 | **981** |
| **Overhead** | | | | |
| File Open | 120 | 219 | 1,118 | — |
| File Close | 26 | 26 | 27 | — |
| Mount | — | 204,000 | — | — |

Multi-sector improvement: 64x single reads = 35,950 us vs 1x CMD18 = 17,815 us (**50% faster**)

#### Sysclk Effect (320 vs 270 MHz)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 942 | 801 | -15.0% |
| Raw Read 64x (32 KB) | 1,950 | 1,834 | -5.9% |
| Raw Write 64x (32 KB) | 1,969 | 1,867 | -5.2% |
| File Read 256 KB | 1,029 | 981 | -4.7% |
| File Write 32 KB | 367 | 274 | -25.3% |

The raw multi-sector operations show the typical ~5% sysclk effect. However, file-level writes at 270 MHz show dramatic variance (Max=52,016 us for 512B, Max=134,450 us for 32 KB), with the card controller introducing unpredictable write stalls. This inflates the average and reduces reported throughput well beyond the expected sysclk effect. Raw multi-sector writes (which bypass FAT) are not affected, confirming the stalls occur during FAT metadata writes.

---

### Samsung EVO Select 128GB (GD4QT, MID $1B)

**Test Date**: 2026-02-08
**CID**: `$1B $53 $4D $47 $44 $34 $51 $54 $30 $C0 $30 $55 $65 $01 $25 $E9`
**Note**: Largest card tested (119 GB, 64 sectors/cluster = 32 KB clusters). FAT32 formatted (OEM "P2FMTER"), volume "P2-XFER".

**Raw Sector API Issue**: `readSectorsRaw()` and `writeSectorsRaw()` return 0 on this card for all timed raw sector tests. File-level operations (which use the handle API internally) work correctly. This appears to be a card-specific compatibility issue with the raw sector API that needs investigation. Raw sector results are omitted; file-level results below are valid.

#### 320 MHz Run

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 202.3 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-225455.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | — | — | — | **ERROR** |
| Write 1x512B | — | — | — | **ERROR** |
| **Raw Multi-Sector** | | | | |
| Read 8/32/64 sectors | — | — | — | **ERROR** |
| Write 8/32/64 sectors | — | — | — | **ERROR** |
| **File-Level** | | | | |
| File Write 512B | 7,821 | 8,027 | 8,537 | **63** |
| File Write 4 KB | 16,686 | 17,253 | 18,142 | **237** |
| File Write 32 KB | 84,730 | 102,330 | 121,699 | **320** |
| File Read 4 KB | 6,209 | 6,286 | 6,933 | **651** |
| File Read 32 KB | 35,227 | 35,296 | 35,769 | **928** |
| File Read 128 KB | 158,710 | 158,857 | 159,994 | **825** |
| File Read 256 KB | 340,113 | 340,286 | 341,577 | **770** |
| **Overhead** | | | | |
| File Open | 101 | 153 | 628 | — |
| File Close | 22 | 22 | 22 | — |
| Mount | — | 202,300 | — | — |

#### 270 MHz Run

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 214.4 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-225554.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | — | — | — | **ERROR** |
| Write 1x512B | — | — | — | **ERROR** |
| **Raw Multi-Sector** | | | | |
| Read 8/32/64 sectors | — | — | — | **ERROR** |
| Write 8/32/64 sectors | — | — | — | **ERROR** |
| **File-Level** | | | | |
| File Write 512B | 8,083 | 8,278 | 8,773 | **61** |
| File Write 4 KB | 17,630 | 18,128 | 18,611 | **225** |
| File Write 32 KB | 87,594 | 100,385 | 122,577 | **326** |
| File Read 4 KB | 6,563 | 6,638 | 7,318 | **617** |
| File Read 32 KB | 37,533 | 37,594 | 38,110 | **871** |
| File Read 128 KB | 154,502 | 154,634 | 155,691 | **847** |
| File Read 256 KB | 342,910 | 343,077 | 344,231 | **764** |
| **Overhead** | | | | |
| File Open | 120 | 189 | 816 | — |
| File Close | 26 | 26 | 27 | — |
| Mount | — | 214,400 | — | — |

#### Sysclk Effect (320 vs 270 MHz)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| File Read 4 KB | 651 | 617 | -5.2% |
| File Read 256 KB | 770 | 764 | -0.8% |
| File Write 32 KB | 320 | 326 | +1.9% |

File reads at small sizes show the typical ~5% sysclk effect. At large sizes, the card controller's internal read latency dominates, making the sysclk difference negligible. File write results are within noise. This Samsung card has notably slower file reads (770 KB/s at 256 KB) compared to other cards (1,029-1,274 KB/s), likely due to higher internal controller latency.

---

### Gigastone High Endurance 16GB (SD16G, MID $00)

**Test Date**: 2026-02-08
**CID**: `$00 $34 $32 $53 $44 $31 $36 $47 $20 $00 $00 $03 $FB $01 $92 $D5`
**Note**: Budget OEM controller (MID $00). FAT32 formatted (OEM "P2FMTER"), volume "P2-XFER", 16 sectors/cluster.

#### 320 MHz Run

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 203.0 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-235803.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 887 | 906 | 1,072 | **565** |
| Write 1x512B | 3,456 | 3,601 | 4,171 | **142** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,687 | 2,708 | 2,872 | **1,512** |
| Read 32 sectors (16 KB) | 8,859 | 8,878 | 9,044 | **1,845** |
| Read 64 sectors (32 KB) | 17,088 | 17,110 | 17,273 | **1,915** |
| Write 8 sectors (4 KB) | 5,173 | 5,390 | 6,028 | **759** |
| Write 32 sectors (16 KB) | 11,211 | 11,294 | 11,930 | **1,450** |
| Write 64 sectors (32 KB) | 18,924 | 19,621 | 25,085 | **1,670** |
| **File-Level** | | | | |
| File Write 512B | 20,607 | 22,072 | 28,404 | **23** |
| File Write 4 KB | 46,168 | 46,545 | 47,058 | **88** |
| File Write 32 KB | 296,680 | 310,332 | 380,277 | **105** |
| File Read 4 KB | 6,129 | 6,221 | 7,047 | **658** |
| File Read 32 KB | 54,665 | 54,835 | 56,337 | **597** |
| File Read 128 KB | 208,092 | 208,292 | 209,816 | **629** |
| File Read 256 KB | 414,901 | 415,200 | 417,118 | **631** |
| **Overhead** | | | | |
| File Open | 95 | 186 | 1,013 | — |
| File Close | 22 | 22 | 22 | — |
| Mount | — | 203,000 | — | — |

Multi-sector improvement: 64x single reads = 57,030 us vs 1x CMD18 = 17,088 us (**70% faster**)

#### 270 MHz Run

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 204.3 ms
**Log**: `tools/logs/SD_performance_benchmark_260208-235858.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 923 | 941 | 1,104 | **544** |
| Write 1x512B | 3,488 | 3,634 | 4,205 | **140** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,839 | 2,857 | 3,020 | **1,433** |
| Read 32 sectors (16 KB) | 9,407 | 9,425 | 9,589 | **1,738** |
| Read 64 sectors (32 KB) | 18,165 | 18,183 | 18,347 | **1,802** |
| Write 8 sectors (4 KB) | 5,311 | 5,459 | 6,049 | **750** |
| Write 32 sectors (16 KB) | 11,561 | 11,705 | 12,277 | **1,399** |
| Write 64 sectors (32 KB) | 19,731 | 19,917 | 20,452 | **1,645** |
| **File-Level** | | | | |
| File Write 512B | 20,644 | 21,574 | 22,150 | **23** |
| File Write 4 KB | 46,641 | 56,020 | 128,008 | **73** |
| File Write 32 KB | 299,025 | 312,727 | 384,028 | **104** |
| File Read 4 KB | 6,374 | 6,468 | 7,318 | **633** |
| File Read 32 KB | 55,549 | 55,718 | 57,240 | **588** |
| File Read 128 KB | 213,018 | 213,187 | 214,709 | **614** |
| File Read 256 KB | 425,880 | 426,049 | 427,570 | **615** |
| **Overhead** | | | | |
| File Open | 113 | 206 | 1,051 | — |
| File Close | 26 | 26 | 27 | — |
| Mount | — | 204,300 | — | — |

Multi-sector improvement: 64x single reads = 59,351 us vs 1x CMD18 = 18,165 us (**69% faster**)

#### Sysclk Effect (320 vs 270 MHz)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 565 | 544 | -3.7% |
| Raw Read 64x (32 KB) | 1,915 | 1,802 | -5.9% |
| Raw Write 64x (32 KB) | 1,670 | 1,645 | -1.5% |
| File Read 256 KB | 631 | 615 | -2.5% |
| File Write 32 KB | 105 | 104 | -1.0% |

Slowest card tested. File write 32 KB at 105 KB/s is 3.5x slower than the Gigastone Camera Plus (367 KB/s) and 4.8x slower than the Lexar (501 KB/s). Raw single-sector write latency (3,601 us) is 2.8x higher than the Gigastone Camera Plus (1,274 us), indicating a very slow internal flash controller. The 70% multi-sector improvement is the highest observed, because single-sector command overhead is proportionally larger on this slow card. Sysclk effect is muted (1-6%) since the card controller latency dominates.

---

### PNY 16GB (SD16G, MID $27 Phison)

**Test Date**: 2026-02-09
**CID**: `$27 $50 $48 $53 $44 $31 $36 $47 $30 $01 $CD $5C $F5 $01 $28 $1F`
**Note**: Phison controller. Known for extremely slow file open times (~17 ms). FAT32 formatted (OEM "P2FMTER"), volume "P2-XFER", 16 sectors/cluster.

#### 320 MHz Run

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 202.7 ms
**Log**: `tools/logs/SD_performance_benchmark_260209-000722.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 812 | 812 | 812 | **630** |
| Write 1x512B | 2,965 | 8,974 | 11,110 | **57** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 3,121 | 3,121 | 3,121 | **1,312** |
| Read 32 sectors (16 KB) | 7,762 | 7,763 | 7,772 | **2,110** |
| Read 64 sectors (32 KB) | 15,038 | 16,098 | 16,220 | **2,035** |
| Write 8 sectors (4 KB) | 11,652 | 11,779 | 12,025 | **347** |
| Write 32 sectors (16 KB) | 24,956 | 25,157 | 26,276 | **651** |
| Write 64 sectors (32 KB) | 32,815 | 32,916 | 33,279 | **995** |
| **File-Level** | | | | |
| File Write 512B | 29,598 | 35,981 | 93,163 | **14** |
| File Write 4 KB | 43,018 | 43,219 | 44,657 | **94** |
| File Write 32 KB | 178,247 | 188,682 | 201,906 | **173** |
| File Read 4 KB | 22,885 | 22,993 | 23,568 | **178** |
| File Read 32 KB | 64,651 | 64,775 | 65,349 | **505** |
| File Read 128 KB | 207,824 | 207,937 | 208,623 | **630** |
| File Read 256 KB | 395,348 | 395,454 | 396,071 | **662** |
| **Overhead** | | | | |
| File Open | 16,838 | 16,945 | 17,581 | — |
| File Close | 22 | 22 | 22 | — |
| Mount | — | 202,700 | — | — |

Multi-sector improvement: 64x single reads = 46,658 us vs 1x CMD18 = 15,033 us (**67% faster**)

#### 270 MHz Run

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 203.9 ms
**Log**: `tools/logs/SD_performance_benchmark_260209-000809.log`

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 760 | 760 | 760 | **673** |
| Write 1x512B | 9,759 | 9,795 | 9,833 | **52** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 3,282 | 3,282 | 3,283 | **1,248** |
| Read 32 sectors (16 KB) | 8,152 | 8,153 | 8,158 | **2,009** |
| Read 64 sectors (32 KB) | 15,796 | 16,930 | 17,057 | **1,935** |
| Write 8 sectors (4 KB) | 11,698 | 11,837 | 12,075 | **346** |
| Write 32 sectors (16 KB) | 25,237 | 25,432 | 26,543 | **644** |
| Write 64 sectors (32 KB) | 33,501 | 33,559 | 33,618 | **976** |
| **File-Level** | | | | |
| File Write 512B | 29,325 | 34,644 | 51,184 | **14** |
| File Write 4 KB | 44,287 | 45,344 | 52,753 | **90** |
| File Write 32 KB | 181,724 | 191,479 | 213,768 | **171** |
| File Read 4 KB | 23,923 | 24,062 | 24,689 | **170** |
| File Read 32 KB | 67,401 | 67,539 | 68,227 | **485** |
| File Read 128 KB | 216,214 | 216,324 | 216,974 | **605** |
| File Read 256 KB | 411,067 | 411,174 | 411,826 | **637** |
| **Overhead** | | | | |
| File Open | 17,624 | 17,778 | 18,456 | — |
| File Close | 26 | 26 | 27 | — |
| Mount | — | 203,900 | — | — |

Multi-sector improvement: 64x single reads = 49,650 us vs 1x CMD18 = 15,801 us (**68% faster**)

#### Sysclk Effect (320 vs 270 MHz)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 630 | 673 | +6.8% |
| Raw Read 64x (32 KB) | 2,035 | 1,935 | -4.9% |
| Raw Write 64x (32 KB) | 995 | 976 | -1.9% |
| File Read 256 KB | 662 | 637 | -3.8% |
| File Write 32 KB | 173 | 171 | -1.2% |

The PNY Phison controller has the most distinctive behavior of all cards tested:
- **File open: 16.9 ms** (85x slower than other cards' ~200 us). This dominates small file operations -- a 4 KB file read takes 23 ms, of which 17 ms is just opening the file.
- **Raw single-sector write: 57 KB/s** with enormous variance (Min=2,965, Max=11,110 us) -- the Phison controller has unpredictable write commit latency.
- **Multi-sector reads surprisingly fast**: 2,110 KB/s at 32 sectors -- competitive with the best cards. The Phison sustains excellent sequential read throughput once past the open overhead.
- **Multi-sector writes very slow**: 995 KB/s at 64 sectors -- roughly half of other cards, indicating the write bottleneck is in the flash controller, not the SPI interface.
- **Extremely consistent reads**: Min=Max for single-sector (812 us) and 8-sector reads (3,121 us) at 320 MHz -- zero variance, suggesting the Phison controller has deterministic read paths.

---

## Performance Observations

### Card Controller Variance

The dramatic difference in file open times (293 µs vs 14,136 µs) demonstrates that SD card performance varies significantly based on the internal controller, not just the rated speed class.

### Write Speed Scaling

Write throughput increases with block size due to:
1. Fewer command/response cycles
2. Better alignment with card's internal erase blocks
3. Reduced FAT update overhead

| Block Size | Gigastone | PNY | SanDisk |
|------------|-----------|-----|---------|
| 512B | 85 KB/s | 52 KB/s | 90 KB/s |
| 4KB | 210 KB/s (2.5×) | 182 KB/s (3.5×) | 302 KB/s (3.4×) |
| 32KB | 325 KB/s (3.8×) | 216 KB/s (4.2×) | 425 KB/s (4.7×) |

### Read Performance

Sequential read performance is consistent and significantly faster than writes:
- Gigastone: 1,339 KB/s (4× faster than best write)
- PNY: 850 KB/s (4× faster than best write)
- SanDisk: 1,467 KB/s (3.5× faster than best write)

---

## Theoretical Limits

At 320 MHz sysclk with current bit-banged SPI:
- **SPI clock**: ~20 MHz (bit_delay = 8)
- **Theoretical max**: ~2.5 MB/s
- **Achieved**: ~1.5 MB/s (60% efficiency)

The gap is due to:
- Command overhead per sector
- FAT table reads during write operations
- Card busy time after writes

---

## Optimization Targets

Based on these baseline measurements, the Smart Pin SPI implementation targets:

| Metric | Current Best | Target | Expected Gain |
|--------|--------------|--------|---------------|
| Read 256KB | 1,467 KB/s | 4,000+ KB/s | 2.7× |
| Write 32KB | 425 KB/s | 1,200+ KB/s | 2.8× |
| Mount | 152 ms | 100 ms | 1.5× |

---

## Test History

| Date | Driver Version | Change | Notes |
|------|----------------|--------|-------|
| 2026-01-21 | Baseline (bit-banged) | Initial benchmark | 3 cards tested |
| 2026-02-07 | Current (smart pin + multi-sector) | Benchmark v2.0 | SanDisk Industrial 16GB @ 320+270 MHz |
| 2026-02-08 | Current (smart pin + multi-sector) | Benchmark v2.0 | Lexar V30 U3 64GB @ 320+270 MHz |
| 2026-02-08 | Current (smart pin + multi-sector) | Benchmark v2.0 | Gigastone Camera Plus 64GB @ 320+270 MHz |
| 2026-02-08 | Current (smart pin + multi-sector) | Benchmark v2.0 | Samsung EVO Select 128GB @ 320+270 MHz (raw sector API errors) |
| 2026-02-08 | Current (smart pin + multi-sector) | Benchmark v2.0 | Gigastone High Endurance 16GB @ 320+270 MHz |
| 2026-02-09 | Current (smart pin + multi-sector) | Benchmark v2.0 | PNY 16GB @ 320+270 MHz |

---

*Document maintained as part of P2 microSD FAT32 Filesystem project*
