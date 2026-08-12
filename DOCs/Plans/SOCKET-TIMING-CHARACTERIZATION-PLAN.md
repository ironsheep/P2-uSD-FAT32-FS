# Socket Timing Characterization Plan

**Status:** proposed 2026-08-11 — deferred until the v1.7.0 bench campaign completes.
**Scope:** `diagnostic-tests/` only (never ships). The driver is not modified by any
tier of this plan.
**Problem owner:** Stephen. Drafted from the 2026-08-11 discussion.

---

## 1. The problem

Most testing runs on the P2 Edge Module's own microSD socket, which cannot be probed
with a logic analyzer. An external adapter with its own microSD socket *can* be
probed. The two are known to differ in signal timing (trace length, connector/stub
capacitance, contact resistance), but the differences cannot be characterized by
instrument — the instrument cannot reach the socket that matters.

## 2. The methodology: calibration transfer

The P2 can act as its own timing instrument (Tiers 1–2 below). On-die measurement
has a property the logic analyzer cannot offer: **the same instrument, through the
same input path, sees both sockets unloaded** — an analyzer probe on the adapter
changes the very edges being measured, while the P2's view is probe-free and
identical for both sockets, so any difference it reports is attributable purely to
socket + wiring (card held constant).

The adapter's probeability is then used the other way around:

1. Measure the **adapter** socket with both the logic analyzer and the on-die
   instrument. Reconcile them. The on-die instrument is now calibrated against the
   analyzer.
2. Point the calibrated instrument at the **Edge** socket. Its reading stands on
   the analyzer's authority, transferred through the calibration.

## 3. The measurand

The quantity that decides driver correctness is the **round-trip data-valid delay
at the P2 pin**: SCK edge leaves the P2 pad → socket/wiring out → card launches
MISO after its clock-to-output delay (t_ODLY, spec'd up to ~14 ns at default
speed) → socket/wiring back → MISO crosses the P2 input threshold. Call it δ.
δ is what determines whether ON-edge `P_SYNC_RX` sampling (`%1_00111`, the mode
this driver deliberately uses) has margin at 25 MHz on each socket, and it is the
parameter class behind CLAUDE.md prohibition #4.

