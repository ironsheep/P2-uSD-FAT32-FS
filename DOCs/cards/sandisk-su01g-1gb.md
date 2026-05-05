# Card: SanDisk SU01G 1 GB SDSC (Industrial, June 2007)

**Label:** microSD 1GB — SanDisk Industrial SU series
**Unique ID:** `SanDisk_SU01G_8.0_006CD5B2_200706`
**Test Date:** 2026-05-05 (characterization on @macca's hardware)
**Reporter:** @macca (field user)
**Status:** **FAILS** under v1.5.1 default settings — see Test Results below

### Card Designator

```
SanDisk SU01G SDSC 1GB SD 2.0 rev8.0 SN:$006C_D5B2 2007/06
Class 2, U0, V0, SPI 25 MHz
```

### Raw Registers

```
CID: $03 $53 $44 $53 $55 $30 $31 $47 $80 $00 $6C $D5 $B2 $00 $76 $DB
CSD: $00 $26 $00 $32 $5F $59 $83 $C8 $BE $FB $CF $FF $92 $40 $40 $D7
OCR: $80FF_8000
SCR: $02 $25 $00 $00 $00 $00 $00 $00
```

### CID Register (Card Identification) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $03 | SanDisk | **[USED]** |
| OID | [119:104] | $53 $44 | "SD" (SanDisk) | [INFO] |
| PNM | [103:64] | $53 $55 $30 $31 $47 | "SU01G" | [INFO] |
| PRV | [63:56] | $80 | 8.0 | [INFO] |
| PSN | [55:24] | $006C_D5B2 | 7,132,594 | [INFO] |
| MDT | [19:8] | $076 | 2007-06 (June 2007) | [INFO] |
| CRC7 | [7:1] | $6D | $6D | [INFO] |

### CSD Register (Card Specific Data, v1.0 / SDSC layout) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| CSD_STRUCTURE | [127:126] | 0 | **CSD Version 1.0 (SDSC)** | **[USED]** |
| TAAC | [119:112] | $26 | 1.5 ms (1.5 × 1 ms unit) | **[USED]** |
| NSAC | [111:104] | $00 | 0 CLK cycles | **[USED]** |
| TRAN_SPEED | [103:96] | $32 | 25 MHz max | **[USED]** |
| CCC | [95:84] | $5F5 | Classes 0,2,4,5,6,7,8,10 | [INFO] |
| READ_BL_LEN | [83:80] | 9 | 512 bytes | [INFO] |
| READ_BL_PARTIAL | [79] | 1 | Allowed | [INFO] |
| WRITE_BLK_MISALIGN | [78] | 0 | Not allowed | [INFO] |
| READ_BLK_MISALIGN | [77] | 0 | Not allowed | [INFO] |
| DSR_IMP | [76] | 0 | DSR not implemented | [INFO] |
| C_SIZE | [73:62] | 3,874 | Device size (SDSC) | **[USED]** |
| VDD_R_CURR_MIN | [61:59] | 7 | 100 mA at VDD min (read) | [INFO] |
| VDD_R_CURR_MAX | [58:56] | 6 | 80 mA at VDD max (read) | [INFO] |
| VDD_W_CURR_MIN | [55:53] | 7 | 100 mA at VDD min (write) | [INFO] |
| VDD_W_CURR_MAX | [52:50] | 6 | 80 mA at VDD max (write) | [INFO] |
| C_SIZE_MULT | [49:47] | 7 | Device size multiplier (SDSC) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 31 | Erase sector = 16 KB (32 sectors) | [INFO] |
| WP_GRP_SIZE | [38:32] | 127 | — | [INFO] |
| WP_GRP_ENABLE | [31] | 1 | Enabled | [INFO] |
| R2W_FACTOR | [28:26] | 4 | **Write = Read × 16** | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | — | [INFO] |
| COPY | [14] | 1 | Copy | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $6B | $6B | [INFO] |

**Derived Values:**
- Read Timeout: **1,500 ms** (calculated from TAAC, with 10× safety margin)
- Write Timeout: **24,000 ms** (calculated from TAAC × R2W_FACTOR)
- Capacity: 968 MB
- Total Sectors: 1,982,464

### OCR Register (Operating Conditions) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| Power Up Status | [31] | 1 | Ready | [INFO] |
| CCS | [30] | 0 | **SDSC (byte addressing)** | **[USED]** |
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

**OCR Value:** $80FF_8000

### SCR Register (SD Configuration) - All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| SCR_STRUCTURE | [63:60] | 0 | SCR Version 1.0 | [INFO] |
| SD_SPEC | [59:56] | 2 | SD Physical Layer 2.00 | **[USED]** |
| DATA_STAT_AFTER_ERASE | [55] | 0 | Data = 0 after erase | [INFO] |
| SD_SECURITY | [54:52] | 2 | SDSC Card (security v1.01) | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 0 | SD 3.0 support: No | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 0 | — | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | No extended commands | [INFO] |

**SD Version:** 2.00 (SD_SPEC=2, SD_SPEC3=0)

### Filesystem

| Field | Value |
|-------|-------|
| MBR Partition Type | $00 (Empty / Unknown) |
| Status | **Cannot read** — sector 0 returns 512 bytes of $00 under v1.5.1 |

The all-zeros sector 0 readback is consistent with the streamer-DMA failure mode observed in this card's test results — we don't know whether the partition table is genuinely empty or whether sector 0's data is being lost in transit. See User Report `2026-05-05-macca-v151-test-results.md` for analysis.

### Test Results (under driver v1.5.1, sysclk=350 MHz, SPI=25 MHz)

| Test | Status | Notes |
|------|--------|-------|
| Card Init (CMD0/CMD8/ACMD41) | **PASS** | Smart-pin SPI works |
| CID Read (CMD10) | **PASS** | Smart-pin SPI byte-by-byte |
| CSD Read (CMD9) | **PASS** | Smart-pin SPI byte-by-byte |
| SCR Read (ACMD51) | **PASS** | Smart-pin SPI byte-by-byte |
| OCR Read (CMD58) | **PASS** | Smart-pin SPI |
| Mount (`SD_RT_mount_tests`) | **FAIL** | First mount returns -7 (E_IO_ERROR), readSector(0) fails; subsequent mounts return -8 (E_BAD_RESPONSE). 18/31 sub-tests pass; 12 fail. |
| Raw Sector Round-Trip (`SD_RT_raw_sector_tests`) | **FAIL** | Every sector readback returns 512 bytes of $00. CMD13 reports CSR_CC_ERROR. 1/14 sub-tests pass. |
| Characterize (read registers only) | **PASS** at sysclk=270 MHz | Works because no streamer reads are exercised |

**Failure Pattern Summary:** Smart-pin SPI works flawlessly on this card. **Streamer-DMA sector reads return all $00**, and CMD13 reports `CSR_CC_ERROR` ($08, bit 3 of R2 status byte). This is the only card in the catalog that exhibits this failure mode.

### Notes

- **Only SDSC card in the catalog.** All other 23 catalog cards report `CSD_STRUCTURE = 1` (SDHC/SDXC). This card reports `CSD_STRUCTURE = 0` (SDSC v1.0). This is the cleanest single differentiator between this card and any other we have data on.
- **Industrial-line card from June 2007.** SanDisk's SU series was their early-era industrial-grade microSD line. "Industrial" 19 years ago does not equate to "industrial" today — the flash technology and controller are well past their typical retention/wear-leveling design life.
- **Variable timing fields are populated** (TAAC=$26, NSAC=$00, R2W_FACTOR=4). For SDHC cards these are spec-mandated constants ($0E, $00, 2). For SDSC cards they reflect real internal timing — and this card's are slow even by SDSC standards (1.5 ms read access; 24 ms typical write; write = 16× read).
- **VDD current fields populated.** SDSC CSD includes VDD_R_CURR and VDD_W_CURR fields that are removed from SDHC CSD. This card reports up to 100 mA at minimum supply voltage during reads/writes — a substantial draw that should be verified against the user's power supply.
- **Erase block = 16 KB (32 sectors).** Modern SDHC cards report erase block = 64 KB (128 sectors). Smaller erase blocks mean each sector write triggers a smaller read-modify-write internally, but the card has more frequent flash-cycle pressure on any given erase block during sequential writes.
- **TRAN_SPEED = $32 (25 MHz max)** — same as every other catalog card. **TRAN_SPEED does not differentiate this card.** All consumer SD cards report 25 MHz here because that is the SD spec's mandated default-mode ceiling; actual high-speed capability is exposed through CMD6, not TRAN_SPEED.
- **The catalog suggests `CSD_STRUCTURE == 0` is the only register-level signal that uniquely identifies this card class.** A heuristic like "if SDSC, derate SPI to 12.5 MHz" would derate only this card and zero modern cards in the catalog.
- **The card is not necessarily faulty.** macca's earlier testing (pre-v1.5.1, see `2026-05-04-macca-1GB-card-clock-sensitivity.md`) showed the card mounting at sysclk=320 MHz under the audit utility. The v1.5.1 mount-test failures may be a result of running this card at the absolute speed ceiling without margin, not a physical card failure.
