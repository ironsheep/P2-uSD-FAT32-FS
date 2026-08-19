# Card: SanDisk Industrial 16GB SDHC

**Label:** [`sandisk-industrial-16gb`](CARD-LABELS.md#sandisk-industrial-16gb) — printed text is mastered there, not here
**Disposition:** `retained`
**Unique ID:** `SanDisk_SA16G_8.0_93E9C0A1_202511`
**Test Date:** 2026-02-25 (characterization + speed characterization + benchmark)

### Card Designator

```
SanDisk SA16G SDHC 14GB [FAT32] SD 5.x rev8.0 SN:93E9C0A1 2025/11
Class 10, U1, V10, SPI 25 MHz
```

### Raw Registers

```
CID: $03 $53 $44 $53 $41 $31 $36 $47 $80 $93 $E9 $C0 $A1 $01 $9B $59
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $76 $B2 $7F $80 $0A $40 $40 $13
OCR: $C0FF_8000
SCR: $02 $35 $84 $43 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (ASCII) | [INFO] |
| PNM | [103:64] | $53 $41 $31 $36 $47 | "SA16G" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $93E9_C0A1 | 2,481,291,425 | [INFO] |
| MDT | [19:8] | $19B | 2025-11 (November 2025) | [INFO] |
| CRC7 | [7:1] | $2C | $2C | [INFO] |

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
| C_SIZE | [69:48] | $76B2 | 30,386 (15,193 MB) | **[USED]** |
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
| CRC7 | [7:1] | $09 | $09 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 31,115,264
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
| SD_SPECX | [41:38] | 1 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 4.xx (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1)

### Filesystem (FAT32)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | (blank) |
| Volume Label | NO NAME |
| Volume Serial | $3161_3063 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 598 |
| Number of FATs | 2 |
| Sectors per FAT | 3,797 |
| Root Cluster | 2 |
| Total Sectors | 31,108,096 |
| Total Clusters | 485,936 |

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

### Notes

- **SanDisk Industrial** - designed for embedded and industrial applications
- MID $03 = SanDisk / Western Digital (standard, not PNY-limited)
- **"SA16G"** product name - Industrial product line
- **HC I** = SDHC UHS-I interface
- **U1** = UHS Speed Class 1 (10 MB/s minimum write speed)
- **C10** = Speed Class 10 (10 MB/s minimum write speed)
- **SD 4.xx spec** compliant (SD_SPEC4=1, SD_SPECX=1)
- CCC $5B5 - standard command classes including Class 10 (switch)
- **COPY=1** - indicates card contents were copied during manufacturing
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)
- Card arrived pre-formatted as FAT32 with 64 sectors/cluster (32 KB clusters)
- OEM name blank, volume label "NO NAME" - factory default format
- Industrial cards are recommended for embedded SPI use due to wider temperature range and longer endurance
- **Benchmark data available** -- see Benchmark Results section below for detailed throughput measurements at 350 and 250 MHz sysclk (both at 25 MHz SPI)

### SPI Speed Characterization

**Test Date:** 2026-02-07
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
| 27 MHz | 4 clocks | 25.0 MHz | -7.4% | timeout* | — | — | **100%** |

*At 27 MHz, CMD6 High Speed switch failed; card became unresponsive during Phase 1.

**Summary:**
- **Maximum Reliable Speed: 25 MHz** (47,200 total sector reads at 0% failure rate)
- CMD6 High Speed mode: Switch **failed** at 27 MHz, card became unresponsive

### Internal Throughput (measured at 25 MHz SPI)

| Metric | Value |
|--------|-------|
| Phase 2 Duration (10,000 reads) | 6.21 seconds |
| Throughput | **824 KB/s** |
| Sectors/second | 1,609 |
| Latency per sector | 0.62 ms |

**Performance Class:** HIGH - Strong performance from the industrial product line, comparable to SanDisk consumer cards.

### Benchmark Results — Standard Protocol (350/250 MHz, 25 MHz SPI)

**Test Date:** 2026-02-25
**Test Program**: SD_performance_benchmark.spin2 v2.0
**Driver Commit**: d62e30d
**Benchmark Protocol**: Both runs use 25 MHz SPI clock — isolates Spin2 overhead effect from SPI bus speed.

#### 350 MHz Run

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 233.8 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 517 | 621 | 1,144 | **824** |
| Write 1x512B | 1,307 | 2,174 | 8,806 | **235** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 1,967 | 2,163 | 2,594 | **1,893** |
| Read 32 sectors (16 KB) | 6,953 | 7,071 | 7,603 | **2,317** |
| Read 64 sectors (32 KB) | 13,624 | 13,725 | 14,238 | **2,387** |
| Write 8 sectors (4 KB) | 2,539 | 2,910 | 3,625 | **1,407** |
| Write 32 sectors (16 KB) | 7,889 | 8,164 | 8,765 | **2,006** |
| Write 64 sectors (32 KB) | 14,836 | 15,126 | 15,817 | **2,166** |
| **File-Level** | | | | |
| File Write 512B | 8,218 | 9,926 | 16,252 | **51** |
| File Write 4 KB | 17,218 | 18,620 | 27,373 | **219** |
| File Write 32 KB | 118,728 | 124,109 | 132,501 | **264** |
| File Read 4 KB | 4,731 | 4,791 | 5,198 | **854** |
| File Read 32 KB | 36,607 | 36,800 | 37,802 | **890** |
| File Read 128 KB | 145,733 | 146,258 | 148,093 | **896** |
| File Read 256 KB | 301,192 | 301,418 | 302,122 | **869** |
| **Overhead** | | | | |
| File Open | 138 | 183 | 591 | — |
| File Close | 35 | 35 | 36 | — |
| Mount | — | 233,800 | — | — |

Multi-sector improvement: 64x single reads = 42,543 us vs 1x CMD18 = 13,620 us (**67% faster**)

#### 250 MHz Run

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 235.3 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 595 | 690 | 1,205 | **742** |
| Write 1x512B | 1,366 | 1,599 | 2,195 | **320** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,163 | 2,258 | 2,772 | **1,813** |
| Read 32 sectors (16 KB) | 7,574 | 7,672 | 8,190 | **2,135** |
| Read 64 sectors (32 KB) | 14,777 | 14,893 | 15,387 | **2,200** |
| Write 8 sectors (4 KB) | 2,873 | 3,051 | 3,748 | **1,342** |
| Write 32 sectors (16 KB) | 8,557 | 9,492 | 14,931 | **1,726** |
| Write 64 sectors (32 KB) | 16,199 | 16,547 | 17,207 | **1,980** |
| **File-Level** | | | | |
| File Write 512B | 8,826 | 9,226 | 10,408 | **55** |
| File Write 4 KB | 18,163 | 20,213 | 26,589 | **202** |
| File Write 32 KB | 124,274 | 128,518 | 133,076 | **254** |
| File Read 4 KB | 5,284 | 5,415 | 6,453 | **756** |
| File Read 32 KB | 40,169 | 41,407 | 51,092 | **791** |
| File Read 128 KB | 159,858 | 160,368 | 162,100 | **817** |
| File Read 256 KB | 329,478 | 329,765 | 330,926 | **794** |
| **Overhead** | | | | |
| File Open | 193 | 303 | 1,298 | — |
| File Close | 50 | 50 | 50 | — |
| Mount | — | 235,300 | — | — |

Multi-sector improvement: 64x single reads = 46,936 us vs 1x CMD18 = 14,784 us (**68% faster**)

#### Sysclk Effect (350 vs 250 MHz at same 25 MHz SPI)

Both runs use identical 25 MHz SPI clock — differences are purely Spin2 inter-transfer overhead.

| Test | 350 MHz (KB/s) | 250 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 824 | 742 | +11% |
| Raw Read 64x (32 KB) | 2,387 | 2,200 | +9% |
| Raw Write 64x (32 KB) | 2,166 | 1,980 | +9% |
| File Read 256 KB | 869 | 794 | +9% |
| File Write 32 KB | 264 | 254 | +4% |

**Note:** With SPI speed held constant at 25 MHz, the 350→250 MHz delta isolates Spin2 overhead between SPI transfers. Consistent 9% improvement across raw operations from faster Spin2 processing. File write shows smaller delta (4%) as card-internal flash latency dominates.
