# Socket Shmoo — Bench Run Notes

**From:** the host-native bench agent, hand-back for the container side.
**Run date:** 2026-08-17. **Brief:** `DOCs/Plans/SOCKET-SHMOO-RUN-BRIEF.md`.
**Tool:** `diagnostic-tests/SD_socket_shmoo.spin2`, unmodified.
**Status:** rounds 1, 2 and 2b all run — bench scope complete.

> **Read the consolidated hand-back at the end of this document first.** This doc
> is written in run order, so each round's verdict is scoped to the cards that
> round used. In particular the round-1 verdict below ("card effect is zero") is
> true *of the Gigastone pair* — round 2b later found a card that carries its own
> failure. The closing section reconciles all of it.

## Round 1 verdict — the Gigastone pair

**The boundary difference is a socket effect. Across this matched pair the card
effect is zero.**

Both cards are clean at 43.75 MHz in the Edge onboard socket. Both cards fail at
43.75 MHz in the external adapter. The failure stayed with the socket across a
physical swap.

| | EDGE (onboard) | ADAPTER (base 16) |
|---|---|---|
| Clean boundary | hp=4 / **43.75 MHz** — every cell tested | hp=5 / **35.0 MHz** |
| Failing cell | none | hp=4, 2/8 cmd errors → abort |

Identical in all four mode/path combinations — ON-edge and PRE-edge sampling,
smart-pin Path A and streamer Path B — in every run.

## Runs

| Log (`tools/logs/`) | Edge socket | Adapter socket | Result |
|---|---|---|---|
| `SD_socket_shmoo_260817-142540.log` | unmarked `$0000_01C7` | GREEN `$0000_01C9` | Edge clean 14→4; adapter fails hp=4 |
| `SD_socket_shmoo_260817-142607.log` | unmarked `$0000_01C7` | GREEN `$0000_01C9` | identical (immediate confirm run) |
| `SD_socket_shmoo_260817-142854.log` | **GREEN `$0000_01C9`** | **unmarked `$0000_01C7`** | identical — failure stayed with the adapter |

The PSN printed in each socket phase proves the swap took: the serials exchange
sockets between run 1 and run 2, and the results do not move with them.

## Cards

Matched pair as the protocol asked for — CID identical except the serial:

```
MID $74  OID 'J`'  PNM '00000'  rev 0.0  mfg 2023/7
GREEN     PSN $0000_01C9
unmarked  PSN $0000_01C7
```

Consecutive serials, so same production reel. Mapping confirmed by Stephen at the
bench: green highlight was in the external eval-board socket for run 1.

## Failure signature

Every occurrence, in all three runs, byte for byte:

```
4  43_750  ON   |    2   0   0  |    2   0   0
4  43_750  PRE  |    2   0   0  |    2   0   0
```

Exactly 2 of 8 reads fail, on **cmd** — 0 crc, 0 data — in both sampling modes and
on both paths, then the cell early-aborts (254). So it is the **command-response
(R1) read** that loses margin first, not data sampling and not CRC. That the two
sampling modes and the two data paths are indistinguishable is consistent with
this: the R1 read is common code beneath all four.

The cliff is hard, not marginal — perfectly clean at 35 MHz, fails at 43.75 with
no degraded cell in between.

## Caveat: the headline delta is a lower bound

**The Edge boundary was never measured.** hp=4 is the fastest cell in the sweep and
the Edge socket passed it clean in all four socket phases, so the Edge boundary is
censored by the sweep floor. The honest statement is:

> adapter = 35.0 MHz; Edge ≥ 43.75 MHz; delta ≥ 1 hp step, magnitude unknown.

To turn that into a measurement the sweep has to extend below hp=4 — hp=3 is
58.3 MHz and hp=2 is 87.5 MHz at 350 MHz sysclk.

## First-light report

The brief flagged two risks. Neither materialized:

- `stop()` → `initCardOnly()` on a different pin base **works**. Every adapter
  phase initialized cleanly after a clean Edge phase, in all three runs.
- No socket failed wholesale at hp=14, so neither tool nor wiring is broken.

No warning fired in any run: CRC scoring **active** on both cards (no dummy-CRC
quirk in this pair), no `hp requested but driver landed` mismatch, and reference
reads agreed at 1988 kHz in all four socket phases. The sweep runs in 4–6 seconds
clean; `-t 300` is generous but correct for the failing-cell case.

---

# Round 2 — sysclk ladder (same session, 2026-08-17)

The round-1 caveat above asked for cells below hp=4. That is not reachable:
`applySPISpeed` **hard-clamps half_period to ≥ 4**, so `clkfreq/8` is the ceiling
on any build. The container side's answer — the `SYSCLK_*` ladder now in the tool
— is the right one: hold hp=4 and *rebuild at a lower sysclk*, which places the
fastest cell between the 350 MHz grid points and brackets the adapter cliff that
otherwise hid in the wide gap between 35.0 and 43.75 MHz.

Ran with the cards left exactly as round 2 left them (Edge `$0000_01C9` GREEN,
adapter `$0000_01C7` unmarked — PSNs confirm it in all four transcripts).

| sysclk | hp=4 cell | EDGE | ADAPTER | log (`tools/logs/`) |
|---|---|---|---|---|
| 290 MHz | 36.25 MHz | clean | **clean** | `SD_socket_shmoo_260817-150723.log` |
| 300 MHz | 37.50 MHz | clean | **fails** (2/8 cmd) | `SD_socket_shmoo_260817-150735.log` |
| 320 MHz | 40.00 MHz | clean | fails | `SD_socket_shmoo_260817-150747.log` |
| 336 MHz | 42.00 MHz | clean | fails | `SD_socket_shmoo_260817-150758.log` |
| 350 MHz | 43.75 MHz | clean | fails | round-1 logs above |

## Result

**The adapter cliff is bracketed between 36.25 MHz (clean, 0/8) and 37.50 MHz
(2/8 cmd errors).** The transition is sharp — 0 to failing across a single
1.25 MHz step, with no degraded cell between:

```
290 MHz  4  36_250  ON   |    0   0   0  |    0   0   0
300 MHz  4  37_500  ON   |    2   0   0  |    2   0   0
```

The failure signature is unchanged from round 1 at every ladder point: exactly
2 of 8, **cmd only**, 0 crc, 0 data, identical in both sampling modes and on both
paths. Five sysclks and three card placements have now produced the same
signature — it is a stable property of the adapter path, not an artifact.

**The Edge socket is still censored.** It passed hp=4 at every sysclk on the
ladder, and every ladder point is *slower* than 43.75 MHz, so the ladder refines
the adapter number without touching the Edge one. Standing statement:

> adapter cliff ∈ (36.25, 37.50] MHz; Edge ≥ 43.75 MHz; **socket delta ≥ 6.25 MHz**
> (≥ ~17%), true magnitude still unknown.

Measuring the Edge boundary needs sysclk *above* 350 (hp=4 at 360 → 45.0, at
380 → 47.5, at 400 → 50.0 MHz), which is a separate decision about running the P2
past its rated sysclk — not a bench call. Say the word and I'll add ladder points
upward; the tool needs only new `#ifdef` arms.

## The `status=` discriminator — answered

The ladder builds carry the new per-failure status line, so the round-2 question
("which code appears?") is already answered. Across the 300 / 320 / 336 MHz
failing cells, every failing read on the adapter:

```
pathA cmd fail read#1: status=-3      pathA: -3 in every instance
pathB cmd fail read#1: status=-1      pathB: -1 on the first failing read,
pathB cmd fail read#2: status=-3              -3 on the rest
```

**Dominantly `status=-3` (E_BAD_RESPONSE) — the card answers, and the answer
arrives garbled.** Not silence. Per the brief's key that puts the **return path
(MISO) under suspicion**, not outbound SCK/MOSI integrity.

One nuance worth keeping: this does *not* simply contradict round 1's
mode-invariance. ON-edge and PRE-edge sampling still score identically, so the
suspect is the MISO **return path itself** — signal integrity and propagation
delay through the adapter — rather than the *choice of sampling point*, which is
what the two modes vary. A response that arrives late or degraded is garbled
under either sampling mode; that is consistent with both observations at once.

The recurring `-1` on Path B's *first* failing read, followed by `-3` on later
reads in the same cell, is a small unexplained sub-pattern — reproducible at all
three sysclks. Flagging it rather than theorizing.

---

# Round 2b — the asdfg pair, run 1 (2026-08-17)

Log: `tools/logs/SD_socket_shmoo_260817-151209.log`. Default 350 MHz build.
Placement: **Lerdisk 1GB in Edge, the other asdfg in the adapter** (Stephen).
No wedge — the read-only workload completed cleanly, both phases.

## FIRST: a second, uncatalogued Cloudisk 2GB

| | brief expected | transcript says |
|---|---|---|
| Edge | Lerdisk `$0000_01F4` | `$0000_01F4` ✓ mfg 2025/12 |
| Adapter | Cloudisk 2GB `$0000_1680` | **`$0001_9B39`** mfg 2025/11 |

**Resolved (Stephen, 2026-08-17):** the card markings are correct — the adapter
card *is* a Cloudisk 2GB, just not the catalogued one. It is a **second Cloudisk
2GB, not yet in the catalog**. The catalog record for `$0000_1680` is fine; this
is a new card needing its own record per the catalog procedure.

```
Cloudisk 2GB #2   PSN $0001_9B39   mfg 2025/11
CID raw: $05 $00 $0C $61 $73 $64 $66 $67 $22 $00 $01 $9B $39 $01 $9B $00
MID $05  PNM 'asdfg'  rev 2.2
```

**And it differs from its family in a way that matters.** The Lerdisk fired the
`CRC scoring appears INACTIVE` warning and scored crc mismatches on every read.
This Cloudisk fired **no warning and scored crc = 0** — i.e. its data CRC
*matched the computed CRC on every read*. If the asdfg class is documented as
`CW_NO_DATA_CRC` silicon twins, this card does not behave like one. That is
either a real split inside the counterfeit class or a limit of the detection
heuristic, and it is directly relevant to
`DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md`. Worth a dedicated look;
this run was not designed to settle it.

## The Edge result — a fourth outcome, not on the brief's list

The brief predicted three discriminating shapes. The observed one is none of
them:

```
 6  29_166  ON   |  A: 0  8  0  |  B: 0  8  0        <- clean (bar crc, see below)
 5  35_000  ON   |  A: 0  8  0  |  B: 0  8  8        <- Path B data, 8/8
 4  43_750  ON   |  A: 0  8  0  |  B: 0  8  8
        pathB data diff: 512 bytes, first at 0 exp=$C1 got=$E0
```

- **cmd = 0 everywhere.** The card always answers, at every frequency.
- **Path A (smart pin) data = 0 everywhere**, including 43.75 MHz.
- **Path B (streamer) data = 8/8 at hp=5 and hp=4**, all 512 bytes wrong.
- **Mode-invariant** — ON and PRE identical, so not a sampling-point question.

So: not mode-dependent (rules out the cyclic sampling-alignment branch), not
broken at 12.5 MHz (rules out the edge-rate/ringing branch), and not clean on
both sockets (rules out the write-path-only branch). It is **streamer-path only,
frequency-banded at ≥ 35 MHz, mode-invariant** — which points at streamer
alignment timing (`align_delay`), not at MISO sampling and not at signal
integrity.

**The corrupted byte looks like a one-bit shift.** `exp=$C1` is `1100_0001`;
`got=$E0` is `1110_0000` — exactly `exp >> 1` with a `1` shifted in from the
left. That is the classic signature of the streamer capturing one bit early.
Caveat: the tool prints only the first differing byte, so this reading rests on
one byte pair. Worth confirming with a dump before it is built on.

## Tool defect: dummy-CRC cards can never show a clean boundary

The `CRC scoring appears INACTIVE` warning fired on the Lerdisk as the brief
predicted — but its own text says *"crc columns will read 0"* and the columns
actually read **8** (every read scored a CRC mismatch). The summary grid then
sums the error classes, so every Edge cell totals ≥ 8 and the comparison prints:

```
ON  PathA  none clean       hp= 5 35000 kHz
```

`none clean` is an artifact. Path A was clean at every cell. Two bugs to fix
container-side:

1. The warning's predicted behaviour (`0`) contradicts the observed behaviour
   (`8`) — one of the two is wrong.
2. When the quirk is detected, crc must be **excluded from the cell total**, or a
   dummy-CRC card can never report a boundary. The summary total also exceeds
   `READS_PER_CELL` (16 of 8), so the header `error reads of 8` is wrong — it is
   summing classes, not counting reads.

Also note the adapter's asdfg card scored crc = 0 with **no** inactive-warning,
while the Lerdisk fired it. If these two are genuinely silicon twins, that
difference wants explaining.

## The adapter result — the socket boundary reproduces on a different card class

```
 5  35_000  |  0 0 0  |  0 0 0        clean
 4  43_750  |  2 0 0  |  2 0 0        status=-3 on every failing read
```

Identical to the Gigastone result: clean to 35.0 MHz, 2/8 cmd failures at
43.75 MHz, `status=-3` (E_BAD_RESPONSE), both paths, both modes. **The adapter
boundary now reproduces across two unrelated card families** (Gigastone SDHC and
counterfeit asdfg SDSC), which is strong evidence it is a property of the socket
rather than of any card.

**Reconciliation status after run 1 alone:** looked like the catalog's
Edge-FAIL / External-PASS inversion reproduced in the read path. **The swap
overturned that** — see run 2 below. Card and socket were still confounded here,
exactly as with the Gigastones before their swap.

---

# Round 2b — run 2, swapped (2026-08-17)

Log: `tools/logs/SD_socket_shmoo_260817-151731.log`. Swap confirmed by PSN:
Edge = Cloudisk #2 `$0001_9B39`, adapter = Lerdisk `$0000_01F4`. No wedge.

| | **in EDGE** | **in ADAPTER** |
|---|---|---|
| **Lerdisk `$01F4`** | Path B fails ≥ 35.0 MHz *(run 1)* | Path B fails ≥ **29.17 MHz** *(run 2)* |
| **Cloudisk #2 `$9B39`** | **clean at every cell** *(run 2)* | clean ≤ 35.0, cmd cliff at 43.75 *(run 1)* |

## The streamer failure follows the CARD, not the socket

Cloudisk #2 moved into the Edge socket and read **clean at every cell, both
paths, through 43.75 MHz** — the exact cells where the Lerdisk had failed 8/8.
The Lerdisk moved into the adapter and **still fails Path B** there.

So the ≥35 MHz streamer corruption is a **Lerdisk property**, not an Edge-socket
property. This directly reverses the run-1 reading.

**And the adapter makes it worse, not better.** The Lerdisk's Path B onset moves
from 35.0 MHz on Edge down to **29.17 MHz** in the adapter — one step *earlier*.
That is the opposite of the "adapter delay rescues these cards" hypothesis: for
this card the adapter costs margin on the streamer path just as it does on the
command path.

## The catalog inversion is NOT reproduced in the read path

Stated plainly, because run 1 suggested otherwise: **the Lerdisk fails Path B on
both sockets** — worse on the adapter. There is no read-path Edge-FAIL /
External-PASS inversion in this data. Per the brief's third branch, the
documented inversion therefore looks **confined to the write/commit path**, which
this read-only tool cannot see. Settling it needs a write-capable probe; wedge
#3240 remains untouched (no wedge fired in any 2b run).

## The adapter cmd cliff is now a four-card result

The 43.75 MHz / 2-of-8 / `status=-3` cmd cliff appeared on the adapter for
**every card tested** — Gigastone `$01C7`, Gigastone `$01C9`, Cloudisk #2
`$9B39`, and Lerdisk `$01F4` — across two unrelated card families and both
sampling modes and paths. It is a socket property, and that conclusion is now
carried by four cards rather than two.

## Shift-signature nuance

The first differing byte is `exp=$C1`:

- at 35.0 MHz → `got=$E0` = `exp >> 1` with a `1` shifted in — a clean one-bit
  right shift.
- at 29.17 MHz → `got=$E1` — the same top bits but with LSB set, which a pure
  one-bit shift of `$C1` does not produce.

So "one-bit shift" fits the 35 MHz case exactly and the 29.17 MHz case only
approximately. Still a single byte per cell; a full dump is needed before this is
treated as characterized rather than suggestive.

---

# Round 3 — align-delay hunt (2026-08-17)

Tool: `diagnostic-tests/SD_phase_sweep_test.spin2` (R3a) and the fixed
`SD_socket_shmoo.spin2` (R3b). Card under test throughout: **Lerdisk `$0000_01F4`**.

## R3a — the align-delay offset rescues Path B, and the socket costs 1 tick

The brief's R3a called for Edge at 35 MHz and adapter at 29.17 MHz — each socket
at its own onset frequency. Those two arms ran and agreed, but **that pairing is
confounded**: different `hp` means the offsets are not comparable across sockets,
so it cannot measure a socket delay. **A third arm was added** — Edge at
29.17 MHz — so that one comparison varies socket and nothing else.

| run | socket | hp / freq | Path B passing band |
|---|---|---|---|
| `SD_phase_sweep_test_260817-160509.log` | Edge | 5 / 35.000 MHz | `[1..8]` |
| `SD_phase_sweep_test_260817-160225.log` | Adapter | 6 / 29.166 MHz | `[1..8]` |
| **`SD_phase_sweep_test_260817-160545.log`** | **Edge** | **6 / 29.166 MHz** | **`[0..8]`** |

**Same card, same frequency, only the socket differs: Edge `[0..8]` vs adapter
`[1..8]`.**

> ### The adapter costs exactly one sysclk tick — ~2.86 ns at 350 MHz.

That is the direct δ the plan expected to need Tier 2's XOR probe for. It fell
out of Tier 1 tooling instead, and it is worth checking against Tier 2 rather
than treating as a substitute: this method resolves to ±1 tick by construction,
so "1 tick" means *one tick, not zero and not two* — it does not distinguish
1.0 ns from 2.8 ns of physical delay.

Both sampling modes gave identical bands in all three arms — the align-delay axis
is the one that matters here, and the sampling-mode axis remains flat.

**Why the card fails in production:** the driver's default is offset 0.

- Edge @ 29.17 MHz — 0 is inside `[0..8]` → works.
- Adapter @ 29.17 MHz — 0 is one tick below `[1..8]` → fails.
- Edge @ 35 MHz — the band's lower edge has moved to +1 → 0 fails.

That reproduces the round-2b shmoo result exactly, from the mechanism side. The
requirement is `align_delay ≥ hp + k`, with k rising as frequency rises and one
extra tick charged by the adapter.

**Upper edge still censored:** every arm passes at +8, the sweep's maximum, so
`width` is a lower bound. Only the lower edge is a measurement. Widening the
sweep past +8 would close it.

## R3b — the one-bit shift is confirmed, and scoring is fixed

Log: `tools/logs/SD_socket_shmoo_260817-160608.log` (Lerdisk in Edge, Cloudisk #2
in adapter). Note this log needs `grep -a` — the dump makes grep treat it as
binary.

**The scoring fixes work.** The warning now reads *"card returns dummy data CRC
(quirk class) — crc scoring is DISABLED for this phase … crc is excluded from
cell totals"*, headers read `bad reads of 8 per path`, and the Lerdisk's
`none clean` artifact is gone. Its true boundaries now print:

| | Path A | Path B |
|---|---|---|
| Lerdisk on Edge | clean through **43.75 MHz** | clean through **29.166 MHz** |

**The full dump settles the shift question.** All 512 bytes: `exp` is uniformly
`$C1`, `got` is uniformly `$E0`.

Repeating `$C1` is the bit stream `…11000001 11000001…`. Sampling it one bit late
yields `[prev LSB=1][1100000]` = `1110_0000` = `$E0`, for **every** byte — which
is exactly what the dump shows. A one-bit *left* shift would give `$83`, which
does not appear.

**Confirmed: a one-bit right shift of the whole stream** — not scattered bit
errors, not a byte-boundary slip. One honest limit: because the reference pattern
is a uniform repeating byte, any shift of k ≡ 1 (mod 8) bits aliases to the same
result, so this pins the shift to *1 mod 8*, with direction certain. Pinning the
absolute count would need a non-uniform reference sector.

This is fully consistent with R3a: a one-bit sampling misalignment is exactly what
a one-tick-short `align_delay` produces.

---

# Step A — regression re-certification (2026-08-17)

Log: `tools/logs/regression_260817_clamp_recert.log`. Card: unmarked Gigastone
`$0000_01C7` in Edge (confirmed by preflight identify), SCRATCH role, baseline
reformat + reformat around destructive suites.

**ALL 27 SUITES PASSED — 530 tests, 0 failures, 439 s.** Closing audit clean
(23/23). 27/27 suites compiled, 0 fail, plus 15 consumer programs. The widened
`debugSetAlignDelayOffset` clamp (`[-8, +16]`) is re-certified on hardware.

Two notes for the record:

- **530 tests here vs the 574 cited in the v1.7.0 release record.** Suite count
  matches (27) and nothing was skipped or failed in this run. Test counts do vary
  with cluster geometry, which is the likely explanation, but **this has not been
  verified** — check before citing this run as equivalent to the release
  certification.
- The identify block names the vendor **"Transcend"** (MID `$74`) while the
  physical label is **Gigastone**. Same card, relabelled silicon. If the catalog
  records these as Gigastone, cross-reference the MID so a future reader does not
  infer a third card.

---

# Round 4 — the band top is closed (2026-08-17)

Gigastone pair, unmarked in Edge / GREEN in adapter. Sweep now runs offsets
−3..+16 (20 offsets × 2 modes). **Every arm now shows FAILs at high offsets — the
upper edge is a measurement, not a censored bound.**

| log | socket | hp / freq | passing band | width | center |
|---|---|---|---|---|---|
| `SD_phase_sweep_test_260817-171629.log` | Edge | 7 / 25.0 MHz | `[-1..11]` | 13 | 5 |
| `SD_phase_sweep_test_260817-171642.log` | Adapter | 7 / 25.0 MHz | `[-1..12]` | 14 | 5 |
| `SD_phase_sweep_test_260817-171653.log` | Edge | 5 / 35.0 MHz | **`[1..9]`** | 9 | 5 |
| `SD_phase_sweep_test_260817-171704.log` | Adapter | 6 / 29.166 MHz | `[0..11]` | 12 | 5 |

