# Card: Gigastone "Camera Plus" 64GB SDXC

**Label:** [`gigastone-camera-plus-64gb`](CARD-LABELS.md#gigastone-camera-plus-64gb) — printed text is mastered there, not here
**Disposition:** `retained`
**Physical mark:** `violet` — permanent marker, following the same convention as the 32 GB pair (applied 2026-08-19 in green highlighter, re-marked in violet 2026-08-20 after the highlighter proved wipeable). Its unmarked twin is also retained and has no record yet.
**Unique ID:** `GigastoneOEM_ASTC_2.0_00000F14_202306`
**Test Date:** 2026-02-25 (characterization + benchmark)

> ### ROLE: shakedown / diagnostic card - NOT a certification card
>
> This card carries the whole 2026-08-03 to 2026-08-07 root-cause-#3 symptom
> history, which is exactly why the v1.7.0 sprint runs its shakedown sweep on it:
> symptom continuity with the 08-07 baseline table is the point. Scoring that
> sweep is done against
> `DOCs/Agent-Reports/SYMPTOM-MAPPING-2026-08-07-TO-v1.7.0-INSTRUMENT.md`.
>
> **It is not one of the two certification cards.** Release certification uses
> `$0001_B9D5` (Gigastone 7GB, 8 sectors/cluster) and `$3584_1E2E` (Amazon Basics
> 64GB, 64 sectors/cluster) - a pairing chosen for an 8x cluster-size spread. This
> card would add no geometry coverage to that pair and must not be substituted
> into it.
>
> Real-CRC card: `cardWarnings() = $00`.
>
> *Role recorded: 2026-08-09 (v1.7.0 sprint, «#61» §13)*

### Card Designator

```
Gigastone ASTC SDXC 58GB [FAT32] SD 6.x rev2.0 SN:00000F14 2023/06
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

Runs of `SD_card_identify` before 2026-08-09 print this card as **"Unknown ASTC"**
rather than "Gigastone ASTC" - see
`tools/logs/SD_card_identify_260807-155417.log`. That was a gap in the identify
utility's manufacturer table, which had no entry for MID `$12` while
`SD_card_characterize` did. Fixed in the v1.7.0 sprint; older logs still show
the old wording and are correct as recorded.

### Raw Registers

```
CID: $12 $34 $56 $41 $53 $54 $43 $00 $20 $00 $00 $0F $14 $01 $76 $4D
CSD: $40 $0E $00 $32 $5B $59 $00 $01 $D1 $EB $7F $80 $0A $40 $00 $A1
OCR: $C0FF_8000
SCR: $02 $C5 $84 $83 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $12 | Gigastone OEM | **[USED]** |
| OID | [119:104] | $34 $56 | "4V" (ASCII) | [INFO] |
| PNM | [103:64] | $41 $53 $54 $43 $00 | "ASTC" | [INFO] |
| PRV | [63:56] | $20 | 2.0 | [INFO] |
| PSN | [55:24] | $0000_0F14 | 3,860 | [INFO] |
| MDT | [19:8] | $176 | 2023-06 (June 2023) | [INFO] |
| CRC7 | [7:1] | $26 | $26 | [INFO] |

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
| C_SIZE | [69:48] | $1D1EB | 119,275 (59,638 MB) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 127 | Erase sector = 64 KB | [INFO] |
| WP_GRP_SIZE | [38:32] | 0 | — | [INFO] |
| WP_GRP_ENABLE | [31] | 0 | Disabled | [INFO] |
| R2W_FACTOR | [28:26] | 2 | Write = Read × 4 | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | — | [INFO] |
| COPY | [14] | 0 | Original | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $50 | $50 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 122,138,624
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
| DATA_STAT_AFTER_ERASE | [55] | 1 | Data = 1 after erase | [INFO] |
| SD_SECURITY | [54:52] | 4 | SDXC (security v3.xx) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 4.xx (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1)

### Filesystem (FAT32 - formatted with P2FMTER)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-XFER |
| Volume Serial | $0371_6EA1 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 14,909 |
| Root Cluster | 2 |
| Total Sectors | 122,130,432 |
| Data Region Start | Sector 29,850 |
| Total Clusters | 1,907,821 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | FAT32 LBA ($0C) partition |
| VBR Read | PASS | |
| Mount | PASS | |
| Regression | PASS | All tests pass |

### Notes

- **Gigastone** (gigastone.com) - Taiwanese flash memory manufacturer
- MID $12 = Gigastone OEM (Patriot-related OEM in some databases)
- **"Camera Plus"** product line marketed for action cameras and drones
- **XC I** = SDXC UHS-I interface (up to 104 MB/s bus speed)
- **A1** = Application Performance Class 1 (1500 read IOPS, 500 write IOPS)
- **V30** = Video Speed Class 30 (30 MB/s sustained sequential write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write speed)
- **SD 4.xx spec** compliant (SD_SPEC4=1)
- CCC $5B5 - standard command classes (no video class bits despite V30 marketing)
- DATA_STAT_AFTER_ERASE=1 (erased data reads as 1s)
- Formatted with P2FMTER (P2 Flash Filesystem Formatter)
- Currently used as scratch/test card for development
- **Benchmark data available** — see Benchmark Results section below for detailed throughput measurements (raw, multi-sector, and file-level)

### SPI Speed Characterization

**Test Date:** 2026-02-02
**Test Configuration:**
- SYSCLK: 200 MHz
- Phase 1: 1,000 single-sector reads (quick check)
- Phase 2: 10,000 single-sector reads (statistical confidence)
- Phase 3: 100 × 8-sector multi-block reads (800 sectors, sustained transfer)
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
| 27 MHz | 4 clocks | 25.0 MHz | -7.4% | timeout* | — | — | **100%** |

*At 27 MHz, CMD6 High Speed switch failed; card became unresponsive during Phase 1.

**Summary:**
- **Maximum Reliable Speed: 25 MHz** (47,200 total sector reads at 0% failure rate)
- CMD6 High Speed mode: Switch **failed** at 27 MHz, card became unresponsive

### Internal Throughput (measured at 25 MHz SPI)

| Metric | Value |
|--------|-------|
| Phase 2 Duration (10,000 reads) | 5.42 seconds |
| Throughput | **944 KB/s** |
| Sectors/second | 1,845 |
| Latency per sector | 0.54 ms |

**Performance Class:** HIGH - Fastest card tested so far (21% faster than SanDisk Nintendo Switch).

### Benchmark Results — Standard Protocol (350/250 MHz, 25 MHz SPI)

**Test Date:** 2026-02-25
**Test Program**: SD_performance_benchmark.spin2 v2.0
**Driver Commit**: d62e30d
**Benchmark Protocol**: Both runs use 25 MHz SPI clock — isolates Spin2 overhead effect from SPI bus speed.

#### 350 MHz Run

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 201.9 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 507 | 559 | 1,027 | **915** |
| Write 1x512B | 1,084 | 1,465 | 3,908 | **349** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,149 | 2,194 | 2,598 | **1,866** |
| Read 32 sectors (16 KB) | 7,781 | 7,826 | 8,238 | **2,093** |
| Read 64 sectors (32 KB) | 15,303 | 15,351 | 15,778 | **2,134** |
| Write 8 sectors (4 KB) | 2,726 | 2,786 | 3,019 | **1,470** |
| Write 32 sectors (16 KB) | 7,757 | 7,984 | 9,666 | **2,052** |
| Write 64 sectors (32 KB) | 15,022 | 15,292 | 17,045 | **2,142** |
| **File-Level** | | | | |
| File Write 512B | 8,622 | 9,251 | 11,438 | **55** |
| File Write 4 KB | 16,291 | 22,331 | 56,819 | **183** |
| File Write 32 KB | 85,889 | 111,780 | 127,679 | **293** |
| File Read 4 KB | 3,949 | 4,048 | 4,912 | **1,011** |
| File Read 32 KB | 30,137 | 30,230 | 31,032 | **1,083** |
| File Read 128 KB | 119,955 | 120,140 | 121,721 | **1,090** |
| File Read 256 KB | 239,994 | 240,169 | 241,617 | **1,091** |
| **Overhead** | | | | |
| File Open | 138 | 233 | 1,092 | — |
| File Close | 35 | 35 | 36 | — |
| Mount | — | 201,900 | — | — |

Multi-sector improvement: 64x single reads = 32,594 us vs 1x CMD18 = 15,304 us (**53% faster**)

#### 250 MHz Run

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 203.9 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 574 | 624 | 1,074 | **820** |
| Write 1x512B | 1,159 | 1,558 | 3,967 | **328** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,408 | 2,450 | 2,833 | **1,671** |
| Read 32 sectors (16 KB) | 8,693 | 8,736 | 9,124 | **1,875** |
| Read 64 sectors (32 KB) | 17,092 | 17,136 | 17,536 | **1,912** |
| Write 8 sectors (4 KB) | 2,939 | 2,998 | 3,207 | **1,366** |
| Write 32 sectors (16 KB) | 8,545 | 8,794 | 10,452 | **1,863** |
| Write 64 sectors (32 KB) | 16,548 | 16,810 | 18,444 | **1,949** |
| **File-Level** | | | | |
| File Write 512B | 9,079 | 13,563 | 47,302 | **37** |
| File Write 4 KB | 17,135 | 22,803 | 58,363 | **179** |
| File Write 32 KB | 90,120 | 115,998 | 128,544 | **282** |
| File Read 4 KB | 4,463 | 4,570 | 5,477 | **896** |
| File Read 32 KB | 33,620 | 33,727 | 34,578 | **971** |
| File Read 128 KB | 133,737 | 133,954 | 135,554 | **978** |
| File Read 256 KB | 267,714 | 267,959 | 269,519 | **978** |
| **Overhead** | | | | |
| File Open | 193 | 291 | 1,177 | — |
| File Close | 49 | 49 | 50 | — |
| Mount | — | 203,900 | — | — |

Multi-sector improvement: 64x single reads = 37,142 us vs 1x CMD18 = 17,092 us (**53% faster**)

#### Sysclk Effect (350 vs 250 MHz at same 25 MHz SPI)

Both runs use identical 25 MHz SPI clock — differences are purely Spin2 inter-transfer overhead.

| Test | 350 MHz (KB/s) | 250 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 915 | 820 | +12% |
| Raw Read 64x (32 KB) | 2,134 | 1,912 | +12% |
| Raw Write 64x (32 KB) | 2,142 | 1,949 | +10% |
| File Read 256 KB | 1,091 | 978 | +12% |
| File Write 32 KB | 293 | 282 | +4% |

**Note:** Consistent 10-12% improvement across raw operations from faster Spin2 processing. File write shows smaller delta (4%) as card-internal write stall variance dominates.
