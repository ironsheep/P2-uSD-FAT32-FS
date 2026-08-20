# Round 16 — Bench Run Sheet

**One ordered pass. Read this; the campaign record is
[SOCKET-SHMOO-RUN-BRIEF.md](SOCKET-SHMOO-RUN-BRIEF.md) and you only need it for
background on a step.**

**Goal:** certify v1.8.0 and produce a catalog measured on the driver that ships.
**Gate:** nothing ships until step 6 (the catalog sweep) has run.

All commands run from `tools/`.

---

## Handoff protocol — bench pauses, container changes, bench resumes

Set 2026-08-19. **The bench agent never edits source.** It observes, pauses, and
hands back; the container agent makes every change and writes the resume below;
the bench agent picks up from there. The two share one working tree, which is why
the rules are specific.

### Who owns which files

| Path | Owner | Bench may edit? |
|---|---|---|
| `src/**`, `diagnostic-tests/**` | container | **never** |
| `DOCs/Plans/SOCKET-SHMOO-RUN-NOTES.md` | **bench** — it is the bench's output | yes, freely |
| `DOCs/Plans/ROUND-16-RUN-SHEET.md`, other plans, `tools/**` | container | no |
| `tools/logs/**` | bench | yes (gitignored) |

### Pristine tree

**A run starts from a committed tree, every time.** `run_regression.sh` enforces
this and has already caught it once — the bench aborted a sweep in the compile
phase because uncommitted notes made the banner unprovable. That abort was
correct behaviour, not a mishap.

So the bench's order is: **write notes → commit notes → start the run.** Never
write notes while a run is in flight and never during a pause that the container
is about to act on. `git status --short` must be empty when the container picks
up, because a container editing around unknown modifications is the fastest way
to lose an afternoon.

Build artifacts (`*.bin`, `*.p2asm`, `logs/`) are gitignored, so compiling and
capturing never dirties the tree. Pristine is achievable, which is why it is
required.

### Hard stop — pause and hand back, do not continue

**Any of these, immediately:**

1. **Any regression test failure.** Zero tolerance; no failure is "pre-existing".
   Continuing past one runs every later suite on an uncertified driver.
2. **Anything that would require editing source to proceed** — including a CON
   value a step seems to want changed. Hand back and ask; the container makes it
   a build-time option instead.
3. **Data corruption anywhere** — a verify mismatch, `CONFIRMED WRITE CORRUPTION`,
   a CRC error that is not the card's documented dummy-CRC quirk.
4. **An instrument contradicting its own documented behaviour** — a landed clock
   that differs from the request, a key line that does not match the canonical
   form, a count that cannot be reconciled. The instrument may be lying, and a
   lying instrument invalidates everything measured after it.
5. **A card wedging or needing an unplanned power cycle.** That is #3240's
   signature and it is supposed to be fixed.
6. **A step's precondition failing** — `check_doc_version.sh` non-zero, the source
   SHA not matching the resume, a card that will not identify.
7. **Anything irreversible about to happen on incomplete information** — most
   sharply, a one-shot card being measured or deployed before its identity is
   captured. Those transcripts cannot be recreated.

**Continue and record (not a stop):** a card cleanly declining high speed; run-to-run
variance; a documented dummy-CRC card scoring zero CRCs. These are outcomes, not faults.

### The judgement calls that are NOT the bench's

Diagnose freely and recommend — the round 16a analysis was exactly right and saved
a cycle. But the **decision** stays with the container: whether a failure is
test-side or driver-side, whether an expected value may change, and whether a
finding blocks the release. Those are judged against source and documented
contract, not against output.

**When the bench pauses, it hands back:**

1. **A clean tree, or an exact statement of what is dirty.** `git status --short`
   in the handback.
2. **The observation, not the verdict.** Exact suite, exact test name, expected vs
   got, and the surrounding transcript lines. **Do not pre-classify a failure as
   "a test bug"** — test-side versus driver-side is the judgement that decides
   whether something is a quick fix or a release-gate finding, and it is made
   against the source and the documented contract, not against the output. A
   failure called test-side and patched away is how a false green is born.
