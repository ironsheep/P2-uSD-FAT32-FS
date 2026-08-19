# Card: Kingston 8GB SDHC

**Label:** [`kingston-microsd-hc-8gb`](CARD-LABELS.md#kingston-microsd-hc-8gb) — printed text is mastered there, not here
**Disposition:** `retained`
**Unique ID:** `Kingston_SD8GB_3.0_43F65DC9_201504`
**Test Date:** 2026-02-02 (characterization)

### Card Designator

```
Kingston SD8GB SDHC 7GB [FAT32] SD 3.x rev3.0 SN:43F65DC9 2015/04
Class 10, U1, SPI 25 MHz
```

### Raw Registers

```
CID: $41 $34 $32 $53 $44 $38 $47 $42 $30 $43 $F6 $5D $C9 $00 $F4 $A1
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $3A $8F $7F $80 $0A $40 $00 $87
OCR: $C0FF_8000
SCR: $02 $B5 $80 $00 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $41 | Kingston | **[USED]** |
| OID | [119:104] | $34 $32 | "42" (ASCII) | [INFO] |
| PNM | [103:64] | $53 $44 $38 $47 $42 | "SD8GB" | [INFO] |
| PRV | [63:56] | $30 | 3.0 | [INFO] |
| PSN | [55:24] | $43F6_5DC9 | 1,140,530,633 | [INFO] |
| MDT | [19:8] | $0F4 | 2015-04 (April 2015) | [INFO] |
| CRC7 | [7:1] | $50 | $50 | [INFO] |

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
| C_SIZE | [69:48] | $3A8F | 14,991 (7,496 MB) | **[USED]** |
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
| CRC7 | [7:1] | $43 | $43 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 15,351,808
- Capacity: ~7 GB

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
| SD_SPECX | [41:38] | 0 | — | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 3.0x (SD_SPEC=2, SD_SPEC3=1)

### Filesystem (FAT32 - Factory CHS format)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0B (FAT32 CHS) |
| VBR Sector | 8,192 |
| OEM Name | SD |
| Volume Label | (blank) |
| Volume Serial | $0403_0201 |
| FS Type | FAT32 |
| Bytes/Sector | 512 |
| Sectors/Cluster | 64 (32 KB clusters) |
| Reserved Sectors | 4,446 |
| Number of FATs | 2 |
| Sectors per FAT | 1,873 |
| Root Cluster | 2 |
| Total Sectors | 15,343,616 |
| Data Region Start | Sector 8,192 |
| Total Clusters | 239,616 |

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | FAT32 CHS ($0B) partition |
| VBR Read | PASS | |
| Mount | PASS | |
| Regression | PASS | All tests pass |

### Notes

- **Genuine Kingston** card - MID $41 is registered Kingston
- **HC I** = SDHC UHS-I interface
- **ui** = UHS-I marking on label
- **(10)** = Speed Class 10 (10 MB/s minimum write speed)
- **"Taiwan"** = Country of manufacture
- **F(c)o** = likely FCC compliance marking
- **SD 3.0x spec** (SD_SPEC3=1, SD_SPEC4=0, SD_SPECX=0) - older spec
- CCC $5B5 - standard command classes
- Manufactured April 2015 (~10 years old)
- Kingston is a recommended brand for embedded SPI use
- Uses FAT32 CHS partition type ($0B) vs LBA ($0C)
- DATA_STAT_AFTER_ERASE=1 (erased data reads as 1s)
