# SD Card Quick Reference — Canonical 2-Line Designators

Every SD card in the project has a canonical 2-line designator derived from register data and the physical label. This file is the single source of truth — the designator block for each card must be character-for-character identical everywhere it appears (card files, CARD-CATALOG.md, Reference/BENCHMARK-RESULTS.md).

**Line 1** — Identity & Filesystem (from CID, CSD, OCR, SCR, MBR registers):
```
<Manufacturer> <ProductName> <CardType> <CapacityGB>GB [<Filesystem>] SD <SpecVersion> rev<Major>.<Minor> SN:<Serial> <Year>/<Month>
```

**Line 2** — Speed & Capabilities (from ACMD13 SD Status + label + SPI):
```
Class <N>, U<N>, V<N>, SPI <Freq> MHz  [<optional notes>]
```

**Note:** Speed class fields on Line 2 currently come from physical label markings. As cards are re-characterized with the updated `SD_card_characterize.spin2` (which now reads ACMD13), Line 2 values will be verified against register data.

---

## Rating A — Video-optimized

### sandisk-sn64g-64gb

**Label:** SanDisk Extreme 64GB U3 A2 microSD XC I V30

```
SanDisk SN64G SDXC 59GB [FAT32] SD 6.x rev8.6 SN:$7E65_0771 2022/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### sandisk-sn128-128gb

**Label:** SanDisk 128GB Nintendo Switch microSD XC I

```
SanDisk SN128 SDXC 119GB [FAT32] SD 6.x rev8.0 SN:F79E34F6 2019/12
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### lexar-mssd0-64gb

**Label:** Lexar A1 V30 U3 64GB microSD XC (Red card)

```
Lexar MSSD0 SDXC 58GB [FAT32] SD 6.x rev6.1 SN:33549024 2024/11
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### lexar-mssd0-128gb

**Label:** Lexar PLAY A2 128GB microSD XC (Blue card)

```
Lexar MSSD0 SDXC 117GB [FAT32] SD 6.x rev6.1 SN:34490F1E 2025/04
Class 10, U3, A2, V30, SPI 25 MHz  [formatted by P2FMTER]
```

### samsung-jd1y7-128gb

**Label:** Samsung Pro Endurance microSD XC I U3 V30

```
Samsung JD1Y7 SDXC 119GB [FAT32] SD 6.x rev3.0 SN:D27654A6 2025/12
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### amazon-basics-usd00-64gb

**Label:** Amazon Basics microSD XC I (10) U3 A2 V30

```
Longsys/Lexar USD00 SDXC 58GB [FAT32] SD 6.x rev2.0 SN:$3584_1E2E 2025/07
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

### sandisk-sh32g-32gb

**Label:** SanDisk MAX ENDURANCE microSD HC I U3 V30 (10)

```
SanDisk SH32G SDHC 29GB [FAT32] SD 6.x rev8.0 SN:$5BFE_CCD8 2025/08
Class 10, U3, A2, V30, SPI 25 MHz  [P2FMTER]
```

---

## Rating B — Fast

### samsung-gd4qt-128gb

**Label:** Samsung EVO Select microSD XC I U3

```
Samsung GD4QT SDXC 119GB [FAT32] SD 3.x rev3.0 SN:C0305565 2018/05
Class 10, U3, SPI 25 MHz  [formatted by P2FMTER]
```

### sandisk-aggcf-128gb

**Label:** SanDisk Extreme PRO 128GB microSD XC I V30 U3 A1

```
SanDisk AGGCF SDXC 119GB [FAT32] SD 5.x rev8.0 SN:E05C352B 2017/07
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

### sandisk-aggce-64gb

**Label:** SanDisk Extreme PRO 64GB microSD XC I V30 U3

```
SanDisk AGGCE SDXC 59GB [FAT32] SD 5.x rev8.0 SN:DD1C1144 2017/03
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

### gigastone-astc-64gb

**Label:** Gigastone "Camera Plus" microSD XC I, A1 V30 U3 64GB

```
Gigastone ASTC SDXC 58GB [FAT32] SD 6.x rev2.0 SN:00000F14 2023/06
Class 10, U3, V30, SPI 25 MHz  [formatted by P2FMTER]
```

### sandisk-sa16g-16gb

**Label:** SanDisk Industrial microSD HC I, U1 C10, 16GB

```
SanDisk SA16G SDHC 14GB [FAT32] SD 5.x rev8.0 SN:93E9C0A1 2025/11
Class 10, U1, V10, SPI 25 MHz
```

### wd-wx64g-64gb

**Label:** Western Digital WD Purple QD101 microSD XC I U1 (10) 64GB

```
SanDisk WX64G SDXC 59GB [FAT32] SD 6.x rev8.0 SN:$EEBA_D6C0 2024/03
Class 10, U1, A2, V10, SPI 25 MHz  [P2FMTER]
```

### siliconpower-spcc-64gb

**Label:** SP Elite microSD XC UHS-I U1 (10)

```
SharedOEM SPCC SDXC 57GB [FAT32] SD 6.x rev0.7 SN:00940105 2025/07
Class 10, U3, A1, V30, SPI 25 MHz  [P2FMTER]
```

**STATUS: BLOCKED** — CMD18 multi-block read times out; mount fails. See [card file](cards/siliconpower-spcc-64gb.md) and PUNCH-LIST.md.

---

## Rating C — Standard

### gigastone-00000-32gb

**Label:** Gigastone 32GB microSD HC I A1 U1 (10)

```
Gigastone 00000 SDHC 29GB [FAT32] SD 3.x rev0.0 SN:000001C9 2023/07
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

