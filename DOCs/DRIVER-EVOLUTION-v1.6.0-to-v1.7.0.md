# Three Releases of Defect Work: v1.6.0 through v1.7.0

**A technical account of what was wrong with this driver, how each defect was found, and what fixed it.**

*P2-uSD-FAT32-FS · written at the v1.7.0 release, 2026-08-12*

---

## Why this document exists

Between v1.6.0 and v1.7.0 this driver went through the hardest defect work of its life. Two data-corruption defects, a reporting architecture that discarded errors by design, and a write-path timing defect whose behavior depended on where the linker placed a variable. Along the way the regression suite — the instrument we use to certify the driver — turned out to have defects of its own, which for a period made it impossible to tell whether a red result meant the driver was broken or the test was.

This is the account of that work: what each defect actually was, how it presented, why the obvious guards did not catch it, and what the fix was. It is written for an engineer who wants to understand the failure modes of a bare-metal SPI storage driver — not as a changelog, which says what changed, but as an explanation of *why those things were wrong*.

Three themes recur, and they are worth naming up front because they are the transferable part:

1. **A validation that compares a thing to itself validates nothing.** This pattern caused two separate defects to survive for months, in two unrelated subsystems.
2. **A detected error that is thrown away is worse than an undetected one**, because the code that would have found it *already ran* and now reports success.
3. **When a timing anchor is an instruction you execute, every instruction between the anchor and the dependent event is part of the timing contract** — including the ones that only *sometimes* take longer.

---

## Part 1 — The state before v1.6.0

### 1.1 Where the write path came from

The write path's timing has a lineage, and it matters for Part 4.

| Release | What changed in write/read timing |
|---|---|
| v1.3.2 | Streamer write timing corrected for power-of-2 SPI half-periods (hp=4, hp=8) via NCO frequency adjustment |
| v1.5.1 | **Read** path gained timing margin: sampling adapts to the sysclk-to-SCK ratio, and bulk reads no longer begin sampling before the card drives data |
| v1.5.2 | **Write** path gained margin, "completing the read-path work from v1.5.1" |

That v1.5.2 change is the one to remember. In completing the write-path work, it *removed* a `WAITX` alignment delay from the write burst and relied instead on what a source comment of the time called "natural settling" — the incidental delay contributed by the surrounding instructions. The change was correct on the hardware it was measured on. What it actually did was convert an explicit timing guarantee into an implicit one, and Part 4 is the story of that implicit guarantee failing.

### 1.2 What v1.6.0 found: two corruption defects in rewriting existing files

Both defects were in **rewriting an existing file**. A file created once and written front-to-back — the data-logger pattern, appending sector-aligned records — was never affected, which is why the driver had shipped five releases without either surfacing.

**Defect one: a cross-boundary overwrite truncated the FAT chain.**

Reopening a file, seeking back into it, and writing across a cluster boundary caused the write path to *allocate a new cluster* at the boundary rather than following the chain the file already had. The file's existing tail was left allocated but unreferenced — orphaned. The user saw a successful write and a file whose content past the rewritten region was gone, with the space still consumed.

The fix is the distinction the driver now states explicitly in its theory of operations: at a cluster boundary, **follow the chain; allocate only at genuine end-of-chain**.

**Defect two: a mid-sector append zero-filled the bytes already there.**

Appending to a file whose length is not a multiple of 512 requires loading the existing final sector, merging the new bytes into it, and writing it back. The driver skipped the load and wrote a fresh buffer, so the bytes already in that final sector became zeros.

The fix: load the existing sector before merging.

**Recoverability differed sharply, and this is the more interesting engineering point.** The cross-boundary defect leaves *lost clusters* — a structural footprint that `SD_FAT32_audit` finds and `SD_FAT32_fsck` reclaims. The space comes back. The file's lost tail content does not.

The mid-sector append defect leaves **no filesystem footprint whatsoever**. The directory entry is right, the chain is right, the length is right; some data bytes are zeros. No tool can detect it, because there is nothing structurally wrong to detect. v1.6.0's release notes had to tell users that the only remedy was verification against a backup. That precedent matters — Part 4 produced a defect of exactly the same undetectable shape, and the v1.7.0 notes say so in the same words.

### 1.3 The third v1.6.0 finding: write failures were silent

