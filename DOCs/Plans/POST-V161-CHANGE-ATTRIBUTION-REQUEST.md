# Analysis Request: Characterize every change since v1.6.1 and map it to the failing suites

**Raised by:** Stephen M Moraco
**Date:** 2026-08-07
**For:** container-based analysis agent (no hardware access)
**Status:** REQUEST — analysis not yet performed

---

## 0. Why this exists

The 2026-08-06/07 session investigated regression failures by running hardware A/B
experiments. It produced some facts but **failed as a process**, for reasons worth stating
plainly so this analysis does not repeat them:

1. **No reference point was ever established.** Nobody measured what v1.6.1 — the last
   certified release — scores *today*, on this card, with this harness. Without that
   number, no failure observed since is attributable.
2. **The measuring instrument changed mid-investigation.** A test-framework drain fix and a
   new `--clean-each` runner mode were introduced *between* sweeps, so the three sweeps
   taken that day are not comparable to each other.
3. **Symptoms were chased instead of attributed.** Only **two commits** since v1.6.1 touch
   the driver. That is a three-step bisection, and it was never run.
4. **Multiple variables moved per experiment** — driver, tests, and harness at once.

This request replaces ad-hoc experimentation with a disciplined characterization, done
**statically first**, so that when hardware time is spent it is spent on a specific
question.

**Working premise from Stephen:** *v1.6.1 passed all regression tests cleanly.* The
analysis should treat this as the reference claim to be reconciled against, not assumed
mid-analysis. (Note the recorded certification figures for that era are **26 suites / 471
tests**; the current roster runs **27 suites / 509 tests**. The roster delta is itself part
of what must be characterized — see §4.6.)

---

## 1. Hard constraints

- **NO HARDWARE RUNS.** The container has no P2 board. This analysis is documentary,
  source-level, and (optionally) compile-level only.
- **Compiling is permitted** (`pnut-ts`) to check that a state builds, measure code size, or
  produce a memory map. Compiling does not touch the card.
- **Do not modify the working tree's driver or test sources.** Use `git worktree` or
  `git show` to inspect historical states. The working tree contains uncommitted work
  (§3) that must be preserved exactly.
- **Do not commit anything.**

---

## 2. The certified baseline (verified)

| Fact | Value |
|---|---|
| Last certified release | **v1.6.1** |
| Tag object | `a9c4450` (annotated) |
| Commit the tag points to | **`f470bfe`** — *"Adopt the changelog voicing guide for v1.6.1"*, 2026-07-27 |
| Commits since | **8** |
| Of those, touching the driver | **2** (`3052e64`, `f34610f`) |

### 2.1 THREE known-good reference points, not one

Stephen confirms **v1.5.3, v1.6.0, and v1.6.1 all passed the test suite** — before the
2026-08-03/07 work on the changes since. That gives three independent green anchors and a
decisive way to separate two very different explanations:

| If v1.6.1 as-tagged, run today with the current instrument… | Then |
|---|---|
| **passes clean** | The bench, card, and instrument are sound. Every failure in §5.1 is attributable to the 8 commits or the uncommitted work. Proceed with the forward walk |
| **fails** | Something OUTSIDE the change set moved — instrument, card, bench, or the drain race (§5.2) masking failures at certification time. **Do not attribute anything to the commits until this is resolved.** Step back to **v1.6.0**, then **v1.5.3**, to find the last state that still reproduces green today |

This is the single most important measurement in the whole plan, and it must come first.
Everything else in §5.1 is uninterpretable without it.

**Caveat that cuts both ways:** the END_SESSION drain race (§5.2) was present but only
partly fixed at all three tags — `6ec45ab` addressed one program, never the framework. So a
historical "passed cleanly" may itself have contained truncation-masked failures. When
re-measuring a tagged state today, apply the framework drain fix so the *instrument* is
sound, and note that this makes today's run **stricter** than the original certification.

---

## 3. Working-tree state at the time of this request — READ CAREFULLY

`git status --short` shows:

```
 M src/micro_sd_fat32_fs.spin2
 M src/regression-tests/SD_RT_error_handling_tests.spin2
 M src/regression-tests/SD_RT_multihandle_tests.spin2
 M src/regression-tests/isp_rt_utilities.spin2
 M tools/run_regression.sh
?? DOCs/Specs/PROPOSAL-IFDEBUG-BLOCK-CONDITIONAL.md
?? DOCs/Plans/POST-V161-CHANGE-ATTRIBUTION-REQUEST.md   (this file)
?? diagnostic-tests/SD_debug_mask_block_elision_probe.spin2
?? diagnostic-tests/SD_empty_debug_block_probe.spin2
?? diagnostic-tests/SD_stack_guard_collision_probe.spin2
?? diagnostic-tests/SD_worker_stack_depth_probe.spin2
```

**⚠ THE DRIVER IN THE TREE IS THE "GATE" VARIANT.** The session's last action before being
halted was an A/B that swapped the gated driver in; the restore command was interrupted.
So `src/micro_sd_fat32_fs.spin2` currently contains the **worker stack-integrity gate**,
NOT the intended gate-withdrawn version. **Confirm with Stephen which variant should be in
the tree before drawing any conclusion from it.** The two differ by ~42 bytes of compiled
code and that difference demonstrably changes which suites pass (§5.3).

### Uncommitted changes, and what each is

| File | Change | Confidence |
|---|---|---|
| `src/micro_sd_fat32_fs.spin2` | **(a)** `cog_stack_end_mark` DAT long inserted between `cog_stack` and `cog_stack_guard` — fixes a real two-detector address collision. **(b)** `worker_stack_fault` byte + `send_command` reporting branch. **(c)** worker-side stack integrity gate — *withdrawn* in the intended version, *present* in the tree right now | (a) high — root-caused; (c) contested |
| `SD_RT_error_handling_tests.spin2` | Test #12 rewritten for the boolean-only `eofHandle` contract (asserts TRUE + `ERROR()` code) | high — verified passing |
| `SD_RT_multihandle_tests.spin2` | Two `eofHandle` assertions rewritten the same way; sub-check count 7→8 | high — verified passing |
| `isp_rt_utilities.spin2` | `waitms(500)` drain at end of `ShowTestEndCounts()` | high — fixes result corruption, §5.2 |
| `tools/run_regression.sh` | New `--clean-each` flag; corrected a header comment that wrongly claimed failures cannot cascade | high |

---

## 4. What to characterize — the core ask

For **each of the 8 commits**, produce a characterization covering:

1. **What it claims to do** (commit message intent).
2. **What it actually changed** (files, and for driver changes, which methods/subsystems).
3. **Behavioral contract changes** — any public API whose return values, semantics, or
   error reporting changed. Call out breaking changes explicitly.
4. **Which regression suites it touched**, and how those edits changed what is asserted.
5. **Overlap with the currently-failing areas** (§5.1) — this is the heart of the request.
6. **Risk assessment** — could this plausibly cause the observed failures, and by what
   mechanism?

### 4.1 The 8 commits, with verified scope

| # | Commit | Subject | Scope |
|---|---|---|---|
| 1 | `3e5aed0` | Drop the dangling [Unreleased] link definition | CHANGELOG only (1 line) |
| 2 | `73e13b0` | The error-reporting audit records where errors go missing | Docs only (+628) |
| 3 | `e6ef008` | A script finds the dropped statuses the read-through missed | `tools/check_error_handling.sh` (+309), docs |
| 4 | `3052e64` | Faults can be injected, and ERROR() describes the last operation | **DRIVER +231**; 5 test files; docs; CI |
| 5 | `f34610f` | Every failure the driver detects now reaches the caller | **DRIVER +1237/-308**; 4 test files; 1 example |
| 6 | `03c769e` | fsck recovers entries stranded past a spurious end-of-directory marker | `isp_fsck_utility.spin2` (+176), docs |
| 7 | `860883f` | The regression runner compiles the programs users actually build | `run_regression.sh` (+64), docs |
| 8 | `b071767` | Two new guides cover error handling and the move from v1.6.x | Docs + CHANGELOG only (+747) |