### gigastone-00000-8gb

**Label:** Gigastone 10x High Endurance 8GB MLC microSD HC I U1

```
Gigastone 00000 SDHC 7GB [FAT32] SD 3.x rev0.0 SN:0001B9D5 2021/09
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

### gigastone-sd16g-16gb

**Label:** Gigastone 10x High Endurance 16GB MLC microSD HC I U3 V30 4K

```
Budget OEM SD16G SDHC 14GB [FAT32] SD 3.x rev2.0 SN:000003FB 2025/02
Class 10, U1, V10, SPI 25 MHz  [formatted by P2FMTER]
```

### kingston-sd8gb-8gb

**Label:** Kingston 8GB microSD HC I ui (10) "Taiwan"

```
Kingston SD8GB SDHC 7GB [FAT32] SD 3.x rev3.0 SN:43F65DC9 2015/04
Class 10, U1, SPI 25 MHz
```

### sandisk-su08g-8gb

**Label:** microSD HC 8GB (4) - Chinese text, no brand - Card #1

```
SanDisk SU08G SDHC 7GB [FAT32] SD 3.x rev8.0 SN:0AA81F11 2010/10
Class 4, SPI 25 MHz
```

### samsung-00000-8gb

**Label:** Unlabeled 8GB microSD (Chinese text/no brand) - Card #2

```
Samsung 00000 SDHC 7GB [FAT16] SD 3.x rev1.0 SN:D9FB539C 2014/08
Class 6, SPI 25 MHz
```

### sandisk-ss08g-8gb

**Label:** SanDisk 8GB (4) microSD HC, Made in Taiwan

```
SanDisk SS08G SDHC 7GB [FAT32] SD 3.x rev3.0 SN:DAAEE8AD 2015/09
Class 4, SPI 25 MHz
```

---

## Rating D — Limited

### pny-sd16g-16gb

**Label:** PNY 16GB microSD HC I

```
Phison SD16G SDHC 14GB [FAT32] SD 3.x rev3.0 SN:$01CD_5CF5 2018/08
Class 4, U0, V0, SPI 25 MHz  [P2FMTER]
```

---

### Sony SR-16UY 16GB (Phison)

**Label:** Sony 16GB microSD HC (10) i U3 SR-16D, Made in Taiwan

```
Phison SD16G SDHC 14GB [FAT32] SD 4.x rev3.0 SN:DA00094B 2016/10
Class 10, U3, V0, SPI 25 MHz
```

---

## Re-characterization Status

Cards that need to be re-run through the updated `SD_card_characterize.spin2` to get verified ACMD13 data for Line 2:

| Card | ACMD13 Status | Line 2 Source | Benchmark |
|------|:---:|---|:---:|
| sandisk-sn64g-64gb | **verified** | ACMD13 (Class 10, U3, A2, V30) | 350+250 (re-run) |
| sandisk-sn128-128gb | **verified** | ACMD13 (Class 10, U3, A2, V30) | 350+250 |
| lexar-mssd0-64gb | **verified** | ACMD13 (Class 10, U3, A2, V30) — label says A1; different unit SN:33549024 | 350+250 |
| lexar-mssd0-128gb | **verified** | ACMD13 (Class 10, U3, A2, V30) | 350+250 |
| samsung-gd4qt-128gb | **verified** | ACMD13 (Class 10, U3, V0) — different unit SN:4AC85F42 | 350+250 |
| sandisk-aggcf-128gb | **verified** | ACMD13 (Class 10, U3, V30) | 350+250 |
| sandisk-aggce-64gb | **verified** | ACMD13 (Class 10, U3, V30) | 350+250 |
| gigastone-astc-64gb | **verified** | ACMD13 (Class 10, U3, V30) | 350+250 |
| sandisk-sa16g-16gb | **verified** | ACMD13 (Class 10, U1, V10) — V10 not on label | 350+250 |
| gigastone-00000-32gb | **verified** | ACMD13 (Class 10, U1, V10) — V10 not on label | — |
| gigastone-00000-8gb | **verified** | ACMD13 (Class 10, U1, V10) — Class 10, V10 not on label | — |
| gigastone-sd16g-16gb | **verified** | ACMD13 (Class 10, U1, V10) — label claims U3/V30! | 350+250 |
| kingston-sd8gb-8gb | **verified** | ACMD13 (Class 10, U1, V0) — U1 not on label | — |
| sandisk-su08g-8gb | **verified** | ACMD13 (Class 4, U0, V0) | — |
| samsung-00000-8gb | **verified** | ACMD13 (Class 6, U0, V0) — FAT16, format failed | — |
| sandisk-ss08g-8gb | **verified** | ACMD13 (Class 4, U0, V0) | — |
| pny-sd16g-16gb | **verified** | ACMD13 (Class 4, U0, V0) | 350+250 |
| wd-wx64g-64gb | **verified** | ACMD13 (Class 10, U1, A2, V10) | 350+250 |
| siliconpower-spcc-64gb | **verified** | ACMD13 (Class 10, U3, A1, V30) — label says U1 | **--** |
| samsung-jd1y7-128gb | **verified** | ACMD13 (Class 10, U3, A2, V30) | 350+250 |
| amazon-basics-usd00-64gb | **verified** | ACMD13 (Class 10, U3, A2, V30) | 350+250 |
| sandisk-sh32g-32gb | **verified** | ACMD13 (Class 10, U3, A2, V30) | 350+250 |

---

*Created: 2026-02-15*
*Cards: 22*
