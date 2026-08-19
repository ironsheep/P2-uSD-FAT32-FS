# Research Heads — Live Status

**Purpose:** one page that answers, for every thread of work in flight: where are
we, what is settled, and what is next. Updated every pass. The top section is the
only part that changes fast — it is what we read before a bench run.

**How to use it:** heads advance in parallel. A bench session pushes every head
that has a bench-side action queued; container-side actions proceed between
sessions. Settled findings move down into each head's running list and stay
there, so the history accumulates without cluttering the decision surface.

**Last updated:** 2026-08-18, container work for H1 and H2 complete; round 11 queued.

**Round 11 run sheet:** `DOCs/Plans/SOCKET-SHMOO-RUN-BRIEF.md`, section ROUND 11.
Card selection is coordinated there — 11b and 11c are meaningless on a card that
cannot negotiate high speed, so they run only on the Lexar Red, Samsung EVO and
PNY (the three round 9d confirmed); the SanDisk MAX Endurance declines and the
two counterfeits are 11a's subject.

---

## ⟹ NEXT UP — what each head needs

**Release is now v1.8.0** (Stephen, 2026-08-19). Scope grew from a patch to a
root-caused fix for a months-old defect plus a public API contract change.

| Head | Next action | Where | Blocked? |
|---|---|---|---|
| **H1 · Edge wedge** | ✅ **Root-caused and FIXED.** CMD12 quiesce is unconditional in `initCard()`. Needs full regression to certify | bench | no |
| **H3 · Catalog integrity** | 🔴 **RELEASE GATE.** Full catalog performance sweep — tomorrow's effort. **v1.8.0 does not ship before it** | bench | no |
| **H2 · High-speed performance** | Decide the read/write asymmetry policy | container | no |
| **H4 · Release** | Blocked on H3's sweep, not on H1. Then doc close-out and tag | container | **yes — H3** |

**Stephen's release conditions (2026-08-19):**
1. The quiesce runs **on every driver start**, not gated behind a flag.
2. **Nothing ships until a new full catalog performance sweep** has been run — the
   sweep is a release gate, not a nice-to-have.

**A method rule this campaign has now paid for twice — measure in the state that
ships, not the state that is convenient.** Reference-content aliasing (round 6)
and the hp=4 band (round 9c vs 12d) each produced a confident conclusion that
inverted when re-measured properly, and each cost a hand-back item that had to be
withdrawn. Any measurement that reaches its target by a shortcut — setting a clock
instead of negotiating, using a uniform test pattern, reading back at a different
speed than the write — states which state it was taken in, or it does not count.

**Decisions SETTLED by Stephen, 2026-08-18:**

1. **Keep both instruments, as two tables named by the question each answers** —
   "card capability (random access)" and "driver throughput by traffic type".
   They measure different things: on random reads the cards spread ~38x; on
   sequential multi-block they nearly converge, because the bus does the
   limiting. **Random access separates cards; the benchmark separates drivers.**
   Limiter attribution goes only on the benchmark table — the random-read metric
   is CARD-bound for every card by construction, so it has one constant answer.
2. **Pristine tables. One banner naming the driver version; no per-row
   provenance, no exception table.** Rationale (Stephen): a full re-sweep of
   every working card is *one afternoon* of bench time, so the mixed-provenance
   state is transient and not worth building machinery to describe. Re-sweep on
   any release that touches the I/O path.

**Consequences adopted with them:**
- Rows are **per instance**, keyed by full Card ID, **grouped by silicon key** =
  `MID_PNM_PRV` (e.g. `Phison_SD16G_3.0`). This is not a new scheme: it is
  already the prefix of every existing Card ID, just never named or used to group.
- Controller-family aggregation is shown as **range + count, never average** —
  an average over a family hides the spread, which is the actual purchasing
  insight.
