# SD Card Catalog

This catalog documents SD cards tested with the P2 SD card driver. Cards are characterized using the `SD_card_characterize.spin2` diagnostic tool. Each card has a dedicated page in [DOCs/cards/](cards/) with full register dumps, field decodes, and test results.

---

## Register Field Reference

This section documents ALL fields available from SD card registers and indicates which are actively used by the driver.

- **[USED]** = Field is actively used by the driver for operation
- **[INFO]** = Informational only - available but not used by driver

### CID Register (Card Identification) - 16 bytes

| Field | Bits | Size | Usage | Description |
|-------|------|------|-------|-------------|
| MID | [127:120] | 8 bits | [INFO] | Manufacturer ID - recorded for card identification; does not affect driver operation |
| OID | [119:104] | 16 bits | [INFO] | OEM/Application ID (2 ASCII chars) |
| PNM | [103:64] | 40 bits | [INFO] | Product Name (5 ASCII chars) |
| PRV | [63:56] | 8 bits | [INFO] | Product Revision (BCD: major.minor) |
| PSN | [55:24] | 32 bits | [INFO] | Product Serial Number |
| MDT | [19:8] | 12 bits | [INFO] | Manufacturing Date (year + month) |
| CRC7 | [7:1] | 7 bits | [INFO] | CRC checksum |

**Driver Usage:** MID is read and exposed via `getManufacturerID()` for card identification only. The driver applies **no manufacturer-specific behavior** — SPI speed is `min(TRAN_SPEED, 25 MHz)` for every card regardless of brand.

> **Note (audited 2026-05-18):** Earlier revisions of this catalog and the driver comments claimed MID `$27` (Phison/PNY) triggered a 20 MHz SPI cap. This was never implemented — it originated as a *proposal* in `DOCs/Research/PNY-MICROSD-SPI-ISSUES.md` (Jan 2026). Characterization showed every Phison/`$27` card runs reliably at 25 MHz, so the per-brand speed cap was evaluated and **deliberately not adopted**. The stale claims were removed.

### CSD Register (Card Specific Data) - 16 bytes

| Field | Bits | Size | Usage | Description |
|-------|------|------|-------|-------------|
| CSD_STRUCTURE | [127:126] | 2 bits | **[USED]** | CSD version: 0=v1.0 (SDSC), 1=v2.0 (SDHC/SDXC) |
| TAAC | [119:112] | 8 bits | **[USED]** | Data read access time-1 (for timeout calculation) |
| NSAC | [111:104] | 8 bits | **[USED]** | Data read access time-2 in CLK cycles |
| TRAN_SPEED | [103:96] | 8 bits | **[USED]** | Max data transfer rate (determines SPI clock) |
| CCC | [95:84] | 12 bits | [INFO] | Card Command Classes supported |
| READ_BL_LEN | [83:80] | 4 bits | [INFO] | Max read data block length (always 9=512 bytes) |
| READ_BL_PARTIAL | [79] | 1 bit | [INFO] | Partial blocks for read allowed |
| WRITE_BLK_MISALIGN | [78] | 1 bit | [INFO] | Write block misalignment |
| READ_BLK_MISALIGN | [77] | 1 bit | [INFO] | Read block misalignment |
| DSR_IMP | [76] | 1 bit | [INFO] | DSR implemented |
| **CSD v1.0 only (SDSC):** |
| C_SIZE | [73:62] | 12 bits | **[USED]** | Device size (SDSC capacity calculation) |
| VDD_R_CURR_MIN | [61:59] | 3 bits | [INFO] | Max read current @ VDD min |
| VDD_R_CURR_MAX | [58:56] | 3 bits | [INFO] | Max read current @ VDD max |
| VDD_W_CURR_MIN | [55:53] | 3 bits | [INFO] | Max write current @ VDD min |
| VDD_W_CURR_MAX | [52:50] | 3 bits | [INFO] | Max write current @ VDD max |
| C_SIZE_MULT | [49:47] | 3 bits | **[USED]** | Device size multiplier (SDSC capacity) |
| **CSD v2.0 only (SDHC/SDXC):** |
| C_SIZE | [69:48] | 22 bits | **[USED]** | Device size (capacity = (C_SIZE+1) × 512KB) |
| **Common fields (both versions):** |
| ERASE_BLK_EN | [46] | 1 bit | [INFO] | Erase single block enable |
| SECTOR_SIZE | [45:39] | 7 bits | [INFO] | Erase sector size |
| WP_GRP_SIZE | [38:32] | 7 bits | [INFO] | Write protect group size |
| WP_GRP_ENABLE | [31] | 1 bit | [INFO] | Write protect group enable |
| R2W_FACTOR | [28:26] | 3 bits | **[USED]** | Write speed factor (write time = read time × 2^R2W) |
| WRITE_BL_LEN | [25:22] | 4 bits | [INFO] | Max write data block length |
| WRITE_BL_PARTIAL | [21] | 1 bit | [INFO] | Partial blocks for write allowed |
| FILE_FORMAT_GRP | [15] | 1 bit | [INFO] | File format group |
| COPY | [14] | 1 bit | [INFO] | Copy flag |
| PERM_WRITE_PROTECT | [13] | 1 bit | [INFO] | Permanent write protection |
| TMP_WRITE_PROTECT | [12] | 1 bit | [INFO] | Temporary write protection |
| FILE_FORMAT | [11:10] | 2 bits | [INFO] | File format |
| CRC7 | [7:1] | 7 bits | [INFO] | CRC checksum |

