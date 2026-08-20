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
| **Source SHA to run** | `9cff9ac` — verify with `git log --oneline -1 -- src/ diagnostic-tests/` |
| **Tree** | clean; six gates green; all five affected programs compile (audit, fsck, demo shell, register_tests, speed_tests) |
| **Resume at** | **Step 4a below (name the file), then 4b, then 4c.** Do NOT reformat the Lerdisk before 4a |

### Container hand-back, session 3 → 4

**Both test failures were test defects, and neither indicted the driver. The audit
finding is real, unattributed, and the card you preserved is the reason it is
still answerable — thank you for leaving it seated.**

#### The audit finding: one defect, not two, and FSInfo is the honest party

A directory entry points at cluster 19 and `FAT[19]` is 0 — the FAT calls the
file's own first cluster free. That single state produces both lines: the chain
walk hits a free next-pointer, and the counted free total comes out one *higher*
than FSInfo claims.

**Your Amazon Basics comparator is what made this readable.** It ended `CLEAN` with
the *same* `Dirs: 1  Files: 1` survivor — so the leftover file is normal — but with
**two** clusters allocated, root plus the file. The Lerdisk has one. The allocation
happened; the FAT entry never stuck.

**I am not calling it a driver defect, because the evidence does not separate
"driver failed to write `FAT[19]`" from "counterfeit card accepted the write and
discarded it".** The asdfg class already carries a punch-listed LBA-failure item.
Three steps settle it, and they must run in this order.

#### Step 4a — name the object *(read-only, do this first)*

```bash
./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2
```

A chain finding now prints a second line, `in: <8.3 name>`. **That name identifies
the file, the suite that made it, and the code path.** Read-only; the card is not
modified. If it comes back `(root)`, say so — that would mean the root directory
chain itself, which is a different and worse story.

#### Step 4b — does it reproduce?

```bash
./run_regression.sh
```

Deterministic or not is the first fork: a one-off points at the card, a repeat
points at the code. Expect **534/534** — the two reds from your run are fixed
below. This reformats the card, so 4a must be done first.

#### Step 4c — hold the geometry, change the silicon

The clean card has 64 sectors/cluster; the failing one has 8. Run the same roster
on a **genuine** card that formats to 8 sectors/cluster — an 8 GB or smaller unit.
Passes ⇒ the counterfeit dropped the write. Fails ⇒ a real driver defect gated on
small-cluster geometry, and a release blocker. Tell me which card you used.

#### The two reds — both test-side, both fixed

**`register_tests` #11, CRC7 stop bit — test defect.** The driver's contract is
faithful register transport, not card conformance, and this test says so itself one
check below the failing one, where PNM printability is informational for exactly
this reason. The Lerdisk's whole CID byte 15 is `$00`, already characterized in its
card record as a scored counterfeit indicator. Demoted to an informational
transcript line. **No coverage lost:** a misaligned CID read is what the stop bit
might have caught, and the surviving checks catch it more directly on every card —
MID must equal `getManufacturerID()`, MDT must decode to a plausible date. Both held
here, which is how we know the transport was sound.

**`speed_tests` #8 — my defect, introduced in the session 1 → 2 fix.** You reported
the two capability paths disagreeing, and that was exactly right. The driver is not
confused by it: `probeHighSpeed()` gates on the **SCR first** and only asks function
group 1 for SD 2.0+ cards, so an SD 1.x card is a definite "no" and the clean
decline with `ERROR() == SUCCESS` is correct. `checkHighSpeedCapability()` even
documents the precondition — *"call checkCMD6Support() first"* — and my test was the
party not honouring it. It now mirrors the driver's gate: capable means **both**
answers.

**Neither changes the test count. Still 534.**

#### Also fixed — the audit was describing the wrong thing

`"chain runs past the file size at cluster 19"` never consults the file size at that
site; the genuine size check lives elsewhere and emits its own warning. The wording
arrived with a rename from the accurate `Truncated at cluster %d`, and it sent my
first reading of your finding down a length-mismatch path. Both chain sites now
report what they actually found, and the `ERROR:` line that was counted as a repair
rather than an error is gone.

### Container hand-back, session 2 → 3 *(historical — completed)*

**No source changed, so your 534/534 still certifies the driver steps 4-6 will run
on.** The whole of this hand-back is a decision and a correction.

#### Step 2 is DEFERRED. Do not run it.

**The cell it asks for cannot be built with the driver you are holding, and that is
a fault in the run sheet, not in your reading of it.** Three facts, in the order that
matters:

1. **`setSPISpeed()` leaves high-speed mode on the way through.** The
   `CMD_SET_SPI_SPEED` handler calls `applyDefaultSpeedMode()` — a CMD6 switch back
   to default mode — *before* it applies any hand-set clock. So `attemptHighSpeed()`
   followed by `setSPISpeed(25_000_000)` lands in **default mode at 25 MHz**: round
   10b's arm, already measured, not the missing cell. Your search found no
   instrument for the cell because the driver has no way to reach it.