Separately from the corruption defects, v1.6.0 found that a write that failed — full card, failing card, unresponsive card — could return success. This was the first sighting of the pattern that v1.7.0 later attacked systematically, and at v1.6.0 it was fixed only where it had been observed: writing, closing, syncing, unmounting, deleting.

The instinct that "there are probably more of these" was correct. There were nineteen more.

---

## Part 2 — v1.6.1: a small release, and a lesson about process

v1.6.1 was a packaging release. Three utilities did not build with the command their own documentation gave (`pnut-ts -d -I ..`), and one debug method was renamed to match what it did.

The technically interesting part of v1.6.1 is not in the release. It is that **v1.6.1 shipped a known documentation defect.** A public method whose docstring asserted the opposite of what its code did — `debugClearRootDir()` — was found by our own audit, written onto the punch list, and shipped two days later, because nothing in the process forced the question "is this fixed or accepted?" before the tag.

The response was a release gate, now recorded in the project's own contributing rules: at release time, every user-affecting item on the punch list is either fixed or explicitly accepted in writing, with the reason recorded. What is forbidden is passing one silently. Every punch-list entry now carries a classification line so the check is mechanical rather than a re-reading of the whole list.

This is why v1.7.0's gate walk is a documented step rather than a good intention, and why the audit blocks in Part 3 could be closed with evidence rather than optimism.

---

## Part 3 — v1.7.0's first half: the reporting architecture

### 3.1 The audit and what it found

The v1.7.0 work began with a read-through audit of every fallible operation in the driver: `DOCs/Analysis/ERROR-REPORTING-AUDIT-2026-07-31.md`. It produced **24 findings, 21 of them user-affecting** — the largest single block of gate items the project has carried.

They fall into recognizable families.

**Family A — the unchecked metadata write (9 findings).** The dominant pattern, and the most dangerous. A method performs a sequence of card writes to change filesystem metadata, checks none of them, and returns SUCCESS unconditionally. The failure modes are not "the operation didn't happen" — they are *corruption*, because the operations are ordered and a partial sequence leaves an inconsistent volume:

| Finding | On a failed write, the card holds |
|---|---|
| `allocateCluster()` — four unchecked FAT writes | cluster reported allocated, card still shows it free → the next allocation hands the **same cluster to a second file** |
| `do_delete()` — entry write unchecked, then frees clusters anyway | entry still live, clusters marked free → the file appears to exist, its clusters get reallocated, reading it returns another file's data |
| `do_movefile()` — source-entry delete unchecked | one chain owned by **two live directory entries in two directories**; deleting either frees clusters the other still points at |
| `do_newdir()` — both writes unchecked | a directory creation that wrote nothing reports success |
| `do_rename()` — entry write unchecked | rename reports success, file keeps its old name |

`do_newdir()` carried an extra irony worth recording: it *did* perform read-back verifications of both writes, and sent the results only to `DEBUG`. The driver ships with `DEBUG_MASK = 0`, so the verification ran, proved the write had failed, and printed the proof nowhere.

**Family B — the conflated error code (2 findings).** `searchDirectory()` returned the same value for "no such file" and "I could not read the directory." Nine public APIs therefore reported card I/O errors as `E_FILE_NOT_FOUND`.

The dangerous instance **failed open**. The three create paths use the search as an existence check, and read `false` as "the name is available." So a read error during that check caused a create to write a *second* directory entry and allocate a *second* cluster chain for a file that already existed: two entries, two chains, one name. The fix propagates a separate `search_io_status` so the check fails **closed**.

**Family C — the reason discarded at the API boundary (5 findings).** `readHandle()` returned a byte count with no way to distinguish "0 because end of file" from "0 because the card failed on the first sector." A file on a failing card was processed as a complete, empty file. This is the one v1.7.0 change most likely to affect existing code, and it is deliberately breaking: `readHandle()` now returns its error code when nothing at all was transferred, so **0 means end of file and nothing else**, and the new `handleError(handle)` supplies the reason for a short read.

**Family D — documentation asserting what the code does not do (3 findings).** `ERROR()` was documented as per-operation and implemented as sticky-since-boot. `sync()` documented failure codes it structurally could not produce — its dispatcher hardcoded `pb_status := SUCCESS`. This is the `debugClearRootDir` family, and the reason the release gate exists.