- **Register/identity data is exempt from all of this.** It is a card property,
  it never stales when our driver changes, and it needs no provenance. Only
  performance data is driver-dependent. (This is why no "unmeasurable rows"
  table is needed: the SU01G has full register data but zero throughput
  measurements, so it never appears in a performance table at all.)
- **Do not hand-restructure the existing tables** — the sweep replaces every row.
  Define the format, build the instruments to emit it, populate from sweep output.

**Buying-guide caveat, to carry into whatever the catalog publishes:** the
property stratifies by something a buyer cannot see before purchase. MID/PNM/PRV
live in the CID register. Brand does not predict controller — Gigastone-branded
cards in our own drawer carry three different MIDs — and SKUs get silently
re-sourced between production runs. So the honest form is "these specific cards,
purchased then, measured this", never "buy brand X".

---

## H1 · The Edge-socket wedge

**Question:** why do two recently-purchased cards work in the external adapter
and fail in the P2 Edge module socket?

**Status:** blocked on our own instrument. The wedge is real and still live, but
the probe built to study it does not trigger it.

**Why this head is shaped as intervention, not measurement:** the Edge module
socket cannot be probed — no logic analyzer access, physically. Only driver-side
changes plus one hardware lever (swap the USB 5 V feed for a bench supply). The
reproducer is therefore the instrument, and its reliability has to be established
before any intervention result can be believed.

### Settled

- [x] Not read alignment — the v1.7.1 mitigation bundle changed it; the wedge is unchanged (9a)
- [x] Not raw single-sector writes — ~336 write cells across four cards, zero wedges (round 5)
- [x] Trigger lives in the **filesystem/mount path**, not raw sector access (round 5, Finding 1)
- [x] Not socket-agnostic — external adapter is 8/8 clean under the same probe (10c step 1)
- [x] The twins are indistinguishable: identical counts, codes, failure point (9a)
- [x] `SD_edge_wedge_probe`'s cycle is **too gentle** — 8/8 clean on Edge while the 9a suite pair wedged the same card minutes later (10c)
- [x] **Correction:** the `-7` unmount is INTERMITTENT — tally now `-7`, `-7`, `0`, `-7` across four runs. Round 9's "free discriminator" claim was wrong; todo #3265's instrumentation is still needed, and must run enough repetitions to see both outcomes
- [x] **"Not enough work per cycle" is largely eliminated** (11a). The rebuilt probe does a real ~1,120 ms FAT scan, double-mount and file create/write/read/delete per cycle and still returns 8/8 clean while the suite pair wedges the same card 40 s later
- [x] The probe now prints its own card identity, so a null result stands without a separate identify run

### Known reproducer

`SD_RT_mount_tests` → `SD_RT_raw_sector_tests`, **no power cycle between**, Edge
socket. Wedge is invariant: `mount()` #2 returns `-8`, raw init then fails.

### Next

- [x] ⛔ **NO RECOVERY EXISTS (14a).** Five rungs — two plain re-inits, then 102,400 clocks in *each* CS polarity with a re-init after each — every one returned `-8`. The driver can **detect** the wedge but cannot repair it. This was the path that would have unblocked the release without a root cause, and it is closed
- [x] **`initCardOnly()` ALONE arms it (14b)**, with the `P_NOTHING` control clean. The entire filesystem layer, the unmount, the FSInfo update and the cog shutdown are all exonerated. The space collapses to card initialisation
- [x] **Float after a driver session: 8/8 clean (14c).** My CMD0-latch / floating-CS hypothesis is refuted. Both float orders are now eliminated, and pin-state mechanisms should not be re-proposed without something new to distinguish them
- [x] 🔑 **DETERMINISTIC REPRODUCER (12a).** Cold — first binary after power-on — is **clean 4/4**. Warm — any prior session, no power cycle — **wedges 2/2**. Power clears it. Demonstrated in both directions in one sitting
- [x] **The `-7` was never noise.** Split by condition: every warm run gives `-7`, every cold run gives `0`. One earlier `0` on a wedged run remains unexplained
- [x] **Bad-pin prefix POSITIVELY ELIMINATED** — those calls execute in the four clean cold runs too. A path that runs identically in clean and wedged runs cannot be what distinguishes them. My hypothesis, refuted by their data before a run was spent on it
- [x] **Cross-binary boundary eliminated in its literal form** — no boundary is crossed before the wedge fires at test #13
- [x] The predecessor does not need to be a *different* program: one wedging run's predecessor was the identical `mount_tests` binary