2. **The cell was tried once and failed hard — though *why* is not established.**
   Round 8a run 2 built this exact cell by accident — a verified high-speed switch,
   then a hand-set 25 MHz,
   before that exit was hooked — and every operation after it returned `-7`
   (`SD_RT_speed_tests` #9/#12). Hooking that exit is item 5 of the bundle you just
   certified.

   **The `-7` is measured; the explanation for it is not.** It was attributed to the
   card sitting on high-speed output timing while the host sampled on default-mode
   timing, and that inference is shakier than it looked: the round 9b read band at
   hp=7 is `[-1..12]` — 13 to 14 ticks of a 14-tick bit period, essentially the whole
   period — and a mode shift the size of the one seen at hp=4 should not strand a
   band that wide. The write side is a live alternative: test #9 was a
   `createFileNew`, and the tx teeth at hp=7 sit at `≡ 1 (mod 7)`.

3. **Reaching the cell is a campaign, not an arm.** It needs a debug-only knob that
   sets the clock without the switch-back, *and* — because we do not know which side
   failed — both a read-band phase sweep and a tx tooth map at hp=7 *inside* verified
   high-speed mode. Round 12d showed bands do move with the card's mode (hp=4 inside
   high speed is `[-3..+4]` centre 0, against `[2..8]` centre +5 outside it), so
   neither map transfers from the default-mode measurements we hold.

#### Why deferred rather than built now

- **A driver change invalidates your 534/534.** A certification run is atomic. The
  knob would be debug-only and would not alter what ships, but it would still cost a
  full re-sweep before steps 4-6 could start.
- **The scarce resource this round is the deployment-bound cards.** They are
  one-shot. The Samsung EVO is retained and will be on the shelf whenever we come
  back to it. Unrepeatable work goes first.
- **Nothing downstream needs the answer.** Step 6 is two-armed *by design*, so the
  sweep produces release numbers for whichever policy is eventually chosen. That is
  precisely the job two arms were added to do.
- **v1.8.0 does not change the high-speed default.** It ships high speed opt-in with
  correct mode bookkeeping. The policy belongs to a later release.

The punch-list entry is corrected — it had claimed "the driver already supports it",
which is what put an unreachable step on this sheet — and re-classified from release
gate to open product decision, carrying the three-step design for the real
experiment.

#### Settled without bench time — do not spend a slot on it

The Samsung EVO PSN question (catalog row keyed `C0305565`, the campaign card reads
`$4AC8_5F42`) is **not** a transcription error: `DOCs/cards/samsung-gd4qt-128gb.md`
already documents two physical units of the same model. The sweep's per-card
`CARD-ID:` line keys whichever unit is in the socket, so this resolves mechanically
when you get there.

#### Then

Resume at **step 4** (16b, the Lerdisk in the Edge socket), then step 5, then step 6.
The Samsung EVO can be unstaged.

### Container hand-back, session 1 → 2 *(historical — completed)*

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

**First-light status, updated after session 2.** The driver is certified on hardware
(534/534) and `SD_card_identify` is verified end to end, emitter through harvester.
**`SD_performance_benchmark` and `SD_speed_characterize` have still not run since
their 2026-08-19 rewrite** — their identity and CATALOG lines were fixed alongside
`SD_card_identify` but only that one has been proven on a card. Expect first-light
friction at step 5, and run one throwaway benchmark through `harvest_catalog.sh`
before any one-shot card goes in the socket.

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

## Step 2 — 16d: the speed-policy cell — ⏸ DEFERRED, DO NOT RUN

**Deferred 2026-08-19, before it ran. The cell is unreachable with the shipped
driver; the full reasoning is in the session 2 → 3 hand-back above.**

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

## Step 4 — 16b: the Lerdisk in the EDGE socket — ✅ RAN; attribution owed

**⚠ Do NOT start this step with `./run_regression.sh`. That reformats the card, and
the card is currently holding evidence.** The ordered continuation is **4a → 4b →
4c** in the session 3 → 4 hand-back at the top of this sheet; 4a is read-only and
must go first.

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

- [x] Step 0: both 64 GB PSNs recorded, `00000F14` marked green
- [x] Step 1: **534/534** (session 2, sweep `260819-155926`)
- [~] Step 2: **deferred** — cell unreachable on the shipped driver; funding the campaign is Stephen's call
- [~] Step 3: **deferred to after step 6** — no default change in v1.8.0 either way
- [~] Step 4: wedge **GONE** (mount 45/45, raw 14/14 in the Edge socket); closing audit found an unterminated chain — attribution owed via 4a/4b/4c
- [ ] Step 4: Lerdisk verdict in the Edge socket
- [ ] Step 5: run variance measured before instance variance; one-shot cards fully captured
- [ ] Step 6: catalog tables harvested, single driver-version banner
- [ ] Card records created for the two uncatalogued retained Gigastones

**Then and only then** the v1.8.0 release gate is satisfied.
