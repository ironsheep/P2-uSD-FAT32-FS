# Card: "Lerdisk" 1 GB SDSC (counterfeit twin of Cloudisk asdfg)

**Label:** [`lerdisk-microsd-1gb-class4`](CARD-LABELS.md#lerdisk-microsd-1gb-class4) — printed text is mastered there, not here
**Disposition:** `retained`
**Unique ID:** `Unknown_asdfg_2.2_000001F4_202512`
**Initial Test Date:** 2026-05-24 (Edge socket, P2 Edge module)
**External Re-characterization:** 2026-05-27 (External SD header, P2 Edge module)
**Reporter:** stephen@ironsheep.biz
**Status:** Characterized. **Edge-socket restriction WITHDRAWN 2026-08-20** — runs clean in both sockets on v1.8.0.

### Support Restriction — WITHDRAWN (raised 2026-05-27, withdrawn 2026-08-20)

> **⚠ Superseded mechanism — update pending (2026-08-20).** The wedge described
> below was root-caused in August 2026 and it is **not** an electrical-margin
> effect and **not** about single-block writes. It is boot-time traffic on the
> pins the Edge socket shares with the boot flash; the External header is clean
> because it sits on ordinary GPIO, not because its wiring is kinder. The CMD25
> workaround referenced below was never implemented and is not needed. v1.8.0
> fixes it with a CMD12 before CMD0 at card initialization, and this card's twin
> has since run the full reproducer clean in the Edge socket.
>
> Full account: [`../SD-CARD-WEDGE-CASE-STUDY.md`](../SD-CARD-WEDGE-CASE-STUDY.md).
>
> **The restriction is now WITHDRAWN.** This card ran the Edge-socket reproducer
> clean on the v1.8.0 build — `SD_RT_mount_tests` **45/45** and
> `SD_RT_raw_sector_tests` **14/14**, the exact two-suite sequence that had been
> the reproducer since May — and the controlled demonstration of §10.1 of the case
> study was performed on this card: five clean warm runs across two power cycles,
> each pair followed by an unmodified build that still wedged in the same session.
>
> **Use either socket.** The historical text below is kept as the record of what
> was believed between May and August 2026; its mechanism is wrong and its
> recommendation no longer applies.

*(Historical, superseded — see the banner above.)* This card was **supported on the External SD header only** (build flag `SD_PINS_EXTERNAL`, pins CS=20 / MOSI=19 / MISO=18 / SCK=21). On the P2 Edge module's onboard SD socket it exhibited a reproducible wedge: operations after a mount wedged until power-cycle. The wedge did **not** fire on the External SD header — believed at the time to be electrical margin (trace length / capacitance) at the Edge socket exacerbating already-buggy counterfeit silicon. That reading was wrong: the External header simply sits on ordinary GPIO rather than on the boot pins.

*(Historical, superseded.)* A driver workaround routing single-block writes through multi-block CMD25 on `CW_NO_DATA_CRC` cards was designed (see `DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md` experiment 7 sequence). **It was never implemented and is not needed** — raw single-block writes were later shown not to wedge these cards at all.

Full External-connector regression results: see "External Connector — Test Results" section below.

### Card Designator (pre-format, FAT16 as shipped)

```
Unknown asdfg SDSC 1GB [FAT16] SD 1.x rev2.2 SN:$0000_01F4 2025/12
Class 10, U1, V0, SPI 25 MHz
```

### Card Designator (post-format, FAT32, settled SPI from probe-fix)

```
Unknown asdfg SDSC 960MB [FAT32] SD 1.x rev2.2 SN:$0000_01F4 2025/12
Class 10, U1, V0, SPI 21 MHz  [P2FMTER]
```

Note: the label claims "Class 4" but the card's own SD Status reports Class 10. Marketing claim vs. internal data mismatch is itself a counterfeit indicator.

### Raw Registers

```
CID: $05 $00 $0C $61 $73 $64 $66 $67 $22 $00 $00 $01 $F4 $01 $9C $00
CSD: $00 $0E $00 $32 $5B $59 $83 $BF $DD $FF $FF $BF $0A $40 $40 $00
OCR: $80FF_8000
SCR: $01 $85 $00 $00 $00 $00 $00 $00
```

### CID Register (Card Identification) — All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| MID | [127:120] | $05 | **Unknown** (not in known-manufacturer list) | **[USED]** |
| OID | [119:104] | $00 $0C | non-printable | [INFO] |
| PNM | [103:64] | $61 $73 $64 $66 $67 | `"asdfg"` — gibberish placeholder | [INFO] |
| PRV | [63:56] | $22 | 2.2 | [INFO] |
| PSN | [55:24] | $0000_01F4 | 500 | [INFO] |
| MDT | [19:8] | $19C | **2025-12** (Dec 2025) | [INFO] |
| CRC7 | [7:1] | $00 | **$00 — anomalous** (real cards have non-zero CRC7) | [INFO] |

### CSD Register (Card Specific Data, v1.0 / SDSC layout) — All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| CSD_STRUCTURE | [127:126] | 0 | **CSD Version 1.0 (SDSC)** | **[USED]** |
| TAAC | [119:112] | $0E | 1.0 ms (1.0 × 1 ms unit) | **[USED]** |
| NSAC | [111:104] | $00 | 0 CLK cycles | **[USED]** |
| TRAN_SPEED | [103:96] | $32 | 25 MHz max | **[USED]** |
| CCC | [95:84] | $5B5 | Classes 0,2,4,5,7,8,10 (Class 6 = No) | [INFO] |
| READ_BL_LEN | [83:80] | 9 | 512 bytes | [INFO] |
| READ_BL_PARTIAL | [79] | 1 | Allowed | [INFO] |
| WRITE_BLK_MISALIGN | [78] | 0 | Not allowed | [INFO] |
| READ_BLK_MISALIGN | [77] | 0 | Not allowed | [INFO] |
| DSR_IMP | [76] | 0 | DSR not implemented | [INFO] |
| C_SIZE | [73:62] | 3,839 | Device size (SDSC) | **[USED]** |
| VDD_R_CURR_MIN | [61:59] | 3 | — | [INFO] |
| VDD_R_CURR_MAX | [58:56] | 5 | — | [INFO] |
| VDD_W_CURR_MIN | [55:53] | 7 | 100 mA at VDD min (write) | [INFO] |
| VDD_W_CURR_MAX | [52:50] | 7 | 200 mA at VDD max (write) | [INFO] |
| C_SIZE_MULT | [49:47] | 7 | Device size multiplier (SDSC) | **[USED]** |
| ERASE_BLK_EN | [46] | 1 | 512-byte erase supported | [INFO] |
| SECTOR_SIZE | [45:39] | 127 | Erase sector = 64 KB (128 sectors) | [INFO] |
| WP_GRP_SIZE | [38:32] | 63 | — | [INFO] |
| WP_GRP_ENABLE | [31] | 0 | Disabled | [INFO] |
| R2W_FACTOR | [28:26] | 2 | **Write = Read × 4** | **[USED]** |
| WRITE_BL_LEN | [25:22] | 9 | 512 bytes | [INFO] |
| WRITE_BL_PARTIAL | [21] | 0 | Not allowed | [INFO] |
| FILE_FORMAT_GRP | [15] | 0 | — | [INFO] |
| COPY | [14] | 1 | Copy | [INFO] |
| PERM_WRITE_PROTECT | [13] | 0 | Not protected | [INFO] |
| TMP_WRITE_PROTECT | [12] | 0 | Not protected | [INFO] |
| FILE_FORMAT | [11:10] | 0 | Hard disk-like | [INFO] |
| CRC7 | [7:1] | $00 | **$00 — anomalous** | [INFO] |

**Derived Values:**
- Read Timeout: **1,000 ms** (calculated from TAAC, with 10× safety margin)
- Write Timeout: **4,000 ms** (calculated from TAAC × R2W_FACTOR)
- Marketing Capacity: 1 GB
- Actual Capacity: 960 MiB (≈ 1.007 GB decimal)
- Total Sectors: 1,966,080

### OCR Register (Operating Conditions) — All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| Power Up Status | [31] | 1 | Ready | [INFO] |
| CCS | [30] | 0 | **SDSC (byte addressing)** | **[USED]** |
| UHS-II Status | [29] | 0 | Not UHS-II | [INFO] |
| S18A | [24] | 0 | 3.3V only | [INFO] |
| 3.5-3.6V through 2.7-2.8V | [23:15] | $1FF | All supported | [INFO] |

**OCR Value:** $80FF_8000

### SCR Register (SD Configuration) — All Fields

| Field | Bits | Raw | Value | Usage |
|-------|------|-----|-------|-------|
| SCR_STRUCTURE | [63:60] | 0 | SCR Version 1.0 | [INFO] |
| SD_SPEC | [59:56] | 1 | **SD Physical Layer 1.10** | **[USED]** |
| DATA_STAT_AFTER_ERASE | [55] | 1 | Data = 1 after erase | [INFO] |
| SD_SECURITY | [54:52] | 0 | No security | [INFO] |
| SD_BUS_WIDTHS | [51:48] | $5 | 1-bit and 4-bit supported | [INFO] |
| SD_SPEC3 | [47] | 0 | SD 3.0 support: No | [INFO] |
| EX_SECURITY | [46:43] | 0 | No extended security | [INFO] |
| SD_SPEC4 | [42] | 0 | SD 4.0 support: No | [INFO] |
| SD_SPECX | [41:38] | 0 | — | [INFO] |
| CMD_SUPPORT | [33:32] | $00 | No extended commands | [INFO] |

**SD Version:** 1.10 (SD_SPEC=1, SD_SPEC3=0) — claims to predate the SDHC era.

### Filesystem (as shipped)

| Field | Value |
|-------|-------|
| MBR Partition Type | $06 (FAT16) |
| Status | Driver mount() returned -22 (E_NOT_FAT32) — card must be reformatted as FAT32 to run filesystem-level tests |

### Counterfeit Classification

Per `CARD-CATALOG.md` counterfeit classifier rubric:

| # | Indicator | Score |
|---|---|:---:|
| 1 | PNM not alphanumeric-printable (`"asdfg"` is printable but is gibberish placeholder, same as Cloudisk) | +3 |
| 4 | MID ($05) not in known-manufacturer list | +2 |
| 5 | CID CRC7 = $00 | +2 |
| 6 | CSD v1.0 (SDSC) with MDT year > 2012 (2025-12) | +3 |
| Subtotal (no empirics) | | **10** |
| 7 | TRAN_SPEED 25 MHz vs. empirical probe (21.875 MHz < 23 MHz) | +3 |
| 8 | `CW_NO_DATA_CRC` set (`cardWarnings() = $04`) | +2 |
| 10 | CSD-claimed capacity ≠ actual usable (capacity verified usable: 1,966,080 sectors) | +0 |
| **Total** | | **15** |

**Final classifier score 15 → CONFIRMED COUNTERFEIT** (threshold ≥ 9).

### Comparison with Cloudisk `asdfg` (companion counterfeit)

| Field | Lerdisk 1GB | Cloudisk 2GB |
|---|---|---|
| MID | $05 (Unknown) | $05 (Unknown) |
| PNM | `"asdfg"` | `"asdfg"` |
| PRV | 2.2 | 2.2 |
| MDT | 2025/12 | 2025/11 |
| CID CRC7 | $00 | $00 |
| SCR SD_SPEC | 1 (SD 1.10) | (per Cloudisk doc) |
| Capacity | 960 MiB | ≈1.9 GiB |
| SN | $0000_01F4 | $0000_1680 |

Identical silicon family, same controller pattern, sequential manufacturing window. Likely from the same counterfeit OEM stream.

### Test Results

| Test | Status | Notes |
|------|--------|-------|
| `initCardOnly()` | **PASS** | Card-level init OK; full register dump succeeded |
| `mount()` (pre-format) | **FAIL** | Returns -22 (E_NOT_FAT32) — card shipped as FAT16 |
| `SD_card_characterize` | **PASS** | Full register dump completed cleanly |
| `cardWarnings()` post-init | **`$04`** | `CW_NO_DATA_CRC` set — dummy data-block CRC |
| Format @ sysclk=270 | **FAIL** | MBR readback mismatch, VBR write `drespTimeout`; data not landing on card |
| Format @ sysclk=350 (with probe-fix detune to 21.875 MHz) | **PASS** | 244,254 clusters, 960 MB usable, "P2-BENCH" label |
| `SD_card_identify` (post-format) | **PASS** | Line 1/2 captured; settled SPI = 21 MHz |
| Performance @ 350 MHz sysclk | **PASS** | (see Benchmark Results below) |
| Performance @ 250 MHz sysclk | **PASS** | (see Benchmark Results below) |
| **Unmount→remount wedge (#3240)** | **PARTIAL** | Wedge fires after probe-fix tool runs (identify→benchmark, characterize→format); but did NOT fire between mount_tests and raw_sector_tests in the regression runner. Trigger condition is not "any unmount" — appears related to specific operation patterns. |
| Full regression — `SD_RT_mount_tests` | **PASS 31/31** | Mount, unmount, and re-mount cycles all succeed within a single binary |
| Full regression — `SD_RT_raw_sector_tests` | **FAIL 1/14** | Sequential writes to sector 100,000+ fail (status=-7 E_IO_ERROR for writes after the first; status=-1 E_TIMEOUT for read-backs). MBR readback returns $00 instead of $55 $AA — identical streamer-DMA failure to SanDisk SU01G |
| Full regression — suites 3-24 | Not run | `run_regression.sh` is configured to STOP on first suite failure |

### Regression Failure Pattern (raw_sector_tests)

```
* Test: Write Pattern A (sequential) to sector 100_000
  READ FAILED after write! status=-1            ← read-back never returned data
* Test: Write Pattern B (AA/55) to sector 100_001
  WRITE FAILED! status=-7                       ← subsequent writes outright fail
* Test: Write Pattern C/D/E
  WRITE FAILED! status=-7
* Test: Read sector 100_000..100_004
  READ FAILED! status=-1                        ← reads of supposedly-written sectors all fail
* Test: Read sector 0 (MBR) and verify signature $55 $AA
  ERROR: Expected $55 $AA, got $$00 $$00        ← even known-good sector returns zeros after stream of failures
```

This is the **streamer-DMA failure mode** documented for SanDisk SU01G. Smart-pin SPI works (registers, file-level operations, mount/unmount), but raw single-sector streamer reads/writes corrupt or hang. The 1 pass in suite 2 is the "high LBA / out-of-range sector" test where the driver correctly returns -1 for an invalid sector.

**Counterfeit class conclusion**: this card joins SU01G and (suspectedly) Cloudisk in the "streamer reads/writes don't work on the data area" failure class. The card-level smart-pin SPI path is solid; the streamer-DMA path is not.

### Benchmark Results

`SPI Frequency` is the value the driver's probe settled on at each sysclk after the probe-fix backoff. Notation per catalog rule: detuned at both → `350@22M+250@21M`.

#### Sysclk 350 MHz / settled SPI 21.875 MHz

| Test | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|
| Mount | — | 339.0 ms | — | — |
| **RAW read 1×512B** | 545 us | 561 us | 689 us | 912 KB/s |
| **RAW write 1×512B** | 858 us | 859 us | 864 us | 596 KB/s |
| RAW read 8×512B (CMD18) | 2,026 us | 2,041 us | 2,176 us | 2,006 KB/s |
| RAW read 32×512B (CMD18) | 7,103 us | 7,121 us | 7,260 us | 2,300 KB/s |
| **RAW read 64×512B (CMD18)** | 13,874 us | 13,890 us | 14,018 us | **2,359 KB/s** |
| RAW write 8×512B (CMD25) | 2,477 us | 2,477 us | 2,477 us | 1,653 KB/s |
| RAW write 32×512B (CMD25) | 7,992 us | 7,996 us | 7,998 us | 2,049 KB/s |
| **RAW write 64×512B (CMD25)** | 15,614 us | 15,618 us | 15,619 us | **2,098 KB/s** |
| File write 512 B | 5,190 us | 6,453 us | 13,311 us | 79 KB/s |
| File write 4 KB | 11,380 us | 12,167 us | 18,160 us | 336 KB/s |
| **File write 32 KB** | 95,324 us | 96,876 us | 102,198 us | **338 KB/s** |
| File read 4 KB | 3,684 us | 3,734 us | 4,189 us | 1,096 KB/s |
| File read 32 KB | 27,917 us | 28,190 us | 29,680 us | 1,162 KB/s |
| File read 128 KB | 111,949 us | 112,185 us | 113,720 us | 1,168 KB/s |
| **File read 256 KB** | 222,498 us | 222,782 us | 225,178 us | **1,176 KB/s** |
| File Open | 149 us | 199 us | 648 us | — |
| File Close | 37 us | 37 us | 38 us | — |
| Unmount | — | 2 ms | — | — |

Single→multi improvement (64 sectors via CMD18): **60%** speedup (35,317 → 13,872 us).

#### Sysclk 250 MHz / settled SPI 20.833 MHz

| Test | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|
| Mount | — | 343.9 ms | — | — |
| **RAW read 1×512B** | 664 us | 672 us | 744 us | 761 KB/s |
| **RAW write 1×512B** | 949 us | 956 us | 957 us | 535 KB/s |
| RAW read 8×512B (CMD18) | 2,275 us | 2,284 us | 2,363 us | 1,793 KB/s |
| RAW read 32×512B (CMD18) | 7,799 us | 7,808 us | 7,886 us | 2,098 KB/s |
| **RAW read 64×512B (CMD18)** | 15,164 us | 15,172 us | 15,251 us | **2,159 KB/s** |
| RAW write 8×512B (CMD25) | 2,773 us | 2,775 us | 2,776 us | 1,476 KB/s |
| RAW write 32×512B (CMD25) | 8,980 us | 8,985 us | 8,995 us | 1,823 KB/s |
| **RAW write 64×512B (CMD25)** | 17,540 us | 17,541 us | 17,548 us | **1,868 KB/s** |
| File write 512 B | 5,649 us | 6,845 us | 13,645 us | 74 KB/s |
| File write 4 KB | 11,704 us | 13,430 us | 19,272 us | 304 KB/s |
| **File write 32 KB** | 99,032 us | 100,558 us | 106,038 us | **325 KB/s** |
| File read 4 KB | 4,328 us | 4,390 us | 4,818 us | 933 KB/s |
| File read 32 KB | 32,564 us | 32,847 us | 34,239 us | 997 KB/s |
| File read 128 KB | 129,529 us | 129,849 us | 131,198 us | 1,009 KB/s |
| **File read 256 KB** | 260,069 us | 260,359 us | 262,372 us | **1,006 KB/s** |
| File Open | 209 us | 258 us | 691 us | — |
| File Close | 52 us | 52 us | 53 us | — |
| Unmount | — | 2 ms | — | — |

Single→multi improvement (64 sectors via CMD18): **64%** speedup (42,677 → 15,162 us).

### Notes

- **Second SDSC card characterized** (after Cloudisk; addresses task #3262 / #3263 — needing a comparison data point).
- **Drives label/silicon mismatch**: label says "Lerdisk" Class 4, silicon's SD Status reports Class 10, U1. Both can't be true; cheap counterfeit controllers commonly lie about speed class.
- **Almost-twin of Cloudisk** — same PNM placeholder, same MID, same PRV, sequential MDT, sequential serial. Confirms an *active stream* of counterfeit `"asdfg"` cards in different marketed capacities. Catalog should treat them as a *card class*, not as one-offs.
- **No format on arrival**: shipped as FAT16. This is normal for the actual capacity (sub-2GB cards typically default to FAT16); not a counterfeit indicator on its own.
- **TRAN_SPEED $32** = 25 MHz max — same as every catalog card. The driver-probed ceiling (after `probeSpiCeiling`) is the real number to record.
- **Format requires sysclk=350 with probe-fix**: at sysclk=270 (`SD_format_card.spin2` default), the VBR write returned `drespTimeout`, MBR readback was zeros, and the card never acked the data block. At sysclk=350 the probe-fix detunes SCK to 21.875 MHz and format completes cleanly. The default formatter sysclk should be reconsidered for SDSC counterfeit support, or the cards added to a "format at 350" exception list.
- **Wedge bug #3240 reproduces consistently on Edge socket**: every fresh `mount()` (or `initCardOnly()`) after a prior unmount on this card *requires a P2 Edge power-cycle*. The driver eventually times out, but no software-level reset clears the wedge. Same pattern as Cloudisk. **Does NOT fire on External SD header** — see External Connector results below.
- **Performance comparable to Cloudisk class** (per resume context). At sysclk=350 the multi-read peaks at 2,359 KB/s — slower than mainstream SDHC cards (~7-15 MB/s at 25 MHz) but consistent with a counterfeit SDSC controller running below 22 MHz.

---

## External Connector — Test Results & Benchmarks (2026-05-27)

Card moved from Edge SD socket to External SD header (pins CS=20 / MOSI=19 / MISO=18 / SCK=21). Tests built with `--external` flag (`-D SD_PINS_EXTERNAL`). Per the investigation doc, the External connector has less aggressive trace-length / capacitance than the Edge socket, and the wedge pattern that fires on Edge does **not** fire here.

### Card identification (External, 2026-05-27)

```
L1: Unknown asdfg SDSC 960MB [FAT32] SD 1.x rev2.2 SN:$0000_01F4 2025/12
L2: Class 10, U1, V0, SPI 21 MHz  [P2FMTER]
L3: CSD claims TRAN_SPEED = 25 MHz; cardWarnings() = $04
```

Identical fingerprint to the Edge characterization — same silicon, same probe-settled SPI (21.875 MHz at sysclk 350, 20.833 MHz at sysclk 250), same `CW_NO_DATA_CRC` flag.

### Full Regression — External Connector

Full `run_regression.sh --external --include-format` plus standalone re-run of `SD_RT_format_tests.spin2 --external`. With the Test #4 fix in commit `d89e7e6` (crc_validation_tests handles dummy-CRC cards correctly), all 25 suites pass.

| # | Suite | Pass | Fail | Time |
|---:|---|---:|---:|---:|
| 1 | SD_RT_mount_tests | 31 | 0 | 17s |
| 2 | SD_RT_raw_sector_tests | 14 | 0 | 3s |
| 3 | SD_RT_multiblock_tests | 6 | 0 | 4s |
| 4 | SD_RT_register_tests | 10 | 0 | 6s |
| 5 | SD_RT_speed_tests | 15 | 0 | 5s |
| 6 | SD_RT_crc_diag_tests | 14 | 0 | 6s |
| 7 | SD_RT_error_handling_tests | 14 | 0 | 3s |
| 8 | SD_RT_crc_validation_tests | 6 | 0 | (with d89e7e6 fix) |
| 9 | SD_RT_recovery_tests | 7 | 0 | 5s |
| 10 | SD_RT_file_ops_tests | 26 | 0 | 4s |
| 11 | SD_RT_read_write_tests | 48 | 0 | 10s |
| 12 | SD_RT_multihandle_tests | 21 | 0 | 4s |
| 13 | SD_RT_seek_tests | 37 | 0 | 5s |
| 14 | SD_RT_volume_tests | 31 | 0 | 10s |
| 15 | SD_RT_subdir_ops_tests | 18 | 0 | 3s |
| 16 | SD_RT_directory_tests | 30 | 0 | 5s |
| 17 | SD_RT_dirhandle_tests | 25 | 0 | 5s |
| 18 | SD_RT_fifo_tests | 21 | 0 | 2s |
| 19 | SD_RT_multicog_tests | 14 | 0 | 3s |
| 20 | SD_RT_cogcwd_tests | 5 | 0 | 4s |
| 21 | SD_RT_timestamp_tests | 6 | 0 | 13s |
| 22 | SD_RT_stress_tests | 4 | 0 | 4s |
| 23 | SD_RT_async_tests | 6 | 0 | 4s |
| 24 | SD_RT_defrag_tests | 12 | 0 | 6s |
| 25 | SD_RT_format_tests | 46 | 0 | (standalone re-run) |
| **TOTAL** | | **467** | **0** | |

**Note on suite 2 (`SD_RT_raw_sector_tests`)**: this is the exact suite that fails 1/14 on the Edge socket. On External it passes **14/14**. The same hardware (Lerdisk) running on a different connector produces opposite outcomes — the proof point for the Edge-vs-External electrical-margin hypothesis.

### Benchmark — External Connector

Catalog notation: `350+250` (both runs land on probe-settled SPI; no SPI mismatch annotation needed).

#### Sysclk 350 MHz / settled SPI 21.875 MHz

| Test | Min (us) | Avg (us) | Max (us) | Throughput |
|---|---:|---:|---:|---:|
| **RAW read 1×512B** | 545 | 559 | 686 | **915 KB/s** |
| **RAW write 1×512B** | 839 | 840 | 845 | **609 KB/s** |
| RAW read 8×512B (CMD18) | 2,025 | 2,039 | 2,172 | 2,008 KB/s |
| RAW read 32×512B (CMD18) | 7,099 | 7,115 | 7,252 | 2,302 KB/s |
| **RAW read 64×512B (CMD18)** | 13,865 | 13,879 | 14,006 | **2,360 KB/s** |
| RAW write 8×512B (CMD25) | 2,297 | 3,461 | 13,927 | 1,183 KB/s (high variance) |
| RAW write 32×512B (CMD25) | 7,257 | 7,263 | 7,268 | 2,255 KB/s |
| **RAW write 64×512B (CMD25)** | 14,145 | 14,152 | 14,157 | **2,315 KB/s** |
| File write 512 B | 5,064 | 6,348 | 13,129 | 80 KB/s |
| File write 4 KB | 11,317 | 12,074 | 18,083 | 339 KB/s |
| **File write 32 KB** | 94,032 | 94,341 | 94,572 | **347 KB/s** |
| File read 4 KB | 3,658 | 3,707 | 4,126 | 1,104 KB/s |
| File read 32 KB | 28,183 | 28,455 | 29,945 | 1,151 KB/s |
| File read 128 KB | 110,763 | 111,049 | 112,518 | 1,180 KB/s |
| **File read 256 KB** | 222,223 | 222,479 | 224,412 | **1,178 KB/s** |
| File Open | 149 | 199 | 647 | — |
| File Close | 37 | 37 | 38 | — |
| Unmount | — | 2 ms | — | — |

#### Sysclk 250 MHz / settled SPI 20.833 MHz

| Test | Min (us) | Avg (us) | Max (us) | Throughput |
|---|---:|---:|---:|---:|
| **RAW read 1×512B** | 659 | 673 | 740 | **760 KB/s** |
| **RAW write 1×512B** | 923 | 1,592 | 7,605 | 321 KB/s (one outlier; min/512B → 555 KB/s steady-state) |
| RAW read 8×512B (CMD18) | 2,269 | 2,274 | 2,311 | 1,801 KB/s |
| RAW read 32×512B (CMD18) | 7,791 | 7,800 | 7,881 | 2,100 KB/s |
| **RAW read 64×512B (CMD18)** | 15,154 | 15,162 | 15,243 | **2,161 KB/s** |
| RAW write 8×512B (CMD25) | 2,517 | 2,522 | 2,527 | 1,624 KB/s |
| RAW write 32×512B (CMD25) | 7,960 | 7,960 | 7,962 | 2,058 KB/s |
| **RAW write 64×512B (CMD25)** | 15,484 | 15,486 | 15,492 | **2,115 KB/s** |
| File write 512 B | 5,590 | 6,752 | 13,595 | 75 KB/s |
| File write 4 KB | 11,564 | 13,172 | 18,983 | 310 KB/s |
| **File write 32 KB** | 96,698 | 97,464 | 102,686 | **336 KB/s** |
| File read 4 KB | 4,350 | 4,399 | 4,836 | 931 KB/s |
| File read 32 KB | 32,666 | 32,947 | 34,408 | 994 KB/s |
| File read 128 KB | 130,107 | 130,397 | 131,815 | 1,005 KB/s |
| **File read 256 KB** | 259,836 | 260,149 | 262,578 | **1,007 KB/s** |

### Operating note

When this card is used on the External connector path, the full driver feature surface works. The card behaves like every other catalog card with respect to the driver API. The wedge that defines this card's class on Edge does not manifest on External in any of the 25 regression suites or in two full benchmark passes. Until the Edge-socket workaround ships, **External is the only supported topology for this card.**
