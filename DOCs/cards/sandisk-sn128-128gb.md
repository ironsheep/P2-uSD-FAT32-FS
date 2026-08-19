# Card: SanDisk Nintendo Switch 128GB SDXC

**Label:** [`sandisk-nintendo-switch-128gb`](CARD-LABELS.md#sandisk-nintendo-switch-128gb) — printed text is mastered there, not here
**Unique ID:** `SanDisk_SN128_8.0_F79E34F6_201912`
**Test Date:** 2026-02-17 (full re-characterization)

### Card Designator

```
SanDisk SN128 SDXC 119GB [FAT32] SD 6.x rev8.0 SN:F79E34F6 2019/12
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### Raw Registers

```
CID: $03 $53 $44 $53 $4E $31 $32 $38 $80 $F7 $9E $34 $F6 $01 $3C $63
CSD: $40 $0E $00 $32 $DB $79 $00 $03 $B8 $AB $7F $80 $0A $40 $40 $5F
OCR: $C0FF_8000
SCR: $02 $45 $84 $87 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (SanDisk) | [INFO] |
| PNM | [103:64] | $53 $4E $31 $32 $38 | "SN128" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $F79E_34F6 | 4,154,373,366 | [INFO] |
| MDT | [19:8] | $13C | 2019-12 (December 2019) | [INFO] |
| CRC7 | [7:1] | $31 | $31 | [INFO] |

### CSD Register (Card Specific Data) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| CSD_STRUCTURE | [127:126] | 1 | CSD Version 2.0 (SDHC/SDXC) | **[USED]** |
| TAAC | [119:112] | $0E | Read access time-1 | **[USED]** |
| NSAC | [111:104] | $00 | 0 CLK cycles | **[USED]** |
| TRAN_SPEED | [103:96] | $32 | 25 MHz max | **[USED]** |
| CCC | [95:84] | $DB7 | Classes 0,1,2,4,5,7,8,10,11 | [INFO] |
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
| CRC7 | [7:1] | $2F | $2F | [INFO] |

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
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 6.x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1, SD_SPECX=2)

### Filesystem (FAT32 - formatted with P2FMTER)

| Field | Value |
|-------|-------|
| Factory Format | exFAT ($07) - reformatted to FAT32 |
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-BENCH |
| Volume Serial | $04C0_F423 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 30,485 |
| Root Cluster | 2 |
| Total Sectors | 249,729,024 |
| Data Region Start | Sector 61,002 |
| Total Clusters | 3,901,062 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| SD Status | PASS | ACMD13 (64 bytes) — Class 10, U3, A2, V30 |
| MBR Read | PASS | FAT32 partition ($0C) |
| Format | PASS | FAT32 formatted with P2FMTER |
| Mount | PASS | (confirmed via benchmark) |
| FSCK | PASS | 0 errors, 0 repairs, CLEAN |

### Notes

- **Genuine SanDisk** - MID $03 + OID "SD" confirms authentic SanDisk/Western Digital
- **Nintendo Switch Edition** = Officially licensed Nintendo-branded SanDisk card
- Product name "SN128" = SanDisk Nintendo Switch 128GB
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **CCC $DB7** includes Class 1 (stream read) and Class 11 (video speed class) - video-optimized
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2) — newest spec generation
- **A2** = Application Performance Class 2 (confirmed by ACMD13 SD Status register)
- **CMD_SUPPORT $00** — no CMD20 or CMD23 support
- **COPY flag = 1** — unusual, may indicate content was pre-loaded at factory
- Features Nintendo mushroom (Super Mario) branding on label
- Designed for Nintendo Switch gaming console storage expansion
- Factory formatted with exFAT — reformatted to FAT32 with P2FMTER
- Second SanDisk 128GB card in catalog with different product name (SN128 vs AGGCF)
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)

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
| 27 MHz | 4 clocks | 25.0 MHz | -7.4% | 0 OK, 1,000 timeout | — | — | **100%** |

**Summary:**
- **Maximum Reliable Speed: 25 MHz** (47,200 total sector reads at 0% failure rate)
- CMD6 High Speed mode: Supported (detected) but **switch failed**
- Failure mode at 27 MHz: After failed CMD6 switch attempt, card became completely unresponsive (all 1,000 reads timed out)
- At SYSCLK=200 MHz with minimum half_period=4 clocks, 25 MHz is the hardware maximum achievable SPI clock

**Recommendation:** Use 25 MHz SPI clock for this card (matches TRAN_SPEED register value $32 = 25 MHz).

### Internal Throughput (measured at 25 MHz SPI)