- [x] **A driver session IS required** (13a): a 49.7 KB binary that touches no pin, download-size-matched so its float window is *longer*, is clean 2/2
- [x] **The state is LATCHED** (13b): 120 s of powered idle still wedges. The garbage-collection model is refuted, and so is any fix resting on "wait longer in init"
- [x] **Writes are irrelevant** (13c): a read-only predecessor with FSInfo suppressed still wedges. Filesystem state exonerated — what persists is **controller state, not data**

### The condition, as bounded after round 13

**A driver session that touches the SD pins (reads suffice), then a P2 reset, then
another driver session. Latched in the card; cleared only by removing power.**

### 🔑 FIX PROVEN (round 15b): CMD12 quiesce before CMD0

**Five clean warm runs across two power cycles, each pair followed by the
unmodified build run warm on the same card with no power cycle — which wedged both
times.** So neither pair can be explained by the wedge having gone quiet, which was
the failure mode the brief specifically warned about.

Switches were left in the **wedging** configuration throughout, so the boot
sequence ran exactly as it does in the failing case. **CMD12 does not prevent the
boot-time conversation; it aborts the data-transfer state that conversation leaves
behind.** A card mid-transfer is streaming, not listening — CMD0 sent into that
stream is data, which is precisely the observed `E_NO_CARD` after five retries.

It is also the retrospective explanation for round 14a: a multiple-block read
continues until told to stop, so 102,400 extra clocks only fed it. The ladder never
sent the one command that would have reached the card.

**Verification gap, now closed for future runs.** The two builds differ by 20 bytes
and the captured log recorded neither the size nor any marker — the debug line was
`DEBUG[CH_INIT]`, which `mount_tests` compiles out. Nothing in the transcript
distinguished a quiesce build from a plain one; the result rests on the interleaved
controls, which is strong but should not have been necessary. The step now prints
unconditionally while it remains an experimental arm.

### 🔑 ROOT CAUSE FOUND (round 15a): boot-time SD access

**The card is wedged before our first instruction executes.** With boot-time SD
access disabled (`P59 = up`), four consecutive warm runs came back clean; the wedge
returned immediately when the switches went back. Toggled in both directions in one
session, on one card — deliberately, because this campaign has already produced two
conclusions that inverted under re-measurement.

That resolves the standing paradox. A reset was necessary, yet both of its
card-visible effects were refuted; the third thing a reset does is **run the boot
sequence**, which on this board talks to the SD card at RCFAST before any user code
runs. It also explains round 14a: no recovery rung worked because the driver never
had a chance.

### Attribution — the bench's own data already answers half of it

The hand-back lists the culprit as *either* the boot ROM's SD conversation *or* the
flash-resident program, and proposes running **P61 up + P59 float** to separate
them. **That configuration is the one that has been wedging all along** — switches
`1-2 up, 3-4 down` are exactly P61 up with P59 floating, and SD boot is not in that
boot pattern at all.

**So the ROM's *SD-boot* path is already exonerated.** It never ran. But that
leaves two candidates, not one, and the second is not in the hand-back's list:

**(a) The ROM's *flash* traffic on shared pins.** On the Edge, P58-P61 are shared
between flash and microSD **with CLK and CS swapped**:

| Pin | Flash role | microSD role | Our driver |
|---|---|---|---|
| P60 | **CLK** | **DAT3/CS** | CS |
| P61 | **CS** | **CLK** | SCK |