Both sampling modes identical in all four arms, as in every prior round.

**The centre is 5 in all four arms** — bands narrow as frequency rises but they
narrow *symmetrically about the same centre*. That is a strong, simple result.

## What this says about a production default

- **Narrowest measured band is `[1..9]`** (Edge, 35 MHz).
- **The candidate `hp + 2` is inside all four bands** — but it sits only **1 tick
  above the lower edge** of the narrowest one.
- **`hp + 5` is inside all four with ≥ 4 ticks of margin on both sides** in the
  narrowest band, and it is the measured centre of every arm.

On this data `hp + 5` is the better-supported default and `hp + 2` is
under-margined. **But do not act on that yet — see the conflict below.**

## ⚠ Two instruments disagree — resolve before choosing a default

The phase sweep says **offset 0 FAILS on the Gigastone, Edge socket, 35 MHz**:

```
sysclk=350 hp=5 mode=0 offset=-1 path_b=FAIL
sysclk=350 hp=5 mode=0 offset=0  path_b=FAIL
sysclk=350 hp=5 mode=0 offset=1  path_b=PASS
```

The round-1 shmoo says the **same card, same socket, same 35 MHz, Path B, at the
production default (offset 0) read 0 errors of 8** — and stayed clean at
43.75 MHz too.

Both cannot describe the same configuration. Either the shmoo's Path B
under-reports streamer misalignment, or the phase sweep's Path B over-reports it.
The most plausible benign explanation is that **the two tools exercise different
streamer call sites** (the driver has several, and the NCO/alignment fix is
documented as bilateral across all four) — in which case each is right about its
own path and neither generalises to "the streamer."

This matters directly: the whole point of round 4 was to choose a shipping
default against a measured band. **A default chosen from a band the other
instrument contradicts is not safe.** Recommend the container side reconcile the
two Path B implementations before picking a number; a single arm run against the
shmoo's exact read call would settle it.

### Confirmed simultaneous — the disagreement is real, not stale

The two conflicting results originally came hours apart, across many reseats and
a driver clamp edit, so the conflict could have been an artifact of drift. It is
not. Both tools were re-run **back to back in one session, on one seated card**
(unmarked Gigastone `$0000_01C7`, Edge socket, sole card in the rig):

```
shmoo        5  35_000  ON  | A: 0 0 0 | B: 0 0 0     <- Path B CLEAN at 35 MHz
             4  43_750  ON  | A: 0 0 0 | B: 0 0 0     <- and clean at 43.75

phase sweep  hp=5 mode=0 offset=0  path_b=FAIL        <- same 35 MHz, FAILS
             hp=5 mode=0 offset=1  path_b=PASS
```

Logs: `SD_socket_shmoo_260817-175558.log` and
`SD_phase_sweep_test_260817-175600.log`, two minutes apart.

**Two consequences.** First, the clamp edit is exonerated — the shmoo still reads
clean at 35 and 43.75 MHz after it, so nothing regressed between this morning and
now. Second, the conflict is a genuine, reproducible property of the two
instruments: they do not agree about the same nominal configuration on the same
card in the same session. That is strong support for the different-call-sites
hypothesis and it makes the reconciliation work clearly justified rather than
speculative.

---

# Round 5a — write probe, healthy cards (2026-08-17)

Log: `tools/logs/SD_write_probe_260817-172000.log`. Gigastone pair, GREEN
`$0000_01C9` in adapter, unmarked `$0000_01C7` in Edge (both PSN-confirmed).
Destructive as designed — scratch LBA 200,100+. Readback at hp=14 / 12.5 MHz with
default read alignment. Phase 3 correctly did **not** run.

**Every cell passed.** Roughly 168 cells:

| phase | socket | command | pads swept | result |
|---|---|---|---|---|
| 1 | Adapter | CMD25 | hp14: 2–30, hp7: 2–16, hp5: 2–12 | all PASS |
| 1 | Adapter | CMD24 | same grid | all PASS |
| 2 | Edge | CMD25 | same grid | all PASS |

## The write path shows no pad sensitivity at all

This is a sharp contrast with the read path. The read side has a narrow, clearly
bounded passing band that closes as frequency rises (`[1..9]` at 35 MHz). The
write side passes at **every** tx pad from 2 to 2+2·hp, at every frequency, on
both sockets, for both commands. No band, no edges, no socket difference.

Two readings, and this run cannot separate them:

1. **The write path is genuinely far more tolerant than the read path** —
   plausible, since the card samples MOSI against its own clock recovery rather
   than the P2 sampling a returning edge.
2. **The probe cannot report failure.** A grid that is 100% PASS everywhere has
   not demonstrated that its failure detection works.

**Reading 2 must be excluded before 5a is cited as evidence of write-path
health.** Per the project's own standing lesson, a health check that has never
been shown capable of failing is not yet a health check. The probe does define
`WRITE_ERR`, `READBACK_ERR` and `DATA_MISMATCH`, but none of them fired here, so
none of them are proven reachable.

**5b is the natural failure case** — the asdfg class is where write-path trouble
is documented. If 5b also returns all-PASS, the probe's failure path is unproven
and should be deliberately provoked (e.g. a knowingly bad pad, or a readback
against a corrupted reference) before any write-path conclusion rests on it.

---

# Round 5b / 5c — asdfg class and the wedge zone (2026-08-17)

**5b** — log `tools/logs/SD_write_probe_260817-173707.log`. Lerdisk `$0000_01F4`
in Edge, Cloudisk #2 `$0001_9B39` in adapter (both PSN-confirmed). Same phases
1+2 as 5a. **165 cells, all PASS. No wedge.**

**5c** — the wedge zone, Edge + CMD24 on the documented #3240 wedger, one cell per
run, slowest first. **No wedge fired at any frequency, so no power cycle was
needed.**

| arm | log | hp / freq | write | second write | sector-0 health | verdict |
|---|---|---|---|---|---|---|
| `P3_SLOW` | `SD_write_probe_260817-173740.log` | 14 / 12.5 MHz | PASS | PASS | 0 | healthy |
| `P3_PROD` | `SD_write_probe_260817-173801.log` | 7 / 25.0 MHz | PASS | PASS | 0 | healthy |
| `P3_HIGH` | `SD_write_probe_260817-173820.log` | 5 / 35.0 MHz | PASS | PASS | 0 | healthy |

The second write — "the wedge classically bites here" — passed at all three
frequencies.

## Finding 1: the wedge does not reproduce through the raw-init write path

Saying it loudly, as the brief asks. The documented #3240 wedger, in the socket
where it wedges, writing with the command it wedges on, at three frequencies
spanning its whole operating range, **did not wedge**. Single-sector raw writes
plus verification plus a repeat write are not sufficient to trigger it.

That relocates the trigger: whatever wedges this card lives in the
**filesystem/mount path**, not in raw single-sector writes. The minimal
reproducer on record (mount_tests → raw_sector_tests, no power cycle) starts with
a *mount*, and that now looks essential rather than incidental. A probe that
wants to catch #3240 has to go through the mount path.

## Finding 2: the write probe has never once failed — treat 5a/5b/5c accordingly

Across 5a, 5b and 5c the probe ran roughly **336 write cells** on four cards of
two families, including the two counterfeit cards whose write path is the subject
of an open investigation. It has produced **zero** `WRITE_ERR`, zero
`READBACK_ERR`, zero `DATA_MISMATCH` and zero wedges. Every defined failure mode
is still unreached.

This is now the dominant caveat on all of round 5. Two readings remain open and
this campaign cannot separate them:

1. The write path really is broadly tolerant — no pad sensitivity, no socket
   sensitivity, no card sensitivity.
2. The probe's failure detection does not work.

**Do not record "the write path is healthy" from this data.** The correct
statement is *the probe reported no failures, and the probe has never been shown
capable of reporting one*. Before round 5 supports any conclusion, provoke a
known failure and confirm the instrument catches it — a deliberately wrong pad
outside the working range, a readback compared against a corrupted reference, or
a write to a card known to reject it. That is cheap and it converts ~336 green
cells from decorative into evidence.

---

# Round 6 — instrument proof and re-verdict (2026-08-17)

Card: unmarked Gigastone `$0000_01C7`, sole card, Edge socket. 6c still pending
(needs the GREEN card in the adapter).

## 6a — detection paths PROVEN ✅

Log: `tools/logs/SD_write_probe_260817-182529.log`.

```
1) wrong-expectation compare reports mismatch:   INSTRUMENT PASS
2) absurd-LBA write returns error (status=-7):   INSTRUMENT PASS
SELFTEST VERDICT: detection paths PROVEN -- green grids are evidence
```

This closes the round-5 Finding 2 blocker. The probe's failure reporting works,
so the ~336 green cells of 5a/5b/5c are now evidence rather than decoration.

## 6b — all PASS, including the pads expected to fail

Log: `tools/logs/SD_write_probe_260817-182552.log`. Edge + CMD24, full pad sweep,
hp = 14 / 7 / 5. **Every cell PASS — including pads 8 and 15 at hp=7**, which the
brief expects to fail from the v1.7.0 record.

## 6d — the original instrument agrees, on the same card

Log: `tools/logs/SD_tx_phase_shmoo_260817-182659.log`. `SD_tx_phase_shmoo` — the
very tool that produced the v1.7.0 characterization — walked pads 2..30:

```
* pad=8:  A=CORRECT  B=CORRECT
* pad=15: A=CORRECT  B=CORRECT
* pad=22: A=CORRECT  B=CORRECT
* pad=29: A=CORRECT  B=CORRECT
* PASSING BAND: pad 2..30 (width 29 sysclks)
```

All four pads the v1.7.0 record lists as failing pass here, and the band is the
full swept range with no losing tooth anywhere.

(Caveat: this tool prints no PSN, so its card identity rests on session
continuity — no reseat occurred between 6a, 6b and 6d — rather than on the
transcript. Worth adding self-labeling to this tool.)

## This is NOT a conflict with the v1.7.0 record — it is a card difference

The brief's branch says all-PASS at 6b means "real conflict with the v1.7.0
record — report loudly, do not proceed." Reporting loudly, but with the
resolution, because the driver's own comment names the missing variable
(`src/micro_sd_fat32_fs.spin2:752`):

> Characterized 2026-08-11 on **Card 2b (SN `$0000_0F14`)**, Edge slot, 350 MHz /
> 25 MHz (hp=7) … Losing phase: pad == 1 (mod 7) — measured fails at pads 8, 15,
> 22, 29 … Default 4 = maximal mod-7 distance (3) from the cliff on both sides.

**The cliff was characterized on Card 2b `$0000_0F14`. Round 6 specifies the
unmarked Gigastone `$0000_01C7`.** Those are different cards, and the record is
explicitly card-scoped. So 6b was asked to reproduce, on one card, a phenomenon
only ever measured on another.

Two instruments — the new write probe and the original `SD_tx_phase_shmoo` —
independently find **no losing phase at all** on `$0000_01C7`. With 6a proving
detection works, the agreement is meaningful: the write probe is vindicated, and
the difference is in the **card**, not the instrument.

## 6c — the aliasing fix is confirmed; the instruments now agree ✅

Log: `tools/logs/SD_socket_shmoo_260817-182837.log`. Gigastone pair, unmarked
`$0000_01C7` Edge / GREEN `$0000_01C9` adapter, both PSN-confirmed. The alias
guard is live and self-reports:

```
Reference sector 0 captured at 1_988 kHz; shift-distinguishable; paths agree
```

**Path B now fails at 35 MHz on the Edge socket**, exactly as the container side
predicted, matching the phase sweep's offset-0 FAIL at that frequency:

| socket | Path A boundary | Path B boundary |
|---|---|---|
| Edge | 43.75 MHz | **29.166 MHz** |
| Adapter | 35.0 MHz | **29.166 MHz** |

Compare with the pre-fix run, where Edge Path B read clean all the way to
43.75 MHz. **The reference-aliasing diagnosis is confirmed on hardware, and the
shmoo/phase-sweep conflict is resolved** — the shmoo was blind, the phase sweep
was right.

Two observations to pass on:

- **Path B's new failures land in the `cmd` column, not `data`** (`2 0 0`). For a
  reference-content change that is unexpected — a shift should surface as a data
  mismatch. It may be that a failed token/CRC read is scored as `cmd`, in which
  case the label is misleading rather than the result wrong. Worth a look before
  these columns are read literally.
- **Both sockets now show the same Path B boundary, 29.166 MHz.** The read-
  streamer limit therefore looks card/driver-bound rather than socket-bound —
  unlike the command path, where the adapter's one-tick cost is real and
  measured. The socket difference lives in the cmd cliff (43.75 vs 35.0 on
  Path A), not in Path B.

## The consequence for the shipping default — this is the real finding

`tx_align_delay = 4` is justified in the driver as *"maximal mod-7 distance from
the cliff on both sides."* That justification is derived from **one card's**
cliff. If the losing tooth is card-specific — and `$0000_01C7` shows no tooth
where `$0000_0F14` shows four — then:

- the cliff's *position* may also be card-specific, and
- pad 4 being maximally distant on Card 2b implies nothing about its distance
  from another card's cliff.

**The default's safety margin is therefore unestablished across the card
population**, even though the default itself may well be fine. This is a
different and more consequential question than the one round 6 set out to
answer.

**Decisive next run:** 6b and 6d on **Card 2b `$0000_0F14`** — the card the cliff
was actually measured on. That is the only run that can confirm the v1.7.0 record
still reproduces, or show that the cliff has gone away since (the driver has
changed underneath it). After that, the same sweep on two or three further cards
would establish whether the tooth moves, and pad 4's real margin.

Note: `DOCs/Agent-Reports/README.md` designates `$0000_0F14` "never a
certification card" — that does not bar it from characterization work, which is
what this is, but the run should be labelled as such.

---

# Round 7d — the 360 MHz overclock run (2026-08-17)

Log: `tools/logs/SD_socket_shmoo_260817-185505.log`. Bounded overclock to
**360 MHz and no higher**, per Stephen's approval. Gigastone pair, unmarked
`$0000_01C7` Edge / GREEN `$0000_01C9` adapter, both PSN-confirmed. Alias guard
live on both phases.

## Overclock control: PASSED — the run is valid

Every slow cell (12.857 – 30.0 MHz) is clean on **both** sockets. The P2 is happy
at 360 MHz, so the fast-cell results are interpretable rather than discardable.

## The Edge cmd ceiling is STILL not reached

| | Path A | Path B |
|---|---|---|
| **Edge** | clean at **45.0 MHz** — every cell | 30.0 MHz |
| **Adapter** | 36.0 MHz | 30.0 MHz |

**Edge hp=4 at 45.0 MHz passes clean.** Per the brief's own decision rule this is
the stopping condition: the map closes at **Edge ≥ 45.0 MHz**, and the ceiling
remains censored — now by the approved overclock limit rather than by the hp
clamp.

**Socket delta, stated from measured brackets:** Edge ≥ 45.0 MHz; adapter cliff
in (36.25, 37.50] from the round-2 ladder; therefore **delta ≥ 7.5 MHz**. (The
brief anticipates 7.75; the difference is only which end of the adapter bracket
is used. 7.5 is the figure the measurements support without interpolation.)

The adapter's Path A cliff at 45.0 MHz, with 36.0 clean, is the same-session
sanity check the brief asked for — the instrument still sees the known cliff.

## New: the first marginal cell of the entire campaign

Adapter, hp=6 / 30.0 MHz, PRE, Path B: **1 error of 8**.

Every other failing cell in seven rounds has been all-or-nothing — 0, 2, or 8 of
8. This is the first partial. It sits exactly at the adapter's Path B boundary
and it drops that mode's reported boundary a step (PRE Path B: hp=7 instead of
hp=6), which is why the two modes disagree there for the first time.

Worth noting rather than theorising: it suggests the Path B limit is a genuinely
marginal, statistical edge on the adapter rather than the hard cliff the command
path shows. A repeat run would say whether it recurs at the same cell.

---

# Round 7a — Card 2b recovered; the tooth reproduces; the default lands on it

**Card 2b was located** (Stephen, 2026-08-17) and verified before use:

```
L1: Gigastone OEM ASTC SDXC 58GB [FAT32] SD 6.x rev2.0 SN:$0000_0F14 2023/06
L2: Class 10, U3, V30, SPI 25 MHz  [P2FMTER]
```

Note this is **different silicon from the pair swept in rounds 1–7d** — those
report *Transcend 00000 SDHC 29GB, SD 3.x rev0.0*; this is an SDXC 58GB U3/V30,
SD 6.x rev2.0. A different controller generation, which is consistent with a
tooth on one and none on the other. Write/format approved by Stephen.

## The v1.7.0 record replicates exactly

`SD_tx_phase_shmoo` (the original instrument, now PSN-labelled), log
`tools/logs/SD_tx_phase_shmoo_260817-190157.log`:

```
>>> SERIAL PSN=$0000_0F14  PNM='ASTC ' <<<
* pad=8:  A=SHIFTED-LATE  B=SHIFTED-LATE
* pad=15: A=SHIFTED-LATE  B=SHIFTED-LATE
* pad=22: A=SHIFTED-LATE  B=SHIFTED-LATE
* pad=29: A=SHIFTED-LATE  B=SHIFTED-LATE
* PASSING BAND: pad 2..7 (width 6 sysclks)
```

Pads 8, 15, 22, 29 — **the exact four the driver comment lists**, all ≡ 1 (mod 7)
at hp=7. The v1.7.0 characterization is validated, the tooth is real, and it is
card-specific (absent on `$0000_01C7` under two instruments, present here).

## The write probe detects it — instrument fully vindicated

Log `tools/logs/SD_write_probe_260817-190217.log`. The probe that had never
failed in ~336 cells now reports `DATA_MISMATCH diffs=512` precisely where the
tooth is. Combined with 6a's selftest, its failure detection is proven both
synthetically and against a real defect.

## ⚠ THE FINDING: the shipped default sits ON the tooth at hp=5

The probe swept three frequencies, and the tooth appears at **all three** — with
period hp, but at a **different residue each time**:

| hp | SPI | failing pads | residue |
|---|---|---|---|
| 14 | 12.5 MHz | 8, 22 | ≡ 8 (mod 14) |
| 7 | 25.0 MHz | 8, 15 | ≡ 1 (mod 7) |
| **5** | **35.0 MHz** | **4, 9** | **≡ 4 (mod 5)** |

**`tx_align_delay = 4` is the shipped default. At hp=5 it fails —
`DATA_MISMATCH`, diffs=512, the whole sector wrong.**

The driver's justification (`micro_sd_fat32_fs.spin2:752`) is explicitly scoped
to *"350 MHz / 25 MHz (hp=7)"*, where pad 4 does sit at maximal mod-7 distance
from the cliff. That reasoning is correct **and complete only at hp=7**. The
residue moves with hp, so distance-from-cliff computed at one frequency does not
carry to another.

### Severity — stated carefully

This card's CSD declares `TRAN_SPEED = 25 MHz`, so running it at 35 MHz is
already **above its rated speed**. At its rated 25 MHz the default is safe, with
the documented distance of 3. That materially limits the exposure, and this is
not evidence of corruption at supported settings on this card.

What it does establish: **the default pad's safety is frequency-dependent and has
only ever been verified at one frequency on one card.** Any change that raises
SPI speed — a faster default, a card with a higher `TRAN_SPEED`, or a user
setting one — can land the default on a tooth, and the failure is silent
whole-sector write corruption.

Recommend the container side treat this as a **punch-list item for the release
gate** and decide explicitly: either bound the supported write speed, make the
pad frequency-aware, or document the constraint. It should not pass silently.

---

# Round 7b — the tooth is NOT card-specific. It is driver-side.

## Card 2 of the survey: SanDisk Extreme Pro

```
L1: SanDisk AGGCE SDXC 59GB [FAT32] SD 5.x rev8.0 SN:$A345_3C0E 2016/12
L2: Class 10, U3, V30, SPI 25 MHz    L3: CSD claims TRAN_SPEED = 25 MHz
```

Both instruments, and the result is **byte-identical to Card 2b**:

| hp | SPI | failing pads — Card 2b `$0000_0F14` | failing pads — SanDisk `$A345_3C0E` |
|---|---|---|---|
| 14 | 12.5 MHz | 8, 22 | **8, 22** |
| 7 | 25.0 MHz | 8, 15 | **8, 15** |
| 5 | 35.0 MHz | 4, 9 | **4, 9** |

`SD_tx_phase_shmoo` likewise: pads 8, 15, 22, 29 `SHIFTED-LATE`, passing band
`2..7` — the same four pads and the same band as Card 2b.

## This overturns the round-7a conclusion

These are **unrelated cards**: different vendor (SanDisk vs Gigastone/ASTC),
different controller, different SD spec revision (5.x rev8.0 vs 6.x rev2.0),
different manufacturing year (2016 vs 2023), different capacity.

If the losing phase were a **card** timing property — t_ODLY, input setup/hold —
its position would differ between two such different parts. **It does not differ
at all.** Identical pads, identical frequencies, identical failure mode.

**The correct model is therefore the opposite of round 7a's:**

> The losing phase is a **fixed, driver-side phase relationship in the P2 write
> path**. It is at the same pads on every card. What varies card to card is only
> whether that card's input margin **tolerates** the bad phase.

`$0000_01C7` (Transcend SDHC, SD 3.x) shows no tooth not because it has no tooth,
but because it tolerates the phase the other two cannot. That is a far more
ordinary explanation than three cards each having their own coincidentally-shaped
cliff — and it predicts that any card with tighter margin will fail at exactly
pads 8/15/22/29 (hp=7) and 4/9 (hp=5).

## What this does to the `tx_align_delay = 4` finding

**It raises the severity.** Round 7a could be read as one odd card. It cannot now:

- **Two of the three cards tested fail at pad 4 / hp=5**, from unrelated vendors.
- The failing position is **predictable, not card-lottery** — which means it is
  also *fixable* driver-side rather than needing per-card calibration.