**Only #4 and #5 touch the driver.** #6 touches a utility, #3 and #7 touch tooling, the rest
are documentation. Any driver-behavior regression must originate in #4, #5, or the
uncommitted work in §3 — or must have pre-existed at v1.6.1.

### 4.2 Reconcile against Stephen's expectations

Stephen initially expected this change set to contain three things. **He has since
confirmed that two of them landed in v1.6.0 / v1.6.1 — i.e. BEFORE the baseline — and are
therefore part of the certified reference, not part of what changed since:**

| Expectation | Verified finding | Action |
|---|---|---|
| **Error codes now passed back to caller instead of being lost** | **Present in this range** — `f34610f` (+1237/-308), supported by the audit in `73e13b0` and the checker in `e6ef008`. Note this work has a **longer lineage**: `a7dc362` "propagate write-path errors that were silently swallowed" and `dbe5cc9` "CMD_WRITE_SECTOR_RAW dispatch passes through actual error code" both predate v1.6.1 | Characterize `f34610f` fully; enumerate every contract change |
| **Broken append-file behaviors fixed** | **Landed BEFORE the baseline** — `382042e` *"Fix write-path corruption; certify on two geometries (v1.5.4)"*, shipped as part of v1.6.0. **In the certified baseline** | Confirm the write/append path in `f34610f` did not disturb it. Any append regression now would be a **new** defect in `f34610f`, not unfinished work |
| **Regression suites adjusted for proper starting media condition + self-cleanup** | **Landed BEFORE the baseline** — `0bbe817` "Release-prep for v1.6.0: audit/fsck consolidation + **end-to-end regression runner**", with `39c1863` tightening the format-vehicle success line | **Characterize what that runner actually guarantees per suite**, and reconcile against §6.1, which found only 1 suite in `REFORMAT_BEFORE` and 2 in `REFORMAT_AFTER`. If the intended guarantee is stronger than the code delivers, that gap is a **prime suspect** for the cascade-shaped failures |

**Note on precedent:** `6ec45ab` *"SD_performance_benchmark: drain the log before
END_SESSION"* (also pre-baseline) fixed the END_SESSION truncation race **in one program**.
The uncommitted `isp_rt_utilities` drain fix (§3) generalizes that same known fix to the
whole test framework. The race was understood before v1.6.1; it was simply never applied
framework-wide.

### 4.3 Deep-dive: `f34610f` contract changes

Its own message says *"Eight leaf I/O methods and five mixed boolean/status methods now
return one kind of value each."* Enumerate all thirteen. For each: old contract, new
contract, whether breaking, whether any regression test still asserts the OLD contract.

Three such stale assertions were already found and fixed (`eofHandle` in error_handling and
multihandle ×2). **Assume there are more and find them.** A test asserting a retired
contract fails without indicating a driver defect — and the reverse, a test *loosened* to
match new behavior, can hide one.

### 4.4 Deep-dive: `3052e64` fault injection

The injection facility is evaluated at the **physical sector read** (inside the read retry
loop, after CRC bytes arrive) and therefore **cannot fire on a cache hit**. Assess whether
the injection tests' preconditions guarantee a physical read of the armed LBA.

Specific open question: `SD_RT_error_injection_tests` #13/#14 arm `debugGetFatSec()` (the FAT
*start* sector) and assert the injection fired. A FAT32 entry for cluster *N* lives at
`fat_sec + N/128`, so arming the first FAT sector covers **only clusters 0–127**. On the
58 GB test card (32 KB clusters) that is the first 4 MB of the volume. **If the test file
is allocated past cluster 127, the armed sector is never read and the check passes
vacuously — or fails, as observed.** Confirm by reading the code path; this is the same
"gate that cannot fire" shape as `lesson_health_check_cannot_fail`.

### 4.5 Deep-dive: `03c769e` fsck

Utility-only, but it changes directory-scan behavior around end-of-directory markers.
Assess any interaction with `subdir_ops` failures (§5.1).

### 4.6 Roster reconciliation

Certified-era figures are **26 suites / 471 tests**; current runs execute **27 suites / 509
tests**. Identify which suite(s) were added and which tests grew, so a count comparison
against the certified baseline is meaningful rather than apples-to-oranges.