So while the ROM reads flash, our card sees **its own chip-select toggling at flash
clock rate** with data on MOSI — repeated spurious selections. This happens on every
flash boot, and it is a general P2 Edge exposure, not specific to this bench.

**(b) The flash-resident program** (`* Hi! from FLASH *` — not ours; it appears in
`src/DEMO/logs/` transcripts from March) touching the SD card itself.

The distinction matters enormously for the release: **(a) affects every Edge board
with flash boot enabled; (b) is an artefact of what happens to be in this board's
flash.**

### The discriminator that actually separates them

Not a boot-pattern change — **replace or erase the flash program**, keeping flash
boot ON. Wedges still → (a), the ROM's flash-interface traffic. Clean → (b), the
program.

Cheaper still, and it costs no bench time: **ask what is in flash.** If it is a
hello-world that never touches the SD pins, (a) is the answer by elimination.

**Superseded hypotheses, kept so they are not re-proposed:** Round 11's hand-back
proposes the **cross-binary boundary** — the reproducer is two downloads with a
reset between them, the probe is one binary looping. But the wedge fires at
**test #13 inside `mount_tests`**, before any boundary is crossed, which argues
the trigger is in that suite's own prefix — most conspicuously its two
**deliberately-wrong-pin `mount()` calls**, which the probe has never made.

Nobody has run `mount_tests` alone from a cold power-on, so the two are still
unseparated.

1. **14a — can a wedged card be RECOVERED without power?** Never asked. "Only a
   power cycle clears it" describes the two things anyone happened to try, not a
   tested claim. **If any rung of the recovery ladder works, the release stops
   depending on root cause** — the driver detects and repairs instead.
2. **14b — float the pins after a driver session, no reset.** Round 13a floated a
   *virgin* card; the order was never varied. Candidate mechanism: CMD0 latches
   the card into SPI mode until power loss, and a card in SPI mode reads a
   floating CS very differently from one still in native SD mode. That single
   mechanism fits every row of the table above.
3. **14b — bisect the predecessor.** `SD_wedge_predecessor` runs one rung of
   activity, download-size-matched to the reproducer within 22 bytes. The smallest
   rung that still wedges names the trigger; everything above it is bystander.
   Watch `P_INIT_STOP`: `stop()` halts the worker cog with `COGSTOP`, and a
   stopped cog releases its DIR bits, so **the pins go high-Z there — a float
   window inside a running application, no reset involved.** If that rung wedges
   while `P_INIT` does not, the driver has a defect it can fix by parking the pins
   before halting the cog.
4. **14c/d — the same float with CS held high.** If CS is it, a board-level pull-up
   is a fix needing no driver change.

### Why prevention alone can never be the answer

A user can reset the board at any moment, including mid-transaction, so no
tidy-up-at-unmount can be relied on to have run. **Recovery at mount is therefore
mandatory regardless of what causes the wedge** — which is why 14a leads. A
prevention measure (parking pins at `stop()`, a CS pull-up) reduces incidence and
is worth having, but it cannot close the defect on its own.

### What the SD specification says (checked 2026-08-19, `DOCs/Specs/`)

The Physical Layer Simplified Specification v9.10 is in the tree, so three things
that were assumptions are now quotations.

**1. SPI mode is entered by CS-asserted CMD0 and exited only by power** — §7.2.1,
verbatim: *"The only way to return to the SD mode is by entering the power cycle."*
So `unmount()` cannot return the card to SD mode; no command does. This does not
explain the wedge by itself (the mode is entered on cold runs too, which are
clean), but it does mean "cleared only by power" is the expected shape for
**anything** latched in SPI mode, and it closes the question of whether a tidy-up
at unmount could sidestep the problem. It cannot.

