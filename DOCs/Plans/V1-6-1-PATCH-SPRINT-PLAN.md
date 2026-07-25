# v1.6.1 Patch — Sprint Plan

**Target:** hardware-verify and ship the five commits that landed after the
`v1.6.0` tag.
**Ships as:** **v1.6.1** (pending §Open Questions Q1)
**Authored:** 2026-07-25
**Predecessor:** `DOCs/Plans/archive/2026-07-25-Write-Path-Corruption-Fix-Sprint-Closeout.md`

---

## Purpose

v1.6.0 shipped certified. Five commits then landed on `main` — all
**compile-verified only, none run on hardware**:

| Commit | What |
|---|---|
| `39ed492` | CHANGELOG: date each release to its tag |
| `7056b3b` | Utilities: say what is true, in a human voice |
| `f0dece0` | CHANGELOG: record the utility-output fixes under `[Unreleased]` |
| `c0ffb36` | `debugClearRootDir` → `debugZeroRootSector` |
| `4696658` | v1.6.0 sprint closeout |

Two of them touch shipping code: the utility output rework
(`src/UTILS/isp_fsck_utility.spin2`, `SD_format_card.spin2`,
`isp_format_utility.spin2`, `SD_performance_benchmark.spin2`) and a driver-level
rename (`src/micro_sd_fat32_fs.spin2`). This sprint proves them on the bench and
ships the patch.

It also closes two of the three carryovers the v1.6.0 closeout recorded, because
the evidence for both arrives naturally during this sprint's bench session.

**No new `src/` files** were added, so `.github/workflows/release.yml` needs no
enumeration change. The one new file, `diagnostic-tests/SD_zero_root_sector_probe.spin2`,
lives in the never-shipped diagnostics tree — confirm, do not change.

## Entry baseline

*Filled by `sprint-start` — build number agreement, working-tree audit,
tracking-readiness entry check, baseline-health entry check.*

---

## § Open Questions

Each carries a recommended resolution. **The sprint does not start until all
three are confirmed or redirected.**

**Q1 — Is v1.6.1 the right number, given a breaking rename?**
`debugClearRootDir()` → `debugZeroRootSector()` is a rename of a *public* method,
and `[Unreleased]` already carries it under **Breaking Changes**. Strict SemVer
argues against a patch bump.
*Recommendation: ship as **v1.6.1**, and state the policy explicitly* — the
`SD_INCLUDE_DEBUG` diagnostic API is documented "NOT FOR PRODUCTION USE" and is
outside the compatibility promise. That policy line belongs in
`DOCs/SD-CARD-DRIVER-THEORY.md` alongside the feature-flag table, so the next
debug-API change doesn't reopen this. If you'd rather honor the rename strictly,
the alternative is v1.7.0 and no policy statement.

**Q2 — One card or two for the sweep?**
The v1.6.0 fix was certified on two cluster geometries. This patch changes no
write-path behavior — a rename plus output strings.
*Recommendation: **one card, the 4 KB SharedOEM SDHC 7 GB.** Two geometries buy
nothing here, and using Card 1 specifically also discharges carryover #3: its
v1.6.0 cert transcript ends in a hand-annotated false-negative closing audit, and
a clean sweep with the fixed tooling replaces that record. One run, two results.*

**Q3 — Does delivering the dual-driver advice doc belong in this sprint?**
Carryover #1: `DOCs/Agent-Reports/ADVICE-TO-DUAL-DRIVER-AGENT-CONVERGENCE.md` is
complete (7 divergences) but was never handed over, because no channel was ever
specified. It is not blocked by anything technical.
*Recommendation: **yes, include it** as §5 below. It has now slipped one full
sprint, it costs one action once you name the channel, and Divergence 7 (utility
voicing) is exactly what this sprint's changes are about — so the doc and the
patch are in sync at the moment of delivery. If the dual-driver agent isn't
reachable right now, drop §5 and it stays on the punch list.*

---

## 1. Certify the `debugZeroRootSector()` contract on hardware

**Why:** `c0ffb36` renamed the method and rewrote its docstring to state three
facts the old name and docs actively denied. Those facts have never been observed
on hardware — they were derived by reading
`src/micro_sd_fat32_fs.spin2:2745-2755` (worker case) and the FAT32 layout. A
docstring asserting unverified behavior is the same defect class this project
just spent a sprint eliminating.

**Current starting point:** `diagnostic-tests/SD_zero_root_sector_probe.spin2`
(written, compiles, 40054 bytes, never run). It builds a 40-file root — enough to
span three root sectors at 16 entries each — then asserts:

- FACT 1 — files in the second and later root sectors survive the call
- FACT 2 — the first root sector is cleared
- FACT 3 — `freeSpace()` is unchanged, i.e. the erased entries' chains are leaked

It reads the first sector back via `readSectorRaw()` rather than the enumeration
path, and remounts before measuring, so results reflect the card and not a cache.

**Target:** run the probe's full operator sequence on a scratch card:

1. `./run_regression.sh --reformat-only` — clean card
2. run the probe — expect FACT 1/2/3 all HOLD
3. `SD_FAT32_audit` — expect **lost clusters reported**, `STATUS: REPAIRS NEEDED`
4. `SD_FAT32_fsck` — expect the clusters reclaimed
5. `SD_FAT32_audit` — expect `STATUS: CLEAN`

Steps 3–5 certify the recovery path the new docstring recommends, using the deep
audit certified in v1.6.0.

**Verification:**
- *Normal* — all three facts HOLD; audit finds the leak; fsck reclaims it; final
  audit clean.