3. **Which steps of this sheet completed**, and their results.

**When the container hands back, the resume below states:**

1. **The source SHA to run.** The bench verifies it before resuming:

   ```bash
   git log --oneline -1 -- src/ diagnostic-tests/
   ```

   **Scoped to the source paths deliberately.** A bare `git log -1` names HEAD,
   which moves every time the container edits a *document* — including this run
   sheet — so the check would fail spuriously and, worse, would be trained out of
   people. Scoping it to the paths that produce binaries makes it mean the one
   thing it should: *is the tree I am about to build from the tree the resume
   describes?*

   This campaign has three times produced transcripts that could not prove which
   build made them. Two agents alternating on one tree only raises that risk, and
   one line of `git log` closes the class.
2. **What changed and why.**
3. **Where to resume, and what the change invalidated.** A driver change
   invalidates every completed suite — a certification run is atomic, so it
   restarts. Say so explicitly rather than leaving it to be inferred. An edit
   confined to test suites or a support vehicle does *not* restart it; say that
   explicitly too, because the bench cannot tell which it is holding.

### 🚪 The container's handoff GATE — finish this before saying "ready"

**The instructions are the deliverable, not the paperwork after it.** The bench is
idle until they exist and Stephen is the one carrying the message, so a handoff
announced before it can be acted on costs a round trip every time.

*This gate exists because it was missed three times running.* Each miss was found by
Stephen asking rather than by the container checking, and each question turned up
something real: a step that would have reformatted the card holding the only copy of
the evidence; a superseded hand-back still ending "continue at **step 2**" when step
2 had become the one step that must not run; and 136 lines of completed instructions
sitting at heading level, indistinguishable from live ones. The code was fine every
time. The handoff was not followable.

- [ ] The resume states **all four** of SHA, what changed, where to resume, **and
      what it invalidated** — the fourth is the one that gets dropped
- [ ] The **whole sheet** was read, not just the edited section — all three misses
      were outside the part that had just been changed
- [ ] Every **completed step carries its status**; an unmarked finished step is an
      instruction to do it again
- [ ] **No superseded directive survives at heading level** — spent hand-backs are
      deleted, not demoted; git and `SOCKET-SHMOO-RUN-NOTES.md` hold the history
- [ ] Tree **clean and committed**, six gates **green**, every affected program
      **compiles** — including indirect consumers
- [ ] Anything **perishable is protected by ordering**, and the warning sits where
      the destructive command used to be, not only in the resume

---

## ▶ SESSION STATE — read this before anything

*Updated by the container agent at each handback. Bench: confirm the SHA first.*

| | |
|---|---|
| **Source SHA to run** | `00a8d45` — verify with `git log --oneline -1 -- src/ diagnostic-tests/` |
| **Tree** | clean; six gates green; all five affected programs compile (audit, fsck, demo shell, register_tests, speed_tests) |
| **Resume at** | **Step 4g (verify the fix) → 4h (re-certify).** DRIVER CHANGED — 4d's 534/534 is stale and the roster restarts |

### Container hand-back, session 5 → 6

**Your bisect closed it. The defect is root-caused and fixed in the driver; step 4g
verifies it with your own two-suite reproducer.**

#### ⚠ What this change invalidated *(protocol item 3)*

**This one IS a driver change** — `micro_sd_fat32_fs.spin2`, three sites. A
certification run is atomic, so **your 4d 534/534 is stale and the roster restarts.**
That is step 4h below. Nothing about the suites changed, so the expected total is
still **534**.

#### Step 4g — verify the fix with your reproducer *(do this first)*

```bash
./run_regression.sh --reformat-only
./run_test.sh ../src/regression-tests/SD_RT_seek_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_defrag_tests.spin2
./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2
```

