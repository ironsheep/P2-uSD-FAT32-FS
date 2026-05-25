# Card: "Lerdisk" 1 GB SDSC (counterfeit twin of Cloudisk asdfg)

**Label:** microSD 1GB Class 4 — "Lerdisk"
**Unique ID:** `Unknown_asdfg_2.2_000001F4_202512`
**Test Date:** 2026-05-24 (Edge socket, P2 Edge module)
**Reporter:** stephen@ironsheep.biz
**Status:** Characterization in progress — see Test Results

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
- **Wedge bug #3240 reproduces consistently**: every fresh `mount()` (or `initCardOnly()`) after a prior unmount on this card *requires a P2 Edge power-cycle*. The driver eventually times out, but no software-level reset clears the wedge. Same pattern as Cloudisk.
- **Performance comparable to Cloudisk class** (per resume context). At sysclk=350 the multi-read peaks at 2,359 KB/s — slower than mainstream SDHC cards (~7-15 MB/s at 25 MHz) but consistent with a counterfeit SDSC controller running below 22 MHz.
