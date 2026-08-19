# Card: "Chinese Made" #1 8GB SDHC (claims SanDisk)

**Label:** [`unbranded-chinese-8gb-card1`](CARD-LABELS.md#unbranded-chinese-8gb-card1) — printed text is mastered there, not here
**Unique ID:** `SanDisk_SU08G_8.0_0AA81F11_201010`
**Test Date:** 2026-02-02 (characterization)

### Card Designator

```
SanDisk SU08G SDHC 7GB [FAT32] SD 3.x rev8.0 SN:0AA81F11 2010/10
Class 4, SPI 25 MHz
```

### Raw Registers

```
CID: $03 $53 $44 $53 $55 $30 $38 $47 $80 $0A $A8 $1F $11 $00 $AA $03
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $3B $37 $7F $80 $0A $40 $40 $AF
OCR: $C0FF_8000
SCR: $02 $35 $80 $01 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | Claims SanDisk (suspicious) | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (SanDisk) | [INFO] |
| PNM | [103:64] | $53 $55 $30 $38 $47 | "SU08G" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $0AA8_1F11 | 178,987,793 | [INFO] |
| MDT | [19:8] | $0AA | 2010-10 (October 2010) | [INFO] |
| CRC7 | [7:1] | $01 | $01 | [INFO] |

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
| C_SIZE | [69:48] | $3B37 | 15,159 (7,580 MB) | **[USED]** |
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
| CRC7 | [7:1] | $57 | $57 | [INFO] |

**Derived Values:**
- Read Timeout: 100 ms (calculated)
- Write Timeout: 250 ms (calculated)
- Total Sectors: 15,523,840
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
| DATA_STAT_AFTER_ERASE | [55] | 0 | Data = 0 after erase | [INFO] |
| SD_SECURITY | [54:52] | 3 | SDHC Card (security v2.00) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 1 | SD 3.0 support: Yes | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 0 | — | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | — | [INFO] |

**SD Version:** 3.0x (SD_SPEC=2, SD_SPEC3=1, SD_SPEC4=0)

### Filesystem (Corrupt FAT32)

| Field | Value |
|-------|-------|
| MBR Partition Type | $0C (FAT32 LBA) |
| VBR Sector | 2,048 |
| OEM Name | mkdosfs (Linux formatter residue) |
| Status | **CORRUPT** - VBR fields contain garbage |

**Note:** Card was formatted with Linux `mkdosfs` but filesystem is corrupt. Needs FAT32 reformatting before use.

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | PASS | CMD0/CMD8/ACMD41 sequence successful |
| CID Read | PASS | Worker cog routing |
| CSD Read | PASS | Worker cog routing |
| SCR Read | PASS | Worker cog routing |
| OCR Read | PASS | Cached during init |
| MBR Read | PASS | FAT32 LBA ($0C) partition |
| VBR Read | PASS | But data is corrupt |
| Mount | N/A | Needs FAT32 reformat first |

### Notes

- **First "Chinese" card** - See also "Chinese Made" #2 (MID $1B, genuine Samsung)
- **Unlabeled card** with speed class 4 marking, Chinese text
- CID claims **SanDisk** (MID $03, OEM "SD") - suspicious for no-name card
- Possible scenarios:
  1. Genuine SanDisk card that was relabeled/repackaged
  2. Counterfeit card spoofing SanDisk's MID (common with fakes)
  3. Recycled/refurbished SanDisk flash with new controller
- **Very old** - manufactured October 2010 (15+ years old)
- **COPY=1** - Card marked as a copy (not original)
- **SD 3.0x spec** compliant (SD_SPEC3=1, but SD_SPEC4=0)
- Filesystem corrupt - needs FAT32 reformatting before use
- **(4)** = Speed Class 4 (4 MB/s minimum write speed) - slowest class
- DATA_STAT_AFTER_ERASE=0 (erased data reads as 0s)
