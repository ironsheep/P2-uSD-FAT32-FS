# Card: Silicon Power Elite MicroSD XC 64GB

**Label:** [`sp-elite-64gb`](CARD-LABELS.md#sp-elite-64gb) — printed text is mastered there, not here
**Unique ID:** `SharedOEM_SPCC_0.7_00940105_202507`
**Test Date:** 2026-03-06 (benchmark + CMD12/CMD23 analysis)

### Card Designator

```
SharedOEM SPCC SDXC 57GB [FAT32] SD 6.x rev0.7 SN:00940105 2025/07
Class 10, U3, A1, V30, SPI 25 MHz  [P2FMTER]
```

*Note: Physical label says U1, but ACMD13 SD Status register reports U3, A1, V30. Register data is authoritative.*

### Raw Registers

```
CID: $9F $54 $49 $53 $50 $43 $43 $20 $07 $00 $94 $01 $05 $71 $97 $6B
CSD: $40 $0E $00 $32 $DB $59 $00 $01 $CF $9B $7F $80 $0A $40 $00 $81
OCR: $C0FF_8000
SCR: $02 $45 $84 $8F $33 $33 $30 $39
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $9F | Shared OEM (Silicon Power) | **[USED]** |
| OID | [119:104] | $54 $49 | "TI" | [INFO] |
| PNM | [103:64] | $53 $50 $43 $43 $20 | "SPCC " | [INFO] |
| PRV | [63:56] | $07 | 0.7 | [INFO] |
| PSN | [55:24] | $0094_0105 | 9,699,589 | [INFO] |
| MDT | [19:8] | $197 | 2025-07 (July 2025) | [INFO] |
| CRC7 | [7:1] | $35 | $35 | [INFO] |

### CSD Register (Card Specific Data) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| CSD_STRUCTURE | [127:126] | 1 | CSD Version 2.0 (SDHC/SDXC) | **[USED]** |
| TAAC | [119:112] | $0E | Read access time-1 | **[USED]** |
| NSAC | [111:104] | $00 | 0 CLK cycles | **[USED]** |
| TRAN_SPEED | [103:96] | $32 | 25 MHz max | **[USED]** |
| CCC | [95:84] | $DB5 | Classes 0,2,4,5,7,8,10,11 | [INFO] |
| READ_BL_LEN | [83:80] | 9 | 512 bytes | [INFO] |
| READ_BL_PARTIAL | [79] | 0 | Not allowed | [INFO] |
| WRITE_BLK_MISALIGN | [78] | 0 | Not allowed | [INFO] |
| READ_BLK_MISALIGN | [77] | 0 | Not allowed | [INFO] |
| DSR_IMP | [76] | 0 | DSR not implemented | [INFO] |
| C_SIZE | [69:48] | $1CF9B | 118,683 (59,342 MB) | **[USED]** |
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
| CRC7 | [7:1] | $40 | $40 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 121,532,416
- Capacity: ~57 GB

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
| Volume Label | P2-BENCH |
| Volume Serial | $0466_FE25 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 14,835 |
| Root Cluster | 2 |
| Total Sectors | 121,524,224 |
| Data Region Start | Sector 29,702 |
| Total Clusters | 1,898,351 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| SD Status | PASS | ACMD13 (64 bytes) |
| MBR Read | PASS | exFAT partition detected (factory) |
| Format | PASS | FAT32 formatted with P2FMTER |
| Mount | PASS | CMD18 warmup removed; CMD12 tolerance added |
| Regression | PASS | 20/20 suites, 407+ tests (2026-03-05) |

**CMD12 Anomaly (RESOLVED):** This card exhibits a CMD12 framing anomaly — the card's read-ahead pipeline starts streaming the next sector before CMD12 can stop it, producing an invalid R1 response ($E0). The driver handles this with CMD12 tolerance + CS deassert recovery. Data integrity is 100% — all sectors arrive with valid CRC-16. Full analysis: [CMD12-SPCE-ANALYSIS.md](../Analysis/CMD12-SPCE-ANALYSIS.md).

### Benchmark Results (Smart Pin SPI + Multi-Sector)

**Test Program**: SD_performance_benchmark.spin2 v2.0

#### 350 MHz Run (2026-03-06)

**SysClk**: 350 MHz | **SPI**: 25,000 kHz | **Mount**: 213.1 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 485 | 529 | 909 | **967** |
| Write 1x512B | 690 | 697 | 761 | **734** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,020 | 2,044 | 2,260 | **2,003** |
| Read 32 sectors (16 KB) | 7,167 | 7,190 | 7,403 | **2,278** |
| Read 64 sectors (32 KB) | 14,012 | 14,037 | 14,267 | **2,334** |
| Write 8 sectors (4 KB) | 2,230 | 2,235 | 2,243 | **1,832** |
| Write 32 sectors (16 KB) | 7,526 | 7,531 | 7,544 | **2,175** |
| Write 64 sectors (32 KB) | 14,665 | 14,677 | 14,696 | **2,232** |
| **File-Level** | | | | |
| File Write 512B | 5,029 | 5,629 | 5,709 | **90** |
| File Write 4 KB | 10,590 | 10,603 | 10,613 | **386** |
| File Write 32 KB | 49,852 | 50,291 | 53,427 | **651** |
| File Read 4 KB | 3,152 | 3,229 | 3,844 | **1,268** |
| File Read 32 KB | 23,767 | 23,950 | 24,623 | **1,368** |
| File Read 128 KB | 93,995 | 94,242 | 95,890 | **1,390** |
| File Read 256 KB | 186,871 | 187,166 | 188,830 | **1,400** |
| **Overhead** | | | | |
| File Open | 148 | 212 | 791 | — |
| File Close | 35 | 35 | 36 | — |
| Mount | — | 213,100 | — | — |

Multi-sector improvement: 64x single reads = 31,694 us vs 1x CMD18 = 14,013 us (**55% faster**)

#### 250 MHz Run (2026-03-06)

**SysClk**: 250 MHz | **SPI**: 25,000 kHz | **Mount**: 215.4 ms

| Test | Min (us) | Avg (us) | Max (us) | KB/s |
|------|----------|----------|----------|------|
| **Raw Single-Sector** | | | | |
| Read 1x512B | 581 | 624 | 996 | **820** |
| Write 1x512B | 760 | 766 | 821 | **668** |
| **Raw Multi-Sector** | | | | |
| Read 8 sectors (4 KB) | 2,253 | 2,277 | 2,493 | **1,798** |
| Read 32 sectors (16 KB) | 7,874 | 7,898 | 8,114 | **2,074** |
| Read 64 sectors (32 KB) | 15,349 | 15,380 | 15,609 | **2,130** |
| Write 8 sectors (4 KB) | 2,464 | 2,470 | 2,477 | **1,658** |
| Write 32 sectors (16 KB) | 8,296 | 8,303 | 8,315 | **1,973** |
| Write 64 sectors (32 KB) | 16,176 | 16,187 | 16,206 | **2,024** |
| **File-Level** | | | | |
| File Write 512B | 5,504 | 6,129 | 6,208 | **83** |
| File Write 4 KB | 11,444 | 11,862 | 15,013 | **345** |
| File Write 32 KB | 53,816 | 53,887 | 54,104 | **608** |
| File Read 4 KB | 3,710 | 3,787 | 4,445 | **1,081** |
| File Read 32 KB | 27,576 | 27,734 | 28,368 | **1,181** |
| File Read 128 KB | 109,220 | 109,475 | 111,221 | **1,197** |
| File Read 256 KB | 218,181 | 218,435 | 220,066 | **1,200** |
| **Overhead** | | | | |
| File Open | 207 | 276 | 902 | — |
| File Close | 50 | 50 | 50 | — |
| Mount | — | 215,400 | — | — |

Multi-sector improvement: 64x single reads = 38,158 us vs 1x CMD18 = 15,357 us (**59% faster**)

#### Sysclk Effect (350 MHz vs 250 MHz)

SPI clock is identical (25,000 kHz) at both speeds. Differences show Spin2 inter-transfer overhead.

| Metric | 350 MHz | 250 MHz | Overhead (us) | Overhead % |
|--------|---------|---------|---------------|------------|
| Raw Read 1x512B | 529 us | 624 us | +95 | +18% |
| Raw Write 1x512B | 697 us | 766 us | +69 | +10% |
| Raw Read 64x (32 KB) | 14,037 us | 15,380 us | +1,343 | +10% |
| Raw Write 64x (32 KB) | 14,677 us | 16,187 us | +1,510 | +10% |
| File Read 256 KB | 187,166 us | 218,435 us | +31,269 | +17% |
| File Write 32 KB | 50,291 us | 53,887 us | +3,596 | +7% |
| File Open | 212 us | 276 us | +64 | +30% |

### Notes

- **MID $9F** - "Shared OEM" code, not assigned to a specific manufacturer in the SD Association registry. Silicon Power Computer Communications (SPCC) is a Taiwanese company that contracts flash manufacturing.
- **OID "TI"** ($54 $49) — contract manufacturer identifier (not Texas Instruments)
- **PNM "SPCC"** — Silicon Power Computer Communications Corporation
- **Label discrepancy**: Physical label says "UHS-I U1 (10)" but ACMD13 SD Status reports U3, A1, V30. The card may be marketed conservatively or the label may be for a different SKU in the same product line.
- **CCC $DB5** includes Class 11 (video speed class) — consistent with V30 rating
- **CMD23 advertised but rejected in SPI mode** — SCR CMD_SUPPORT=$03 advertises CMD23 (SET_BLOCK_COUNT), but CMD23 returns R1=$04 (Illegal Command) in SPI mode. The CMD_SUPPORT field applies to the SD 4-bit bus interface, not SPI. Verified 2026-03-06
- **SD 6.x** spec compliant (SD_SPEC4=1, SD_SPECX=2) — newest spec version we've seen
- **DATA_STAT_AFTER_ERASE=0** (erased data reads as 0s)
- Very recent manufacture (July 2025)
- Factory formatted with exFAT — needs FAT32 reformat before use with P2 SD driver
