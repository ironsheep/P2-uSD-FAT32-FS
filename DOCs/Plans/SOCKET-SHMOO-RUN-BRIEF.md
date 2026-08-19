# Socket Shmoo — Bench Run Brief

**For:** the host-native bench agent (hardware side of this two-agent effort).
**Authored:** 2026-08-17, container side.
**Plan:** `DOCs/Plans/SOCKET-TIMING-CHARACTERIZATION-PLAN.md` (results so far: §11).

## ⟹ CURRENT STATE + WHAT TO RUN NEXT (updated 2026-08-19, round 16 queued)

🔑 **The #3240 wedge is root-caused AND fixed.** Boot-time access to the shared
flash/microSD pins leaves the card mid-transfer; **CMD12 before CMD0 aborts it**.
Proven on hardware — five clean warm runs across two power cycles, each pair
followed by a build without the step, which wedged both times.

**The fix is now unconditional in `initCard()`** — no flag, every driver start
(Stephen, 2026-08-19). Release is **v1.8.0**.

**Run next: ROUND 16 — certification, then the catalog sweep.**

| Track | What | Why |
|---|---|---|
| **16a** | Full regression, standard card, quiesce now default | Certifies a change that touches every card start |
| **16b** | Full regression on the **Lerdisk in the EDGE socket** | The card the whole campaign was about. Its record says "External only" — this may now be wrong |
| **16d** | 🔑 **The missing H2 cell** — HS mode negotiated, writes clocked at 25 MHz | **Decides whether the read/write speed policy can be general.** Run BEFORE 16c |
| **16e** | Multi-card: run variance, then instance variance | Tells us whether any card-to-card delta means anything |
| **16c** | 🔴 **Full catalog performance sweep, TWO-ARMED** | **RELEASE GATE** — v1.8.0 does not ship without it |

---

## ROUND 16d — the cell nobody has run

**One card (Samsung EVO `$4AC8_5F42`), one arm, a few minutes. Run it before 16c.**

Rounds 10b and 11b compared *(default mode, 25 MHz)* against *(HS mode, 43.75 MHz)*
— **two variables moved at once.** So the Samsung's reproducible −52% write
regression has never been attributed to either one. The missing cell is:

> **High speed negotiated via CMD6, then writes clocked at 25 MHz.**

The spec permits this: High Speed is *"Frequency up to 50 MHz"* (Part 1, bus speed
mode list) — a ceiling, not a required rate, and stated differently from UHS-II
which is given as a *range*. So a card can sit in high-speed mode while the host
clocks writes down.

The driver already supports it without new machinery: `effectiveAlignDelay()` is
called at each burst site and derives from the live `spi_period`, so a
per-operation clock change automatically picks up the hp=4 floor rule at 43.75 and
the +5 offset at 25.

**What each outcome means:**

| Result | Meaning | Policy |
|---|---|---|
| Writes recover at 25 MHz | The regression is **clock-side** | Asymmetric policy works and is **general** — reads fast, writes at 25, one rule for every card |
| Writes still slow | The regression is **mode-side** | Dropping the clock cannot help. Choice narrows to keeping high speed opt-in, or shipping it by default and accepting one controller family's write loss for +47% reads everywhere |

Switching the card back per-write via CMD6 is viable per-*session* only, never
per-operation — that is an API question, not a default-policy one.

---

## ROUND 16e — multi-card: run variance, then instance variance

**Available matched sets:** 5x Gigastone Camera Plus 64GB, 3x Lexar 64GB (red),
2x SanDisk Extreme 64GB. Each set already has one catalogued unit, so every new
unit has a known comparator.

**Step 0 — identify all of them first.** `SD_card_identify` on every card in the
set before any measurement. **Same label does NOT mean same silicon**:
Gigastone-printed labels sit on four different MIDs in this drawer, and SKUs get
re-sourced silently. If the five Camera Plus units split across silicon keys, the
experiment is not spoiled — it becomes a direct measurement of how much a
re-sourced SKU varies under one printed label. But we must know which experiment
we are running before we run it.

**Step 1 — RUN variance, on ONE Gigastone.** `REPEAT_RUNS > 1` in the benchmark.
Round 11b measured one physical card moving up to 3x between rounds, so a
card-to-card delta means nothing until the same-card spread is known. Use a card
from the instance set, so the two variances share silicon and are directly
comparable without a bridge.

**Step 2 — INSTANCE variance, all 5 Gigastones.** n=5 is the only set here that
can show a distribution; n=2 cannot, and n=3 is thin.

**Step 3 — the 3 Lexar reds. NOT optional, and not a curiosity.** The Lexar red is
one of the three H2 cards and the clean-win case (+47% reads, +44% writes in high
speed). **Every H2 conclusion is n=1 per card**, and it is about to inform a
shipped default policy. Three units say whether "the Lexar gains 44% on writes" is
a property of the product or of that one unit. If unit variance is large, the H2
evidence base needs re-reading before the policy ships.

**Step 4 — the 2 SanDisk Extremes.** n=2 cannot give a distribution but will catch
a gross outlier cheaply. Lowest priority.

### THE DEPLOYMENT-BOUND UNITS ARE A ONE-SHOT

Of each matched set, only the catalog cards stay. The retained Gigastones are the
**unmarked and green 32 GB pair** plus the **Camera Plus 64 GB** (`00000F14`); the
retained Lexar is the one red already catalogued
(`Longsys/Lexar_MSSD0_6.1_33549024_202411`). Every other unit in the 5x Camera Plus
and 3x Lexar sets is working stock — measured on the bench, then deployed, and
**they do not come back.**

Two consequences that change what to do in the session:

1. **Capture everything from them while they are on the bench**, not just the
   instance-variance datapoint: identity, both speed arms, the full benchmark. There
   is no second chance, and a gap found during write-up cannot be filled.
2. **The n=5 and n=3 findings are unrepeatable by construction.** Any future
   re-check can only use the retained units — two Gigastones and one Lexar. The
   write-up must say so rather than implying the experiment can be redone.

They get **no card records** (see CATALOG-PROCEDURE.md, "Two populations of card").
Their CIDs and measurements live in this round's run notes, because a card record
asserts re-sweepability and these cards will not be.

### STEP 0a — ONE-TIME: identify the two retained 64 GB units, then mark

**Do this before the five Camera Plus units are handled together, and do it once.**

```bash
cd tools
./run_test.sh ../src/UTILS/SD_card_identify.spin2      # card A
./run_test.sh ../src/UTILS/SD_card_identify.spin2      # card B
```

**READ FIRST, MARK SECOND.** The order is what makes this a one-time job:

1. Run identify on each of the **two retained** 64 GB cards, one at a time. Note
   which physical card produced which transcript as you go — the P2 cannot see a
   highlighter, so this one correspondence is yours to hold for the length of two
   runs and no longer.
2. One of them is PSN `$0000_0F14`, the already-catalogued
   `GigastoneOEM_ASTC_2.0_00000F14_202306`. **Mark that one green.**
3. The other is the second retained unit. Its transcript's `CARD-ID:` line is what
   its new card record is keyed on.

Marking *after* reading means green = catalogued **by construction**, matching the
32 GB pair, and nothing has to be discovered later. Marking first would invert the
job into working out which card happens to be green.

`SD_card_identify` now emits `SILICON-KEY:`, `CARD-ID:` and a `CATALOG-CARD:` line
alongside the human-readable designator, so both new card records are built from
the transcripts rather than retyped from them.

**If neither card reads `$0000_0F14`**, stop and re-check which cards are the
retained pair before marking anything — the catalogued unit is somewhere in the
set of five, and marking the wrong one puts a retained card in the deploy pile.

**Do the same for the 32 GB pair if convenient**, though its mapping is already
PSN-confirmed: GREEN `$0000_01C9`, unmarked `$0000_01C7`. Only the unmarked one's
card record is owed.

### ⚠ FOUR RETAINED GIGASTONES, TWO CARD RECORDS — AND GREEN MEANS CATALOGUED

Two pairs are retained, one pair per product. **Only one unit of each pair has ever
been catalogued**, so two card records are owed from this round:

| Product | Green (catalogued) | Unmarked (NO RECORD) |
|---|---|---|
| Gigastone 32 GB | PSN `$0000_01C9` = `Transcend_00000_0.0_000001C9_202307` | PSN `$0000_01C7` — **owed** |
| Gigastone Camera Plus 64 GB | PSN `$0000_0F14` = `GigastoneOEM_ASTC_2.0_00000F14_202306` | PSN unknown — **owed** |

**The convention is: green = the retained, catalogued unit.** That is already true
of the 32 GB pair, PSN-confirmed in every socket-campaign transcript, and the 64 GB
green mark is being applied to match. It doubles as a **do-not-deploy** signal —
green is committed to the project, and retained cards leave only by dying.

**(a) Mark the 64 GB `00000F14` green BEFORE the five Camera Plus units are mixed
together.** Otherwise the retained unit is indistinguishable from the four
working-stock units, and deploying it would remove a card from the permanent
population by a route the model does not allow. If they are already mixed, read all
five PSNs first and mark `00000F14` on the spot.

**(b) The unmarked 32 GB `$0000_01C7` has carried socket-campaign data since round
5 and still has no card record.** That is the "measured but never reached the
catalog" failure mode, live. Create its record from this round.

**(c) Confirm each new mark against a PSN in a transcript**, and put it in the card
record's `Physical mark:` line. Today that mapping lives only in the run notes.

**Record how and when each unit was purchased.** Five cards from one batch are
likely one production run, which measures *within-batch* variance — the narrowest
case, and it understates real-world spread. The write-up has to say which was
measured.

**Catalog consequence:** each unit gets its own card record keyed by its own Card
ID, all pointing at the same label ID in `CARD-LABELS.md`. This is the first
many-to-one use of the label master; today it is 1:1 throughout.

---

## ROUND 16c — the sweep is TWO-ARMED

Standard **and** high-speed arms, same session, same card, same instrument.

