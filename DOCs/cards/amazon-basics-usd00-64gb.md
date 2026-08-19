# Card: Amazon Basics 64GB SDXC

**Label:** [`amazon-basics-xc-64gb`](CARD-LABELS.md#amazon-basics-xc-64gb) — printed text is mastered there, not here
**Unique ID:** `Longsys/Lexar_USD00_2.0_35841E2E_202507`
**Test Date:** 2026-02-17 (initial characterization)

### Card Designator

```
Longsys/Lexar USD00 SDXC 58GB [FAT32] SD 6.x rev2.0 SN:$3584_1E2E 2025/07
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### Raw Registers

```
CID: $AD $4C $53 $55 $53 $44 $30 $30 $20 $35 $84 $1E $2E $A1 $97 $27
CSD: $40 $0E $00 $32 $DB $79 $00 $01 $D7 $7B $7F $80 $0A $40 $00 $8B
OCR: $C0FF_8000
SCR: $02 $45 $84 $87 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $AD | Longsys/Lexar | **[USED]** |
| OID | [119:104] | $4C $53 | "LS" (ASCII) | [INFO] |
| PNM | [103:64] | $55 $53 $44 $30 $30 | "USD00" | [INFO] |
| PRV | [63:56] | $20 | 2.0 | [INFO] |
| PSN | [55:24] | $3584_1E2E | 897,843,758 | [INFO] |
| MDT | [19:8] | $197 | 2025-07 (July 2025) | [INFO] |
| CRC7 | [7:1] | $13 | $13 | [INFO] |

### CSD Register (Card Specific Data) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| CSD_STRUCTURE | [127:126] | 1 | CSD Version 2.0 (SDHC/SDXC) | **[USED]** |
| TAAC | [119:112] | $0E | Read access time-1 | **[USED]** |
| NSAC | [111:104] | $00 | 0 CLK cycles | **[USED]** |
| TRAN_SPEED | [103:96] | $32 | 25 MHz max | **[USED]** |
| CCC | [95:84] | $DB7 | Classes 0,1,2,4,5,7,8,10 | [INFO] |
| READ_BL_LEN | [83:80] | 9 | 512 bytes | [INFO] |
| READ_BL_PARTIAL | [79] | 0 | Not allowed | [INFO] |
| WRITE_BLK_MISALIGN | [78] | 0 | Not allowed | [INFO] |
| READ_BLK_MISALIGN | [77] | 0 | Not allowed | [INFO] |
| DSR_IMP | [76] | 0 | DSR not implemented | [INFO] |
| C_SIZE | [69:48] | $1D77B | 120,699 (60,350 MB) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 127 | Erase sector = 64 KB | [INFO] |
| WP_GRP_SIZE | [38:32] | 0 | -- | [INFO] |
| WP_GRP_ENABLE | [31] | 0 | Disabled | [INFO] |
| R2W_FACTOR | [28:26] | 2 | Write = Read x 4 | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | -- | [INFO] |
| COPY | [14] | 0 | Original | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $45 | $45 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 123,596,800
- Capacity: ~58 GB

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
| SD_SECURITY | [54:52] | 4 | SDXC Card (security v3.xx) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | -- | [INFO] |

**SD Version:** 6.x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1, SD_SPECX=2)

### ACMD13 SD Status

```
Class 10, U3, A2, V30, SPI 25 MHz
```

### Filesystem (FAT32 - reformatted with P2FMTER)

*Originally shipped as exFAT ($07). Reformatted to FAT32 by P2 format utility.*

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-BENCH |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 15,087 |
| Root Cluster | 2 |
| Total Sectors | 123,596,800 |
| Data Region Start | Sector 38,398 |
| Total Clusters | 1,930,600 |

### SPI Speed Characterization

| Speed | Actual | Phase 1 (1K) | Phase 2 (10K) | Phase 3 (800 multi) | Result |
|-------|--------|--------------|---------------|---------------------|--------|
| 18 MHz | 16.6 MHz | 0 CRC err | 0 CRC err | 0 CRC err | PASS |
| 20 MHz | 20.0 MHz | 0 CRC err | 0 CRC err | 0 CRC err | PASS |
| 22 MHz | 20.0 MHz | 0 CRC err | 0 CRC err | 0 CRC err | PASS |
| 25 MHz | 25.0 MHz | 0 CRC err | 0 CRC err | 0 CRC err | PASS |
| 27 MHz | 25.0 MHz | CMD6 FAIL, timeout | -- | -- | FAIL |

