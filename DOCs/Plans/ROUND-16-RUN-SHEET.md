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
   restarts. Say so explicitly rather than leaving it to be inferred.

---

## ▶ SESSION STATE — read this before anything

*Updated by the container agent at each handback. Bench: confirm the SHA first.*

| | |
|---|---|
| **Source SHA to run** | see below — verify with `git log --oneline -1 -- src/ diagnostic-tests/` |
| **Tree** | clean; six gates green |
| **Resume at** | **Step 1, re-run in full** (driver + test changed) |

### Container hand-back, session 1 → 2

**Both work items are done, and one of them was a near miss.**

**Item A — Test #8 fixed. Your classification was right, and I verified it against
the contract independently before touching anything.** `attemptHighSpeed()`
documents three outcomes; the test modelled two and called the third a defect. It
now uses the capability answer already in hand: a card that said it *can* and then
did not must carry an error code; a card that said it *cannot* is a clean decline
and must not. **Sub-check count is unchanged, so the total is still 534.**

The driver half of item A was **already fixed before your handback arrived**
(`9f22a44`) — same defect, found independently. All five failure exits in
`do_attempt_high_speed()` now set `hs_query_error`. Punch-listed and changelogged.
The path still cannot be reached by injection; the recommended
`setTestCorruptReadAfter()` facility is punch-listed, decision pending.

**Item B — all three emitters fixed, and this one nearly cost the sweep.** Your
diagnosis was exact. Confirmed from the transcripts: `$$AD`, `$3584_1E2E` inside a
key, `mdt=2_02507`, `sysclk=350_000_000`. The grouping was the dangerous part —
`awk`'s `+0` reads `kbps=2_500` as **2**, so a swept catalog would have carried
numbers truncated to their leading digits with nothing looking wrong anywhere.

All machine lines in `SD_card_identify`, `SD_performance_benchmark` and
`SD_speed_characterize` are now composed with `fmt.sFormatStr*` and emitted as one
plain string, per the demo-shell precedent you cited. PNM trailing spaces trimmed.
Human-readable lines keep `debug()`'s formatters — grouping helps a reader.

**Plus a hardening you did not ask for:** `harvest_catalog.sh` now *refuses* a
non-integer numeric field instead of silently coercing it. A grouped value is a
hard error naming the field and telling you to re-run the instrument. The fix
stopped this instance; the guard stops the class.

### Verify on hardware before trusting the sweep

Your resume step 3 is right and now has a sharper acceptance test:

```bash
./run_test.sh ../src/UTILS/SD_card_identify.spin2
./harvest_catalog.sh logs/SD_card_identify_<newest>.log
```

Expect `SILICON-KEY: $AD_USD00_2.0` and
`CARD-ID: $AD_USD00_2.0_35841E2E_202507` — single `$`, contiguous hex, `YYYYMM`.
The harvester should report a clean parse. **If it refuses a field, stop** — that
is item B not fully fixed, and it must be right before any one-shot capture.

### Then

1. Re-run **step 1** in full (Amazon Basics still seated). Expect **534/534**.
2. Re-identify both retained 64 GB cards for clean record-source transcripts
   (records owed for `$0000_0E2F` and the 32 GB `$0000_01C7`).
3. Continue at **step 2** (16d, Samsung EVO `$4AC8_5F42`).

### Noted from your session

- The unconditional CMD12 quiesce passed its first full-suite exposure, 27 suites,
  every mount, two mid-sweep reformats, 23/23 closing audit. That is the release's
  headline fix certified in practice.
- One-shot population corrected to 6 cards; purchase provenance recorded.
- Aborting the sweep because uncommitted notes made the banner unprovable was
  **correct behaviour**, and it is now written into the protocol above rather than
  left as a judgement call.

## Before you start

```bash
cd tools
./check_doc_version.sh      # must exit 0
```

A sweep run under a stale version constant mislabels every row it produces, and
the mislabelling is indistinguishable from correct data afterwards.

