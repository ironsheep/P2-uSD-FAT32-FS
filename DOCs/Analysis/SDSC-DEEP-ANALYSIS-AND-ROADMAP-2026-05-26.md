---
title: SDSC counterfeit (asdfg) wedge — deep cross-source synthesis + investigation roadmap
date: 2026-05-26
author: Stephen M Moraco (synthesis by Claude)
sources:
  - DOCs/Specs/Part1_chunks/ (SD Physical Layer Simplified Spec v9.10, Part 1)
  - DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md (running log, sessions 2026-05-18 … 2026-05-25)
  - DOCs/cards/lerdisk-asdfg-1gb.md (per-card profile)
  - src/micro_sd_fat32_fs.spin2 (driver under audit, 7,939 lines)
  - tools/logs/ (May 24-26 raw_sector_tests and mount_tests)
  - DOCs/Analysis/_SDSC_DEEP_RESEARCH/01_spec_findings.md  (full spec inventory)
  - DOCs/Analysis/_SDSC_DEEP_RESEARCH/02_driver_audit.md   (forensic code walk)
  - DOCs/Analysis/_SDSC_DEEP_RESEARCH/03_test_log_evidence.md (test-log timeline)
---

# Where we are, what we know, what to chase next

## Section 1 — The picture, in 60 seconds

Two counterfeit SDSC cards (Cloudisk `$0000_1680`, Lerdisk `$0000_01F4`, both PNM `"asdfg"`, MID `$05`, PRV 2.2, sequential MDT 2025/11 and 2025/12) share a deterministic failure pattern on the **P2 Edge socket** (CS=60 MOSI=59 MISO=58 SCK=61). The same cards work cleanly on the **external SPI header** (CS=20 MOSI=19 MISO=18 SCK=21). The cards are in the spec-defined "dummy data-CRC" class (`cardWarnings()=$04`, `CW_NO_DATA_CRC`). The driver detects this via `probeDataCrc` and disables read-side CRC validation but otherwise treats them identically to SDHC.

Multi-week investigation has eliminated almost every plausible electrical/timing hypothesis. **The three signaling-level health checks all pass on the failing Edge run** (bus idle high, R1 returns fast, MISO release on busy is genuine). The wedge is at a higher layer.

Three driver-side *silent-error reporting bugs* have already been fixed (`a7dc362`, `dbe5cc9`, `bfeb20e`). They were all instances of the same anti-pattern — **a `0` return value collides with a legitimate "everything fine" value (R1=$00 / R2=$0000 / success), so the driver consumes a silent failure as success**. Each fix sharpened the symptom; the residue is the actual mechanism. After fix `bfeb20e`, the failure shape on Lerdisk is sharp and reproducible:

```
write #1 (sector 100_000)  → wire-level SUCCESS (code=7, R1=$00, dresp=$05, busy clears)
read  #1 (sector 100_000)  → CMD17 sent, $FE start token NEVER arrives    → E_TIMEOUT
write #2 (sector 100_001)  → CMD24 R1 = $00 fast, data-response token NEVER arrives → code=2 drespTO
write #3-5 (sectors 100_002-100_004) → CMD24 issued, NO R1 EVER ARRIVES (1 s × 138_000 polls) → code=8
```

**This is the spec's command-rejected-while-busy state (Part 1 §7.2.8) presenting as silent-no-R1.** The card has entered an internal post-write state from which it does not recover until power-cycle. Counterfeit FTL semantics, not bus electrical.

The cross-source synthesis below identifies **one concrete candidate root cause (a fourth silent-error bug in `writeSectors`)**, **three secondary mechanisms** worth chasing in priority order, and **specific experiments** that decide between them.

---

## Section 2 — Established facts (do not retest)

Established by experiment + cited evidence. These should bound the search; don't relitigate them.

### 2.1 Card identity

| Card     | SN          | MDT     | Capacity | Notes                                           |
|----------|-------------|---------|----------|-------------------------------------------------|
| Cloudisk | $0000_1680  | 2025/11 | ~1.9 GB  | original investigation card                     |
| Lerdisk  | $0000_01F4  | 2025/12 | 960 MB   | sequential serial, twin silicon                 |

Both: MID `$05`, PNM `"asdfg"`, PRV 2.2, CID CRC7=$00, CSD v1.0 (SDSC), TRAN_SPEED claims 25 MHz, `cardWarnings()=$04` (dummy data-CRC). Counterfeit classifier scores Lerdisk 15, Cloudisk 16. Both confirmed counterfeit.