**What still bounds it:** both cards declare `TRAN_SPEED = 25 MHz`, and at 25 MHz
(hp=7) the passing band is `2..7` — pad 4 is comfortably inside it. The failure
needs hp=5 / 35 MHz, which is above both cards' declared rating.

Note a fact worth checking across the remaining cards: **even a U3/V30 SanDisk
Extreme Pro declares 25 MHz.** If 25 MHz is simply the SD **SPI-mode** ceiling
rather than a per-card figure, then 35 MHz is out of spec on *every* SD card in
SPI mode, and the exposure stays bounded no matter how fast the card is rated for
its native bus. That would be the difference between "documentation constraint"
and "live defect", so it is worth confirming rather than assuming.

## The complete population survey — five cards

| PSN | label / silicon | spec rev | tooth? | pads (hp=7) |
|---|---|---|---|---|
| `$0000_01C7` | Gigastone label / **Transcend** SDHC 29GB | SD 3.x r0.0 | **no** | band 2..30 |
| `$0000_0F14` | Gigastone OEM **ASTC** SDXC 58GB | SD 6.x r2.0 | **YES** | 8, 15, 22, 29 |
| `$A345_3C0E` | **SanDisk** Extreme Pro SDXC 59GB | SD 5.x r8.0 | **YES** | 8, 15, 22, 29 |
| `$3449_0F1E` | Lexar Blue **MSSD0** 128GB | 2025/4 | **no** | band 2..30 |
| `$EEBA_D6C0` | WD Purple label / **SanDisk WX64G** SDXC 59GB | SD 6.x r8.0 | **YES** | 8, 15, 22, 29 |

**Three of five carry the tooth. Every one that does carries it at exactly the
same pads**, across three different controller families and spec revisions from
SD 5.x to 6.x. The two that don't show a clean band 2..30.

Write-probe grids on all three affected cards are identical too: `8, 22` at
hp=14; `8, 15` at hp=7; **`4, 9` at hp=5**.

(Two label-vs-silicon notes for the catalog: the "Gigastone 32GB" pair reports as
**Transcend**, and "WD Purple" reports as **SanDisk WX64G** — WD owns SanDisk.
Neither is a surprise, but both matter when a record is keyed by label.)

## Conclusion: a driver-side defect, bounded by the SPI-mode speed ceiling

**The mechanism is driver-side.** Identical failing pads across unrelated silicon
rules out a card timing property. The losing phase is fixed in the P2 write path;
cards differ only in whether their input margin tolerates it. One driver-side fix
covers the whole population — no per-card calibration needed.

**`tx_align_delay = 4` is safe at rated speed and unsafe above it.** At hp=7
(25 MHz) the passing band is `2..7` and pad 4 sits inside it on every card. At
hp=5 (35 MHz) the tooth moves to `4, 9` and **the shipped default lands on it** —
silent whole-sector write corruption, on three of five cards tested.

**What bounds the exposure:** every card measured with `identify` declares
`TRAN_SPEED = 25 MHz` — including a U3/V30 SanDisk Extreme Pro and an SD 6.x
WX64G. That is consistent with 25 MHz being the **SD SPI-mode ceiling** rather
than a per-card figure, in which case 35 MHz is out of spec on *any* SD card in
SPI mode and no card can reach the failing configuration while in spec.

**What is still true regardless:** the driver *permits* 35 MHz, the failure is
silent, and it hits the majority of cards tested. The bound is a specification
argument, not a guard in the code.

**Recommended for the release-gate punch list** — decide explicitly, do not let
it pass silently:

1. **Clamp or warn** — refuse (or warn on) SPI targets above the card's declared
   `TRAN_SPEED`, which closes this and any other above-spec surprise; **or**
2. **Make the pad frequency-aware** — pick `tx_align_delay` per hp so it never
   lands on `≡ 1 (mod hp)`; **or**
3. **Document the constraint** and accept it, with the reason recorded.

Option 1 is the smallest change and fixes the general case rather than this one
symptom. Option 2 is the only one that keeps 35 MHz working.

---

# Round 7 — status of the rest

- **7a — RUN AND DECISIVE.** Card 2b was found after all; see the section above.
  The tooth reproduces exactly, and the shipped default lands on it at hp=5.
- **7b — now the priority, and the question has changed.** It is no longer "does
  a tooth exist anywhere else?" but **"where does each card's tooth sit at each
  frequency, and does pad 4 ever land on one at a supported speed?"** Card 2b
  answers that with *yes, at 35 MHz* — above its own rated speed. A card rated
  for 35 MHz+ with the same residue behaviour would make it a live defect rather
  than a bounded one. Vary controller vendor, and sweep all three hp values per
  card rather than hp=7 alone.
- **7c — RUN.** Lerdisk `$0000_01F4` verified in Edge (asdfg SDSC 960MB, SD 1.x
  rev2.2, `cardWarnings() = $04`). Read-only sweep, 29.166 MHz, offsets −3..+16.
  Log: `tools/logs/SD_phase_sweep_test_260817-191...log`.

  **Band top closed: `[0..11]`, width 12, centre 5.** The R3a figure of `[0..8]`
  was censored by the old +8 limit; the true upper edge is 11.

  Two things follow. First, this is **identical to the Gigastone's band at the
  same frequency and socket** (round 4 adapter arm: `[0..11]`, width 12,
  centre 5) — so the read-side band is *not* card-specific between these two very
  different cards, and the Lerdisk's earlier trouble was the socket's one-tick
  shift, not a peculiar card. Second, **centre 5 again** — that is now five
  independent arms across two card families, both sockets, and three frequencies
  all centring on 5.

## Read-side default: `hp + 5` is well supported (a separate knob from the write tooth)

Worth stating explicitly because the two are easy to conflate:

- **`align_delay_offset`** — the **read** path knob. Round 4 + 7c bands. Every
  measured band centres on 5; the narrowest is `[1..9]`. **`hp + 5` sits mid-band
  in all of them; `hp + 2` sits one tick from an edge.** This recommendation is
  solid and is *not* affected by the tooth finding.
- **`tx_align_delay`** — the **write** path knob, currently 4. This is the one
  that lands on Card 2b's tooth at hp=5. Different mechanism, different
  measurement, different decision.

A change to one should not be justified by evidence from the other.

---

# Round 8a, attempt 1 — SUPERSEDED (defect record): the bundle regressed `SD_RT_speed_tests`

Log: `tools/logs/regression_260817_round8_mitigation.log`; failing suite detail in
`tools/logs/SD_RT_speed_tests_260817-212555.log`. Cards PSN-verified before the
run: Edge `$0000_01C7`, adapter `$0000_01C9`.

**Result: 27 suites, 528 pass, 2 fail.** `SD_RT_speed_tests` FAILED.
**8b was not run at this attempt** — the brief makes an 8a failure a stop-and-report, and nothing
should stack on uncertified driver state.

## It is a regression, not a pre-existing condition

Same suite, same card, same day, the only difference being the mitigation bundle:

| run | driver state | `SD_RT_speed_tests` |
|---|---|---|
| Step A (`regression_260817_clamp_recert.log`) | clamp widening only | **15 pass, 0 fail** |
| Round 8a (`..._round8_mitigation.log`) | + offset 0→5, + speed clamp | **13 pass, 2 fail** |

## Failure 1 — Test #8: `attemptHighSpeed()` now reports an I/O error

```
attemptHighSpeed: 0  isHSActive: 0  ERROR(): -7
SPI freq before: 25_000_000 Hz, after: 25_000_000 Hz
Sub-Test: card declined, query did not fail
Value: -7 (expected 0)
```

The card declining high speed is the expected path on this card. Previously that
left `ERROR()` clean; now it leaves `E_IO_ERROR (-7)`. The speed itself is
unchanged at 25 MHz, so the *outcome* is right and the *error state* is wrong.

## Failure 2 — Test #12: file I/O is broken after a speed change

This is the serious one — not a test-expectation mismatch but functional failure:

```
Test #11: setSPISpeed(400_000) init speed -> 399_543 Hz -> pass
Test #12: Data integrity after speed restore
   createFileNew() after restore .......... FAIL
   writeHandle() byte count 0 (exp 512) ... FAIL
   openFileRead after restore failed: -7
   readHandle() byte count 0 (exp 512) .... FAIL
   Pattern mismatch at 0: got $00 expected $A5
   SURVEY: raw read of directory sector FAILED
```

**Raw sector reads fail too**, so this is not confined to the filesystem layer —
the SPI link is left unusable after the 400 kHz set and subsequent restore.
Test #13 (`setSPISpeed(25_000_000)`) passes afterwards, so the driver recovers on
an explicit later call; it is the restore path inside #12 that breaks.

## Round 8a, attempt 2 — SUPERSEDED (defect record): one fixed, one remained

Driver updated 22:32 (+139/−31: `clampUserSpeed()`, `effectiveAlignDelay()`,
`overspeed_allowed`, and an hp=4 special case withholding positive offsets).
Log: `tools/logs/regression_260817_round8_rerun.log`; failing suite
`tools/logs/SD_RT_speed_tests_260817-230556.log`. Card `$0000_01C7` (preflight-
confirmed).

**529 pass, 1 fail** — up from 528/2.

- ✅ **Test #8 FIXED.** `attemptHighSpeed()` no longer leaves `ERROR() = -7`.
- ❌ **Test #12 UNCHANGED.** Identical functional failure: `createFileNew` fails,
  `writeHandle` returns 0, `openFileRead` returns -7, pattern mismatch, and the
  raw directory-sector read still FAILS.

## The exact reproducer (from the test source, not inference)

```
computedSpeed := sd.getSPIFrequency()   ' = 25_000_000 at mount
...
sd.setSPISpeed(400_000)                 ' Test #11 -> 399_543 Hz, PASSES
sd.setSPISpeed(computedSpeed)           ' restore to 25_000_000
<any file or raw I/O>                   ' Test #12 -> ALL FAIL
```

**A 25 MHz → 400 kHz → 25 MHz round trip leaves the SPI link unusable.** Both
endpoint values are legitimate and in-bounds for the new clamp, so this is not a
request being rejected — it is the transition itself.

This worked before the mitigation bundle: Step A scored this suite 15/0.

## Correction to the earlier Round 8a note

The first write-up said "Test #13 (`setSPISpeed(25_000_000)`) passes afterwards,
so the driver recovers on a later explicit call." **That was wrong and is
withdrawn.** Test #13 only asserts `getSPIFrequency()` lands in 20–30 MHz — it
performs no I/O, as do the timeout getters after it. Nothing following Test #12
exercises the link.

**There is therefore no evidence the driver recovers at all.** The link may stay
broken from the 400 kHz round trip until the suite ends. That is a materially
worse reading than the original note implied, and it removes the "recovers on a
later call" clue a reader might have chased.

## What I am not doing

Not diagnosing the driver from the bench. The evidence points at the new
`setSPISpeed()` clamp interacting with the low-speed set / restore sequence, but
naming a mechanism without reading the changed code would be speculation. Both
symptoms should be reproducible container-side from this transcript.

**Both changes ship together in this bundle, so it is worth isolating which one
is responsible** — the read-alignment default (0→5) and the speed clamp are
independent, and a build with only one of them would say which. The bench can run
that the moment such a build exists.

---

# Round 8 — THE BUNDLE IS CERTIFIED (run 3 of 8a, plus 8b)

**Run 2026-08-18, third attempt at 8a. Both 8a and 8b are GREEN.** The two prior
reds are gone, and neither was papered over — each was a real driver defect that
the container side fixed between attempts.

## 8a — full regression: 530 / 0

```
Result: ALL 27 SUITES PASSED
TOTAL   530 pass   0 fail   448s
Card health: closing audit clean. (23/23)
```

Log: `tools/logs/regression_260818_round8a_run3.log`.
Card: unmarked Gigastone `$0000_01C7` in the **Edge** socket, preflight-confirmed
(`Transcend 00000 SDHC 29GB [FAT32] SD 3.x rev0.0 SN:$0000_01C7 2023/07`,
`cardWarnings() = $00`, `TRAN_SPEED = 25 MHz`). Sweep-start fsck clean, nothing to
reclaim; two card reformats during the run (baseline + before `fatchain`), both OK.

### `SD_RT_speed_tests` — all three watch items landed as specified

15 pass, 0 fail. Log: `tools/logs/SD_RT_speed_tests_260818-125535.log`.

| Test | Expected by the brief | Observed |
|---|---|---|
| #8 | `attemptHighSpeed: -1  isHSActive: -1`, both true | `attemptHighSpeed: -1 isHSActive: -1 ERROR(): 0`, freq before `25_000_000` → after `43_750_000` |
| #9 | genuine create/write/read-back; a `-7` is a FAIL | `data integrity post-HS: 4_294_967_295` (= -1, TRUE) — passes on its merits, not by abstention |
| #12 | passes as collateral of the same fix | pass |

**The run-2 contradiction is gone.** `isHSActive` now agrees with a successful
attempt at 43_750_000 Hz, which is the whole point of replacing the
`spi_freq >= 50_000_000` inference with the explicit `hs_mode_active` flag — at
this project's 350 MHz sysclk, verified high speed resolves to hp=4 / 43.75 MHz
and the old threshold answered FALSE while the card was genuinely in high-speed
mode.

**The fourth exit is confirmed hooked.** Test #10, immediately after the
hand-set clock restore, reads `spiFreq = 25_000_000 Hz, HS active: 0` — the card
is back in default timing rather than stranded in CMD6 high speed. That stranding
was run 2's root cause, and the suite now demonstrates its absence directly.

## 8b — socket shmoo: the `hp + 5` default made visible

Log: `tools/logs/SD_socket_shmoo_260818-130306.log`. Gigastone pair, standard
placement, no swap: unmarked `$0000_01C7` in Edge, GREEN `$0000_01C9` in the
adapter — both PSN-confirmed in their phase banners. Alias guard live on **both**
phases (`Reference sector 0 captured at 1_988 kHz; shift-distinguishable; paths
agree`), so these Path-B columns are trustworthy in the post-6c sense.

**Path B moved a full hp step on both sockets. That is the fix working.**

| socket | Path A boundary | Path B — 6c (pre-fix) | **Path B — 8b** |
|---|---|---|---|
| Edge `$0000_01C7` | 43.75 MHz | 29.166 MHz | **35.0 MHz** |
| Adapter `$0000_01C9` | 35.0 MHz | 29.166 MHz | **35.0 MHz** |

Every cell at or below 25 MHz is clean on both sockets, both modes, both paths —
unchanged from every prior round. The overspeed knob works: cells above 25 MHz
still swept, reaching 43.75 MHz, so `debugSetOverspeedAllowed()` is doing its job
for the diagnostics.

### The one remaining Path-B failure is the one cell the campaign never characterised

Edge Path B fails **only** at hp=4 / 43.75 MHz — `2 0 0`, `status=-4` on both
reads, in both sampling modes. That is precisely the floor cell where
`effectiveAlignDelay()` deliberately withholds the +5 offset and reverts to the
historical `align = hp`. The bands behind the `hp + 5` recommendation were
measured at hp 5, 6 and 7 only.

So the read path is now clean everywhere the campaign actually measured, and
fails only where it did not. **Closing that cell needs a characterisation run at
hp=4, not another fix attempt** — the same conclusion the brief reached
independently when it named hp=4 as the next suspect.

### The adapter cmd cliff is unchanged, and still socket-bound

Path A: Edge 43.75 MHz vs adapter 35.0 MHz. The adapter's hp=4 failures are
`status=-3` on Path A and `-1`/`-3` on Path B — the same signature as rounds 1–2.
Its reappearance in this session is a useful same-session control: the instrument
still sees the known cliff, so 8b's improvements are not an instrument that went
blind.

## What Round 8 settles, and what it does not

**Settles:** the mitigation bundle — all five items, including the two added
between attempts — is certified on hardware at full regression scope. The read
default `align_delay_offset = hp + 5` is now not only band-supported but
*demonstrated*, with the Path-B boundary movement as its visible proof.

**Does not settle:** the `tx_align_delay` write-path release-gate item from Round
7b is untouched by this round. 8b is read-only and 8a runs at 25 MHz, where the
pad is safe on all five surveyed cards. **That decision is still open and still
user-affecting.**

---

# Hand-back — consolidated, all rounds

> 🔑 **ROUND 15 — ROOT CAUSE IDENTIFIED (2026-08-19).** The #3240 wedge is caused
> by **boot-time SD access**, not by anything the driver does. With it disabled,
> **4 warm runs came back clean across 2 power cycles**; re-enabling it brought the
> wedge back immediately — **toggle proven in both directions on one card in one
> session**. This resolves the standing paradox (a reset was necessary yet both of
> its card-visible effects were refuted — the third thing a reset does is run the
> boot ROM) and explains why round 14a found no recovery: the card is wedged
> before our first instruction runs. ⚠ **Not yet attributed** — `P59 = up`
> disables flash boot AND SD boot, and this board runs a flash program each reset;
> the discriminator is P61 up + P59 float.
> 🔑 **15b: CMD12 QUIESCE WORKS — a shippable fix**, proven in 2 pairs (5 clean
> runs, 2 power cycles) each with a same-session control that wedged. Default OFF;
> enabling it is a container-side call that now rests on controlled evidence.
> See the Round 15 section at the end.
>
> ✅ **ROUND 14 COMPLETE (2026-08-19)** — 🔑 **`initCardOnly()` ALONE arms the
> wedge** (control clean, size-matched): the filesystem layer is exonerated and
> the search collapses to CMD0/CMD8/ACMD41/CMD58. ⛔ **A wedged card is NOT
> recoverable without removing power** — five rungs incl. 102_400 clocks in both
> CS polarities, all `-8`; **v1.7.1 is not unblocked by recovery**. Floating the
> pins **after** a driver session is also clean (8/8), closing the ordering
> qualification round 13 left open. The paradox sharpens: a reset is necessary,
> but both of its card-visible effects are now refuted.
> See the Round 14 section at the end.
>
> ✅ **ROUND 13 COMPLETE (2026-08-19)** — the wedge condition is now tightly
> bounded: **a driver session that touches the pins (reads suffice, writes are
> unnecessary), then a P2 reset, then another driver session**; the state is
> **latched in the controller** and cleared only by removing power. Eliminated:
> the reset alone (a larger null binary is clean 2/2), time-based recovery (120 s
> powered idle still wedges — the GC-completes model is refuted), and filesystem
> state (read-only predecessor with FSInfo suppressed still wedges).
> One gap remains: in-binary cycles stay clean while reset-separated sessions
> wedge, with reads in both.
> See the Round 13 section at the end.
>
> ✅ **ROUND 12 COMPLETE (2026-08-19)** — 🔑 **the wedge is now a switch**: cold
> (first binary after power-on) is clean 4/4, warm is wedged 2/2, cleared only by
> power — a deterministic reproducer for #3240 at last, and the bad-pin prefix is
> positively eliminated. 🔑 **the hp=4 exemption is LOAD-BEARING**: measured inside
> real high-speed mode the band is `[-3..4]` centre 0 on two cards, so the shipped
> `+5` is **outside** it — **round 9's item 3 is REVERSED**. hp=4 write teeth hold
> across three cards with **pad 4 passing on all**. Two bench fixes to the
> `SPI_43M_HS` arm, which could never have worked as delivered.
> See the Round 12 section at the end.
>
> ✅ **ROUND 11 COMPLETE (2026-08-18)** — **11c mapped the hp=4 write cell at last**:
> not a band but periodic teeth at ≡ 2 (mod 4), and **the shipped default pad 4
> PASSES**, so the pad is not the cause and high speed is correctness-clear.
> 11b: the write regression is **SLOW, not corrupt** (12/12 verifies match), and
> round 10's PNY regression is **corrected — it was card variance**. 11a: the
> rebuilt probe is **still 8/8 clean** while the suite pair wedges the same card,
> so the gate failed and the ladder was not run. ⚠ The corruption is
> **bit-smearing (`exp | exp>>1`), not a one-bit shift**.
> See the Round 11 section at the end.
>
> ✅ **ROUND 10 COMPLETE (2026-08-18)** — 10b: the 75% clock increase gives
> **+47% reads on all three cards but REGRESSES writes on two of three** (worst
> −64%), and 43.75 MHz is hp=4, the one cell whose *write* pad was never
> characterised. 10c: the new wedge probe is **8/8 clean on Edge** while the 9a
> suite pair still wedges the same card minutes later — the probe does not
> reproduce, so the ladder is stopped at step 2. 10a: the Kingston 2GB is dead
> (no init in either socket, runs hot), so its scope question is unanswered.
> ⚠ **Round 9's `-7` unmount finding is CORRECTED — it is intermittent.**
> See the Round 10 section at the end.
>
> ✅ **ROUND 9 COMPLETE (2026-08-18)** — four studies, six cards. +5 is universal
> across four controller families; the hp=4 floor cell has a real band `[2..8]`
> centered +5; three of four modern cards negotiate CMD6 high speed at 43.75 MHz
> (falsifying `SD-CARD-PERFORMANCE.md` §7); a 119GB/64-spc geometry certifies
> 532/532; the asdfg Edge wedge is unchanged. One bench test-source fix (one
> line) and one unrealized 75% speed opportunity are the hand-back's live items.
> See the Round 9 section at the end.
>
> ✅ **ROUND 8 GREEN — the mitigation bundle IS certified (2026-08-18).**
> 8a full regression: **530 pass / 0 fail, 27 suites**, closing audit clean.
> 8b socket shmoo: Path B improved **29.166 → 35.0 MHz on both sockets**, the
> `hp + 5` default demonstrated rather than merely band-supported. Both earlier
> 8a reds were real driver defects and are fixed. See the Round 8 section.
>
> The two superseded 8a sections below are kept as the defect record — they are
> how the stranded-high-speed-mode bug was found. Read them as history, not as
> current state.

**Every planned test in the brief has been run — rounds 1 through 8.** Rounds 1,
2, 2b, 3, 4, 5a/b/c, 6a/b/c/d, 7a/b/c/d and 8a/8b, plus the Step-A regression
re-certification. ~45 runs across five distinct cards (plus the asdfg pair) and
both sockets. No wedge, no run aborted, no card lost. **Bench scope is CLOSED,
and the tree is certified.**

