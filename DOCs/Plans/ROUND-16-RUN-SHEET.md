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

**When the bench pauses, it hands back:**

1. **A clean tree, or an exact statement of what is dirty.** `git status --short`
   in the handback. A container agent building on an unknown working tree is the
   fastest way to lose an afternoon.
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
| **Source SHA to run** | `9f22a44` — verify with `git log --oneline -1 -- src/ diagnostic-tests/` |
| **Tree** | clean; six gates green |
| **Resume at** | **Step 1, from the top** |

**Why step 1 restarts:** the driver changed twice since the last run began — the
`Driver identity` test group (mount_tests, +2 tests) and the high-speed
verify-mismatch error-code fix. A certification run that spans a source change is
not a certification.

**Changed since the last bench pickup:**

- **FIXED, driver:** `do_attempt_high_speed()` verify-MISMATCH branch set no error
  code, so a card corrupting data at 50 MHz reported `FALSE` + `ERROR() == SUCCESS`
  — which `attemptHighSpeed()`'s contract defines as "the card declined". Now
  `E_IO_ERROR`, matching all four sibling exits. *(This was the bench agent's
  find — correctly classified as driver-side.)*
- **ADDED, tests:** `Driver identity` group in `SD_RT_mount_tests`. **Expect 534,
  not 532.**
- **NOT COVERED:** the mismatch path cannot be reached by injection — the hooks
  force read *failures*, not a read that succeeds with wrong bytes. Punch-listed
  with a recommended `setTestCorruptReadAfter()` facility. Decision pending.

**⚠ OUTSTANDING — container is blocked on this:** the bench reported **1 regression
failure** whose identity has not been passed back. It has not been classified or
fixed. Hand back the suite, test name, expected vs got, and transcript lines.

---

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