**Driver Usage:**
- CSD_STRUCTURE determines SDSC vs SDHC/SDXC capacity formulas
- TRAN_SPEED calculates maximum SPI clock frequency
- TAAC/NSAC/R2W_FACTOR calculate read/write timeouts (SDSC only)
- C_SIZE + multipliers calculate card capacity in sectors

### SCR Register (SD Configuration) - 8 bytes

| Field | Bits | Size | Usage | Description |
|-------|------|------|-------|-------------|
| SCR_STRUCTURE | [63:60] | 4 bits | [INFO] | SCR structure version |
| SD_SPEC | [59:56] | 4 bits | **[USED]** | SD Physical Layer spec version |
| DATA_STAT_AFTER_ERASE | [55] | 1 bit | [INFO] | Data status after erase |
| SD_SECURITY | [54:52] | 3 bits | [INFO] | CPRM security support |
| SD_BUS_WIDTHS | [51:48] | 4 bits | [INFO] | DAT bus widths supported (bit 0=1-bit, bit 2=4-bit) |
| SD_SPEC3 | [47] | 1 bit | [INFO] | SD spec 3.0 support |
| EX_SECURITY | [46:43] | 4 bits | [INFO] | Extended security support |
| SD_SPEC4 | [42] | 1 bit | [INFO] | SD spec 4.0 support |
| SD_SPECX | [41:38] | 4 bits | [INFO] | SD spec 5.x/6.x/7.x indicator |
| CMD_SUPPORT | [33:32] | 2 bits | [INFO] | Command support bits |

**Driver Usage:** SD_SPEC determines High Speed (CMD6) support availability.

### OCR Register (Operating Conditions) - 4 bytes

| Field | Bits | Size | Usage | Description |
|-------|------|------|-------|-------------|
| Power Up Status | [31] | 1 bit | [INFO] | Card power up status (1=ready) |
| CCS | [30] | 1 bit | **[USED]** | **CRITICAL** - Card Capacity Status |
| UHS-II Status | [29] | 1 bit | [INFO] | UHS-II card status |
| S18A | [24] | 1 bit | [INFO] | Switching to 1.8V accepted |
| Voltage Window | [23:15] | 9 bits | [INFO] | Supported voltage range (2.7V-3.6V) |

**Driver Usage:** CCS bit is **CRITICAL** - determines addressing mode:
- CCS=0: SDSC byte addressing (sector << 9)
- CCS=1: SDHC/SDXC block addressing (sector number directly)

### Summary: Fields Used by Driver