**Both round-4/5 blockers are now RESOLVED on hardware by round 6:**

- ✅ **The shmoo/phase-sweep conflict is closed.** Cause was reference-content
  aliasing; with the alias guard live, Edge Path B fails at 35 MHz and the two
  instruments agree (6c). The phase sweep was right throughout. **Retroactive
  consequence: every pre-6c Gigastone shmoo Path-B "clean" column is unreliable.
  Path A and cmd-cliff results stand.**
- ✅ **The write probe's failure detection is proven** (6a) — the ~336 green cells
  of round 5 are now evidence, and the write path's total lack of pad sensitivity
  is a real result rather than a blind instrument.

**One new item takes their place — now fully characterised, and it is the
campaign's most consequential result:**

- ⚠ **`tx_align_delay = 4` lands on a driver-side losing phase at hp=5 / 35 MHz,
  on three of five cards tested.** Silent whole-sector write corruption. The
  mechanism is driver-side, not card-specific — every affected card fails at
  identical pads. It is bounded by the fact that all cards measured declare
  `TRAN_SPEED = 25 MHz`, where the default is safe; but the driver permits
  35 MHz and nothing in code enforces that bound. **Release-gate punch-list item
  with three options — see Round 7b.**

## Established

1. **The adapter socket costs real margin, and it is the socket.** The
   43.75 MHz / 2-of-8 / `status=-3` command cliff appeared on **four cards across
   two unrelated families** (Gigastone SDHC ×2, Cloudisk asdfg SDSC, Lerdisk
   asdfg SDSC), and the Gigastone 2×2 swap put the card term at zero.
2. **The adapter cliff is bracketed to 36.25 MHz clean / 37.50 MHz broken** by the
   sysclk ladder. Sharp — no degraded cell between.
3. **The Edge boundary is still unmeasured** — censored by the hp ≥ 4 clamp in
   `applySPISpeed`. Standing figure: **delta ≥ 6.25 MHz (≥ ~17%)**, true magnitude
   unknown.
4. **Failures are `status=-3` (E_BAD_RESPONSE), not `-1`** — the card answers and
   the answer arrives garbled. Return path, not outbound. Mode-invariance says the
   suspect is the MISO path itself, not the sampling point.
5. **The Lerdisk's streamer corruption is a card property**, not a socket one, and
   the adapter makes it *worse* (onset 35.0 → 29.17 MHz).
6. **The catalog's Edge-FAIL / External-PASS inversion does not exist in the read
   path.** It looks confined to write/commit, which this tool cannot see.
7. **The socket delay is measured: exactly one sysclk tick (~2.86 ns at
   350 MHz)** — same card, same frequency, Path B align-delay passing band
   `[0..8]` on Edge vs `[1..8]` on the adapter. Tier 1 tooling produced the number
   Tier 2 was designed for.
8. **The Lerdisk's corruption is a one-bit right shift of the entire stream**,
   confirmed over all 512 bytes, and it is cured by any positive align-delay
   offset. The driver's default offset of 0 is what puts it outside the passing
   band.

## The two driver defaults — current recommendations

These are separate knobs and separate decisions. Do not justify one with the
other's evidence.

**`align_delay_offset` — the READ path. `hp + 5` — SHIPPED AND CERTIFIED (round 8).**
Bands are now fully closed (round 4 top-finding + 7c). Every measured arm centres
on 5 — five arms, two card families, both sockets, three frequencies. Narrowest
band is `[1..9]`. `hp + 5` sits mid-band in all of them; today's `hp + 0` sits on
or outside the lower edge at 35 MHz, and the earlier `hp + 2` candidate sits one
tick from an edge. This recommendation was acted on, and round 8 certified it: 530/0 regression,
and 8b shows the Path-B boundary moving 29.166 → 35.0 MHz on both sockets. The
one cell still failing (hp=4, where the offset is withheld by design) was never
characterised and needs a measurement run, not a fix. **No decision outstanding
on this knob.**

**`tx_align_delay` — the WRITE path. Currently 4. Needs a release-gate decision.**
Safe at 25 MHz on all five cards surveyed (band `2..7`). Lands **on** the
driver-side losing phase at hp=5 / 35 MHz, causing silent whole-sector corruption
on three of the five. Options and their trade-offs are in Round 7b.

## Decisions needed from Stephen

- **The `tx_align_delay` release-gate call** — clamp/warn above declared
  `TRAN_SPEED`, make the pad frequency-aware, or document and accept. This is the
  one open user-affecting item from the campaign.
- **Whether to push the Edge cmd ceiling past 360 MHz.** 7d ran at the approved
  360 and Edge still passed at 45.0 MHz, so the ceiling remains unmeasured. By
  the brief's own rule the map closes at "Edge ≥ 45.0, socket delta ≥ 7.5 MHz"
  unless a higher overclock is approved.

## Container-side work items

- **Catalog two cards.** (1) Second Cloudisk 2GB, `PSN $0001_9B39`, mfg 2025/11,
  CID in the round-2b section — note it scored *real* data CRC while its
  documented `CW_NO_DATA_CRC` family-mate did not, which bears on
  `DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md`. (2) Record the
  label-vs-silicon mismatches: the "Gigastone 32GB" pair reports as **Transcend**
  (MID `$74`), "WD Purple" reports as **SanDisk WX64G**. Records keyed by label
  will otherwise mislead.
- **Aim the adapter investigation at R1-response read timing margin.** Multiple
  sysclks of cmd-only failures with zero crc and zero data errors is a specific
  finger-point, and the adapter's cost is now quantified at exactly one tick.
- **Add a drain delay to `SD_write_probe`.** Its final debug line is truncated at
  `END_SESSION` (`5 12 PAS`) — the known `waitms(500)` fix, seen on every run.
- **The hp=4 floor cell is the campaign's one uncharacterised cell.** Both the
  read offset (withheld there by `effectiveAlignDelay()`) and the tx pad were
  measured only at hp 5/6/7 and 14. It is the sole remaining Path-B failure in
  8b, and it is also where verified CMD6 high speed lands at 350 MHz sysclk. If
  a decision ever needs that cell, say so and the bench will characterise it —
  it is a measurement run, not a fix.
- **Consider re-running the one marginal cell** (7d, adapter, 30.0 MHz, PRE,
  Path B, 1 error of 8) — the only partial result in the entire campaign.

### Resolved during the campaign — no action needed

- ~~Shmoo/phase-sweep Path B conflict~~ → reference-content aliasing, fixed and
  confirmed (6c).
- ~~Write probe's failure detection unproven~~ → proven synthetically (6a) and
  against a real defect (7a).
- ~~Shmoo scoring defects (dummy-CRC totals, `none clean`)~~ → fixed, confirmed
  (6c).
- ~~One-bit-shift reading unconfirmed~~ → confirmed over all 512 bytes (R3b).
- ~~Write-capable probe not built~~ → built and run across rounds 5–7.
- ~~`tx_align_delay` justification is sample-size-one~~ → now five cards; the
  mechanism is driver-side, not card-specific.

## Full log inventory (`tools/logs/`)

| Log | What |
|---|---|
| `SD_socket_shmoo_260817-142540.log` | R1, Gigastone, unmarked@Edge |
| `SD_socket_shmoo_260817-142607.log` | R1 confirm, identical |
| `SD_socket_shmoo_260817-142854.log` | R1 swapped — proves socket effect |
| `SD_socket_shmoo_260817-150723.log` | ladder 290 MHz (36.25) — adapter clean |
| `SD_socket_shmoo_260817-150735.log` | ladder 300 MHz (37.50) — adapter fails |
| `SD_socket_shmoo_260817-150747.log` | ladder 320 MHz (40.00) |
| `SD_socket_shmoo_260817-150758.log` | ladder 336 MHz (42.00) |
| `SD_socket_shmoo_260817-151209.log` | R2b, Lerdisk@Edge |
| `SD_socket_shmoo_260817-151731.log` | R2b swapped — reverses the run-1 reading |
| `SD_phase_sweep_test_260817-160225.log` | R3a adapter, Lerdisk, 29.17 MHz — band `[1..8]` |
| `SD_phase_sweep_test_260817-160509.log` | R3a Edge, Lerdisk, 35.0 MHz — band `[1..8]` |
| `SD_phase_sweep_test_260817-160545.log` | **R3a Edge, Lerdisk, 29.17 MHz — band `[0..8]`; the 1-tick measurement** |
| `SD_socket_shmoo_260817-160608.log` | R3b fixed scoring + full dump (`grep -a`) |
| `regression_260817_clamp_recert.log` | Step A — 27 suites, 530 tests, 0 fail |
| `SD_phase_sweep_test_260817-171629/171642/171653/171704.log` | R4 band-top, 4 arms |
| `SD_write_probe_260817-172000.log` | R5a healthy pair — all PASS |
| `SD_write_probe_260817-173707.log` | R5b asdfg pair — all PASS |
| `SD_write_probe_260817-173740/173801/173820.log` | R5c wedge zone 12.5 / 25 / 35 MHz — no wedge |
| `SD_write_probe_260817-182529.log` | R6a selftest — detection PROVEN |
| `SD_write_probe_260817-182552.log` | R6b Edge+CMD24 on `$01C7` — all PASS (no tooth) |
| `SD_tx_phase_shmoo_260817-182659.log` | R6d same card, original instrument — band 2..30 |
| `SD_socket_shmoo_260817-182837.log` | R6c alias guard live — Edge Path B now fails at 35 MHz |
| `SD_socket_shmoo_260817-185505.log` | R7d 360 MHz overclock — Edge clean at 45.0 MHz |
| `SD_tx_phase_shmoo_260817-190157.log` | **R7a Card 2b `$0F14` — tooth reproduces 8/15/22/29** |
| `SD_write_probe_260817-190217.log` | **R7a Card 2b — pad 4 fails at hp=5** (confirmed on re-run 190849) |
| `SD_phase_sweep_test_260817-19xxxx.log` | R7c Lerdisk read band `[0..11]` |
| `SD_write_probe` + `SD_tx_phase_shmoo` 7b runs | `$A345_3C0E` tooth, `$3449_0F1E` none, `$EEBA_D6C0` tooth |
| `SD_card_identify_260817-*.log` | per-card identity + `TRAN_SPEED` verification |
| `regression_260818_round8a_run3.log` | **R8a run 3 — 27 suites, 530 tests, 0 fail; bundle CERTIFIED** |
| `SD_RT_speed_tests_260818-125535.log` | R8a run 3 — #8/#9/#12 all green; `isHSActive` agrees at 43.75 MHz |
| `SD_socket_shmoo_260818-130306.log` | **R8b — Path B 29.166 → 35.0 MHz both sockets; only hp=4 floor cell fails** |
| `SD_RT_mount_tests_260818-135524.log` + `..._raw_sector_tests_260818-135535.log` | R9a Lerdisk Edge — wedge reproduces, `unmount()` `-7` |
| `SD_RT_mount_tests_260818-135744.log` + `..._raw_sector_tests_260818-135746.log` | R9a Cloudisk Edge — identical to Lerdisk |
| `SD_phase_sweep_test_260818-140028/-140243/-140434/-140622.log` | **R9b bands @25 MHz — all four cards center +5** |
| `SD_phase_sweep_test_260818-140042/-140245/-140436/-140624.log` | **R9c hp=4 floor cell — `[2..8]` center +5 on 3 of 4** |
| `SD_RT_speed_tests_260818-140709.log` | R9d PNY pre-fix 16/17 — the Test #17 precondition defect |
| `SD_RT_speed_tests_260818-141955.log` | R9d PNY post-fix **17/17** — one-line fix verified |
| `SD_RT_speed_tests_260818-142251/-142420/-142522.log` | R9d SanDisk (declines) / Samsung / Lexar (both 43.75 MHz) |
| `SD_RT_speed_tests_260818-142720/-142856.log` | R9d asdfg pair on adapter — decline + contradictory getter pair |
| `regression_260818_round9e_samsung128.log` | **R9e Samsung 128GB — 25 suites 440/0; two suites timed out** |
| `SD_RT_mount_tests_260818-145827.log` + `SD_RT_read_write_tests_260818-150012.log` | **R9e completing re-runs — 43/0 and 49/0, total 532/532** |
| `SD_card_identify_260818-155532.log` + `SD_card_characterize_260818-*` | R10a Kingston 2GB — no init either socket, card dead |
| `SD_performance_benchmark_260818-160431/-160529.log` | **R10b Samsung — HS: +42% large reads, −55% 1-sector write** |
| `SD_performance_benchmark_260818-161433/-161452.log` | **R10b Lexar — HS: gains on all 15 measurements, to +47%** |
| `SD_performance_benchmark_260818-161756/-161826.log` | **R10b PNY — HS: +47% reads, −64% / −60% writes** |
| `SD_edge_wedge_probe_260818-162159.log` | R10c step 1 CONTROL, adapter — 8/8 clean |
| `SD_edge_wedge_probe_260818-162425.log` | **R10c step 2, EDGE — 8/8 CLEAN; probe does not reproduce** |
| `SD_RT_mount_tests_260818-162715.log` + `SD_RT_raw_sector_tests_260818-162718.log` | **R10c control — 9a pair still wedges same card; unmount `0` this time** |
| `SD_edge_wedge_probe_260818-174340.log` | **R11a rebuilt probe, EDGE — 8/8 CLEAN; gate FAILED** |
| `SD_RT_mount_tests_260818-174421.log` + `SD_RT_raw_sector_tests_260818-174423.log` | R11a control — suite pair wedges same card 40 s later |
| `SD_performance_benchmark_260818-175602/-175644.log` | R11b Samsung — regression reproduces (−52%), all verifies match |
| `SD_performance_benchmark_260818-180316/-180336.log` | R11b Lexar — gains everywhere, all verifies match |
| `SD_performance_benchmark_260818-181751/-181822.log` | **R11b PNY — regression NOT reproducible; std arm varies 3x** |
| `SD_write_probe_260818-182055.log` (+3 identical repeats) | **R11c hp=4 write teeth ≡ 2 (mod 4); default pad 4 PASSES** |
| `SD_RT_mount_tests_260818-184339/-184420/-184503/-184949.log` | **R12a COLD — 43/43 clean, four times** |
| `SD_RT_mount_tests_260818-184534/-185003.log` | **R12a WARM — 19/24 wedged, both times** |
| `SD_write_probe_260818-1851*/-1853*.log` | R12c Lexar (no tooth) + PNY (≡ 2 mod 4); pad 4 PASS on both |
| `SD_phase_sweep_test_260818-185537/-185616.log` | R12d PNY in HS mode — band `[-1..5]` centre +2 |
| `SD_phase_sweep_test_260818-190333/-190346.log` | **R12d Lexar in HS mode — `[-3..4]` centre 0; `+5` OUTSIDE** |
| `SD_phase_sweep_test_260818-190607/-190610.log` | **R12d Samsung in HS mode — `[-3..4]` centre 0; `+5` OUTSIDE** |
| `SD_RT_mount_tests_260818-192229/-194244.log` | **R13a after null predecessor — CLEAN 2/2; reset eliminated** |
| `SD_null_predecessor_260818-200349.log` | R13b the P2-timed 120 s hold, transcript-confirmed |
| `SD_RT_mount_tests_260818-200403.log` | **R13b WEDGED after 120 s idle — state is latched** |
| `SD_edge_wedge_probe_260818-2142*.log` + `SD_RT_mount_tests_260818-214314.log` | **R13c read-only predecessor still WEDGES — writes irrelevant** |
| `SD_edge_wedge_probe_260818-231037.log` | **R14a RECOVERY ladder — all 5 rungs `-8`; not recoverable without power** |
| `SD_wedge_predecessor` `P_INIT` + `SD_RT_mount_tests_260818-231212.log` | **R14b `initCardOnly()` alone WEDGES — filesystem exonerated** |
| `SD_wedge_predecessor` `P_NOTHING` + `SD_RT_mount_tests_260818-231838.log` | R14b control — CLEAN 43/43 |
| `SD_edge_wedge_probe_260818-231954.log` | **R14c FLOAT_BETWEEN — 8/8 clean; float-after-session refuted** |
| `SD_null_predecessor_260819-013648.log` | R15a switch-state check — flash banner ABSENT, boot-time access off |
| `SD_RT_mount_tests_260819-013742/-013752/-014017/-014028.log` (+ a 3rd warm) | **R15a SD boot OFF — 43/43 CLEAN warm, 4 runs, 2 power cycles** |
| `SD_RT_mount_tests_260819-014205.log` | R15a switches restored — flash banner PRESENT, cold clean |
| `SD_RT_mount_tests_260819-014222.log` | **R15a switches restored — WEDGE RETURNS 19/24, `-7`/`-8`** |
| `SD_RT_mount_tests_260819-015035/-015053.log` | **R15b pair 1 quiesce — cold + warm CLEAN, SD boot enabled** |
| `SD_RT_mount_tests_260819-015120.log` | **R15b pair 1 CONTROL — unmodified warm WEDGED same session** |
| `SD_RT_mount_tests_260819-015220/-015230/-015241.log` | **R15b pair 2 quiesce — 3 runs CLEAN** |
| `SD_RT_mount_tests_260819-015257.log` | **R15b pair 2 CONTROL — unmodified warm WEDGED** |

---

# Round 9 — hardware-understanding studies (run 2026-08-18)

Six cards, four studies, all run on the shared tree as it stood at 13:41–13:48.
Every card seat was verified with `SD_card_identify` before its study; the PSN in
each transcript is the proof of which card ran.

**⚠ One test-source change was made at the bench during this round** — a missing
precondition in the brand-new Test #17. Details in the 9d section below; it is
one line, and it is the only edit the bench made to the tree.

## Card roster as actually identified

The labels in the brief and the silicon do not always agree; these are the
identify-line facts, and they are what the results below key off.

| Label | Identify line | PSN | Warnings |
|---|---|---|---|
| SanDisk MAX Endurance 32GB | `SanDisk SH32G SDHC 29GB SD 6.x rev8.0` | `$5BFE_CCD8` | `$02` |
| Samsung EVO Select 128GB | `Samsung GD4QT SDXC 119GB SD 3.x rev3.0` | `$4AC8_5F42` | `$00` |
| Lexar 64GB red | `Longsys/Lexar MSSD0 SDXC 58GB SD 6.x rev6.1` | `$3354_9024` | `$00` |
| PNY 16GB | `Phison SD16G SDHC 14GB SD 3.x rev3.0` | `$01CD_5CF5` | `$00` |
| Cloudisk 2GB | `Unknown asdfg SDSC 1GB SD 1.x rev2.2` | `$0000_1680` | `$04` |
| Lerdisk 1GB | `Unknown asdfg SDSC 960MB SD 1.x rev2.2` | `$0000_01F4` | `$04` |

## 9a — the asdfg Edge wedge is UNCHANGED by the mitigation bundle

Answer: **still wedges.** The catalog's External-only guidance for both cards
stands, and read alignment is not implicated in a defect filed on the write path.

Both cards, Edge socket, the recorded minimal reproducer (`mount_tests` then
`raw_sector_tests`, no power cycle between):

| | Lerdisk `$0000_01F4` | Cloudisk `$0000_1680` |
|---|---|---|
| `mount_tests` | 19 pass / 24 fail | 19 pass / 24 fail |
| Tests #1–12 (first mount + ops) | pass | pass |
| **#13 `unmount()`** | **`-7`** after ~4 s stall | **`-7`** |
| #15 `mount()` #2 | `-8` E_NO_CARD | `-8` |
| `raw_sector_tests` after | 0/1, `ERROR: Card init failed!` | 0/1, same |

`DIAG2: error()=-8, lastCMD13=$0, lastCMD13Error=$0, CRC match=0 mismatch=0 retry=0`
on both.

**The twins are indistinguishable** — identical counts, identical codes,
identical failure point. That is stronger evidence for the silicon-twin record
than anything currently in the catalog.

**One delta from the record — ⚠ CORRECTED in round 10c: it is INTERMITTENT, not
a stable change.** The #3240 record has `unmount()` returning **0** with the
failure surfacing at mount #2. Both 9a runs instead returned **`-7`** at unmount
after a ~4 s stall, one test earlier. **A third run of the same pair, on the same
card and socket, later the same day (10c) returned `0` instantly** — the record's
original behaviour. So `unmount()` on a wedging asdfg card returns `-7`
*sometimes* and `0` *sometimes*; the wedge itself (mount #2 `-8`, raw init
failure) is invariant across all three runs.

This still bears on todo #3265 — but as evidence the failure is intermittent at
the unmount step, NOT as a free discriminator that removes the need for the
instrumentation. #3265 should still be built; it now also needs to run enough
repetitions to catch both outcomes.

Logs: `SD_RT_mount_tests_260818-135524.log`, `SD_RT_raw_sector_tests_260818-135535.log`
(Lerdisk); `SD_RT_mount_tests_260818-135744.log`, `SD_RT_raw_sector_tests_260818-135746.log`
(Cloudisk).

## 9b — the `+5` align default is UNIVERSAL, not vendor-dependent

Answer: **every controller centers at +5.** Four families, none of them among the
two that produced the default. No card centers at +2 or +9 — the headline result
9b was watching for did not occur.

| Card | Controller | Band @25 MHz (both sample modes) | Center |
|---|---|---|---|
| SanDisk `$5BFE_CCD8` | SanDisk `$03` | `[-1..12]` width 14 | **5** |
| Samsung `$4AC8_5F42` | Samsung `$1B` | `[-1..11]` width 13 | **5** |
| Lexar `$3354_9024` | Longsys `$AD` | `[-1..11]` width 13 | **5** |
| PNY `$01CD_5CF5` | Phison `$27` | `[-1..11]` width 13 | **5** |

Pre-edge and on-edge modes gave identical bands on every card. The single global
default is well supported; per-vendor calibration is not indicated.

Logs: `SD_phase_sweep_test_260818-140028 / -140243 / -140434 / -140622.log`.

## 9c — the hp=4 floor cell HAS a band, and it centers at +5 too

Answer: **`[2..8]`, width 7, center +5** on three of four cards. The exemption
rests on ignorance that no longer exists.

