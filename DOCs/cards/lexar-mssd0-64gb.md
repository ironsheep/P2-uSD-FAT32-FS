# Card: Lexar Red MicroSD XC A1 V30 U3 64GB

**Label:** Lexar A1 V30 U3 64GB microSD XC (Red card)
**Unique ID:** `Longsys/Lexar_MSSD0_6.1_33549024_202411`
**Test Date:** 2026-02-17 (full re-characterization)

### Card Designator

```
Lexar MSSD0 SDXC 58GB [FAT32] SD 6.x rev6.1 SN:33549024 2024/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

*Note: Two physical units tested. Current unit SN:33549024. Previous unit SN:31899471 had identical CSD/OCR/SCR registers. Both units labeled A1 on the physical card; ACMD13 register reports A2.*

### Raw Registers

```
CID: $AD $4C $53 $4D $53 $53 $44 $30 $61 $33 $54 $90 $24 $71 $8B $55
CSD: $40 $0E $00 $32 $DB $79 $00 $01 $D2 $67 $7F $80 $0A $40 $00 $59
OCR: $C0FF_8000
SCR: $02 $45 $84 $87 $33 $33 $30 $39
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $AD | Longsys/Lexar | **[USED]** |
| OID | [119:104] | $4C $53 | "LS" (Longsys/Lexar) | [INFO] |
| PNM | [103:64] | $4D $53 $53 $44 $30 | "MSSD0" | [INFO] |
| PRV | [63:56] | $61 | 6.1 | [INFO] |
| PSN | [55:24] | $3354_9024 | 862,269,476 | [INFO] |
| MDT | [19:8] | $18B | 2024-11 (November 2024) | [INFO] |
| CRC7 | [7:1] | $2A | $2A | [INFO] |

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
| C_SIZE | [69:48] | $1D267 | 119,399 (59,700 MB) | **[USED]** |
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
| CRC7 | [7:1] | $2C | $2C | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 122,265,600
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
| SD_SECURITY | [54:52] | 4 | SDXC (security v3.xx) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 1 | SD 4.0 support: Yes | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $03 | CMD20+CMD23 advertised (CMD23 rejected in SPI mode) | [INFO] |

**SD Version:** 6.x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=1, SD_SPECX=2)

### Filesystem (FAT32 - formatted with P2FMTER)

| Field | Value |
|-------|-------|
| Factory Format | exFAT ($07) - reformatted to FAT32 |
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-XFER |
| Volume Serial | $047C_AD41 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 14,924 |
| Root Cluster | 2 |
| Total Sectors | 122,257,408 |
| Data Region Start | Sector 29,880 |
| Total Clusters | 1,909,805 |

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
| Mount | PASS | 212.4 ms at 350 MHz |

### Notes

- **Lexar-branded** card using Longsys silicon (Longsys acquired Lexar brand in 2017)
- MID $AD = Longsys (often incorrectly listed as Hynix in older databases)
- OEM code "LS" = Longsys/Lexar
- **CCC $DB7** includes Class 1 (stream read) and Class 11 (video speed class) - video-optimized card
- **V30** = Video Speed Class 30 (30 MB/s sustained write)
- **U3** = UHS Speed Class 3 (30 MB/s minimum write)
- **(10)** = Speed Class 10 (10 MB/s minimum write speed)
- **100 MB/s*** = Maximum read speed (asterisk indicates "up to")
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2) — newest spec generation
- **A2** = Application Performance Class 2 (confirmed by ACMD13 SD Status register)
- **CMD23 advertised but rejected in SPI mode** - SCR CMD_SUPPORT=$03 advertises CMD23 (SET_BLOCK_COUNT), but CMD23 returns R1=$04 (Illegal Command) in SPI mode. The CMD_SUPPORT field applies to the SD 4-bit bus interface, not SPI. Verified 2026-03-06
- Factory formatted with exFAT — reformatted to FAT32 with P2FMTER
- Very recent manufacture (November 2024)
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)

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
| Phase 2 Duration (10,000 reads) | 4.84 seconds |
| Throughput | **1,059 KB/s** |
| Sectors/second | 2,068 |
| Latency per sector | 0.48 ms |

**Performance Class:** HIGH - **Fastest card tested** (12% faster than Gigastone Camera Plus, 35% faster than Samsung/SanDisk).

### Benchmark Results (Smart Pin SPI + Multi-Sector)