| Register | Field | Purpose |
|----------|-------|---------|
| CSD | CSD_STRUCTURE | SDSC vs SDHC/SDXC formulas |
| CSD | TRAN_SPEED | SPI clock frequency |
| CSD | TAAC | Read timeout (SDSC) |
| CSD | NSAC | Read timeout (SDSC) |
| CSD | R2W_FACTOR | Write timeout calculation |
| CSD | C_SIZE | Capacity calculation |
| CSD | C_SIZE_MULT | Capacity calculation (SDSC) |
| SCR | SD_SPEC | High Speed (CMD6) support |
| OCR | CCS | **Addressing mode** (byte vs block) |

---

## Summary Table

**Speed Rating Key** (based on register values, not marketing claims):
- **A** = Video-optimized (CCC=$DB7 with Classes 1+11 for sustained writes)
- **B** = Fast (Premium brand, SD 4.xx spec, 25 MHz)
- **C** = Standard (SD 3.0x spec, 25 MHz)
- **D** = Limited (markedly low *measured* internal throughput, e.g. < 100 KB/s; runs at 25 MHz like every card — the card's own controller, not the SPI bus, is the bottleneck)
- **E** = SDSC class (CSD v1.0, pre-2010 architecture, recommend ≤ 12.5 MHz)

> **Note (audited 2026-05-18):** Rating **D** previously read "MID $27 triggers 20 MHz SPI limit." That MID-based SPI derate was never implemented in the driver and has been removed (see Driver Usage note above). **D** is now defined by measured throughput.

| Card ID | Manufacturer | Product | Capacity | Speed | Test Status |
|---------|-------------|---------|----------|:-----:|-------------|
| SanDisk_SN64G_8.6_7E650771_202211 | SanDisk ($03) | SN64G | 64 GB | **A** | PASS |
| SanDisk_SN128_8.0_F79E34F6_201912 | SanDisk ($03) | SN128 | 128 GB | **A** | PASS |
| Longsys/Lexar_MSSD0_6.1_33549024_202411 | Lexar (Longsys $AD) | MSSD0 | 64 GB | **A** | PASS |
| Longsys/Lexar_MSSD0_6.1_34490F1E_202504 | Lexar (Longsys $AD) | MSSD0 | 128 GB | **A** | PASS |
| Samsung_JD1Y7_3.0_D27654A6_202512 | Samsung ($1B) | JD1Y7 | 128 GB | **A** | PASS |
| Samsung_GD4QT_3.0_C0305565_201805 | Samsung ($1B) | GD4QT | 128 GB | **B** | PASS |
| SanDisk_AGGCF_8.0_E05C352B_201707 | SanDisk ($03) | AGGCF | 128 GB | **B** | PASS |
| SanDisk_AGGCE_8.0_DD1C1144_201703 | SanDisk ($03) | AGGCE | 64 GB | **B** | PASS |
| GigastoneOEM_ASTC_2.0_00000F14_202306 | Gigastone (OEM $12) | ASTC | 64 GB | **B** | PASS |
| SanDisk_SA16G_8.0_93E9C0A1_202511 | SanDisk ($03) | SA16G | 16 GB | **B** | PASS |
| Transcend_00000_0.0_000001C9_202307 | Gigastone (Transcend $74) | 00000 | 32 GB | **C** | PASS |
| Unknown_00000_0.0_0001B9D5_202109 | Gigastone (Shared OEM $9F) | 00000 | 8 GB | **C** | PASS |
| BudgetOEM_SD16G_2.0_000003FB_202502 | Gigastone (Budget OEM $00) | SD16G | 16 GB | **C** | PASS |
| Kingston_SD8GB_3.0_43F65DC9_201504 | Kingston ($41) | SD8GB | 8 GB | **C** | PASS |
| SanDisk_SU08G_8.0_0AA81F11_201010 | Unknown (claims SanDisk $03) - Chinese #1 | SU08G | 8 GB | **C** | PASS |
| Samsung_00000_1.0_D9FB539C_201408 | Samsung ($1B) - Chinese #2 | 00000 | 8 GB | **C** | PASS |
| SanDisk_SS08G_3.0_DAAEE8AD_201509 | SanDisk ($03) - Taiwan | SS08G | 8 GB | **C** | PASS |
| SharedOEM_SPCC_0.7_00940105_202507 | Silicon Power (Shared OEM $9F) | SPCC | 64 GB | **A** | PASS |
| Longsys/Lexar_USD00_2.0_35841E2E_202507 | Amazon Basics (Longsys $AD) | USD00 | 64 GB | **A** | PASS |
| SanDisk_SH32G_8.0_5BFECCD8_202508 | SanDisk ($03) | SH32G | 32 GB | **A** | PASS |
| SanDisk_WX64G_8.0_EEBAD6C0_202403 | SanDisk ($03) — WD subsidiary | WX64G | 64 GB | **A** | PASS |
| Phison_SD16G_3.0_01CD5CF5_201808 | PNY (Phison $27) | SD16G | 16 GB | **D** | PASS |
| Phison_SD16G_3.0_DA00094B_201610 | Sony (Phison $27) - Taiwan | SD16G | 16 GB | **D** | PASS |
| SanDisk_SU01G_8.0_006CD5B2_200706 | SanDisk ($03) — Industrial SDSC | SU01G | 1 GB | **E** | **FAIL** (v1.5.1, 350 MHz) |

---

## Internal Throughput Summary

Cards tested with `diagnostic-tests/SD_speed_characterize.spin2` have measured internal throughput data. This reflects the card's internal flash/controller performance, NOT the SPI bus speed.

**Test Methodology:**
- 10,000 random single-sector reads at 25 MHz SPI
- CRC-16 verification on every read
- Throughput = sectors read / elapsed time

**Performance Class Definitions:**
- **HIGH** = >500 KB/s (fast controller, suitable for demanding applications)
- **MEDIUM** = 100-500 KB/s (adequate for most embedded uses)
- **LOW** = <100 KB/s (slow controller, SPI clock not the bottleneck)

| Card | Manufacturer | Capacity | Throughput | Latency | Class | Max SPI |
|------|-------------|----------|------------|---------|-------|---------|
| Longsys_USD00 | Amazon Basics ($AD) | 64 GB | — | — | — | not yet tested |
| SanDisk_SN64G | SanDisk ($03) | 64 GB | — | — | — | not yet tested |
| SanDisk_SN128 | SanDisk ($03) | 128 GB | **780 KB/s** | 0.66 ms | HIGH | 25 MHz |
| Longsys_MSSD0 | Lexar ($AD) | 64 GB | **1,059 KB/s** | 0.48 ms | HIGH | 25 MHz |
| Samsung_GD4QT | Samsung ($1B) | 128 GB | **783 KB/s** | 0.65 ms | HIGH | 25 MHz |
| SanDisk_AGGCF | SanDisk ($03) | 128 GB | — | — | — | not yet tested |
| SanDisk_AGGCE | SanDisk ($03) | 64 GB | **866 KB/s** | 0.59 ms | HIGH | 25 MHz |
| GigastoneOEM_ASTC | Gigastone ($12) | 64 GB | **944 KB/s** | 0.54 ms | HIGH | 25 MHz |
| SanDisk_SA16G | SanDisk ($03) | 16 GB | **824 KB/s** | 0.62 ms | HIGH | 25 MHz |
| Transcend_00000 | Gigastone ($74) | 32 GB | — | — | — | not yet tested |
| Unknown_00000 | Gigastone ($9F) | 8 GB | — | — | — | not yet tested |
| BudgetOEM_SD16G | Gigastone ($00) | 16 GB | **368 KB/s** | 1.39 ms | MEDIUM | 25 MHz |
| Kingston_SD8GB | Kingston ($41) | 8 GB | — | — | — | not yet tested |
| SanDisk_SU08G | Chinese #1 ($03) | 8 GB | — | — | — | not yet tested |
| Samsung_00000 | Chinese #2 ($1B) | 8 GB | — | — | — | not yet tested |
| SanDisk_SS08G | SanDisk Taiwan ($03) | 8 GB | **687 KB/s** | 0.75 ms | MED | 25 MHz |
| SharedOEM_SPCC | Silicon Power ($9F) | 64 GB | **967 KB/s** | 0.53 ms | HIGH | 25 MHz |
| SanDisk_SH32G | SanDisk ($03) | 32 GB | **~951 KB/s** | 0.54 ms | HIGH | 25 MHz |
| SanDisk_WX64G | WD Purple ($03) | 64 GB | — | — | — | not yet tested |
| Phison_SD16G (PNY) | PNY ($27) | 16 GB | **31.3 KB/s** | 16.0 ms | LOW | 25 MHz |
| Phison_SD16G (Sony) | Sony ($27) | 16 GB | **714 KB/s** | 0.72 ms | MED | 25 MHz |

**Tested: 12 of 23 cards**

**Key Observations:**
1. **Lexar V30 U3 64GB** - **Fastest card tested** (1,059 KB/s), 12% faster than SP Elite
2. **Silicon Power Elite 64GB** - Very fast (967 KB/s), CMD12 anomaly handled by driver tolerance
3. **Gigastone Camera Plus 64GB** - Very fast (944 KB/s), excellent value
4. **SanDisk Extreme PRO 64GB** - High performance (866 KB/s), professional line
5. **SanDisk Industrial 16GB** - High performance (824 KB/s), industrial/embedded grade
6. **Samsung EVO Select 128GB** - High performance (783 KB/s), nearly identical to SanDisk
7. **SanDisk Nintendo Switch 128GB** - High performance (780 KB/s), designed for gaming
8. **Gigastone High Endurance 16GB** - Medium performance (368 KB/s), MLC flash endurance focus
9. **PNY 16GB** - Slow internal controller (31 KB/s); runs reliably at 25 MHz SPI but throughput limited by internal latency
10. All tested cards max out at 25 MHz SPI (CMD6 High Speed switch fails on all)

---

## Card Details

Each card has a dedicated page with full register dumps, field-by-field decode, filesystem info, test results, notes, and (where tested) SPI speed characterization and internal throughput data. The 2-line designator for each card is from [CARD-REFERENCE.md](CARD-REFERENCE.md).

**Rating A** - Video-optimized:

**SanDisk Extreme 64GB SDXC** — [sandisk-sn64g-64gb.md](cards/sandisk-sn64g-64gb.md)
```
SanDisk SN64G SDXC 59GB [FAT32] SD 6.x rev8.6 SN:$7E65_0771 2022/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**SanDisk Nintendo Switch 128GB SDXC** — [sandisk-sn128-128gb.md](cards/sandisk-sn128-128gb.md)
```
SanDisk SN128 SDXC 119GB [FAT32] SD 6.x rev8.0 SN:F79E34F6 2019/12
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**Lexar MicroSD XC A1 V30 U3 64GB** — [lexar-mssd0-64gb.md](cards/lexar-mssd0-64gb.md)
```
Lexar MSSD0 SDXC 58GB [FAT32] SD 6.x rev6.1 SN:33549024 2024/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**Lexar PLAY A2 128GB SDXC** — [lexar-mssd0-128gb.md](cards/lexar-mssd0-128gb.md)
```
Lexar MSSD0 SDXC 117GB [FAT32] SD 6.x rev6.1 SN:34490F1E 2025/04
Class 10, U3, A2, V30, SPI 25 MHz  [formatted by P2FMTER]
```

**Samsung PRO Endurance 128GB SDXC** — [samsung-jd1y7-128gb.md](cards/samsung-jd1y7-128gb.md)
```
Samsung JD1Y7 SDXC 119GB [FAT32] SD 6.x rev3.0 SN:D27654A6 2025/12
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**Amazon Basics 64GB SDXC** — [amazon-basics-usd00-64gb.md](cards/amazon-basics-usd00-64gb.md)
```
Longsys/Lexar USD00 SDXC 58GB [FAT32] SD 6.x rev2.0 SN:$3584_1E2E 2025/07
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**SanDisk MAX Endurance 32GB SDHC** — [sandisk-sh32g-32gb.md](cards/sandisk-sh32g-32gb.md)
```
SanDisk SH32G SDHC 29GB [FAT32] SD 6.x rev8.0 SN:$5BFE_CCD8 2025/08
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

**Western Digital WD Purple QD101 64GB SDXC** — [wd-wx64g-64gb.md](cards/wd-wx64g-64gb.md)
```
SanDisk WX64G SDXC 59GB [FAT32] SD 6.x rev8.0 SN:$EEBA_D6C0 2024/03
Class 10, U1, A2, V10, SPI 25 MHz  [P2FMTER]
```

**Rating B** - Fast:

**Silicon Power Elite 64GB SDXC** — [siliconpower-spcc-64gb.md](cards/siliconpower-spcc-64gb.md)
```
SharedOEM SPCC SDXC 57GB [FAT32] SD 6.x rev0.7 SN:00940105 2025/07
Class 10, U3, A1, V30, SPI 25 MHz  [P2FMTER]
```

**Samsung EVO Select 128GB SDXC** — [samsung-gd4qt-128gb.md](cards/samsung-gd4qt-128gb.md)
```
Samsung GD4QT SDXC 119GB [FAT32] SD 3.x rev3.0 SN:C0305565 2018/05
Class 10, U3, SPI 25 MHz  [formatted by P2FMTER]
```

**SanDisk Extreme PRO 128GB SDXC** — [sandisk-aggcf-128gb.md](cards/sandisk-aggcf-128gb.md)
```
SanDisk AGGCF SDXC 119GB [FAT32] SD 5.x rev8.0 SN:E05C352B 2017/07
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

**SanDisk Extreme PRO 64GB SDXC** — [sandisk-aggce-64gb.md](cards/sandisk-aggce-64gb.md)
```
SanDisk AGGCE SDXC 59GB [FAT32] SD 5.x rev8.0 SN:DD1C1144 2017/03
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

**Gigastone "Camera Plus" 64GB SDXC** — [gigastone-astc-64gb.md](cards/gigastone-astc-64gb.md)
```
Gigastone ASTC SDXC 58GB [FAT32] SD 6.x rev2.0 SN:00000F14 2023/06
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

**SanDisk Industrial 16GB SDHC** — [sandisk-sa16g-16gb.md](cards/sandisk-sa16g-16gb.md)
```
SanDisk SA16G SDHC 14GB [FAT32] SD 5.x rev8.0 SN:93E9C0A1 2025/11
Class 10, U1, V10, SPI 25 MHz
```

**Rating C** - Standard:

**Gigastone 32GB SDHC** — [gigastone-00000-32gb.md](cards/gigastone-00000-32gb.md)
```
Gigastone 00000 SDHC 29GB [FAT32] SD 3.x rev0.0 SN:000001C9 2023/07
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

**Gigastone "High Endurance" 8GB SDHC MLC** — [gigastone-00000-8gb.md](cards/gigastone-00000-8gb.md)
```
Gigastone 00000 SDHC 7GB [FAT32] SD 3.x rev0.0 SN:0001B9D5 2021/09
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

**Gigastone "High Endurance" 16GB SDHC MLC** — [gigastone-sd16g-16gb.md](cards/gigastone-sd16g-16gb.md)
```
Budget OEM SD16G SDHC 14GB [FAT32] SD 3.x rev2.0 SN:000003FB 2025/02
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

**Kingston 8GB SDHC** — [kingston-sd8gb-8gb.md](cards/kingston-sd8gb-8gb.md)
```
Kingston SD8GB SDHC 7GB [FAT32] SD 3.x rev3.0 SN:43F65DC9 2015/04
Class 10, U1, SPI 25 MHz
```

**"Chinese Made" #1 8GB SDHC (claims SanDisk)** — [sandisk-su08g-8gb.md](cards/sandisk-su08g-8gb.md)
```
SanDisk SU08G SDHC 7GB [FAT32] SD 3.x rev8.0 SN:0AA81F11 2010/10
Class 4, SPI 25 MHz
```

**"Chinese Made" #2 8GB SDHC (Samsung inside)** — [samsung-00000-8gb.md](cards/samsung-00000-8gb.md)
```
Samsung 00000 SDHC 7GB [FAT16] SD 3.x rev1.0 SN:D9FB539C 2014/08
Class 6, SPI 25 MHz
```

**SanDisk 8GB SDHC (Taiwan)** — [sandisk-ss08g-8gb.md](cards/sandisk-ss08g-8gb.md)
```
SanDisk SS08G SDHC 7GB [FAT32] SD 3.x rev3.0 SN:DAAEE8AD 2015/09
Class 4, SPI 25 MHz
```

**Rating D** - Limited:

**PNY 16GB SDHC** — [pny-sd16g-16gb.md](cards/pny-sd16g-16gb.md)
```
Phison SD16G SDHC 14GB [FAT32] SD 3.x rev3.0 SN:$01CD_5CF5 2018/08
Class 4, U0, V0, SPI 25 MHz  [P2FMTER]
```

---

## Template for New Cards

Create a new file in `DOCs/cards/` named `brand-product-capacity.md` (e.g., `sandisk-sn64g-64gb.md`).
Use the product name from the CID register (PNM field) and lowercase the brand.

```markdown
# Card: [Brand] [Model] [Capacity]

**Unique ID:** `[Manufacturer]_[ProductName]_[Rev]_[Serial]_[YYYYMM]`
**Test Date:** YYYY-MM-DD

### Hardware Identification

| Field | Value |
|-------|-------|
| Manufacturer ID | $XX ([Name]) |
| OEM/Application | $XX $XX |
| Product Name | [name] |
| Product Revision | X.X |
| Serial Number | $XXXX_XXXX |
| Manufacturing Date | [Month] [Year] |

### Card Capabilities

| Field | Value |
|-------|-------|
| CSD Version | X.0 |
| Card Type | [SDSC/SDHC/SDXC] |
| Capacity | ~XX GB |
| Total Sectors | XXX,XXX,XXX |
| SD Spec Version | X.Xx |
| Bus Width Support | 1-bit, 4-bit |

### Raw Registers

```
CID: [16 bytes hex]
CSD: [16 bytes hex]
OCR: $XXXX_XXXX
SCR: [8 bytes hex]
```

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| Card Init | ? | |
| Mount | ? | |
| Read | ? | |
| Write | ? | |
| Seek | ? | |
| Format | ? | |

### Notes

- [Any observations about this card]
```

---

## Known Manufacturer IDs (Heuristic)

**Note:** This table is heuristic - mappings are inferred from observed CIDs and may change as OEM relationships shift. Source: Matt Cole's survey + CID/OEM compilation.

| MID | OID | Manufacturer/Controller | Example Brands |
|-----|-----|------------------------|----------------|
| $00 | "42" | Unknown OEM, many rebrands | Gigastone, Patriot, fake cards |
| $02 | "TM" | Kioxia (Toshiba) | Toshiba, Kioxia |
| $03 | "SD" | SanDisk / Western Digital | SanDisk, WD |
| $09 | "AP" | ATP Electronics | ATP industrial |
| $12 | "4V" | Patriot-related OEM | Patriot, Gigastone |
| $1B | "SM" | Samsung | Samsung EVO/PRO |
| $1D | "AD" | ADATA | ADATA retail |
| $27 | "PH" | Phison controller family | Delkin, HP, Kingston, Lexar (older), PNY |
| $28 | "BE" | Lexar (pre-Longsys) | Older Lexar cards |
| $31 | — | Silicon Power | Silicon Power |
| $41 | — | Kingston | Kingston |
| $45 | "-B" | TEAMGROUP | TEAMGROUP |
| $6F | $0303 | Hiksemi / Longsys-related | Hiksemi, HP, Kodak, Lenovo, Netac |
| $74 | $4A60 | Gigastone / Transcend OEM | Gigastone, Transcend |
| $76 | — | Patriot Memory | Patriot |
| $82 | — | Sony | Sony |
| $89 | $0303 | Netac | Netac |
| $9C | — | Angelbird / Hoodman | Angelbird, Hoodman |
| $9F | "TI" | Shared OEM (many brands) | Amazon, Kingston, Kodak, Silicon Power |
| $AD | "LS" | Longsys | Amazon Basics, newer Lexar, RPi |
| $FE | "42" | Unknown OEM, budget brands | HP, ORICO, TEAMGROUP, fake SanDisk |

---

*Catalog created: 2026-01-20*
*Last updated: 2026-02-25*
*Cards cataloged: 22 (individual card pages in [DOCs/cards/](cards/))*
