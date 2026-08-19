# Card: Sony SR-16UY 16GB SDHC (Taiwan)

**Label:** [`sony-sr-16d-16gb`](CARD-LABELS.md#sony-sr-16d-16gb) — printed text is mastered there, not here
**Disposition:** `retained`
**Unique ID:** `Phison_SD16G_3.0_DA00094B_201610`
**Test Date:** 2026-03-17 (characterization + benchmark)

### Card Designator

```
Phison SD16G SDHC 14GB [FAT32] SD 4.x rev3.0 SN:DA00094B 2016/10
Class 10, U3, V0, SPI 25 MHz
```

### Raw Registers

```
CID: $27 $50 $48 $53 $44 $31 $36 $47 $30 $DA $00 $09 $4B $01 $0A $FF
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $77 $5F $7F $80 $0A $40 $00 $4B
OCR: $C0FF_8000
SCR: $02 $35 $84 $02 $01 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $27 | Phison | **[USED]** |
| OID | [119:104] | $50 $48 | "PH" | [INFO] |
| PNM | [103:64] | $53 $44 $31 $36 $47 | "SD16G" | [INFO] |
| PRV | [63:56] | $30 | 3.0 | [INFO] |
| PSN | [55:24] | $DA00_094B | 3,657,735,499 | [INFO] |
| MDT | [19:8] | $10A | 2016-10 (October 2016) | [INFO] |
| CRC7 | [7:1] | $7F | $7F | [INFO] |

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
| C_SIZE | [69:48] | $775F | 30,559 (15,280 MB) | **[USED]** |
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
| CRC7 | [7:1] | $25 | $25 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 31,293,440
- Capacity: ~14 GB

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
| SD_SPECX | [41:38] | 0 | -- | [INFO] |
| CMD_SUPPORT | [33:32] | $01 | CMD20 Speed Class supported | [INFO] |

**SD Version:** 4.xx (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1)

### ACMD13 SD Status

```
[00-0F]: $00 $00 $00 $00 $02 $00 $00 $00 $02 $02 $90 $00 $08 $05 $00 $00
[10-3F]: all $00
```
- SPEED_CLASS (byte 8): $02 = Class 10
- UHS_SPEED_GRADE (byte 14): $00 = U0 (Note: card label says U3, but ACMD13 reports U0)
- VIDEO_SPEED_CLASS (byte 15): $00 = V0

### Filesystem (FAT32)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | MSWIN4.1 |
| Volume Label | MYPRUSA |
| Volume Serial | $57B6_BDA6 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 554 |
| Number of FATs | 2 |
| Sectors per FAT | 3,819 |
| Root Cluster | 2 |
| Total Sectors | 31,285,248 |
| Total Clusters | 488,704 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | FAT32 LBA partition |
| VBR Read | PASS | Valid FAT32 filesystem |
| Mount | PASS | FAT32 formatted, 15,061 MB free |

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 217.9 ms | **Volume:** MYPRUSA | **Free:** 15,061 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 688 us | 717 us | 951 us | 714 KB/s |
| Write (1x512B) | 512B | 3,094 us | 3,109 us | 3,133 us | 164 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,152 us | 2,159 us | 2,169 us | 1,897 KB/s |
| 32 sectors | 16 KB | 7,807 us | 7,822 us | 7,849 us | 2,094 KB/s |
| 64 sectors | 32 KB | 14,548 us | 14,576 us | 14,788 us | 2,248 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 4,571 us | 4,689 us | 5,132 us | 873 KB/s |
| 32 sectors | 16 KB | 14,771 us | 14,940 us | 15,770 us | 1,096 KB/s |
| 64 sectors | 32 KB | 21,354 us | 21,444 us | 21,488 us | 1,528 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 34,283 us | 35,051 us | 35,249 us | 14 KB/s |
| create+write+close | 4 KB | 56,776 us | 57,070 us | 57,227 us | 71 KB/s |
| create+write+close | 32 KB | 242,080 us | 250,032 us | 265,754 us | 131 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 8,684 us | 8,793 us | 9,447 us | 465 KB/s |
| open+read+close | 32 KB | 57,991 us | 58,158 us | 58,836 us | 563 KB/s |
| open+read+close | 128 KB | 230,457 us | 230,727 us | 232,048 us | 568 KB/s |
| open+read+close | 256 KB | 461,362 us | 515,855 us | 1,002,590 us | 508 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 338 us | 421 us | 1,168 us | -- |
| File Close | -- | 36 us | 36 us | 36 us | -- |
| Unmount | -- | -- | 7 ms | -- | -- |

**Multi-sector gain:** 64x single=59,267 us vs 1x multi=14,526 us --> **75% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 221.9 ms | **Volume:** MYPRUSA | **Free:** 15,061 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 848 us | 883 us | 1,139 us | 579 KB/s |
| Write (1x512B) | 512B | 3,208 us | 3,255 us | 3,289 us | 157 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,434 us | 2,447 us | 2,467 us | 1,673 KB/s |
| 32 sectors | 16 KB | 8,420 us | 8,437 us | 8,455 us | 1,941 KB/s |
| 64 sectors | 32 KB | 15,735 us | 15,772 us | 15,988 us | 2,077 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 4,847 us | 4,927 us | 5,347 us | 831 KB/s |
| 32 sectors | 16 KB | 15,568 us | 15,723 us | 16,551 us | 1,042 KB/s |
| 64 sectors | 32 KB | 22,774 us | 22,842 us | 22,892 us | 1,434 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 39,600 us | 39,739 us | 40,107 us | 12 KB/s |
| create+write+close | 4 KB | 63,814 us | 67,002 us | 81,895 us | 61 KB/s |
| create+write+close | 32 KB | 248,829 us | 256,889 us | 267,894 us | 127 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 9,350 us | 9,459 us | 10,104 us | 433 KB/s |
| open+read+close | 32 KB | 62,137 us | 62,298 us | 63,049 us | 525 KB/s |
| open+read+close | 128 KB | 247,333 us | 247,661 us | 249,122 us | 529 KB/s |
| open+read+close | 256 KB | 493,890 us | 546,128 us | 1,013,064 us | 480 KB/s |
| **Overhead** | | | | | |
| File Open | -- | 473 us | 562 us | 1,356 us | -- |
| File Close | -- | 50 us | 50 us | 51 us | -- |
| Unmount | -- | -- | 7 ms | -- | -- |

**Multi-sector gain:** 64x single=65,067 us vs 1x multi=15,737 us --> **75% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 714 | 579 | +23% |
| Raw write 1x (KB/s) | 164 | 157 | +4% |
| Raw read 64x (KB/s) | 2,248 | 2,077 | +8% |
| Raw write 64x (KB/s) | 1,528 | 1,434 | +7% |
| File read 256KB (KB/s) | 508 | 480 | +6% |
| File write 32KB (KB/s) | 131 | 127 | +3% |
| Multi-sector gain | 75% | 75% | -- |

### Notes

- **Sony-branded, Phison controller** - MID $27 = Phison Electronics, same as PNY cards
- **OID "PH"** - Phison OEM identifier
- **Label says U3** but ACMD13 reports UHS_SPEED_GRADE=U0 — label may refer to bus-mode rating not SPI-mode performance
- **SD 4.xx spec** compliant (SD_SPEC3=1, SD_SPEC4=1)
- **High per-operation latency** - File open averages 421 us (vs ~140-212 us for SanDisk cards)
- **Occasional controller stalls** - 256KB file read Max=1,002 ms (vs ~344 ms for SanDisk SS08G)
- **Phison controllers consistently slow in SPI mode** - this card and PNY SD16G share MID $27 and similar performance characteristics
- **Volume label "MYPRUSA"** - previously used in a Prusa 3D printer
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)