On the **8-sectors/cluster** card (Gigastone HE `$0001_B9D5` — reformat it freely,
its evidence is fully harvested). **Expect `STATUS: CLEAN`.** Anything else and the
fix is wrong or incomplete: hand back with the audit log and do not continue.

Run it **twice** if the first is clean. This defect needed the allocator to climb
past cluster 128 before it bit, so one clean pass is weaker evidence than it looks.

#### Step 4h — re-certify (the driver moved)

```bash
./run_regression.sh          # regression card
```

**Expect 534/534 with a clean closing audit.** Then, if you still have the
8-sec/cluster card handy, a full sweep on *it* is the strongest single check we can
make — it is the geometry that exposed this, and it has never had a full green
roster with a clean audit.

#### Then

Step 5 (16e) is unblocked. Its first-light requirement still stands: one throwaway
benchmark through `harvest_catalog.sh` before any one-shot card is seated.

#### ⚠ Still do not fix `SD_RT_seek_tests`

It is still the seed for the reproducer, and 4g needs it exactly as it is. It gets
fixed after 4g is green, together with the regression test that is owed for this
defect.

---

#### The root cause

`findContiguousRun()` **never loaded the first FAT sector.**

```spin2
fat_idx := ROOT_CLUSTER * 4        ' = 8
repeat
  if fat_idx & SECTOR_OFFSET_MASK == 0     ' 8 & 511 = 8 -> FALSE on the first pass
    ...readSector(BUF_FAT)...
  entry := LONG[@fat_buf + (fat_idx & SECTOR_OFFSET_MASK)]
```

The scan starts at cluster 2, so its first sector load happened at `fat_idx` 512, and
**every verdict for clusters 2..127 came from whatever the previous FAT operation left
in the buffer.** `allocateCluster()` has always pre-loaded for this exact reason.

It reports *allocated* clusters as **free** — the dangerous direction.
`do_compact_file()` then builds its contiguous chain across a live bystander's
cluster, and when that chain is later freed the bystander is left with a directory
entry pointing at a cluster both FATs call free. Your `dirSize=600` reading is what
made this legible: the entry was complete and untouched, so nothing was wrong with the
file — something else came along and freed its cluster.

**Two of your observations are now explained rather than just recorded.** The damaged
cluster moved between runs (19, then 5) because the fault follows allocation history,
which a fixed-offset bug would not. And the geometry gate is exact:
`do_compact_file()` returns early at `frag_count == 1`, so with 64-sector clusters the
fixtures are single-cluster and this code never runs — `SD_RT_defrag_tests` says so
itself in its CLUSTER-SIZE CAVEAT comment.

**Fixed at three sites.** `findContiguousRun()` and `countFreeClusters()` carry the
identical defect — same shape, same missing pre-load, same trailing invalidate
guarding the wrong end — and are fixed together so neither survives as the example.
In `countFreeClusters()` the consequence was quieter: a wrong free-cluster total
written to FSInfo on unmount. The third is the `allocateCluster()` test-hook wrap
path, which reset the index to cluster 2 without reloading the sector holding it.

### Earlier hand-backs — completed, and deliberately not kept here

Sessions 1 → 2 and 2 → 3 are done and their instructions are spent. They were
removed on 2026-08-20 because a superseded hand-back is not harmless: the session
1 → 2 block still ended "continue at **step 2**", which is now the one step that
must **not** run, and a bench agent skimming for its next command could act on it.
This sheet carries the current hand-back only.

The history is in git (`git log --oneline DOCs/Plans/ROUND-16-RUN-SHEET.md`) and in
the bench's own record, `SOCKET-SHMOO-RUN-NOTES.md`. What survived from those
sessions is already live elsewhere on this page: the step 2 deferral has its own
step section, and the first-light status is under **Before you start**.

## Before you start

```bash
cd tools
./check_doc_version.sh      # must exit 0
```

A sweep run under a stale version constant mislabels every row it produces, and
the mislabelling is indistinguishable from correct data afterwards.