---

## 5. Observed failures to map against

### 5.1 Last trustworthy sweep — 2026-08-07, `--clean-each`, drain fix active

Every suite started from a freshly formatted card, so these are independent measurements.
**Driver state: DAT fix present, worker gate WITHDRAWN.**

**Total: 484 pass / 25 fail (509 executed).**

| Suite | Fails | Notes |
|---|---|---|
| `SD_RT_subdir_ops_tests` | **12** | First real failure is Test #7 `newDirectory()` → **-7 E_IO_ERROR**; `changeDirectory()` then → -43; rest cascade internally. Failures begin at Test #2 |
| `SD_RT_error_handling_tests` | 5 | Tests #3 newDirectory-on-existing, #5 handle slot reuse, #6 same-file write+read, #14 rename-to-existing. **Not** the `eofHandle` test — that now passes |
| `SD_RT_crc_diag_tests` | 3 | Uncharacterized |
| `SD_RT_error_injection_tests` | 3 | The `"FAT read injection actually fired"` class — see §4.4 |
| `SD_RT_speed_tests` | 2 | Uncharacterized. Previously mis-scored 0/0 by the truncation bug |

All other 22 suites passed clean, including all six that the gate had been breaking.

### 5.2 Instrument defect found and fixed — affects ALL earlier numbers

The test framework emitted its totals line and then immediately `debug("END_SESSION")`,
which shut the capture down mid-drain. Observed in one sweep: `SD_RT_speed_tests` **passed
15/0** but its totals line was truncated to `* 15 ` and the runner scored it **0/0**;
`SD_RT_subdir_ops_tests` had **real failures** truncated to `-> FA` and was *also* scored
0/0. **A truncated pass and a truncated failure are indistinguishable downstream.**

**Consequence: any sweep number recorded before this fix may be wrong in either
direction** — including the 08-03 sweeps and the certification figures, if the race existed
then. The analysis should note which historical numbers are and are not trustworthy.

### 5.3 The unexplained finding — highest-value open question

A ~42-byte block of code in `fs_worker` changes which suites pass, **while never being
executed**. Measured on clean cards:

| Driver | `SD_RT_cogcwd_tests` | `SD_RT_subdir_ops_tests` |
|---|---|---|
| gate **present** | **0 pass / 5 fail** | **18 pass / 0 fail** |
| gate **absent** | **5 pass / 0 fail** | **6 pass / 12 fail** |

Exact mirror image. Supporting facts:
- The branch is provably **never taken**: a variant that evaluated the guard and published
  `E_STACK_OVERFLOW` on failure passed 5/0 with **no `-26` ever observed**, from either the
  worker side or `send_command`'s own check.
- The body is **not** compiled out: it emits **42 bytes** (46,380 vs 46,336 byte builds).
- `SD_RT_subdir_ops_tests` uses **neither** `SD_INCLUDE_ALL` **nor** `SD_INCLUDE_STACK_CHECK`
  — this is a **core** build, so the core driver is affected.
- This is the **third** reproduction; the first two were at the `stackUtils.checkStack()`
  site (2026-08-03), where wrapping the call in a condition broke `SD_RT_mount_tests` #31
  reproducibly with the added branch demonstrably never executing.

**Working hypothesis: a layout-sensitive latent defect in the core driver** — an
out-of-bounds write, uninitialized read, or address-dependent assumption whose damage
depends on what is adjacent in memory. Under this hypothesis **both** configurations are
defective and we have only been changing which suite notices. **This must be root-caused
before v1.7.0 ships.** It is not a reason to prefer one variant.

Static work the container can do without hardware:
- Compile both variants with `-m`/`-l`; diff DAT symbol placement and object layout.
- Audit DAT array bounds and every index that could write past an array end.
- Audit inline PASM for hub-address or alignment assumptions, especially the streamer paths.
- Look for reads of DAT/VAR state before initialization.
- Check whether `MAX_OPEN_FILES`-derived handle-buffer sizing can overrun.