**2. The card carries an internal 50 kΩ pull-up on CS, and it is host-controllable
via ACMD42** (`SET_CLR_CARD_DETECT`): *"Connect[1]/Disconnect[0] the 50 KOhm
pull-up resistor on CS (pin 1) of the card."* **Our driver never sends ACMD42** —
checked; it uses only ACMD13, ACMD41 and ACMD51 — so the pull-up stays in whatever
state the card powers up in. On a conforming card that is *connected*, which would
hold a floating CS high and make the float window harmless. On counterfeit silicon
it is exactly the kind of detail that may not be implemented.

**3. The spec states the principle directly**, for UHS-II but as a general host
obligation: *"Host shall not leave these unused lines floating, but keep them at a
defined high or low level."* Our `stop()` leaves all four SD pins floating, and a
P2 reset does the same for about a second.

### An unprobeable question that turns out to be readable

We cannot put an analyser on the Edge socket — but the P2 can read its own pins.
Floating CS with `pinclear()` and then sampling `pinr()` measures whether anything
is actually pulling that line up, which is a **card-side property measured from the
host side**, needing no probe access at all.

If CS reads high and stable during the float, the card's 50 kΩ pull-up is working
and a floating CS is not the mechanism. If it reads low, or drifts, then a floating
CS is a *selected* card and the whole float hypothesis gains a physical basis.

**Queued as an instrument change for the round after next** — the wedge probe is in
the bench's hands for round 14 and must not change underneath it.
4. Then the ladder (400 kHz, read-only), finally meaningful now a reproducer exists.
5. Bench-supply swap if anything points back at power.

### Parked

- Replacement non-`asdfg` SDSC card, to test whether this is counterfeit-specific or SDSC-class-wide (the Kingston 2GB that would have answered this is dead)

---

## H2 · High-speed performance and driver adaptation

**Question:** CMD6 high speed gives a 75% clock increase. What does the driver
have to do to turn that into real performance — and where does it hurt?

**Status:** the naive plan is dead; the interesting version is alive.

### Settled

- [x] **3 of 4 modern controllers negotiate high speed** and hold it at 43.75 MHz (9d). `SD-CARD-PERFORMANCE.md` §7's "fails on all tested cards" is falsified
- [x] SD 1.x counterfeits decline cleanly, `ERROR() = 0` — the honest-boolean contract works on a card that genuinely lacks the feature (9d)
- [x] **Reads gain on all three cards tested, up to +47%** (10b)
- [x] **Writes regress on two of three, worst −64%** (10b) — reproduces across several traffic types within each affected card
- [x] Blanket auto-negotiate-at-mount is therefore **not viable** — it would hand most cards a large write regression
- [x] **The writes are byte-CORRECT at high speed** (11b) — 24 verify checks across three cards and both arms, all clean. Slow, not corrupt
- [x] **The hp=4 write pad is mapped** (11c): teeth at `≡ 2 (mod 4)`, i.e. pads 2/6/10. **The shipped default of 4 passes**, two pads clear either side. The pad is not the cause of the slowdown
- [x] **CORRECTION to 10b:** writes regress on **one of three** cards, not two. The PNY's −64% did not reproduce — its standard-arm numbers moved up to 3× between rounds while its high-speed numbers repeated to 0.3%, and it shows 6× dispersion inside a single measurement loop. Card variance, not a bus effect
- [x] The hp=4 write corruption is **bit-smearing** (`exp | exp>>1`), the opposite of the read path's true one-bit shift with carry-in. Different path, different mechanism — do not conflate them

- [x] **The hp=4 pad map now covers three cards** (12c): two controllers share residue `≡ 2 (mod 4)`, the third expresses no tooth, and **pad 4 passes on all three**. Off n=1
- [x] 🔑 **The hp=4 exemption is LOAD-BEARING** (12d), measured inside high-speed mode: band `[-3..+4]` on two cards, `[-1..+5]` on the third. The rule's offset 0 is inside on all three and dead centre on two; **the shipped +5 is outside the band on two of three**. Round 9's recommendation to delete the rule is withdrawn — it was based on a sweep that set the clock instead of negotiating, and the band sits three ticks higher in that state
- [x] Independent confirmation, by accident: an instrument that lifted the rule before negotiating put `align = hp + 5` on the CMD6 verify read; that verify failed on the Lexar and the driver correctly refused a mode it could not verify