**Recommended Max: 25 MHz** (CMD6 High Speed switch fails at 27 MHz)

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| SD Status | PASS | ACMD13 (64 bytes) -- Class 10, U3, A2, V30 |
| MBR Read | PASS | exFAT ($07) partition -- reformatted to FAT32 |
| VBR Read | PASS | (confirmed via benchmark mount) |
| Format | PASS | FAT32 formatted with P2FMTER |
| Mount | PASS | (confirmed via benchmark) |
| FSCK | PASS | 0 errors, 0 repairs, CLEAN |

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 232.5 ms | **Volume:** P2-BENCH | **Free:** 60,347 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 408 us | 411 us | 431 us | 1,245 KB/s |
| Write (1x512B) | 512B | 604 us | 605 us | 609 us | 846 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 1,867 us | 1,869 us | 1,886 us | 2,191 KB/s |
| 32 sectors | 16 KB | 6,856 us | 6,858 us | 6,879 us | 2,389 KB/s |
| 64 sectors | 32 KB | 13,503 us | 13,509 us | 13,526 us | 2,425 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,032 us | 2,032 us | 2,036 us | 2,015 KB/s |
| 32 sectors | 16 KB | 7,222 us | 7,222 us | 7,222 us | 2,268 KB/s |
| 64 sectors | 32 KB | 14,212 us | 14,213 us | 14,216 us | 2,305 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 3,992 us | 4,205 us | 4,238 us | 121 KB/s |
| create+write+close | 4 KB | 8,455 us | 8,472 us | 8,499 us | 483 KB/s |
| create+write+close | 32 KB | 42,139 us | 42,312 us | 42,491 us | 774 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 3,084 us | 3,125 us | 3,463 us | 1,310 KB/s |
| open+read+close | 32 KB | 23,719 us | 23,765 us | 24,116 us | 1,378 KB/s |
| open+read+close | 128 KB | 94,494 us | 94,614 us | 95,303 us | 1,385 KB/s |
| open+read+close | 256 KB | 188,856 us | 189,001 us | 189,629 us | 1,386 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 98 us | 135 us | 472 us | -- |
| File Close | -- | 20 us | 20 us | 21 us | -- |
| Unmount | -- | -- | 1 ms | -- | -- |

**Multi-sector gain:** 64x single=29,852 us vs 1x multi=13,517 us --> **54% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 234.8 ms | **Volume:** P2-BENCH | **Free:** 60,347 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 481 us | 484 us | 507 us | 1,057 KB/s |
| Write (1x512B) | 512B | 668 us | 668 us | 668 us | 766 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,057 us | 2,063 us | 2,082 us | 1,985 KB/s |
| 32 sectors | 16 KB | 7,458 us | 7,464 us | 7,483 us | 2,195 KB/s |
| 64 sectors | 32 KB | 14,659 us | 14,666 us | 14,684 us | 2,234 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,234 us | 2,235 us | 2,246 us | 1,832 KB/s |
| 32 sectors | 16 KB | 7,911 us | 7,913 us | 7,917 us | 2,070 KB/s |
| 64 sectors | 32 KB | 15,553 us | 15,553 us | 15,554 us | 2,106 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 4,768 us | 5,469 us | 5,561 us | 93 KB/s |
| create+write+close | 4 KB | 10,176 us | 10,200 us | 10,223 us | 401 KB/s |
| create+write+close | 32 KB | 46,177 us | 47,749 us | 59,137 us | 686 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 3,563 us | 3,606 us | 3,984 us | 1,135 KB/s |
| open+read+close | 32 KB | 27,998 us | 28,064 us | 28,463 us | 1,167 KB/s |
| open+read+close | 128 KB | 109,200 us | 109,301 us | 110,054 us | 1,199 KB/s |
| open+read+close | 256 KB | 217,741 us | 217,845 us | 218,576 us | 1,203 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 138 us | 180 us | 560 us | -- |
| File Close | -- | 29 us | 29 us | 29 us | -- |
| Unmount | -- | -- | 1 ms | -- | -- |

**Multi-sector gain:** 64x single=32,223 us vs 1x multi=14,671 us --> **54% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 1,245 | 1,057 | +18% |
| Raw write 1x (KB/s) | 846 | 766 | +10% |
| Raw read 64x (KB/s) | 2,425 | 2,234 | +9% |
| Raw write 64x (KB/s) | 2,305 | 2,106 | +9% |
| File read 256KB (KB/s) | 1,386 | 1,203 | +15% |
| File write 32KB (KB/s) | 774 | 686 | +13% |
| Multi-sector gain | 54% | 54% | -- |

### Notes

- **Amazon Basics brand** -- Amazon's private label, sourced from **Longsys** (MID $AD), same silicon manufacturer as Lexar
- **OID "LS"** -- Longsys OEM/Application ID (vs "SD" for SanDisk)
- **Product name "USD00"** -- generic Longsys product code for Amazon Basics line
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **A2** = Application Performance Class 2 (4000 read IOPS, 2000 write IOPS) -- confirmed via ACMD13
- **V30** = Video Speed Class 30 (30 MB/s sustained sequential write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- **Class 10** = Speed Class 10 (10 MB/s minimum write speed)
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2)
- **SD_SECURITY = 4** -- SDXC Card security v3.xx (CPRM)
- **CMD_SUPPORT $00** -- no CMD20 or CMD23 support
- **CCC $DB7** = Classes 0,1,2,4,5,7,8,10 (includes Class 10 switch, Class 2 block read)
- **COPY flag = 0** -- original card (not copy/pre-loaded)
- **CMD6 High Speed switch fails** -- despite CCC including Class 10 (switch), CMD6 returns failure at 27 MHz
- First Amazon Basics card in collection (card #21)
- Manufactured July 2025
- Originally shipped with exFAT, reformatted with P2FMTER for FAT32
- **Top-tier performance** -- fastest file write in collection at 774 KB/s (32KB), second-fastest file read at 1,386 KB/s (256KB)
- **Fastest single-sector write: 846 KB/s** -- significantly faster than most cards (vs 333-680 KB/s range for others)
- **Very fast single-sector read: 1,245 KB/s** -- among the fastest in collection
- **U3/V30 rating shows** -- the higher speed class ratings correlate with better SPI write performance
- **Moderate multi-sector gain (54%)** -- fast single-sector performance means less relative benefit from batching