**Why both, rather than picking one:** the sweep measures the default I/O path, and
whether high speed becomes the default is undecided until 16d. A single-arm sweep
taken before that decision is obsolete the day the policy lands — every read row
moves by up to +47%. Two arms produce the release numbers for **whichever** policy
ships, answer the policy question across the whole fleet instead of three cards,
and satisfy the same-instrument/same-session comparator rule. Cost is roughly
double: one long afternoon instead of one.

Procedure: `DOCs/cards/CATALOG-PROCEDURE.md`. Harvest with
`tools/harvest_catalog.sh`; do not hand-type rows. Confirm
`tools/check_doc_version.sh` passes before starting — a sweep run under a stale
version constant mislabels every row it produces, indistinguishably from correct
data.

## What this tool does

One binary sweeps SPI half-period hp=14→4 (12.5 → 43.75 MHz at 350 MHz sysclk) ×
sampling mode (ON-edge `%1_00111`, PRE-edge `%0_00111`) × socket (Edge onboard, then
external adapter, one powered session). Each cell reads sector 1000 eight times per
path — Path A byte-by-byte through the MISO smart pin (the sampling-mode curve),
Path B through the production streamer — and scores cmd/crc/data errors separately.
**Read-only; it never writes either card.**

## Setup

1. Populate **both** sockets. Primary protocol (plan §4.1): a **matched same-vendor
   pair** (same model; name them by brand + label size in your notes). Single-socket
   sessions also work — the tool reports the empty socket and produces a half-matrix.
2. No `-D` flags — both pin sets are baked into the one binary (Edge 60/59/58/61,
   adapter 20/19/18/21).

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300
```

Clean sweep ≈ a couple of minutes. Cells that fail burn read-timeouts (~100–200 ms
each, early-abort after 2 consecutive), hence `-t 300`.

## The session sequence (2×2 crossed design)

Selected pair for this campaign: **two Gigastone 32GB cards** (Stephen, 2026-08-17).
One is marked with a **green highlight**; the other is unmarked.

1. **Run 1:** unmarked card in Edge (onboard), **GREEN card in the external
   adapter** (Stephen's placement, 2026-08-17).
2. **Run 2:** swap — GREEN to Edge, unmarked to adapter. Same powered session if
   practical.
3. Each socket phase prints a full identity block — MID/OID/PNM/rev, then a
   `>>> SERIAL PSN=$xxxxxxxx  mfg YYYY/M <<<` line, then the raw 16-byte CID.
   A same-model pair is identical in everything **except PSN and possibly the
   mfg date** — the PSN is the ground truth for which card was where.
4. **At run 1, record the PSN↔card mapping from the transcript:** the ADAPTER
   phase's PSN is the GREEN card, the EDGE phase's PSN is the unmarked card.
   State it explicitly in the run notes ("GREEN = PSN $…, unmarked = PSN $…").
   Run 2's transcripts then prove the swap happened, and the card-vs-socket
   separation algebra keys off it.

## Reading the output

- Per-cell rows: `hp freq_kHz mode | A: cmd crc data | B: cmd crc data` — counts are
  error reads out of 8. A first data-mismatch in a cell prints one detail line
  (diff count, first offset, expected/got) so a shifted read names itself.
- Per-socket summary grid, then a cross-socket comparison: the clean boundary
  (fastest hp with that and every slower cell clean) per mode/path, per socket.
  **The boundary delta between sockets is the number this whole exercise is after.**
- `254` = cell aborted on consecutive cmd failures; `255` = never ran.

## Warnings that are signal, not faults

- `WARNING: CRC scoring appears INACTIVE` — the card carries the no-data-CRC quirk;
  crc columns will be 0, cmd/data columns still score. Note which card.
- `WARNING: hp=N requested but driver landed M` — the frequency-request rounding
  missed its hp target; report it, the container side will fix the request math.
- `Reference reads DISAGREE at benign speed` — the socket can't even baseline at
  2 MHz; that socket is skipped. That itself is data — report it.

## First-light risks (dial-in expectations)

This tool exercises `stop()` → `initCardOnly()` on a different pin base for the
first time in this codebase's diagnostics. If the **adapter phase** fails to init
after a clean Edge phase, suspect the restart path before suspecting the socket.
Also: if every cell of a socket fails identically including hp=14/12.5 MHz, the
tool (or wiring) is broken, not the timing — 12.5 MHz should be trivially clean on
both sockets.

## ROUND 2 — boundary refinement (added 2026-08-17 after first light)

Round 1 found: adapter clean ≤ 35.0 MHz, dead at 43.75 MHz; Edge clean at every
cell (boundary censored by the hp ≥ 4 driver clamp). The 35 → 43.75 gap is one hp
step at 350 MHz sysclk — the ladder below rebuilds the same tool at other sysclk
values so hp=4 lands *inside* that gap. Cards stay where run 1 had them (GREEN in
adapter); no swap needed — the card term is already proven zero.

Run all five, same session:

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300                 # hp4 = 43.75 MHz
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300 -D SYSCLK_336   # hp4 = 42.0 MHz
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300 -D SYSCLK_320   # hp4 = 40.0 MHz
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300 -D SYSCLK_300   # hp4 = 37.5 MHz
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300 -D SYSCLK_290   # hp4 = 36.25 MHz
```

Each transcript's banner prints its SYSCLK — self-labeling as usual. The adapter
boundary falls out as the highest hp=4 frequency that runs clean.

The tool also now prints a status line for every failing cmd read:

- `status=-1` (E_TIMEOUT) — the card **never answered**: it likely never decoded
  the command → outbound SCK/MOSI integrity through the adapter is the suspect.
- `status=-3` (E_BAD_RESPONSE) — an answer arrived **garbled** → return-path
  (MISO) suspect.

Round 1's failures were mode-invariant (ON = PRE), which already leans away from
MISO sampling margin; the status codes are the next discriminator. Report which
one appears.

## ROUND 2b — the asdfg pair (the cards that motivated this study)

The catalog's two **Edge-FAIL / External-PASS** cards — the inversion this whole
study exists to explain (approved by Stephen, 2026-08-17):

- **Lerdisk asdfg 1GB** (PSN `$0000_01F4`) and **Cloudisk asdfg 2GB**
  (PSN `$0000_1680`) — counterfeit SDSC silicon twins, MID `$05`, PNM `"asdfg"`,
  `CW_NO_DATA_CRC`. Records: `DOCs/cards/lerdisk-asdfg-1gb.md`,
  `DOCs/cards/cloudisk-asdfg-2gb.md`,
  `DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md`.

**Pair in hand (Stephen, 2026-08-17): one Lerdisk 1GB + one Cloudisk 2GB.**
Different labels and sizes is fine here — they are recorded silicon twins (same
MID/PNM/rev/controller behavior), so the card timing term is near-matched at the
level that matters, and the 2×2 swap separates card from socket algebraically
either way. The PSN tells them apart in the transcripts (Lerdisk `$0000_01F4`,
Cloudisk `$0000_1680`); size in the banner is a second check.

Run the standard shmoo (default 350 MHz build is enough to start), one asdfg card
per socket, then swap — same 2×2 protocol as round 1:

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300
```

**What discriminates what** (the reconciliation question this run answers):

- **Edge phase fails mode-DEPENDENTLY** (ON and PRE columns differ, possibly
  frequency-banded, crc/data-class errors) → cyclic sampling-alignment
  mechanism: the adapter's extra delay was *rescuing* these cards by shifting
  their long-t_ODLY transitions past the sample point.
- **Edge phase fails everywhere incl. 12.5 MHz, mode-invariant** → edge-rate /
  ringing mechanism: sharp Edge-socket edges glitching the counterfeit
  controller; adapter capacitance damps them.
- **Reads clean on BOTH sockets at every cell** → their documented Edge failure
  is confined to the write/commit path (wedge #3240 is write-triggered and this
  tool is read-only) — a third mechanism, needing a separate write-capable probe.

**Expected and not a fault:** the `CRC scoring appears INACTIVE` warning WILL
fire on these cards (dummy-CRC quirk) — crc columns read 0 by construction; the
cmd and data columns carry the scoring.

**Wedge protocol:** the shmoo never writes, so wedge #3240 should not fire. But
these cards have wedged on Edge after operation-pattern surprises before — if a
socket phase starts timing out wholesale after a clean start (`status=-1` on
every read regardless of frequency), assume the card is wedged: **power-cycle
the rig**, note it in the hand-back, and re-run. A wedge fired by a read-only
workload would itself be a finding — say so loudly.

**SDSC note:** these are byte-addressed 1–2 GB cards; sector 1000 is in range
and the driver's `hcs` shift handles addressing — no tool change needed.

## ROUND 3 — Lerdisk streamer-alignment hunt + fixed scoring (added after rounds 1–2b)

Container-side changes since round 2b, all compile-verified:

- **Shmoo scoring fixed** per the hand-back: dummy-CRC cards now have crc
  *excluded* from scoring (columns read 0 by construction, warning text says so),
  and the grid stores **bad reads** (a read with any error counts once) so the
  header is truthful and a dummy-CRC card can report a clean boundary. The
  Lerdisk's `none clean` artifact is gone.
- **Full-sector dual dump**: the first data-mismatching read of each socket phase
  now dumps all 512 bytes, exp/got interleaved 16 per row — the one-bit-shift
  question settles from the whole stream, not one byte pair.
- **`SD_phase_sweep_test.spin2` gained speed arms**: `-D SYSCLK_350` and
  `-D SPI_35M` / `-D SPI_29M` / `-D SPI_25M` (default keeps historical
  init-settled behavior). It sweeps 2 sample modes × align-delay offsets −3..+8 —
  the knob the Lerdisk finding points at.

**R3a — align-delay sweep on the Lerdisk** (the mechanism test for the
card-property streamer corruption; prediction: some positive offsets rescue
Path B, and the passing-band shift between sockets measures the socket delay in
sysclk ticks):

```bash
cd tools
# Lerdisk in EDGE socket (Path B onset was 35.0 MHz there):
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_35M
# Lerdisk in ADAPTER (onset 29.17 MHz there):
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 --external -D SYSCLK_350 -D SPI_29M
```

(Phase-sweep reads sector 0, not 1000 — fine, it self-references a slow read.)

**R3b — one shmoo re-run with the fixed tool**, Lerdisk in Edge, default build:
gives the Lerdisk's *true* per-cell boundaries (previous run's totals were
crc-poisoned) and captures the full dump at the first Path-B corruption.

## ROUND 4 — find the band's TOP (added 2026-08-17, after the clamp widening)

The driver's `debugSetAlignDelayOffset` clamp is widened to `[-8, +16]` and
`SD_phase_sweep_test` now sweeps offsets −3..+16 (both compile-verified). This is
step 2 of the approved mitigation path: **close the passing band's upper edge on
healthy cards** so a production default can be chosen against a measured band,
not a censored one.

⚠️ The clamp change is a `src/` driver edit — **the full regression suite must be
run and green on hardware** before this driver state is treated as certified.
Suggest running regression first, then the sweeps.

Sweeps (Gigastone pair, both sockets — same arms as R3a but the band top is the
target; every arm should now show FAILs at high offsets, and where they start is
the measurement):

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_25M              # Edge, production speed
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 --external -D SYSCLK_350 -D SPI_25M   # adapter, production speed
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_35M              # Edge, high
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 --external -D SYSCLK_350 -D SPI_29M   # adapter, high (its 35 MHz cmd margin is too thin)
```

