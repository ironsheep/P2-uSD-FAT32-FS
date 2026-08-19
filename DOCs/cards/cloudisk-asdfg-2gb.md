# Card: "Cloudisk" 2 GB SDSC (counterfeit twin of Lerdisk asdfg)

**Label:** [`cloudisk-microsd-2gb-class4`](CARD-LABELS.md#cloudisk-microsd-2gb-class4) — printed text is mastered there, not here
**Unique ID:** `Unknown_asdfg_2.2_00001680_202511`
**Test Date:** 2026-05-18 (initial Edge characterization), 2026-05-27 (External re-characterization)
**Reporter:** stephen@ironsheep.biz
**Status:** Characterized. Supported on External SD header **only** until Edge-socket wedge is resolved.

### ⚠️ Temporary Support Restriction (2026-05-27)

This card is currently **supported on the External SD header only** (build flag `SD_PINS_EXTERNAL`, pins CS=20 / MOSI=19 / MISO=18 / SCK=21). On the P2 Edge module's onboard SD socket the card exhibits the same reproducible flash-commit-pipeline wedge as its twin Lerdisk: any single-block write after mount permanently wedges subsequent operations until power-cycle. The wedge does **not** fire on the External SD header — believed to be electrical-margin (trace length / capacitance) at the Edge socket exacerbating already-buggy counterfeit silicon.

A driver workaround that routes single-block writes through multi-block CMD25 protocol on `CW_NO_DATA_CRC` cards has been designed (see `DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md` experiment 7 sequence) but is not yet implemented. Until that workaround ships, **use the External SD header for this card class**.

### Card Designator (post-format, FAT32, External connector, settled SPI from probe-fix)

```
Unknown asdfg SDSC 1GB [FAT32] SD 1.x rev2.2 SN:$0000_1680 2025/11
Class 4, U0, V0, SPI 21 MHz  [P2FMTER]
L3: CSD claims TRAN_SPEED = 25 MHz; cardWarnings() = $04
```

Note on capacity reporting:
- **CSD-claimed capacity: 2 GB** (1920 MiB / 2014 MB decimal — from C_SIZE math)
- **L1 reports 1GB**: this is the FAT32-formatted usable size with the current partition configuration; the CSD reports a larger size.
- **Marketing label: 2 GB** — matches CSD claim.
- Whether the silicon actually delivers 2 GB of usable storage (vs. being a 1 GB silicon lying in CSD) has **not been ground-truthed** by a full write-then-read-back at the CSD-claimed capacity. The fake-capacity hypothesis remains open; classifier rule 10 (gold standard) requires that capacity test to fire its +5 points.

### Raw Registers

```
CID: $05 $00 $0C $61 $73 $64 $66 $67 $22 $00 $00 $16 $80 $01 $9B $00
CSD: $00 $0E $00 $32 $5B $5A $83 $BF $DD $FF $FF $9F $0A $80 $40 $00
OCR: $80FF_8000
SCR: $01 $85 $00 $00 $00 $00 $00 $00
```

### CID Register (Card Identification)

| Field | Value | Interpretation |
|---|---|---|
| MID | $05 | Manufacturer ID — **unknown / unassigned** (counterfeit indicator) |
| OID | $00 $0C | OEM ID — non-printable bytes (counterfeit indicator) |
| PNM | `asdfg` | Product Name — placeholder/keyboard-walk string (strong counterfeit indicator) |
| PRV | 2.2 | Product Revision |
| PSN | $0000_1680 | Serial Number |
| MDT | 2025-11 | Manufacturing Date |
| CRC | $00 | CID CRC7 — **$00** is invalid (counterfeit indicator) |

### CSD Register (Card Specific Data, v1.0 / SDSC layout)

| Field | Value | Interpretation |
|---|---|---|
| CSD_STRUCTURE | 0 | CSD v1.0 → SDSC card type |
| TAAC | $0E | Access time |
| NSAC | $00 | Read access clock cycles |
| TRAN_SPEED | $32 | 25 MHz max — driver's empirical probe disagrees (settles at ~21.875 MHz at sysclk=350) |
| CCC | $5B5 | Command class support: 0,2,4,5,7,8 |
| READ_BL_LEN | 10 | Default block size = 2^10 = **1024 bytes** (NOTE: differs from Lerdisk which has READ_BL_LEN=9 / 512 bytes — CMD16 SET_BLOCKLEN to 512 is required for this card) |
| C_SIZE | 3839 | Device size code |
| C_SIZE_MULT | 7 | Capacity multiplier |
| Marketing Capacity | 2 GB | (C_SIZE+1) × 2^(C_SIZE_MULT+2) × 2^READ_BL_LEN = 3840 × 512 × 1024 = 1920 MiB ≈ 2 GB |
| R2W_FACTOR | 2 | Write time = read time × 4 |
| SECTOR_SIZE | 127 | Erase block = 64 KB (128 sectors of 512 B) |
| ERASE_BLK_EN | 1 | 512-byte erase supported |

### OCR Register

```
OCR: $80FF_8000
```

Bit 31 = 1 (card ready), bit 30 = 0 (SDSC byte-addressed), voltage window all set ($FF_8000 lower bits).

### SCR Register

```
SCR: $01 $85 $00 $00 $00 $00 $00 $00
```

- SCR_STRUCTURE = 0 (version 1.0)
- SD_SPEC = 1 (Physical Spec Version 1.10)
- DATA_STAT_AFTER_ERASE = 0
- SD_SECURITY = 0 (no security)
- SD_BUS_WIDTHS = $5 (1-bit + 4-bit supported)
- CMD_SUPPORT = $00 (no CMD23 / CMD20 / extended bits) — consistent with all other catalog cards

### Filesystem (as received)

```
Partition table valid: yes
Volume label: P2-BENCH
Filesystem: FAT32
Cluster size: 8 KB (16 sectors)
Free space: ~960 MB (1,957,864 sectors)
```

### Counterfeit Classification

Per `CARD-CATALOG.md` classifier rubric:

| Rule | Triggered | Points |
|---|---|---|
| 1. PNM not alphanumeric-printable | "asdfg" is keyboard-walk, not a real product name | +3 |
| 2. MID is unassigned / unknown | $05 is not a registered SD manufacturer | +2 |
| 3. CID CRC7 = $00 | $00 is an invalid CRC7 (typically $01-$7F) | +2 |
| 6. CSD v1.0 (SDSC) with MDT year > 2012 | 2025-11 SDSC card is anachronistic | +3 |
| 7. CSD TRAN_SPEED claims 25 MHz but probe ceiling < 23 MHz | Card settles at 21.875 MHz under probe-fix | +3 |
| 8. CW_NO_DATA_CRC | Card sends dummy data-block CRC | +2 |
| 9. SD spec 1.x + class 4 + CSD v1.0 | All three "lowest-of-everything" indicators | +1 |
| **Total (without capacity ground-truth)** | | **16** |

Score ≥ 10 ⇒ `CARD_CONFIRMED_COUNTERFEIT`. Cloudisk and Lerdisk are the highest-scoring (most clearly counterfeit) cards in the catalog.

### Comparison with Lerdisk `asdfg` (companion counterfeit)

| Attribute | Lerdisk | Cloudisk | Same? |
|---|---|---|---|
| MID | $05 | $05 | yes |
| PNM | "asdfg" | "asdfg" | yes |
| PRV | 2.2 | 2.2 | yes |
| OID | $00 $0C | $00 $0C | yes |
| MDT | 2025-12 | 2025-11 | sequential (1 month apart) |
| PSN | $0000_01F4 | $0000_1680 | sequential serial pool |
| CSD_STRUCTURE | v1.0 (SDSC) | v1.0 (SDSC) | yes |
| TRAN_SPEED | $32 (25 MHz) | $32 (25 MHz) | yes |
| Settled SPI (probe) | 21.875 MHz @ 350 | 21.875 MHz @ 350 | yes |
| **READ_BL_LEN** | **9 (512 B)** | **10 (1024 B)** | **NO** — Cloudisk needs CMD16 to set 512-byte blocks |
| C_SIZE | 3839 | 3839 | yes |
| Marketing Capacity (CSD) | 1 GB | 2 GB | NO (driven by READ_BL_LEN difference) |
| Marketed label size | 1 GB | 2 GB | NO |
| cardWarnings() | $04 (CW_NO_DATA_CRC) | $04 (CW_NO_DATA_CRC) | yes |
| Edge-socket wedge | Fires reproducibly | Fires reproducibly | yes (same root cause) |
| External-connector full regression | 467/467 pass | 467/467 pass | yes (clean on both) |

**Conclusion**: Lerdisk and Cloudisk are **silicon twins from the same counterfeit production stream**. Same CID layout, sequential MDT, sequential PSN, same probe-settled SPI ceiling, same dummy-CRC handling, same Edge-socket wedge symptom. The only meaningful CSD difference is READ_BL_LEN (encoding 1 GB vs 2 GB Marketing Capacity), and the marketing labels match accordingly — Lerdisk sells as 1 GB, Cloudisk as 2 GB.

---

## External Connector — Test Results & Benchmarks (2026-05-27)

Card on External SD header (pins CS=20 / MOSI=19 / MISO=18 / SCK=21). Tests built with `--external` flag (`-D SD_PINS_EXTERNAL`). The Edge-socket wedge is electrical-margin-amplified and does **not** fire here.

### Card identification (External, 2026-05-27)

```
L1: Unknown asdfg SDSC 1GB [FAT32] SD 1.x rev2.2 SN:$0000_1680 2025/11
L2: Class 4, U0, V0, SPI 21 MHz  [P2FMTER]
L3: CSD claims TRAN_SPEED = 25 MHz; cardWarnings() = $04
```

### Full Regression — External Connector

Full `run_regression.sh --external --include-format`. With the Test #4 fix in commit `d89e7e6` (crc_validation_tests handles dummy-CRC cards correctly), all 25 suites pass in a single run.

| # | Suite | Pass | Fail | Time |
|---:|---|---:|---:|---:|
| 1 | SD_RT_mount_tests | 31 | 0 | 24s |
| 2 | SD_RT_raw_sector_tests | 14 | 0 | 3s |
| 3 | SD_RT_multiblock_tests | 6 | 0 | 4s |
| 4 | SD_RT_register_tests | 10 | 0 | 8s |
| 5 | SD_RT_speed_tests | 15 | 0 | 5s |
| 6 | SD_RT_crc_diag_tests | 14 | 0 | 8s |
| 7 | SD_RT_error_handling_tests | 14 | 0 | 3s |
| 8 | SD_RT_crc_validation_tests | 6 | 0 | 4s |
| 9 | SD_RT_recovery_tests | 7 | 0 | 5s |
| 10 | SD_RT_file_ops_tests | 26 | 0 | 6s |
| 11 | SD_RT_read_write_tests | 48 | 0 | 14s |
| 12 | SD_RT_multihandle_tests | 21 | 0 | 6s |
| 13 | SD_RT_seek_tests | 37 | 0 | 6s |
| 14 | SD_RT_volume_tests | 31 | 0 | 14s |
| 15 | SD_RT_subdir_ops_tests | 18 | 0 | 3s |
| 16 | SD_RT_directory_tests | 30 | 0 | 7s |
| 17 | SD_RT_dirhandle_tests | 25 | 0 | 6s |
| 18 | SD_RT_fifo_tests | 21 | 0 | 1s |
| 19 | SD_RT_multicog_tests | 14 | 0 | 3s |
| 20 | SD_RT_cogcwd_tests | 5 | 0 | 4s |
| 21 | SD_RT_timestamp_tests | 6 | 0 | 14s |
| 22 | SD_RT_stress_tests | 4 | 0 | 4s |
| 23 | SD_RT_async_tests | 6 | 0 | 3s |
| 24 | SD_RT_defrag_tests | 12 | 0 | 8s |
| 25 | SD_RT_format_tests | 46 | 0 | 9s |
| **TOTAL** | | **467** | **0** | **172s** |

**Note on suite 2 (`SD_RT_raw_sector_tests`)**: this is the exact suite that fails 1/14 on the Edge socket. On External it passes **14/14** — same evidence point as Lerdisk for the Edge-vs-External electrical-margin hypothesis.

### Benchmark — External Connector

Catalog notation: `350+250`.

#### Sysclk 350 MHz / settled SPI 21.875 MHz

| Test | Min (us) | Avg (us) | Max (us) | Throughput |
|---|---:|---:|---:|---:|
| Mount | — | 1,658.5 ms | — | — |
| **RAW read 1×512B** | 621 | 653 | 908 | **784 KB/s** |
| **RAW write 1×512B** | 1,066 | 1,117 | 1,190 | **458 KB/s** |
| RAW read 8×512B (CMD18) | 2,101 | 2,139 | 2,463 | 1,914 KB/s |
| RAW read 32×512B (CMD18) | 7,169 | 7,496 | 10,382 | 2,185 KB/s |
| **RAW read 64×512B (CMD18)** | 13,929 | 14,261 | 17,125 | **2,297 KB/s** |
| RAW write 8×512B (CMD25) | 2,416 | 2,424 | 2,432 | 1,689 KB/s |
| RAW write 32×512B (CMD25) | 7,343 | 7,346 | 7,350 | 2,230 KB/s |
| **RAW write 64×512B (CMD25)** | 14,231 | 14,233 | 14,237 | **2,302 KB/s** |
| File write 512 B | 7,020 | 7,580 | 7,703 | 67 KB/s |
| File write 4 KB | 16,154 | 18,934 | 42,666 | 216 KB/s |
| **File write 32 KB** | 125,717 | 150,311 | 157,766 | **218 KB/s** |
| File read 4 KB | 4,193 | 4,271 | 4,896 | 959 KB/s |
| File read 32 KB | 32,277 | 32,690 | 35,044 | 1,002 KB/s |
| File read 128 KB | 128,438 | 128,866 | 131,222 | 1,017 KB/s |
| **File read 256 KB** | 257,716 | 258,184 | 261,350 | **1,015 KB/s** |
| Unmount | — | 2 ms | — | — |

#### Sysclk 250 MHz / settled SPI 20.833 MHz

| Test | Min (us) | Avg (us) | Max (us) | Throughput |
|---|---:|---:|---:|---:|
| Mount | — | 1,716.4 ms | — | — |
| **RAW read 1×512B** | 731 | 753 | 949 | **679 KB/s** |
| **RAW write 1×512B** | 1,131 | 1,133 | 1,146 | **451 KB/s** |
| RAW read 8×512B (CMD18) | 2,342 | 2,370 | 2,576 | 1,728 KB/s |
| RAW read 32×512B (CMD18) | 7,864 | 8,178 | 10,997 | 2,003 KB/s |
| **RAW read 64×512B (CMD18)** | 15,234 | 15,547 | 18,352 | **2,107 KB/s** |
| RAW write 8×512B (CMD25) | 2,643 | 2,651 | 2,659 | 1,545 KB/s |
| RAW write 32×512B (CMD25) | 8,041 | 8,046 | 8,057 | 2,036 KB/s |
| **RAW write 64×512B (CMD25)** | 15,566 | 15,569 | 15,584 | **2,104 KB/s** |
| File write 512 B | 7,256 | 7,889 | 7,976 | 64 KB/s |
| File write 4 KB | 16,420 | 19,779 | 48,713 | 207 KB/s |
| **File write 32 KB** | 126,826 | 146,892 | 191,313 | **223 KB/s** |
| File read 4 KB | 4,875 | 4,965 | 5,654 | 824 KB/s |
| File read 32 KB | 36,932 | 37,368 | 39,701 | 876 KB/s |
| File read 128 KB | 147,067 | 147,507 | 149,715 | 888 KB/s |
| **File read 256 KB** | 294,554 | 295,023 | 298,077 | **888 KB/s** |
| Unmount | — | 3 ms | — | — |

### Comparison: Cloudisk vs Lerdisk performance (External, sysclk 350)

| Metric | Lerdisk | Cloudisk | Notes |
|---|---:|---:|---|
| Mount | 339 ms | 1,659 ms | Cloudisk is ~5× slower at mount — consistent run-to-run; not transient |
| RAW read 1×512B | 915 KB/s | 784 KB/s | Cloudisk ~14% slower |
| RAW write 1×512B | 609 KB/s | 458 KB/s | Cloudisk ~25% slower |
| RAW read 64×512B | 2,360 KB/s | 2,297 KB/s | within run-to-run variance |
| RAW write 64×512B | 2,315 KB/s | 2,302 KB/s | within run-to-run variance |
| File read 256 KB | 1,178 KB/s | 1,015 KB/s | Cloudisk ~14% slower |
| File write 32 KB | 347 KB/s | 218 KB/s | Cloudisk ~37% slower |

Cloudisk runs measurably slower than its silicon-twin Lerdisk despite identical SPI speed and identical core CSD parameters. The mount-time difference is striking and points to internal flash-translation-layer initialization differences — the silicon may be identical but firmware (or NAND geometry) differs.

### Operating note

When this card is used on the External connector path, the full driver feature surface works. The card behaves like every other catalog card with respect to the driver API. The wedge that defines this card's class on Edge does not manifest on External in any of the 25 regression suites or in two full benchmark passes. Until the Edge-socket workaround ships, **External is the only supported topology for this card.**

### Notes

- **Confirmed twin of Lerdisk** with measurable performance differences. Same silicon family, sequential serial numbers and manufacturing dates, identical Edge-socket wedge symptom.
- **READ_BL_LEN difference (10 vs 9)** is the only CSD-encoded distinction between the twins. The driver issues CMD16 to set 512-byte blocks at init; this works on both cards.
- **CSD-claimed capacity is 2 GB** (vs Lerdisk's 1 GB) but actual silicon capacity has not been ground-truthed by full write-then-read-back. Fake-capacity-test could push the classifier score from 16 to 21.
- **Cloudisk mount is significantly slower than Lerdisk** (~5×). Consistent run-to-run. Worth investigating if the difference is consequential for production workloads.
- **Wedge bug #3240 reproduces consistently on Edge socket**; does NOT fire on External. Same pattern as Lerdisk.