**Nothing below has run on hardware yet.** The driver, `SD_performance_benchmark`,
`SD_speed_characterize` and `SD_card_identify` all changed on 2026-08-19 and are
compile-verified only. Expect first-light friction in step 2 and step 5; that is
the point of running them before the sweep, not after.

---

## Step 0 — Identify and mark the two retained 64 GB cards  *(one time, no driver dependency)*

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

## Step 1 — 16a: certify the driver

```bash
./run_regression.sh
```

**Expect 534/534.** Anything below that is a stale binary — 530 predates the
speed-tests group, 532 predates the driver-identity group added 2026-08-19.

Certifies the CMD12 quiesce (now unconditional on every driver start) and the new
version constant.

**STOP on any failure.** Zero tolerance; no failure is pre-existing.

---

## Step 2 — 16d: the cell that decides the speed policy 🔑

**One card (Samsung EVO `$4AC8_5F42`), one arm, minutes. Run it before anything
downstream, because it is the only step whose outcome can change the driver.**

Rounds 10b/11b moved *mode* and *clock* together, so the Samsung's reproducible
−52% write regression has never been attributed to either. The missing cell is
**high speed negotiated, then writes clocked at 25 MHz**.

| Result | Meaning | What happens next |
|---|---|---|
| Writes recover at 25 MHz | Regression is **clock-side** | Asymmetric policy works and is general — reads fast, writes at 25, one rule for every card. **Driver changes → re-run step 1** |
| Writes still slow | Regression is **mode-side** | Dropping the clock cannot help. Either keep high speed opt-in (no driver change, continue), or ship it by default accepting one controller family's write loss |

**Record:** the write figures at 43.75 vs 25 MHz inside high-speed mode, and
whether `isHighSpeedActive()` stayed true throughout.

---

## Step 3 — decide the policy  *(container, between bench sessions)*

Step 2's answer maps to a policy via the table above. If the driver changes,
**return to step 1** before going further — a sweep must measure the shipping
driver.

---

## Step 4 — 16b: the Lerdisk in the EDGE socket

```bash
./run_regression.sh
```

The card the whole campaign was about. Its record says "External connector only" —
**that restriction *was* the #3240 defect**, now fixed. Round 15b already showed
`mount_tests` 43/43 there with the quiesce.

**If the full suite passes:** its card record and `CARD-CATALOG.md` need rewriting
and a documented incompatibility disappears.

---

## Step 5 — 16e: multi-card, run variance BEFORE instance variance

**Order is not optional.** One physical card has moved up to 3× between rounds, so
a card-to-card delta means nothing until the same-card spread is known.

1. **Identify every unit first.** Same label ≠ same silicon — Gigastone labels sit
   on four different MIDs here. If the five Camera Plus units split across silicon
   keys, that is a *better* result, not a spoiled one, but we must know which
   experiment we are running.
2. **Run variance:** one Gigastone, `REPEAT_RUNS > 1` in `SD_performance_benchmark`.
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

Two arms produce the release numbers for *whichever* policy step 3 chose, answer
the policy question across the whole fleet rather than three cards, and satisfy the
same-instrument comparator rule. One long afternoon instead of one.

Procedure: [../cards/CATALOG-PROCEDURE.md](../cards/CATALOG-PROCEDURE.md).

```bash
./harvest_catalog.sh logs/SD_speed_characterize_*.log logs/SD_performance_benchmark_*.log
```

**Do not hand-type rows.** Harvest them. The script refuses to emit a table
spanning two driver versions.

---

## What "done" looks like

- [ ] Step 0: both 64 GB PSNs recorded, `00000F14` marked green
- [ ] Step 1: 534/534
- [ ] Step 2: write regression attributed to clock or mode
- [ ] Step 3: policy decided; if the driver changed, step 1 re-run and green
- [ ] Step 4: Lerdisk verdict in the Edge socket
- [ ] Step 5: run variance measured before instance variance; one-shot cards fully captured
- [ ] Step 6: catalog tables harvested, single driver-version banner
- [ ] Card records created for the two uncatalogued retained Gigastones

**Then and only then** the v1.8.0 release gate is satisfied.
