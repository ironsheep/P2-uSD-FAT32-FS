# Card: SanDisk 8GB SDHC (Taiwan)

**Label:** SanDisk 8GB (4) microSD HC, Made in Taiwan
**Unique ID:** `SanDisk_SS08G_3.0_DAAEE8AD_201509`
**Test Date:** 2026-03-17 (characterization + benchmark)

### Card Designator

```
SanDisk SS08G SDHC 7GB [FAT32] SD 3.x rev3.0 SN:DAAEE8AD 2015/09
Class 4, SPI 25 MHz
```

### Raw Registers

```
CID: $03 $50 $54 $53 $53 $30 $38 $47 $30 $DA $AE $E8 $AD $00 $F9 $BB
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $39 $B7 $7F $80 $0A $40 $00 $3B
OCR: $C0FF_8000
SCR: $02 $35 $80 $02 $01 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk | **[USED]** |
| OID | [119:104] | $50 $54 | "PT" (Taiwan production?) | [INFO] |
| PNM | [103:64] | $53 $53 $30 $38 $47 | "SS08G" | [INFO] |
| PRV | [63:56] | $30 | 3.0 | [INFO] |
| PSN | [55:24] | $DAAE_E8AD | 3,668,748,461 | [INFO] |
| MDT | [19:8] | $0F9 | 2015-09 (September 2015) | [INFO] |
| CRC7 | [7:1] | $5D | $5D | [INFO] |

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
| C_SIZE | [69:48] | $39B7 | 14,775 (7,388 MB) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 127 | Erase sector = 64 KB | [INFO] |
| WP_GRP_SIZE | [38:32] | 0 | — | [INFO] |
| WP_GRP_ENABLE | [31] | 0 | Disabled | [INFO] |
| R2W_FACTOR | [28:26] | 2 | Write = Read x 4 | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | — | [INFO] |
| COPY | [14] | 0 | Original | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $1D | $1D | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 15,130,624
- Capacity: ~7 GB

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
| SD_SECURITY | [54:52] | 3 | SDHC Card (security v2.00) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 0 | — | [INFO] |
| CMD_SUPPORT | [33:32] | $01 | CMD20 Speed Class supported | [INFO] |

**SD Version:** 3.0x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=0)

### Filesystem (FAT32)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0B (FAT32 CHS) |
| VBR Sector | 8,192 |
| OEM Name | (blank) |
| Volume Label | NO NAME |
| Volume Serial | $1DBC_FED9 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 4,500 |
| Number of FATs | 2 |
| Sectors per FAT | 1,846 |
| Root Cluster | 2 |
| Total Sectors | 15,122,432 |
| Total Clusters | 236,160 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | FAT32 CHS partition |
| VBR Read | PASS | Valid FAT32 filesystem |
| Mount | READY | FAT32 formatted - ready for use |

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 203.5 ms | **Volume:** NO NAME | **Free:** 7,383 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 741 us | 745 us | 748 us | 687 KB/s |
| Write (1x512B) | 512B | 3,438 us | 3,444 us | 3,453 us | 148 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,354 us | 2,354 us | 2,356 us | 1,740 KB/s |
| 32 sectors | 16 KB | 7,864 us | 7,864 us | 7,866 us | 2,083 KB/s |
| 64 sectors | 32 KB | 14,901 us | 14,902 us | 14,903 us | 2,198 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 9,689 us | 9,695 us | 9,699 us | 422 KB/s |
| 32 sectors | 16 KB | 15,795 us | 15,799 us | 15,803 us | 1,037 KB/s |
| 64 sectors | 32 KB | 23,169 us | 23,172 us | 23,179 us | 1,414 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 17,095 us | 20,171 us | 47,805 us | 25 KB/s |
| create+write+close | 4 KB | 41,102 us | 44,382 us | 52,573 us | 92 KB/s |
| create+write+close | 32 KB | 178,990 us | 191,793 us | 231,442 us | 170 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 5,553 us | 5,620 us | 6,210 us | 728 KB/s |
| open+read+close | 32 KB | 42,837 us | 42,916 us | 43,513 us | 763 KB/s |
| open+read+close | 128 KB | 171,455 us | 171,614 us | 173,011 us | 763 KB/s |
| open+read+close | 256 KB | 342,498 us | 342,673 us | 344,065 us | 764 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 131 us | 212 us | 941 us | -- |
| File Close | -- | 36 us | 36 us | 36 us | -- |
| Unmount | -- | -- | 0 ms | -- | -- |

**Multi-sector gain:** 64x single=50,248 us vs 1x multi=14,898 us --> **70% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 206.0 ms | **Volume:** NO NAME | **Free:** 7,383 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 895 us | 896 us | 898 us | 571 KB/s |
| Write (1x512B) | 512B | 3,616 us | 3,640 us | 3,802 us | 140 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,488 us | 2,489 us | 2,491 us | 1,645 KB/s |
| 32 sectors | 16 KB | 8,513 us | 8,516 us | 8,521 us | 1,923 KB/s |
| 64 sectors | 32 KB | 16,112 us | 16,113 us | 16,115 us | 2,033 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 9,924 us | 11,056 us | 21,146 us | 370 KB/s |
| 32 sectors | 16 KB | 16,529 us | 16,537 us | 16,547 us | 990 KB/s |
| 64 sectors | 32 KB | 24,575 us | 27,747 us | 35,640 us | 1,180 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 16,524 us | 19,366 us | 29,645 us | 26 KB/s |
| create+write+close | 4 KB | 35,204 us | 43,824 us | 71,988 us | 93 KB/s |
| create+write+close | 32 KB | 199,864 us | 211,096 us | 226,788 us | 155 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 6,172 us | 6,243 us | 6,885 us | 656 KB/s |
| open+read+close | 32 KB | 47,212 us | 47,307 us | 47,947 us | 692 KB/s |
| open+read+close | 128 KB | 188,159 us | 188,363 us | 189,838 us | 695 KB/s |
| open+read+close | 256 KB | 376,726 us | 376,913 us | 378,412 us | 695 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 183 us | 270 us | 1,052 us | -- |
| File Close | -- | 50 us | 50 us | 51 us | -- |
| Unmount | -- | -- | 0 ms | -- | -- |

**Multi-sector gain:** 64x single=57,365 us vs 1x multi=16,114 us --> **71% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 687 | 571 | +20% |
| Raw write 1x (KB/s) | 148 | 140 | +6% |
| Raw read 64x (KB/s) | 2,198 | 2,033 | +8% |
| Raw write 64x (KB/s) | 1,414 | 1,180 | +20% |
| File read 256KB (KB/s) | 764 | 695 | +10% |
| File write 32KB (KB/s) | 170 | 155 | +10% |
| Multi-sector gain | 70% | 71% | -- |

### Notes

- **Genuine SanDisk** - MID $03 confirms authentic SanDisk
- **OID "PT"** - Unusual (not "SD" like most SanDisk cards) - possibly Taiwan production code
- **Made in Taiwan** - Label indicates Taiwan manufacturing
- Product name "SS08G" = SanDisk Standard 8GB
- **SDHC** - High Capacity (8GB class, ~7GB usable)
- **SD 3.0x spec** compliant (SD_SPEC3=1, but SD_SPEC4=0)
- **CMD20 supported** - Speed Class command available (unusual for Class 4)
- **COPY=0** - Original card (not a copy)
- **Properly formatted** - FAT32 ready for immediate use with P2 SD driver
- **(4)** = Speed Class 4 (4 MB/s minimum write speed)
- SanDisk recommended for embedded SPI use
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)