**Test Program**: SD_performance_benchmark.spin2 v2.0

#### 350 MHz Run (2026-02-17)

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 212.4 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 402 | 413 | 506 | **1,239** |
| Write 1x512B | 750 | 759 | 841 | **674** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 1,888 | 2,062 | 3,523 | **1,986** |
| Read 32 sectors (16 KB) | 6,979 | 6,990 | 7,083 | **2,343** |
| Read 64 sectors (32 KB) | 13,782 | 13,791 | 13,881 | **2,376** |
| Write 8 sectors (4 KB) | 2,218 | 2,221 | 2,222 | **1,844** |
| Write 32 sectors (16 KB) | 7,398 | 7,398 | 7,399 | **2,214** |
| Write 64 sectors (32 KB) | 14,554 | 14,554 | 14,554 | **2,251** |
| **File-Level** | | | | |
| File Write 512B | 5,794 | 6,216 | 6,560 | **82** |
| File Write 4 KB | 12,902 | 13,689 | 14,493 | **299** |
| File Write 32 KB | 53,566 | 75,640 | 86,051 | **433** |
| File Read 4 KB | 3,950 | 3,967 | 4,093 | **1,032** |
| File Read 32 KB | 24,637 | 24,663 | 24,807 | **1,328** |
| File Read 128 KB | 95,603 | 95,689 | 96,211 | **1,369** |
| File Read 256 KB | 190,121 | 190,215 | 190,799 | **1,378** |
| **Overhead** | | | | |
| File Open | 956 | 991 | 1,311 | — |
| File Close | 20 | 20 | 21 | — |
| Mount | — | 212,400 | — | — |

Multi-sector improvement: 64x single reads = 28,659 us vs 1x CMD18 = 13,818 us (**51% faster**)

#### 250 MHz Run (2026-02-17)

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 214.2 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 467 | 480 | 566 | **1,066** |
| Write 1x512B | 801 | 811 | 898 | **631** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,083 | 2,093 | 2,182 | **1,956** |
| Read 32 sectors (16 KB) | 7,625 | 7,634 | 7,723 | **2,146** |
| Read 64 sectors (32 KB) | 15,013 | 15,023 | 15,117 | **2,181** |
| Write 8 sectors (4 KB) | 2,434 | 2,434 | 2,435 | **1,682** |
| Write 32 sectors (16 KB) | 8,139 | 8,139 | 8,139 | **2,013** |
| Write 64 sectors (32 KB) | 15,996 | 15,996 | 15,996 | **2,048** |
| **File-Level** | | | | |
| File Write 512B | 6,390 | 6,813 | 7,152 | **75** |
| File Write 4 KB | 13,878 | 14,662 | 15,451 | **279** |
| File Write 32 KB | 77,125 | 82,677 | 87,890 | **396** |
| File Read 4 KB | 4,630 | 4,645 | 4,738 | **881** |
| File Read 32 KB | 28,565 | 28,586 | 28,698 | **1,146** |
| File Read 128 KB | 110,678 | 110,740 | 111,225 | **1,183** |
| File Read 256 KB | 220,168 | 220,236 | 220,829 | **1,190** |
| **Overhead** | | | | |
| File Open | 1,153 | 1,183 | 1,425 | — |
| File Close | 29 | 29 | 29 | — |
| Mount | — | 214,200 | — | — |

Multi-sector improvement: 64x single reads = 32,551 us vs 1x CMD18 = 15,013 us (**53% faster**)

#### Sysclk Effect (350 MHz vs 250 MHz)

SPI clock is identical (25,000 kHz) at both speeds. Differences show Spin2 inter-transfer overhead.

| Metric | 350 MHz | 250 MHz | Overhead (us) | Overhead % |
|--------|---------|---------|---------------|------------|
| Raw Read 1x512B | 413 us | 480 us | +67 | +16% |
| Raw Write 1x512B | 759 us | 811 us | +52 | +7% |
| Raw Read 64x (32 KB) | 13,791 us | 15,023 us | +1,232 | +9% |
| Raw Write 64x (32 KB) | 14,554 us | 15,996 us | +1,442 | +10% |
| File Read 256 KB | 190,215 us | 220,236 us | +30,021 | +16% |
| File Write 32 KB | 75,640 us | 82,677 us | +7,037 | +9% |
| File Open | 991 us | 1,183 us | +192 | +19% |