Optionally repeat one arm with the Lerdisk to see whether slow silicon narrows
the band from the top as well as the bottom. Bring back the per-arm bands; the
candidate default (`hp + 2`) is judged against the *narrowest* measured band.

## ROUND 5 — the write path, wedge-aware (added 2026-08-17; the last uncharted IO surface)

New instrument: `diagnostic-tests/SD_write_probe.spin2` (compile-verified, all
variants; **DESTRUCTIVE** — writes scratch sectors at LBA 200,100+; run only on
cards whose contents are expendable). It maps frequency (12.5 / 25 / 35 MHz) ×
tx_align_delay pad (full SCK period, 2..2+2·hp) × command (CMD25 vs CMD24) ×
socket, writing a **period-256 non-uniform pattern** (absolute shift counts are
recoverable from its dumps) and reading back at a known-safe slow configuration
so failures attribute to the write path.

**Structure is safest-first; the wedge zone is quarantined:**

The same binary serves 5a and 5b — **the difference is which cards sit in the
sockets** (see the sequencing table at the top; PSN in the transcript is the
proof):

```bash
cd tools
# 5a — HEALTHY CARDS: Gigastone unmarked in Edge, GREEN in adapter.
#      Full phases 1+2 (adapter CMD25+CMD24 grids, Edge CMD25 grid) in one run:
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 600

# 5b — ASDFG CLASS: Lerdisk $0000_01F4 in Edge, Cloudisk #2 $0001_9B39 in adapter.
#      Same phases 1+2 (the wedge has never fired in these regions; wedge
#      detection + autopsy run automatically if that belief is wrong):
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 600

# 5c — THE WEDGE ZONE: Lerdisk $0000_01F4 in Edge (the documented #3240 wedger).
#      Edge + CMD24, ONE cell per run, ONE power cycle budgeted per run,
#      slowest frequency first:
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 300 -D P3_SLOW    # 12.5 MHz
# power-cycle if wedged, then:
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 300 -D P3_PROD    # 25 MHz
# power-cycle if wedged, then:
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 300 -D P3_HIGH    # 35 MHz
```

**What 5c decides:** a wedge at 12.5 MHz is frequency-INDEPENDENT → edge-rate /
signal-quality at the card's inputs. A wedge only at higher frequency →
timing-domain. Either way, on any wedge the tool runs an **autopsy** (what the
stuck controller still answers: re-init ×2, read attempts, every status printed)
before asking for the power cycle — each cycle buys maximum information. A
completed 5c cell with NO wedge is equally a finding (the raw-init path may not
reproduce what the filesystem-mount path triggered — say so loudly if seen).

Ordering note: run ROUND 4's regression + band-top sweeps first — the clamp
driver-edit must be re-certified before more instruments stack on it.

## ROUND 6 — reconciliation: prove the instruments, then re-verdict (added 2026-08-18)

Container-side analysis resolved both round-4/5 blockers; this round confirms the
resolutions on hardware. Both resolutions, briefly:

- **The shmoo/phase-sweep conflict is reference-content aliasing.** A one-bit
  shift of a *uniform* sector (fresh-card LBA 1000 = one repeated byte)
  reproduces itself byte-for-byte *including its CRC*, so the shmoo's Path B was
  blind exactly where the phase sweep (whose sector-0 MBR reference has
  structure) saw the true shift. The shmoo now scans for a shift-distinguishable
  reference (falls back to sector 0) and prints which sector it chose.
  **Retroactive consequence: all prior Gigastone shmoo Path-B "clean" columns
  are unreliable; Path A and cmd-cliff results stand.**
- **The write probe's 336 green cells never included the one condition known to
  fail** — v1.7.0 measured failing pads (≡ 1 mod 7) on **Edge + CMD24**, and the
  probe's phase structure ran CMD24 pad sweeps only on the *adapter* and Edge
  only with CMD25. New `-D EDGE_CMD24_SWEEP` arm runs exactly the v1.7.0
  condition; new `-D DETECT_SELFTEST` arm proves the failure reporting fires.

Run with the **unmarked Gigastone `$0000_01C7` in Edge** (adapter may stay
populated; only 6c uses it):

```bash
cd tools
# 6a — instrument proof: both verdict lines must print INSTRUMENT PASS
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 300 -D DETECT_SELFTEST
# 6b — the v1.7.0 condition: EXPECT FAILs at pads 8 and 15 in the hp=7 group.
#      Failing there = detection proven + v1.7.0 reproduced (green grids become
#      evidence). All-PASS there = real conflict with the v1.7.0 record — report
#      loudly, do not proceed to conclusions.
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 600 -D EDGE_CMD24_SWEEP
# 6c — fixed shmoo (alias guard live), Gigastone pair both sockets: re-verdicts
#      every Path-B column. Expect Edge hp=5 Path B to now show errors (matching
#      the phase sweep's offset-0 FAIL at 35 MHz).
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300
# 6d — optional cross-check with the original v1.7.0 instrument, same card:
./run_test.sh ../diagnostic-tests/SD_tx_phase_shmoo.spin2 -t 600
```

The production align-delay default discussion resumes only after 6a/6b prove the
instruments; then round 4's phase-sweep bands (which the aliasing resolution
leaves as the trustworthy record) carry the decision.

## ROUND 7 — tx-tooth population survey (added 2026-08-18, after round 6)

Round 6 established: the v1.7.0 losing-phase cliff (pads ≡ 1 mod 7 at hp=7) was
characterized on **Card 2b `$0000_0F14` only** (the driver comment is explicitly
card-scoped), and on `$0000_01C7` **two proven instruments independently find no
tooth at all**. So the tooth is card-specific, and `tx_align_delay = 4`'s
"maximal distance from the cliff" justification has a sample size of one. This
round establishes the tooth's existence, position, and movement across the
population — the write-side prerequisite for any default decision.

Container-side changes: `SD_tx_phase_shmoo` now prints the card PSN (the round-6
identity caveat is closed); the socket shmoo's per-cell column is relabeled
`err` (a negative read status covers cmd/token failures AND in-driver CRC-retry
exhaustion — the per-failure status line under the row disambiguates).

⚠️ **Serial near-collision:** Card 2b `$0000_0F14` (Gigastone ASTC 64GB, 2023/06)
and the Lerdisk `$0000_01F4` (asdfg 1GB, 2025/12) have **anagram serials** —
same four hex digits, two transposed. They are different cards. Check the
transcript's PNM as well as the PSN: Card 2b prints `PNM='ASTC '`-class content
and 64GB capacity; the Lerdisk prints `PNM='asdfg'` and ~1GB. A 7a run showing
`asdfg` is on the wrong card — stop and swap.

```bash
cd tools
# 7a — THE DECISIVE PAIR, on Card 2b $0000_0F14 in Edge (characterization-only
#      card; label the runs as such in the hand-back):
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 600 -D EDGE_CMD24_SWEEP
./run_test.sh ../diagnostic-tests/SD_tx_phase_shmoo.spin2 -t 600
#      Cliff reproduces -> tooth is real + card-specific: proceed to 7b to map it.
#      Cliff GONE on its own card -> the phenomenon changed underneath the record
#      (driver write path is unchanged since certification) -> report loudly, stop.
# 7b — population: repeat the same pair on 2-3 more library cards, one at a
#      time, Edge socket. Vary controller vendor (e.g. a SanDisk, a Samsung, a
#      Phison). The question per card: tooth present? at which pads?
# 7c — asdfg read-band top (their earlier bands were censored at the old +8
#      sweep limit), Lerdisk in Edge:
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_29M
```

Bring back per card: PSN, tooth present/absent, failing pads if present, and the
passing band. The write-default decision (keep 4, move, or per-card calibrate)
is judged against the union of these.

### 7d — the Edge cmd ceiling at 360 MHz (approved overclock, one run)

Stephen approved a **bounded overclock to 360 MHz sysclk — and no higher**
(2026-08-18) to chase the one censored number left: the Edge socket's cmd
ceiling (clean at 43.75 MHz, the 350 MHz instrument limit). At 360, hp=4 lands
at **45.0 MHz**. Gigastone pair, standard placement:

```bash
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300 -D SYSCLK_360
```

