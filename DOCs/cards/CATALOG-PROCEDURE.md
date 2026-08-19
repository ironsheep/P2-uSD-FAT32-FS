# SD Card Catalog Procedure

The standard sequence for adding a card to the catalog or re-characterizing an
existing entry. All steps run from `tools/` via `run_test.sh`.

## The two tables, and the rule that keeps them apart

The catalog publishes performance in **two tables that are never merged**:

| Table | Instrument | What it measures |
|---|---|---|
| Card capability (random access) | `diagnostic-tests/SD_speed_characterize.spin2` | The **card**. Random single-sector reads pay full internal seek latency, so cards spread ~38x |
| Driver throughput by traffic type | `src/UTILS/SD_performance_benchmark.spin2` | The **driver**. Sequential and file traffic, where the bus limits and cards nearly converge |

**Never compare a number from one against a number from the other.** They ran
different workloads. A comparison across instruments shows a large gain or loss
that is purely an instrument change, and a single mixed table is exactly how the
old catalog produced rows that were not comparable to each other. When you need a
before/after, the comparator is a **same-instrument, same-session** arm.

**Rows are harvested, not transcribed.** Both instruments emit `CATALOG-CARD` and
`CATALOG-ROW` lines. `tools/harvest_catalog.sh` turns a set of logs into the
Markdown tables:

```bash
./harvest_catalog.sh logs/SD_speed_characterize_*.log logs/SD_performance_benchmark_*.log
```

Hand-transcription is what produced three different row labels for one
measurement across eras, and six cards whose data never reached the summary at
all. It also refuses to emit a table spanning two driver versions.

**Every run stamps the driver version.** `driverVersionString()` goes into both
instruments' output and into the harvested banner, because throughput is a
property of the driver as much as of the card.

## Two populations of card, and only one of them gets a record

**A catalog card is committed to this project permanently.** It stays available to
be re-measured for as long as it works, and **dying is the only way out** of the
population. That commitment is the entire basis of the pristine-table format: one
banner naming the driver version, no per-row provenance and no exception table is
only honest because a full re-sweep is one afternoon — which is only true if every
card carrying a performance row is still on the shelf.

**Everything else is working stock**, needed elsewhere. Such a card may be measured
while it is on the bench, but it then goes into service and never comes back.

| | Catalog card | Working stock |
|---|---|---|
| Card record | **Yes** | **No** |
| Performance row | Yes | Never |
| Re-measurable on the next release | Yes | No |
| Leaves the population when | It dies | It is deployed |

**Measurements from working stock go in the experiment record that produced them**,
not into a card record. A card record asserts re-sweepability; a one-shot number
from a card that has left is an experiment datapoint. Keeping the two apart is what
keeps the card-record population exactly equal to the re-sweepable population, which
is what makes the check mechanical.

### Marking identical units: green means catalogued

Two units of one product are indistinguishable by eye, and a card record is useless
if nobody can tell which card in the hand it describes. The convention, already in
effect for the 32 GB Gigastone pair and now deliberate:

> **A green highlighter mark means: this is the retained, catalogued unit.**

That makes the mark carry information rather than being an arbitrary tiebreak, and
it doubles as a **do-not-deploy** signal — green is a card committed to the project,
and retained cards leave the population only by dying. Cards bearing a mark record
it in a **`Physical mark:`** line, so the hand-to-record mapping survives outside
the run notes where it currently lives.

Confirm the mark against the PSN once, in a transcript, and state it in the record.
The 32 GB pair is the worked example: GREEN is `$0000_01C9`, unmarked is
`$0000_01C7`, PSN-confirmed in every socket-campaign run.

Every card record therefore carries a **`Disposition:`** line, validated by
`tools/check_card_labels.sh`:

| Value | Meaning |
|---|---|
| `retained` | Committed to the project; re-measurable. The normal case |
| `dead` | Was retained, has failed. Record and historical data stay; no new rows |
| `deployed` | Measured once, then went into service. Should rarely have a record at all |
| `not-in-possession` | Never ours, or returned — e.g. a customer's card |
| `not-located` | Believed retained, cannot currently be found |

Availability used to live in prose scattered across three documents. Reading it
that way is how the working 8 GB Kingston came to be annotated with the death of a
different, uncatalogued 2 GB Kingston.