### Open questions

- **What policy replaces "always negotiate"?** The only one left, and it is a product question rather than a safety one. Reads gain up to +47% on every card; writes are byte-correct but no faster, and one card of three is reproducibly slower. Candidates: asymmetric (high speed for reads, standard for writes), per-card gating, or negotiate-then-measure.

### That reading held up

The signature argued against a phase fault and for card-side behaviour. Both
follow-ups agreed: writes verify byte-clean, and the pad at hp=4 is two clear of
the nearest tooth. The one reproducible regression (Samsung, −52%) is card-side
behaviour in high-speed mode.

### Next

**Nothing at the bench.** Choose the adaptation policy — that is a design
discussion, not a measurement.

---

## H3 · Catalog and measurement integrity

**Question:** the catalog measures *our driver* against good cards. Does it
currently say anything trustworthy?

**Status:** partly repaired; the structural fix is blocked on two decisions.

### Settled

- [x] All 26 card records carry a `**Label:**` line — capture was careful, propagation was not
- [x] Labels enriched, never truncated: the counterfeit/PNM/twin detail and the Kingston's trailing `F(c)o` now agree across record and reference
- [x] `CARD-REFERENCE.md` was missing two cards entirely (Cloudisk 2GB, SanDisk SU01G) — added; 26 entries now match 26 records
- [x] Label column added to **both** `CARD-CATALOG.md` tables
- [x] **The throughput table mixes instruments under one heading.** Some rows are `SD_speed_characterize` (10,000 *random* reads), others are `SD_performance_benchmark` (10 iterations, one fixed sector). Proof in one card: SanDisk MAX Endurance carries both 951 and 998 KB/s in its own record
- [x] **And it may mix reads with writes** — PNY's 31.3 KB/s baseline does not match its measured 701 KB/s read; nearest match is a *write* metric (10b)
- [x] Six cards have data that never reached the summary, including **the Blue Lexar — our fastest card at 1,196 KB/s**, absent entirely
- [x] Three table dialects across eras for the same measurement
- [x] **No provenance anywhere** — no driver version constant, no version stamped in benchmark output, most measurements predate v1.6.0 and v1.7.0

### Consequence to carry into every write-up

Comparing a new benchmark number against a catalog row can show a large **fake**
gain that is purely an instrument change. Always compare same-instrument; a
same-session standard-speed arm is the only safe comparator.

### Next

1. **Stephen's two decisions** (top of page)
2. Restructure into clearly-named per-instrument tables, each row carrying date + driver-commit provenance
3. Add the six missing cards; fix the card count (26, not 23)
4. Add a driver version constant and stamp it into benchmark output
5. Confirm whether PNY's 31.3 is a write metric
6. Resolve the Samsung EVO serial discrepancy — catalog row says PSN `C0305565`, its record says `4AC85F42`, round 9 measured `$4AC8_5F42`. Two units, or a transcription error? It is a benchmark card, so it matters

### ⚠ Design change forced by round 11b

The planned noise-floor experiment — 5 instances of one Gigastone model — assumed
**run-to-run** variance was small enough to ignore, so that differences between
instances could be read as instance variance. Round 11b refutes that assumption:
the PNY's standard-arm write numbers moved by up to **3x between rounds on the
same physical card**, with 6x dispersion inside a single measurement loop, while
its high-speed numbers repeated to 0.3%.

**So run variance must be measured before instance variance.** Repeat one card
several times first; only then does comparing five instances mean anything.
Without that, the instance experiment would attribute run noise to units.

Two smaller consequences for the sweep: measurement **order** may matter (the
first run of a card can differ from later ones), and any card showing wide
dispersion needs repeat runs before any delta is believed.

