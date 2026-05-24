# SD Card Catalog Procedure

The standard sequence for adding a card to the catalog or re-characterizing an
existing entry. All steps run from `tools/` via `run_test.sh`.

## Prerequisites

- Card physically inserted in the target socket
  - **P2 Edge socket** (default pins CS=60, MOSI=59, MISO=58, SCK=61) — the production target
  - **External SD header** — `SD_PINS_EXTERNAL` build flag selects pins CS=20, MOSI=19, MISO=18, SCK=21
- Note which socket; performance can vary (Edge has tighter SI margin than the external header)

## Sysclk choices

All tools default to a sysclk from the family "**350 MHz and lower**". When the
catalog procedure requires multiple sysclk runs of the same tool, at least one
of those sysclks must yield an **exact 25 MHz SCK** so throughput numbers are
directly comparable across cards.

| Sysclk | Default `hp` at target=25 MHz | Actual SCK | Exact 25 MHz? |
|---:|---:|---:|:---:|
| 350 MHz | 7 | 25.000 MHz | **yes** |
| 320 MHz | 7 | 22.857 MHz | no |
| 300 MHz | 6 | 25.000 MHz | **yes** |
| 270 MHz | 6 | 22.500 MHz | no |
| 250 MHz | 5 | 25.000 MHz | **yes** |

Established catalog convention is **350 + 250** for the benchmark sweep. Both
land on exact 25 MHz SCK; the spread isolates command/overhead-dominated paths
(visible at the low-sysclk run) from bus-bandwidth-dominated paths.

## Rule: record actual SPI clock when ≠ 25 MHz

**Sysclk alone is sufficient ONLY when `getSPIFrequency()` reports exactly
25_000 kHz.** That's the assumed default; the catalog convention bakes in
"25 MHz unless stated otherwise."

When the driver's probe detunes the SPI clock below 25 MHz (counterfeit /
dummy-CRC / marginal cards), the benchmark entry MUST record both the sysclk
and the actual SPI clock so throughput numbers stay comparable across cards.

| Condition | Catalog notation |
|---|---|
| Both benchmark runs at SPI 25 MHz | `350+250` (bare — 25 MHz assumed) |
| Benchmark detuned at one sysclk | `350@22M+250` (only the detuned row annotated) |
| Both detuned | `350@22M+250@22M` |
| Other SPI target | `350@<N>M+250@<N>M` |

This applies to:

- **`CARD-CATALOG.md` Benchmark column** — short notation as above
- **Per-card data sheets** — record both sysclk AND `getSPIFrequency()` value
  next to each throughput row
- **`CARD-REFERENCE.md` Line 2** — already records SPI MHz; verify it matches
  the benchmark's `getSPIFrequency()` (mismatch is a data-quality bug)

The `SPI Frequency: <N> kHz` line in the benchmark log is the source of truth.
Always read it before transcribing numbers; do not assume 25 MHz silently.

**Why this matters:** Two cards showing the same throughput at the same sysclk
look equivalent — but if one ran at 25 MHz and the other at 21.875 MHz, the
slower-clock card is actually *faster per bus cycle*. Without the SPI annotation,
the catalog conflates "slow card" with "card the driver had to detune."

## Steps

### 1. Identify (fingerprint)

```bash
./run_test.sh ../src/UTILS/SD_card_identify.spin2
```

- Default sysclk: 350 MHz (lands on exact 25 MHz SCK; file-level constant, change if needed)
- Output: 3-line designator (CID/CSD/SCR-derived) — paste into `CARD-REFERENCE.md`
- Also reports `getSPIFrequency()` (driver's settled operating SPI rate) and
  `cardWarnings()` (CW_NO_DATA_CRC for dummy-CRC cards, etc.)

### 2. Characterize (full register dump)

```bash
./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 90
```

- Default sysclk: 350 MHz (lands on exact 25 MHz SCK; file-level constant)
- Output: every CID/CSD/SCR/OCR/MBR/VBR field, marked `[USED]` or `[INFO]`
- Ends with `END_CHARACTERIZATION` (not `END_SESSION`); the script will
  timeout, but the data is complete in `tools/logs/`
- **NOTE:** `SD_card_characterize` uses `initCardOnly()`. Running it
  immediately after another tool that did a full `mount()` + `unmount()` may
  fail to init on some cards — workaround is power-cycling the P2 Edge board
  before this step. Tracking as bug `#3240`.

### 3. Performance benchmark — first sysclk (350 MHz)

```bash
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
```

- Default sysclk: 350 MHz
- Output: throughput for RAW single-sector, RAW multi-sector (CMD18/CMD25 at
  8/32/64 sectors), and FILE-LEVEL (handle API) at standard sizes
- Capture the log; paste numbers into the card's per-card data sheet
- **Read the `SPI Frequency:` line** in the log. If it's not 25_000 kHz,
  annotate the benchmark entry per the "Rule: record actual SPI clock" above
  (e.g., `350@22M` instead of bare `350`).

### 4. Performance benchmark — second sysclk (250 MHz)

```bash
# Edit _CLKFREQ from 350_000_000 to 250_000_000 in:
#   src/UTILS/SD_performance_benchmark.spin2
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
# Restore _CLKFREQ to 350_000_000 when done
```

- Same throughput categories, lower sysclk
- Per-card data sheet records both rows: `350 MHz` and `250 MHz`
- Card-catalog `Benchmark` column annotation: `350+250` (or annotated form
  if SPI detuned — see "Rule: record actual SPI clock" above)
- **Read the `SPI Frequency:` line** at this sysclk too. Both rows must match
  the convention; mismatched assumptions are how throughput comparisons go
  silently wrong.

### 5. Annotate

- Update `DOCs/cards/CARD-REFERENCE.md` with the 2-line designator
- Update `DOCs/cards/CARD-CATALOG.md` with the entry
- Add per-card data sheet `DOCs/cards/<vendor>-<pnm>-<size>.md` with full data
- Mark the `Benchmark` column with `350+250` (or other sysclk pair if used)

## Optional / situational steps

- **Counterfeit / dummy-CRC cards**: also capture `cardWarnings()` value and
  any `probeSpiCeiling` debug output. The card-catalog quirks table records
  the SCK ceiling (clean) and forced-corruption (fail) bounds.
- **Edge-vs-external comparison**: when SI margin is suspected, re-run steps 3
  and 4 in both sockets. Differences > a few % point at SI sensitivity.
- **Multi-card-position runs**: if running multiple cards in sequence, power-
  cycle the P2 Edge between cards (serial-download reset does not drop SD VCC).

## Why "350 and lower"

The driver's `hp` is an integer number of sysclks; ceiling-rounded division
means most sysclks land an SCK *below* the target 25 MHz. Only the sysclks
listed above (multiples of `2 × target`) hit exact 25 MHz. Choosing sysclks
from the "350 and lower" family that satisfy this keeps catalog throughput
numbers honest and comparable; running at sysclks that land at e.g. 22.857 MHz
SCK would slightly understate throughput for no good reason.

## Tool sysclk defaults (current)

| Tool | `_CLKFREQ` | Notes |
|------|---:|---|
| `SD_card_identify` | 350 MHz | One-shot register read; aligned with benchmark sysclks (exact 25 MHz SCK) |
| `SD_card_characterize` | 350 MHz | One-shot register dump; aligned with benchmark sysclks (exact 25 MHz SCK) |
| `SD_performance_benchmark` | 350 MHz | Edit to 250_000_000 for the low-sysclk catalog row |
| Regression suites | 350 MHz | Standardized across all `SD_RT_*_tests.spin2` |
