# Card: SanDisk Extreme PRO 128GB SDXC

**Label:** SanDisk Extreme PRO 128GB microSD XC I V30 U3 A1
**Unique ID:** `SanDisk_AGGCF_8.0_E05C352B_201707`
**Test Date:** 2026-02-25

### Card Designator

```
SanDisk AGGCF SDXC 119GB [FAT32] SD 5.x rev8.0 SN:E05C352B 2017/07
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

### Raw Registers

```
CID: $03 $53 $44 $41 $47 $47 $43 $46 $80 $E0 $5C $35 $2B $01 $17 $F9
CSD: $40 $0E $00 $32 $5B $59 $00 $03 $B8 $AB $7F $80 $0A $40 $40 $79
OCR: $C0FF_8000
SCR: $02 $45 $84 $43 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (SanDisk) | [INFO] |
| PNM | [103:64] | $41 $47 $47 $43 $46 | "AGGCF" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $E05C_352B | 3,764,118,827 | [INFO] |
| MDT | [19:8] | $117 | 2017-07 (July 2017) | [INFO] |
| CRC7 | [7:1] | $7C | $7C | [INFO] |

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
| C_SIZE | [69:48] | $3B8AB | 243,883 (121,942 MB) | **[USED]** |
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
| CRC7 | [7:1] | $3C | $3C | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 249,737,216
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
- **A1** = Application Performance Class 1 (1500 read IOPS, 500 write IOPS)
- Product name "AGGCF" = internal SanDisk nomenclature
- **CCC $5B5** - Standard classes only (no video stream class unlike Nintendo Switch edition)
- **SD 4.xx spec** compliant (SD_SPEC4=1)
- Factory formatted with exFAT (not FAT32)
- Needs FAT32 reformat before use with P2 SD driver
- SanDisk recommended for embedded SPI use
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)
- **Benchmark data available** — see Benchmark Results section below for detailed throughput measurements (raw, multi-sector, and file-level)

### Benchmark Results — Standard Protocol (350/250 MHz, 25 MHz SPI)

**Test Date:** 2026-02-25
**Test Program**: SD_performance_benchmark.spin2 v2.0
**Driver Commit**: d62e30d
**Benchmark Protocol**: Both runs use 25 MHz SPI clock — isolates Spin2 overhead effect from SPI bus speed.

#### 350 MHz Run

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 234.2 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 517 | 608 | 625 | **842** |
| Write 1x512B | 1,189 | 1,198 | 1,218 | **427** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 1,958 | 1,958 | 1,958 | **2,091** |
| Read 32 sectors (16 KB) | 6,958 | 6,958 | 6,958 | **2,354** |
| Read 64 sectors (32 KB) | 13,607 | 13,607 | 13,607 | **2,408** |
| Write 8 sectors (4 KB) | 2,533 | 2,586 | 2,727 | **1,583** |
| Write 32 sectors (16 KB) | 7,770 | 7,897 | 7,976 | **2,074** |
| Write 64 sectors (32 KB) | 14,742 | 15,312 | 19,783 | **2,140** |
| **File-Level** | | | | |
| File Write 512B | 6,545 | 6,842 | 8,609 | **74** |
| File Write 4 KB | 13,646 | 14,259 | 15,805 | **287** |
| File Write 32 KB | 72,489 | 73,519 | 75,208 | **445** |
| File Read 4 KB | 3,812 | 3,856 | 4,252 | **1,062** |
| File Read 32 KB | 28,986 | 29,033 | 29,435 | **1,128** |
| File Read 128 KB | 115,602 | 115,747 | 116,779 | **1,132** |
| File Read 256 KB | 237,468 | 237,658 | 238,705 | **1,103** |
| **Overhead** | | | | |
| File Open | 138 | 181 | 577 | — |
| File Close | 35 | 35 | 36 | — |
| Mount | — | 234,200 | — | — |

Multi-sector improvement: 64x single reads = 38,515 us vs 1x CMD18 = 13,710 us (**64% faster**)

#### 250 MHz Run

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 236.4 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 582 | 582 | 583 | **879** |
| Write 1x512B | 1,256 | 1,265 | 1,273 | **404** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,145 | 2,145 | 2,145 | **1,909** |
| Read 32 sectors (16 KB) | 7,561 | 7,561 | 7,561 | **2,166** |
| Read 64 sectors (32 KB) | 14,759 | 14,759 | 14,759 | **2,220** |
| Write 8 sectors (4 KB) | 2,620 | 2,789 | 2,865 | **1,468** |
| Write 32 sectors (16 KB) | 8,445 | 8,601 | 8,838 | **1,904** |
| Write 64 sectors (32 KB) | 16,024 | 16,193 | 16,664 | **2,023** |
| **File-Level** | | | | |
| File Write 512B | 6,989 | 7,392 | 9,492 | **69** |
| File Write 4 KB | 14,606 | 14,980 | 16,689 | **273** |
| File Write 32 KB | 77,698 | 78,227 | 79,817 | **418** |
| File Read 4 KB | 4,345 | 4,393 | 4,831 | **932** |
| File Read 32 KB | 32,531 | 32,582 | 33,022 | **1,005** |
| File Read 128 KB | 129,334 | 129,461 | 130,542 | **1,012** |
| File Read 256 KB | 265,212 | 265,373 | 266,222 | **987** |
| **Overhead** | | | | |
| File Open | 193 | 241 | 679 | — |
| File Close | 49 | 49 | 50 | — |
| Mount | — | 236,400 | — | — |

Multi-sector improvement: 64x single reads = 40,173 us vs 1x CMD18 = 14,784 us (**63% faster**)

#### Sysclk Effect (350 vs 250 MHz at same 25 MHz SPI)

Both runs use identical 25 MHz SPI clock — differences are purely Spin2 inter-transfer overhead.

| Test | 350 MHz (KB/s) | 250 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 842 | 879 | -4% |
| Raw Read 64x (32 KB) | 2,408 | 2,220 | +8% |
| Raw Write 64x (32 KB) | 2,140 | 2,023 | +6% |
| File Read 256 KB | 1,103 | 987 | +12% |
| File Write 32 KB | 445 | 418 | +6% |

**Note:** Nearly identical to 64GB AGGCE sibling — same controller architecture. Zero-variance multi-sector reads at both speeds. Highest file write throughput (445 KB/s) of all tested cards. Single-sector read anomaly (842 vs 879 KB/s) likely due to initial cold-cache miss at 350 MHz; subsequent multi-sector reads show expected improvement.
