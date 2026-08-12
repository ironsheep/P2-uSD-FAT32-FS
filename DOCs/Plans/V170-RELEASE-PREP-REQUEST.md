# Release-Prep Request: v1.7.0 container-side preparation

**Raised by:** Stephen M Moraco
**Date:** 2026-08-12
**For:** container-based agent (no hardware access)
**Status:** REQUEST — prep not yet performed

---

## 0. Why this exists

The v1.7.0 hardware scope is **closed and green**. The layout-sensitivity defect
(write-path RDFAST landing inside the SCK phase window) was root-caused, fixed
(`3fee3f0`), characterized (`8b6cca9`), and certified (`4186e1b`), and the fix is
now proven **cross-card**:

| Sweep | Card | Result | Transcript |
|---|---|---|---|
| 2026-08-12 | Card 2b — Gigastone ASTC SDXC 58GB, SN `$0000_0F14` | **574/574, 0 fail**, closing audit 23/23 | `tools/logs/shakedown_SN0000-0F14_260812.txt` |
| 2026-08-12 | Card 1 — SharedOEM/Gigastone SDHC 7GB, SN `$0001_B9D5` | **574/574, 0 fail**, closing audit 23/23 | `tools/logs/shakedown_SN0001-B9D5_260812.txt` |

Both sweeps: 27 suites including format, stack-measurement build, zero infra
retries. **The certified figure is now 27 suites / 574 tests.** Any document
citing older figures (26/471, 25/465, 27/509) is stale.

What remains before the tag is container-side: documentation audit, punch-list
gate sweep, CHANGELOG, and one annotated code constant. This request scopes that
work.

---

## 1. Hard constraints

- **NO HARDWARE RUNS.** Compiling with pnut-ts is permitted and expected
  (`cd tools && ./run_regression.sh --compile-only` is the build gate).
  `command not found` for `pnut-term-ts`/flash tooling is the expected shape of
  the container — never report it as a failure or install around it.
- **NEVER author a release-gate disposition.** The punch-list gate requires
  Stephen's own words for every accept-or-fix decision. During v1.6.1 an agent
  wrote an acceptance in his name onto an item he had never seen. Your output
  for an unresolved item is a **question for Stephen**, never an answer.
- **Do not cut the tag.** Prepare everything up to the tag; Stephen tags.
- **Do not touch driver behavior.** The certified binary state is commits
  through `4186e1b`. The only permitted source change is §2.4 (STACK_SIZE,
  a sizing constant explicitly pre-authorized by the sweep runner's output).
  Any other code change invalidates the certification above.

---

## 2. Work items

### 2.1 Documentation audit (the three advisory scripts)

Run, from `tools/`: `./check_doc_counts.sh; ./check_doc_claims.sh; ./check_doc_api.sh`

- `check_doc_counts.sh` was run on the host 2026-08-12 and is **green** (27
  suites / 574 tests already propagated to README.md, regression-tests
  README, release.yml, SD-CARD-UTILITIES.md).
- `check_doc_claims.sh` and `check_doc_api.sh` require bash ≥ 4 and **have not
  run since certification** — they fail on the macOS host (`mapfile` missing).
  Run them in the container; resolve every ORPHAN (docs claim output the code
  never prints), DUPLICATE (same transcript in two files), and API-surface
  drift they report. Advisory scripts, but their findings are release-gate
  relevant when a doc misdescribes shipped behavior.

### 2.2 Punch-list gate sweep (`DOCs/Plans/PUNCH-LIST.md`)

For every item classed `user-affecting`: verify whether its owning fix actually
landed (cross-reference the v1.7.0 sprint tasks, commits, and the regression
suites that now pass). Produce a **gate roster** in the hand-back:

- items whose fix is confirmed landed (cite the evidence — commit, test, or
  both) — mark the punch-list entry resolved with that citation;
- items still open — list them verbatim for Stephen's accept-or-fix decision,
  **with no disposition written**.

Known open items that will need Stephen's decision (hardware-dependent, cannot
be resolved in the container): todo #3240 (Cloudisk unmount→mount wedge),
todo #3348 (Card 2a raw-init failure), the Maxwell NCard format item (carried
forward at v1.6.1 and again at v1.7.0 planning — needs re-decision at this tag).

Also add two **new** entries, `Class: test-harness — not user-affecting`:

1. **pnut-term-ts false download-abort:** failure-path debug output mid-run can
   trigger a spurious `Download failed (! received)` session abort.
2. **pnut-term-ts session-start truncation:** roughly the first 10 lines of a
   session's debug output can be lost from the captured log.

### 2.3 CHANGELOG.md — complete the v1.7.0 entry

The `## v1.7.0 (2026-08-03)` section predates the layout-sensitivity work. Add
entries for (style: terse, additive framing, user-visible behavior only, no
root-cause narration, ≤25 words each, matching the voicing of the existing
v1.7.0/v1.6.1 entries):

- the write-path reliability fix (streamer write phase alignment; certified on
  two cards, 574 tests);
- **breaking:** `changeDirectory()` with a missing name now returns
  `E_FILE_NOT_FOUND` (-40), including for the volume-label name;
- CID product-name printability: now an informational hex-escaped line instead
  of a warning;
- `handleError()`/error-reporting sprint items if any landed after the entry
  was drafted — reconcile the section against what actually shipped.

Refresh the heading date at tag time. Heading format for new entries is
`## vX.Y.Z (YYYY-MM-DD)`; v1.6.0 and earlier keep their old bracket form
permanently.

### 2.4 STACK_SIZE 160 (the one permitted source change)

Both certifying sweeps ran the stack-measurement build; max watermark was
**122/512 longs** (`SD_RT_defrag_tests`, both cards). The runner's output
authorizes: set release `STACK_SIZE` to **160** (max + 32, rounded to multiple
of 16) at the `STACK_SIZE` CON in `src/micro_sd_fat32_fs.spin2`, annotated with
both sweep dates and card serials per the formula comment at that CON. Verify
with `./run_regression.sh --compile-only`.

### 2.5 Minor doc corrections

- `DOCs/Analysis/DUMMY-DATA-CRC-ANALYSIS.md` line ~27 claims writes "All work"
  on the dummy-CRC card class — known wrong (todo #3214); correct the claim to
  match the documented investigation state.

---

## 3. Hand-back

A single report containing: doc-audit results (per script: clean, or findings
fixed), the §2.2 gate roster (landed-with-evidence vs. needs-Stephen), the
CHANGELOG diff summary, the STACK_SIZE change + compile-gate result, and
anything discovered that this request did not anticipate. Stephen then walks
the gate roster, and the tag follows.