**First-light status, updated after session 2.** The driver is certified on hardware
(534/534) and `SD_card_identify` is verified end to end, emitter through harvester.
**`SD_performance_benchmark` and `SD_speed_characterize` have still not run since
their 2026-08-19 rewrite** — their identity and CATALOG lines were fixed alongside
`SD_card_identify` but only that one has been proven on a card. Expect first-light
friction at step 5, and run one throwaway benchmark through `harvest_catalog.sh`
before any one-shot card goes in the socket.

---

## Step 0 — Identify and mark the two retained 64 GB cards — ✅ DONE

**Completed session 1, re-captured with canonical keys in session 2. Do not repeat —
the cards are marked and the transcripts are keyed.** Card A (unmarked, record still
owed) is `$12_ASTC_2.0_00000E2F_202306`; card B (green, catalogued) is
`$12_ASTC_2.0_00000F14_202306`. Same silicon key on both: one product, one silicon.
Kept below for the reasoning, which the two owed card records will need.

**Do this before the five Camera Plus units are handled together.**

```bash
./run_test.sh ../src/UTILS/SD_card_identify.spin2      # retained card A
./run_test.sh ../src/UTILS/SD_card_identify.spin2      # retained card B
```

**READ FIRST, MARK SECOND.**

1. One card reads PSN `$0000_0F14` — the catalogued `GigastoneOEM_ASTC_2.0_00000F14_202306`. **Mark that one green.**
2. The other is the second retained unit. Its `CARD-ID:` line keys its new card record.

Green then means *catalogued* by construction, matching the 32 GB pair, and it
doubles as a **do-not-deploy** mark.

**STOP if neither reads `$0000_0F14`** — the catalogued unit is then somewhere in
the set of five, and marking the wrong card puts a retained card in the deploy pile.

**Record:** both PSNs, which is now green, purchase date/source of each unit.
**Owed afterwards:** card records for the unmarked 64 GB *and* for the unmarked
32 GB `$0000_01C7`, which has carried socket-campaign data since round 5 and still
has none.

---

## Step 1 — 16a: certify the driver — ✅ PASSED TWICE, ⚠ now stale again

**Session 2: 534/534** on the regression card (Amazon Basics `$3584_1E2E`).
**Session 5 (step 4d): 534/534 with a clean closing audit**, restoring the gate after
two suites were edited. Transcript `tools/logs/sweep_260819-234405.txt`.

**The driver changed on 2026-08-20** (the `findContiguousRun` fix), and a
certification run is atomic — so both of those are stale and the roster restarts.
That re-run is **step 4h** in the hand-back. Expected total is unchanged at **534**.

```bash
./run_regression.sh
```

**Expect 534/534.** Anything below that is a stale binary — 530 predates the
speed-tests group, 532 predates the driver-identity group added 2026-08-19.

Certifies the CMD12 quiesce (now unconditional on every driver start) and the new
version constant.

**STOP on any failure.** Zero tolerance; no failure is pre-existing.

---

## Step 2 — 16d: the speed-policy cell — ⏸ DEFERRED, DO NOT RUN

**Deferred 2026-08-19, before it ran. The cell is unreachable with the shipped
driver; the full reasoning is in the punch-list entry "Read/write speed policy is
undecided", which also carries the decision rule and the cost estimate.**

In one line: `setSPISpeed()` CMD6-switches the card *out* of high-speed mode before
applying any hand-set clock, so "high speed negotiated, writes at 25 MHz" cannot be
constructed — and round 8a run 2 already showed that holding the card in high speed
while the host drops to 25 MHz strands the link with a `-7` cascade.

Reaching it needs a debug-only clock knob that skips the switch-back, plus a read-band
phase sweep at hp=7 *inside* high-speed mode to find the sampling centre there. That
is **H2's next campaign, after v1.8.0 tags**, on the retained Samsung — not this
round, whose scarce resource is the one-shot deployment-bound cards.