A cross-compiler binary comparison (PNut on Windows vs pnut-ts) was proposed to rule out a
codegen defect. Reference artifact: gated `SD_RT_cogcwd_tests.bin`, **46,380 bytes, md5
`c505157602885cecbd1b8e6922bdeee7`**. **Unresolved at time of writing.**

---

## 6. Known process/tooling gaps to fold into recommendations

1. **No per-suite starting media condition.** `REFORMAT_BEFORE` holds one suite
   (`fatchain`); `REFORMAT_AFTER` holds two (`fatchain`, `format`). Every other suite
   inherits its predecessor's debris. `--clean-each` (uncommitted) reformats before every
   suite at ~13 s each. Stephen has indicated he prefers **each suite establishing the
   precise precondition it needs and cleaning up after itself, at minimal effort** — see
   the open question in §7.
2. **No suite self-cleanup contract.**
3. **Cascade demonstrated:** `SD_RT_multiblock_tests` failed with a one-bit stream shift in
   cascade-prone sweeps and **passed 6/0** with `--clean-each`. Treat every non-clean-each
   failure as suspect.

---

## 7. Open questions for Stephen — ANSWER BEFORE ANALYSIS

*(Q2 and part of Q3 were answered by Stephen on 2026-08-07 and are folded into §4.2: the
append fix and the end-to-end regression runner both landed in v1.6.0/v1.6.1 and are part
of the certified baseline.)*

1. **Which driver variant belongs in the working tree** — gate-withdrawn (intended) or the
   gated version currently there? (§3) **This blocks any tree-based analysis.**
2. **Per-suite media conditioning:** v1.6.0's end-to-end runner was intended to give each
   suite a proper starting condition, but the code reformats before only ONE suite. Should
   the fix be (a) `--clean-each` as the certification mechanism, or (b) each suite
   establishing and cleaning its own precondition at minimal effort — Stephen's stated
   preference — with `--clean-each` kept only as a fallback? (§6.1)
3. **Was v1.6.1 certified with the drain race present?** `6ec45ab` fixed it in one program
   pre-baseline but never framework-wide, so **the race was almost certainly active during
   v1.6.1 certification.** If so, the baseline's "all clean" result may itself contain
   truncation-masked failures, and §5.2 applies to the reference point. This materially
   affects what "v1.6.1 passed cleanly" can be taken to mean.
4. **Scope for the container agent:** characterization + static root-cause hunting only, or
   should it also propose and stage fixes for review?

---

## 8. Deliverables

1. **Per-commit characterization** (§4) — one section each for the 8 commits.
2. **Contract-change register** for `f34610f` — all thirteen methods, old vs new, breaking
   or not, tests still asserting the old contract.
3. **Overlap matrix** — failing suite × commit, with a reasoned mechanism for each
   plausible link and an explicit "no plausible link" where that is the honest answer.
4. **Verdict per failing suite** in §5.1: attributable to a named commit, attributable to
   uncommitted work, pre-existing at v1.6.1, or **undetermined pending hardware** — with the
   specific experiment that would settle it.
5. **Static findings on §5.3**, the layout-sensitivity hypothesis.
6. **Reconciliation of §4.2**, Stephen's three expectations against what is actually there.
7. **A recommended hardware plan** for the next session: the ordered, minimal set of runs
   that resolves the remaining undetermined items — each run stating the question it
   answers and what each outcome would mean. Instrument frozen; one variable per run.

---

## 9. Method requirements

- **Freeze the instrument.** Harness, drain fix, and `--clean-each` must be identical across
  every comparison proposed. Note explicitly wherever a historical number was taken with a
  different instrument.
- **One variable per experiment.**
- **Establish the reference point first.** Any hardware plan must begin by measuring v1.6.1
  as-tagged with the current instrument, before attributing anything to later commits. Note
  that the v1.6.1 *tests* must be used with the v1.6.1 *driver* — the three `eofHandle` test
  edits assume the new contract and would fail against the old driver for reasons that are
  not defects.
- **Prove every check can fail.** Per `lesson_health_check_cannot_fail` and the `#error`
  control failure of 2026-08-07: never accept a passing check without confirming it is
  capable of reporting failure. §4.4 is a live instance.
- **State "I don't know"** where evidence is absent, rather than constructing a mechanism.
