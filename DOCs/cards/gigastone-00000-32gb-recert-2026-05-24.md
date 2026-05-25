# Card: Gigastone 32GB SDHC — Re-Certification 2026-05-24

**Label:** Gigastone 32GB microSD HC I A1 U1 (10)
**Unique ID:** `Transcend_00000_0.0_000001C9_202307`
**Original characterization:** 2026-02-02 — see [gigastone-00000-32gb.md](gigastone-00000-32gb.md)
**This re-cert date:** 2026-05-24
**Socket:** P2 Edge onboard slot
**Driver state:** `main` with uncommitted probe-fix WIP
  (PROBE_SCK_SAMPLES=8, N-sample probe, exact-target SCK pre-backoff; see task #3242)

> **Why a re-cert sheet:** This card was re-run through the full catalog
> procedure (identify → characterize → benchmark @ 350 → benchmark @ 250 →
> full regression including format) to validate that the probe-fix WIP and
> recent driver changes have not regressed performance or correctness on a
> previously-certified Class 10 card. **Existing
> `gigastone-00000-32gb.md` is unchanged**; this file is the independent
> dataset.

---

## Card Designator (2026-05-24)

```
L1: Transcend 00000 SDHC 29GB [FAT32] SD 3.x rev0.0 SN:$0000_01C9 2023/7
L2: Class 10, U1, V10, SPI 22 MHz  [P2FMTER]
L3: CSD claims TRAN_SPEED = 25 MHz; cardWarnings() = $00
```

**Notes:**
- L1 brand reads "Transcend" — MID $74 maps to Transcend OEM silicon
  (Gigastone uses Transcend controllers for this product). Label brand is
  Gigastone; CID brand is Transcend; the catalog tracks both.
- L2 reports **SPI 22 MHz** at the identify tool's sysclk of **320 MHz** —
  **this is integer-hp arithmetic, not driver detuning**. At sysclk 320,
  SCK = 320/(2·hp); hp=7 → 22.857 MHz, hp=6 → 26.667 MHz (over target).
  Ceiling division picks hp=7. Documented in `CATALOG-PROCEDURE.md` table
  ("320 MHz / 7 / 22.857 MHz / no"); this is exactly why catalog benchmarks
  use sysclks 350 and 250 (the only ones that hit exact 25 MHz). The probe
  is *not* engaging the exact-target backoff rule (that rule only fires on
  dummy-CRC cards with `cardWarnings != 0`, and this card has $00). At the
  benchmark sysclks the probe settles cleanly at exact 25 MHz SCK.
- cardWarnings = $00 — no dummy-CRC, no anomaly flags. Clean certified card.

---

## Raw Registers (unchanged from 2026-02-02)

```
CID: $74 $4A $60 $30 $30 $30 $30 $30 $00 $00 $00 $01 $C9 $01 $77 $09
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $E8 $F5 $7F $80 $0A $40 $00 $D1
OCR: $C0FF_8000
SCR: $02 $B5 $80 $83 $00 $00 $00 $00
```

Identical to the 2026-02-02 capture — registers are persistent card state.
Full per-field decomposition lives in `gigastone-00000-32gb.md`; this file
focuses on performance and driver-behavior deltas.

---

## Probe & SPI Frequency (per sysclk)

| Tool | Sysclk | `getSPIFrequency()` reported | Catalog annotation |
|------|---:|---:|:---|
| `SD_card_identify` | 320 MHz | **22_000 kHz** | (identify tool isn't a benchmark row; informational) |
| `SD_card_characterize` | 270 MHz | (see characterize log) | (characterize tool isn't a benchmark row; informational) |
| `SD_performance_benchmark` (high) | 350 MHz | **25_000 kHz** | **350** (no annotation) |
| `SD_performance_benchmark` (low) | 250 MHz | **25_000 kHz** | **250** (no annotation) |

**Catalog Benchmark column notation:** `350+250` — both rows clean at exact
25 MHz SCK, no annotation needed per `CATALOG-PROCEDURE.md` rule.

---

## Performance Benchmark — sysclk 350 MHz, SPI 25 MHz

Source log: `tools/logs/SD_performance_benchmark_260524-122252.log`

### Mount
| Metric | Value |
|---|---|
| Mount time | 226 ms |
| Volume | P2-XFER |
| Free space | 29_815 MB (61_062_848 sectors) |

### RAW Single-Sector (1×512B per operation)
| Operation | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|
| Read  1 sector | 706 us | 756 us | 1_209 us | **677 KB/s** |
| Write 1 sector | 1_326 us | 1_834 us | 5_679 us | **279 KB/s** |

### RAW Multi-Sector (CMD18 / CMD25 bulk)
| Operation | Count | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|---:|
| Read  | 8  | 2_431 us | 2_471 us | 2_824 us | **1_657 KB/s** |
| Read  | 32 | 8_346 us | 8_386 us | 8_751 us | **1_953 KB/s** |
| Read  | 64 | 16_220 us | 16_263 us | 16_643 us | **2_014 KB/s** |
| Write | 8  | 3_331 us | 3_410 us | 3_495 us | **1_201 KB/s** |
| Write | 32 | 8_129 us | 8_598 us | 12_483 us | **1_905 KB/s** |
| Write | 64 | 15_574 us | 15_917 us | 18_324 us | **2_058 KB/s** |

Single-vs-multi (64 sectors): **64% improvement** with CMD18 vs 64×CMD17.

### File-Level (handle API; includes FAT overhead)
| Operation | Size | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|---:|
| Write | 512B | 9_614 us | 12_497 us | 25_600 us | **40 KB/s** |
| Write | 4KB  | 19_269 us | 22_349 us | 23_729 us | **183 KB/s** |
| Write | 32KB | 149_787 us | 152_797 us | 155_339 us | **214 KB/s** |
| Read  | 4KB  | 4_459 us | 4_557 us | 5_448 us | **898 KB/s** |
| Read  | 32KB | 35_709 us | 35_866 us | 37_276 us | **913 KB/s** |
| Read  | 128KB | 144_790 us | 144_941 us | 146_293 us | **904 KB/s** |
| Read  | 256KB | 290_221 us | 290_372 us | 291_728 us | **902 KB/s** |

### Overhead
| Metric | Min | Avg | Max |
|---|---:|---:|---:|
| File Open  | 131 us | 229 us | 1_108 us |
| File Close | 37 us | 37 us | 38 us |
| Unmount    | — | 7 ms | — |

---

## Performance Benchmark — sysclk 250 MHz, SPI 25 MHz

Source log: `tools/logs/SD_performance_benchmark_260524-132552.log`

### Mount
| Metric | Value |
|---|---|
| Mount time | (see log) |
| Free space | 29_815 MB |

### RAW Single-Sector (1×512B per operation)
| Operation | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|
| Read  1 sector | 792 us | 837 us | 1_247 us | **611 KB/s** |
| Write 1 sector | 1_417 us | 1_946 us | 5_718 us | **263 KB/s** |

### RAW Multi-Sector (CMD18 / CMD25 bulk)
| Operation | Count | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|---:|
| Read  | 8  | 2_740 us | 2_777 us | 3_108 us | **1_474 KB/s** |
| Read  | 32 | 9_422 us | 9_460 us | 9_797 us | **1_731 KB/s** |
| Read  | 64 | 18_347 us | 18_386 us | 18_738 us | **1_782 KB/s** |
| Write | 8  | 3_387 us | 3_484 us | 3_560 us | **1_175 KB/s** |
| Write | 32 | 8_997 us | 9_325 us | 11_740 us | **1_756 KB/s** |
| Write | 64 | 17_285 us | 17_641 us | 20_224 us | **1_857 KB/s** |

### File-Level (handle API; includes FAT overhead)
| Operation | Size | Min | Avg | Max | Throughput |
|---|---:|---:|---:|---:|---:|
| Write | 512B | 10_691 us | 12_379 us | 14_847 us | **41 KB/s** |
| Write | 4KB  | 20_148 us | 24_044 us | 30_574 us | **170 KB/s** |
| Write | 32KB | 122_010 us | 152_646 us | 169_046 us | **214 KB/s** |
| Read  | 4KB  | 5_085 us | 5_211 us | 6_339 us | **786 KB/s** |
| Read  | 32KB | 39_951 us | 40_158 us | 42_020 us | **815 KB/s** |
| Read  | 128KB | 162_588 us | 162_821 us | 164_608 us | **805 KB/s** |
| Read  | 256KB | 326_737 us | 326_955 us | 328_775 us | **801 KB/s** |

### Overhead
| Metric | Min | Avg | Max |
|---|---:|---:|---:|
| File Open  | 184 us | 287 us | 1_216 us |
| File Close | 52 us | 52 us | 53 us |
| Unmount    | — | 3 ms | — |

---

## 350 vs 250 Spread (bus-bandwidth vs command-overhead)

At equal SPI clock (25 MHz on both rows), the 350→250 drop isolates code paths
dominated by **cog-side overhead** (visible at 250) vs **bus-side throughput**
(equal across both):

| Path | 350 KB/s | 250 KB/s | Δ (%) | Dominated by |
|---|---:|---:|---:|---|
| RAW read 1 sector | 677 | 611 | -10% | command overhead |
| RAW write 1 sector | 279 | 263 | -6% | card-side R2W |
| RAW read 64 sectors | 2_014 | 1_782 | -11% | SPI streamer + cog setup |
| RAW write 64 sectors | 2_058 | 1_857 | -10% | SPI streamer + cog setup |
| File write 32KB | 214 | 214 | 0% | card-side R2W (FAT + erase) |
| File read 32KB | 913 | 815 | -11% | SPI streamer + FAT walk |
| File read 256KB | 902 | 801 | -11% | SPI streamer (steady state) |

The ~10% spread on read paths is the expected cog-cycle drop (350/250 = 1.4× of
non-bus overhead). The 0% spread on the file-write 32KB path confirms write
throughput is card-side-limited (R2W_FACTOR=4 + FAT-update cost), not driver-
limited.

### Decomposition — RAW read 64 sectors (32 KB at SPI 25 MHz)

Solving the two-row system to separate bus time from cog overhead:

```
350: 16_220 us = X + B       (X = cog overhead at 350, B = bus time at SCK)
250: 18_347 us = 1.4·X + B   (sysclk 1.4× slower → cog overhead 1.4× longer)
```

| Quantity | Value |
|---|---:|
| Bus time B (same both rows, SPI 25 MHz) | **10_902 us** |
| Cog overhead X (at sysclk 350) | **5_318 us** |
| Cog overhead at sysclk 250 (= 1.4·X) | **7_445 us** |
| Bus throughput (32_768 B / 10_902 us) | **3.005 MB/s** |
| SPI theoretical ceiling (25 Mbps / 8) | 3.125 MB/s |
| **Bus efficiency** (driver streamer vs SPI ceiling) | **96.2%** |
| Bus share @ 350 | 67% |
| Bus share @ 250 | 59% |

**Reading this:** the streamer/DMA path hits 96% of the SPI bus ceiling, so
there's almost no room to improve the bus portion. The 10% sysclk-dependent
drop is the signature of a *bus-dominated* driver, which is the goal. A
cog-dominated driver would show a 30 %+ drop on the same comparison; we see
~11%. **This is not a regression — same SPI clock means same bus time; the
cog portion has to be longer at lower sysclk.**

---

## Comparison vs Original 2026-02-02 Catalog Entry

The original `gigastone-00000-32gb.md` does not include per-row throughput
numbers (the catalog data sheet at that time recorded register decomposition
only; performance numbers landed in `CARD-CATALOG.md` notation `350+250` with
no detailed breakdown).

**Catalog-level summary delta:**

| Metric | 2026-02-02 entry | 2026-05-24 re-cert | Status |
|---|---|---|---|
| Catalog grade | C (PASS) | (regression results below) | — |
| SPI clock @ benchmark | 25 MHz | 25 MHz | unchanged |
| Probe behaviour @ 320 MHz sysclk | (not captured) | detunes to 22 MHz | new data point |
| `cardWarnings()` | (not captured pre-feature) | $00 | clean |
| MOUNT time | (not captured) | 226 ms | new baseline |
| Regression suites passing | "all tests pass" | (see Regression section) | — |

---

## Regression Results — Full Suite Including Format

**Run:** 2026-05-24, P2 Edge socket, sysclk 350 MHz, `--include-format`
**Result:** **ALL 25 SUITES PASSED — 467 tests, 0 failures, 319 s runtime**

| #  | Suite                       | Pass | Fail | Time |
|---:|-----------------------------|-----:|-----:|-----:|
|  1 | SD_RT_mount_tests           |   31 |    0 |  61s |
|  2 | SD_RT_raw_sector_tests      |   14 |    0 |   2s |
|  3 | SD_RT_multiblock_tests      |    6 |    0 |   3s |
|  4 | SD_RT_register_tests        |   10 |    0 |  13s |
|  5 | SD_RT_speed_tests           |   15 |    0 |  14s |
|  6 | SD_RT_crc_diag_tests        |   14 |    0 |  14s |
|  7 | SD_RT_error_handling_tests  |   14 |    0 |   2s |
|  8 | SD_RT_crc_validation_tests  |    6 |    0 |   3s |
|  9 | SD_RT_recovery_tests        |    7 |    0 |   2s |
| 10 | SD_RT_file_ops_tests        |   26 |    0 |  14s |
| 11 | SD_RT_read_write_tests      |   48 |    0 |  41s |
| 12 | SD_RT_multihandle_tests     |   21 |    0 |  14s |
| 13 | SD_RT_seek_tests            |   37 |    0 |  13s |
| 14 | SD_RT_volume_tests          |   31 |    0 |  39s |
| 15 | SD_RT_subdir_ops_tests      |   18 |    0 |   2s |
| 16 | SD_RT_directory_tests       |   30 |    0 |  16s |
| 17 | SD_RT_dirhandle_tests       |   25 |    0 |  14s |
| 18 | SD_RT_fifo_tests            |   21 |    0 |   2s |
| 19 | SD_RT_multicog_tests        |   14 |    0 |   2s |
| 20 | SD_RT_cogcwd_tests          |    5 |    0 |   3s |
| 21 | SD_RT_timestamp_tests       |    6 |    0 |  12s |
| 22 | SD_RT_stress_tests          |    4 |    0 |   3s |
| 23 | SD_RT_async_tests           |    6 |    0 |   2s |
| 24 | SD_RT_defrag_tests          |   12 |    0 |   7s |
| 25 | SD_RT_format_tests          |   46 |    0 |  21s |
|    | **TOTAL**                   |**467**|  **0** | **319s** |

**Verdict:** Driver passes 100% of regression suites against this card with
format included, matching the 2026-02-02 "Class C / PASS" certification.
No regressions from probe-fix WIP, dummy-CRC support, MODE_CHECK addition,
or other recent driver work.

### Notable suite timings

- `SD_RT_mount_tests` at 61s — repeated unmount→mount cycles all clean
  (no recurrence of the Cloudisk-on-Edge wedge tracked in #3240 on this card)
- `SD_RT_format_tests` at 21s — format + mount + post-format ops all pass
- `SD_RT_read_write_tests` at 41s — full file-IO surface clean

---

## Source Logs (this re-cert)

- Identify:      `tools/logs/SD_card_identify_260524-121955.log`
- Characterize:  `tools/logs/SD_card_characterize_260524-122219.log`
- Benchmark@350: `tools/logs/SD_performance_benchmark_260524-122252.log`
- Benchmark@250: `tools/logs/SD_performance_benchmark_260524-132552.log`
- Regression run: `/tmp/regression_recert_2026-05-24.log`
  (per-suite logs in `tools/logs/SD_RT_*_260524-*.log`)