| Card | hp=4 Path A | hp=4 Path B band |
|---|---|---|
| SanDisk `$5BFE_CCD8` | **FAIL** | none — every offset `-3..+16` fails, both modes |
| Samsung `$4AC8_5F42` | PASS | `[2..8]` width 7, center **5** |
| Lexar `$3354_9024` | PASS | `[2..8]` width 7, center **5** |
| PNY `$01CD_5CF5` | PASS | `[2..8]` width 7, center **5** |

Banner `FLOOR-CELL ARM: hp=4 rule LIFTED for measurement (production keeps it)`
confirmed present on every 9c run.

**The SanDisk's all-FAIL is a cell failure, not an alignment failure.** Path A is
the byte-by-byte smart-pin read and has nothing to do with streamer alignment;
its failure means the card cannot complete a basic read at 43.75 MHz at all, so
the offset sweep ran downstream of an already-broken cell. **9d corroborates this
independently: the same card is the one card that DECLINES CMD6 high speed.** Two
unrelated instruments, same conclusion about the same silicon.

**Consequence for the production exemption, stated as evidence not as a
recommendation.** The floor rule withholds +5 at hp=4 and falls back to
`align = hp = 4`. On all three cards with a band, **both values are inside
`[2..8]` — but +5 is dead center and 4 is one tick off it**, so the exemption
does not protect anything; it trades the measured center for a nearer-edge value.
The band is also half the width of the 25 MHz band (7 vs 13), so there is less
room for marginal silicon. Deleting or keeping the exemption is a container-side
call; this is the measurement it was waiting on.

Logs: `SD_phase_sweep_test_260818-140042 / -140245 / -140436 / -140624.log`.

### ⚠ CONTAINER-SIDE CORRECTION to the 9c consequence (2026-08-18)

*The measurement above is correct and verified against all four logs. The
consequence drawn from it is not, in two independent ways.*

**1. Offset and align value are not the same axis.** The floor rule produces
`align = hp = 4`. In the sweep's coordinates `align = 4 + offset`, so the
exemption is **offset 0**, not offset 4. Offset 0 **FAILS on all four cards, in
both sample modes** — verified in every 9c log. So the exemption does not "trade
the center for a nearer-edge value inside the band"; in this measured condition
it produces a configuration that fails outright.

**2. But the sweep measured the wrong card state, so neither reading transfers.**
`SD_phase_sweep_test` runs `initCardOnly()` then `setSPISpeed(43_750_000)` with
the speed bound lifted — that is **default speed mode driven above spec**. It
never calls `attemptHighSpeed()`. In production, hp=4 arises *only* inside
**verified CMD6 high-speed mode**, where the card's own output timing is
different by definition. And there the exemption demonstrably works: the CMD6
verify read at 43.75 MHz with `align = 4` active has passed in every green
`SD_RT_speed_tests` run.

**Conclusion: 9c does NOT authorize deleting the hp=4 exemption, and does not
establish that it is needed either.** It answers a question about above-spec
default-mode operation, which is exactly the regime the production clamp exists
to prevent. Deciding the exemption requires a phase sweep taken *inside* verified
high-speed mode at hp=4 — a new instrument arm, not a re-reading of these logs.