## Run variance is measured BEFORE instance variance

One physical card has been measured moving up to **3x between rounds**, with 6x
dispersion inside a single measurement loop, while another arm on the same card
repeated to 0.3%. So:

1. **Repeat one card several times first.** Set `REPEAT_RUNS` in
   `SD_performance_benchmark.spin2` above 1; every emitted row carries its run
   number and the harvested table shows the spread as a **range, never an
   average**.
2. **Only then compare instances.** Comparing five cards of one model before the
   run-to-run spread is known attributes run noise to units.
3. **Order may matter.** A card's first run can differ from its later ones, so
   record the order runs were taken in.
4. **Any card showing wide dispersion needs repeat runs before a delta is
   believed** — including a delta against a previous release.

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
- **Was bug `#3240`, fixed in v1.8.0.** `SD_card_characterize` uses
  `initCardOnly()`, and running it after another tool that had used the card
  used to fail to init until the board was power-cycled. The cause was the boot
  sequence leaving the card mid-transfer on boards where the microSD socket
  shares pins with the boot flash; card initialisation now issues a
  stop-transmission command first. **No power cycle is needed between steps on
  v1.8.0 or later.**

### 3. Card capability — random access

```bash
./run_test.sh ../diagnostic-tests/SD_speed_characterize.spin2 -t 300
```

- Populates the **card capability (random access)** table. This step was missing
  from the procedure until 2026-08-19, which is why that table was never
  systematically filled.
- Walks a speed ladder and, at each level that passes, reports random-access
  throughput and latency from Phase 2's 10,000 random single-sector reads.
- **This tool lifts the production speed bound** (`debugSetOverspeedAllowed`) so
  it can probe above the card ceiling, and says so unconditionally in its own
  transcript. It also prints the **LANDED** clock read back from the driver at
  each level, not a predicted one — a level whose landed clock differs from the
  request is flagged in place, and its numbers belong to the landed clock.
- Read the `CATALOG-ROW: instr=random_access` lines, or harvest them.

### 4. Performance benchmark — first sysclk (350 MHz)

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

### 5. Performance benchmark — second sysclk (250 MHz)

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

### 6. Annotate

- Update `DOCs/cards/CARD-REFERENCE.md` with the 2-line designator
- Add per-card data sheet `DOCs/cards/<vendor>-<pnm>-<size>.md` with full data
- **Do NOT hand-type performance rows into `CARD-CATALOG.md`.** Run
  `./harvest_catalog.sh` over the session's logs and paste its output under the
  matching heading. Register and identity data is still entered by hand — it is a
  card property, it never stales, and it carries no version banner.
- Mark the `Benchmark` column with `350+250` (or other sysclk pair if used)

## Full-catalog sweep (release gate)

A release that touches the I/O path re-sweeps every working card, because every
published figure is a measurement of the driver that produced it. This is a
**gate for v1.8.0**, set by Stephen on 2026-08-19: nothing ships until the catalog
carries numbers taken on the shipping driver.

The sweep is roughly one afternoon for the whole drawer, which is why the tables
are pristine — one banner naming the driver version, no per-row provenance and no
exception table. That trade only holds if the sweep actually gets run.

Before starting, confirm `./check_doc_version.sh` passes: it verifies the driver's
version constant, its printable string and the newest changelog heading all agree.
A sweep run under a stale constant mislabels every row it produces, and the
mislabelling is indistinguishable from correct data afterwards.

## Optional / situational steps

- **Counterfeit / dummy-CRC cards**: also capture `cardWarnings()` value and
  any `probeSpiCeiling` debug output. The card-catalog quirks table records
  the SCK ceiling (clean) and forced-corruption (fail) bounds.
- **Edge-vs-external comparison**: when SI margin is suspected, re-run steps 4
  and 5 in both sockets. Differences > a few % point at SI sensitivity.
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
| `SD_speed_characterize` | 350 MHz | Capability table instrument; was 270 MHz, which landed 22.5 MHz for a 25 MHz request |
| `SD_performance_benchmark` | 350 MHz | Edit to 250_000_000 for the low-sysclk catalog row |
| Regression suites | 350 MHz | Standardized across all `SD_RT_*_tests.spin2` |
