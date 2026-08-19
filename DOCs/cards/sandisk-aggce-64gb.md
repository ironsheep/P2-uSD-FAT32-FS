# Card: SanDisk Extreme PRO 64GB SDXC

**Label:** [`sandisk-extreme-pro-64gb`](CARD-LABELS.md#sandisk-extreme-pro-64gb) — printed text is mastered there, not here
**Unique ID:** `SanDisk_AGGCE_8.0_DD1C1144_201703`
**Test Date:** 2026-02-25

### Card Designator

```
SanDisk AGGCE SDXC 59GB [FAT32] SD 5.x rev8.0 SN:DD1C1144 2017/03
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

### Raw Registers

```
CID: $03 $53 $44 $41 $47 $47 $43 $45 $80 $DD $1C $11 $44 $01 $13 $55
CSD: $40 $0E $00 $32 $5B $59 $00 $01 $DB $D3 $7F $80 $0A $40 $40 $DF
OCR: $C0FF_8000
SCR: $02 $45 $84 $43 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (SanDisk) | [INFO] |
| PNM | [103:64] | $41 $47 $47 $43 $45 | "AGGCE" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $DD1C_1144 | 3,709,178,180 | [INFO] |
| MDT | [19:8] | $113 | 2017-03 (March 2017) | [INFO] |
| CRC7 | [7:1] | $2A | $2A | [INFO] |

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
| C_SIZE | [69:48] | $1DBD3 | 121,811 (60,906 MB) | **[USED]** |
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
| CRC7 | [7:1] | $6F | $6F | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 124,735,488
- Capacity: ~59 GB

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
| DATA_STAT_AFTER_ERASE | [55] | 0 | Data = 0 after erase | [INFO] |
| SD_SECURITY | [54:52] | 4 | SDXC (security v3.xx) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 1 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 4.xx (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1)

### Filesystem (Factory - exFAT)

| Field | Value |
|-------|-------|
| MBR Partition Type | $07 (exFAT/NTFS) |
| Factory Format | exFAT (default for 64GB+) |

**Note:** Card ships with exFAT filesystem. Needs FAT32 format for P2 SD driver compatibility.

### Speed Characterization Results

| Speed | Half Period | Actual | Phase 1 | Phase 2 | Phase 3 | Result |
|-------|-------------|--------|---------|---------|---------|--------|
| 18 MHz | 6 clocks | 16.6 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 20 MHz | 5 clocks | 20.0 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 22 MHz | 5 clocks | 20.0 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 25 MHz | 4 clocks | 25.0 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 27 MHz | 4 clocks | 25.0 MHz | — | — | — | CMD6 FAIL |

**Maximum Reliable SPI Speed:** 25 MHz (limited by SYSCLK=200 MHz, not card)

### Internal Throughput

| Metric | Value |
|--------|-------|
| Test Iterations | 10,000 single-sector reads |
| Elapsed Time | ~5.9 seconds |
| Throughput | **866 KB/s** |
| Average Latency | 0.59 ms/sector |
| Performance Class | HIGH |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | exFAT partition detected |
| Mount | N/A | Requires FAT32 format first |

### Notes

- **Genuine SanDisk** - MID $03 + OID "SD" confirms authentic SanDisk/Western Digital
- **Extreme PRO** = SanDisk's premium professional line (highest tier)
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **V30** = Video Speed Class 30 (30 MB/s sustained sequential write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- Product name "AGGCE" = internal SanDisk nomenclature (64GB variant)
- Related to AGGCF (128GB variant) - same product line, different capacity
- **CCC $5B5** - Standard classes only (no video stream class)
- **SD 4.xx spec** compliant (SD_SPEC4=1)
- Factory formatted with exFAT (not FAT32)
- Needs FAT32 reformat before use with P2 SD driver
- **High throughput (866 KB/s)** - excellent for embedded applications
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)
- Manufactured March 2017 (4 months earlier than 128GB AGGCF variant)
- **Benchmark data available** — see Benchmark Results section below for detailed throughput measurements (raw, multi-sector, and file-level)

### Benchmark Results — Standard Protocol (350/250 MHz, 25 MHz SPI)

**Test Date:** 2026-02-25
**Test Program**: SD_performance_benchmark.spin2 v2.0
**Driver Commit**: d62e30d
**Benchmark Protocol**: Both runs use 25 MHz SPI clock — isolates Spin2 overhead effect from SPI bus speed.
**Note**: Benchmark unit SN:$A345_3C0E (different physical unit, same product/revision as characterized unit SN:DD1C1144).

#### 350 MHz Run

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 234.2 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 513 | 513 | 513 | **998** |
| Write 1x512B | 1,188 | 1,195 | 1,218 | **428** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 1,958 | 1,958 | 1,958 | **2,091** |
| Read 32 sectors (16 KB) | 6,958 | 6,958 | 6,962 | **2,354** |
| Read 64 sectors (32 KB) | 13,607 | 13,607 | 13,607 | **2,408** |
| Write 8 sectors (4 KB) | 2,529 | 2,586 | 2,723 | **1,583** |
| Write 32 sectors (16 KB) | 7,770 | 8,258 | 11,500 | **1,984** |
| Write 64 sectors (32 KB) | 14,755 | 14,822 | 14,864 | **2,210** |
| **File-Level** | | | | |
| File Write 512B | 6,516 | 6,893 | 9,234 | **74** |
| File Write 4 KB | 13,746 | 14,500 | 16,213 | **282** |
| File Write 32 KB | 73,385 | 74,976 | 75,914 | **437** |
| File Read 4 KB | 3,812 | 3,857 | 4,252 | **1,061** |
| File Read 32 KB | 28,986 | 29,030 | 29,430 | **1,128** |
| File Read 128 KB | 115,616 | 115,750 | 116,890 | **1,132** |
| File Read 256 KB | 237,793 | 237,955 | 239,243 | **1,101** |
| **Overhead** | | | | |
| File Open | 138 | 181 | 573 | — |
| File Close | 35 | 35 | 36 | — |
| Mount | — | 234,200 | — | — |

Multi-sector improvement: 64x single reads = 36,118 us vs 1x CMD18 = 13,620 us (**62% faster**)

#### 250 MHz Run

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 236.4 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 582 | 582 | 583 | **879** |
| Write 1x512B | 1,256 | 1,270 | 1,291 | **403** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,145 | 2,145 | 2,145 | **1,909** |
| Read 32 sectors (16 KB) | 7,561 | 7,561 | 7,561 | **2,166** |
| Read 64 sectors (32 KB) | 14,759 | 14,759 | 14,759 | **2,220** |
| Write 8 sectors (4 KB) | 2,615 | 2,793 | 2,871 | **1,466** |
| Write 32 sectors (16 KB) | 8,451 | 8,604 | 8,838 | **1,904** |
| Write 64 sectors (32 KB) | 16,030 | 16,203 | 16,681 | **2,022** |
| **File-Level** | | | | |
| File Write 512B | 7,059 | 7,530 | 9,180 | **67** |
| File Write 4 KB | 14,686 | 15,491 | 17,275 | **264** |
| File Write 32 KB | 77,791 | 79,083 | 80,053 | **414** |
| File Read 4 KB | 4,319 | 4,368 | 4,805 | **937** |
| File Read 32 KB | 32,593 | 32,648 | 33,098 | **1,003** |
| File Read 128 KB | 129,531 | 129,661 | 130,757 | **1,010** |
| File Read 256 KB | 266,443 | 266,670 | 267,650 | **983** |
| **Overhead** | | | | |
| File Open | 193 | 241 | 679 | — |
| File Close | 49 | 49 | 50 | — |
| Mount | — | 236,400 | — | — |

Multi-sector improvement: 64x single reads = 38,700 us vs 1x CMD18 = 14,765 us (**61% faster**)

#### Sysclk Effect (350 vs 250 MHz at same 25 MHz SPI)

Both runs use identical 25 MHz SPI clock — differences are purely Spin2 inter-transfer overhead.

| Test | 350 MHz (KB/s) | 250 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 998 | 879 | +14% |
| Raw Read 64x (32 KB) | 2,408 | 2,220 | +8% |
| Raw Write 64x (32 KB) | 2,210 | 2,022 | +9% |
| File Read 256 KB | 1,101 | 983 | +12% |
| File Write 32 KB | 437 | 414 | +6% |

**Note:** Exceptional card — zero variance on raw single-sector reads (Min=Max=513 us at 350 MHz), and highest file write throughput (437 KB/s) of all tested cards. Near-zero multi-sector read variance indicates excellent controller design.