**Read it with the overclock control in mind:** the sweep's slower cells
(12.5–36 MHz) re-run at 360 MHz sysclk and must stay clean — if THEY fail, the
P2 itself is unhappy at 360 and the run is **discarded, not interpreted**. If
slow cells are clean: Edge hp=4 failing = the ceiling is finally **measured**
(bracketed 43.75–45.0 MHz); Edge hp=4 passing = the map closes at "Edge ≥ 45.0,
socket delta ≥ 7.75 MHz" and we stop there by decision. The adapter phase will
fail its usual high cells (~37+ MHz equivalents) — expected, and itself a
same-session sanity check that the instrument still sees the known cliff.

## ROUND 8 — certify the mitigation bundle (added 2026-08-18; Stephen-approved driver changes)

The driver carries the campaign's mitigation bundle, compile-verified (34 of 34
consumers — 27 suites plus examples and DEMO, both build shapes) and style-clean
in `src/`. **The bundle grew between your 8a attempts**; this is the current
contents, in the order they were added:

1. **`align_delay_offset` default 0 → 5** — the read-streamer alignment moves to
   the measured center of every band.
2. **hp=4 floor-cell rule** (`effectiveAlignDelay()`) — positive offsets are
   withheld at `spi_period = 4`, which keeps the historical `align = hp` there.
   *Added after 8a run 1*: the bands were measured at hp 5–7 only, and +5 at
   hp=4 exceeds the bit period, which is what broke the CMD6 verify read.
3. **Production speed bound** — `setSPISpeed()` clamps at the card's declared
   ceiling (TRAN_SPEED capped at the SPI-mode 25 MHz; 50 MHz during verified
   CMD6 high-speed). New `debugSetOverspeedAllowed()` lifts it for diagnostics;
   the shmoo, write probe and phase sweep already call it.
4. **`applyDefaultSpeedMode()`** — CMD6 switch-back on the three high-speed
   *fallback* paths. *Added after 8a run 1.*
5. **Explicit high-speed mode state (`hs_mode_active`)** — *added after 8a run 2,
   and the reason a third attempt is needed.* See below.

### What changed since your 8a run 2, and why

Run 2's surviving reds (`SD_RT_speed_tests` #9 and #12) were **not** marginal
operation at 43.75 MHz, and **not** the new switch-back misbehaving. The high-speed
verify *succeeded*; the test then hand-set the clock back to 25 MHz, and the card
stayed in CMD6 high-speed mode — because item 4 above covered only the three
fallback exits, and a verified success followed by any later `setSPISpeed()` is a
**fourth exit** that nothing hooked. Card on high-speed output timing, host on
default timing, `-7` on everything after.

Hooking that exit needed state the driver did not have: high-speed mode was being
*inferred* from `spi_freq >= 50_000_000`, which is false at 350 MHz sysclk where
high speed resolves to hp=4 / **43_750_000 Hz**. So the driver now carries an
explicit `hs_mode_active` flag, set at the verified switch and cleared only by the
switch-back, and:

- `isHighSpeedActive()` reports the **card's mode**, not a clock threshold.
  **This is a public API contract change** — it previously answered FALSE at this
  project's own sysclk while high-speed mode was genuinely active.
- Every exit routes through the switch-back: the three fallbacks, a user
  `setSPISpeed()`, and `unmount()`. `initCard()` clears the flag so a card swap
  cannot inherit a stale TRUE.

### `SD_RT_speed_tests` — read this suite closely

Its scoring changed, so a comparison against your run-2 transcript needs care:

- **Test #8** now makes **two** sub-checks instead of one. Expect
  `attemptHighSpeed: -1  isHSActive: -1` — *both* true, at
  `43_750_000 Hz`. Run 2 printed `isHSActive: 0` here alongside a successful
  attempt; that contradiction was the tell, and it should be gone.
- **Test #9** previously printed `createFileNew failed after HS: -7` and then
  **scored itself a pass** ("Skip — card-specific"). That absolution is removed.
  It must now genuinely create, write, read back and match. A `-7` here is a
  **FAIL**, and it prints survey coordinates when it fails.
- **Test #12** unchanged, and should now pass — it was collateral damage from the
  same stranded card.
- Expect **530/530**. Note that 529/530 in run 2 understated the problem: the
  same root cause was inside #9 too, wearing a green mark.

```bash
cd tools
# 8a — FULL REGRESSION certifies the whole bundle (Gigastone regression card, Edge):
./run_regression.sh
# 8b — one shmoo run, Gigastone pair, standard placement — the hp+5 default
#      made VISIBLE: Path B columns should now stay clean far beyond the old
#      29.17 MHz boundary (at default offset the band's lower edge no longer
#      bites). Also proves the overspeed knob works (cells >25 MHz still sweep):
./run_test.sh ../diagnostic-tests/SD_socket_shmoo.spin2 -t 300
```

Expected changes vs. earlier rounds, so nothing reads as a fault: 8b's Path B
boundaries should IMPROVE markedly (that is the fix working); every ≤25 MHz cell
behaves as before; tools still reach 43.75 MHz (knob working). A regression
failure in 8a or a Path B boundary that did NOT move in 8b is a stop-and-report.

### RESULT — certified 2026-08-18

**8a run 3: 530/530, all 27 suites, closing audit clean (23/23)**
(`regression_260818_round8a_run3.log`). The predicted signatures are present in
`SD_RT_speed_tests_260818-125535.log`: #8 prints `attemptHighSpeed: -1
isHSActive: -1` at `43_750_000 Hz`, and #9 passes on the real
create/write/read/compare path rather than through the removed absolution.

**8b clean** (`SD_socket_shmoo_260818-130306.log`, Gigastone pair — Edge
`$0000_01C7`, adapter `$0000_01C9`). Path B is now clean through **35 MHz on both
sockets**; the adapter's Path B boundary was ~29.17 MHz before the align default
moved to +5. That is the fix working, and it is the "equal socket support" claim
the changelog makes, measured.

**One cell is worth recording, and it is not a defect.** At hp=4 / 43.75 MHz the
Edge grid reads `ON-A 0, ON-B 254` — the byte-by-byte path is clean and the
production streamer path aborts. This is the uncharacterized floor cell (item 2
withholds the align offset there, and tx pad 4 at hp=4 was never measured — the
tooth was mapped at hp 5, 7 and 14). Note what it does **not** contradict: the
shmoo drives 43.75 MHz with the card in **default** speed mode, which is above
spec, while the driver reaches 43.75 MHz only **inside verified CMD6 high-speed
mode**, where the card is entitled to run that fast — and that path read cleanly
in both green speed-test runs. Read together, the two results are the production
speed clamp's justification: above-spec-in-default-mode fails, in-high-speed-mode
works. Characterizing the hp=4 band is a future measurement, not a v1.7.1 item.

## Bring back

- The full log path(s) under `tools/logs/` (transcripts are the record).
- Which physical card (brand + label size) was in which socket per run, even though
  CID confirms it.
- Any deviation from expectations above, verbatim lines preferred.

## ROUND 9 — hardware-understanding studies (added 2026-08-18, post-certification)

Six cards, in hand. Named by label so they can be found physically; the PSN in
each transcript is the proof of which one actually ran.

| # | Card (physical label) | Controller | Socket |
|---|---|---|---|
| 1 | **SanDisk MAX Endurance 32GB** microSD HC I U3 V30 | SanDisk `$03` | Edge |
| 2 | **Samsung EVO Select 128GB** microSD XC I U3 | Samsung `$1B` | Edge |
| 3 | **Lexar 64GB** microSD XC, red card, A1 V30 U3 | Longsys `$AD` | Edge |
| 4 | **PNY 16GB** microSD HC I | Phison `$27` | Edge |
| 5 | **Cloudisk 2GB** Class 4 (counterfeit `asdfg`) | unknown `$05` | see 9a |
| 6 | **Lerdisk 1GB** (counterfeit `asdfg`, label reads only "microSD 1GB") | unknown `$05` | see 9a |

### What changed in the shared tree since your last run

We share this tree and there is no git handoff, so read this before comparing
anything against your round-8 transcripts. All of it is compile-verified across
34 consumers in both build shapes, and `check_style.sh` reports `src/` conformant.

| Change | Why it matters to you |
|---|---|
| `SD_RT_speed_tests`: new **High-Speed Mode Exits** group, **15 tests → 17** | **Regression totals move 530 → 532.** A 530 means a stale binary |
| Driver: new **`debugSetAlignFloorRuleEnabled()`** [SD_INCLUDE_DEBUG] | Makes 9c possible at all; production behavior unchanged |
| `SD_phase_sweep_test`: new **`-D SPI_43M`** arm | 9c's instrument. Lifts two production guards on purpose |

Nothing else in the driver moved. The v1.7.1 bundle is exactly as certified in
round 8a run 3 — these are additive diagnostics and test coverage, not changes to
shipped behavior.

The two new tests cover paths that had **no coverage at all**: `setSPISpeed()`
and `unmount()` both exit high-speed mode, and until now only the three *failure*
exits were exercised by anything. The unmount test is deliberately end-to-end
(unmount while high-speed → remount → file operation) because the card cannot be
asked what mode it is in; the only honest proof is that the next mount works.

### 9a — Does the bundle change the asdfg Edge wedge? (cheapest run, do first)

**The belief under test:** the catalog says these two cards are External-only
because of the #3240 Edge wedge. That guidance predates the mitigation bundle,
and the bundle changed read alignment for every card. Nobody has run an asdfg
card through the mount path on Edge since. So the honest status is *untested*,
not *fixed*.

Round 5 could never trigger the wedge with raw writes (~336 cells, zero wedges);
Finding 1 relocated the trigger to the **filesystem/mount path**. The minimal
reproducer on record is `mount_tests` then `raw_sector_tests` **with no power
cycle between them**, on the Edge socket. Baseline to beat: raw_sector_tests 1/14.

```bash
cd tools
# Lerdisk 1GB in EDGE, then repeat the identical pair with Cloudisk 2GB in EDGE:
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
./run_test.sh ../src/regression-tests/SD_RT_raw_sector_tests.spin2 -t 120
```

All three outcomes are worth having: **still wedges** confirms the reproducer
still works and the catalog stands; **no longer wedges** means read alignment was
implicated in something we had filed as a write-path defect, and the card records
need rewriting; **wedges differently** is the most informative of all, since the
campaign has never been able to trigger it on demand.

If a card wedges: power-cycle, note it, move on. Do not spend more than one power
cycle per card here.

### 9b — Is the +5 align default universal, or vendor-dependent?

**The belief under test:** the shipped default came from five sweeps across
**two** card families. If different controllers center their read band at
different offsets, one global default is the wrong architecture, and we would
want that finding now rather than after release.

Cards 1-4, one at a time, Edge socket, production speed:

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_25M
```