Nothing downstream depends on it: step 6 is two-armed, so the sweep is valid for
whichever policy is eventually chosen, and v1.8.0 does not change the high-speed
default.

---

## Step 3 — decide the policy — ⏸ STEPHEN'S CALL, deferred to after step 6

**Not decided by the container.** Whether to spend bench time reaching the 16d cell
is Stephen's decision, and he has asked to make it himself.

**What is not in question:** v1.8.0 changes nothing about the high-speed default —
it stays opt-in via `attemptHighSpeed()`, now with correct mode bookkeeping and a
switch-back on every exit. That is the state the driver was just certified in, and no
driver change is proposed, so **step 1 does not re-run**.

**Why the decision waits for step 6 rather than preceding it.** The value of any
asymmetric policy depends on how many cards actually lose writes in high-speed mode,
and today that is n=1 per card on three cards — with one of the three already
withdrawn on re-measurement. Step 6 runs both arms on every working card at no extra
bench cost, which either makes the 16d campaign clearly worth funding or makes it
unnecessary. The decision rule and the full cost estimate are in the punch-list entry
"Read/write speed policy is undecided".

---

## Step 4 — 16b: the Lerdisk in the EDGE socket — ✅ RAN; 🔴 DRIVER DEFECT FOUND

**Attribution is settled and it is the bad branch.** 4a named the file
(`RTDIRTY.BIN`, from `SD_RT_seek_tests`), 4b reproduced it deterministically, and
4c reproduced it on **genuine** Gigastone High Endurance 8 GB silicon. Clean only at
64 sectors/cluster. The counterfeit is exonerated; this is a driver defect gated on
small-cluster geometry, and it was a **release blocker**. **ROOT-CAUSED AND FIXED
2026-08-20** — `findContiguousRun()` never loaded FAT sector 0, so it reported
allocated clusters as free. Verification is step 4g.

**⚠ Do NOT re-run this step.** It is complete, and its evidence has been fully
harvested — the Gigastone HE `$0001_B9D5` is now free to reformat. The ordered
continuation is **4g → 4h** in the session 5 → 6 hand-back at the top of this sheet.

**Ran 2026-08-19** on the Lerdisk asdfg 1GB `$0000_01F4`, transcript
`tools/logs/sweep_260819-180530.txt`.

**The wedge is GONE.** `mount_tests` 45/45 and `raw_sector_tests` 14/14 in the Edge
socket, on the card whose record says "External connector only" — and that
restriction *was* the #3240 defect. Round 15b had already shown 43/43 with the
quiesce; this is the full-suite confirmation.

**Still owed before the incompatibility can be withdrawn:** the closing audit
reported an unterminated cluster chain (a directory entry pointing at cluster 19
whose FAT entry is 0) with all 27 suites green. Until 4a-4c attribute that to the
counterfeit's silicon or to driver code, the card record and `CARD-CATALOG.md`
rewrite waits — a card that mounts cleanly but may leave a damaged filesystem has
not earned an unqualified endorsement.

---

## Step 5 — 16e: multi-card, run variance BEFORE instance variance

**Order is not optional.** One physical card has moved up to 3× between rounds, so
a card-to-card delta means nothing until the same-card spread is known.

1. **Identify every unit first.** Same label ≠ same silicon — Gigastone labels sit
   on four different MIDs here. If the five Camera Plus units split across silicon
   keys, that is a *better* result, not a spoiled one, but we must know which
   experiment we are running.
2. **Run variance:** one Gigastone, `REPEAT_RUNS > 1` in `SD_performance_benchmark`.
   **This is also the benchmark's first light since its 2026-08-19 rewrite** — it is
   a *retained* card, so put it in the socket before any one-shot unit and feed its
   log to `harvest_catalog.sh`. If the harvester refuses a field, stop: that is the
   emitter fix incomplete, and it must be right before a card you cannot re-measure.