**Family F — the boolean that ate the reason (3 findings).** Thirteen fallible operations had been flattened to booleans in an earlier API migration. The worst was a genuine impossibility: `eofHandle()` and `isFileContiguous()` returned `TRUE`, `FALSE`, *or* a negative error code — and in Spin2 `TRUE` is `-1`, while `E_TIMEOUT` is also `-1`. "At end of file" and "the card timed out" were the same 32 bits. **There was no correct way to call either method**, and any existing code was already wrong on the error path. Both now return booleans only, with `ERROR()` distinguishing.

### 3.2 The structural problem: a failure with no caller to return to

One finding could not be fixed by adding a status check, and it is the most architecturally interesting of the 24.

The driver flushes buffered writes automatically after 200 ms of idle. That flush is initiated by **the worker cog itself** — there is no caller waiting on it, no mailbox transaction, nobody to return a status to. `do_idle_flush()` discarded the outcome of both its `do_sync_h()` and `updateFSInfo()` calls, and no mechanism existed by which a user could ever learn that a background flush had failed. For a program that writes without explicit syncs, *this is the path its data takes.* The data was gone and every subsequent call returned success.

The fix had to invent the reporting channel that the architecture lacked: the failure is retained in driver state and read by the new public `lastFlushError()` / `clearFlushError()`. It is the one place in v1.7.0 where the answer was a new API rather than a corrected return value, because the problem was structural rather than an oversight.

### 3.3 What the machine found that reading did not

Two of the nine Family-A findings — `do_rename()` and `do_movefile()` — were **not** found by the read-through audit. They were found by `tools/check_error_handling.sh` on its first run, a script that mechanically identifies fallible call sites whose status is never consumed.

A later pass found five more defects by a third method again: hand-editing error paths to fire and observing what the driver reported.

Three detection methods, three different yields, minimal overlap. The read-through found the architectural families; the mechanical checker found the individual sites a careful reader's eye slid over; deliberate fault injection found the ones where the code checked the status and then did the wrong thing with it. **None of the three was sufficient alone.** That is the reusable finding, and it directly shaped the test suite described in Part 5.

---

## Part 4 — v1.7.0's second half: the layout-sensitivity defect

This is the hardest defect in the driver's history, and the most instructive.

### 4.1 How it presented

During v1.7.0 development, after a commit that touched no timing code, four regression suites began failing with a signature that made no immediate sense:

| Suite | Symptom |
|---|---|
| `subdir_ops` | file created, handle valid → `openFileRead` returns **-40** (not found), `deleteFile` **-40** |
| `speed` | `Pattern mismatch at 0: got $0` — data reads back as zeros |
| `crc_diag` | `Pattern mismatch at 0: got $0 expected $30` |
| `cogcwd` | written data reads back 0 |

Two facts bounded it hard, and both were confusing:

- **The same suites were green on the committed tree**, on the same card, days earlier.
- **It was not a general write failure.** In the same sweep, `read_write` 49/0, `file_ops` 26/0, `directory` 30/0, `seek` 37/0, `volume` 31/0 — all passing.

Data written comes back as zeros, or the file cannot be found, but only in some suites, and only in some builds.

### 4.2 The hypotheses that were wrong

**Stack overflow corrupting the SPI pin configuration.** This was attractive because the memory map made it plausible: only 20 bytes separate the end of the worker stack from the `cs` variable, with `miso` at +28, `spi_rx_mode` at +44 and `spi_period` at +48. Corrupt `miso` or `spi_rx_mode` and reads return zeros; corrupt `spi_period` and you get `E_IO_ERROR`. The symptoms fit exactly.

It was **refuted by the guard**. `send_command()` checks the 16-byte stack guard after every command and overrides the status with `E_STACK_OVERFLOW`. Any overflow deep enough to reach `cs` must first pass through all 16 guard bytes, so it cannot arrive unreported — and the failing runs showed no `-26` anywhere. The guard was intact while the data was corrupt.

**Layout roulette as an explanation rather than a symptom.** For a period the working theory was that the driver was somehow sensitive to binary layout in an unbounded way — which is true, but stated that way it is not a mechanism, and it invited the wrong response (shuffle things until it works). The insistence on a *mechanism* is what eventually produced the fix.

### 4.3 The mechanism

The write burst's timing works like this. `DIRL`/`DRVL` on the SCK pin resets the `P_TRANSITION` smart pin's base-period counter, and **every SCK edge thereafter lands on a grid anchored at that DIR-rise**. `XINIT` starts the streamer, whose NCO ramps from zero at the instant it executes. So the phase between the outgoing MOSI bitstream and the clock edges that latch it is set entirely by **how many sysclks elapse between the `DRVL` and the `XINIT`**.

