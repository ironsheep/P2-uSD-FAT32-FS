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
| **H1 · Edge wedge** | ✅ built — probe rebuilt (heavy cycle + identity print). **Bench: round 11a**, and it is a GATE: if it still does not reproduce, stop, do not run the ladder | bench | no |
| **H2 · High-speed performance** | ✅ built — write verification in the benchmark, and `-D HS_PAD_SWEEP` for the hp=4 pad. **Bench: rounds 11b + 11c** | bench | no |
| **H3 · Catalog integrity** | Decisions settled. Build the instruments (version stamp, silicon key, table format); the sweep populates the tables | container, then bench | no |
| **H4 · Release** | Doc pass ✅ mostly done (see head). Remaining: PERFORMANCE §8 final numbers, plan §11 append — both want round 11 data | container | version number: **yes — H1** |

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
- [x] **Correction:** the `-7` unmount is INTERMITTENT (`-7`, `-7`, `0`), not a stable new behaviour. Round 9's "free discriminator" claim was wrong; todo #3265's instrumentation is still needed

### Known reproducer

`SD_RT_mount_tests` → `SD_RT_raw_sector_tests`, **no power cycle between**, Edge
socket. Wedge is invariant: `mount()` #2 returns `-8`, raw init then fails.

### Next

1. **Rebuild the probe.** Three gaps, all mine: workload far heavier than
   mount/512B-write/unmount; the **cross-binary transition** (two downloads, no
   power cycle) which the probe never exercises at all; and printing card
   PSN/PNM so a null result is interpretable without a separate identify run.
2. Re-establish reliability — is the wedge deterministic once the probe bites?
3. Then and only then the ladder: 400 kHz (decisive — nothing about edge rates or
   setup/hold survives there), then read-only (splits write-burst from protocol).
4. Bench-supply swap if the write burst is implicated.

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
- [x] The write slowdown is **uniform, not occasional**: PNY min/avg/max went 2,601/3,599/12,303 µs → 9,631/9,966/11,213 µs. The *best* case got 3.7× worse while the worst case improved

### Open questions

- **Slower, or corrupt?** The benchmark does **not verify what it writes** — no readback, no compare. Zero errors means no *rejections*, not no *corruption*. Round 7b's tx tooth produced exactly this kind of silent whole-sector corruption, so it cannot be ruled out by this data.
- **The hp=4 hole.** 43.75 MHz is hp=4. The `tx_align_delay` tooth was mapped at hp 5, 7 and 14 only; hp=4 has never been characterised on the **write** side. The read side was measured in 9c — but in *default* mode, not inside high-speed mode, which is a different card state.
- **What policy replaces "always negotiate"?** Candidates: asymmetric (high speed for reads, standard for writes), per-card gating, or negotiate-then-measure.

### Reading of the evidence, held loosely

The uniform slowdown with a *tightened* distribution and zero rejections is the
wrong signature for a phase/tooth fault, which produces variance and corruption.
It looks more like these controllers genuinely behave differently for writes once
CMD6 high speed is engaged. **But the unverified-write gap means this reading
cannot be trusted yet** — that is why write verification is this head's next
action rather than the tx pad sweep.

### Next

1. **Write-verification arm in the benchmark.** Gates the interpretation of
   everything above. Until it exists, "slower" and "corrupt" are indistinguishable.
2. `tx_align_delay` sweep at **hp=4, inside verified high-speed mode**.
3. Read-side: phase sweep at hp=4 **inside high-speed mode** — 9c measured
   default mode only, so the floor-cell exemption is still undecided.
4. Then choose the adaptation policy and implement it.

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
