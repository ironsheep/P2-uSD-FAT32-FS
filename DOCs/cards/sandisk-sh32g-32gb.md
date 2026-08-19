# Card: SanDisk MAX Endurance 32GB SDHC

**Label:** [`sandisk-max-endurance-32gb`](CARD-LABELS.md#sandisk-max-endurance-32gb) — printed text is mastered there, not here
**Unique ID:** `SanDisk_SH32G_8.0_5BFECCD8_202508`
**Test Date:** 2026-02-18

### Card Designator

```
SanDisk SH32G SDHC 29GB [FAT32] SD 6.x rev8.0 SN:$5BFE_CCD8 2025/08
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### Raw Registers

```
CID: $03 $53 $44 $53 $48 $33 $32 $47 $80 $5B $FE $CC $D8 $01 $98 $79
CSD: $40 $0E $00 $32 $DB $79 $00 $00 $ED $C8 $7F $80 $0A $40 $40 $E5
OCR: $C0FF_8000
SCR: $02 $35 $84 $87 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk / Western Digital | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (ASCII) | [INFO] |
| PNM | [103:64] | $53 $48 $33 $32 $47 | "SH32G" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $5BFE_CCD8 | 1,543,425,240 | [INFO] |
| MDT | [19:8] | $198 | 2025-08 (August 2025) | [INFO] |
| CRC7 | [7:1] | $3C | $3C | [INFO] |

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
| C_SIZE | [69:48] | $EDC8 | 60,872 (30,436 MB) | **[USED]** |
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
| CRC7 | [7:1] | $72 | $72 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 62,332,928
- Capacity: ~29 GB

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
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 6.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 6.x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1, SD_SPECX=2)

### Filesystem (FAT32 - factory format)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | (blank) |
| Volume Label | NO NAME |
| Volume Serial | $3864_6363 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 1,170 |
| Number of FATs | 2 |
| Sectors per FAT | 7,607 |
| Root Cluster | 2 |
| Total Sectors | 62,325,760 |
| Data Region Start | Sector 16,384 |
| Total Clusters | 973,584 |

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
| VBR Read | PASS | Factory FAT32 format |
| FSCK | PASS | 0 errors, 1 repair (FSInfo free count was $FFFFFFFF → 973,583), REPAIRED |
| Format | PASS | FAT32 formatted with P2FMTER (via regression test) |
| Mount | PASS | (confirmed via benchmark) |
| **Regression** | **236/236** | mount(21), file_ops(22), read_write(29), directory(28), seek(37), multicog(14), multihandle(19), multiblock(6), raw_sector(14), format(46) |

### SPI Speed Characterization

**SYSCLK:** 200 MHz | **Test:** 11,800 reads per speed level (1K + 10K + 800 multi-block)

| Target SPI | Actual SPI | HalfPer | Phase 1 (1K) | Phase 2 (10K) | Phase 3 (800) | Result |
|------------|------------|---------|--------------|----------------|----------------|--------|
| 18 MHz | 16.6 MHz | 6 | PASS | PASS | PASS | **PASS** |
| 20 MHz | 20.0 MHz | 5 | PASS | PASS | PASS | **PASS** |
| 22 MHz | 20.0 MHz | 5 | PASS | PASS | PASS | **PASS** |
| 25 MHz | 25.0 MHz | 4 | PASS | PASS | PASS | **PASS** |
| 27 MHz | 25.0 MHz | 4 | FAIL (0/1000 timeout) | — | — | **FAIL** |

**Maximum Reliable SPI:** 25 MHz
**CMD6 High Speed:** Failed (card unresponsive after switch attempt — typical SanDisk behavior)

