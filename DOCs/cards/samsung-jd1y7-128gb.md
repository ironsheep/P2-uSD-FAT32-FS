# Card: Samsung PRO Endurance 128GB SDXC

**Label:** [`samsung-pro-endurance-128gb`](CARD-LABELS.md#samsung-pro-endurance-128gb) — printed text is mastered there, not here
**Disposition:** `retained`
**Unique ID:** `Samsung_JD1Y7_3.0_D27654A6_202512`
**Test Date:** 2026-02-17 (initial characterization)

### Card Designator

```
Samsung JD1Y7 SDXC 119GB [FAT32] SD 6.x rev3.0 SN:D27654A6 2025/12
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### Raw Registers

```
CID: $1B $53 $4D $4A $44 $31 $59 $37 $30 $D2 $76 $54 $A6 $A1 $9C $BD
CSD: $40 $0E $00 $32 $DB $79 $00 $03 $BA $FF $7F $80 $0A $40 $00 $2D
OCR: $C0FF_8000
SCR: $02 $05 $84 $87 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $1B | Samsung | **[USED]** |
| OID | [119:104] | $53 $4D | "SM" (ASCII) | [INFO] |
| PNM | [103:64] | $4A $44 $31 $59 $37 | "JD1Y7" | [INFO] |
| PRV | [63:56] | $30 | 3.0 | [INFO] |
| PSN | [55:24] | $D276_54A6 | 3,530,073,254 | [INFO] |
| MDT | [19:8] | $19C | 2025-12 (December 2025) | [INFO] |
| CRC7 | [7:1] | $5E | $5E | [INFO] |

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
| C_SIZE | [69:48] | $3BAFF | 244,479 (122,240 MB) | **[USED]** |
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
| CRC7 | [7:1] | $16 | $16 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 250,347,520
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
| SD_SECURITY | [54:52] | 0 | No security | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 6.x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1, SD_SPECX=2)

### Filesystem (FAT32 - reformatted with P2FMTER)

*Originally shipped as exFAT ($07). Reformatted to FAT32 by P2 format utility.*

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-BENCH |
| Volume Serial | TBD |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 30,559 |
| Root Cluster | 2 |
| Total Sectors | 250,347,520 |
| Data Region Start | Sector 69,342 |
| Total Clusters | 3,910,596 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| SD Status | PASS | ACMD13 (64 bytes) — Class 10, U3, A2, V30 |
| MBR Read | PASS | exFAT ($07) partition — needs FAT32 format |
| VBR Read | — | Skipped (exFAT) |
| Format | PASS | FAT32 formatted with P2FMTER |
| Mount | PASS | (confirmed via benchmark) |
| FSCK | PASS | 0 errors, 0 repairs, CLEAN |

### Performance Benchmarks (350 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 243.2 ms | **Volume:** P2-BENCH | **Free:** 122,235 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 389 us | 399 us | 492 us | 1,283 KB/s |
| Write (1x512B) | 512B | 829 us | 829 us | 833 us | 617 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 1,843 us | 1,853 us | 1,951 us | 2,210 KB/s |
| 32 sectors | 16 KB | 6,832 us | 6,841 us | 6,930 us | 2,394 KB/s |
| 64 sectors | 32 KB | 13,486 us | 13,496 us | 13,585 us | 2,427 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,027 us | 2,042 us | 2,056 us | 2,005 KB/s |
| 32 sectors | 16 KB | 7,046 us | 7,286 us | 8,971 us | 2,248 KB/s |
| 64 sectors | 32 KB | 13,932 us | 14,126 us | 15,879 us | 2,319 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 4,316 us | 4,673 us | 4,789 us | 109 KB/s |
| create+write+close | 4 KB | 8,869 us | 9,100 us | 9,407 us | 450 KB/s |
| create+write+close | 32 KB | 42,216 us | 43,220 us | 45,498 us | 758 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 3,019 us | 3,064 us | 3,472 us | 1,336 KB/s |
| open+read+close | 32 KB | 23,182 us | 23,227 us | 23,635 us | 1,410 KB/s |
| open+read+close | 128 KB | 92,333 us | 92,412 us | 93,132 us | 1,418 KB/s |
| open+read+close | 256 KB | 184,534 us | 184,613 us | 185,333 us | 1,419 KB/s |
| **Overhead** | | | | | |
| File Open | — | 98 us | 143 us | 551 us | — |
| File Close | — | 20 us | 20 us | 21 us | — |
| Unmount | — | — | 1 ms | — | — |

**Multi-sector gain:** 64x single=25,277 us vs 1x multi=13,473 us → **46% improvement**

### Performance Benchmarks (250 MHz sysclk)

**SPI Clock:** 25,000 kHz | **Mount:** 245.5 ms | **Volume:** P2-BENCH | **Free:** 122,235 MB