### 2.2 Driver SPI ceiling (post-probe-fix)

After commit `6b2a0fa` the driver's `probeSpiCeiling` plus exact-target pre-backoff settles to:
- sysclk 320 MHz → SCK 22.857 MHz (hp=7)
- sysclk 350 MHz → SCK 21.875 MHz (hp=8, exact-target pre-backoff fires)
- sysclk 250 MHz → SCK 20.833 MHz (hp=6)

Empirical clean-read ceiling on **external connector**: between 22.86 MHz (clean) and 24.29 MHz (single-bit flips). The driver runs the card safely below this on either socket.

### 2.3 Disproven hypotheses (with strong evidence)

| Hypothesis                                         | Evidence ruling it out                                             |
|----------------------------------------------------|---------------------------------------------------------------------|
| Floating MISO between commands                     | E2f (P_HIGH_15K) didn't change wedge                                |
| CMD13 trailing capture leaves card non-responsive  | Disabling checkCardStatus() didn't help                             |
| Card needs N settle clocks after busy-clear        | 8-clock CS-LOW guard added; no change                               |
| Driver overshoot above 25 MHz SCK ceiling          | Probe lands at 21.875 MHz, well below 24.29 MHz fail threshold       |
| Smart-pin retention from prior init                | `pinclear(sck/mosi)` added (C1); wedge unchanged                    |
| Recovery-flush clock count too low                 | MISO releases at ~5500 extra clocks but CMD0 still returns $00     |
| `cmd()` busy-tail $00 confused for R1=$00          | Card emits $00 for full 1 s; fixed by `bfeb20e`                     |
| Debug ISR per-instruction overhead                 | P2KB: event-triggered, zero idle cost                               |
| Debug serial-output time gives card settling       | Success run had *shorter* gap than failing run                      |
| Code-layout / hub-address timing shifts            | Egg-beater is cog-phase-deterministic                               |
| Bus electrical: stuck-low MISO                     | `cmd13_pre_capture` = $FF×7 (genuinely idle high)                   |
| 100 ms `waitDataResponse` timeout too tight        | 1000 ms bump → still no response on write #2                        |
| Transient `$FF` blip during busy mis-detected      | 3-consecutive guard → identical failure pattern                     |

### 2.4 The remaining symptom is at the protocol layer, not the wire

After all the disproven hypotheses, the **bus is verifiably healthy** at the moment of each observed failure: idle high during CMD13, R1 arrives quickly on the still-recoverable commands, MISO release on busy is genuine (passes 3-byte-$FF test), no bit corruption on data. **The card simply refuses the data phase of write #2, then refuses the entire command of write #3+.**

### 2.5 The Edge-vs-External asymmetry is real but no longer believed to be the proximate cause

On the external header with longer wires, this same card and same driver pass `raw_sector_tests` cleanly. On Edge, the wedge fires deterministically after `mount_tests`. The longer-cable-helps interpretation (slew damping / reflection absorption) is a real PCB SI phenomenon, but every signaling-level check we can make at the P2's pins says **the Edge bus is electrically clean during the wedge itself**. The two interpretations now consistent with all evidence:

- Edge socket has slightly tighter margin somewhere we cannot probe (analog overshoot at the *card's* input, sub-ns ringing the P2 cannot synchronize). The card's input filter would see extra edges the P2 cannot see. **Possible, not directly testable without a hardware LA on the Edge socket (which we cannot attach).**
- A driver protocol bug is *triggerable* on Edge for reasons unrelated to electrical (e.g., faster sysclk → tighter post-write timing → spec §7.2.8 violation). **More likely given the evidence.**

The second interpretation is the working assumption for everything below.

---

## Section 3 — The single most likely root cause (top-priority candidate)

**The investigation has spent ~8 sessions on the read/single-block-write paths. The actual wedge-arming event is in the multi-block write path (`do_writeSectors`, CMD25) called by mount_tests before the failing CMD24/CMD17 in raw_sector_tests fires.** That path has a fourth silent-error bug of the same family as the three already fixed.

### 3.1 The bug — `writeSectors` does not disambiguate `cmd()` R1=timeout from R1=$00

Driver audit finding **C-1**, src/micro_sd_fat32_fs.spin2:

```spin2
' Line 6741-6742 (writeSectors / do_writeSectors)
resp := cmd(CMD25, start_sector << hcs)
if resp <> $00                         ' <-- bug: $00 means "clean" OR "timeout"
    pinh(cs)
    return E_BAD_RESPONSE
```

Compare to the post-`bfeb20e` writeSector path:

```spin2
' Line 6591-6601 (writeSector / do_writeSector)
resp := cmd(CMD24, sector << hcs)
if diag_cmd_r1_ms < 0                  ' <-- distinguishes timeout from clean R1
    pinh(cs)
    return E_TIMEOUT
if resp & R1_FATAL_MASK
    pinh(cs)
    return E_IO_ERROR
```

`cmd()` returns `false` (= integer 0) on R1 timeout (line 6166-6177) AND `$00` for a clean R1 with no error bits. The two are wire-different but byte-identical at the API. `writeSector` was patched in `bfeb20e` to also check `diag_cmd_r1_ms < 0`. **`writeSectors` was not.**

### 3.2 Why this matches the symptom progression

Mount_tests does file I/O. The driver's file-write paths use multi-block writes via `do_writeSectors` (CMD25). If the counterfeit silicon's CMD25 R1 ever silently fails to acknowledge (within a 1 s budget) on Edge — for any reason at all, including transient busy from a prior FAT-extension write — the current code path does:

1. `cmd(CMD25, ...)` returns 0 (R1 timed out, card never acknowledged CMD25).
2. `if resp <> $00` is **false** → no error path.
3. Driver proceeds into the per-block write loop: data-start token `$FC`, 512 data bytes streamed via PASM streamer, CRC bytes, `waitDataResponse`, busy-poll.
4. The card never received CMD25 — it is in whatever state the prior command left it in, plus 512+N bytes of garbage clocked into it.
5. The data-response wait probably times out (card has no idea what we want). The driver fires `recoverToIdle()` (CS HIGH + dummy clocks) but the card's internal state is already corrupted.
6. `writeSectors` returns SUCCESS up the stack to whatever caller mount_tests invoked.
7. Whatever the file API thinks just got written, didn't. mount_tests continues. Whatever sector was the "start" of CMD25 — typically a FAT entry, FSInfo, or file data — is now in an indeterminate state on the card.

This is the exact same shape as the original Cloudisk "Phase 2: writeSector → readSector wedge" picture in the 2026-05-19 log entry. Mount_tests' file ops use `do_writeSectors` for file data > 1 sector and during FAT extension. The dummy-CRC tells the card "ignore the data CRC"; the card has no protection. The driver has no protection. **The card silently accepts arbitrary state corruption.**

After this, `unmount()` runs `updateFSInfo` which calls **single-block** `writeSector` to write FSInfo. That call lands on a card whose internal state machine is already in §7.2.8 "all commands rejected while busy" mode — which is exactly the F1 symptom that surfaced on Cloudisk via the smell-fix `a7dc362`.

### 3.3 What the spec adds (Part 1 §7.2.4, §7.2.8, §4.4)

- §7.2.4 lines 1717-1722: *"If the card is reselected before the programming is finished, the DataOut line will be forced back to low and all commands will be rejected."*
- §7.2.8 lines 1788-1798: *"A command may be rejected … It is sent while the card is in Busy."*
- §4.4 lines 1821-1828: *"After the last SD Memory Card bus transaction, the host is required, to provide 8 (eight) clock cycles for the card to complete the operation."*

Once the driver issues CMD25's data bytes into a card that didn't acknowledge CMD25, the card is left in its prior internal state — which after a real prior write is the post-busy/internal-FTL state. Sending data tokens to a card not in "wait for data block" violates the spec implicitly, and §7.2.8 lets the card reject everything subsequently. The spec offers no soft recovery — power cycle only.

### 3.4 Why this would NOT have been seen on the external connector

On the external connector the longer cable + extra capacitance slows everything by a few ns per edge. The card's FTL has slightly more wall time per byte-time. A counterfeit FTL whose post-write internal busy clears at ~T-microseconds on Edge may clear at ~T+δ microseconds on External — and the host's command-spacing happens to land *after* the FTL is done on External, *during* the FTL on Edge. The bug exists on both sockets, but only Edge triggers it.

### 3.5 Confidence

- **The bug is real and reproducible by code inspection** (driver audit C-1).
- **The class of bug (silent-zero collision) has shown up THREE times already** in this exact investigation — strong prior.
- **Mount_tests is the precondition that primes the failure** — and mount_tests is what uses the CMD25 path.
- **The symptom shape (Stage 2 → Stage 3 cascade) matches what would happen if CMD25 silently bricked the card's state without the driver knowing.**
- **External-vs-Edge asymmetry is consistent with FTL-timing-margin sensitivity, not with a bus electrical issue.**

This is the single highest-confidence root-cause candidate in the entire investigation. The fix is the same pattern as `bfeb20e`, applied to `writeSectors`.

### 3.6 The fix

```spin2
' src/micro_sd_fat32_fs.spin2, around line 6741
resp := cmd(CMD25, start_sector << hcs)
if diag_cmd_r1_ms < 0
    pinh(cs)
    return E_TIMEOUT
if resp & R1_FATAL_MASK
    pinh(cs)
    return E_IO_ERROR
if resp <> $00
    pinh(cs)
    return E_BAD_RESPONSE
```

(Apply the same three-tier check pattern that the post-`bfeb20e` `writeSector` uses.)

### 3.7 Predicted experimental outcomes

After applying the fix:

| Scenario                                       | Expected outcome                                                                |
|------------------------------------------------|---------------------------------------------------------------------------------|
| Mount_tests on Cloudisk-Edge after power-cycle | If CMD25 ever silently fails: now visible as `-1 E_TIMEOUT` from file write     |
| Then unmount                                   | If CMD25 wasn't silently failing, `updateFSInfo` still fails (different cause)  |
| If CMD25 IS silently failing                   | Mount_tests fails earlier with a real error code; subsequent ops never run     |
| raw_sector_tests after fresh power-cycle       | Should still pass 14/14 (no change to single-block path)                       |
| raw_sector_tests after a successful mount_tests | Should pass if mount_tests' CMD25 issues are visible and don't poison the card |

**The fix may simply make the failure honest** (mount_tests fails with -1 instead of silently passing while bricking the card). That alone is progress: it surfaces the *real* underlying mechanism so we can chase it.

---

## Section 4 — Secondary candidates (chase after Section 3 fix lands)

These are the next-highest-suspect items. None has the prior of "fourth instance of a three-times-proven anti-pattern" — but each is concrete, falsifiable, and grounded in the spec or driver code.

### 4.1 CMD16 SET_BLOCKLEN warning-only error path

**Driver audit E-2 / Spec §4.3.4.**

```spin2
' Line 6087-6091 (initCard)
if hcs <> 0   ' SDSC
    if cmd(CMD16, SECTOR_SIZE) <> $00
        debug("...CMD16 SET_BLOCKLEN warning...")
        ' init continues; no failure return
```

Spec mandates CMD16 = 512 for SDSC writes (§4.3.4 / Table 4-5). If the counterfeit silicon silently rejects CMD16 (returns non-$00 R1 or doesn't apply the value), the driver continues with whatever block length the card defaults to. The CSD might claim 512 but the silicon might honor 1024 (or vice-versa). Every CMD17/CMD24 would then desync the streamer mid-block.

**Why this is a secondary not primary candidate:** if CMD16 were silently failing the FIRST write of any test would already corrupt — but write #1 of `raw_sector_tests` succeeds at the wire level (write #1 = full SUCCESS code=7). So either CMD16 is being honored, or the symptom isn't block-length related.

**Investigation:** Add a CH_INIT debug at line 6087-6091 to log the CMD16 R1 value on Cloudisk and Lerdisk. If R1=$00 (clean), this hypothesis is dead. If R1≠$00, it's a smoking gun.

### 4.2 The per-block waitBusyComplete-then-fall-through-to-$FD path in writeSectors

**Driver audit C-3.**

Inside `do_writeSectors`, lines 6790-6797: if `waitBusyComplete` times out per-block, the loop `quit`s but the post-loop code still sends `$FD` (Stop-Tran token) and a `$FF` stuff byte to the card *which is still programming a block*. The driver eventually calls `recoverToIdle()` (force CS HIGH + 80-240 clocks), but by then the card may be in an indeterminate internal state.

**Why this is a secondary candidate:** If mount_tests' CMD25 bursts complete cleanly at the wire level (no per-block timeout), this path is never taken. The Section 3 fix (R1-timeout detection on CMD25 itself) more directly addresses the silent-failure family. But if Section 3's fix lands and mount_tests STILL wedges the card, this is the next thing to investigate — instrument the per-block busy-wait and capture how often it nears the timeout.

### 4.3 The zero-SCK gap between CRC LSB and first MISO poll for data-response

**Driver audit D-2 / Spec §7.3.3.2.**

In `writeSector` and `writeSectors`, between the last CRC byte's transmission and the first poll byte of `waitDataResponse`, there are **zero SCK clocks**. Several µs of Spin2 interpreter overhead, but the bus is idle (no clocks). This is spec-permitted (the first `sp_transfer_8($FF)` poll provides clocks for the card to shift out the response), but on a marginal card it can be tight.

**Why this is a secondary candidate:** Investigation 2026-05-25 already bumped `waitDataResponse` timeout to 1000 ms; write #2 still timed out — so it's not "we gave up too early," it's "the card never emitted a response." If the card never emits, more clocks won't help. But if the *first* poll byte starts before the card is internally ready to even emit, the card might never enter the emit state. **Diagnostic: add an idle byte transmission (`sp_transfer_8($FF)`) AFTER the CRC LSB and BEFORE entering `waitDataResponse` — 8 extra dummy SCK with MOSI=high before polling.** Tests whether the gap is the issue.

### 4.4 Determinism of the DEBUG_MASK-on / DEBUG_MASK-off divergence

**Running log §2026-05-24.**

The single observation that DEBUG_MASK = `(1 << CH_MOUNT) | (1 << CH_SECTOR)` reverses the outcome from 16/14 fail to 31/31 pass is unexplained. Every plausible mechanism has been disproven (ISR overhead, serial settling time, code layout, hub timing). **The observation has not been determinism-tested.**

Run `mount_tests × 2` per DEBUG_MASK setting (4 total runs), with a power cycle between each. If both settings reproduce their results consistently → there IS an unknown mechanism. If one setting is variable → it was variance, and "DEBUG_MASK matters" gets retired.

**This is high information value, low cost — should be done in parallel with Section 3.**

### 4.5 The "raw_sector_tests after mount_tests" sequence-specific trigger

**Running log §2026-05-25.**

The wedge requires `mount_tests` to be run before `raw_sector_tests`. Either alone passes. The class of operations mount_tests performs that raw_sector_tests does not: **CMD25 multi-block writes** (via file I/O) and **CMD13 polls** (via the routine handle ops).

If Section 3's fix exposes a CMD25 silent failure, it answers this. If not, run reduced reproducers to find which mount_tests operation specifically primes the wedge:

| Reduced repro                              | What it isolates                            |
|--------------------------------------------|--------------------------------------------|
| mount → unmount only, then raw_sector_tests | Pure mount/unmount priming (no file ops)   |
| mount → read one file → unmount, then RST   | Read-only priming (CMD17 + CMD18 only)     |
| mount → create + write one file → unmount   | One CMD25 burst, then test                 |
| mount → write to one DIRECT sector via raw, then RST | One CMD24 burst, then test         |

The minimal triggering sequence isolates the spec-section we're tickling.

---

## Section 5 — Outright weaker hypotheses, ordered (do not start here)

These are *possible* but each has stronger evidence against it than for it. Listed for completeness so they don't get re-investigated by accident:

### 5.1 SI ringing creating extra SCK edges at the card input

Disproven by: signaling-level health checks all pass at the P2 input; `cmd13_pre_capture` is idle-high during the failure; bit corruption is not observed (data integrity at the wire is intact). Cannot be **completely** ruled out because we cannot probe the card's input directly. If everything else is exhausted, the next test is: **drop SCK to 1 MHz for the writeSector / writeSectors path on Edge** and see if the wedge persists. If wedge survives 1 MHz, SI is finally dead as a hypothesis.

### 5.2 PCB pull-up absence on MISO

Disproven by E2f (P_HIGH_15K added to MISO; no effect). Spec wants host pull-up; absent here. Irrelevant to the wedge but a real correctness improvement worth keeping in the code regardless.

### 5.3 Stale `card_warning_flags` leaking across init attempts

**Already fixed.** Driver audit E-4 confirms `card_warning_flags := 0` at top of `initCard()` (line 5875). The originally-flagged "smell #2" from the 2026-05-23/24 session was resolved.

### 5.4 `do_unmount` swallows `updateFSInfo` failures

**Already fixed** in commit `a7dc362`. The current symptom (-7 from unmount) only became visible because of this fix.

### 5.5 Token wait loop returns prematurely on transient $FF

Disproven by 3-consecutive-$FF guard experiment. Card's busy release is a clean signal, not a blip.

### 5.6 The streamer-to-smart-pin transition in writeSector

Driver audit A-1 / A-2 / A-3 found no ordering bug. Pin states between PASM streamer end and CRC byte transmission are clean. The smart-pin re-arm at line 6647 technically violates p2kb's "DIR=0 before WRPIN" rule but the prior `pinclear` did reset the smart pin before streamer; this is defensible. Not a likely vector.

### 5.7 The dummy-CRC code path

Driver audit E-3 confirms `CW_NO_DATA_CRC` only affects read-side CRC validation. Write side computes and sends a real CRC regardless. Not a vector.

### 5.8 Lock / COGATN / send_command mailbox primitive

Surveyed clean in the running log §2026-05-25 (continued). Works for thousands of operations per regression run on every other card. Not a vector.

---

## Section 6 — Diagnostic tool and test-utility gaps

The investigation has been gated by tool limitations as much as by the bug itself. Each is worth a small, focused improvement.

### 6.1 The fsck/format/audit/check pattern of swallowing read failures

The running log notes that ~25 sites still have the `isp_fsck_utility` / `isp_format_utility` shape of calling `readSectorRaw` / `writeSectorRaw` and not checking the return code. Each is a silent-failure-masquerading-as-data-corruption vector. **Single sweep commit:** find every call site, route through a helper that asserts the return code or logs `(sector, status)`. This was started in `isp_format_utility` (commit reference unknown) and `SD_RT_raw_sector_tests` (E5 fix) but is incomplete.

### 6.2 `sendCmd13Transaction` cannot distinguish "card OK" from "stuck-low MISO"

Both produce R2 = $0000 (driver audit Survey 5 / 2026-05-25). The driver already captures `cmd13_pre_capture[]` (the full-duplex MISO bytes during CMD13 transmission) — but never inspects it. A stuck-low MISO would yield `cmd13_pre = [$00 × 7]`; healthy is `[$FF × 7]`. **Cheap fix:** in `checkCardStatus`, if R2=$0000 AND `cmd13_pre` contains any $00, escalate to "card stuck" rather than "card OK."

### 6.3 `dumpReadFailDiag` reports init-residue CRC values on dummy-CRC cards

`rxCRC` is always $0000 on dummy-CRC silicon (intentional). `calcCRC` is init-residue from the most recent successful CRC computation (the `probeDataCrc` value). Both fields actively mislead readers of failure dumps. **Cheap fix:** annotate or suppress these fields when `CW_NO_DATA_CRC` is set.

### 6.4 No "post-write delay sweep" reproducer

The single decisive open experiment from the 2026-05-25 evening session was "add `waitms(50)` after writeSector success." Build a small diagnostic that does the minimal reproducer (`initCardOnly → write → wait(N) → write → check`) with a parameter sweep over N. Outcome cleanly separates "card needs more time" from "card has a protocol-level issue." **High decisiveness, low cost.**

### 6.5 No CMD25 burst reproducer separate from mount_tests

The investigation conflates "mount_tests poisons the card" with "CMD25 is the culprit." A standalone diagnostic that does only one CMD25 multi-block burst (no filesystem context) and then tries the next CMD24/CMD17 would isolate the trigger. Could be built on top of `SD_audit_repro.spin2` pattern.

### 6.6 Soft LA capture has never been run on the wedge

The 2026-05-19 session built the soft LA tool (`diagnostic-tests/SD_soft_la_test.spin2`) explicitly because hardware LA cannot attach to Edge socket. **It has not been used to capture the actual writeSector → next-command transition on the failing path.** This is the single most expensive instrumentation gap. If Section 3's fix doesn't resolve the wedge, soft LA capture is the next escalation.

---

## Section 7 — Proposed investigation roadmap (ordered, with stop conditions)

Each step has a yes/no outcome that determines the next step. Run in order; do not skip.

### Step 1 — Apply the Section 3 fix to `writeSectors`

**Change:** add the three-tier R1 check pattern (timeout / fatal / non-zero) to `writeSectors` at line 6741-6742, matching `writeSector`'s post-`bfeb20e` pattern.

**Test:** run `mount_tests` on Cloudisk-Edge and Lerdisk-Edge with a power-cycle before each.

**Decision tree:**
- (a) mount_tests now fails earlier with a real error code from a writeSectors call → **the bug existed and was hiding the real symptom**. Look at where it fails. Section 3.7 predicts. → proceed to Step 2.
- (b) mount_tests still passes; subsequent raw_sector_tests still wedges → CMD25 R1 was never silently failing, the bug class is elsewhere. → proceed to Step 4.
- (c) mount_tests passes; subsequent raw_sector_tests now passes → **the fix resolved the wedge.** Run the full regression. If it passes, write up and ship.

### Step 2 — If (a): trace the actual CMD25 failure cause

If mount_tests now fails honestly with a CMD25 R1 timeout, the question becomes: *why is the card silent on CMD25?* Spec §7.2.8 says "rejected while busy" — what put the card in busy that mount_tests didn't notice?

Add instrumentation around the prior writeSector calls and prior CMD13s to identify the moment the card enters its "rejecting" state. Possible mechanisms (in declining likelihood):
- A prior `writeSector` declared SUCCESS but the card was actually still in FTL commit (busy-detection too eager on Edge);
- A prior `readSector` cross-mailbox + CS handoff happens fast enough to step on the card's internal state machine;
- A prior init step (probeSpiCeiling) does something the card retains;
- Mount-time CMD16/CMD58 sequence interacts with this silicon differently.

### Step 3 — Once CMD25 R1 failure cause is found, fix it

Likely one of:
- `waitBusyComplete` requires N consecutive $FF bytes (revisit 3-consecutive in the writeSectors per-block loop, not just the final wait);
- After CMD13 (or any post-write status query) inject 8 dummy SCK clocks with CS HIGH (§4.4);
- Insert spec-compliant Ncs gap between commands explicitly.

### Step 4 — If (b): the bug is in another silent-zero collision

Run a forensic grep for every call site of `cmd()` and verify each one checks `diag_cmd_r1_ms < 0` separately from the R1 byte. Specifically:

- `cmd(CMD0, ...)` — initCard line 6017-ish — check for collision
- `cmd(CMD8, ...)` — checked? CMD8 has a 4-byte R7 payload; the R1 byte is parsed but the timeout case may not be handled
- `cmd(CMD17, ...)` — readSector — has the protection? **Verify.**
- `cmd(CMD18, ...)` — readSectors — has the protection? **Verify.**
- `cmd(CMD23, ...)` — pre-erase count — silent failure here might affect CMD25 erase semantics
- `cmd(CMD55, ...)` — ACMD prefix
- `cmd(CMD41, ...)` — ACMD41
- `cmd(CMD58, ...)` — OCR read
- `cmd(CMD13, ...)` — inside `sendCmd13Transaction` — and CMD13's response shape is special anyway

Probably one of these is the actual culprit. Audit them.

### Step 5 — In parallel with Steps 1-4: determinism-test DEBUG_MASK

This is independent of the protocol investigation. Four runs: DEBUG_MASK=0 × 2, DEBUG_MASK=(MOUNT|SECTOR) × 2, with power-cycle between each. Resolves whether the observation is mechanism or noise.

### Step 6 — In parallel: add the diagnostic-tool fixes from Section 6.1, 6.2, 6.3

These don't fix the wedge but ensure future failures self-report honestly. Specifically:
- The `~25 sites` that swallow `readSectorRaw` return codes (Section 6.1)
- `checkCardStatus` consulting `cmd13_pre_capture` to detect stuck-low (Section 6.2)
- `dumpReadFailDiag` annotating init-residue CRC on dummy-CRC cards (Section 6.3)

### Step 7 — If Steps 1-6 all complete without resolution

Capture soft LA traces of the failing writeSectors → unmount → next-mount sequence on Edge. The investigation has explicitly named soft LA as "the next escalation" since 2026-05-19 and never executed. With Sections 3-6 done, the soft LA capture would be highly targeted.

### Step 8 — If even soft LA doesn't reveal the mechanism

Two final escalations remain:
- **Drop SCK to 1 MHz for the writeSectors path on Edge** (and writeSector for the unmount FSInfo path). If the wedge persists at 1 MHz, signal integrity is finally proven irrelevant.
- **Drop _CLKFREQ to 50 MHz** for the test. Egg-beater timing all stretches by the same factor; spec timings don't. If the wedge persists, the issue is independent of CPU speed — it's pure protocol.

---

## Section 8 — Spec-anchored "what counterfeit silicon shouldn't be doing" list

These are deviations the spec doesn't explicitly forbid but that real silicon obeys, and that counterfeit may violate. Useful as anchors for what's allowable when fixing the driver.

| Spec text                                                                                              | What counterfeit might do                                                                            | Driver defensive response                                                       |
|---|---|---|
| §7.3.2.2 line 928: "non-zero byte = ready"                                                              | Bring MISO HIGH transiently then back LOW for residual housekeeping                                  | Require N consecutive $FF (already tried 3 — try 8?)                            |
| §4.4 line 1821-1828: "8 clocks after the CRC status token"                                              | Need MORE than 8 clocks to fully clear internal state                                                | Provide 16+ clocks before next operation                                        |
| §7.2.4 line 1719: "if reselected before programming finished, all commands rejected"                    | Stay in this state indefinitely; spec offers no soft recovery                                       | Detect via silent-CMD24 and trigger explicit CMD0 reset (destructive but spec-clean) |
| §7.2.2 line 1493: "CRC error → R1 response regardless of command index"                                | Fail silently instead of returning R1 with error bit                                                 | Audit every `cmd()` caller for timeout-vs-R1=$00 collision (in progress)        |
| §4.3.4 / Table 4-5: "block length set by CMD16 = 512 for SDSC"                                          | Silently reject CMD16 or apply different value                                                       | Promote CMD16 warning to a hard failure on SDSC (audit E-2)                     |
| §7.3.3.1 line 1037: "data response token: 010 accept, 101 CRC err, 110 write err"                       | Never emit a data response token; just go to busy-low or hold MISO indeterminate                     | Already detected as drespTO (code=2); no spec-compliant recovery exists         |
| §7.2.1 line 1328: "The only way to return to SD mode is power cycle"                                    | (this is just for the SD→SPI transition; SPI mode is sticky)                                         | (informational)                                                                  |
| §7.2.4 line 1720: "CMD0 mid-busy may destroy data formats"                                              | Refuse CMD0 entirely until power-cycle (observed)                                                    | Hard-recover STEP 3 must include a CMD0 attempt even if destructive             |

---

## Section 9 — Brief notes on driver tests that surfaced gaps

The `mount_tests × 2 back-to-back` failure (16/14 after the smell-fix `a7dc362`) is itself a *test* and reproduces the wedge. **It is currently the most reliable, most economical wedge reproducer.** If we add a small CI-style test that runs mount_tests twice in the same session, it would catch any regression of the eventual fix without needing the raw_sector_tests staging.

The test suite `SD_RT_raw_sector_tests.spin2` is currently the wedge canary. Its 1/14 result on Lerdisk and 1/13 on Cloudisk is sharp and consistent. **Leave it as-is; it is the working diagnostic.**

The `diagnostic-tests/SD_audit_repro.spin2` and `SD_tempcog_repro.spin2` are useful for investigating the cog-handoff variant of the wedge (the 2026-05-19 cross-mailbox version). Keep them.

---

## Section 10 — One-screen TL;DR for resume

You're chasing a wedge on counterfeit SDSC (Cloudisk, Lerdisk; both "asdfg" silicon) that fires after `mount_tests` on the P2 Edge socket but not on the External header. Three rounds of silent-error reporting bugs have been fixed. The wedge is now sharp:

1. Some prior operation (almost certainly a CMD25 multi-block write inside mount_tests) puts the card into the spec-defined "commands rejected while busy" state (§7.2.8). The driver doesn't notice.
2. The next single-block write or read lands in that state — first symptom is "data tokens never arrive," next is "R1 never arrives."
3. Power cycle is the only recovery.

**The most likely root cause is a fourth instance of the same silent-zero collision bug pattern: `do_writeSectors` (CMD25 path) doesn't disambiguate `cmd()` R1 timeout from a clean R1=$00.** Same fix shape as commit `bfeb20e`, applied to `writeSectors` line 6741. The Section 3 fix is the single highest-prior next change.

If that fix surfaces the real CMD25 failure mechanism (Step 2), it goes to busy-detection (waitBusyComplete needing more bytes, or §4.4 missing 8 clocks). If it doesn't help, audit every other `cmd()` call site for the same collision (Step 4). In parallel, determinism-test the DEBUG_MASK observation (Step 5), clean up the swallowed-error sites (Section 6), and only escalate to soft LA capture if all of the above run dry (Step 7).

Files in `DOCs/Analysis/_SDSC_DEEP_RESEARCH/` document the spec citations, the driver audit, and the test-log timeline that ground each item above.