Bring back per card: the passing band (first and last passing offset) per sample
mode, and where it centers. **The number that matters is whether every controller
centers near +5.** A card centering at, say, +2 or +9 is the headline result of
this whole round.

### 9c — What is actually in the hp=4 floor cell?

**The belief under test:** none — this is the cell we have never measured, and we
carry a production exemption purely because of that ignorance. The driver's own
verified high-speed path runs here. Measuring it may let the exemption be deleted.

Cards 1-4, Edge socket. Note this arm lifts two production guards on purpose:

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_43M
```

The banner prints `FLOOR-CELL ARM: hp=4 rule LIFTED for measurement`. If that line
is missing, the wrong binary is running — stop. Expect failures at the extremes;
that is the measurement. A card that fails at **every** offset is itself the
answer for that card (no usable band at hp=4), and should be reported as such
rather than as a broken run.

### 9d — Which controllers actually negotiate CMD6 high speed?

**The belief under test:** `SD-CARD-PERFORMANCE.md` §7 says high speed "fails on
all tested cards." One counterexample already falsifies it, but the real question
is bigger: high speed is 43.75 MHz against 25 MHz, a ~75% clock increase we
currently tell users is unavailable. Which silicon takes it, and holds it?

All six cards, one at a time. Cards 1-4 in Edge; **cards 5 and 6 in the external
adapter** unless 9a shows the Edge wedge is gone, in which case run them on Edge
too and say which socket produced each transcript:

```bash
cd tools
./run_test.sh ../src/regression-tests/SD_RT_speed_tests.spin2 -t 120              # Edge
./run_test.sh ../src/regression-tests/SD_RT_speed_tests.spin2 -t 120 --external   # adapter
```

Read from each transcript: test #8's `attemptHighSpeed` / `isHSActive` pair and
the achieved frequency, plus whether #6/#7 report the card *declining* versus the
query *failing* — those are different answers and ERROR() separates them. The
counterfeit SD 1.x cards should decline cleanly; that is a real check of the
honest-boolean contract on a card that genuinely lacks the feature, which has
probably never been exercised.

This suite creates and deletes a scratch file. It does not format. It reports
**17 tests** this round (was 15).

**Expected on the two counterfeit cards, and not a driver defect:** the new
High-Speed Mode Exits group unmounts and remounts. On marginal counterfeit
silicon a remount can fail for reasons that have nothing to do with high-speed
mode — these cards have a documented Edge wedge and a probe-found SCK ceiling.
If those two tests are the only reds on cards 5-6, record it as card-specific and
move on. Reds there on cards 1-4 are a different matter: report those loudly.

### 9e — Second full regression: Samsung EVO Select 128GB

**Why this card:** the regression card is 32GB at 32 sectors/cluster; this one
formats to 119GB FAT32 at **64 sectors/cluster** — double the cluster size, ~4x
the capacity, a much larger FAT — and it is a completely different controller.
Full regression is the only thing that exercises FAT32 layout math, so the second
card should maximize geometry, not vendor (9b/9d already cover vendor). Its card
record shows it has been reformatted to FAT32 with P2FMTER before, so our
formatter is known to handle it.

**This run formats the card.** Do it last.

```bash
cd tools
./run_regression.sh
```

**Expect 532/532, not 530/530.** `SD_RT_speed_tests` grew from 15 tests to 17
this round (the High-Speed Mode Exits group), so the suite total moved with it.
A run reporting 530 means the binary predates this round's tree — stop and say
so rather than reading it as a pass.

Any red here is a genuine finding about a geometry we have never certified. If
the **format step** fails on a 128GB card, that is itself the finding: report it
and stop rather than working around it — our formatter is documented as having
handled this card before, so a failure means something changed.

### Bring back for round 9

Per study, per card: the log path, the physical card by label, which socket, and
the specific number that study asked for (band edges for 9b/9c, the HS pair and
frequency for 9d, pass/fail for 9a/9e). Deviations verbatim.

**Two standing rules for this round, because these are studies and not pass/fail
gates.** First, a study that returns "nothing works here" or "no band exists" is
a **result**, not a failed run — report it as the answer rather than retrying
until it looks better. Second, do not diagnose from hypotheses: if something
surprises you, send the transcript and say what surprised you. Round 8 cost two
bench runs to a hypothesis list standing in for a discriminating read of a log we
already had.

**Suggested order:** 9a (cheapest, gates 9d's socket choice) → 9b → 9c on the same
card while it is seated → 9d → 9e last, since it formats. 9b and 9c are read-only;
9d writes a scratch file; only 9e formats.

## ROUND 10 — performance payoff and the first Edge-wedge answers (added 2026-08-18)

### New and changed instruments (all compile-verified, `src/` style-clean)

| Instrument | Change |
|---|---|
| `src/UTILS/SD_performance_benchmark.spin2` | New **`-D HIGH_SPEED`** arm negotiates CMD6 high speed before measuring. Every rate line now also reports **`[N% of bus, LIMITER]`** |
| `diagnostic-tests/SD_edge_wedge_probe.spin2` | **NEW.** Five arms for blind differential diagnosis of the Edge wedge |

**About the new benchmark annotation.** A 512-byte sector is 4096 bits on one SPI
data line, so the bus ceiling is `spi_freq / 8` bytes per second and nothing —
card or driver — can beat it. Each rate is printed as a percentage of that
ceiling with a verdict: `BUS-bound` at or above 70%, `CARD-bound` below 30%,
`mixed` between. Those two thresholds are reporting boundaries for legibility,
not physics. This is what lets the catalog say *which* thing is the limit for
each traffic type, and it is the baseline 4-bit support will be measured against.

### 10a — deep-catalog the Kingston-labelled 2GB

Stephen's suspicion is that we have seen this card already and do not know it.
That is plausible: the catalog names cards by **silicon identity**, not by the
label printed on them, and our only Kingston entry is an **8GB SDHC**
(`Kingston_SD8GB`, CSD v2.0). A 2GB card is SDSC (CSD v1.0), so it cannot be that
entry. Either it matches some other existing row under a different label, or it
is genuinely new.

Follow `DOCs/cards/CATALOG-PROCEDURE.md` as written — identify, characterize,
benchmark at both sysclks, annotate:

```bash
cd tools
./run_test.sh ../src/UTILS/SD_card_identify.spin2
./run_test.sh ../src/UTILS/SD_card_characterize.spin2 -t 90
```

Bring back the PSN, MID, PNM and CSD version before going further — if the
fingerprint matches an existing row, the rest of the procedure is an *update*,
not a new entry, and which one it is changes what gets written.

**This card also matters to 10c.** It is SDSC-class like both failing cards but
is not an `asdfg` twin. If it wedges on Edge too, the problem is not about two
counterfeit cards, it is about SDSC or low-power silicon generally — and the
scope of what we are chasing changes completely. Worth knowing early.

### 10b — does the 75% clock increase become 75% throughput?

Three cards, each run **twice** — once standard, once with `-D HIGH_SPEED` — so
each card is its own control and the delta is unambiguous:

```bash
cd tools
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180 -D HIGH_SPEED
```

| Card | Catalog baseline | Why this card |
|---|---|---|
| **Samsung EVO Select 128GB** | 783 KB/s | Mid-range, high-speed capable, freshly certified and already formatted |
| **Lexar 64GB** (red) | 1059 KB/s | Our fastest card — closest to the bus ceiling, so most likely to show the gain |
| **PNY 16GB** | 31.3 KB/s | The extreme opposite: high-speed capable but a controller that delivers 31 KB/s. If a 75% clock increase does nothing here, that is the clearest possible illustration of what the catalog's limiter column is for |

**What to expect, so a real result is not mistaken for a broken run.** The gain
should be strongly workload-dependent. Random single-sector access is dominated
by card-internal latency (0.5 ms and up), so it may gain little or nothing even
on a fast card — that is the expected answer, not a failure. Sequential
multi-block through the streamer is where the bus is plausibly the limit and
where the gain should appear. **A card that gains on multi-block and not on
single-sector is the headline result of 10b**, not an inconsistency.

Bring back per card and per traffic type: the rate, the `% of bus`, and the
limiter verdict, for both arms.

### 10c — the Edge-wedge probe ladder

**The constraint that shapes this whole track:** the Edge module socket cannot be
probed. We cannot see anything, so every step is *change one thing and re-test*.
That also means the reproducer itself is the instrument, and its reliability has
to be established before any intervention result can be believed.

**A wedge ends the session.** One arm per run, power-cycle after any wedge.

Run in this order — each step is chosen to split what remains, not to confirm a
hunch:

```bash
cd tools
# 1. CONTROL -- Lerdisk 1GB in the EXTERNAL adapter. Must come back CLEAN.
#    If this wedges, the fault is not socket-specific and the whole frame is wrong.
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D SD_PINS_EXTERNAL

# 2. RELIABILITY -- Lerdisk 1GB in EDGE, default arm. How many cycles until it wedges?
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300

# 3. THE DECISIVE RUN -- same card, EDGE, clamped to 400 kHz.
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D SPEED_400K