Note that the SCK reference in Tier 2 is the **read-back state of the SCK pad**
(P61's pin read state), so SCK slew differences caused by socket loading are
inside the measurement too — a feature, not an error term.

## 4. Tier 1 — margin shmoo

**First look, zero new code:** `diagnostic-tests/SD_freq_sweep_tests.spin2`
(15–25 MHz sweep), `diagnostic-tests/SD_spi_limit_test.spin2`, and the driver's
CRC error counters (`SD_INCLUDE_DEBUG`) can bound the question — record the
frequency where CRC errors first appear per socket — before any tool is built.

**The characterization tool — `SD_socket_shmoo.spin2` (one tool, decided
2026-08-11):** frequency sweep × sampling mode × socket in a single binary,
because all three dimensions share the same machinery (init, set speed, read a
known sector, score by CRC counters, step):

- Inner loop: at each frequency, read under both `%1_00111` (ON-edge) and
  `%0_00111` (PRE-edge) `P_SYNC_RX` sampling — the two-curve shmoo maps the
  data-valid window edge directly.
- Outer loop: both sockets, sequentially, in one powered session. The driver is
  a singleton but restarts cleanly on a different pin base (`stop()` →
  re-init on the adapter's pins), so temperature and supply are common-mode
  across the whole matrix.
- Each phase reads the CID serial of the card in the socket under test and
  prints it into the transcript — self-labeling per the card-serial transcript
  convention; a card swap is detected, not trusted to bench notes.

The failure boundary is the *integrated* timing margin — every socket
difference folded into one number per socket per sampling mode. It answers
*how much* the sockets differ, and whether Tier 2 is worth building.

### 4.1 Dual-socket population and the crossed (2×2) design

Both sockets can be populated simultaneously. A single session therefore
measures two *different* cards — card and socket are confounded. The protocol
that separates them: run the full matrix, **swap the two cards between
sockets**, run again. The 2×2 result — δ(card, socket) under both assignments —
algebraically separates the card contribution from the socket contribution, so
the socket difference comes out free of card-to-card variation. The CID-serial
self-labeling makes the swap verifiable from the transcripts alone.

**Card selection (multiple same-vendor sets are available):**

- **Primary comparison: a matched pair** — two cards of the same vendor set
  (same model, ideally adjacent date codes). Matching minimizes the card term
  going in; the 2×2 swap removes what remains. t_ODLY is a card property, so an
  unmatched pair would put most of the raw difference in the cards, not the
  sockets — matching keeps the measurement working close to zero.
- **Replication: repeat the 2×2 with a second (and third) matched pair.** The
  spread of the extracted socket difference across pairs is the error bar: it
  says whether the observed socket delta stands above card-population noise.
  The within-model card-to-card spread that falls out is itself a useful
  by-product for the card catalog.
- One cross-vendor pair at the end is worth a run: if the *socket* difference
  extracted with dissimilar cards agrees with the matched-pair value, the
  separation algebra is confirmed working.

## 5. Tier 2 — the XOR skew probe (direct δ measurement)

**A separate tool from the shmoo (decided 2026-08-11):** the probe reconfigures
the MISO smart pin mid-transaction, collects timing statistics rather than
pass/fail, and the §7 sysclk vernier wants runs at six `_CLKFREQ` values (or
`clkset()` hot-switching with debug-serial re-init) — none of which the shmoo
needs. Keeping the shmoo simple keeps it trustworthy, and the shmoo's result
decides whether this tool gets built at all. Suggested name:
`SD_socket_skew_probe.spin2`.

Dual-socket population helps here too: the per-sysclk socket-A/socket-B pairs —
where every fixed offset cancels in the difference — are taken minutes apart in
one session instead of across a card swap, keeping drift common-mode. The §4.1
swap protocol then separates card from socket exactly as in the shmoo.

**Pin-spacing constraint:** the XOR trick needs MISO and SCK within ±3 on the
adapter's pin group as well — but the driver's `P_SYNC_RX` clock routing already
imposes that on any pin set the driver runs on, so any adapter wiring the driver
works with satisfies the probe by construction.

**Hardware facts (verified against P2KB):** a smart pin's A and B inputs route
from neighbors within ±3 (`WRPIN` selector fields), and the `FFF` field combines
A/B with logic/filtering, including XOR. MISO = P58 and SCK = P61 are exactly +3
apart — the same routing the driver's `P_SYNC_RX` already uses for its clock
input. MISO never drives, so reconfiguring its smart pin cannot float anything.
(The exact `FFF` encoding for XOR is confirmed against the Silicon Doc when the
diagnostic is written.)

**Design:**

- Pre-fill a sector with `$AA` so MISO toggles every bit (2048 transitions per
  sector read).
- Issue a normal read via the diagnostic's own card machinery, but during the
  data phase reconfigure the MISO smart pin (P58) from `P_SYNC_RX` to **mode
  `%10000` (time A-input states)** with input = **XOR(this pin, +3 pin)
  = XOR(MISO, SCK)**.
- Every SCK launch edge toggles the XOR; the card's MISO transition toggles it
  back **δ later**. The XOR signal's short states *are* δ — one sample per bit.
- Run SCK slow (1–2 MHz) so the cog can collect every state duration via
  IN-flag + `RDPIN`. δ is a launch delay plus wire time — it does not change
  with SCK frequency, so nothing is lost by measuring slow.
- Sector data is discarded. This pass measures; it does not read.

**Primary analysis:** same card, same sysclk, both sockets → Δδ between sockets,
with every deterministic offset (input synchronizer, smart-pin pipeline) cancelling
in the difference. **Secondary analysis:** absolute δ per socket, which needs the
per-frequency calibration of §7 because fixed pipeline offsets are constant in
*ticks* and therefore scale as n·T in nanoseconds across sysclk choices.

## 6. The quantization problem this creates

One sysclk tick at 350 MHz is ~2.857 ns. Because SCK is generated from sysclk
(`P_TRANSITION`, half-period in sysclk ticks), the launch edge is phase-locked to
the measurement clock — so the quantization of δ is **near-deterministic, not
averaging**. A single sysclk gives a staircase: every δ inside the same tick bin
reads identically, and averaging 2048 samples sharpens the *same wrong bin*, not
the value. Resolution stalls at ±1 tick (~3 ns) — enough for capacitance-dominated
socket differences, not for trace-length ones.

The fix is a **sysclk vernier**: repeat the capture at several sysclk frequencies.
Each frequency lays its own quantization grid (boundaries at n·T, T = 1/f_sys)
over the fixed analog δ; each capture reports which bin δ falls in on that grid;
the intersection of the bins across grids localizes δ far more finely than any
single grid.

## 7. Choosing the sysclk set — the banding rule

**The failure mode (banding):** two frequencies whose grids coincide give repeated
behavior instead of new information. Grid boundaries coincide where
n·T_i = m·T_j, i.e. wherever f_i/f_j = n/m. Writing f_i/f_j = p/q in lowest
terms, the **first coincidence sits at p·T_i = p/f_i**. If that point lands inside
the δ window of interest (0–20 ns), the pair is partially redundant — the bands
repeat exactly as predicted.

Named anti-examples, worst first:

| Pair | Ratio | First coincidence | Verdict |
|---|---|---|---|
| 175 / 350 MHz | 1:2 | every 350 MHz boundary | grids nest completely — zero new information |
| 200 / 300 MHz | 2:3 | 10.0 ns | dead center of the window — bad pair |
| 280 / 350 MHz | 4:5 | 14.3 ns | right in the expected t_ODLY region — bad pair |
| 220 / 330 MHz | 2:3 | 9.1 ns | why 330 is excluded when 220 is used |

**Selection rule:** choose frequencies pairwise such that, with f_i/f_j = p/q in
lowest terms, p/f_i ≥ 20 ns. Additionally prefer periods spread across a tick
(arithmetic-ish in *period*, not frequency) so the union of grid boundaries covers
the window evenly rather than clustering.

**Recommended set — six frequencies, all pairs verified:**

| f_sys (MHz) | tick T (ns) | grid boundaries in 0–16 ns |
|---|---|---|
| 350 | 2.857 | 2.86, 5.71, 8.57, 11.43, 14.29 |
| 340 | 2.941 | 2.94, 5.88, 8.82, 11.76, 14.71 |
| 320 | 3.125 | 3.13, 6.25, 9.38, 12.50, 15.63 |
| 300 | 3.333 | 3.33, 6.67, 10.00, 13.33 |
| 270 | 3.704 | 3.70, 7.41, 11.11, 14.81 |
| 250 | 4.000 | 4.00, 8.00, 12.00, 16.00 |

Pairwise first-coincidence check (lowest-terms ratio → coincidence point):
250/300 = 5:6 → 20.0 ns; 250/350 = 5:7 → 20.0 ns; 300/350 = 6:7 → 20.0 ns
(all exactly at the window edge, acceptable); every other pair (25:27, 9:10,
15:16, 16:17, 34:35, …) first coincides at ≥ 33 ns. **No interior coincidence
below 20 ns.**

Coverage of the boundary union: above 8 ns — where δ (t_ODLY plus round trip) is
expected to live — the largest gap between adjacent boundaries is ~0.95 ns, and
mostly ≤ 0.6 ns. Below 6 ns there is a ~1.7 ns desert (4.00 → 5.71 ns); if early
captures show δ landing that low, add **220 MHz** (T = 4.545 ns; boundaries 4.55,
9.09, 13.64) — verified clean against all six (worst pair 220/300 = 11:15 →
50 ns). 330 MHz must stay out of any set containing 220 (2:3 → 9.1 ns).

**Why the vernier is legitimate despite lock-step SCK:** changing sysclk changes
*both* the tick size and the phase of the launch edge relative to the grid, so the
six captures are six genuinely independent quantizations of the same analog δ.
The remaining per-frequency unknowns (fixed pipeline offsets, in ticks) are
resolved once, on the adapter socket, against the logic analyzer — that is the §2
calibration — and cancel entirely in socket-vs-socket differences taken at the
same sysclk.

Practical notes: all six frequencies are reachable from the 20 MHz crystal PLL;
the 2 Mbaud debug link and the 1–2 MHz measurement SCK are unaffected by the
sysclk choice; run the whole set in one powered session per socket so temperature
drift stays common-mode.

## 8. Tier 3 — edge-rate profiling (only if Tiers 1–2 disagree)

Every P2 pin has comparator-against-internal-DAC modes. With a repetitive signal,
sweep the DAC threshold and time the crossings against a reference edge —
equivalent-time sampling reconstructing the edge profile, i.e. rise-time
differences between sockets (the capacitance signature directly). Considerably
more work; reach for it only if the shmoo and the XOR probe tell conflicting
stories.

## 9. Deliverables and order

1. **After the v1.7.0 campaign clears:** Tier 1 on both sockets, same card — one
   bench session, zero new code. Record per-socket failure frequency and CRC
   error-rate curves.
2. If margins differ meaningfully: author the XOR-probe diagnostic
   (`diagnostic-tests/SD_socket_skew_probe.spin2` or similar), calibrate on the
   adapter against the logic analyzer (§2), then measure the Edge socket across
   the §7 frequency set.
3. Output: a per-socket δ profile (mean, spread, per-sysclk bins), the
   socket-vs-socket Δδ, and the margin math against the 25 MHz ON-edge sampling
   budget. File alongside the card catalog work in `DOCs/`.

## 10. Constraints

- Nothing in this plan modifies `src/` — driver, suites, or utilities.
- All new code lives in `diagnostic-tests/`, which never ships (release.yml
  excludes it) and sits outside regression certification.
- Nothing starts until the current bench campaign completes; if any tier's
  findings motivate a driver change, that change enters through the normal
  sequence (style conformance → compile → regression → hardware).