### Bench-side items

- [ ] **Full characterization of the Blue Lexar** (Lexar PLAY A2 128GB) — Stephen's request. Its number is our most exposed row: 2026-02-14, driver commit `797f913`, predating v1.6 *and* v1.7. Note for the write-up: A2 buys command queuing and caching, which are **SD 4-bit bus features** and unreachable in SPI mode, so it may measure flat despite being the more capable card. Its record also carries a CMD6 failure at 27 MHz from before the verify rework
- [x] Kingston-labelled 2GB — **dead** (no init in either socket, runs hot). 10a closed without an answer

---

## H4 · Release

**Question:** what ships, as what version, and when?

**Status:** certified and held, by decision.

### Settled

- [x] v1.7.1 mitigation bundle certified: 530/530 (round 8a run 3), closing audit clean
- [x] 532/532 on a second geometry — 119GB, 64 sectors/cluster (round 9e)
- [x] **Stephen's call:** hold for an Edge fix. With a fix it may ship as **v1.8.0**; without one it ships as v1.7.1. A card-location restriction is not acceptable as a shipped limitation
- [x] **RESOLVED 2026-08-19 — the fix landed, so it is v1.8.0.** The card-location restriction is going away rather than being documented
- [x] T1/T2 style-audit deferral recorded in `RELEASE-CHECKLIST.md` §2 in Stephen's words — settled, do not re-raise

### Open

- Two `run_regression.sh` timeout budgets are tuned to a 32GB card and do not clear a 119GB one (`mount_tests` 120s, `read_write_tests` 90s). Harness assumption, not a driver defect
- Regression total is now **532**, not 530 — a run reporting 530 is a stale binary

### Doc pass — done 2026-08-18

- [x] `SD-CARD-PERFORMANCE.md` §7 — the "CMD6 fails on all tested cards" claim **corrected**. It was a user-facing factual error, so a release-gate item
- [x] `SPI-PHASE-MARGIN-API.md` — align offset default (0 → +5) and range (`[-8,+16]`), the hp=4 floor-cell rule, both new guard-lifting knobs, and the five-card tooth survey that revised the single-card v1.7.0 characterization
- [x] `SD-CARD-DRIVER-THEORY.md` — production speed bound, why high speed is 43.75 MHz and not 50, why `isHighSpeedActive()` reports mode not clock, the four exits from high-speed mode, and the align default moving to the band centre
- [x] `CHANGELOG.md` — drafted under `[Unreleased]` since the version number depends on H1. Themes, the breaking `isHighSpeedActive()` contract change, and the doc correction
- [x] `README.md` **and** `.release/README.md` — the same falsified CMD6 claim in Known Limitations, plus both socket-timing notes updated to say read margin is now equalised **without** implying the socket-dependent wedge is fixed, because it is not

### Still open

- `SD-CARD-PERFORMANCE.md` §8 final numbers and the plan §11 append — both want round 11's data, so writing them now would mean rewriting them

### Next (all container-side, mostly unblocked)

1. Doc pass: `SD-CARD-DRIVER-THEORY.md` (frequency/clamp + tooth mechanism), `SPI-PHASE-MARGIN-API.md` (tooth map + the two new debug knobs), `SD-CARD-PERFORMANCE.md` §8 numbers and the **§7 CMD6 correction** — now quantitative thanks to 9d and 10b
2. Changelog — themes: broader card support, equal socket support (both measured). **Must include the `isHighSpeedActive()` public contract change**
3. READMEs — both sets, including the `.release/` shadow copies
4. Append rounds 5–10 to the campaign plan §11
5. Release gate

---

## Parked heads

- **4-bit (4-wire) SPI support.** Stephen's stated next major driver capability. It quadruples the bus ceiling, so it helps only cards already pressed against the 1-bit wall — which is exactly what H3's limiter attribution is designed to predict, per card, before the work starts.