Every instruction in that window must therefore consume a fixed, known number of clocks. `WAITX`, `XINIT` and `WYPIN` do — two clocks each.

**`RDFAST` does not.** It blocks while the FIFO fills, and that takes **10–17 sysclks**. The spread is the hub egg-beater slot wait for the buffer address's hub slice — and *which slot a buffer sits on is a function of its hub address.*

`RDFAST` was sitting inside the phase window. So the data-to-clock phase was a function of where the linker had placed the driver's data. Measured with `pnut-ts -l` on both reproducer variants: the presence of the `SD_INCLUDE_SPEED` feature shifted the driver's DAT by 36 bytes — **exactly four hub slots** — which was enough on its own to move a build from the passing side of the boundary to the losing side.

On the losing side, the card **stored every sector one bit late.** Silently.

### 4.4 Why nothing caught it — two tautologies

This is the part worth carrying to other projects.

**The card said the write was accepted.** In SPI mode, write-CRC checking is off unless the host enables it with CMD59, and this driver has never sent CMD59. So the `dresp = $05` "data accepted" token only ever proved the **packet framing** was well-formed. It never proved the payload bits were the ones the caller supplied. A spec-conforming card with CRC enforcement enabled would have rejected these writes outright — the driver's decision never to enable CRC enforcement is exactly what let a wire-level corruption pass as success.

**Reading the sector back matched.** The shifted bytes were genuinely what the card had stored. A read returned them faithfully — the read path had been hardened in an earlier phase and was never affected — so a byte-compare of written-versus-read-back **agreed with itself**. The comparison was tautological: it validated that the card could return what the card had stored, which was never in question.

Note that this is the *same shape* as the `attemptHighSpeed()` defect found independently in the same release: that method wrote to the card at an unverified speed and compared the result against itself, so the check could not detect the failure it existed to catch. Two unrelated subsystems, one error of reasoning. **A validation that compares a thing to itself validates nothing** — and both instances survived review because the code plainly *did* perform a comparison.

The immediate error in the first analysis of this defect was to read the accepted-data token as evidence that the bytes at the card were correct, and therefore to look for the corruption on the capture side. The defect was on the write side.

### 4.5 The fix, and the difference between a fix and a workaround

`SETXFRQ` and `RDFAST` — and `WRFAST` on the read side — are hoisted **above** the SCK reset, at all three sites that had not already been hardened. The variable hub-slot latency is now spent *before* the phase-critical window opens. From `DRVL` onward every instruction is a fixed-two-clock cog op, `XINIT` sits at a compile-time-constant offset from the reset, and the phase becomes a build-independent constant.

**Only then is tuning meaningful.** A pad value chosen while the phase still moved with layout would have been meaningless — it would have been tuned to one particular binary. This ordering matters: *establish invariance first, then center the window.*

With invariance established, the pad was measured. `tx_align_delay` is the `WAITX` between the SCK reset and `XINIT`, and its behavior turned out to be non-obvious: pad-to-phase is a **sawtooth of period hp**, because SCK starts on the next base-period boundary after `WYPIN` while the streamer start moves continuously. Only hp distinct phases exist, no matter how far the pad is swept. At hp=7, across three sweep runs, exactly one phase loses — `pad ≡ 1 (mod 7)`, failing at pads 8, 15, 22 and 29, with all 24 other measured points passing. The shipped default of **4** sits at maximal mod-7 distance (3) from the cliff on both sides. The value it replaced, 2, sat one sysclk away from it.

Then the fix was tested for the property it claims. The driver's DAT was deliberately displaced by 1, 2, 4, 8, 12, 36 and 60 bytes and the suites re-run: **all pass**. That is the acceptance criterion for an invariance fix — not "it works now," but "it works at every displacement that used to matter."

### 4.6 The lineage, closed

Part 1.1 noted that v1.5.2 removed an explicit `WAITX` from the write path and relied on natural settling. That is where the implicit timing guarantee was created. v1.5.2 tagged on 2026-05-06; the losing layout arrived on 2026-08-11. The driver won that lottery for three months and three releases — v1.5.3, v1.6.0, v1.6.1 — until a commit that touched no timing code moved the DAT and lost it.

The source now carries the note: *"v1.5.2 removed WAITX align_delay here, relying on natural settling — that margin was a layout lottery, won until a41c839 lost it."*

