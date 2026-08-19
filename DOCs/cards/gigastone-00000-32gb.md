# Card: Gigastone 32GB SDHC

**Label:** [`gigastone-microsd-hc-a1-u1-32gb`](CARD-LABELS.md#gigastone-microsd-hc-a1-u1-32gb) — printed text is mastered there, not here
**Unique ID:** `Transcend_00000_0.0_000001C9_202307`
**Test Date:** 2026-02-02 (characterization)

### Card Designator

```
Gigastone 00000 SDHC 29GB [FAT32] SD 3.x rev0.0 SN:000001C9 2023/07
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

### Raw Registers

```
CID: $74 $4A $60 $30 $30 $30 $30 $30 $00 $00 $00 $01 $C9 $01 $77 $09
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $E8 $F5 $7F $80 $0A $40 $00 $D1
OCR: $C0FF_8000
SCR: $02 $B5 $80 $83 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $74 | Transcend | **[USED]** |
| OID | [119:104] | $4A $60 | "J`" | [INFO] |
| PNM | [103:64] | $30 $30 $30 $30 $30 | "00000" | [INFO] |
| PRV | [63:56] | $00 | 0.0 | [INFO] |
| PSN | [55:24] | $0000_01C9 | 457 | [INFO] |
| MDT | [19:8] | $177 | 2023-07 (July 2023) | [INFO] |
| CRC7 | [7:1] | $04 | $04 | [INFO] |

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
| C_SIZE | [69:48] | $E8F5 | 59,637 (29,819 MB) | **[USED]** |
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
| CRC7 | [7:1] | $68 | $68 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 61,069,312
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
| DATA_STAT_AFTER_ERASE | [55] | 1 | Data = 1 after erase | [INFO] |
| SD_SECURITY | [54:52] | 3 | SDHC (security v2.00) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 2 | SD 5.x/6.x/7.x indicator | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 3.0x (SD_SPEC=2, SD_SPEC3=1)

### Filesystem (FAT32 - reformatted with P2FMTER)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 8,192 |
| OEM Name | P2FMTER |
| Volume Label | P2-XFER |
| Volume Serial | $04AA_C74F |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 32 (16 KB clusters) |
| Reserved Sectors | 32 |
| Number of FATs | 2 |
| Sectors per FAT | 14,908 |
| Root Cluster | 2 |
| Total Sectors | 61,061,120 |
| Data Region Start | Sector 29,848 |
| Total Clusters | 1,907,227 |

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

- **Gigastone-branded** card using **Transcend** flash/controller silicon (MID $74)
- **HC I** = SDHC UHS-I interface (up to 104 MB/s bus speed)
- **A1** = Application Performance Class 1 (1500 read IOPS, 500 write IOPS)
- **U1** = UHS Speed Class 1 (10 MB/s minimum write speed)
- **(10)** = Speed Class 10 (10 MB/s minimum write speed)
- Product name "00000" and revision "0.0" = OEM/white-label product
- Originally formatted with SD Card Formatter (MSWIN4.1), now P2FMTER
- 16 KB cluster size (smaller than typical 32 KB)
- DATA_STAT_AFTER_ERASE=1 (erased data reads as 1s)
