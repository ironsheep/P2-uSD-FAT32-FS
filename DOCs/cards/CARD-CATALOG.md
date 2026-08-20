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

> **Label text is not mastered here.** The `Label` column is a **cache** of
> [CARD-LABELS.md](CARD-LABELS.md), kept inline because this table has to be
> scannable at a glance. Edit the master, never this column;
> `tools/check_card_labels.sh` fails if a single character diverges.


**Speed Rating Key** (based on register values, not marketing claims):
- **A** = Video-optimized (CCC=$DB7 with Classes 1+11 for sustained writes)
- **B** = Fast (Premium brand, SD 4.xx spec, 25 MHz)
- **C** = Standard (SD 3.0x spec, 25 MHz)
- **D** = Limited (markedly low *measured* internal throughput, e.g. < 100 KB/s; runs at 25 MHz like every card — the card's own controller, not the SPI bus, is the bottleneck)
- **E** = SDSC class (CSD v1.0, pre-2010 architecture, recommend ≤ 12.5 MHz)

> **Note (audited 2026-05-18):** Rating **D** previously read "MID $27 triggers 20 MHz SPI limit." That MID-based SPI derate was never implemented in the driver and has been removed (see Driver Usage note above). **D** is now defined by measured throughput.

| Card ID | Label (what is printed on the card) | Manufacturer | Product | Capacity | Speed | Test Status |
|---------|-------------------------------------|-------------|---------|----------|:-----:|-------------|
| SanDisk_SN64G_8.6_7E650771_202211 | SanDisk Extreme 64GB U3 A2 microSD XC I V30 | SanDisk ($03) | SN64G | 64 GB | **A** | PASS |
| SanDisk_SN128_8.0_F79E34F6_201912 | SanDisk 128GB Nintendo Switch microSD XC I | SanDisk ($03) | SN128 | 128 GB | **A** | PASS |
| Longsys/Lexar_MSSD0_6.1_33549024_202411 | Lexar A1 V30 U3 64GB microSD XC (Red card) | Lexar (Longsys $AD) | MSSD0 | 64 GB | **A** | PASS |
| Longsys/Lexar_MSSD0_6.1_34490F1E_202504 | Lexar PLAY A2 128GB microSD XC (Blue card) | Lexar (Longsys $AD) | MSSD0 | 128 GB | **A** | PASS |
| Samsung_JD1Y7_3.0_D27654A6_202512 | Samsung Pro Endurance microSD XC I U3 V30 | Samsung ($1B) | JD1Y7 | 128 GB | **A** | PASS |
| Samsung_GD4QT_3.0_C0305565_201805 | Samsung EVO Select microSD XC I U3 | Samsung ($1B) | GD4QT | 128 GB | **B** | PASS |
| SanDisk_AGGCF_8.0_E05C352B_201707 | SanDisk Extreme PRO 128GB microSD XC I V30 U3 A1 | SanDisk ($03) | AGGCF | 128 GB | **B** | PASS |
| SanDisk_AGGCE_8.0_DD1C1144_201703 | SanDisk Extreme PRO 64GB microSD XC I V30 U3 | SanDisk ($03) | AGGCE | 64 GB | **B** | PASS |
| GigastoneOEM_ASTC_2.0_00000F14_202306 | Gigastone "Camera Plus" microSD XC I, A1 V30 U3 64GB | Gigastone (OEM $12) | ASTC | 64 GB | **B** | PASS |
| SanDisk_SA16G_8.0_93E9C0A1_202511 | SanDisk Industrial microSD HC I, U1 C10, 16GB | SanDisk ($03) | SA16G | 16 GB | **B** | PASS |
| Transcend_00000_0.0_000001C9_202307 | Gigastone 32GB microSD HC I A1 U1 (10) | Gigastone (Transcend $74) | 00000 | 32 GB | **C** | PASS |
| Unknown_00000_0.0_0001B9D5_202109 | Gigastone 10x High Endurance 8GB MLC microSD HC I U1 | Gigastone (Shared OEM $9F) | 00000 | 8 GB | **C** | PASS |
| BudgetOEM_SD16G_2.0_000003FB_202502 | Gigastone 10x High Endurance 16GB MLC microSD HC I U3 V30 4K | Gigastone (Budget OEM $00) | SD16G | 16 GB | **C** | PASS |
| Kingston_SD8GB_3.0_43F65DC9_201504 | Kingston 8GB microSD HC I ui (10) "Taiwan" F(c)o | Kingston ($41) | SD8GB | 8 GB | **C** | PASS |
| SanDisk_SU08G_8.0_0AA81F11_201010 | microSD HC 8GB (4) - Chinese text, no brand - Card #1 | Unknown (claims SanDisk $03) - **suspect counterfeit, needs re-characterization** | SU08G | 8 GB | **C** | PASS |
| Samsung_00000_1.0_D9FB539C_201408 | Unlabeled 8GB microSD (Chinese text/no brand) - Card #2 | **LIKELY COUNTERFEIT** — Samsung MID `$1B` with placeholder PNM `"00000"` (brand/PNM mismatch) | 00000 | 8 GB | **C** | PASS |
| SanDisk_SS08G_3.0_DAAEE8AD_201509 | SanDisk 8GB (4) microSD HC, Made in Taiwan | SanDisk ($03) - Taiwan | SS08G | 8 GB | **C** | PASS |
| SharedOEM_SPCC_0.7_00940105_202507 | SP Elite microSD XC UHS-I U1 (10) | Silicon Power (Shared OEM $9F) | SPCC | 64 GB | **A** | PASS |
| Longsys/Lexar_USD00_2.0_35841E2E_202507 | Amazon Basics microSD XC I (10) U3 A2 V30 | Amazon Basics (Longsys $AD) | USD00 | 64 GB | **A** | PASS |
| SanDisk_SH32G_8.0_5BFECCD8_202508 | SanDisk MAX ENDURANCE microSD HC I U3 V30 (10) | SanDisk ($03) | SH32G | 32 GB | **A** | PASS |
| SanDisk_WX64G_8.0_EEBAD6C0_202403 | Western Digital WD Purple QD101 microSD XC I U1 (10) 64GB | SanDisk ($03) — WD subsidiary | WX64G | 64 GB | **A** | PASS |
| Phison_SD16G_3.0_01CD5CF5_201808 | PNY 16GB microSD HC I | PNY (Phison $27) | SD16G | 16 GB | **D** | PASS |
| Phison_SD16G_3.0_DA00094B_201610 | Sony 16GB microSD HC (10) i U3 SR-16D, Made in Taiwan | Sony (Phison $27) - Taiwan | SD16G | 16 GB | **D** | PASS |
| SanDisk_SU01G_8.0_006CD5B2_200706 | microSD 1GB — SanDisk Industrial SU series | SanDisk ($03) — Industrial SDSC | SU01G | 1 GB | **E** | **FAIL** (v1.5.1, 350 MHz) |
| Unknown_asdfg_2.2_000001F4_202512 | microSD 1GB Class 4 — "Lerdisk" | **CONFIRMED COUNTERFEIT** — MID $05 unknown, PNM "asdfg" (label "Lerdisk") | asdfg | 1 GB | **E (FAIL) / X (PASS 25/25)** | **Both sockets** (v1.8.0). The Edge-socket restriction was withdrawn 2026-08-20: #3240 is fixed at card init and this card now runs the Edge reproducer clean (mount 45/45, raw 14/14). Historical: External passed all 25 suites 467/467. See lerdisk-asdfg-1gb.md. |
| Unknown_asdfg_2.2_00001680_202511 | microSD 2GB Class 4 — "Cloudisk" | **CONFIRMED COUNTERFEIT** — MID $05 unknown, PNM "asdfg" (label "Cloudisk"); silicon twin of Lerdisk | asdfg | 2 GB | **E (FAIL) / X (PASS 25/25)** | **Both sockets** (v1.8.0). The Edge-socket restriction was withdrawn 2026-08-20: 45/45 mount + 14/14 raw on four warm Edge runs across two power cycles, boot access enabled. Historical: External passed all 25 suites 467/467. See cloudisk-asdfg-2gb.md. |

---

## Card Quirks — Non-Standard Behaviors

Some cards deviate from spec-typical behavior in ways the driver must recognize and accommodate. Documented here so a card showing the same pattern is matched against a *known, handled* quirk instead of triggering a fresh investigation.

### Dummy data-block CRC (SPI read CRC not provided)

Some cards — observed so far on older **SDSC** (CSD v1.0) media — do **not** compute a real CRC-16 for the data blocks they return on a read. They transmit a fixed placeholder (`$0000` or `$FFFF`) in the CRC field. **The card's 512 data bytes are correct** — only the trailing CRC is a dummy.

**Recognition signature:** a slow/tolerant read returns valid, structured data (e.g. sector 0 ends in the `55 AA` MBR signature), but the CRC read back from the card is a constant placeholder that does not match the CRC computed over that data — and is identical across different sectors.

A driver that hard-fails on a data-CRC mismatch rejects every card in this class. The driver detects such a card with an init-time CRC probe and disables read-CRC *validation* for the session (write-CRC generation and the post-read CMD13 check are unaffected).

| Card | MID | Capacity | Behavior | Notes |
|------|-----|----------|----------|-------|
| Cloudisk `asdfg` (counterfeit) | `$05` | 2 GB SDSC | Sends `$0000` data-block CRC | Wire-confirmed by hardware LA, 2026-05-18 |
| "Lerdisk" `asdfg` (counterfeit) | `$05` | 1 GB SDSC | Sends dummy data-block CRC (`cardWarnings()=$04`) | Twin of Cloudisk: same PNM/MID/PRV; characterized 2026-05-25 |
| SanDisk SU01G 1 GB SDSC | `$03` | 1 GB SDSC | **Suspected** — same streamer-read symptom | Re-test with `SD_la_streamer_diag.spin2` to confirm |

> CRC-validation / CRC error-injection regression suites implicitly assume a *real-CRC* card. On a dummy-CRC card those specific tests are **inapplicable** and must not be read as failures.

Full analysis, recognition procedure, and driver fix design: [`DOCs/Analysis/DUMMY-DATA-CRC-ANALYSIS.md`](../Analysis/DUMMY-DATA-CRC-ANALYSIS.md).

### Counterfeit classification (preliminary, under refinement)

Counterfeit SD cards (forged silicon, fake capacity, dummy CRC, lying CSD) cluster — many indicators show up together. Single indicators are noisy; combinations are diagnostic. The classifier below scores observed CID/CSD/empirical fields against a weighted rubric; design rationale and the running investigation log live in [`DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md`](../Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md).

| # | Indicator | Weight |
|:---:|---|:---:|
| 1 | PNM not alphanumeric-printable (gibberish like `"asdfg"`) | +3 |
| 2 | PNM is all zeros (`"00000"`) / all spaces, *alone* | +2 |
| 3 | **Major-brand MID with placeholder/anomalous PNM** (silicon says SanDisk/Samsung/etc., but PNM doesn't match that brand's conventions — strong forged-silicon tell) | **+4** |
| 4 | MID not in known-manufacturer list | +2 |
| 5 | CID CRC7 = `$00` | +2 |
| 6 | CSD v1.0 (SDSC) with MDT year > 2012 (real SDSC silicon ended ~2010) | +3 |
| 7 | CSD TRAN_SPEED claims 25 MHz but empirical probe finds ceiling < 23 MHz | +3 |
| 8 | `CW_NO_DATA_CRC` set (dummy data-block CRC) | +2 |
| 9 | SD spec 1.x + Class 4 + CSD v1.0 (lowest of everything) | +1 |
| 10 | Gold standard: CSD-claimed capacity ≠ actual usable sectors | +5 |

**Decision thresholds:**
- Score < 3 → legitimate
- Score 3-5 → suspected counterfeit (advisory; empirical SCK probe + drift headroom recommended)
- Score 6-8 → likely counterfeit (advisory; expose via `cardWarnings()`)
- Score ≥ 9 → confirmed counterfeit (user-visible warning recommended)

**Cards in this catalog meeting counterfeit thresholds:**

| Card row in summary | Score (no empirics) | Indicators firing | Classification |
|---|:---:|---|---|
| `Samsung_00000_1.0_D9FB539C_201408` (Chinese #2) | **6** | #2 PNM zeros (+2), **#3 Samsung MID with `"00000"` PNM (+4)** | **LIKELY COUNTERFEIT** |
| `SanDisk_SU08G_8.0_0AA81F11_201010` (Chinese #1) | 0 (from CID) | — | needs empirical re-characterization (CID alone looks legitimate; physical-card suspicion not yet confirmed in silicon) |

Cards being investigated in `COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md` that will be added to this catalog once the investigation closes:

| Card | Score | Classification |
|---|:---:|---|
| Cloudisk `"asdfg"` 2 GB SDSC (MID `$05`, MDT 2025/11) | **12-16** (with empirics) | **CONFIRMED COUNTERFEIT** |
| "Lerdisk" `"asdfg"` 1 GB SDSC (MID `$05`, MDT 2025/12) | **15** (with empirics) | **CONFIRMED COUNTERFEIT** — twin of Cloudisk |

---

## Performance

Performance figures live in **two tables that are never merged**, named by the
question each answers. They come from two different instruments measuring two
different things, and a row from one compared against a row from the other shows
a large gain or loss that is purely an instrument change.

> **Both tables are being repopulated.** Every figure previously published here
> predated the v1.8.0 align-offset change, the production speed bound and the
> card-quiesce fix, and the old single table silently mixed both instruments under
> one heading. The rows are generated from a full sweep rather than hand-edited --
> see [CATALOG-PROCEDURE.md](CATALOG-PROCEDURE.md).

**How rows are produced.** Both instruments emit `CATALOG-CARD` and `CATALOG-ROW`
lines; `tools/harvest_catalog.sh` turns a set of sweep logs into the Markdown
below. Do not hand-edit rows -- re-harvest. The script refuses to emit a table
whose rows came from more than one driver version, because a pristine table states
its provenance in one banner and cannot do that for a mixed set.

**Keys.** Rows are per physical instance, keyed by full **Card ID**
(`MID_PNM_PRV_PSN_YYYYMM`), and grouped by **silicon key** = `MID_PNM_PRV`
(e.g. `$27_SD16G_3.0`). The MID stays hex: mapping it to a manufacturer is not a
function -- `$9F` appears in this drawer as both a Silicon Power and a
Gigastone-branded card -- so the name is decoration applied from
[Known Manufacturer IDs](#known-manufacturer-ids-heuristic), which this document
owns in one place. **Brand does not predict controller**: Gigastone-branded cards
here carry four different MIDs (`$00`, `$12`, `$74`, `$9F`), and the same
silicon key can carry different labels: `Phison_SD16G_3.0` appears in this drawer
as both a PNY and a Sony card.

**Repeat runs show as a range, never an average.** One physical card has been
measured moving up to 3x between rounds. An average over runs reports a confident
single number for a measurement that is not stable, and hides the dispersion the
repeat run existed to expose. The `Runs` column says how many passes a row spans.

---

### Card capability (random access)

**Instrument:** `diagnostic-tests/SD_speed_characterize.spin2`
**Workload:** 10,000 single-sector reads at random offsets, CRC-16 verified.

This is a property of the **card**. Every read pays the controller's full internal
seek latency, which is why these figures spread roughly 38x across our drawer while
sequential figures nearly converge. **Random access separates cards.**

No limiter attribution column appears here: this metric is card-bound for every
card by construction, so the column would carry one constant answer.

<!-- harvested: tools/harvest_catalog.sh --capability -->

| Silicon key | Card ID | Reads | Landed clock | Throughput | Runs | Mean latency | Min | Max |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| _(awaiting sweep)_ | | | | | | | | |

---

### Driver throughput by traffic type

**Instrument:** `src/UTILS/SD_performance_benchmark.spin2`
**Workload:** raw single-sector, raw multi-sector (CMD18/CMD25) and file-level
handle traffic, at several sizes, writes verified byte-for-byte.

This is what an application actually gets from **this driver**. On sequential
multi-block traffic the bus does the limiting and cards nearly converge.
**The benchmark separates drivers.**

Limiter attribution belongs on this table only. Each rate is expressed as a
percentage of the bus ceiling -- one data line carries one bit per SCK, so nothing
can exceed `spi_freq / 8` bytes per second -- which turns "what is the limiting
factor" into a derived number rather than a judgement. `BUS-bound` means a faster
card cannot help and only a faster clock or 4-bit transfers would; `CARD-bound`
means the card's internal latency dominates and neither would help much.

<!-- harvested: tools/harvest_catalog.sh --throughput -->

| Silicon key | Card ID | Traffic | Bytes | SPI | Throughput | Runs | % of bus | Limiter |
|---|---|---|---:|---:|---:|---:|---:|---|
| _(awaiting sweep)_ | | | | | | | | |

---

### Register and identity data is exempt

Everything in the register tables above -- CID, CSD, SCR, capacity, quirks -- is a
property of the card. It does not stale when the driver changes and carries no
provenance requirement. Only performance data is driver-dependent, which is why
only performance data lives under a version banner.

### A caveat for anyone reading this as a buying guide

Performance here stratifies by something **a buyer cannot see before purchase**:
MID, PNM and PRV live in the CID register and are not printed on the card or the
packaging. SKUs are silently re-sourced between production runs, so two cards with
the same label and the same part number can carry different controllers. The honest
form of any claim from this table is "these specific cards, purchased then,
measured this" -- never "buy brand X".

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

**"Chinese Made" #1 8GB SDHC (claims SanDisk)** — [sandisk-su08g-8gb.md](cards/sandisk-su08g-8gb.md) — **SUSPECT COUNTERFEIT, needs empirical re-characterization**
```
SanDisk SU08G SDHC 7GB [FAT32] SD 3.x rev8.0 SN:0AA81F11 2010/10
Class 4, SPI 25 MHz
```
> CID alone looks legitimate (MID `$03` SanDisk + PNM `SU08G` matches SanDisk product code conventions). Catalog flag is from physical-card suspicion. Counterfeit classifier requires empirical follow-up (`cardWarnings()`, TRAN_SPEED-vs-probe check) to confirm or refute.

**"Chinese Made" #2 8GB SDHC (Samsung inside)** — [samsung-00000-8gb.md](cards/samsung-00000-8gb.md) — **LIKELY COUNTERFEIT (classifier score 6)**
```
Samsung 00000 SDHC 7GB [FAT16] SD 3.x rev1.0 SN:D9FB539C 2014/08
Class 6, SPI 25 MHz
```
> Counterfeit indicators firing: PNM is `"00000"` placeholder (+2), and **Samsung MID `$1B` with placeholder PNM is brand/PNM mismatch** (+4). Real Samsung cards use real product codes (`GD4QT`, `JD1Y7`). The silicon claims Samsung but the conventions don't match — strong forged-silicon tell.

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

**Rating E** - SDSC (counterfeit class):

**"Lerdisk" 1GB SDSC (counterfeit twin of Cloudisk)** — [lerdisk-asdfg-1gb.md](cards/lerdisk-asdfg-1gb.md)
```
Unknown asdfg SDSC 960MB [FAT32] SD 1.x rev2.2 SN:$0000_01F4 2025/12
Class 10, U1, V0, SPI 21 MHz  [P2FMTER]
```

**"Cloudisk" 2GB SDSC (counterfeit twin of Lerdisk)** — [cloudisk-asdfg-2gb.md](cards/cloudisk-asdfg-2gb.md)
```
Unknown asdfg SDSC 1GB [FAT32] SD 1.x rev2.2 SN:$0000_1680 2025/11
Class 4, U0, V0, SPI 21 MHz  [P2FMTER]
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
*Last updated: 2026-08-19*
*Cards cataloged: 26 (individual card pages in [DOCs/cards/](cards/))*
