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

| Head | Next action | Where | Blocked? |
|---|---|---|---|
| **H1 · Edge wedge** | **13a/b/c** narrow what a "prior session" leaves behind. Deterministic reproducer in hand at last | bench | no |
| **H2 · High-speed performance** | Nothing at the bench. **Decide the read/write asymmetry policy** — correctness is established | container | no |
| **H3 · Catalog integrity** | Build instruments to emit the new format; run variance before instance variance | container | no |
| **H4 · Release** | §8 numbers can be written now. Version still depends on H1 | container | version: **yes — H1** |

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

- [x] 🔑 **DETERMINISTIC REPRODUCER (12a).** Cold — first binary after power-on — is **clean 4/4**. Warm — any prior session, no power cycle — **wedges 2/2**. Power clears it. Demonstrated in both directions in one sitting
- [x] **The `-7` was never noise.** Split by condition: every warm run gives `-7`, every cold run gives `0`. One earlier `0` on a wedged run remains unexplained
- [x] **Bad-pin prefix POSITIVELY ELIMINATED** — those calls execute in the four clean cold runs too. A path that runs identically in clean and wedged runs cannot be what distinguishes them. My hypothesis, refuted by their data before a run was spent on it
- [x] **Cross-binary boundary eliminated in its literal form** — no boundary is crossed before the wedge fires at test #13
- [x] The predecessor does not need to be a *different* program: one wedging run's predecessor was the identical `mount_tests` binary

### What survives, and the constraint that shapes round 13

What is left is **card or pin state that persists across a P2 reset and is cleared
only by power**. But "prior driver session" is not by itself the trigger: the
wedge probe runs eight mount/operate/unmount cycles inside one power-on and stays
clean every time, so cycles 2-8 are all "after a prior session" without wedging.

The difference is the **reset window** — roughly a second in which the P2 drives
nothing and the card sits with CS floating and unclocked. No in-binary cycle ever
creates that condition. Round 13a separates the two by using a **non-SD binary**
as the predecessor: if that wedges, no driver session is required at all and the
trigger is the reset itself.

**Superseded hypotheses, kept so they are not re-proposed:** Round 11's hand-back
proposes the **cross-binary boundary** — the reproducer is two downloads with a
reset between them, the probe is one binary looping. But the wedge fires at
**test #13 inside `mount_tests`**, before any boundary is crossed, which argues
the trigger is in that suite's own prefix — most conspicuously its two
**deliberately-wrong-pin `mount()` calls**, which the probe has never made.

Nobody has run `mount_tests` alone from a cold power-on, so the two are still
unseparated.

1. **13a** — non-SD binary as predecessor. Separates "driver session required"
   from "the reset itself".
2. **13b** — does a 120 s wait clear it, or only power? Latched state versus a
   process completing. These cards are documented as re-busying themselves for
   garbage collection after CS deassert, and the driver's init busy-poll gives up
   after ~2 s and proceeds regardless — so this outcome would make it
   driver-fixable.
3. **13c** — read-only prior session: must the predecessor have written?
4. Then the ladder (400 kHz, read-only), which is finally meaningful now that a
   reproducer exists.
5. Bench-supply swap if the write burst is implicated.

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
- [x] **Stephen's call:** hold for an Edge fix. With a fix it may ship as **v1.8.0**; without one it ships as **v1.7.1**. A card-location restriction is not acceptable as a shipped limitation
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