**The general rule:** when a smart pin's timing is anchored by an instruction you execute, every instruction between that anchor and the dependent event is part of the timing contract. A hub-touching instruction in that window silently converts a timing constant into a function of memory layout. It will pass every test on the machine you wrote it on.

---

## Part 5 — The instrument was also under repair

A driver is certified by its regression suite. For a stretch after v1.6.1 that suite could not be trusted, and understanding why is as important as the driver defects.

### 5.1 Three root causes, not N failures

Post-v1.6.1, a sweep produced seven failing or blank suites plus three more failures elsewhere. The instinct — ten failures, ten investigations — would have been wrong. `DOCs/Analysis/POST-V161-ROOT-CAUSE-ANALYSIS.md` resolved them to **three** causes.

**Root cause 1: two stack detectors sharing one address.** `prepStackForCheck()` wrote its sentinel to `LONG[@cog_stack][STACK_SIZE]` — one long past the stack. With no gap long declared, that address *was* `cog_stack_guard[0]`. Two detectors demanded different values at one address (`$addee5e5` versus `$CC`), and since `start()` writes the guard first and the sentinel second, the guard always lost. `checkStackGuard()` became a **stuck-at-FAIL detector**.

This was latent and invisible for as long as the violation only reached `DEBUG`. Then the error-reporting work — correctly — escalated the check to the caller, and a stuck-at-FAIL detector became `-26` on every single command.

The attribution was exact: the seven suites failing were precisely the seven suites defining `SD_INCLUDE_STACK_CHECK`. No other suite was affected. `mount_tests` went 15/16 → 31/0 on the fix.

There is a lesson here that is easy to state and hard to remember: **escalating a detector's severity is a change to the detector's correctness requirements.** A false positive that only writes to a disabled debug channel costs nothing. The same false positive wired to a return value fails everything.

**Root cause 2: stale assertions for a retired contract.** Three tests still compared `eofHandle()`'s *return value* against error codes after the contract had deliberately moved the error to `ERROR()`. These were test defects, not driver defects — the driver was right and the suite was wrong.

**Root cause 3: the layout-sensitivity defect of Part 4**, presenting through four different suites and initially mistaken for something else.

**One defect, four detectors** — that framing is what eventually cracked it. The failing-suite *identity* was not the phenomenon; the shared signature was.

### 5.2 The suite's own defects

A systematic audit of all 27 suites for per-test preconditions and order-dependence found five suites genuinely fragile. Separately, the fault-injection suite shipped tests that armed a failure **at a point the driver never reaches** — deterministic test defects that had failed every run they had ever been part of, and one whose premise was simply unreachable.

That last category is the uncomfortable one. A test that has always failed carries no information, and a test that *cannot* pass is worse than no test, because it consumes attention on every sweep.

The project's response was a rule now recorded in its working practice: the regression suite is the certification mechanism, so **suite defects are fixed at the same priority as driver defects**, and false-green fixes come first. Tests do not get retired for being inconvenient; missing test facilities get added.

### 5.3 Why the error-injection suite is built the way it is

Part 3 established that 21 user-affecting findings were all invisible to success-path testing — the code *ran*, it just discarded the answer. Proving those fixes requires manufacturing the failures, which is what `SD_INCLUDE_TEST_HOOKS` exists for: `setTestFailSector()`, `setTestFailWriteAfter()`, `setTestMaxClusters()`, `getTestWriteCallCount()`, `clearTestErrors()`. They are enabled by `SD_INCLUDE_ALL` and **deliberately not** by `SD_INCLUDE_DEBUG`, so a consumer who wants diagnostics cannot accidentally compile fault injection into a shipping product.

The resulting suite has a structure worth copying. **Its first four groups test the injector, not the driver:** that nothing fails when nothing is armed; that a named LBA fails and only that LBA; that `setTestFailWriteAfter(n)` fires on the nth write and not the n±1th; that one-shot arms stay one-shot and `clearTestErrors()` really disarms.

The reason is that a red in this suite is ambiguous in a way other suites' reds are not — it can mean the driver stopped reporting an error, *or* that the injector never armed the failure. If the first four groups are green, the instrument is sound and any later red belongs to the driver. Given that two of this suite's own tests were defective on their first bench run, that ordering earned its place immediately.

### 5.4 What the suite is now

