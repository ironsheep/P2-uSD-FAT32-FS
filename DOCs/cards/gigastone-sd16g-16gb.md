# Card: Gigastone "High Endurance" 16GB SDHC MLC

**Label:** [`gigastone-high-endurance-16gb`](CARD-LABELS.md#gigastone-high-endurance-16gb) — printed text is mastered there, not here
**Unique ID:** `BudgetOEM_SD16G_2.0_000003FB_202502`
**Test Date:** 2026-02-25 (characterization + benchmark)

### Card Designator

```
Budget OEM SD16G SDHC 14GB [FAT32] SD 3.x rev2.0 SN:000003FB 2025/02
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

### Raw Registers

```
CID: $00 $34 $32 $53 $44 $31 $36 $47 $20 $00 $00 $03 $FB $01 $92 $D5
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $77 $0B $7F $80 $0A $40 $00 $4F
OCR: $C0FF_8000
SCR: $02 $B5 $80 $43 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $00 | Budget OEM | **[USED]** |
| OID | [119:104] | $34 $32 | "42" (ASCII) | [INFO] |
| PNM | [103:64] | $53 $44 $31 $36 $47 | "SD16G" | [INFO] |
| PRV | [63:56] | $20 | 2.0 | [INFO] |
| PSN | [55:24] | $0000_03FB | 1,019 | [INFO] |
| MDT | [19:8] | $192 | 2025-02 (February 2025) | [INFO] |
| CRC7 | [7:1] | $6A | $6A | [INFO] |

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
| C_SIZE | [69:48] | $770B | 30,475 (15,238 MB) | **[USED]** |
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
| CRC7 | [7:1] | $27 | $27 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 31,207,424
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
| DATA_STAT_AFTER_ERASE | [55] | 1 | Data = 1 after erase | [INFO] |
| SD_SECURITY | [54:52] | 3 | SDHC (security v2.00) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 1 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 3.0x (SD_SPEC=2, SD_SPEC3=1)

### Filesystem (FAT32 - Factory)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | (blank) |
| Volume Label | (blank) |
| Volume Serial | $0403_0201 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 576 |
| Number of FATs | 2 |
| Sectors per FAT | 3,808 |
| Root Cluster | 2 |
| Total Sectors | 31,199,232 |
| Data Region Start | Sector 8,192 |
| Total Clusters | 487,360 |

### Speed Characterization Results

| Speed | Half Period | Actual | Phase 1 | Phase 2 | Phase 3 | Result |
|-------|-------------|--------|---------|---------|---------|--------|
| 18 MHz | 6 clocks | 16.6 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 20 MHz | 5 clocks | 20.0 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 22 MHz | 5 clocks | 20.0 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 25 MHz | 4 clocks | 25.0 MHz | 1,000/1,000 | 10,000/10,000 | 800/800 | PASS |
| 27 MHz | 4 clocks | 25.0 MHz | — | — | — | CMD6 FAIL |

**Maximum Reliable SPI Speed:** 25 MHz (limited by SYSCLK=200 MHz, not card)

### Internal Throughput

| Metric | Value |
|--------|-------|
| Test Iterations | 10,000 single-sector reads |
| Elapsed Time | ~13.9 seconds |
| Throughput | **368 KB/s** |
| Average Latency | 1.39 ms/sector |
| Performance Class | MEDIUM |

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

- **Gigastone-branded** card using budget OEM silicon (MID $00)
- MID $00 + OID "42" = common on white-label/rebrand cards
- **Different silicon than 8GB "High Endurance"** - even same product line uses multiple sources
- **"High Endurance"** product line for continuous recording (dashcams, security cameras)
- **MLC** (Multi-Level Cell) flash - more durable than TLC
- **10x** = marketing claim for endurance vs standard cards
- **HC I** = SDHC UHS-I interface
- **U3** = UHS Speed Class 3 (30 MB/s minimum write)
- **V30** = Video Speed Class 30 (30 MB/s sustained write)
- **4K** = Suitable for 4K video recording
- **SD 3.0x spec** (SD_SPEC3=1, SD_SPEC4=0) - older spec than some cards
- CCC $5B5 - standard command classes (no video class bits despite V30 marketing)
- Factory formatted with blank OEM name and volume label
- Very recent manufacture (February 2025)
- Fourth different silicon source found in Gigastone cards
- DATA_STAT_AFTER_ERASE=1 (erased data reads as 1s)
- **MEDIUM throughput (368 KB/s)** - slower than premium cards but reliable
- MLC flash may prioritize endurance over raw speed
- **Benchmark data available** — see Benchmark Results section below; slowest card tested (file write 32 KB at 105 KB/s, raw single-sector write latency 3.6 ms)

### Benchmark Results — Standard Protocol (350/250 MHz, 25 MHz SPI)

**Test Date:** 2026-02-25
**Test Program**: SD_performance_benchmark.spin2 v2.0
**Driver Commit**: d62e30d
**Benchmark Protocol**: Both runs use 25 MHz SPI clock — isolates Spin2 overhead effect from SPI bus speed.

#### 350 MHz Run

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 202.0 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 870 | 888 | 1,054 | **576** |
| Write 1x512B | 3,405 | 3,565 | 4,142 | **143** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,512 | 2,531 | 2,696 | **1,618** |
| Read 32 sectors (16 KB) | 8,144 | 8,162 | 8,328 | **2,007** |
| Read 64 sectors (32 KB) | 15,653 | 15,671 | 15,837 | **2,090** |
| Write 8 sectors (4 KB) | 4,979 | 5,210 | 5,725 | **786** |
| Write 32 sectors (16 KB) | 10,377 | 10,459 | 11,119 | **1,566** |
| Write 64 sectors (32 KB) | 17,449 | 17,536 | 18,165 | **1,868** |
| **File-Level** | | | | |
| File Write 512B | 21,107 | 22,492 | 28,046 | **22** |
| File Write 4 KB | 45,946 | 47,101 | 54,986 | **86** |
| File Write 32 KB | 292,665 | 298,016 | 301,634 | **109** |
| File Read 4 KB | 6,885 | 6,974 | 7,776 | **587** |
| File Read 32 KB | 53,186 | 53,345 | 54,780 | **614** |
| File Read 128 KB | 199,600 | 199,806 | 201,255 | **655** |
| File Read 256 KB | 397,126 | 397,433 | 398,929 | **659** |
| **Overhead** | | | | |
| File Open | 138 | 227 | 1,028 | — |
| File Close | 35 | 35 | 36 | — |
| Mount | — | 202,000 | — | — |

Multi-sector improvement: 64x single reads = 56,069 us vs 1x CMD18 = 15,653 us (**72% faster**)

#### 250 MHz Run

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 204.1 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 938 | 956 | 1,123 | **535** |
| Write 1x512B | 3,475 | 3,628 | 4,189 | **141** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,771 | 2,790 | 2,956 | **1,468** |
| Read 32 sectors (16 KB) | 9,056 | 9,075 | 9,242 | **1,805** |
| Read 64 sectors (32 KB) | 17,437 | 17,455 | 17,622 | **1,877** |
| Write 8 sectors (4 KB) | 5,375 | 5,487 | 5,934 | **746** |
| Write 32 sectors (16 KB) | 11,176 | 11,307 | 11,891 | **1,449** |
| Write 64 sectors (32 KB) | 18,989 | 19,134 | 19,703 | **1,712** |
| **File-Level** | | | | |
| File Write 512B | 20,664 | 21,630 | 21,979 | **23** |
| File Write 4 KB | 46,525 | 47,222 | 48,218 | **86** |
| File Write 32 KB | 294,892 | 301,778 | 308,079 | **108** |
| File Read 4 KB | 7,381 | 7,475 | 8,315 | **547** |
| File Read 32 KB | 56,560 | 56,728 | 58,245 | **577** |
| File Read 128 KB | 211,369 | 211,538 | 213,054 | **619** |
| File Read 256 KB | 424,131 | 424,609 | 426,177 | **617** |
| **Overhead** | | | | |
| File Open | 193 | 286 | 1,126 | — |
| File Close | 50 | 50 | 50 | — |
| Mount | — | 204,100 | — | — |

Multi-sector improvement: 64x single reads = 60,329 us vs 1x CMD18 = 17,437 us (**71% faster**)

#### Sysclk Effect (350 vs 250 MHz at same 25 MHz SPI)

Both runs use identical 25 MHz SPI clock — differences are purely Spin2 inter-transfer overhead.

| Test | 350 MHz (KB/s) | 250 MHz (KB/s) | Delta |
|------|----------------|----------------|-------|
| Raw Read 1x512B | 576 | 535 | +8% |
| Raw Read 64x (32 KB) | 2,090 | 1,877 | +11% |
| Raw Write 64x (32 KB) | 1,868 | 1,712 | +9% |
| File Read 256 KB | 659 | 617 | +7% |
| File Write 32 KB | 109 | 108 | +1% |

**Note:** Slowest card tested. File write 32 KB at 109 KB/s — budget OEM flash controller dominates latency. The 72% multi-sector improvement is the highest observed, because single-sector command overhead is proportionally larger on this slow card. Sysclk effect is muted for file writes (1%) since card controller latency dominates.