- *Edge* — the volume label occupies a root-sector-0 entry on a freshly formatted
  card, so FACT 2's "first sector cleared" includes the label. Confirm the card
  still mounts afterwards; if it does not, the docstring needs a fourth fact.
- *Error* — any FACT reported VIOLATED is a hard stop: the docstring is still
  wrong and the patch does not ship until it is corrected.

## 2. Full regression sweep — patch verification and a clean cert record

**Why:** `c0ffb36` modified the driver itself, so a compile check is not
sufficient evidence. The sweep also exercises the reworked audit output on every
run (preflight, closing) and the format vehicle 3–4 times.

**Current starting point:** `tools/run_regression.sh` — end-to-end, one
invocation, continue-on-failure by default.

**Target:** one full sweep on the 4 KB card (pending Q2):

```
cd tools
./run_regression.sh --include-format --log ../DOCs/Agent-Reports/sweep_card1_v161_260726.txt
```

Launch in the background and poll the transcript — the sweep is ~600 s, at or past
a foreground command's ceiling.

**Verification:**
- *Normal* — exit 0: 26/26 suites, 471/0, zero `INFRA` rows, closing audit clean.
- *Edge* — the preflight and closing audit lines must show the **new** wording
  (`needs repair:` / the read-only header). Old wording anywhere means a stale
  `.bin` was used; force a rebuild and rerun.
- *Error* — any failed suite is a hard stop; a driver-level rename that breaks a
  suite means something still references the old name.

This transcript replaces `sweep_card1_recert_260724.txt` as Card 1's certification
record, discharging carryover #3.

## 3. Confirm the format drain, then tighten the runner

**Why:** carryover #2. `_reformat_card()` in `tools/run_regression.sh` accepts
either `FORMAT COMPLETE` or `FORMAT SUCCESSFUL`, with a ~12-line comment
explaining that `SD_format_card` truncated its own success line. `7056b3b` added
`waitms(500)` before `END_SESSION` (`src/UTILS/SD_format_card.spin2:70`), which
should make the line survive.

**Target:**

1. After §2's sweep, grep the newest `tools/logs/SD_format_card_*.log` for an
   intact `FORMAT SUCCESSFUL`.
2. **If present:** tighten `_reformat_card()` to that single marker and delete the
   workaround comment. Then run `./run_regression.sh --reformat-only` (~12 s) to
   prove the tightened path still verifies a format.
3. **If absent:** the drain is insufficient. Do **not** lengthen the wait —
   investigate why the line still doesn't land, and leave the workaround in place.

**Verification:**
- *Normal* — marker intact; runner tightened; `--reformat-only` reports OK.
- *Edge* — the tightened runner must still fail loudly on a genuinely failed
  format; `FORMAT FAILED` remains decisive.
- *Error* — if the marker is absent, §3 produces a findings note instead of a code
  change, and the carryover stays open.

## 4. Documentation and CHANGELOG

**Why:** documentation currency is a deliverable, not an afterthought.

**Target:**

- `CHANGELOG.md` — promote `[Unreleased]` to `## [1.6.1] - <tag date>`; add the
  compare link; leave `[Unreleased]` empty. Entries must follow
  `DOCs/procedures/changelog-style-guide.md` — name the trigger, no test
  artifacts, no editorial framing, no protocol internals.
- `DOCs/SD-CARD-DRIVER-THEORY.md` — add the debug-API compatibility policy line
  (pending Q1) near the feature-flag table.
- `DOCs/Plans/PUNCH-LIST.md` — strike whichever carryovers §2 and §3 discharge.

**Verification:** `[Unreleased]` empty; every version has a compare link; a
style-guide read-through of the new section finds no banned construction.

## 5. Deliver the dual-driver advice doc

*Included pending Q3.*

**Why:** carryover #1 — the doc is complete and has never been handed over.

**Target:** with the channel {{USER_NAME}} names, deliver
`DOCs/Agent-Reports/ADVICE-TO-DUAL-DRIVER-AGENT-CONVERGENCE.md` (7 divergences,
Divergence 7 being this sprint's utility-voicing rules). Record in the punch-list
entry what was delivered, how, and when.

**Verification:** the punch-list item is struck with a delivery record naming the
channel and date. *Error* case — if the agent is unreachable, record that and
leave the item open rather than silently dropping it.

## 6. Release v1.6.1

**Why:** ship gate.

**Target:** follow `DOCs/procedures/RELEASE-CHECKLIST.md`. Confirm
`release.yml` needs no enumeration change (no new `src/` files this sprint) and
that `diagnostic-tests/` — now holding the new probe — is still excluded from the
bundle. Tag `v1.6.1`, push, then verify the published release by **downloading the
zip**, not by reading the API's asset metadata (that field goes stale after a tag
update — v1.6.0 lesson).

**Verification:**
- *Normal* — tag pushed; workflow green; bundle contains the intended `src/` tree,
  excludes `diagnostic-tests/`, and its bundled `CHANGELOG.md` carries the 1.6.1
  section.
- *Edge* — release notes are generated from the tagged `CHANGELOG.md`; any
  hand-edit of the release body is overwritten by a later tag push.
- *Error* — a failed workflow means fix and re-tag with `git tag -f` +
  `git push --force` (`softprops/action-gh-release` upserts on the tag).

---

## Exit-gate notes

- The patch ships only when §1's three facts HOLD and §2's sweep is exit-0.
- §3 may legitimately end with no code change; that is a finding, not a failure.
- §5 is discharged by a delivery record, not by the doc existing.