**The finding underneath this is real and worth keeping:** the optimal read
alignment at 43.75 MHz differs between default mode and high-speed mode on the
same silicon. That is physically sensible and it is the second time this
default-mode-vs-HS-mode distinction has been needed to read an hp=4 result
correctly (the first was round 8b's Edge `ON-B 254` cell). Any future hp=4
measurement must state which mode it was taken in.

## 9d — CMD6 high speed: three of four modern cards take it and hold it

Answer: **`SD-CARD-PERFORMANCE.md` §7 is decisively falsified.** It says high
speed "fails on all tested cards."

| Card | Controller | CMD6 | HS cap | Outcome | Suite |
|---|---|---|---|---|---|
| PNY 16GB | Phison `$27` | `-1` | `-1` | **25 → 43_750_000 Hz** | 17/17 |
| SanDisk 32GB | SanDisk `$03` | `-1` | `0` | declines cleanly, 25 MHz | 17/17 |
| Samsung 128GB | Samsung `$1B` | `-1` | `-1` | **25 → 43_750_000 Hz** | 17/17 |
| Lexar 64GB | Longsys `$AD` | `-1` | `-1` | **25 → 43_750_000 Hz** | 17/17 |
| Lerdisk 1GB (adapter) | asdfg `$05` | **`0`** ⚠ | **`-1`** ⚠ | declines, 21.875 MHz | 17/17 |
| Cloudisk 2GB (adapter) | asdfg `$05` | **`0`** ⚠ | **`-1`** ⚠ | declines, 21.875 MHz | 17/17 |

All six ran 17/17 with the precondition fix in place. Cards 5–6 ran on the
**external adapter**, per the brief's conditional, because 9a showed the Edge
wedge is still live. Every decline had `ERROR(): 0` — the card was asked and said
no, as distinct from the query failing. Both mode-exit tests passed on the
counterfeits, so there are no card-specific reds to record there.

### ⚠ The asdfg pair reports a contradictory getter pair

Both counterfeits report `checkCMD6Support() = 0` (does NOT support CMD6) while
`checkHighSpeedCapability() = -1` (claims high-speed capable). Those cannot both
be true: high-speed capability is discovered *through* CMD6. Compare the SanDisk,
which reports the coherent opposite pairing (`-1 / 0` — supports the command,
declines the mode).

Behavior is safe: `attemptHighSpeed()` correctly returns 0 and nothing switches.
But one of the two getters is answering from something other than a real
negotiation. **This is the first time either getter has been exercised on a card
that genuinely lacks the feature**, and it reproduces identically on both twins,
so it is a class property of the counterfeit silicon rather than a one-card
fluke. Whether `checkHighSpeedCapability()` should be gated on
`checkCMD6Support()` is a driver-contract question for the container side.
Belongs in `COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md` alongside `CW_NO_DATA_CRC`.

### ⚠ BENCH TREE CHANGE — Test #17 precondition (one line)

`SD_RT_speed_tests.spin2:391`, added before the `createFileNew`:

```spin2
sd.deleteFile(@spTestFile3)   ' Test #12 left this file behind; createFileNew would return E_FILE_EXISTS
```

**What happened.** Test #17 called `createFileNew(@spTestFile3)` with no
preceding delete, unlike every sibling creation site in the same file (lines 161,
238, 304 all delete first). `spTestFile3` is created at line 305 by Test #12 and
not removed until cleanup at line 406, so `createFileNew` correctly returned
**`-41` E_FILE_EXISTS** and the test failed 16/17 — on its own precondition, on
its first-ever hardware run.

**Why it mattered more than a lost test.** Test #17's assertion is "the card is
usable after a high-speed unmount → remount." `-41` is *proof that it is* — the
mount succeeded, the directory was read, and the filesystem correctly identified
an existing file. A genuinely stranded high-speed card returns `-7`, as round 8a
run 2 did. The one outcome that would have signalled real trouble is the outcome
this red ruled out, so the red was anti-informative.

**Verified on hardware**, same card, same seating: PNY 16GB `$01CD_5CF5` went
**16/17 → 17/17**. Log of the passing run: `SD_RT_speed_tests_260818-141955.log`.

This restores the brief's staleness tripwire: **9e should read 532/532**, and a
531 now means a genuine red rather than this defect.

This is the same failure mode as commit `c84edb6` ("the new suite's one red was
its own precondition, not the driver") — both times, a brand-new test's first
hardware run. Worth a habit: new tests that create a file should delete it first,
the way the three older sites in this very file already do.

**Not committed.** The tree still carries the container side's uncommitted
v1.7.1 diagnostics work; bundling the bench's one line into that is not the
bench's call.

### ⚠ The unrealized speed opportunity — for container-side planning

9d measures a **75% clock increase as available and entirely unrealized**. Three
of four modern cards negotiate 43.75 MHz and hold it, and nothing in the shipped
driver ever asks:

- `attemptHighSpeed()` has exactly one consumer in the tree — `SD_RT_speed_tests`.
  Nothing in `mount()` or the init path calls it; `hs_mode_active := true` occurs
  in exactly one place (`micro_sd_fat32_fs.spin2:6205`), inside the verified switch.
- **The regression suite will not show better numbers**, and is not the instrument
  that would: every other suite mounts at the probed default and stays there, and
  per-suite elapsed times are dominated by test logic, mount cycles and reformats,
  not throughput.
- **The production speed bound would refuse the clock anyway.** `setSPISpeed()`
  clamps at the card's declared `TRAN_SPEED`, and all six cards declare 25 MHz —
  including the three that just ran at 43.75. The 50 MHz allowance exists only
  while verified high speed is active.
- No benchmark has ever been run against high-speed mode.
  `SD_performance_benchmark`, `SD_speed_characterize` and
  `SD_frequency_characterize` exist in `src/UTILS/` and were not part of round 9.

Stephen's direction (2026-08-18): **the container agent plans what to do about
this.** The bench did not run benchmarks at 43.75 MHz; say the word and it will.
The design question is how a user should reach the mode — mount-time opt-in, a
documented `attemptHighSpeed()` recipe, or leaving it manual — plus what the
speed bound should do for a card whose declared `TRAN_SPEED` understates what it
demonstrably sustains.

Logs: `SD_RT_speed_tests_260818-140709.log` (PNY, pre-fix 16/17),
`-141955` (PNY, post-fix 17/17), `-142251` (SanDisk), `-142420` (Samsung),
`-142522` (Lexar), `-142720` (Lerdisk), `-142856` (Cloudisk).

## 9e — second full regression on a 119GB / 64-sectors-per-cluster card: 532/532

Answer: **the new geometry certifies clean.** Samsung EVO Select 128GB
`$4AC8_5F42` in Edge, formatted by our own formatter as part of the run (the
format step succeeded — the brief's stop-and-report condition did not fire).

**Final: 532 pass / 0 fail, 27 suites, closing audit clean 23/23.**

The number needs one line of explanation, because the single-pass run reported
440 and named two failed suites:

| Suite | Single-pass run | Cause | Re-run with `-t 400` |
|---|---|---|---|
| `SD_RT_mount_tests` | 0/0 **fail** (121s) | hit its **120s** budget at test #29 | **43 / 0** (120s) |
| `SD_RT_read_write_tests` | 0/0 **fail** (91s) | hit its **90s** budget at test #44 | **49 / 0** (105s) |
| other 25 suites | 440 / 0 | — | — |
| **total** | | | **532 / 0** |

**Neither was a test failure — both were timeout-budget exhaustion, and every
assertion passed right up to the cut.** The runner's `NO-SUMMARY => FAIL` rule
did exactly its job: it refused to score silence as success. Worth noting that
this is the rule working as designed on its first encounter with a genuinely
slow card rather than a truncated capture.

### ⚠ The real 9e finding: per-suite timeout budgets are tuned to a 32GB card

`freeSpace()` scans the FAT, and this card's FAT is ~4x larger. One `freeSpace()`
call in `read_write` test #44 took **21 seconds** (14:45:28 -> 14:45:50). The same
suite completes in 50s on the 32GB regression card and needs 105s here; mount
needs 120s against a 120s budget, i.e. it certifies only by a rounding accident.

Budgets in `run_regression.sh` (line 584 onward) that do not clear this geometry:

- `SD_RT_mount_tests.spin2:120` — needs >120, currently passes on the edge
- `SD_RT_read_write_tests.spin2:90` — needs ~105, must rise

Several others ran far longer here than on the 32GB card and are worth checking
against their budgets before this card is used for certification again:
`directory` 60s, `defrag` 74s, `volume` 110s, `error_injection` 88s, closing
audit 135s.

**This is not a driver defect and not a geometry defect** — it is a harness
assumption (that suite runtimes are card-independent) meeting a card 4x larger
than the one the budgets were written against. Container-side call whether to
raise the budgets globally, scale them by card capacity, or designate the 32GB
card as the only certification geometry.

Logs: `regression_260818_round9e_samsung128.log` (the 27-suite pass),
`SD_RT_mount_tests_260818-145827.log` and
`SD_RT_read_write_tests_260818-150012.log` (the two completing re-runs).

# Round 9 — hand-back summary

**All four studies complete, six cards, no card lost, one wedge (expected, on the
card whose wedge was the subject of the study).**

| Study | Question | Answer |
|---|---|---|
| 9a | Did the bundle change the asdfg Edge wedge? | **No — still wedges.** Catalog guidance stands. `unmount()` now reports `-7` where the record has 0 |
| 9b | Is +5 universal or vendor-dependent? | **Universal.** 4 controller families, all center +5 |
| 9c | What is in the hp=4 floor cell? | **A real band, `[2..8]` center +5**, on 3 of 4 cards. The 4th cannot run the cell at all |
| 9d | Which controllers negotiate CMD6 high speed? | **3 of 4 modern cards do**, at 43.75 MHz. `SD-CARD-PERFORMANCE.md` §7 is falsified |
| 9e | Does a 119GB / 64-spc geometry certify? | **Yes, 532/532** — after two timeout budgets are raised |

## Items for the container side, in priority order

1. **The unrealized 75% speed gain** (9d) — Stephen's direction is that the
   container agent plans this. Detail in the 9d section.
2. **`SD-CARD-PERFORMANCE.md` §7 must be corrected** — "fails on all tested
   cards" is false on three of four cards tested today, with transcripts.
3. **The hp=4 production exemption can now be decided** (9c) — ⚠ **REVERSED by
   round 12d: the exemption must STAY.** 9c's band `[2..8]` centre `+5` was
   measured with the clock *set* to 43.75 MHz, leaving the card in default speed
   mode driven above spec. Measured inside real high-speed mode the band is
   `[-3..4]` centre 0 on two of three cards, putting the shipped `+5` **outside**
   it. The exemption's `align = hp` (offset 0) is dead centre on two cards and
   inside on all three.
4. **Two timeout budgets must rise** before a large card is used for
   certification again (9e).
5. **The asdfg contradictory getter pair** (9d) — `checkCMD6Support()=0` with
   `checkHighSpeedCapability()=-1` on both twins. Driver-contract question, and a
   `COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md` entry.
6. **The bench's one-line test fix** (9d) — review and fold into whatever commit
   carries the v1.7.1 diagnostics work. Not committed by the bench.
7. **`unmount()` returning `-7`** on a wedged asdfg card (9a) — ⚠ **CORRECTED by
   10c: intermittent.** Two 9a runs gave `-7` with a ~4 s stall; a third run of
   the same pair on the same card/socket gave `0` instantly. Do NOT treat this as
   a discriminator that closes todo #3265 — build the instrumentation, and run it
   enough times to see both outcomes.

## Bench scope

Round 9 is **COMPLETE**. Nothing in the brief remains unrun. The only bench work
identified but not performed is benchmarking at 43.75 MHz on the three
negotiating cards, which is off-brief and awaits the container side's plan.

---

# Round 10 — performance payoff and the first Edge-wedge answers (run 2026-08-18)

## 10a — the Kingston-labelled 2GB is DEAD; the question it was asked is unanswered

The card **never initializes**, in either socket, on either init path, and it
**runs hot**.

| | Edge | Adapter |
|---|---|---|
| `SD_card_identify` (mount path) | `mount() failed: error -8` | `-8` |
| `SD_card_characterize` (raw, no-mount / `initCardOnly`) | `FATAL: Failed to initialize SD card!` | same |

Reseated once and retried; identical. Because it never returns a CID there is
**no PSN, MID, PNM or CSD version to fingerprint**, so the "is this an existing
catalog row under a different label?" question cannot be answered with this card.
Stephen removed it after the heat was noticed.

**Critically, this yields NO evidence on the question 10a was positioned to
answer.** "Does SDSC silicon fail on Edge generally?" requires a card that
initializes *somewhere*. This one initializes nowhere, so it neither broadens nor
narrows the wedge scope. **10c's scope is therefore unchanged: two asdfg twins,
and the optional third-card confirmation has no third card.** A different
non-asdfg SDSC card (2GB or smaller) would restore the study.

Logs: `SD_card_identify_260818-155532.log`, `SD_card_characterize_260818-*.log`,
plus the two adapter runs at 16:00–16:01.

## 10b — the 75% clock increase: reads gain everywhere, writes regress on 2 of 3 cards

Three cards, each its own control (standard arm then `-D HIGH_SPEED`). All three
negotiated high speed and ran at **43_750 kHz**, banner-confirmed.

### The synthesis

| Card | Reads | Writes |
|---|---|---|
| **Lexar 64GB** `$3354_9024` | gain everywhere, to **+47%** | **gain everywhere, to +44%** |
| **Samsung EVO 128GB** `$4AC8_5F42` | gain on large, **−15%** single-sector | **−55%** 1-sector, **−28%** 8-sector |
| **PNY 16GB** `$01CD_5CF5` | gain everywhere, to **+47%** | **−64%**, **−60%**, −22%, −13% |

**Reads gain on all three cards. Writes regress on two of three.** ⚠ **CORRECTED
in round 11b: only ONE of the two is reproducible.** The Samsung's regression
repeats (−55% then −52%); the **PNY's does not** — its 25 MHz write numbers moved
by up to 3x between runs and the regression inverted into a small gain, so it is
card variance, not a high-speed effect. The correct statement is **one of three
confirmed, one refuted as noise, one clean**. See round 11b.

### Per-card detail

**Samsung EVO Select 128GB** (`-160431` standard / `-160529` HS):

| Traffic | 25 MHz | 43.75 MHz | Δ |
|---|---|---|---|
| raw read 1 sector | 749 | 640 | **−15%** |
| raw write 1 sector | 385 | 175 | **−55%** |
| raw read 64 sectors | 2_273 | 3_230 | +42% |
| raw write 8 sectors | 1_428 | 1_031 | **−28%** |
| raw write 64 sectors | 2_135 | 2_962 | +39% |
| file read 32KB | 897 | 751 | **−16%** |
| file read 256KB | 765 | 903 | +18% |

**Lexar 64GB** (`-161433` / `-161452`) — all 15 measurements improved:

| Traffic | 25 MHz | 43.75 MHz | Δ |
|---|---|---|---|
| raw read 1 sector | 925 | 1_082 | +17% |
| raw read 64 sectors | 2_295 | **3_372** | **+47%** |
| raw write 64 sectors | 2_172 | 3_119 | +44% |
| file read 256KB | 1_192 | **1_450** | +22% |

**PNY 16GB** (`-161756` / `-161826`):

| Traffic | 25 MHz | 43.75 MHz | Δ |
|---|---|---|---|
| raw read 64 sectors | 2_313 | **3_401** | **+47%** |
| file read 256KB | 701 | 779 | +11% |
| raw write 1 sector | 142 | **51** | **−64%** |
| raw write 8 sectors | 927 | **368** | **−60%** |
| raw write 32 sectors | 938 | 730 | −22% |

### ⚠ The write regressions land exactly where the map has a hole

Stated as a factual connection, not a diagnosis: **43.75 MHz is hp=4, and the
write-side pad at hp=4 has never been characterised.** Round 9's 9c measured the
*read* align band there for the first time (`[2..8]`, centre +5). The
`tx_align_delay` tooth was mapped at **hp 5, 7 and 14 only**, and round 8's
hand-back already lists hp=4 as the campaign's one uncharacterised cell. These
write numbers sit squarely in that unmeasured territory, and that hole is now the
difference between a +47% read gain and a −64% write loss on the same card and
the same clock change.

### ⚠ Catalog discrepancy on the PNY baseline

The brief cites PNY's baseline as **31.3 KB/s**; the standard arm measures
**701 KB/s** on 256KB file reads. The nearest match to 31.3 is our measured
**26 KB/s for 512-byte file writes**, so the catalog figure is probably a *write*
metric. Confirm before anything is compared against it.

## 10c — the ladder stops at step 2: the probe does not reproduce the wedge

| Step | Arm | Socket | Result |
|---|---|---|---|
| 1 CONTROL | default | adapter | **8/8 CLEAN**, every unmount `status=0 elapsed=2 ms` |
| 2 RELIABILITY | default | **Edge** | **8/8 CLEAN** — no wedge, no stall, no near-miss |
| 3 (`SPEED_400K`) | — | — | **NOT RUN** — see below |
| 4 (`READ_ONLY`) | — | — | **NOT RUN** |

Step 2's run parameters are transcript-confirmed (`SOCKET: EDGE module (base 60)`,
writes arm, no clamp), and the card in the Edge slot was confirmed by a separate
identify immediately after the run: Lerdisk `$0000_01F4`.

**Steps 3 and 4 were deliberately not run.** They are interventions, and an
intervention on a reproducer that is not reproducing produces clean arms that
mean nothing — a clean step 3 would read as "400 kHz fixed it" when the control
never failed. Stephen approved stopping the ladder here (2026-08-18).

### The control run that makes this interpretable

Immediately after step 2, the **9a reproducer was re-run on the same card in the
same socket** — `mount_tests` then `raw_sector_tests`, no power cycle:

- `mount_tests` **21 pass / 22 fail**; `mount()` #2 = **`-8`**
- `raw_sector_tests` **0/1**, `ERROR: Card init failed!`

**The wedge is still live.** So step 2's clean result is the probe's cycle being
too gentle, not the card having changed behaviour. That was the one distinction
worth a run, and it is settled.

### What the probe's cycle is missing

| | 9a / re-run (WEDGES) | probe step 2 (CLEAN) |
|---|---|---|
| unmount result | `-7` (2 runs) or `0` (1 run) | `status=0`, 2 ms, ×8 |
| workload | full `mount_tests` — 43 tests, file ops, double-mount, 3x mount/unmount cycles — **then a separate binary** doing raw sector access | mount -> 512-byte write burst -> unmount, x8 |
| crosses a binary boundary | **yes** (two downloads, no power cycle) | **no** |

The probe's mount/write/unmount cycle is not the thing that wedges the card.
**Before the ladder's interventions can discriminate anything, the probe needs to
reproduce first** — a heavier workload, and ideally the cross-binary transition,
which the probe does not exercise at all.

### ⚠ CORRECTION to the round-9 record: the `-7` unmount is INTERMITTENT

Round 9's 9a section reported that `unmount()` "now returns `-7`" as though it
were a stable change from the #3240 record. The 10c re-run — same card, same
socket, same day — returned **`0` instantly, with no stall**, matching the
original record. Three runs: `-7`, `-7`, `0`. The wedge itself (mount #2 `-8`,
raw init failure) is invariant across all three.

Both the 9a section and hand-back item 7 have been corrected in place. The
practical consequence: **todo #3265's instrumentation is still needed** — the
`-7` does not arrive reliably enough to serve as a free discriminator, and
whatever is built must run enough repetitions to observe both outcomes.

### Instrument gap worth closing

`SD_edge_wedge_probe` **never prints the card's identity**. A null result from a
wedge probe is only interpretable if the transcript proves which card was in
which socket; this run needed a separate identify to establish that. The same
caveat was closed for `SD_tx_phase_shmoo` in round 7 — the probe should print
PSN/PNM the same way.

## Round 10 — hand-back summary

| Study | Question | Answer |
|---|---|---|
| 10a | Is the Kingston 2GB an existing catalog row? | **Unanswerable — card is dead** (no init either socket, runs hot). Yields no evidence on SDSC-vs-Edge either |
| 10b | Does a 75% clock increase become 75% throughput? | **No — reads gain up to +47% on all 3 cards; writes REGRESS on 2 of 3** (worst −64%) |
| 10c | Is the Edge-wedge reproducer deterministic? | **The probe does not reproduce it at all** (8/8 clean on Edge) while the 9a suite pair still wedges the same card minutes later |

### Container-side items from round 10

1. **The write regression at hp=4 is the headline** (10b). Reads gain, writes lose
   badly on 2 of 3 cards, and hp=4 is the one cell whose *write* pad the campaign
   never characterised. This bears directly on the item-1 speed decision: enabling
   high speed as shipped would improve reads and materially damage writes on some
   cards. **A tx-pad characterisation at hp=4 is the obvious next bench run** —
   say the word and it runs.
2. **`SD_edge_wedge_probe` needs a heavier arm** (10c) before its ladder means
   anything: closer to `mount_tests`' workload, and ideally crossing a binary
   boundary. Also make it print card identity.
3. **The `-7` correction** (10c) — round 9's item 7 was wrong; #3265 still needs
   building.
4. **A replacement non-asdfg SDSC card** to restore 10a's scope question.
5. **Confirm the PNY catalog baseline** (31.3 KB/s looks like a write metric being
   compared against read figures).

### Bench scope

10a is closed (dead card). 10b is complete, 6 runs, 3 cards. 10c is stopped at
step 2 by decision, with steps 3-4 pending a probe that reproduces. No card lost;
one card found dead on arrival.

---

# Round 11 — reproduce the wedge, and settle the write regression (run 2026-08-18)

## 11a — ⛔ GATE NOT PASSED: the rebuilt probe still does not reproduce the wedge

| | Rebuilt probe | Known suite pair, 40 s later |
|---|---|---|
| Result | **8/8 CLEAN** | **WEDGED** |
| `unmount()` | `status=0`, 2–9 ms every cycle | **`-7`** |
| `mount()` #2 | never failed | **`-8`** |
| `raw_sector_tests` | — | **0/1**, `ERROR: Card init failed!` |
| `mount_tests` | — | 19 pass / 24 fail |

Transcript-confirmed: `SOCKET: EDGE module (base 60)`,
`CARD: MID=$05 PNM='asdfg' PSN=$0000_01F4`. **The identity gap flagged in round 10
is closed** — the probe prints its own identity now, so this null result stands
without a separate identify run.

**Per the brief's own rule, the ladder was NOT run.** `-D SPEED_400K` and
`-D READ_ONLY` are untouched. An intervention tested against a non-reproducing
reproducer yields clean arms that mean nothing.

**What the rebuild bought, and what it did not.** The heavier cycle is genuinely
heavier — `freeSpace()` performs a real full FAT scan (~1_120 ms per cycle),
plus `volumeLabel()`, a raw sector read, a double-mount, and
create/write/read/delete. It still does not wedge. **"Not enough work per cycle"
is therefore largely eliminated as the explanation.**

**The one structural difference the rebuild did not address:** the known
reproducer **crosses a binary boundary** — `mount_tests` and `raw_sector_tests`
are two separate downloads with a P2 reset between them and no power cycle. The
probe is a single binary looping internally. That is now the most conspicuous
surviving candidate. Flagged as the untested variable, **not** asserted as the
mechanism.

This run's `unmount()` returned `-7`, consistent with the intermittency correction
made in round 10 — the tally is now `-7`, `-7`, `0`, `-7` across four runs.

Logs: `SD_edge_wedge_probe_260818-174340.log`,
`SD_RT_mount_tests_260818-174421.log`, `SD_RT_raw_sector_tests_260818-174423.log`.

## 11b — the high-speed write regression is SLOW, not CORRUPT

**Twelve verify checks across three cards and both arms: every one `bytes match`.**
No `CONFIRMED WRITE CORRUPTION`, no attribution re-read triggered anywhere, so all
timings in every run are comparable.

The regression is real where it reproduces, and the data lands intact:

| Card | 10b | 11b | Verdict |
|---|---|---|---|
| **Samsung** `$4AC8_5F42` | −55% 1-sector write | **−52%** (404 -> 192 KB/s) | **REPRODUCIBLE** |
| **Lexar** `$3354_9024` | gains everywhere | gains everywhere (64-sec read 2_296 -> 3_372, +47%) | **REPRODUCIBLE** |
| **PNY** `$01CD_5CF5` | −64%, −60% | **+6%, +5%** | ⚠ **NOT ESTABLISHED** |

### ⚠ CORRECTION to round 10b: the PNY regression was card variance

Same card, same bench, hours apart:

| PNY raw write | 10b std | 11b std | 10b HS | 11b HS |
|---|---|---|---|---|
| 1 sector | 142 | **48** | 51 | **51** |
| 8 sectors | 927 | **351** | 368 | **369** |
| 32 sectors | 938 | **663** | 730 | **732** |
| 64 sectors | 1_325 | **1_025** | 1_154 | **1_157** |

**The high-speed numbers reproduce to within 0.3%. The 25 MHz numbers moved by up
to 3x.** In 11b the standard arm is *slower* than high speed at every write size,
so the −64% / −60% regression inverts into a small gain. The card's within-run
dispersion says the same: `Min=13_430 Avg=20_079 Max=79_407` on a 512-byte file
write, `Min=163_135 Avg=211_371 Max=585_262` on 32KB — 6x and 3.6x spreads inside
a single measurement loop. That is controller housekeeping, not a bus effect.

**Round 10's "writes regress on two of three cards" overstates the evidence.** The
correct statement is **one of three confirmed, one refuted as noise, one clean**.
Corrected in the round 10 section in place.

Logs: Samsung `-175602`/`-175644`, Lexar `-180316`/`-180336`, PNY `-181751`/`-181822`.

## 11c — the hp=4 write pad: the tooth is MAPPED, and the shipped default is SAFE

Samsung `$4AC8_5F42`, `high speed ACTIVE: 43_750 kHz, hp=4`, readback at 12.5 MHz.
**Run four times; byte-identical every time**, including the exact expected/got
values at each failing pad.

| pad | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| result | **FAIL** | PASS | **PASS** | PASS | **FAIL** | PASS | PASS | PASS | **FAIL** |

### The brief asked for a "passing band and its centre" — that model does not fit

**There is no contiguous band.** Failures land at pads **2, 6, 10**: a strict
**period of 4**, i.e. failing pads ≡ **2 (mod 4)** at hp=4. Every failure is
`diffs=496` of 512, `first at offset 0`.

This is the round-7b sawtooth signature, **measured at hp=4 for the first time** —
the cell that has been the campaign's one uncharacterised hole since round 8 is
now closed. The period tracks hp again, but the phase offset is **2**, where hp=7
gave losing pads 8/15/22/29 (≡ **1** mod 7). The model now has a fourth point to
fit; why the offset differs is a container-side question, not a bench claim.

### Two answers fall out directly

1. **The shipped default pad 4 PASSES** (4 mod 4 = 0), two pads clear of the
   nearest tooth on either side. A user running verified high speed at the default
   is **not** exposed to this corruption — which is exactly what 11b's twelve
   clean verifies independently showed. Two instruments, same conclusion.
2. **The pad is therefore NOT the cause of the write slowdown.** By the brief's own
   decision rule, the Samsung's reproducible −52% is **card-side behaviour in
   high-speed mode**. Combined with 11b, the write path at 43.75 MHz is
   **slow but sound**.

### ⚠ The corruption is bit-SMEARING, not a bit-shift

Derived arithmetically from the repeated data, not proposed as a mechanism. At
every failing pad the corrupted byte is exactly `exp | (exp >> 1)`:

| pad | expected | got | `exp \| (exp>>1)` |
|---|---|---|---|
| 2 | `$C2` | `$E3` | `$C2 \| $61` = `$E3` ✓ |
| 6 | `$46` | `$67` | `$46 \| $23` = `$67` ✓ |
| 10 | `$CA` | `$EF` | `$CA \| $65` = `$EF` ✓ |

Three for three, stable across four runs. **Every `1` bit also appears in the
next-lower bit position** — the signature of a bit held or sampled across an extra
half-clock, not of the stream sliding by one position. A true one-bit shift would
give `exp >> 1` with a carry-in, and it does not. **The campaign has described
this failure family as a "one-bit shift" since the round-6 aliasing work; on this
cell the data says otherwise.** Handed over as a measurement.

Log: `SD_write_probe_260818-182055.log` plus three byte-identical repeats.

# Round 11 — hand-back summary

| Study | Question | Answer |
|---|---|---|
| 11a | Does the rebuilt probe reproduce the wedge? | **No — gate failed.** 8/8 clean while the suite pair wedges the same card. Ladder not run |
| 11b | Is the HS write regression slow or corrupt? | **SLOW.** 12/12 verifies match. Plus the PNY regression is **not reproducible** — round 10 overstated it |
| 11c | What is the hp=4 write pad band? | **Not a band — periodic teeth at ≡ 2 (mod 4).** Shipped default pad 4 is SAFE; the pad is not the cause |

## Container-side items from round 11

1. **The hp=4 cell is now fully characterised and the shipped default is safe
   there.** Read band `[2..8]` centre +5 (round 9c), write teeth at ≡ 2 (mod 4)
   with default pad 4 passing (11c). **The round-8 hp=4 exemption question and the
   round-10 write-regression blocker are both answerable now**, and neither blocks
   the high-speed decision on correctness grounds.
2. **The high-speed speed decision is now correctness-clear**: reads gain up to
   +47% on every card tested, writes are proven byte-correct at the default pad,
   and the only reproducible write slowdown (Samsung, −52%) is card-side. What
   remains is a product decision about how users reach the mode, not a safety one.
3. **`exp | (exp >> 1)` — revisit the "one-bit shift" language** in the campaign
   docs and in `DOCs/SD-CARD-DRIVER-THEORY.md` if it appears there. The corruption
   on this cell smears bits; it does not shift the stream.
4. **The wedge probe needs to cross a binary boundary** (11a). Heavier workload is
   now ruled out as the missing ingredient; two downloads with a reset between them
   is the conspicuous untested difference. Until the probe reproduces, the ladder
   cannot discriminate anything.
5. **Round 10b's "two of three cards" claim is corrected** to one of three; the PNY
   is a variance case, and any future benchmark comparison on that card needs
   repeat runs before a delta is believed.

## Bench scope

11a stopped at the gate by the brief's own rule. 11b complete (6 runs, 3 cards,
12 verifies). 11c complete and repeated 4x. The Samsung's raw scratch sectors at
LBA 200/100+ were overwritten by 11c and the card was reformatted afterward.

---

# Round 12 — the wedge becomes deterministic, and the hp=4 exemption is vindicated (run 2026-08-18/19)

## 12a — 🔑 THE WEDGE IS NOW A SWITCH: cold is clean, warm wedges, every time

**Six runs on Lerdisk `$0000_01F4` in Edge, zero exceptions:**

| Condition | Runs | `mount_tests` | `unmount()` | `mount()` #2 |
|---|---|---|---|---|
| **COLD** — first binary after power-on | **4** | **43/43 PASS** | `0` | `0` |
| **WARM** — any prior driver session, no power cycle | **2** | **19/24 FAIL** | `-7` | `-8` |

**The wedge requires a prior driver session on the card. A power cycle clears it.**
Demonstrated in both directions in one sitting, alternating on demand. #3240 has
been an intermittent, hard-to-trigger defect since May; it now has a
**deterministic two-command reproducer**.

Card identity confirmed between runs (`asdfg $0000_01F4`). **Note the deliberate
omission: no identify was run before the cold runs** — an identify is itself a
preceding binary and would have destroyed the experiment. Identity was checked
after run 1 instead.

### The preceding binary does NOT need to be a different program

Run 4's predecessor was **the identical `mount_tests` binary**. So this is not
about another tool leaving pins in a strange state, nor about tool-specific
configuration. It is about the card having been through *any* prior driver
session without losing power.

### ⛔ 12b is POSITIVELY ELIMINATED — not deferred

The brief proposes the bad-pin prefix (`mount(60, 10, 58, 15)` and
`mount(60, 59, 20, 16)` in the "Pin offset validation" group) as the trigger the
probe never reproduced. **Those calls execute in all six runs, including the four
clean ones.** A code path that runs identically in clean and wedged runs cannot be
what distinguishes them. `-D BAD_PIN_PREFIX` would be testing a hypothesis the
data has already refuted, so it was not run.

This also retires round 11's **cross-binary-boundary** candidate in its literal
form: no boundary is crossed inside run 4 before the wedge fires at test #13. What
survives is narrower and better — **card state that persists across a P2 reset and
is cleared only by power**.

### The `-7` intermittency was an uncontrolled variable, not noise

The tally had been `-7`, `-7`, `0`, `-7` and read as flakiness. Split by
condition it is not: **every warm run gives `-7`, every cold run gives `0`.**
(The one earlier `0` on a wedged run remains the outstanding exception to that
model and is worth checking against it.)

Logs: `SD_RT_mount_tests_260818-184339/-184420/-184503` (cold, clean),
`-184534` (warm, wedged), `-184949` (cold, clean), `-185003` (warm, wedged).

## 12c — the hp=4 write teeth on two more cards: pad 4 is ESTABLISHED safe

| Card | Controller | Failing pads | Residue | **pad 4** |
|---|---|---|---|---|
| Samsung `$4AC8_5F42` (11c) | Samsung `$1B` | 2, 6, 10 | ≡ 2 (mod 4) | **PASS** |
| Lexar `$3354_9024` | Longsys `$AD` | **none** | — | **PASS** |
| PNY `$01CD_5CF5` | Phison `$27` | 2, 6, 10 | **≡ 2 (mod 4)** | **PASS** |

Each card run twice; identical both times. **Two unrelated controllers land on the
identical residue** and the third expresses no tooth — matching round 7b, where
only three of five cards expressed it. **Nowhere does pad 4 fail.** By the brief's
own decision rule the map is a driver property and the shipped pad is safe, now on
three cards rather than one. The sample-size gap that made 11c's safety conclusion
fragile is **closed**.

### The smearing signature reproduces on a second controller, at lower severity

| pad | expected | Samsung got | PNY got |
|---|---|---|---|
| 2 | `$C2` | `$E3` (bits 5 **and** 0) | `$E2` (bit 5 only) |
| 6 | `$46` | `$67` | `$47` (bit 0 only) |
| 10 | `$CA` | `$EF` | `$EA` (bit 5 only) |

`diffs = 379/380` on the PNY versus `496` on the Samsung. **Same failing pads, same
smear direction — every affected bit propagating into the next-lower position —
but the PNY smears one bit where the Samsung smears several.** The same phenomenon
at lower severity, as expected from a shared timing cause with card-dependent
margin. It further undercuts "one-bit shift": a shift would corrupt the whole
stream identically on both cards.

## 12d — 🔑 THE hp=4 EXEMPTION IS LOAD-BEARING, and round 9c's reading is REVERSED

Measured **inside verified high-speed mode** (banner `HS ARM: high speed ACTIVE at
43_750 kHz, hp=4`), which is the state hp=4 actually ships in. Each card twice,
identical.

| Card | Band | Centre | offset 0 (**exemption**) | offset +5 (**shipped default**) |
|---|---|---|---|---|
| Samsung `$4AC8_5F42` | `[-3..4]` | **0** | **dead centre** | ❌ **OUTSIDE** |
| Lexar `$3354_9024` | `[-3..4]` | **0** | **dead centre** | ❌ **OUTSIDE** |
| PNY `$01CD_5CF5` | `[-1..5]` | +2 | inside | at the **upper edge** |

**Two of three cards exclude the shipped `+5` outright; the third has it on the
boundary. Offset 0 is inside on all three and dead centre on two.**

At hp=4 the floor rule keeps `align = hp`, i.e. **offset 0** — confirmed at
`micro_sd_fat32_fs.spin2:9510`.

### ⚠ CORRECTION to the round-9 hand-back

Round 9's item 3 said the hp=4 exemption "trades the measured centre for a
nearer-edge value" and could now be deleted. **That is wrong, and it is reversed
here.** It rested on round 9c's band of `[2..8]` centre `+5` — which was measured
by *setting* the clock to 43.75 MHz, leaving the card in **default speed mode
driven above spec**. In the state that ships, the band moves down by 3 and
`+5` falls outside it on two of three cards.

**The exemption is not a conservative placeholder awaiting better data. It is the
correct value, and the only one of the two that works on every card tested.**

### The instrument's own failure was independent confirmation

Before the bench fix below, the arm lifted the floor rule *before* negotiating,
putting `align = hp + 5` on the CMD6 verify read. On the **Lexar that verify
failed** with `E_IO_ERROR` and the card appeared to "decline" high speed. It was
not declining: `+5` genuinely does not work on that card at hp=4, and the driver
correctly refused a mode it could not verify. **Two independent observations, same
conclusion** — and the same failure round 8a originally hit.

### ⚠ Pattern worth naming: measuring in a convenient state instead of the shipping state

This is the **second** time this campaign that a measurement taken in a convenient
state produced a conclusion that inverted once measured properly. First the
reference-content aliasing (round 6), now the hp=4 band (9c vs 12d). Both cost a
hand-back item that had to be withdrawn.

## ⚠ TWO BENCH FIXES to `SD_phase_sweep_test.spin2` (the `SPI_43M_HS` arm)

The new arm could **never have worked on any card** as delivered. Both fixes are
ordering, both verified on hardware.

1. **`attemptHighSpeed()` was called BEFORE `initCardOnly()`.** The driver's worker
   cog did not exist yet, so `cog_id == -1` returned `E_NOT_MOUNTED` (`-20`) and
   the arm bailed printing "card DECLINED". Block moved to after `initCardOnly`.
   (`SPI_TARGET_HZ = 0` for this arm, so the `setSPISpeed` override is correctly
   skipped and needed no change.)
2. **`debugSetAlignFloorRuleEnabled(false)` was called BEFORE the negotiation.**
   That put `align = hp + 5` at hp=4 on the CMD6 verify read — exceeding the whole
   bit period (`2*hp = 8` sysclks), the exact read round 8a measured breaking. Moved
   to after a successful negotiation, with a comment recording why.

**Also fixed: the arm reported both `-20` and `-7` as `card DECLINED`.** That is
the decline-vs-query-failed conflation `attemptHighSpeed()`'s own docstring warns
against — "the card said no" and "the card could not be asked" call for opposite
responses. The arm now branches on `ERROR() == 0` and says which it was.

Not committed. The tree still carries the container side's uncommitted work.

# Round 12 — hand-back summary

| Study | Question | Answer |
|---|---|---|
| 12a | Does `mount_tests` wedge from cold? | **NO — clean 4/4 cold, wedged 2/2 warm.** The wedge needs a prior driver session; power clears it. **Deterministic reproducer at last** |
| 12b | Is the bad-pin prefix the trigger? | **Not run — positively eliminated.** Those calls execute in the clean cold runs too |
| 12c | Do the hp=4 teeth hold across cards? | **Yes.** Two controllers share residue ≡ 2 (mod 4), one has no tooth, **pad 4 passes on all three** |
| 12d | Is the exemption's `align = hp` inside the real band? | **Yes — dead centre on 2 of 3.** And the shipped `+5` is **outside** on those two. **Round 9's item 3 is reversed** |

## Container-side items from round 12

1. **The hp=4 exemption must STAY, and round 9's item 3 must be withdrawn.** 12d
   measures `+5` outside the band on two of three cards in the shipping state.
   This is now the strongest single result about the floor cell.
2. **The wedge has a deterministic reproducer** (12a): cold = clean, warm = wedge,
   any prior driver session, cleared only by power. The next question is what
   card-side state survives a P2 reset — and the probe should be rebuilt to run
   *twice in one power-on*, which is the shape that reproduces.
3. **Bad-pin prefix is eliminated** — do not spend a round on it.
4. **Two instrument fixes** to the `SPI_43M_HS` arm plus a decline-vs-failure
   message fix; review and fold in.
5. **`exp | (exp >> 1)` reproduces on a second controller** at lower severity —
   the "one-bit shift" language needs revisiting (carried over from round 11).
6. **Name the measurement-state pattern** in the campaign's method notes: measure
   in the state that ships, not the state that is convenient. Two inversions so far.

## Bench scope

12a complete (6 runs + identity). 12b not run, by elimination. 12c complete
(3 cards x 2). 12d complete (3 cards x 2) after two instrument fixes. Lexar and
PNY were reformatted after 12c's destructive writes.

---

# Round 13 — what exactly does a "prior session" leave behind? (run 2026-08-18/19)

One card throughout: **Lerdisk `asdfg` `$0000_01F4`, Edge socket**, adapter empty.
Identity confirmed in the 13c probe transcript (`CARD: MID=$05 PNM='asdfg'
PSN=$0000_01F4`). **No identify was run before any warm sequence** — an identify is
itself a driver-session predecessor and would have destroyed every result.

## Correction carried in from round 12

Round 12's write-up said the wedge needs "a prior driver session". **That was
looser than the data supported**, and the brief caught it: the wedge probe runs
eight mount/operate/unmount cycles inside a single power-on and stays clean, and
cycles 2-8 are each "after a prior driver session". So a prior driver session
**alone** was never the trigger. The reset window is part of the condition.

## 13a — a DRIVER session is required; the reset alone is not enough

| Predecessor | Runs | `mount_tests` | `unmount()` | `mount()` #2 |
|---|---|---|---|---|
| **null binary** — 49_691 bytes, no driver object, no pin touched | **2** | **43/43 CLEAN** | `0` | `0` |
| `mount_tests` — 47.3 KB, driver session (round 12a) | 2 | 19/24 WEDGED | `-7` | `-8` |

The two predecessors are **matched on download size — the null one is larger**, so
its high-impedance float window is *longer*. It still does not wedge.

**This eliminates the reset itself, the float window, and the download traffic.**
The hypothesis stays on what the driver does to the card, not on what the P2 does
to the pins.

## 13b — the state is LATCHED: time does not clear it, only power

| Step | Predecessor | Gap | Result |
|---|---|---|---|
| 1 | none (cold) | — | **43/43 CLEAN**, `0` / `0` |
| 2 | — | **120 s idle, P2-timed, card powered** | — |
| 3 | driver session + the 120 s hold | 120 s | **19/24 WEDGED**, `-7` / `-8` |

The hold is confirmed in its own transcript (`ARM: HOLD_120S -- idling 120 s
before exit`, ticking `idle 10 s of 120` … ), so the interval is exact rather than
operator-timed.

**This refutes the internal-housekeeping model.** These cards are documented as
re-busying themselves after CS deassert for garbage collection, and the driver's
init busy-poll gives up after about two seconds and proceeds regardless — which
made "the card is still busy and the driver stopped waiting too early" both
plausible and *convenient*, since it would have been driver-fixable. **120 seconds
of powered idle changes nothing.** The defect is not fixable by waiting longer in
init.

## 13c — writes are IRRELEVANT; reads suffice

Predecessor: `SD_edge_wedge_probe -D READ_ONLY` — transcript confirms
`ARM: READ_ONLY -- no writes, FSInfo update suppressed at unmount`, and the probe
itself ran **8/8 clean**.

Then `mount_tests` warm: **19/24 WEDGED**, `unmount()` `-7`, `mount()` #2 `-8`.

**The card's filesystem state is exonerated.** No writes occur, and the FSInfo
update is suppressed, yet it still wedges. Nothing on the card was modified, so
whatever persists is **controller state, not data**.

## The condition, as now bounded

| Predecessor | Wedges? | What it eliminates |
|---|---|---|
| none (cold) — 6 runs across rounds 12-13 | **no** | — |
| null binary, 49.7 KB, no pins — 2 runs | **no** | the reset, the float window, download traffic |
| driver session + 120 s powered idle | **yes** | time-based recovery; the GC-completes model |
| driver session, **read-only** | **yes** | writes, FSInfo update, post-write internal activity |
| driver session, with writes (12a) | **yes** | — |
| 8 in-binary cycles, no reset (probe) | **no** | "prior driver session" alone |

**The trigger is: a driver session that touches the SD pins — reads suffice,
writes are unnecessary — followed by a P2 reset, then another driver session. The
resulting state is latched in the card and cleared only by removing power.**

### ⚠ The one thing that fits no single model yet

**Why do the probe's in-binary cycles stay clean while a reset-separated session
wedges?** Reads happen in both. The only remaining difference is the reset — which
13a proves is **insufficient alone**, but which may still be **necessary in
combination** with a driver session. That is the shape of the next experiment:
something that separates "driver session, then reset, then driver session" from
"driver session, then driver session" with the reset as the only variable.

Stated as the open question, not as a proposed mechanism. Designing that
experiment is container-side work; the bench did not improvise one.

## The cold/warm model held on every run

The brief asked for any run breaking the `0`-cold / `-7`-warm split. **None did**,
across all of round 13. The single earlier `0` on a wedged run (round 10c) remains
the only exception on record and is still unexplained.

# Round 13 — hand-back summary

| Study | Question | Answer |
|---|---|---|
| 13a | Is a *driver* session required? | **Yes.** A larger null binary with no pin activity is clean 2/2 — reset, float window and download traffic are all eliminated |
| 13b | Does time clear it, or only power? | **Only power.** 120 s of powered idle still wedges — the state is latched, and the GC-completes model is refuted |
| 13c | Must the prior session have written? | **No.** A read-only predecessor with FSInfo suppressed still wedges — filesystem state is exonerated, this is controller state |

## Container-side items from round 13

1. **Design the reset-isolating experiment.** The last unexplained gap is
   in-binary cycles (clean) vs reset-separated sessions (wedge), with reads in
   both. The reset is insufficient alone (13a) but may be necessary in
   combination. Needs an instrument that varies *only* the reset.
2. **Drop the busy-poll / init-timeout line of attack.** 13b refutes it with 120 s
   of idle. Any fix proposal resting on "wait longer for the card" is dead.
3. **Stop looking at filesystem state.** 13c wedges with no writes and FSInfo
   suppressed. Whatever persists is in the controller.
4. **Round 12's phrasing needs tightening** wherever it says the wedge needs "a
   prior driver session" — true but incomplete; the reset window is part of the
   condition, as the probe's eight clean in-binary cycles show.

## Bench scope

13a complete (2 runs), 13b complete (3-step sequence with a P2-timed hold), 13c
complete. Six power cycles. No card written, nothing to reformat — 13c's
predecessor was read-only by construction and the rest were `mount_tests`, which
cleans up after itself.

---

# Round 14 — recovery, and the float tested in the right order (run 2026-08-19)

One card throughout: **Lerdisk `asdfg` `$0000_01F4`, Edge socket**, adapter empty.
Four power cycles.

## 14a — ⛔ NOT RECOVERABLE without removing power. Now a tested claim.

Card deliberately wedged first (cold `mount_tests` **43/43 CLEAN** -> warm
**19/24 WEDGED**, `-7` / `-8`), then the ladder with no power cycle:

| Rung | Action | Result |
|---|---|---|
| 1.1 | plain `initCardOnly()` | **`-8` E_NO_CARD** |
| 1.2 | plain `initCardOnly()` again | **`-8`** |
| 2 -> 3 | **102_400 clocks, CS HIGH** (25x the driver's own 4_096 flush), then init | **`-8`** |
| 4 -> 5 | **102_400 clocks, CS LOW** (card selected), then init | **`-8`** |

"Only a power cycle clears it" was previously an observation about the two things
anyone happened to try — re-running the suite, and waiting. **It is now tested.**

**Clocking does not help either.** Idle is not the same as clocked: an SD card
advances its state machine on SCK, and a card waiting for clocks it will never
receive looks exactly like a dead one. It was given 25x the driver's recovery
flush in **both** CS polarities and stayed dead.

**The consequence for v1.7.1 is the unwelcome one, and 14a was aimed squarely at
avoiding it:** there is no in-driver repair to apply. The defect can be *detected*
(init returns `-8`) but not *fixed* without the user physically removing power.

Log: `SD_edge_wedge_probe_260818-231037.log`.

## 14b — 🔑 `initCardOnly()` ALONE arms it. The filesystem layer is exonerated.

Three binaries within **35 bytes** of each other and of the reproducer
(`SD_RT_mount_tests` = 47_347), so the arms differ in what they *do*, not in how
long they take to download:

| Rung | Predecessor does | Size | `mount_tests` warm |
|---|---|---|---|
| `P_NOTHING` | nothing at all, no pin touched | 47_369 | **43/43 CLEAN**, `0` / `0` |
| `P_INIT` | `initCardOnly()` only, **cog left RUNNING** | 47_334 | **19/24 WEDGED**, `-7` / `-8` |
| `P_INIT_STOP` … `P_READ` | — | — | **not needed** |

`P_INIT`'s own `initCardOnly` returned `0` — it succeeded, then armed the wedge.

**The control was run and passed.** `P_NOTHING` is the size-matched control inside
the same instrument (stronger than round 13a's separate null binary, which also
passed), so the reproducer is responding to the predecessor and not to "any binary
having run".

**What this eliminates in one run:** the filesystem mount, directory reads, the FAT
scan, the unmount, and the FSInfo update. Whatever the mechanism is, it lives in
**card initialisation** — CMD0/CMD8/ACMD41/CMD58 and SPI-mode entry — not in
anything the filesystem layer does.

**It also moots `P_INIT_STOP` for arming purposes.** That rung exists to test
whether `stop()` halting the worker cog (releasing DIR bits, floating the pins
inside a running application) is the trigger. `P_INIT` **left the cog running**, so
no `COGSTOP` float occurred, and it armed anyway. Cog shutdown is not required.

## 14c — floating after a driver session is NOT it either

`-D FLOAT_BETWEEN`: all four SD pins released to high-Z for **1_200 ms** between
cycles, matched to the reset-and-download window. **8/8 cycles CLEAN.**

Transcript confirms both that the float happened and that it happened in the right
order: `unmount: status=0` -> `float 1_200 ms (ALL four pins high-Z, as a P2 reset
leaves them)` -> `cycle N CLEAN`. By cycle 2 this is unambiguously a card that has
been mounted, FAT-scanned, written, read and unmounted, then left floating.

### This closes a qualification the round-13 write-up got ahead of itself on

Round 13a concluded the reset, the float window and download traffic were "all
eliminated" — but 13a floated a **virgin** card, before any driver session ever
touched it. In the wedging sequence the float comes **after** one. The order was
never varied, and I reported the elimination without noting that. 14c tests the
order that actually occurs, and it is **also clean**, so the conclusion survives —
but it survives on evidence, not on an untested assumption.

**The CMD0-latches-SPI-mode candidate does not survive.** The proposal was that a
card already latched into SPI mode interprets floating CS and stray SCK very
differently from one still in native SD mode. By cycle 2 the card is unambiguously
in SPI mode, and floating it changes nothing.

## 14d — NOT RUN

Gated on 14c wedging. It did not. Testing CS-held-high as "the mechanism" when the
all-pins-float case is already clean would be testing a weaker version of a
refuted condition.

## Where the wedge stands after round 14

| Ingredient | Status |
|---|---|
| Filesystem operations (mount, FAT scan, unmount, writes) | ❌ eliminated — `P_INIT` alone arms it (14b), writes already irrelevant (13c) |
| Cog shutdown / `COGSTOP` pin release | ❌ not required — `P_INIT` left the cog running (14b) |
| Pin float **after** a driver session | ❌ eliminated — 8/8 clean (14c) |
| Pin float **before** any driver session | ❌ eliminated — 2/2 clean (13a) |
| Time / card housekeeping completing | ❌ eliminated — 120 s powered idle (13b) |
| Clocked recovery, either CS polarity | ❌ eliminated — 25x flush, `-8` every rung (14a) |
| Download duration | ❌ eliminated — size-matched arms throughout (13a, 14b) |
| **`initCardOnly()` + a P2 reset + another driver session** | ✅ **the surviving condition** |

### ⚠ The paradox is sharper, not resolved

**A reset is necessary, but neither of the two things a reset does to the card —
floating the pins, or the download delay — reproduces it.** Both are now
independently eliminated, in both orders. A reset also resets **the P2 itself**,
and that is the part no experiment has isolated.

One observation, offered as an observation and **not** as a mechanism: every
wedging sequence initialises the card **twice** — once in the predecessor, once in
the reproducer — with a P2 reset between them. No in-binary experiment has ever
re-initialised a card that a *previous binary* already initialised; the probe's
cycles re-mount, but the driver object and its cog persist across them. That is
the remaining structural difference. Designing the instrument that isolates it is
container-side work and the bench did not improvise one.

# Round 14 — hand-back summary

| Study | Question | Answer |
|---|---|---|
| 14a | Can a wedged card be recovered without power? | **NO — five rungs, all `-8`**, including 102_400 clocks in both CS polarities. Now tested, not assumed. **No in-driver repair exists** |
| 14b | Which operation arms it? | **`initCardOnly()` alone.** Control `P_NOTHING` clean. **Filesystem layer exonerated**; cog shutdown not required |
| 14c | Does floating after a driver session do it? | **No — 8/8 clean.** Closes the ordering qualification 13a left open; CMD0-latch candidate refuted |
| 14d | CS-high float? | **Not run** — gated on 14c wedging |

## Container-side items from round 14

1. **v1.7.1 is NOT unblocked by recovery.** 14a was the attempt and it failed: the
   driver can detect the wedge (`-8` from init) but cannot repair it. Any release
   decision has to be made on that basis — detection plus documentation, or a
   deliberate acceptance.
2. **Search only card initialisation.** 14b collapses the space to
   CMD0/CMD8/ACMD41/CMD58 and SPI-mode entry. The filesystem layer, the unmount,
   the FSInfo update and cog shutdown are all out.
3. **Both float orders are now eliminated** — stop proposing pin-state mechanisms
   unless something new distinguishes them. 14d remains unrun and unneeded.
4. **The next instrument must isolate the P2 reset itself**, since the reset is
   necessary but its two card-visible effects are refuted. The double-initialise
   asymmetry noted above is the concrete structural difference to attack.
5. **Round 13's phrasing needs the ordering caveat** wherever it says the float
   window is eliminated — true, but only proven for both orders as of 14c.

## Bench scope

14a complete (wedge + 5 rungs), 14b complete and decided at the second rung with
its control, 14c complete (8 cycles), 14d not run by gate. Four power cycles. No
card written beyond the probe's own scratch file, which it deletes; nothing to
reformat.

---

# Round 15 — 🔑 ROOT CAUSE IDENTIFIED: boot-time SD access wedges the card (run 2026-08-19)

One card throughout: **Lerdisk `asdfg` `$0000_01F4`, Edge socket**, adapter empty.

## 15a — the wedge disappears with boot-time SD access disabled, and returns when it is re-enabled

| Switch setting | Flash banner | Cold | Warm |
|---|---|---|---|
| **`1,3` up** (P59 pulled up) | **absent** | 43/43 | **43/43 CLEAN — 4 warm runs across 2 power cycles** |
| **`1-2` up, `3-4` down** (as before) | **present** | 43/43 | **19/24 WEDGED**, `unmount()` `-7`, `mount()` #2 `-8` |

**Every previous warm run in this campaign wedged on the first attempt. With
boot-time SD access disabled, four consecutive warm runs came back clean**, then
the wedge returned immediately when the switches went back.

**The toggle was demonstrated in BOTH directions in one session on one card.** A
single-direction result would not have distinguished "we fixed it" from "the card
had a quiet day" — and this campaign has already produced two conclusions that
inverted under re-measurement, so the reverse control was run deliberately.

### Switch state was verified empirically, not assumed

P2KB (`p2kbArchBootPatternSelection`, Hardware Manual 2022-11-01) documents
`P59 = up` -> *"Program from serial within 60 s window; no flash or microSD card
boot"*, with P60/P61 both "any". Since that pattern disables **flash** boot too,
the `* Hi! from FLASH *` banner is an observable proxy for the switch state:

- `1,3` up -> banner **absent** (boot-time access off) — confirmed by running the
  pin-silent null predecessor, which round 13a proved does not arm the wedge
- `1-2` up, `3-4` down -> banner **present** (boot-time access on)

The switch numbering was never guessed; the banner was read out of each transcript.

## Why this explains everything the previous four rounds could not

**The damage is done before our code runs.** That single fact resolves the
standing paradox — a reset was necessary, yet both of its card-visible effects
(pin float in both orders, download duration) were independently refuted. The
third thing a reset does is **run the boot ROM**, and on this board the boot
sequence talks to the SD card at RCFAST (20-30 MHz) before any user instruction
executes.

It also explains **round 14a**: no recovery rung worked because the driver never
had a chance. By the time our first instruction ran, the card was already wedged.

And it fits every row of the elimination table, including the two that most
constrained the space — in-binary cycles stay clean because no reset intervenes,
and `P_INIT` wedges because our init runs *before* a boot-time SD conversation
that then follows it.

## ⚠ NOT YET ATTRIBUTED: boot ROM vs the flash program

**Both settings changed two things at once.** `P59 = up` disables **flash boot as
well as SD boot**, and this board runs a user program in flash on every reset
(`* Hi! from FLASH *`). So the culprit is **either**:

- the **boot ROM's own SD conversation** (ROM initialises the card in SPI mode,
  mounts FAT32, looks for a boot file, falls back to serial), **or**
- the **flash program** touching the card

Both are boot-time, both fit every observation. **Round 15 identifies the layer,
not yet the actor.**

### The discriminator, from the same P2KB table

**P61 up with P59 floating** -> *"Program from serial within 100 ms, OR boot from
flash"*: flash boot **runs**, SD boot **does not**.

- Warm run **clean** in that config -> the **boot ROM** is the culprit
- Warm run **wedges** -> the **flash program** is the culprit

The bench did not run this, because it requires knowing which physical DIP
positions correspond to `FLASH` (P61) and the `△`/`▽` pair (P59). P2KB documents
the labels but not their mapping to positions 1-4, and a wrong setting would
silently produce a meaningless result. **Note the open possibility:** if
`1-2 up, 3-4 down` already *is* P61-up-with-P59-floating, then the discriminator
has effectively already run and the answer would be "the flash program" — but that
turns entirely on the mapping and is not asserted here.

## What this does and does not deliver for v1.7.1

**It is a diagnostic, not a fix.** Users cannot be required to set a DIP switch —
booting from SD is a legitimate configuration the driver must work in, and users
have their own boards.

Combined with round 14a (**no in-driver recovery exists** — five rungs including
102_400 clocks in both CS polarities, all `-8`), the shape of the release decision
is now clear and evidence-backed rather than open-ended:

- the wedge is **triggered before our code runs**
- it is **not recoverable** by anything the driver can do afterwards
- it needs a **marginal/counterfeit card** *and* **a board with boot-time SD
  access** — no mainstream card has ever wedged in this campaign

That is a narrow, precisely stateable incompatibility rather than a blanket
warning — though with 15b passing, a documented incompatibility is now the
fallback position rather than the expected one.

## 15b — 🔑 CMD12 QUIESCE WORKS. A shippable fix, proven twice with controls.

`-D SD_INIT_QUIESCE` (default OFF in the driver), **switches left in the wedging
config — SD boot ENABLED, flash banner present in every transcript**, so the boot
sequence ran exactly as it does in the failing case.

| | Pair 1 | Pair 2 |
|---|---|---|
| quiesce, cold | **43/43** | **43/43** |
| quiesce, **warm** | **43/43 CLEAN** | **43/43 CLEAN** |
| quiesce, warm again | — | **43/43 CLEAN** |
| **unmodified, warm (control)** | **19/24 WEDGED**, `-7`/`-8` | **19/24 WEDGED**, `-7`/`-8` |

**Five clean quiesce runs across two power cycles.** In *both* pairs the
unmodified build was run warm immediately afterward, on the same card with no
power cycle, and **wedged both times** — so neither pair can be explained by the
wedge having gone quiet. The brief's own warning ("a fix that is really just a
quiet day proves nothing") is answered directly.

### What this confirms about the mechanism

Nothing about the board changed — the boot sequence still talks to the card on
every reset. So **CMD12 is not preventing the boot-time conversation; it is
aborting the data-transfer state that conversation leaves behind.**

A card left mid-transfer is **streaming, not listening**. CMD0 sent into that
stream is data, not a command — precisely the observed failure mode: five CMD0
retries, no response, `E_NO_CARD`. Part 1 Physical Layer §4.3: *"All data read
commands can be aborted any time by the stop command (CMD12). The data transfer
will terminate and the card will return to the Transfer State."*

**It also explains round 14a's total recovery failure.** A multiple-block read
continues until it is told to stop, so 102_400 extra clocks in either CS polarity
only fed the stream. The recovery ladder never sent the one command that would
have reached it.

### Why this matters for v1.7.1

15a identified the cause but explicitly **could not ship** — users cannot be
required to set a DIP switch. **15b works on any board, with no switch and no user
action.** The driver quiesces the card itself.

The arm is **default OFF**, so shipped behaviour is unchanged until the container
side decides to enable it. That decision is now backed by two controlled
demonstrations rather than a hypothesis.

# Round 15 — hand-back summary

| Study | Question | Answer |
|---|---|---|
| 15a | Is boot-time SD access the trigger? | **YES.** 4 warm runs clean with it disabled; wedge returns immediately when re-enabled. Toggle proven both directions |
| — | Which actor — boot ROM or flash program? | **NOT YET SEPARATED.** `P59 = up` disables both. Discriminator identified (P61 up + P59 float) but needs the DIP mapping |
| 15b | Can CMD12 quiesce the card? | **YES — 5 clean runs, 2 pairs, each with a same-session control that wedged.** A shippable fix needing no switch and no user action |

## Container-side items from round 15

1. **Root cause is boot-time SD access.** Four rounds of elimination end here. The
   card is wedged before our first instruction executes, which is also why no
   recovery exists (14a).
2. **Attribute it: boot ROM or flash program.** Run P61 up + P59 floating — flash
   boot runs, SD boot does not. Needs the Edge DIP position mapping, which the
   bench would not guess at.
3. **15b PASSED — enable it.** CMD12 quiesce is proven on hardware: 5 clean runs
   across 2 power cycles with SD boot enabled, and the unmodified build wedged
   immediately after each pair on the same card. It is **default OFF** in the
   driver; turning it on is a container-side decision that now rests on controlled
   evidence. **This is the fix that unblocks v1.7.1.**
4. **The incompatibility can now be stated precisely** if no fix lands: marginal
   or counterfeit card **and** a board with boot-time SD access enabled. Not a
   blanket warning.
5. **P2KB gap worth filing:** `p2kbArchBootPatternSelection` records the Edge
   `FLASH` and `△`/`▽` switch labels but not their DIP positions, and flags P60's
   pull-up source as "verification pending". Both cost us a run this session.

## Bench scope

15a complete, both directions, 8 runs plus a switch-state verification. **15b
complete — 2 pairs, 5 quiesce runs, 2 controls.** No card written; nothing to
reformat.

**Bench incident, for the record:** between 15a and 15b the P2 stopped answering
`Prop_Chk` while the USB port still enumerated (`No Propeller v2 device found`).
Cause was external — something else on the host was talking to the board. Cleared
by a power cycle; no data affected, nothing needed re-running. Worth noting
because the symptom is identical to the known PropPlug failure mode AND to a
no-serial-window boot-switch setting (`P61 = up` with `P59 = down`); check all
three, in that order.

---

# Round 16 — bench notes (run 2026-08-19)

## Fleet correction, from Stephen before any card was handled

**The Camera Plus 64 GB set is FIVE cards TOTAL: 2 retained + 3 deploy-bound** —
not 5 deploy-bound plus a separate retained pair as the run sheet / brief imply.
Consequences for this round:

1. **16e instance variance (n=5) includes both retained units.** The n=5
   distribution is still measurable, but only 3 of its points are one-shot.
2. **The one-shot capture-everything rule applies to the 3 deploy-bound units**
   (plus the 2 non-retained Lexar reds), not to five.
3. **Any future re-check has n=2 Camera Plus available** (the retained pair),
   not n=1 — slightly better than the brief's write-up caveat assumed.
4. Step 0's STOP condition is unchanged: if neither retained unit reads
   `$0000_0F14`, the catalogued unit is among the 3 deploy-bound cards.

**Same pattern for the other two matched sets (Stephen, same conversation):**
the stated set sizes are totals that INCLUDE each set's retained/catalogued unit.

| Set | Total | Retained (catalogued) | Deploy-bound (one-shot) |
|---|---|---|---|
| Gigastone Camera Plus 64 GB | 5 | 2 | 3 |
| Lexar red 64 GB | 3 | 1 (`Longsys/Lexar_MSSD0_6.1_33549024_202411`) | 2 |
| SanDisk Extreme 64 GB | 2 | 1 | 1 |

So the one-shot population this round is **6 cards** (3 + 2 + 1), and every
matched set keeps at least one unit for future re-checks.

## Step 0 — retained 64 GB pair identified and marked (16:46–16:49 bench time)

| Card | PSN | Details | Disposition |
|---|---|---|---|
| A | `$0000_0E2F` | Gigastone OEM ASTC SDXC 58GB, rev 2.0, 2023/06, [mkfs.fat], warnings $00 | Unmarked retained unit — **card record owed**. This is Card 2a, the open #3348 raw-init defect card |
| B | `$0000_0F14` | Gigastone OEM ASTC SDXC 58GB, rev 2.0, 2023/06, [P2FMTER], warnings $00 | **Marked GREEN** = catalogued `GigastoneOEM_ASTC_2.0_00000F14_202306` |

Transcripts: `tools/logs/SD_card_identify_260819-144633.log` (A),
`tools/logs/SD_card_identify_260819-144930.log` (B). Both identified in the
EDGE socket on driver 1.8.0. **Purchase date (Stephen): Gigastone 64 GB
units purchased 2024-03-13; the 32 GB Gigastone pair the same date.
Lexar red 64 GB units purchased 2026-01-16. SanDisk Extreme 64 GB:
no purchase record.**
Source/vendor not recorded.

**Bonus fact:** the unmarked retained 64 GB is `$0000_0E2F` = Card 2a of #3348
(initCardOnly/audit/fsck/formatter fail, mount/identify work). Retained status
means #3348 stays reproducible-on-demand; the unconditional CMD12 quiesce in
v1.8.0 has not yet been tested against it.

### ⚠ INSTRUMENT DEFECT (first light): machine-readable identify lines malformed

`SD_card_identify` 2026-08-19 build emits mangled key lines (human L1/L2/L3 fine):

```
SILICON-KEY: $$12_ASTC _2.0                        ← doubled $, embedded space
CARD-ID: $$12_ASTC _2.0_$0000_0F14_2_02306         ← date mangled "2_02306", $ and _ inside key
CATALOG-CARD: ... mid=$$12 pnm=ASTC  prv=2.0 psn=$$0000_0F14 mdt=2_023/6 ...
```

Expected key style (per catalog): `GigastoneOEM_ASTC_2.0_00000F14_202306`.
Looks like `$`-prefixed debug formatting applied on top of literal `$`, plus a
misplaced digit-grouping underscore in the date fields. **Must be fixed before
the two owed card records are keyed from transcripts, and before step 5's
one-shot captures** — those transcripts are unrepeatable and would carry the
mangled keys forever. Card identity itself is unaffected (PSNs are readable).

## Step 1 (16a) — RESULT: 533/534, single failure ROOT-CAUSED as a test defect

**BENCH PAUSED HERE awaiting container changes** (policy, Stephen 2026-08-19:
bench diagnoses and documents; container makes ALL code changes, then adds
resume documentation below; bench picks up from there).

Sweep: Amazon Basics `$3584_1E2E`, EDGE socket, tree **clean at `1ee21cc`**
(`v1.7.0-25-g1ee21cc`), 27 suites, closing audit 23/23 OK, both mid-sweep
reformats OK. Transcript: `tools/logs/sweep_260819-150140.txt`.
Only red: `SD_RT_speed_tests` 16/17 — Test #8, first hardware light of the
2026-08-19 speed suite. Failing suite log:
`tools/logs/SD_RT_speed_tests_260819-150702.log`.

### Root cause (bench analysis, evidence in the two logs above)

Test #8 (`attemptHighSpeed()` consistent with `isHighSpeedActive()`,
`src/regression-tests/SD_RT_speed_tests.spin2` ~lines 207-230): on this card
`attemptHighSpeed()` = FALSE, `isHighSpeedActive()` = FALSE, `ERROR()` = -7
(E_IO_ERROR). The test's FALSE branch demands `ERROR() == SUCCESS` ("card
declined, query did not fail") — it models only two of the driver's three
documented outcomes. The driver docstring (`micro_sd_fat32_fs.spin2:2348`)
defines: TRUE; FALSE+SUCCESS = card said no; FALSE+error = query/switch/verify
failed. This card CLAIMS capability (tests #6/#7 = TRUE, error 0) but its
record documents "CMD6 High Speed switch fails despite CCC including Class 10"
(`DOCs/cards/amazon-basics-usd00-64gb.md:256`, known since characterization).
Driver behaved per contract: switch failed, safe rollback proven by tests
#9/#10 (integrity green, 25 MHz restored). **Driver correct; test incomplete.**

### Container work item A — fix Test #8 (and one latent driver/docstring gap)

Bench recommendation (container has decision latitude):
1. **Test**: FALSE branch should assert consistency with the capability answer
   already captured by test #7: capable=TRUE → expect `ERROR() <> SUCCESS`
   (switch/verify failure is the documented outcome); capable=FALSE → expect
   `ERROR() == SUCCESS` (clean decline). Keep the hsActive==FALSE check; a
   freq-unchanged check strengthens the failure arm.
2. **Driver (one line)**: the verify-MISMATCH fallback
   (`micro_sd_fat32_fs.spin2:6250` region) sets NO error code, though the
   docstring says verification failure carries one — FALSE+SUCCESS from a
   capable card would be indistinguishable from a polite decline and would
   fail the recommended test invariant if a card ever exercises that path.
   Set `hs_query_error := E_IO_ERROR` there to align code with contract.
   (If declined, punch-list it and weaken the test invariant accordingly.)
3. If sub-test counts change, update every doc citing **534** (ROUND-16-RUN-SHEET
   step 1, SOCKET-SHMOO-RUN-BRIEF 16a) to the new total.

Driver change → step 1 re-runs in full per the run sheet; the re-sweep is
needed anyway for a green cert transcript, so it costs nothing extra.

### Container work item B — catalog key-line formatting defect (3 tools)

First light proved the machine-readable identity lines are mangled and would
corrupt the harvest. Evidence: step-0 transcripts above. Mechanism:
- `uhex_byte_()`/`uhex_long_()` emit their own `$` (doubling the literal:
  `$$12`) and underscore-group longs (`$0000_0F14` where the key needs
  contiguous `00000F14`)
- `udec_()` underscore-groups >=1000: CARD-ID dates render `2_02306`, and every
  numeric CATALOG-ROW field (kbps, avg_us, landed_hz…) breaks
  `harvest_catalog.sh`'s `field()+0` (awk reads `2_500` as 2 — silent numeric
  corruption of the whole sweep)