# 4. WRITE-BURST -- same card, EDGE, no writes and no FSInfo update at unmount.
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D READ_ONLY
```

**The decision tree.** Report the outcome of each step; the next step's meaning
depends on it.

- **Step 2 wedges on cycle 1 every time** → reproducer is deterministic, and
  interventions can be trusted. **If it takes several cycles, or does not wedge
  at all in eight, say so loudly** — an intermittent reproducer changes how every
  later result must be read, and we would need repeat runs before believing any
  intervention.
- **Step 3 still wedges at 400 kHz** → timing and signal integrity are BOTH
  eliminated. Nothing about edge rates, setup/hold or sampling margin survives at
  400 kHz. Only power delivery and command protocol remain, and step 4 splits
  those.
- **Step 3 is clean at 400 kHz** → the failure IS speed-dependent, which puts
  signal integrity back in play and makes a driver-side pin drive-strength knob
  the next thing to build (P2 `WRPIN` bits 20:8 carry drive strength).
- **Step 4 clean (read-only) while step 2 wedges** → the write burst is required,
  which points hard at write/erase current draw. **That is the trigger for the
  bench-supply intervention:** swap the USB 5 V feed for a robust bench supply and
  re-run step 2. If that fixes it, the answer is power delivery.
- **Step 4 also wedges (read-only)** → not the write burst; the fault is in the
  unmount/re-init command sequence itself, and the next work is driver-side
  protocol, not electrical.

If the ladder completes and the Lerdisk is behaving, repeating step 2 and step 3
on the **Cloudisk 2GB** confirms the twins behave identically, and on the
**Kingston 2GB** answers the much larger question in 10a.

### Bring back for round 10

10a: the fingerprint fields, before anything else. 10b: per card, per traffic
type, both arms — rate, `% of bus`, limiter. 10c: the outcome of each ladder step
in order, the cycle number of any wedge, the unmount `elapsed=` figures
(including near-misses that stalled but recovered), and the autopsy block from
any wedge.

**Standing rules from round 9 still apply:** a study returning "nothing here" is
a result, not a failed run; and do not diagnose from hypotheses — send the
transcript and say what surprised you.

## ROUND 11 — reproduce the wedge, and settle the write regression (added 2026-08-18)

### Instrument changes since round 10 (all compile-verified, `src/` style-clean)

| Instrument | Change |
|---|---|
| `SD_edge_wedge_probe` | **Cycle rebuilt.** Round 10c's version was too gentle — 8/8 clean while the known reproducer wedged the same card minutes later. Now does `freeSpace()` (full FAT scan), `volumeLabel()`, a raw sector read, a double-mount, and create/write/read/delete. Also **prints card identity** via `initCardOnly` + CID, so a null result no longer needs a separate identify run |
| `SD_performance_benchmark` | **Writes are now verified.** Read back and compared after the timed loop. The fill pattern was `bytefill($5A)` — uniform, and therefore blind to exactly the shift corruption we are hunting; it is now shift-detectable, varying within and between sectors |
| `SD_write_probe` | **New `-D HS_PAD_SWEEP` arm** — the hp=4 write pad, measured inside verified high-speed mode |

### 11a — does the rebuilt probe reproduce the wedge?

**This is a gate, not a result.** If the probe still comes back clean while the
suite pair still wedges, do NOT proceed to the ladder — report it and stop. An
intervention tested against a reproducer that is not reproducing produces clean
arms that mean nothing.

```bash
cd tools
# Lerdisk 1GB in EDGE, default (heavy) arm:
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300
```

- **Wedges** → the gate is passed. Record the cycle number, then run the ladder:
  `-D SPEED_400K` (decisive — nothing about edge rates or setup/hold survives at
  400 kHz), then `-D READ_ONLY`. Power-cycle after each wedge, one arm per run.
- **Still clean** → stop and report. The next move is container-side, not another
  intervention.

Confirm the reproducer is still live either way with the known pair
(`SD_RT_mount_tests` then `SD_RT_raw_sector_tests`, no power cycle) — round 10c
showed that check is what made a null result interpretable.

### 11b — is the high-speed write regression slow, or corrupt?

Round 10b measured writes getting much slower at 43.75 MHz with **zero reported
errors** — but the benchmark had never checked that the bytes on the card matched
the bytes sent. "No errors" meant no card *rejections*, not no corruption, and
round 7b documented a driver-side phase that corrupts whole sectors silently.

Three cards, both arms each, exactly as in 10b so the numbers stay comparable:

```bash
cd tools
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180
./run_test.sh ../src/UTILS/SD_performance_benchmark.spin2 -t 180 -D HIGH_SPEED
```

New lines to watch for. A clean run prints `verify: N bytes match` after each
write result. A mismatch prints the offset and then **re-reads at a trusted
speed** to attribute it:

- `CONFIRMED WRITE CORRUPTION` — the bytes on the card are wrong. The regression
  is a correctness bug, not a performance one, and high speed must not be used
  for writes on that card until the pad question is settled
- `Write was CLEAN; the fast READ-BACK was at fault` — the write is fine and the
  hp=4 *read* path is the problem instead

Either mismatch message drops the clock to attribute it, which exits high-speed
mode — so **timings after a mismatch in the same run are not comparable**. The
transcript says so at the point it happens.

### 11c — the hp=4 write pad, inside high-speed mode

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 300 -D HS_PAD_SWEEP
```

**DESTRUCTIVE** (scratch sectors at LBA 200,100+) and **high-speed capable cards
only** — the arm refuses and explains itself on a card that declines, which is
not a failure.

The arm negotiates high speed once, writes every pad in `[2..10]` to its own
sector while still at hp=4, exits once, then reads them all back at 12.5 MHz and
scores. That shape is forced: `setSPISpeed()` exits high-speed mode, and a card
in high-speed mode cannot be read slowly — so per-cell write-then-readback is
impossible here, and writing everything in one verified card state is also the
cleaner experiment.

Bring back the **passing band and its centre**. The shipped default is pad 4.

- Default **outside** the band → this explains 10b's write regression, and the
  fix is an hp-aware tx pad
- Every pad passing → the pad is **not** the cause; the regression is card-side
  behaviour in high-speed mode, and 11b's verification should agree by showing
  the bytes were correct all along

### Bring back for round 11

11a: wedged or not, and on which cycle; the unmount `elapsed=` figures including
near-misses; the identity line proving card and socket. 11b: per card, per
traffic type, both arms — rate, `% of bus`, limiter, and every verify line.
11c: the per-pad table and the band.

**Standing rules:** a study returning "nothing here" is a result, not a failed
run; and do not diagnose from hypotheses — send the transcript and say what
surprised you.

## ROUND 12 — close the sample-size gaps, and split the wedge hypothesis (added 2026-08-19)

### 12a — does `mount_tests` wedge from a cold power-on? (do this first, it is free)

**The gap.** In round 11a the probe ran first and `mount_tests` wedged 40 seconds
later. In round 9a it also followed other work. **Nobody has run `mount_tests`
alone, immediately after a power cycle.** So we do not know whether the wedge
needs a preceding binary at all.