3. **Instance variance:** all 5 Camera Plus. n=5 is the only set that can show a distribution.
4. **The 3 Lexar reds — not optional.** The Lexar red is one of the three H2 cards
   and the clean-win case (+47% reads, +44% writes). Every H2 conclusion is **n=1
   per card** and is about to inform a shipped default. This says whether that
   +44% belongs to the product or to one unit.
5. **The 2 SanDisk Extremes.** Cannot show a distribution; will catch a gross
   outlier cheaply. Lowest priority.

**THE DEPLOYMENT-BOUND UNITS ARE A ONE-SHOT.** Only the retained cards stay — the
rest are deployed and do not come back. Capture *everything* while they are in the
socket: identity, both speed arms, the full benchmark. A gap found at write-up time
cannot be filled, and the n=5 / n=3 findings are unrepeatable by construction.

Working stock gets **no card record** — its numbers go in this round's run notes.

---

## Step 6 — 16c: the catalog sweep 🔴 RELEASE GATE

**Two-armed: standard and high-speed, same session, same card, same instrument.**

Two arms produce the release numbers for *whichever* policy is eventually chosen —
step 3 is deferred, and two arms are precisely what lets this sweep run without it —
answer the policy question across the whole fleet rather than three cards, and
satisfy the same-instrument comparator rule. One long afternoon instead of two.

**This sweep is also the input to the deferred step 3 decision.** It measures both
arms on every working card, which is what says whether the high-speed write
regression is a fleet property or a single controller family's quirk. Capture both
arms on every card even where the standard arm looks uninteresting.

Procedure: [../cards/CATALOG-PROCEDURE.md](../cards/CATALOG-PROCEDURE.md).

```bash
./harvest_catalog.sh logs/SD_speed_characterize_*.log logs/SD_performance_benchmark_*.log
```

**Do not hand-type rows.** Harvest them. The script refuses to emit a table
spanning two driver versions.

---

## What "done" looks like

- [x] Step 0: both 64 GB PSNs recorded, `00000F14` marked green
- [x] Step 1: **534/534** (session 2, sweep `260819-155926`)
- [~] Step 2: **deferred** — cell unreachable on the shipped driver; funding the campaign is Stephen's call
- [~] Step 3: **deferred to after step 6** — no default change in v1.8.0 either way
- [~] Step 4: wedge **GONE** (mount 45/45, raw 14/14 in the Edge socket) — but the Lerdisk verdict is **not** final until the closing-audit chain finding is attributed
  - [x] 4a: named it — `RTDIRTY.BIN`, from `SD_RT_seek_tests`
  - [x] 4b: reproduces deterministically on the Lerdisk
  - [x] 4c: **reproduces on genuine 8-sec/cluster silicon** — driver defect, release blocker
  - [ ] 4e: read-only re-audit for `start=` / `dirSize=` (do before any reformat)
  - [ ] 4f: bisect — which suite frees the chain?
  - [x] 4e: `dirSize=600` — entry complete while the FAT called its cluster free
  - [x] 4f: bisect named `SD_RT_defrag_tests`; two-suite reproducer in hand
  - [x] 4d: gate A restored — **534/534**, closing audit clean
  - [ ] 4g: **verify the fix** on 8-sec/cluster silicon — audit CLEAN, run twice
  - [ ] 4h: re-certify — driver changed, so the roster restarts
- [x] 🔴 The chain-free defect is root-caused and fixed — `findContiguousRun()` never loaded FAT sector 0
- [ ] Regression coverage owed for it: bystander file survives a compact (no suite catches this today)
- [ ] `SD_RT_seek_tests` handle leak fixed — **only after** the driver defect is understood
- [ ] Step 5: run variance measured before instance variance; one-shot cards fully captured
- [ ] Step 6: catalog tables harvested, single driver-version banner
- [ ] Card records created for the two uncatalogued retained Gigastones
- [ ] Lerdisk card record + `CARD-CATALOG.md` rewritten (blocked on 4a-4c)

**Then and only then** the v1.8.0 release gate is satisfied.