- `lstr_(@pnm, 5)` prints the space-padded PNM verbatim (`ASTC ` inside keys)

The parser (`tools/harvest_catalog.sh`) documents the canonical form and is
correct — fix the emitters. Canonical targets:
`SILICON-KEY: $12_ASTC_2.0` · `CARD-ID: $12_ASTC_2.0_00000F14_202306` (no inner
$, PSN 8 contiguous hex, YYYYMM zero-padded) · CATALOG-CARD/ROW values as plain
digits (`mid=$12 pnm=ASTC psn=$00000F14 mdt=2023/6 sysclk=350000000`).

Fix pattern (house precedent `src/DEMO/SD_demo_shell.spin2:1125-1132`): use
existing `src/isp_mem_strings.spin2` — `fmt.sFormatStrN` into a line buffer,
emit via one `debug(zstr_(@lineBuf))`. `%.2x` = 2 hex digits no sigil, `%.8x` =
8 hex digits, `%d` plain decimal, `%.2d` zero-padded month (collapses the
month-padding if/else). Lines needing >8 args: second call appends at
`@BYTE[@lineBuf][nLen]` (demo-shell pattern). Trim trailing spaces from a PNM
copy for key use (in SD_card_identify the existing `@pnm` buffer can be trimmed
in place right after its terminator is placed — also fixes L1's silent double
space; benchmark/characterize need a small `pnmKey[6]` since they print raw CID
bytes today).