| Metric | Value |
|--------|-------|
| Phase 2 Duration (10,000 reads) | 6.56 seconds |
| Throughput | **780 KB/s** |
| Sectors/second | 1,524 |
| Latency per sector | 0.66 ms |

**Performance Class:** HIGH - Fast internal controller, suitable for demanding applications.

### Benchmark Results (Smart Pin SPI + Multi-Sector)

**Test Program**: SD_performance_benchmark.spin2 v2.0

#### 350 MHz Run (2026-02-17)

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 233.3 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 516 | 577 | 623 | **887** |
| Write 1x512B | 1,511 | 1,542 | 1,578 | **332** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 1,983 | 2,591 | 2,713 | **1,580** |
| Read 32 sectors (16 KB) | 6,967 | 7,033 | 7,133 | **2,329** |
| Read 64 sectors (32 KB) | 13,617 | 13,617 | 13,618 | **2,406** |
| Write 8 sectors (4 KB) | 2,422 | 2,782 | 5,151 | **1,472** |
| Write 32 sectors (16 KB) | 7,653 | 7,736 | 7,948 | **2,117** |
| Write 64 sectors (32 KB) | 15,113 | 15,220 | 15,437 | **2,152** |
| **File-Level** | | | | |
| File Write 512B | 7,328 | 7,753 | 7,873 | **66** |
| File Write 4 KB | 16,341 | 16,488 | 16,724 | **248** |
| File Write 32 KB | 86,039 | 86,582 | 87,658 | **378** |
| File Read 4 KB | 4,231 | 4,279 | 4,704 | **957** |
| File Read 32 KB | 32,002 | 32,067 | 32,488 | **1,021** |
| File Read 128 KB | 129,030 | 129,145 | 130,028 | **1,014** |
| File Read 256 KB | 257,782 | 257,893 | 258,743 | **1,016** |
| **Overhead** | | | | |
| File Open | 98 | 146 | 584 | — |
| File Close | 20 | 20 | 21 | — |
| Mount | — | 233,300 | — | — |

Multi-sector improvement: 64x single reads = 35,939 us vs 1x CMD18 = 13,711 us (**61% faster**)

#### 250 MHz Run (2026-02-17)

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 235.7 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 604 | 604 | 604 | **847** |
| Write 1x512B | 1,557 | 1,620 | 2,052 | **316** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,152 | 2,152 | 2,153 | **1,903** |
| Read 32 sectors (16 KB) | 7,546 | 7,546 | 7,546 | **2,171** |
| Read 64 sectors (32 KB) | 14,743 | 14,743 | 14,743 | **2,222** |
| Write 8 sectors (4 KB) | 2,605 | 2,701 | 2,917 | **1,516** |
| Write 32 sectors (16 KB) | 8,342 | 8,416 | 8,631 | **1,946** |
| Write 64 sectors (32 KB) | 16,652 | 16,987 | 19,185 | **1,929** |
| **File-Level** | | | | |
| File Write 512B | 7,735 | 8,197 | 8,298 | **62** |
| File Write 4 KB | 17,140 | 17,303 | 17,587 | **236** |
| File Write 32 KB | 89,851 | 90,572 | 92,436 | **361** |
| File Read 4 KB | 4,625 | 4,678 | 5,162 | **875** |
| File Read 32 KB | 35,713 | 35,785 | 36,269 | **915** |
| File Read 128 KB | 142,513 | 142,643 | 143,622 | **918** |
| File Read 256 KB | 284,960 | 285,103 | 286,069 | **919** |
| **Overhead** | | | | |
| File Open | 137 | 189 | 662 | — |
| File Close | 29 | 29 | 29 | — |
| Mount | — | 235,700 | — | — |

Multi-sector improvement: 64x single reads = 39,689 us vs 1x CMD18 = 14,804 us (**62% faster**)

#### Sysclk Effect (350 MHz vs 250 MHz)

SPI clock is identical (25,000 kHz) at both speeds. Differences show Spin2 inter-transfer overhead.

| Metric | 350 MHz | 250 MHz | Overhead (us) | Overhead % |
|--------|---------|---------|---------------|------------|
| Raw Read 1x512B | 577 us | 604 us | +27 | +5% |
| Raw Write 1x512B | 1,542 us | 1,620 us | +78 | +5% |
| Raw Read 64x (32 KB) | 13,617 us | 14,743 us | +1,126 | +8% |
| Raw Write 64x (32 KB) | 15,220 us | 16,987 us | +1,767 | +12% |
| File Read 256 KB | 257,893 us | 285,103 us | +27,210 | +11% |
| File Write 32 KB | 86,582 us | 90,572 us | +3,990 | +5% |
| File Open | 146 us | 189 us | +43 | +29% |