That matters because round 11's hand-back proposes the cross-binary boundary as
the leading candidate — but the wedge fires at **test #13 inside `mount_tests`**
(`unmount()` returns `-7`, then `mount()` #2 returns `-8` at #15), which is before
any boundary is crossed. The two readings make opposite predictions, and one run
separates them.

```bash
# POWER-CYCLE THE RIG FIRST. Lerdisk 1GB in EDGE. Nothing else in between.
cd tools
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
```

- **Wedges cold** → the trigger is inside `mount_tests`. Proceed to 12b
- **Clean cold** → a preceding binary is required, the cross-binary hypothesis is
  right, and 12b is not the next move. Report and stop

Because the `-7` is intermittent (tally so far `-7`, `-7`, `0`, `-7`), **run this
three times, power-cycling between each**. A single clean run is not evidence.

### 12b — the bad-pin prefix (only if 12a wedges cold)

**The one thing `mount_tests` does that the probe never has.** Before the mount
whose unmount then fails, it calls `mount()` twice on deliberately wrong pins —
`mount(60, 10, 58, 15)` and `mount(60, 59, 20, 16)`, its "Pin offset validation"
group. Both are rejected with `E_BAD_PIN_CONFIG`, but whether the driver touches
any pin before rejecting is exactly the question: smart pins configured on the
wrong pins, or the card partially clocked, is a card-visible event this probe has
never reproduced.

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D BAD_PIN_PREFIX
```

Wedges → the trigger is identified and the ladder finally becomes meaningful.
Clean → bad pins are eliminated, and the remaining prefix difference is the
pre-mount error-path group.

### 12c — the hp=4 write pad on two more cards

**Why this is not optional.** Round 11c mapped the hp=4 teeth to `≡ 2 (mod 4)` and
found the shipped pad 4 safe — **on one card**. The tooth is expressed by only
three of five cards surveyed, and the residue moves with hp. A single-card map is
exactly the evidence base that made the v1.7.0 characterization wrong, and this
one is currently carrying a safety conclusion.

```bash
cd tools
# Lexar Red 64GB, then PNY 16GB -- the other two cards that negotiate high speed:
./run_test.sh ../diagnostic-tests/SD_write_probe.spin2 -t 300 -D HS_PAD_SWEEP
```

**DESTRUCTIVE** (scratch sectors at LBA 200,100+). Bring back each card's failing
pads. Same residue on all three → the map is a driver property and pad 4 is
established safe. A different residue on any card, or pad 4 failing anywhere →
the single fixed pad is not sufficient at hp=4, and that lands directly on the
high-speed decision.

### 12d — the hp=4 read band inside high-speed mode

Round 9c measured the hp=4 read band by **setting** the clock to 43.75 MHz, which
leaves the card in default speed mode driven above spec. hp=4 occurs in production
only inside high-speed mode, where the card's own output timing differs. The band
that ships has therefore never been measured in the state it ships in.

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_phase_sweep_test.spin2 -t 300 -D SYSCLK_350 -D SPI_43M_HS
```

New arm: it negotiates high speed rather than setting a clock, and sweeps without
changing speed at all (Path B compares the streamer against the byte-by-byte path
at the same clock, and that path was measured clean at hp=4). The banner must read
`HS ARM: high speed ACTIVE` — if it does not, the wrong binary is running.

Run on all three high-speed-capable cards. The question: does the band centre at
+5 as it does everywhere else, and **is the exemption's `align = hp` inside it?**
The exemption is already known safe empirically — round 11b's high-speed reads
were clean and gained up to 47% — so this decides whether it is also *optimal*.

### Bring back for round 12

12a: wedged or clean, on each of three cold runs. 12b: same, plus the bad-pin
mount return codes. 12c: the failing pads per card. 12d: the band per card and
whether `align = hp` falls inside it.

**Standing rules:** a study returning "nothing here" is a result; and do not
diagnose from hypotheses — send the transcript and say what surprised you.

## ROUND 13 — what exactly does a "prior session" leave behind? (added 2026-08-19)

Round 12a turned #3240 from an intermittent mystery into a switch: **cold is
clean (4/4), warm wedges (2/2), power clears it.** That is a large step. This
round narrows *what* the warm condition actually consists of, because the current
description still contains at least two independent variables.

**The observation that constrains everything here:** the wedge probe runs eight
mount/operate/unmount cycles inside a single power-on and stays clean, every time.
Cycles 2 through 8 are all "after a prior driver session" — yet only a session
that follows **a P2 reset and re-download** wedges. So "prior driver session" is
not by itself the trigger. Something about the reset window is part of it.

During a P2 reset and download the pins go high-impedance for roughly a second:
the card sits with CS floating and unclocked, which is a condition no in-binary
cycle ever creates.

### 13a — is a *driver* session required at all? (the decisive one)

Run any binary that does **not** touch the SD pins as the predecessor, then
`mount_tests` warm.

`diagnostic-tests/SD_null_predecessor.spin2` is built for exactly this: it does
not include the driver object, touches no pin, and clocks nothing. It carries a
DAT pad that brings it to **49.7 KB against mount_tests' 47.3 KB**, so the two
predecessors differ in what they *do* and not in how long they take to download —
and download time IS the float window under test. A 5 KB predecessor coming back
clean would have been ambiguous.

```bash
cd tools
# 1. POWER-CYCLE. 2. The null predecessor. 3. WITHOUT power cycling, the reproducer:
./run_test.sh ../diagnostic-tests/SD_null_predecessor.spin2 -t 60
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
```

- **Wedges** → a driver session is NOT required. The trigger is the reset itself —
  the float window, or the download traffic — and the whole hypothesis moves off
  the card's filesystem state and onto the pins
- **Clean** → a driver session genuinely is required, and 13b/13c narrow which
  part of it

Run it twice to be sure, power-cycling before each.

### 13b — does time clear it, or only power?

```bash
cd tools
# POWER-CYCLE, run mount_tests (cold, expect clean), then hold 120 s with the P2
# idle and the card powered, then run the reproducer again -- no power cycle:
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
./run_test.sh ../diagnostic-tests/SD_null_predecessor.spin2 -t 200 -D HOLD_120S
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
```

The hold is done by the P2 rather than by an operator with a watch, so the
interval is exact and appears in the transcript. Note this run has **two**
predecessors (a driver session, then the null hold) — if 13a shows the null
binary alone wedges, re-read this result accordingly.

- **Wedges after the wait** → the state is latched, not a process finishing
- **Clean after the wait** → something in the card completes on its own, and
  internal housekeeping moves to the front. These cards are documented as
  re-busying themselves after CS deassert for garbage collection, and the driver's
  init busy-poll gives up after about two seconds and proceeds regardless

That second outcome would make this a driver-fixable defect rather than a card
limitation, so it is worth the two minutes.

### 13c — must the prior session have written?

```bash
# POWER-CYCLE, then a READ-ONLY prior session, then mount_tests warm:
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D READ_ONLY
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
```

- **Clean** → prior *writes* are required, which points hard at post-write
  internal activity
- **Wedges** → writes are irrelevant and the trigger is in init/teardown

### Bring back for round 13

Per run: cold or warm, what the predecessor was, the gap in seconds, and
`mount_tests`' pass/fail plus its `unmount()` and `mount()` #2 codes. The
cold/warm split predicts `0` and `-7` respectively — note any run that breaks
that model, since one earlier `0` on a wedged run is still unexplained.

**Standing rules:** a study returning "nothing here" is a result; and do not
diagnose from hypotheses — send the transcript and say what surprised you.

## ROUND 14 — recovery, and the float that was never tested in the right order

### 14a — can a wedged card be recovered without removing power? (do this first)

**Nobody has asked.** Rounds 12 and 13 established thoroughly what *causes* the
wedge. "Only a power cycle clears it" is an observation about the two things anyone
happened to try — re-running the suite, and waiting — not a tested claim.

It matters more than root cause right now: if any sequence revives the card, the
user-facing defect becomes something the driver can detect and repair, and
**v1.7.1 stops being blocked on an explanation**.

```bash
cd tools
# 1. POWER-CYCLE.  2. Wedge the card deliberately:
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120   # cold, expect CLEAN
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120   # warm, expect WEDGED
# 3. WITHOUT power cycling, run the recovery ladder:
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D RECOVERY
```

Five escalating rungs, each reported separately so a partial success is visible:
plain re-init twice, then 102,400 clocks with **CS high** (25x the driver's own
recovery flush) and a re-init, then the same with **CS low** and a re-init. A
claimed recovery is checked with a real sector read — a card that inits but cannot
read is not recovered.

Idle time is already known not to help (13b), but idle is not the same as clocked:
an SD card advances its state machine on SCK, and a card waiting for clocks it will
never receive looks exactly like a dead one.

**Any rung succeeding is the most valuable result available this round.**

### 14b — bisect the predecessor: which operation actually arms it?

**Why this is the highest-information run available.** We can trigger the wedge on
demand, but the predecessor that arms it is an entire regression suite — card
init, filesystem mount, directory reads, a FAT scan, an unmount, a cog shutdown.
"A driver session arms it" is true and nearly useless, because any one of those
could be the trigger while the rest are bystanders.

`SD_wedge_predecessor.spin2` is that session with a dial on it. Every arm is
download-size-matched to the reproducer — **47,327 to 47,369 bytes against
`SD_RT_mount_tests`' 47,347** — so the arms differ in what they *do* and not in how
long they take to arrive.

```bash
cd tools
# POWER-CYCLE, run ONE rung, then the reproducer -- no power cycle between:
./run_test.sh ../diagnostic-tests/SD_wedge_predecessor.spin2 -t 60 -D P_INIT
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120
```

**Start at `P_INIT` and escalate only if an arm comes back clean.** If card init
alone arms it, the answer arrives in one run and the entire filesystem layer is
exonerated.

| Rung | Predecessor does | If this is the first to wedge |
|---|---|---|
| `P_NOTHING` | nothing at all | control — **must be clean**, or the reproducer is responding to something else |
| `P_INIT` | `initCardOnly()`, cog left running | card initialisation alone arms it; filesystem exonerated |
| `P_INIT_STOP` | `initCardOnly()` then `stop()` | **the cog shutdown is the trigger, not the card activity** — see below |
| `P_MOUNT` | `mount()`, cog left running | filesystem mount adds something init does not |
| `P_MOUNT_UNMOUNT` | `mount()` + `unmount()` | the unmount is implicated |
| `P_READ` | `mount()` + one sector read + `unmount()` | a data transfer is required |

**`P_INIT_STOP` is the rung to watch.** `stop()` halts the worker cog with
`COGSTOP`, and a stopped cog releases its DIR bits — so the SD pins go
high-impedance right there, inside a running application, with no reset anywhere
near it. If `P_INIT_STOP` wedges while `P_INIT` does not, the trigger is the float
rather than the card activity, and the driver has a defect it can fix directly:
park the pins before halting the cog.

Power-cycle before every rung. One rung per power-on.

### 14c — float the pins after a driver session, with no reset

**Round 13a's conclusion needs one qualification.** It ran a 49.7 KB pin-silent
binary as predecessor, stayed clean, and concluded the reset, the float window and
the download traffic were all eliminated. That holds for a **virgin** card — in 13a
the float came *before* any driver session ever touched the card. In the wedging
sequence the float comes *after* one. **The order was never varied**, so "a card
that has been driven, then left floating" is still untested.

That combination has a candidate mechanism: CMD0 latches the card into SPI mode
until it loses power, and a card already in SPI mode interprets a floating CS and
stray SCK very differently from one still in native SD mode. It would explain every
row of round 13's table at once — cold clean, null-binary clean, in-binary cycles
clean (pins stay driven, CS held high), reset-separated sessions wedged.

```bash
cd tools
# POWER-CYCLE first. One binary, no reset anywhere in it:
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D FLOAT_BETWEEN
```

The probe releases all four SD pins to high-Z for 1200 ms between cycles — matched
to the reset-and-download window — and then mounts again.

- **Wedges** → no reset is required. The mechanism is bounded to the pins, and the
  P2 side is out of scope entirely
- **Clean** → floating after a driver session is *not* it either, and something
  else about the reset matters

### 14d — the same float, with CS held high

Only if 14c wedges. Same sequence, but CS is **driven high** throughout the float
while the other three go high-Z — which is what a board-level pull-up would do.

```bash
cd tools
./run_test.sh ../diagnostic-tests/SD_edge_wedge_probe.spin2 -t 300 -D FLOAT_CS_HIGH
```

- **Clean** → CS is the mechanism, and a pull-up on the CS pin is a candidate fix
  that needs no driver change at all
- **Wedges** → CS is not sufficient on its own; SCK or MOSI floating matters too

### Bring back for round 14

14a: the rung reached, each rung's status, and the post-recovery read result.
14b: the rung reached and whether each wedged — the SMALLEST wedging rung is the
result. 14c/14d: wedged or clean, and on which cycle. As always the identity line, and the
`unmount()` / `mount()` #2 codes.

**Standing rules:** a study returning "nothing here" is a result; and do not
diagnose from hypotheses — send the transcript and say what surprised you.

## ROUND 15 — the third thing a reset does (added 2026-08-19)

### The gap in the elimination table

Round 14 closed out the reset's two *card-visible* effects — floating pins (both
orders) and download duration. But a P2 reset does something else to the card
entirely, and nothing has tested it: **the boot ROM talks to the SD card.**