Affected emitters:
- `src/UTILS/SD_card_identify.spin2` 185-200 (SILICON-KEY, CARD-ID both
  branches, CATALOG-CARD incl. spi_hz)
- `src/UTILS/SD_performance_benchmark.spin2` 293-316 (same set) and 467-471
  (CATALOG-ROW instr=throughput: run/bytes/avg_us/min_us/max_us/kbps/pct_bus/
  spi_hz all need plain digits; op & limiter are strings already)
- `diagnostic-tests/SD_speed_characterize.spin2` 327-349 (same identity set;
  CATALOG-CARD has NO spi_hz field, ends at sysclk; 2-space indent file) and
  623-626 (CATALOG-ROW instr=random_access: iters/kbps/mean_us/min_us/max_us/
  req_hz/landed_hz)
Human-readable lines (L1/L2/L3, `Card:`, `>>> SERIAL`) keep their formatters —
grouping is good for humans; only machine lines change.

### Bench resume procedure (container: append your hand-back below this)

1. `cd tools && ./check_doc_version.sh` (exit 0) and confirm clean tree at the
   container's commit
2. Re-run step 1: `./run_regression.sh` — Amazon Basics `$3584_1E2E` is STILL
   SEATED in the Edge socket. Expect the (possibly updated) full-green total
3. Verify item B on hardware: one `./run_test.sh ../src/UTILS/SD_card_identify.spin2`
   run (any seated card) — key lines must match canonical form; feed the log to
   `./harvest_catalog.sh` if practical (expect clean CATALOG-CARD parse, no rows)
4. Cheap while sockets are free: re-identify both retained 64 GB cards for
   clean record-source transcripts (records for `$0000_0E2F` and the 32 GB
   `$0000_01C7` are owed from this round)
5. Continue the run sheet at step 2 (16d, Samsung EVO `$4AC8_5F42`)

---

# Round 16 (bench session 1, 2026-08-19) — hand-back summary

Steps 0 and 1 of ROUND-16-RUN-SHEET.md ran; bench is PAUSED at the step-1 gate.
Detail and evidence pointers are in the bench notes above; this is the record.

| Step | Question | Answer |
|---|---|---|
| pre | Version constants consistent? | **YES** — check_doc_version.sh exit 0, driver/string/CHANGELOG all 1.8.0 |
| 0 | Which retained 64 GB is the catalogued unit? | **Card B = `$0000_0F14`, now marked green.** Card A = `$0000_0E2F` (the open #3348 card) — record owed |
| 1 (16a) | Does the quiesce-default driver certify? | **533/534 — driver exonerated, the one red is a TEST defect.** Closing audit 23/23; transcript `tools/logs/sweep_260819-150140.txt` on clean tree `1ee21cc` |
| — | What failed and why? | Speed suite Test #8: its FALSE branch models 2 of the driver's 3 documented outcomes. Amazon Basics claims CMD6 capability but the switch fails (behavior already in its card record); driver returned FALSE + E_IO_ERROR per contract and rolled back cleanly (integrity + 25 MHz proven by tests #9/#10) |

## Observations of record

1. **The unconditional CMD12 quiesce passed its first full-suite exposure.**
   533 of 534 tests green across 27 suites, every mount in every suite starting
   with the quiesce, plus two mid-sweep reformats and a 23/23 closing audit.
   The single failure is unrelated to the quiesce.
2. **Test #8's contract gap is card-class-shaped, not random**: it will fail on
   every card that advertises CMD6 capability but refuses the switch — a class
   the catalog already documents. First light behaved exactly as the
   new-test-first-run lesson predicts: the red indicted the test, not the code.
3. **Latent driver/docstring gap found during root-cause** (not hit by any card
   yet): the 50 MHz verify-MISMATCH fallback leaves ERROR()=SUCCESS while the
   docstring promises an error on verification failure. Fix or punch-list —
   container's call; work item A above carries both options.
4. **Instrument defect, first light of the 2026-08-19 identity lines**: all
   three catalog instruments emit mangled machine keys (`$$12`, `ASTC `,
   `2_02306`) and — worse — `udec_()` digit-grouping breaks every numeric
   field the harvester reads (`kbps=2_500` parses as 2). Caught before any
   one-shot card was measured, which was the point of running first-light
   before the sweep. Full fix spec is work item B above.
5. **Fleet corrections from Stephen taken as notes above**: matched-set counts
   INCLUDE retained units (one-shot population is 6 cards, not 10); purchase
   provenance recorded (Gigastones 2024-03-13, Lexar reds 2026-01-16, SanDisk
   Extreme no record).

## Container-side items from this session

1. **Work item A** — Test #8 three-outcome fix + optional one-line driver
   mismatch-path error (spec above). If test counts change, update every doc
   citing 534.
2. **Work item B** — catalog key-line formatting in identify / benchmark /
   speed_characterize (spec above). Must land before step 5's one-shot captures
   and before the two owed card records are keyed from transcripts.
3. Append the resume hand-back below the bench resume procedure above.

## Bench scope

Step 0: two identify runs (retained 64 GB pair), green mark applied to
`$0000_0F14`. Step 1: one full regression sweep, Amazon Basics `$3584_1E2E`,
Edge socket, plus one aborted sweep start (stopped in compile phase to commit
bench notes — the sweep banner caught a dirty tree; nothing ran on hardware).
Amazon Basics was reformatted twice by the sweep harness as designed and REMAINS
SEATED in the Edge socket for the re-run. No incidents; PropPlug and board
behaved throughout.

---

# Round 16 (bench session 2, 2026-08-19) — resume verified, STEP 1 GREEN

Resumed per the container hand-back in ROUND-16-RUN-SHEET.md (source SHA
`88fe9a3` verified via the scoped log check; tree clean; check_doc_version 0).

| Gate | Result |
|---|---|
| Item B on hardware | **PASS** — identify on the seated Amazon Basics emits `SILICON-KEY: $AD_USD00_2.0`, `CARD-ID: $AD_USD00_2.0_35841E2E_202507`, CATALOG-CARD all plain digits (`tools/logs/SD_card_identify_260819-155904.log`); `harvest_catalog.sh` parses clean, banner "All figures measured on driver v1.8.0", exit 0 |
| Step 1 (16a) re-run | **534/534, 27 suites, 0 fail.** Speed suite 17/17 — Test #8 now passes on the CMD6-claims-but-refuses card class. Closing audit 23/23; 2 reformats OK. Transcript `tools/logs/sweep_260819-155926.txt`, tree `v1.7.0-31-g80cff82`, source `88fe9a3` |

**v1.8.0 driver certification on Amazon Basics `$3584_1E2E` (64 sec/cluster
geometry) is complete.** Next per resume: re-identify both retained 64 GB cards
(clean record-source transcripts), then step 2 (16d, Samsung EVO `$4AC8_5F42`).

## Clean record-source transcripts for the retained 64 GB pair

Re-identified on driver 1.8.0 with the fixed key lines. Both card records key
from these transcripts (supersede the session-1 mangled-key transcripts):

| Card | CARD-ID | Transcript |
|---|---|---|
| A (unmarked, record OWED) | `$12_ASTC_2.0_00000E2F_202306` | `tools/logs/SD_card_identify_260819-161527.log` |
| B (green, catalogued) | `$12_ASTC_2.0_00000F14_202306` | `tools/logs/SD_card_identify_260819-161620.log` |

Same silicon key `$12_ASTC_2.0` on both — one product, one silicon. A carries
mkfs.fat, B carries P2FMTER. Next: step 2 (16d), Samsung EVO `$4AC8_5F42`.

## BENCH PAUSED at step 2 — the 16d cell has no instrument arm

**Observation** (protocol rule 2: proceeding needs a source change, so hand
back). The 16d cell is "high speed negotiated via CMD6, then writes clocked at
25 MHz". Searched for its implementation before seating the Samsung:

- `SD_performance_benchmark`: the only speed arm is `#ifdef HIGH_SPEED`
  (lines 174-187, added 2026-08-18) — negotiate, then measure EVERYTHING at
  the negotiated clock. That is the round-11b cell, not the missing one. The
  only post-negotiation `setSPISpeed(25_000_000)` is the verify-failure
  attribution fallback (~line 643), unreachable in a healthy run.
- `SD_speed_characterize`: no `attemptHighSpeed()` call anywhere; its ladder
  is standard-mode and its CATALOG-ROW op is `random_read_1x512` — read-only.
- No dedicated 16d instrument exists in `diagnostic-tests/` or `src/UTILS/`.
- `run_test.sh -D <sym>` passes defines through (repeatable), so a build-time
  arm slots straight into the existing invocation pattern.

**Bench recommendation** (container decides): a second define in the benchmark
(e.g. `HS_WRITES_AT_25`, valid only with `HIGH_SPEED`) that negotiates CMD6,
then drops the clock to 25 MHz for the write measurements — or the simpler
whole-run-at-25-inside-HS form, which still answers the attribution because
both comparators already exist (10b: standard mode at 25; 11b: HS mode at
43.75). Either way the transcript must record `isHighSpeedActive()` at start
and end per the run sheet, and a `CATALOG-ROW`-visible marker of which arm ran
(the harvester must not mix these rows into the standard tables).

**State at pause:** tree clean at `78185bd` (source unchanged at `88fe9a3`).
Run-sheet steps complete: 0 ✓ (plus clean re-identify of the retained pair),
1 ✓ **534/534**. Edge socket EMPTY — Samsung EVO `$4AC8_5F42` staged but NOT
seated. Bench resumes at step 2 when the container hands back an arm to run.

## Step 4 (16b) — Lerdisk in the EDGE socket: the wedge is GONE; 532/534; closing audit says REPAIRS NEEDED → BENCH PAUSED (hard stop rule 3)

**The campaign headline first: the #3240 signature did not reproduce.** Mount
tests 45/45 and raw_sector_tests 14/14 in the EDGE socket on the card whose
record says "External connector only". Full transcript
`tools/logs/sweep_260819-180530.txt`, tree `e932838`, source `88fe9a3`,
preflight identify clean (`asdfg` SDSC 960MB, SN `$0000_01F4`, detuned SPI
21_875_000 Hz per its class), sweep-start fsck **clean, nothing to reclaim**.

**TOTAL 532/534, 2 failing suites, and the closing audit flagged 2 repairs.**
Observations only — classification is the container's:

1. **`SD_RT_register_tests` #11** (`readCIDRaw() returns valid CID`), sub-check
   "CRC7 stop bit set": got 0, expected TRUE. The card's CID final byte has
   bit0 (the spec's always-1 stop bit) = 0. PNM bytes read `asdfg` as always.
   Log `tools/logs/SD_RT_register_tests_260819-180853.log` (~line 91).
2. **`SD_RT_speed_tests` #8**, sub-check "capable card that did not switch
   reports an error": got 0, expected TRUE. The two capability paths DISAGREE
   on this card: #6 `checkCMD6Support()` (SCR spec version) = 0 not supported;
   #7 `checkHighSpeedCapability()` (CMD6 inquiry) = -1 CAPABLE; attempt = FALSE
   with ERROR() = 0 (clean-decline path). The #8 invariant assumes the two
   answers agree; this counterfeit answers a CMD6 inquiry affirmatively while
   its SCR says SD 1.x. Log `tools/logs/SD_RT_speed_tests_260819-180858.log`
   (~line 75).
3. **Closing audit `STATUS: REPAIRS NEEDED`** (hard blocker per harness):
   Pass 2 "ERROR: Bad ref 0 in chain" + "chain runs past the file size at
   cluster 19"; Pass 4 FSInfo free count off by one (says 244252, actually
   244253 — consistent with one over-hanging cluster). 23/23 structural checks
   pass, FATs in sync, no lost clusters. Dirs: 1, Files: 1 (audit does not name
   the file). Sweep-start was clean and the harness reformatted twice
   mid-sweep, so the state was created DURING this sweep, after the last
   reformat (suites 14-27 window; defrag_tests ran last).
   Log `tools/logs/SD_FAT32_audit_260819-181101.log`.
4. **Comparator:** the identical roster on Amazon Basics `$3584_1E2E` earlier
   today ended 534/534 with a CLEAN closing audit (`sweep_260819-155926.txt`).
5. Cosmetic, noted in passing: test-side human debug lines still use the
   doubled-sigil style (`CID: MID=$$5` in the register failure dump) — human
   lines only, not machine lines.

**EVIDENCE PRESERVED: fsck was NOT run; nothing was repaired; the Lerdisk
remains SEATED in the Edge socket untouched.** The over-long chain, its dir
entry, and the unnamed file are still on the card for any forensics the
container wants before repair/reformat.

**State at pause:** steps 0 ✓, 1 ✓ (534/534), 2 deferred, 4 run with the above,
5-6 not started. Tree clean. Bench resumes on container hand-back.
