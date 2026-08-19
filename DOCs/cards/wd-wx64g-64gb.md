# Card: Western Digital WD Purple QD101 64GB SDXC

**Label:** [`wd-purple-qd101-64gb`](CARD-LABELS.md#wd-purple-qd101-64gb) — printed text is mastered there, not here
**Disposition:** `retained`
**Unique ID:** `SanDisk_WX64G_8.0_EEBAD6C0_202403`
**Test Date:** 2026-02-17 (initial characterization)

### Card Designator

```
SanDisk WX64G SDXC 59GB [FAT32] SD 6.x rev8.0 SN:$EEBA_D6C0 2024/03
Class 10, U1, A2, V10, SPI 25 MHz  [P2FMTER]
```

### Raw Registers

```
CID: $03 $53 $44 $57 $58 $36 $34 $47 $80 $EE $BA $D6 $C0 $01 $83 $4B
CSD: $40 $0E $00 $32 $DB $79 $00 $01 $DB $D3 $7F $80 $0A $40 $40 $F9
OCR: $C0FF_8000
SCR: $02 $45 $84 $87 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk (WD subsidiary) | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (ASCII) | [INFO] |
| PNM | [103:64] | $57 $58 $36 $34 $47 | "WX64G" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $EEBA_D6C0 | 4,009,035,456 | [INFO] |
| MDT | [19:8] | $183 | 2024-03 (March 2024) | [INFO] |
| CRC7 | [7:1] | $25 | $25 | [INFO] |

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
| C_SIZE | [69:48] | $1DBD3 | 121,811 (60,906 MB) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 127 | Erase sector = 64 KB | [INFO] |
| WP_GRP_SIZE | [38:32] | 0 | -- | [INFO] |
| WP_GRP_ENABLE | [31] | 0 | Disabled | [INFO] |
| R2W_FACTOR | [28:26] | 2 | Write = Read x 4 | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | -- | [INFO] |
| COPY | [14] | 1 | Copy | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $7C | $7C | [INFO] |

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
Class 10, U1, A2, V10, SPI 25 MHz
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
| Sectors per FAT | 15,226 |
| Root Cluster | 2 |
| Total Sectors | 124,735,488 |
| Data Region Start | Sector 38,676 |
| Total Clusters | 1,948,387 |

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
| SD Status | PASS | ACMD13 (64 bytes) -- Class 10, U1, A2, V10 |
| MBR Read | PASS | exFAT ($07) partition -- reformatted to FAT32 |
| VBR Read | PASS | (confirmed via benchmark mount) |
| Format | PASS | FAT32 formatted with P2FMTER |
| Mount | PASS | (confirmed via benchmark) |
| FSCK | PASS | 0 errors, 0 repairs, CLEAN |

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 232.7 ms | **Volume:** P2-BENCH | **Free:** 60,903 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 536 us | 556 us | 712 us | 920 KB/s |
| Write (1x512B) | 512B | 1,483 us | 1,534 us | 1,902 us | 333 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 1,991 us | 1,991 us | 1,991 us | 2,057 KB/s |
| 32 sectors | 16 KB | 6,979 us | 6,979 us | 6,980 us | 2,347 KB/s |
| 64 sectors | 32 KB | 13,631 us | 13,634 us | 13,636 us | 2,403 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,493 us | 2,540 us | 2,707 us | 1,612 KB/s |
| 32 sectors | 16 KB | 7,720 us | 7,820 us | 7,926 us | 2,095 KB/s |
| 64 sectors | 32 KB | 15,241 us | 15,250 us | 15,262 us | 2,148 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 7,746 us | 8,180 us | 8,245 us | 62 KB/s |
| create+write+close | 4 KB | 17,089 us | 17,217 us | 17,331 us | 237 KB/s |
| create+write+close | 32 KB | 89,613 us | 90,303 us | 92,780 us | 362 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 4,242 us | 4,295 us | 4,732 us | 953 KB/s |
| open+read+close | 32 KB | 32,972 us | 33,032 us | 33,475 us | 992 KB/s |
| open+read+close | 128 KB | 132,238 us | 132,360 us | 133,272 us | 990 KB/s |
| open+read+close | 256 KB | 264,587 us | 264,719 us | 265,617 us | 990 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 98 us | 147 us | 593 us | -- |
| File Close | -- | 20 us | 20 us | 21 us | -- |
| Unmount | -- | -- | 2 ms | -- | -- |

**Multi-sector gain:** 64x single=34,439 us vs 1x multi=13,635 us --> **60% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 235.1 ms | **Volume:** P2-BENCH | **Free:** 60,903 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 602 us | 602 us | 602 us | 850 KB/s |
| Write (1x512B) | 512B | 1,560 us | 1,574 us | 1,588 us | 325 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,177 us | 2,177 us | 2,183 us | 1,881 KB/s |
| 32 sectors | 16 KB | 7,578 us | 7,578 us | 7,584 us | 2,162 KB/s |
| 64 sectors | 32 KB | 14,779 us | 14,779 us | 14,779 us | 2,217 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,700 us | 2,727 us | 2,745 us | 1,502 KB/s |
| 32 sectors | 16 KB | 8,383 us | 8,402 us | 8,433 us | 1,950 KB/s |
| 64 sectors | 32 KB | 16,393 us | 16,396 us | 16,399 us | 1,998 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 8,007 us | 8,494 us | 8,554 us | 60 KB/s |
| create+write+close | 4 KB | 18,024 us | 18,138 us | 18,226 us | 225 KB/s |
| create+write+close | 32 KB | 93,994 us | 94,899 us | 97,177 us | 345 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 4,753 us | 4,815 us | 5,309 us | 850 KB/s |
| open+read+close | 32 KB | 36,694 us | 36,752 us | 37,250 us | 891 KB/s |
| open+read+close | 128 KB | 146,429 us | 146,592 us | 147,574 us | 894 KB/s |
| open+read+close | 256 KB | 305,801 us | 305,967 us | 306,971 us | 856 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 138 us | 192 us | 681 us | -- |
| File Close | -- | 29 us | 29 us | 29 us | -- |
| Unmount | -- | -- | 3 ms | -- | -- |

**Multi-sector gain:** 64x single=38,611 us vs 1x multi=14,779 us --> **61% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 920 | 850 | +8% |
| Raw write 1x (KB/s) | 333 | 325 | +2% |
| Raw read 64x (KB/s) | 2,403 | 2,217 | +8% |
| Raw write 64x (KB/s) | 2,148 | 1,998 | +8% |
| File read 256KB (KB/s) | 990 | 856 | +16% |
| File write 32KB (KB/s) | 362 | 345 | +5% |
| Multi-sector gain | 60% | 61% | -- |

### Notes

- **WD Purple QD101** -- surveillance-grade microSD designed for continuous video recording
- **Western Digital brand** but uses **SanDisk MID $03** (WD acquired SanDisk in 2016)
- **OID "SD"** -- standard SanDisk OEM/Application ID
- **Product name "WX64G"** -- WD internal product code (W=WD, X=XC, 64G=64GB)
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **A2** = Application Performance Class 2 (4000 read IOPS, 2000 write IOPS) -- confirmed via ACMD13
- **V10** = Video Speed Class 10 (10 MB/s sustained sequential write)
- **U1** = UHS Speed Class 1 (10 MB/s minimum write speed)
- **Class 10** = Speed Class 10 (10 MB/s minimum write speed)
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2)
- **SD_SECURITY = 4** -- SDXC Card security v3.xx (CPRM)
- **CMD_SUPPORT $00** -- no CMD20 or CMD23 support
- **CCC $DB7** = Classes 0,1,2,4,5,7,8,10 (includes Class 10 switch, Class 2 block read)
- **COPY flag = 1** -- indicates factory pre-loaded content or copy card
- **CMD6 High Speed switch fails** -- despite CCC including Class 10 (switch), CMD6 returns failure at 27 MHz
- First Western Digital / WD Purple card in collection (card #20)
- Manufactured March 2024
- Originally shipped with exFAT, reformatted with P2FMTER for FAT32
- **Slowest write performance in collection** -- single-sector write 333 KB/s (vs 617-680 KB/s for Samsung/Lexar), file write 362 KB/s at 32 KB (vs 616-758 KB/s). Surveillance cards optimize for sustained sequential write endurance, not random write speed.
- **Moderate read performance** -- file read 990 KB/s (vs best 1,444 KB/s Samsung PRO Endurance)
- **Highest multi-sector gain: 60%** -- because single-sector overhead is so high (slow controller), batching provides the largest relative improvement of any card tested
