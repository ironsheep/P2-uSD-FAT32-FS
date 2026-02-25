# Card: SanDisk Extreme 64GB SDXC

**Label:** SanDisk Extreme 64GB U3 A2 microSD XC I V30
**Unique ID:** `SanDisk_SN64G_8.6_7E650771_202211`
**Test Date:** 2026-02-17 (full re-characterization + re-benchmark)

### Card Designator

```
SanDisk SN64G SDXC 59GB [FAT32] SD 6.x rev8.6 SN:$7E65_0771 2022/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### Raw Registers

```
CID: $03 $53 $44 $53 $4E $36 $34 $47 $86 $7E $65 $07 $71 $01 $6B $8D
CSD: $40 $0E $00 $32 $DB $79 $00 $01 $DB $D3 $7F $80 $0A $40 $40 $F9
OCR: $C0FF_8000
SCR: $02 $45 $84 $87 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk / Western Digital | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (ASCII) | [INFO] |
| PNM | [103:64] | $53 $4E $36 $34 $47 | "SN64G" | [INFO] |
| PRV | [63:56] | $86 | 8.6 | [INFO] |
| PSN | [55:24] | $7E65_0771 | 2,120,025,969 | [INFO] |
| MDT | [19:8] | $16B | 2022-11 (November 2022) | [INFO] |
| CRC7 | [7:1] | $46 | $46 | [INFO] |

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
| SD_SECURITY | [54:52] | 4 | SDXC (security v3.xx) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 6.x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1, SD_SPECX=2)

### Filesystem (FAT32 - reformatted with P2FMTER)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-BENCH |
| Volume Serial | $058C_662D |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 15,226 |
| Root Cluster | 2 |
| Total Sectors | 124,727,296 |
| Data Region Start | Sector 30,484 |
| Total Clusters | 1,948,387 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| SD Status | PASS | ACMD13 (64 bytes) — Class 10, U3, A2, V30 |
| MBR Read | PASS | FAT32 LBA ($0C) partition |
| VBR Read | PASS | |
| Format | PASS | FAT32 formatted with P2FMTER |
| Mount | PASS | (confirmed via benchmark) |
| FSCK | PASS | 0 errors, 0 repairs, CLEAN |

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 232.7 ms | **Volume:** P2-BENCH | **Free:** 60,903 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 508 us | 509 us | 513 us | 1,005 KB/s |
| Write (1x512B) | 512B | 1,511 us | 1,545 us | 1,577 us | 331 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 1,973 us | 1,973 us | 1,973 us | 2,076 KB/s |
| 32 sectors | 16 KB | 6,961 us | 6,961 us | 6,961 us | 2,353 KB/s |
| 64 sectors | 32 KB | 13,604 us | 13,604 us | 13,604 us | 2,408 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,457 us | 2,500 us | 2,667 us | 1,638 KB/s |
| 32 sectors | 16 KB | 7,663 us | 7,745 us | 7,869 us | 2,115 KB/s |
| 64 sectors | 32 KB | 15,134 us | 15,236 us | 15,344 us | 2,150 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 7,332 us | 7,720 us | 7,792 us | 66 KB/s |
| create+write+close | 4 KB | 16,321 us | 16,463 us | 16,534 us | 248 KB/s |
| create+write+close | 32 KB | 85,966 us | 86,511 us | 88,303 us | 378 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 4,052 us | 4,099 us | 4,523 us | 999 KB/s |
| open+read+close | 32 KB | 31,329 us | 31,445 us | 31,877 us | 1,042 KB/s |
| open+read+close | 128 KB | 125,851 us | 125,957 us | 126,822 us | 1,040 KB/s |
| open+read+close | 256 KB | 251,805 us | 251,931 us | 252,776 us | 1,040 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 98 us | 145 us | 575 us | -- |
| File Close | -- | 20 us | 20 us | 21 us | -- |
| Unmount | -- | -- | 3 ms | -- | -- |

**Multi-sector gain:** 64x single=32,909 us vs 1x multi=13,613 us --> **58% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 235.0 ms | **Volume:** P2-BENCH | **Free:** 60,903 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 577 us | 577 us | 577 us | 887 KB/s |
| Write (1x512B) | 512B | 1,594 us | 1,620 us | 1,649 us | 316 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,158 us | 2,158 us | 2,158 us | 1,898 KB/s |
| 32 sectors | 16 KB | 7,559 us | 7,559 us | 7,559 us | 2,167 KB/s |
| 64 sectors | 32 KB | 14,754 us | 14,754 us | 14,754 us | 2,220 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,667 us | 2,711 us | 2,880 us | 1,510 KB/s |
| 32 sectors | 16 KB | 8,305 us | 8,385 us | 8,562 us | 1,953 KB/s |
| 64 sectors | 32 KB | 16,437 us | 16,543 us | 16,645 us | 1,980 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 7,796 us | 8,339 us | 8,525 us | 61 KB/s |
| create+write+close | 4 KB | 17,297 us | 17,716 us | 20,345 us | 231 KB/s |
| create+write+close | 32 KB | 90,728 us | 91,246 us | 93,089 us | 359 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 4,547 us | 4,600 us | 5,072 us | 890 KB/s |
| open+read+close | 32 KB | 35,016 us | 35,072 us | 35,540 us | 934 KB/s |
| open+read+close | 128 KB | 139,908 us | 140,055 us | 140,978 us | 935 KB/s |
| open+read+close | 256 KB | 279,774 us | 279,945 us | 280,869 us | 936 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 138 us | 190 us | 662 us | -- |
| File Close | -- | 29 us | 29 us | 29 us | -- |
| Unmount | -- | -- | 3 ms | -- | -- |

**Multi-sector gain:** 64x single=37,089 us vs 1x multi=14,760 us --> **60% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 1,005 | 887 | +13% |
| Raw write 1x (KB/s) | 331 | 316 | +5% |
| Raw read 64x (KB/s) | 2,408 | 2,220 | +8% |
| Raw write 64x (KB/s) | 2,150 | 1,980 | +9% |
| File read 256KB (KB/s) | 1,040 | 936 | +11% |
| File write 32KB (KB/s) | 378 | 359 | +5% |
| Multi-sector gain | 58% | 60% | -- |

### Notes

- **Genuine SanDisk** - MID $03 + OID "SD" = authentic SanDisk/Western Digital product
- **"Extreme"** product line - premium consumer tier
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **A2** = Application Performance Class 2 (4000 read IOPS, 2000 write IOPS) - higher than A1
- **V30** = Video Speed Class 30 (30 MB/s sustained sequential write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- Product name "SN64G" = SanDisk Nomenclature 64GB
- Originally shipped with exFAT, now reformatted with P2FMTER for FAT32
- Volume label "P2-BENCH" indicates use as benchmark/test card
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2) — newest spec generation
- **A2** confirmed by ACMD13 SD Status register (previously known from label only)
- **CMD_SUPPORT $00** — no CMD20 or CMD23 support
- **COPY flag = 1** — may indicate factory content was pre-loaded
- **Full benchmark data** — 350+250 MHz, see tables above and ../Reference/BENCHMARK-RESULTS.md