Per the P2 knowledge base (`p2kbArchSdCardBoot`, `p2kbArchBootPatternSelection`),
the ROM boot pattern is read from P59/P60/P61 on every reset, and:

- **P60 pulled up selects SD boot** — and P60 *is our CS pin*. The SD specification
  gives the card an internal 50 kΩ pull-up on CS, which is exactly what would
  assert that pattern whenever a card is seated.
- On that pattern the ROM **initialises the card in SPI mode, mounts FAT32, and
  looks for a boot file**, then falls back to the serial window when it finds none.
- All of this happens under **RCFAST (20-30 MHz)**, before any user code runs.

So on every single download, the boot ROM may be conducting its own complete SD
conversation with our card, at a clock we do not control, before our driver ever
sees it. That is a card-visible effect of the reset, it is not floating pins, and
it is not download duration.

### The model this produces, and it fits every row

**Our driver's init leaves the card in a state that the ROM's next SD-boot attempt
turns into a wedge.**

| Sequence | ROM/driver order | Observed |
|---|---|---|
| cold | ROM init → our init | clean ✓ |
| null-binary predecessor (13a) | ROM init → ROM init → our init | clean ✓ |
| `P_INIT` predecessor (14b) | ROM init → **our init** → ROM init → our init | **wedge** ✓ |
| in-binary cycles (14c and the probe) | our init → our init, no ROM | clean ✓ |
| 120 s powered idle (13b) | our init → idle → ROM init → our init | **wedge** ✓ |

Every row agrees, including the two that most constrained the space. The ROM's own
leftovers are benign to the ROM; ours are not.

### 15a — turn SD boot off and re-run

The boot pattern table gives a clean way to stop the ROM touching the card:
**`P59 = up` → "Program from serial within 60 s window; no flash or microSD card
boot"**. On the Edge module P59 is the **`△` / `▽` DIP switch pair** — flip **`△`
ON** (and make sure `▽` is OFF; both on is a contradiction). Serial download keeps
working, which is the whole point.

```bash
# 1. Set the P59 UP DIP switch ON. 2. POWER-CYCLE.
cd tools
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120   # cold  -- expect CLEAN
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120   # warm  -- THE QUESTION
```

- **Warm run CLEAN** → the boot ROM's SD conversation is the trigger. That is the
  root cause, after four rounds, and it explains why nothing the driver does can
  recover: the damage is done before our code runs
- **Warm run WEDGED** → the ROM is exonerated too, and the reset's effect on the
  card is something none of us has thought of yet

Run the pair twice to be sure, power-cycling between. Then **flip the switch back**
and confirm the wedge returns — a fix that cannot be un-fixed is not yet proven.

### What 15a can and cannot deliver

**It is a diagnostic, not a fix.** We cannot require users to set a DIP switch —
booting from SD is a legitimate configuration our driver has to work in, and users
have their own boards. So 15a's value is identification only: if the wedge
disappears with SD boot off, we know what we are fighting.

### 15b — CMD12 before CMD0: the fix that could work on any board

If the ROM is leaving the card mid-transfer, our init should be able to quiesce it
before use — and there is a specific, spec-designated way to do that which nothing
has yet tried.

**A card left in a data-transfer state is not listening for commands; it is
streaming.** CMD0 sent into that stream is data, not a command — which is exactly
the observed failure: five CMD0 retries, no response, `E_NO_CARD`. It also explains
why round 14a's recovery ladder failed: a multiple-block read continues until it is
told to stop, so 102,400 extra clocks in either polarity only fed it.

Part 1 Physical Layer §4.3, verbatim: *"All data read commands can be aborted any
time by the stop command (CMD12). The data transfer will terminate and the card
will return to the Transfer State."*

`initCard()` has never sent CMD12, and neither did the recovery ladder. A gated
step is now in the driver — **default OFF**, so shipped behaviour is unchanged
until this proves out.

```bash
# POWER-CYCLE. Normal switch settings (SD boot ENABLED -- we want the ROM to run):
cd tools
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120 -D SD_INIT_QUIESCE   # cold
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2 -t 120 -D SD_INIT_QUIESCE   # warm -- THE QUESTION
```

- **Warm run CLEAN** → the driver can quiesce the card itself, on any board, with
  no switch and no user action. That is a shippable fix and it unblocks the release
- **Warm run WEDGED** → CMD12 is not sufficient; the card is stuck in a way the
  stop command does not reach, and 15a's result tells us whether the ROM is even
  the right suspect

Run both cold and warm, twice. Also run the **unmodified** build warm in the same
session to confirm the wedge is still reproducing that day — a fix that is really
just a quiet day proves nothing.

### If the ROM is confirmed but CMD12 does not help

Then the honest position is a documented incompatibility, narrower than it first
looks: it needs a *marginal or counterfeit* card **and** a board with SD boot
enabled. No mainstream card has ever wedged. That is a scope worth stating
precisely rather than a blanket warning.

### Bring back for round 15

Switch position for every run, cold/warm, `mount_tests` pass/fail, and the
`unmount()` / `mount()` #2 codes. Both directions: switch on, and switch back off.

**Standing rules:** a study returning "nothing here" is a result; and do not
diagnose from hypotheses — send the transcript and say what surprised you.

## ROUND 16 — the fix, and how big the problem really is (added 2026-08-19)

### 16a — CMD12 quiesce (carried over from 15b, still unrun)

Unchanged from the round 15 section: build with `-D SD_INIT_QUIESCE` at **normal**
switch settings (boot-time SD access ENABLED — we want the wedge condition present)
and run cold then warm. Also run the unmodified build warm in the same session, so
a clean result cannot be a quiet day.

This is the release-relevant run. If the driver can quiesce the card itself, no
user action and no board change is needed.

### 16b — is this a general Edge exposure, or this bench's flash program?

**The hand-back's attribution question is half-answered by its own data.** It
proposes running P61 up + P59 float to separate the boot ROM from the flash
program — but **that is the configuration that has been wedging all along**
(switches `1-2 up, 3-4 down` are exactly P61 up, P59 floating), and SD boot is not
part of that boot pattern. The ROM's **SD-boot** path never ran. It is exonerated.

That leaves two candidates, and the second is not in the hand-back's list:

**(a) The boot ROM's *flash* traffic on shared pins.** On the Edge, P58-P61 serve
both flash and microSD **with CLK and CS swapped** — P60 is flash CLK but microSD
CS, P61 is flash CS but microSD CLK. So while the ROM reads flash, the card sees
**its own chip-select toggling at flash clock rate**. Every flash boot does this.
**This would be a general P2 Edge exposure**, not specific to this bench.

**(b) The flash-resident program** — the `* Hi! from FLASH *` banner. Not ours; it
turns up in `src/DEMO/logs/` transcripts from March. If that program touches the SD
card, it is the culprit and the problem is an artefact of what happens to be in
this board's flash.

**The difference decides the release wording.** (a) means every Edge user with
flash boot enabled is exposed. (b) means almost nobody is.

**The run:** erase the flash program, or replace it with something that provably
never touches P58-P61, and **leave flash boot ON**. Then the usual cold/warm pair.

- **Still wedges** → (a). The ROM's flash-interface traffic is the mechanism, and
  this is a general Edge exposure worth documenting prominently
- **Clean** → (b). The flash program did it, and the scope collapses to boards
  running SD-touching code from flash

**Cheaper first step, costing no bench time: ask what is actually in that flash.**
If it is a hello-world that never touches the SD pins, (a) follows by elimination
and 16b can be skipped.

### Bring back for round 16

16a: cold/warm for both the quiesce build and the unmodified build, same session.
16b: what was in flash, what replaced it, and the cold/warm result with flash boot
still enabled.

## ROUND 16 — certify the fix, then the catalog sweep (added 2026-08-19)

### 16a — full regression with the quiesce as default

`initCard()` now issues CMD12 before CMD0 on every start, with no flag. That
touches every card, every mount, so it needs the full suite rather than a spot
check.

```bash
cd tools
./run_regression.sh
```

Expect **532/532**. Note the driver no longer prints a quiesce marker — the
unconditional debug line was removed when the step became production, because
production has no business printing on every mount. Build shape is the proof now:
there is no other build.

### 16b — is the Lerdisk still "External only"?

The two `asdfg` cards are recorded in the catalog as **External connector only**,
because they wedged in the Edge socket. **That was this defect.** Round 15b already
showed `mount_tests` 43/43 on the Lerdisk in the Edge socket with the fix — but the
catalog claim covers the whole suite, so it needs the whole suite.

```bash
# Lerdisk $0000_01F4 in the EDGE socket:
cd tools
./run_regression.sh
```

- **Passes** → the card records and `CARD-CATALOG.md` need rewriting: these cards
  are no longer socket-restricted, and a documented incompatibility disappears
- **Fails elsewhere** → the wedge is fixed but something else limits them; record
  precisely what, because "External only" would then need a narrower reason

This card is expendable and reformattable.

### 16c — full catalog performance sweep (RELEASE GATE)

**v1.8.0 does not ship without this** (Stephen, 2026-08-19). The driver has changed
materially since every number in the catalog was taken — read alignment moved to
the measured band centre, a production speed bound was added, and now every card
start begins with a quiesce. The existing figures predate all of it.

Procedure is `DOCs/cards/CATALOG-PROCEDURE.md` per card. Two things the container
side must settle **before** the sweep starts, because they change what the
instruments must emit:

1. **Run variance before instance variance.** Round 11b measured the same physical
   card moving up to 3x between rounds. Repeat one card several times first to
   establish the noise floor; only then do differences between instances mean
   anything.
2. The new two-table format, silicon-key grouping, and driver-version stamping are
   **not built yet**. Sweeping before they exist means sweeping twice.

Expect this to be an afternoon for every working card, per Stephen's estimate.
