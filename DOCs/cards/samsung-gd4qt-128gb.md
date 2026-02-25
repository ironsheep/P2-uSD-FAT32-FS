# Card: Samsung EVO Select 128GB SDXC

**Label:** Samsung EVO Select microSD XC I U3
**Unique ID:** `Samsung_GD4QT_3.0_C0305565_201805`
**Test Date:** 2026-02-02 (characterization)

### Card Designator

```
Samsung GD4QT SDXC 119GB [FAT32] SD 3.x rev3.0 SN:4AC85F42 2018/05
Class 10, U3, SPI 25 MHz  [P2FMTER]
```

*Note: Two physical units tested — SN:C0305565 (original catalog, 320/270 MHz benchmarks) and SN:4AC85F42 (standard protocol 350/250 MHz benchmarks, characterization). Same model.*

### Raw Registers

```
CID: $1B $53 $4D $47 $44 $34 $51 $54 $30 $C0 $30 $55 $65 $01 $25 $E9
CSD: $40 $0E $00 $32 $5B $59 $00 $03 $B9 $FF $7F $80 $0A $40 $40 $AB
OCR: $C0FF_8000
SCR: $02 $C5 $80 $03 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $1B | Samsung | **[USED]** |
| OID | [119:104] | $53 $4D | "SM" (Samsung) | [INFO] |
| PNM | [103:64] | $47 $44 $34 $51 $54 | "GD4QT" | [INFO] |
| PRV | [63:56] | $30 | 3.0 | [INFO] |
| PSN | [55:24] | $C030_5565 | 3,224,646,005 | [INFO] |
| MDT | [19:8] | $125 | 2018-05 (May 2018) | [INFO] |
| CRC7 | [7:1] | $74 | $74 | [INFO] |

### CSD Register (Card Specific Data) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| CSD_STRUCTURE | [127:126] | 1 | CSD Version 2.0 (SDHC/SDXC) | **[USED]** |
| TAAC | [119:112] | $0E | Read access time-1 | **[USED]** |
| NSAC | [111:104] | $00 | 0 CLK cycles | **[USED]** |
| TRAN_SPEED | [103:96] | $32 | 25 MHz max | **[USED]** |
| CCC | [95:84] | $5B5 | Classes 0,2,4,5,7,8,10 | [INFO] |
| READ_BL_LEN | [83:80] | 9 | 512 bytes | [INFO] |
| READ_BL_PARTIAL | [79] | 0 | Not allowed | [INFO] |
| WRITE_BLK_MISALIGN | [78] | 0 | Not allowed | [INFO] |
| READ_BLK_MISALIGN | [77] | 0 | Not allowed | [INFO] |
| DSR_IMP | [76] | 0 | DSR not implemented | [INFO] |
| C_SIZE | [69:48] | $3B9FF | 244,223 (122,112 MB) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 127 | Erase sector = 64 KB | [INFO] |
| WP_GRP_SIZE | [38:32] | 0 | — | [INFO] |
| WP_GRP_ENABLE | [31] | 0 | Disabled | [INFO] |
| R2W_FACTOR | [28:26] | 2 | Write = Read x 4 | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | — | [INFO] |
| COPY | [14] | 1 | Copy | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $55 | $55 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 250,085,376
- Capacity: ~119 GB

### OCR Register (Operating Conditions) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| Power Up Status | [31] | 1 | Ready | [INFO] |
| CCS | [30] | 1 | SDHC/SDXC (block addressing) | **[USED]** |
| UHS-II Status | [29] | 0 | Not UHS-II | [INFO] |
| S18A | [24] | 0 | 3.3V only | [INFO] |
| 3.5-3.6V | [23] | 1 | Supported | [INFO] |
| 3.4-3.5V | [22] | 1 | Supported | [INFO] |
| 3.3-3.4V | [21] | 1 | Supported | [INFO] |
| 3.2-3.3V | [20] | 1 | Supported | [INFO] |
| 3.1-3.2V | [19] | 1 | Supported | [INFO] |
| 3.0-3.1V | [18] | 1 | Supported | [INFO] |
| 2.9-3.0V | [17] | 1 | Supported | [INFO] |
| 2.8-2.9V | [16] | 1 | Supported | [INFO] |
| 2.7-2.8V | [15] | 1 | Supported | [INFO] |

**OCR Value:** $C0FF_8000

### SCR Register (SD Configuration) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| SCR_STRUCTURE | [63:60] | 0 | SCR Version 1.0 | [INFO] |
| SD_SPEC | [59:56] | 2 | SD Physical Layer 2.00+ | **[USED]** |
| DATA_STAT_AFTER_ERASE | [55] | 1 | Data = 1 after erase | [INFO] |
| SD_SECURITY | [54:52] | 4 | SDXC (security v3.xx) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 0 | — | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 3.0x (SD_SPEC=2, SD_SPEC3=1)

### Filesystem (FAT32 - reformatted with P2FMTER)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-XFER |
| Volume Serial | $04AF_0E27 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 30,527 |
| Root Cluster | 2 |
| Total Sectors | 250,077,184 |
| Data Region Start | Sector 61,086 |
| Total Clusters | 3,906,501 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | FAT32 LBA ($0C) partition |
| VBR Read | PASS | |
| Mount | PASS | |
| Regression | PASS | All tests pass |

### Notes

- **Genuine Samsung** - MID $1B + OID "SM" confirms authentic Samsung
- **EVO Select** = Amazon-exclusive variant of EVO Plus line
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- Used in DJI Phantom 4 drone - known reliable for video recording
- Originally factory formatted with exFAT, now reformatted with P2FMTER
- Largest card in catalog (128GB / ~119GB usable)
- DATA_STAT_AFTER_ERASE=1 (erased data reads as 1s, not 0s)
- **Benchmark data complete** — see Benchmark Results sections below for full throughput at 320/270 MHz (file-level only) and 350/250 MHz (all tests, post-fix)

### SPI Speed Characterization

**Test Date:** 2026-02-02
**Test Configuration:**
- SYSCLK: 200 MHz
- Phase 1: 1,000 single-sector reads (quick check)
- Phase 2: 10,000 single-sector reads (statistical confidence)
- Phase 3: 100 x 8-sector multi-block reads (800 sectors, sustained transfer)
- Total reads per speed level: 11,800 sector reads
- Test sectors: 1,000,000 to 1,010,000 (safe area away from FAT)
- CRC-16 verification on every read

**Results:**

| Target | Half Period | Actual | Delta | Phase 1 | Phase 2 | Phase 3 | Failure % |
|--------|-------------|--------|-------|---------|---------|---------|-----------|
| 18 MHz | 6 clocks | 16.6 MHz | -7.4% | 1,000 OK | 10,000 OK | 800 OK | **0.000%** |
| 20 MHz | 5 clocks | 20.0 MHz | +0.0% | 1,000 OK | 10,000 OK | 800 OK | **0.000%** |
| 22 MHz | 5 clocks | 20.0 MHz | -9.0% | 1,000 OK | 10,000 OK | 800 OK | **0.000%** |
| 25 MHz | 4 clocks | 25.0 MHz | +0.0% | 1,000 OK | 10,000 OK | 800 OK | **0.000%** |
| 27 MHz | 4 clocks | 25.0 MHz | -7.4% | timeout* | — | — | **100%** |

*At 27 MHz, CMD6 High Speed switch failed; card became unresponsive during Phase 1.

**Summary:**
- **Maximum Reliable Speed: 25 MHz** (47,200 total sector reads at 0% failure rate)
- CMD6 High Speed mode: Switch **failed** at 27 MHz, card became unresponsive

### Internal Throughput (measured at 25 MHz SPI)

| Metric | Value |
|--------|-------|
| Phase 2 Duration (10,000 reads) | 6.53 seconds |
| Throughput | **783 KB/s** |
| Sectors/second | 1,531 |
| Latency per sector | 0.65 ms |

**Performance Class:** HIGH - Very similar to SanDisk Nintendo Switch (within 0.4%).

### Non-Multiple Sysclk Characterization (320/270 MHz)

**Test Program**: SD_performance_benchmark.spin2 v2.0 | **Card Unit**: SN:C0305565
**Test Date**: 2026-02-08 | **SPI**: 22,857 kHz @ 320 MHz, 22,500 kHz @ 270 MHz

These runs used sysclk values that are NOT clean multiples of the SPI frequency (320/25 = 12.8, 270/25 = 10.8). This shows real-world behavior with non-integer clock dividers. Raw sector data unavailable (pre-fix driver); file-level results are valid.

#### 320 MHz Run (File-Level Only)

**SysClk**: 320 MHz | **SPI**: 22,857 kHz | **Mount**: 202.3 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| File Write 512B | 7,821 | 8,027 | 8,537 | **63** |
| File Write 4 KB | 16,686 | 17,253 | 18,142 | **237** |
| File Write 32 KB | 84,730 | 102,330 | 121,699 | **320** |
| File Read 4 KB | 6,209 | 6,286 | 6,933 | **651** |
| File Read 32 KB | 35,227 | 35,296 | 35,769 | **928** |
| File Read 128 KB | 158,710 | 158,857 | 159,994 | **825** |
| File Read 256 KB | 340,113 | 340,286 | 341,577 | **770** |

#### 270 MHz Run (File-Level Only)

**SysClk**: 270 MHz | **SPI**: 22,500 kHz | **Mount**: 214.4 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| File Write 512B | 8,083 | 8,278 | 8,773 | **61** |
| File Write 4 KB | 17,630 | 18,128 | 18,611 | **225** |
| File Write 32 KB | 87,594 | 100,385 | 122,577 | **326** |
| File Read 4 KB | 6,563 | 6,638 | 7,318 | **617** |
| File Read 32 KB | 37,533 | 37,594 | 38,110 | **871** |
| File Read 128 KB | 154,502 | 154,634 | 155,691 | **847** |
| File Read 256 KB | 342,910 | 343,077 | 344,231 | **764** |

#### Sysclk Effect (320 vs 270 MHz, non-multiple)

| Test | 320 MHz (KB/s) | 270 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| File Read 4 KB | 651 | 617 | -5.2% |
| File Read 256 KB | 770 | 764 | -0.8% |
| File Write 32 KB | 320 | 326 | +1.9% |

File reads at small sizes show the typical ~5% sysclk effect. At large sizes, the card controller's internal read latency dominates. This Samsung card has notably slower file reads (770 KB/s at 256 KB) compared to other cards (1,029-1,274 KB/s), likely due to higher internal controller latency.

### Benchmark Results — Standard Protocol (350/250 MHz, 25 MHz SPI)

**Test Program**: SD_performance_benchmark.spin2 v2.0 | **SPI**: 25,000 kHz at both clock speeds
**Test Date**: 2026-02-25 | **Driver**: commit d62e30d
**Card Unit**: SN:4AC85F42

#### 350 MHz Run

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 201.3 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 556 | 560 | 565 | **914** |
| Write 1x512B | 1,192 | 1,203 | 1,272 | **425** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,060 | 2,063 | 2,065 | **1,985** |
| Read 32 sectors (16 KB) | 7,159 | 7,159 | 7,159 | **2,288** |
| Read 64 sectors (32 KB) | 13,951 | 13,951 | 13,951 | **2,348** |
| Write 8 sectors (4 KB) | 2,715 | 2,728 | 2,800 | **1,501** |
| Write 32 sectors (16 KB) | 7,526 | 7,529 | 7,535 | **2,176** |
| Write 64 sectors (32 KB) | 14,975 | 15,525 | 20,338 | **2,110** |
| **File-Level** | | | | |
| File Write 512B | 7,440 | 7,684 | 8,764 | **66** |
| File Write 4 KB | 16,204 | 16,851 | 17,918 | **243** |
| File Write 32 KB | 82,407 | 101,235 | 120,135 | **323** |
| File Read 4 KB | 6,076 | 6,148 | 6,772 | **666** |
| File Read 32 KB | 33,577 | 33,640 | 34,094 | **974** |
| File Read 128 KB | 152,010 | 152,158 | 153,291 | **861** |
| File Read 256 KB | 313,253 | 313,679 | 315,893 | **835** |
| **Overhead** | | | | |
| File Open | 139 | 203 | 785 | — |
| File Close | 35 | 35 | 36 | — |
| Unmount | — | 3 | — | — |

Multi-sector improvement: 64x single reads = 37,988 us vs 1x CMD18 = 14,130 us (**62% faster**)

#### 250 MHz Run

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 205.0 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 698 | 738 | 778 | **693** |
| Write 1x512B | 1,399 | 1,411 | 1,480 | **362** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,408 | 2,408 | 2,408 | **1,700** |
| Read 32 sectors (16 KB) | 7,955 | 7,955 | 7,961 | **2,059** |
| Read 64 sectors (32 KB) | 15,350 | 15,353 | 15,356 | **2,134** |
| Write 8 sectors (4 KB) | 3,080 | 3,094 | 3,161 | **1,323** |
| Write 32 sectors (16 KB) | 8,320 | 8,328 | 8,372 | **1,967** |
| Write 64 sectors (32 KB) | 16,515 | 16,541 | 16,567 | **1,981** |
| **File-Level** | | | | |
| File Write 512B | 8,911 | 9,192 | 10,569 | **55** |
| File Write 4 KB | 16,445 | 18,895 | 19,602 | **216** |
| File Write 32 KB | 87,939 | 99,754 | 126,192 | **328** |
| File Read 4 KB | 5,619 | 5,683 | 6,256 | **720** |
| File Read 32 KB | 45,008 | 45,087 | 45,688 | **726** |
| File Read 128 KB | 150,428 | 150,552 | 151,568 | **870** |
| File Read 256 KB | 309,960 | 310,343 | 312,499 | **844** |
| **Overhead** | | | | |
| File Open | 195 | 254 | 787 | — |
| File Close | 50 | 50 | 50 | — |
| Unmount | — | 3 | — | — |

Multi-sector improvement: 64x single reads = 52,875 us vs 1x CMD18 = 15,294 us (**71% faster**)

#### Sysclk Effect (350 vs 250 MHz)

| Test | 350 MHz (KB/s) | 250 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| **Raw Single-Sector** | | | |
| Read 1x512B | 914 | 693 | +31.9% |
| Write 1x512B | 425 | 362 | +17.4% |
| **Raw Multi-Sector** | | | |
| Read 64 (32 KB) | 2,348 | 2,134 | +10.0% |
| Write 64 (32 KB) | 2,110 | 1,981 | +6.5% |
| **File-Level** | | | |
| File Write 32 KB | 323 | 328 | -1.5% |
| File Read 4 KB | 666 | 720 | -7.5% |
| File Read 256 KB | 835 | 844 | -1.1% |

This card's internal controller latency dominates throughput — file reads show minimal sysclk effect. Raw operations show the expected 10-30% improvement at higher sysclk.
