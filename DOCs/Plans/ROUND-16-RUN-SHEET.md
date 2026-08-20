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
| **Source SHA to run** | set at commit — verify with `git log --oneline -1 -- src/ diagnostic-tests/` |
| **THE DRIVER DID NOT MOVE** | `micro_sd_fat32_fs.spin2` is **untouched** since `00a8d45`. Confirm with `git log --oneline -1 -- src/micro_sd_fat32_fs.spin2` — it must still read `00a8d45`. Your 4h certification is **not** invalidated as a *driver* certification |
| **What changed** | three regression suites only: `SD_RT_mount_tests` (#39 precondition), `SD_RT_seek_tests` (handle leak), `SD_RT_defrag_tests` (**+1 new test**) — plus docs |
| **Expected roster** | **535**, not 534. The defrag suite gains one test (13 → 14) |
| **Tree** | Source committed for this sweep. **Correction to the previous hand-back:** `run_regression.sh` does **not** abort on a dirty tree — it prints the `-dirty` stamp and the warning *"this result is not reproducible from any commit"* and runs anyway (script §GIT_STAMP). The rule is a judgement, not a gate: a certifying sweep wants the source committed. Doc work on the case studies stays uncommitted pending a voicing decision, so expect `-dirty` in the header — annotate it as documentation-only, exactly as session 6 did. Six gates green; all three changed suites compile in both shapes |
| **Resume at** | **Step 4j — re-certify the suite changes.** Then step 5 remains ON HOLD per Stephen's gate-ordering instruction |

### Container hand-back, session 6 → 7

**Your 4g / 4h / 4i session closed three things and opened one. The one it opened
is fixed here — in the test suites, not in the driver.**

#### ⚠ What this change invalidated *(protocol item 3)*

**This is NOT a driver change.** `micro_sd_fat32_fs.spin2` is untouched; the source
SHA moves only because the regression suites live under `src/`. So:

- Your **4h 534/534 on both geometries stands** as the driver certification of
  `00a8d45`. Nothing about the driver's behaviour is in question.
- But the **suite set changed**, so the number 534 no longer describes it. Two tests
  changed behaviour and one test is new. **The new expected total is 535.**
- That means one more sweep to re-baseline — step 4j — not a fresh investigation.

#### What was fixed, and why

**1. `mount_tests` #39 on Cloudisk `$0001_9B39` — root-caused as a TEST defect.**
You handed back two candidate mechanisms and asked the container to decide. Decided
from source, no hardware needed, and **both of your candidates were near misses**:

- Your mechanism 1 (the unscored `createFileNew` precondition) is **dead**.
  `do_unmount()` calls `updateFSInfo()` **unconditionally** — there is no dirty gate
  anywhere in the path — so whether that file got created changes nothing about
  whether the write-back is attempted. The block was decorative.
- Your mechanism 2 (a real `unmount()` validation miss) is **also dead**, and this
  is the important half: the driver is behaving **correctly**.

The actual gate is in `updateFSInfo()`: it returns early when
`fsi_free_count == $FFFF_FFFF`, and `do_mount()` sets exactly that sentinel whenever
the FSInfo sector is absent, sits outside the reserved region, cannot be read, or
carries bad signatures. On such a card there is genuinely nothing to write back, so
`SUCCESS` is the right answer — and `E_BAD_FSINFO` is unreachable by construction.

**That card's own FSInfo is one the driver does not accept.** The test asserted an
outcome whose precondition it never established: locating the FSInfo sector through
the VBR pointer (which it did score) is *not* the same as the driver having accepted
it. On the two regression cards the precondition happened to hold, so the test passed
for four months without ever being right.

**The fix plants the precondition instead of assuming it** — the test now writes a
known-good FSInfo (valid signatures, a real free count) before mounting, and scores
that plant as a new sub-check. It saves and restores the card's original sector
exactly as before. Sub-checks go 6 → 7; the test count does not change.

*Also removed:* the unscored `createFileNew` / `writeHandle` / `deleteFile` block.
It was setup for a gate that does not exist — and dropping it means this test no
longer writes files to whatever card it lands on.

**2. `SD_RT_seek_tests` handle leak — the hold is released.** 4g is green, so the
leak no longer needs preserving as reproducer seed. `closeFileHandle()` sat in the
`else` branch, where the handle is invalid by definition, so the success path never
closed and the following `deleteFile()` returned `E_FILE_OPEN` into a discarded
value. That is what left `RTDIRTY.BIN` on the card and seeded your whole round-16
investigation. The close moved to the success path **and the delete is now scored**,
which is the part that stops it recurring silently. Sub-checks 5 → 6.

**3. The owed regression test for the defrag defect — written.** `SD_RT_defrag_tests`
gains **Test 10, "Bystander file intact after compacting a fragmented file"** (new
TEST GROUP 3; the later groups renumbered). It creates a bystander file in low
clusters with a distinct pattern, fragments a victim around a spacer, frees the
spacer, compacts the victim, then reads the bystander back **in full and byte-for-byte**.
A chain freed under it fails as a short read; a stolen cluster fails as a pattern
mismatch.

It does **not** reproduce the original stale-buffer condition on demand — that needed
the allocator to have climbed past cluster 128 first, which is allocation history and
not something a test can stage. It asserts the property the defect violated, which is
what a regression test is for. It is cluster-geometry independent: 64 KB fills span
multiple clusters at both 8 and 64 sectors/cluster.

*Space:* `PEAK_BYTES` rose from 5 to 6 × 64 KB because the bystander is alive across
a compaction by design. The suite's existing preflight gate covers it.

#### Still open — and both are Stephen's calls, not the bench's

1. **The control-arm decision.** A debug-only way to disable the quiesce is the only
   thing that lets the case study drop its §11 caveat. Not implemented — see
   *Decisions* below.
2. **Card record for `$0001_9B39`.** Its identity is captured in your notes and needs
   no further handling, but a new record needs a `CARD-LABELS.md` entry, and whether
   card #2's printed text is identical to the catalogued Cloudisk's is a question for
   a human with the card in hand. One look, then the container writes it.

#### Done on the container side since your handback

- **The External-only restriction is WITHDRAWN** in all four places it was asserted:
  both `asdfg` card records, `CARD-CATALOG.md` and `CARD-REFERENCE.md`. Your 4i result
  is what closed it. The historical text is kept, marked superseded, rather than
  deleted — it carries the wrong mechanism and that is worth preserving as a record.
- **The run sheet's "nothing written" claim for 4i is corrected** where it appeared,
  in both places. You were right and it mattered: `mount_tests` #39 writes.
- Suite README + both top-level READMEs re-stamped 589 → **590** documented tests.

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

## Step 1 — 16a: certify the driver — ✅ PASSED; re-certified at `00a8d45` (step 4h)

**Session 2: 534/534** on the regression card (Amazon Basics `$3584_1E2E`).
**Session 5 (step 4d): 534/534 with a clean closing audit**, restoring the gate after
two suites were edited. Transcript `tools/logs/sweep_260819-234405.txt`.

**Session 6 (step 4h): 534/0 on BOTH geometries** with clean closing audits, at
source SHA `00a8d45` — the re-certification the `findContiguousRun` driver fix
required. That is the current driver certification and it stands.

> **⚠ The roster number moved after that run.** The suite set changed on 2026-08-20
> (regression suites only — the driver did not move), so **the current expected total
> is 535**, not 534. Re-baselining it is **step 4j**, which is where the bench
> resumes. Do not re-run this step; 4j supersedes it.

Anything *below* the expected total is usually a stale binary — 530 predates the
speed-tests group, 532 predates the driver-identity group added 2026-08-19, and 534
predates the bystander test added 2026-08-20.

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
allocated clusters as free.

> **✅ VERIFIED AND CLOSED 2026-08-20.** Step 4g ran the two-suite reproducer twice
> from a fresh reformat on the 8-sectors/cluster card: `seek_tests` 38/0,
> `defrag_tests` 13/0, closing audit **CLEAN** 23/23 both passes. Step 4h then
> re-certified the driver at `00a8d45` — **534/0 on both geometries** with clean
> closing audits, including the 8-sectors/cluster card's first ever full green
> roster. 4g and 4h are spent; their instructions were removed with the session
> 5 → 6 hand-back. The regression test that was owed for this defect is now written
> and is re-certified in **step 4j**.

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

## Step 4i — 16f: the Cloudisk twins on a quiesce build — ✅ RAN 2026-08-20

> **✅ COMPLETE. DO NOT RE-RUN.** Both twins came back clean on the quiesce build:
> `$0000_1680` 45/45 mount + 14/14 raw on four warm runs across two power cycles;
> `$0001_9B39` clean on the wedge axis with one unrelated test failure (#39, since
> root-caused as a test defect and fixed — see step 4j). Boot access was left
> ENABLED and the flash banner verified in all 12 transcripts. **No control arm
> existed at that SHA**, so the case-study §11 caveat is weakened to *"consistent on
> both twins, controlled on one"* and NOT deleted. The section below is kept for its
> protocol and its "what a clean result proves" reasoning, both of which apply again
> if the control arm is ever built.

**Why this exists.** The CMD12 quiesce that fixed the #3240 wedge was proven on
**one** card. Round 15's scope line says so in as many words — *"One card
throughout: Lerdisk `asdfg` `$0000_01F4`, Edge socket, adapter empty"* — and that
covers 15a, 15b **and** step 4's full-suite confirmation. The Cloudisk
`$0000_1680` has only ever been run **pre-fix**: round 9a, 2026-08-18, where it
wedged 19/24 with `-7` / `-8`, indistinguishable from its twin.

Cross-checked two ways before this step was written: no round-15 or round-16
section names a Cloudisk, and the newest Cloudisk transcript in `tools/logs/` is
`260818-142849` — a day before the quiesce build existed.

So the shipped claim rests on one of the two cards known to carry the defect.
`DOCs/SD-CARD-WEDGE-CASE-STUDY.md` §11 states that limitation in print, for
readers to weigh. **This step is what deletes it.**

**Cards — all three of the `asdfg` class, all `retained`:**

| Card | Serial | Standing |
|---|---|---|
| Cloudisk 2 GB | `$0000_1680` | wedged pre-fix (9a); **never run on a quiesce build** |
| Cloudisk #2 2 GB | `$0001_9B39` | **uncatalogued**; round 9 found it scores `crc = 0` unlike its twins, so it may not be `CW_NO_DATA_CRC` silicon at all |
| Lerdisk 1 GB | `$0000_01F4` | the proven card — needed here only if a control arm exists |

**Edge socket. No reformat.** Cheap step; the cost is card handling, not bench time.

> **CORRECTION (2026-08-20, from the bench).** An earlier version of this line said
> "nothing written — the reproducer only mounts and reads." **That is wrong, and it
> mattered:** `SD_RT_mount_tests` #39 writes raw sectors over the FSInfo LBA, and
> (before the 2026-08-20 test fix) also created, wrote and deleted a file. It
> restores what it corrupts and verifies the restore, and no harm came of it — but
> anyone reading that line to decide what is safe to run on a precious one-shot card
> would have been misled. `mount_tests` writes. `raw_sector_tests` writes to its
> scratch LBAs. Neither reformats.

### The protocol, per card

Warm is the entire point: the wedge needs a prior driver session **and** a P2
reset, with no power cycle between.

```bash
# power cycle the board first (a serial-download reset does NOT drop the SD rail)
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2       # cold - priming session
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2       # WARM - the measurement
./run_test.sh ../src/regression-tests/SD_RT_raw_sector_tests.spin2  # WARM - raw init after
```

Power cycle, repeat. **Three warm runs across two power cycles per card.**

Expect **45/45** on every `mount_tests` and **14/14** on `raw_sector_tests`.
Pre-fix the warm run gives **19/24**, `unmount()` `-7`, `mount()` #2 `-8`.

**⚠ Switches stay in the WEDGING configuration** — the `* Hi! from FLASH *` banner
must be present in every transcript. Check it. A missing banner means the boot
sequence never ran, and the run is void: it would produce clean results for the
wrong reason, which is worse than a failure.

**⚠ Do not run `SD_card_identify` before the cold run.** An identify is itself a
driver session and destroys the cold arm. Confirm identity *after* the first run,
exactly as round 12a did.

### What a clean result does and does not prove

A clean result here is **consistent with** the fix and does not on its own
establish it — a card that does not wedge today may be having a quiet day. That is
precisely the failure mode round 15b was built to exclude, and it excluded it with
an **interleaved control**: an unmodified build run warm on the same card minutes
later, which wedged both times.

**That control is not buildable today.** The quiesce is unconditional in
`initCard()` with no way to compile it out (checked: no `SD_INIT_QUIESCE`, no
guard of any kind — the round-15b flag is gone).

| | Outcome |
|---|---|
| **Without a control arm** | Three clean warm runs per card **weakens** the §11 caveat to *"consistent on both twins, controlled on one."* It does not delete it |
| **With a control arm** | The caveat is deleted |

**This is a container decision, not the bench's:** whether to add a debug-only way
to disable the quiesce so the control arm exists. If it lands before this session
the protocol gains one line per card and the step becomes conclusive. **If it does
not, run the three arms anyway** — partial evidence on a retained card costs one
card swap, and the cards are already here.

### Bonus while the socket is loaded

Cloudisk #2 `$0001_9B39` is owed a card record (punch list). One
`SD_card_identify` capture *after* its warm runs clears that debt at no extra card
handling.

### Hand back

Append to `SOCKET-SHMOO-RUN-NOTES.md` as usual. State per card: warm-run counts,
flash-banner presence, and whether a control arm was available. **If any card
wedges, stop** — that is a hard-stop finding under rule 5, not a caveat to record
and continue past.

---

## Step 4j — re-certify the suite changes ◀ **START HERE**

**This is a test-suite re-baseline, not a driver re-certification.** The driver did
not move (verify: `git log --oneline -1 -- src/micro_sd_fat32_fs.spin2` must still
read `00a8d45`). Your 4h result stands for the driver; what changed underneath it is
the suite set, so the roster number has to be re-established.

**Expected total is 535, not 534.** `SD_RT_defrag_tests` goes 13 → 14.

### 4j.1 — the three changed suites first, individually

Cheap, and it catches an authoring error before you spend a sweep on it. Any
regression card, either geometry.

```bash
cd tools
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_seek_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_defrag_tests.spin2 -t 120
```

| Suite | Expect | What specifically to look at |
|---|---|---|
| `SD_RT_mount_tests` | **45 / 0** | Test #39 now reports **7** sub-checks, not 6. The new one is `valid FSInfo planted (precondition)` and it must PASS — if it FAILS, the raw write to the FSInfo LBA did not land and nothing after it is meaningful |
| `SD_RT_seek_tests` | **38 / 0** | The dirty-seek test now reports **6** sub-checks. The new one is `cleanup deleteFile()` and it must return SUCCESS — a `-45 E_FILE_OPEN` there means the handle is still leaking |
| `SD_RT_defrag_tests` | **14 / 0** | New Test 10 `Bystander file intact after compacting a fragmented file`, 5 sub-checks. **All five must pass.** `bystander bytes unchanged by the compaction` is the one that carries the defect |

**If the bystander test fails, STOP and hand back.** That is a hard-stop finding — it
means a compaction is touching another file's chain, which is the release blocker all
over again. Capture the transcript and run `SD_FAT32_audit` (`-t 300`) before touching
anything else on that card.

### 4j.2 — the defect card

This is the actual retest of the reported bench issue. **Cloudisk `$0001_9B39`**,
Edge socket, no reformat.

```bash
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2
```

**Expect 45 / 0** — where you measured **44 / 1** four times running. Test #39 must
now pass on this card, because the test no longer depends on the card's own FSInfo
being one the driver accepts.

*Card handling:* this suite **writes** — raw sectors over the FSInfo LBA, restored and
verified. It does not reformat. (It no longer creates files; that block was removed.)

**If #39 still fails here**, the diagnosis was wrong and it hands back as a driver
question after all. Send the full sub-check list for #39 — specifically whether
`valid FSInfo planted (precondition)` passed, because that one check separates
"the card won't take our planted FSInfo" from "the driver isn't validating it".

### 4j.3 — one full sweep to set the new baseline

```bash
./run_regression.sh
```

**Expect 535 / 0** with a clean closing audit.

**Both geometries if the cards are still to hand** — and it is worth it this time,
because the new bystander test is the one thing in this change whose *value* depends
on cluster geometry, and it has never run on hardware. The 8-sectors/cluster card is
where the original defect lived.

| Card | Geometry | Expect |
|---|---|---|
| Gigastone HE 8 GB `$0001_B9D5` | 8 sec/cluster | 535 / 0, closing audit clean |
| Amazon Basics 64 GB `$3584_1E2E` | 64 sec/cluster | 535 / 0, closing audit clean |

### Hand back

Append to `SOCKET-SHMOO-RUN-NOTES.md`: the three suite results, the `$0001_9B39`
mount_tests result with #39's sub-check list, and the sweep totals per geometry.
**Then stop** — step 5 stays on hold (below).

---

## Step 5 — 16e: multi-card, run variance BEFORE instance variance

> **⏸ ON HOLD — Stephen's instruction, 2026-08-20.** Do not run the catalog
> pass until every remaining fix and its tests are specified and everything else is
> release-ready. The reasoning is gate ordering and it is correct: the catalog sweep
> **is** the release gate, a certification run is atomic, and any driver change
> landing after it invalidates it wholesale. Running the parade early buys nothing
> and risks burning one-shot card handling on a build that will move again.


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
- [x] Step 1: **534/0 on both geometries** at `00a8d45` (session 6, step 4h) — superseded by 4j's 535 re-baseline
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
  - [x] 4g: fix **verified** on 8-sec/cluster silicon — audit CLEAN, both passes
  - [x] 4h: re-certified — **534/0 on both geometries**, closing audits clean
  - [x] 4i: Cloudisk twins clean on the quiesce build — caveat weakened, not deleted (no control arm existed)
- [x] 🔴 The chain-free defect is root-caused and fixed — `findContiguousRun()` never loaded FAT sector 0
- [x] Regression coverage written for it: `SD_RT_defrag_tests` Test 10, bystander file survives a compact
- [x] `SD_RT_seek_tests` handle leak fixed — hold released once 4g was green; the cleanup delete is now scored
- [x] `mount_tests` #39 on `$0001_9B39` root-caused as a **test** defect (unestablished precondition) and fixed
- [ ] **Step 4j: re-certify the suite changes — 535/0, and #39 green on `$0001_9B39`** ◀ next
- [ ] Control-arm decision (debug-only quiesce disable) — Stephen's call; only thing that deletes case-study §11
- [ ] Step 5: run variance measured before instance variance; one-shot cards fully captured *(ON HOLD)*
- [ ] Step 6: catalog tables harvested, single driver-version banner
- [ ] Card records created for the two uncatalogued retained Gigastones, plus `$0001_9B39` (needs one label look)
- [x] `asdfg` External-only restriction withdrawn in all four places (both card records, catalog, quick reference)

**Then and only then** the v1.8.0 release gate is satisfied.