| Test | Size | Min | Avg | Max | Throughput |
|------|------|-----|-----|-----|------------|
| **Raw Single-Sector** | | | | | |
| Read (1x512B) | 512B | 467 us | 478 us | 572 us | 1,071 KB/s |
| Write (1x512B) | 512B | 887 us | 887 us | 887 us | 577 KB/s |
| **Raw Multi-Sector Read (CMD18)** | | | | | |
| 8 sectors | 4 KB | 2,028 us | 2,038 us | 2,133 us | 2,009 KB/s |
| 32 sectors | 16 KB | 7,428 us | 7,442 us | 7,526 us | 2,201 KB/s |
| 64 sectors | 32 KB | 14,625 us | 14,634 us | 14,723 us | 2,239 KB/s |
| **Raw Multi-Sector Write (CMD25)** | | | | | |
| 8 sectors | 4 KB | 2,218 us | 2,397 us | 3,894 us | 1,708 KB/s |
| 32 sectors | 16 KB | 7,678 us | 7,732 us | 7,787 us | 2,118 KB/s |
| 64 sectors | 32 KB | 15,065 us | 15,540 us | 17,098 us | 2,108 KB/s |
| **File Write** | | | | | |
| create+write+close | 512B | 4,544 us | 4,929 us | 4,972 us | 103 KB/s |
| create+write+close | 4 KB | 9,394 us | 9,437 us | 9,513 us | 434 KB/s |
| create+write+close | 32 KB | 45,085 us | 46,196 us | 48,197 us | 709 KB/s |
| **File Read** | | | | | |
| open+read+close | 4 KB | 3,514 us | 3,564 us | 4,018 us | 1,149 KB/s |
| open+read+close | 32 KB | 26,756 us | 26,806 us | 27,260 us | 1,222 KB/s |
| open+read+close | 128 KB | 106,473 us | 106,563 us | 107,373 us | 1,229 KB/s |
| open+read+close | 256 KB | 212,762 us | 212,852 us | 213,662 us | 1,231 KB/s |
| **Overhead** | | | | | |
| File Open | — | 137 us | 187 us | 641 us | — |
| File Close | — | 29 us | 29 us | 29 us | — |
| Unmount | — | — | 1 ms | — | — |

**Multi-sector gain:** 64x single=29,488 us vs 1x multi=14,612 us → **50% improvement**

### Sysclk Effect (350 vs 250 MHz, same 25 MHz SPI)

| Metric | 350 MHz | 250 MHz | Delta |
|--------|---------|---------|-------|
| Raw read 1x (KB/s) | 1,283 | 1,071 | +20% |
| Raw read 64x (KB/s) | 2,427 | 2,239 | +8% |
| Raw write 64x (KB/s) | 2,319 | 2,108 | +10% |
| File read 256KB (KB/s) | 1,419 | 1,231 | +15% |
| File write 32KB (KB/s) | 758 | 709 | +7% |
| Multi-sector gain | 46% | 50% | — |

### Notes

- **Genuine Samsung** - MID $1B + OID "SM" = authentic Samsung product
- **"PRO Endurance"** product line - designed for surveillance/dashcam use (high write endurance)
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **A2** = Application Performance Class 2 (4000 read IOPS, 2000 write IOPS) — confirmed via ACMD13
- **V30** = Video Speed Class 30 (30 MB/s sustained sequential write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- Product name "JD1Y7" = Samsung internal product code
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2) — newest spec generation
- **SD_SECURITY = 0** — unlike most Samsung cards, no CPRM security
- **CMD_SUPPORT $00** — no CMD20 or CMD23 support
- **COPY flag = 0** — original (no factory pre-loaded content)
- Originally shipped with exFAT, reformatted with P2FMTER for FAT32
- **CCC $DB7** = same command class set as Rating A cards (includes Class 10 switch)
- Second Samsung card in collection (first: GD4QT EVO Select, SD 3.x)
- **Newer Samsung silicon** — SD 6.x vs GD4QT's SD 3.x; manufactured Dec 2025
- **Exceptional performance** — best or near-best in every benchmark category:
  - Best file write: 758 KB/s (23% ahead of previous best Lexar Blue 616 KB/s)
  - Best single-sector read: 1,283 KB/s (beats Lexar V30's 1,239 KB/s)
  - Best raw write 64x: 2,319 KB/s (beats Lexar Blue's 2,275 KB/s)
  - Near-best file read: 1,419 KB/s (close to Lexar Blue's 1,444 KB/s)
- **Low multi-sector gain (46%)** — because single-sector performance is already fast (fast internal controller), batching provides less relative improvement
- **Full benchmark data** — 350+250 MHz, see tables above and ../Reference/BENCHMARK-RESULTS.md