| | v1.6.1 | v1.7.0 |
|---|---|---|
| Suites | 26 | 27 |
| Tests | 471 | 574 |
| Certification cards | 1 | 2 |
| Cluster geometries | 4 KB | 4 KB and 32 KB |

The two-card requirement deserves a note, because the first attempt at it was nearly worthless and the reason is not obvious. The cluster geometry recorded in a card catalog is the card's **factory** format — which a regression run destroys on its first reformat. What actually runs is whatever the formatter's capacity table selects. An earlier pairing of a 7 GB and a 14 GB card therefore ran at 8 and 16 sectors per cluster: adjacent buckets, a 2x spread, which is why the two runs looked interchangeable and the whole two-card procedure felt like ceremony.

The v1.7.0 pairing runs at **8 and 64** sectors per cluster — an 8x cluster-size spread, roughly 4x cluster count, crossing the SDHC/SDXC boundary and two spec generations. That is chosen deliberately against what this release changed: cluster-boundary arithmetic in `writeAdvanceCluster`, `readNextSector`'s boundary advance, `allocateCluster`'s FAT sector math, `freeClusterChain`, and the fsck chain walk. Large clusters cross boundaries 8x less often against a 4x smaller FAT, so a defect that hides at one geometry has a real chance of showing at the other.

A failure appearing on one card and not the other is the highest-value signal the procedure can produce. It is diagnosed as geometry-dependent — never retried in hope.

---

## Part 6 — What we would tell another driver author

**On validation.** Any check whose reference value is derived from the thing being checked is not a check. Two independent defects in this release had that shape — a write verified by reading it back from the card that stored it, and a high-speed switch verified by comparing the card's output to itself. Both looked like diligence in review, because both plainly performed a comparison. Ask what the reference *is*, and where it came from.

**On discarded errors.** A detected-then-discarded error is strictly worse than an undetected one. The detection code has already run and paid for itself, and the caller now gets an affirmative report of success. Nine of this release's findings were methods that computed a perfectly good status and dropped it on the floor; one of them performed a read-back verification and sent the result to a disabled debug channel. A mechanical audit for fallible call sites whose status is never consumed found two defects that a careful human read-through had missed, and it now runs as a gate.

**On timing anchored by instructions.** If you reset a counter and then depend on the phase of something that follows, everything in between is timing-critical — including instructions whose duration is *usually* fixed. `RDFAST` takes 10–17 clocks depending on hub slot, and hub slot depends on address, and address depends on the linker. That is not a timing bug you can find by reading the code on one build, and it is not one you can fix by tuning a delay. Establish invariance, *then* tune.

**On feature flags and layout.** A conditional-compilation flag that changes a data section's size changes every hub address after it. If any timing in the driver depends on a hub address, that flag is a timing flag. Ours was: enabling `SD_INCLUDE_SPEED` moved the DAT by four hub slots, which was the difference between a working driver and a silently corrupting one.

**On the instrument.** The suite that certifies the driver is part of the driver's correctness argument, and it has its own defect rate. Budget for that. When a sweep goes red in several places at once, resolve to root causes before opening investigations — ten failures were three causes, and one of those three accounted for seven of them by a mechanism that had nothing to do with the subsystems under test. And when a test can never pass, remove the impossibility; a permanently red test trains everyone to read red as normal.

---

## Reading further

| Document | What it covers |
|---|---|
| `DOCs/Analysis/ERROR-REPORTING-AUDIT-2026-07-31.md` | The 24-finding audit, per-finding, with call sites |
| `DOCs/Analysis/LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` | The Part 4 defect: mechanism, measurements, and the refuted hypotheses |
| `DOCs/Analysis/POST-V161-ROOT-CAUSE-ANALYSIS.md` | The three root causes behind the post-v1.6.1 red period |
| `DOCs/Analysis/REGRESSION-COVERAGE-ANALYSIS-2026-08-10.md` | The 12-finding coverage audit run during certification |
| `DOCs/SD-CARD-DRIVER-THEORY.md` | Driver architecture, and the current write-path invariant |
| `DOCs/SPI-PHASE-MARGIN-API.md` | The phase-margin diagnostic surface and the sawtooth measurement |
| `DOCs/MIGRATION-GUIDE-v1.7.0.md` | What breaks for a consumer, and the data-recovery note |
| `src/regression-tests/THEORY-OF-OPERATIONS.md` | What each suite proves, and the certification record |