**Internal Throughput at 25 MHz:** ~951 KB/s (10,000 single-sector reads in ~5.25s)

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 232.9 ms | **Volume:** NO NAME | **Free:** 30,427 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 513 us | 513 us | 513 us | 998 KB/s |
| Write (1x512B) | 512B | 1,523 us | 1,551 us | 1,580 us | 330 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 1,977 us | 1,977 us | 1,977 us | 2,071 KB/s |
| 32 sectors | 16 KB | 6,966 us | 6,966 us | 6,966 us | 2,351 KB/s |
| 64 sectors | 32 KB | 13,608 us | 13,608 us | 13,609 us | 2,407 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,493 us | 2,591 us | 2,793 us | 1,580 KB/s |
| 32 sectors | 16 KB | 7,666 us | 8,041 us | 10,948 us | 2,037 KB/s |
| 64 sectors | 32 KB | 15,195 us | 15,211 us | 15,224 us | 2,154 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 7,245 us | 7,582 us | 7,654 us | 67 KB/s |
| create+write+close | 4 KB | 16,615 us | 16,642 us | 16,671 us | 246 KB/s |
| create+write+close | 32 KB | 87,932 us | 89,088 us | 91,085 us | 367 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 4,101 us | 4,149 us | 4,581 us | 987 KB/s |
| open+read+close | 32 KB | 31,581 us | 31,633 us | 32,053 us | 1,035 KB/s |
| open+read+close | 128 KB | 126,134 us | 126,264 us | 127,151 us | 1,038 KB/s |
| open+read+close | 256 KB | 252,880 us | 253,016 us | 253,887 us | 1,036 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 93 us | 140 us | 569 us | -- |
| File Close | -- | 20 us | 20 us | 21 us | -- |
| Unmount | -- | -- | 2 ms | -- | -- |

**Multi-sector gain:** 64x single=33,144 us vs 1x multi=13,613 us --> **58% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 235.0 ms | **Volume:** NO NAME | **Free:** 30,427 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 577 us | 577 us | 583 us | 887 KB/s |
| Write (1x512B) | 512B | 1,576 us | 1,606 us | 1,638 us | 318 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,164 us | 2,164 us | 2,165 us | 1,892 KB/s |
| 32 sectors | 16 KB | 7,565 us | 7,565 us | 7,566 us | 2,165 KB/s |
| 64 sectors | 32 KB | 14,754 us | 14,754 us | 14,754 us | 2,220 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,672 us | 2,795 us | 3,205 us | 1,465 KB/s |
| 32 sectors | 16 KB | 8,399 us | 8,795 us | 11,425 us | 1,862 KB/s |
| 64 sectors | 32 KB | 16,574 us | 16,672 us | 16,776 us | 1,965 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 7,559 us | 8,105 us | 8,290 us | 63 KB/s |
| create+write+close | 4 KB | 17,419 us | 17,542 us | 17,638 us | 233 KB/s |
| create+write+close | 32 KB | 92,077 us | 92,718 us | 94,910 us | 353 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 4,614 us | 4,667 us | 5,139 us | 877 KB/s |
| open+read+close | 32 KB | 35,009 us | 35,070 us | 35,538 us | 934 KB/s |
| open+read+close | 128 KB | 140,368 us | 140,507 us | 141,451 us | 932 KB/s |
| open+read+close | 256 KB | 281,850 us | 281,974 us | 282,883 us | 929 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 130 us | 183 us | 661 us | -- |
| File Close | -- | 29 us | 29 us | 29 us | -- |
| Unmount | -- | -- | 3 ms | -- | -- |

**Multi-sector gain:** 64x single=37,226 us vs 1x multi=14,760 us --> **60% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 998 | 887 | +13% |
| Raw write 1x (KB/s) | 330 | 318 | +4% |
| Raw read 64x (KB/s) | 2,407 | 2,220 | +8% |
| Raw write 64x (KB/s) | 2,154 | 1,965 | +10% |
| File read 256KB (KB/s) | 1,036 | 929 | +12% |
| File write 32KB (KB/s) | 367 | 353 | +4% |
| Multi-sector gain | 58% | 60% | -- |

### Notes

- **Genuine SanDisk** - MID $03 + OID "SD" = authentic SanDisk/Western Digital product
- **"MAX Endurance"** product line - designed for continuous recording (dashcams, security cameras)
- **HC I** = SDHC UHS-I interface (up to 104 MB/s bus speed)
- **V30** = Video Speed Class 30 (30 MB/s sustained sequential write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- **Class 10** = Speed Class 10 (10 MB/s minimum write speed)
- **A2** = Application Performance Class 2 (confirmed by ACMD13 SD Status)
- Product name "SH32G" = SanDisk High-endurance 32GB
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2)
- **Factory FAT32 formatted** with 64 sectors/cluster (32KB clusters) — same cluster size as P2FMTER
- **COPY flag = 1** — may indicate factory content was pre-loaded
- Manufactured August 2025
