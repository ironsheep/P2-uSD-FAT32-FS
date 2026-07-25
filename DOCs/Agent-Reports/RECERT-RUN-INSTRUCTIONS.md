# v1.6.0 Recertification — Host Run Instructions

**For:** the host-native agent on Stephen's Mac (P2 hardware attached)
**Prepared:** 2026-07-24, container side
**Goal:** recertify the release on hardware, then tag and ship **v1.6.0**.

---

## What changed since the last hardware run

Two things need hardware proof this time:

1. **Tool consolidation (the actual subject of this recert).** `SD_FAT32_check`
   is gone. `audit` is now the *deep, read-only* 4-pass engine (it was shallow);
   `fsck` is the same engine plus repairs; `MODE_CHECK` was removed. The naming
   used to be inverted — audit was the blind/shallow one — and that is now fixed.
2. **The regression runner runs end-to-end in ONE invocation.** Preflight card
   identify + incoming audit, baseline format, all 26 suites, closing audit,
   summary. It no longer stops on the first failure and no longer dies on a
   serial download glitch.

The **driver itself is untouched** since the 2026-07-24 CONFIRM run. The
write-path Bug A/B fix is already certified on two geometries (471/0 each); do not
re-litigate it.

---

## The run

One command per card. **Do not chunk it with `--from`, and do not run any suite
standalone first** — the runner reformats before the suites that need a clean
card, so a solo pre-run adds nothing but a manual step.

```bash
cd tools/
./run_regression.sh --include-format --log ../DOCs/Agent-Reports/sweep_<card>_recert_260725.txt
```

Run it **in the background and poll the transcript.** A full sweep is ~600 s,
which is at or past the ceiling for a foreground command — that ceiling is exactly
what forced the old chunk-and-resume pattern. The `--log` file updates live.

Repeat on **two cards of different cluster geometry** (the certified pair:
SharedOEM SDHC 7 GB @ 4 KB/clus, Gigastone SD16G 14 GB @ 8 KB/clus). Swap the card
between runs; nothing else changes.

**The card is scratch.** Authorizing the run authorizes formatting it — that is
project policy and the runner relies on it.

---

## Reading the result

Exit code **0** means: every suite executed, every suite passed, and the closing
audit is clean. Anything else is explained in its own block at the end.

| Result | Meaning | Action |
|---|---|---|
| `FAILED SUITES (n)` | Suites ran and reported failures. Log path is printed per suite. | Real defect — investigate before shipping. |
| `INFRASTRUCTURE FAILURES (n)` / `INFRA` row | Suite **never executed** — the download died twice (known USB checksum transient). Not a pass, not a driver result. | Re-run just those: `./run_regression.sh --from <name>`. |
| `CLOSING AUDIT FAILED` | The sweep left the card unhealthy. | **Hard blocker.** On a fixed driver this must never happen. |
| `Note: the INCOMING card was not clean` | Pre-existing state from a prior run. | Informational only — the baseline reformat handled it. |

The transcript's first lines are the card's own L1/L2/L3 identity (capacity,
geometry, SN, warnings). Quote those into the cert report rather than
hand-transcribing card details.

---

## Additional checks specific to THIS recert

The sweep covers the driver. The tool consolidation needs two more checks, run
manually after a sweep completes:

1. **Clean-card smoke test** — on a freshly formatted card, run both tools and
   confirm no regression from the engine refactor:
   ```bash
   ./run_test.sh ../src/UTILS/SD_FAT32_audit.spin2 -t 300
   ./run_test.sh ../src/UTILS/SD_FAT32_fsck.spin2  -t 300
   ```
   Expect the structural itemization (`[PASS]` per MBR/VBR field) followed by the
   4-pass scan, and a clean summary from each.

2. **Bug-A detection A/B — the one that proves the new audit earns its keep.**
   The old shallow audit reported **39/39 clean** on a card the driver had damaged
   with lost clusters; the new deep audit must *find* them (Pass 3, lost/orphaned
   clusters). To produce a damaged card: run `SD_RT_fatchain_tests` against the
   **pre-fix** driver (`git stash` the fix, or check out the DETECT-era driver),
   then run the new audit on the resulting card **without reformatting**.
   - Old audit on that card: 39/39 "clean" (documented, `SD_FAT32_audit_260723-185222.log`)
   - New audit on that card: **must report lost clusters**
   This is what validates the CHANGELOG's upgrade/recovery note telling users to
   run the audit to find Bug A damage. If the new audit also says clean, that note
   is wrong and must be corrected before shipping.

   > **Correction (host agent, 2026-07-24):** the recipe above does not compile as
   > written. `SD_RT_fatchain_tests:105` calls `sd.clusterBytes()`, and the fix
   > commit is what added that getter. Backport *only* that getter into the pre-fix
   > driver — a pure DAT accessor (`n := sec_per_clus << SECTOR_SHIFT`) that cannot
   > influence the write path, whose real fix is `writeAdvanceCluster` replacing the
   > boundary-advance `allocateCluster`. The damage produced is authentically pre-fix.
   >
   > **RESULT (2026-07-24): PASS.** Same card, no reformat between: old shallow
   > audit → `Tests: 39 Pass: 39 / FILESYSTEM INTEGRITY: OK` (false clean, runner
   > rc=0 — would have shipped); new deep audit → `REPAIR: Would free 2 lost
   > clusters / Repairs needed: 2 / STATUS: REPAIRS NEEDED` (runner rc=1, blocks).
   > The CHANGELOG upgrade/recovery note is truthful; no correction needed.

   Note: **Bug B (mid-sector zero-fill) is undetectable** by any FAT32 tool — no
   data checksum exists. The recovery note already says restore-from-backup for it.
   Do not expect the audit to find Bug B.

---

## After the runs are green

Remaining before the tag (tracked as todo `#11`):

- **§5 doc audit** — 19 shipping docs still cite "25 suites / 465 tests"; should be
  **26 suites**, and the test total should cite the certification figure. Also
  document in `SD-CARD-UTILITIES.md`, `SD-CARD-DRIVER-THEORY.md`, and
  `src/UTILS/README.md` (its utility table lists only 4 tools and is missing the
  FAT32 audit/fsck entirely): the two-tool audit/fsck consolidation, dummy-CRC
  support (`CW_NO_DATA_CRC`), macOS-SDSC, `SD_PINS_EXTERNAL`, and the new fatchain
  suite.
- **Commit all release-prep as ONE commit** ("Release-prep for v1.6.0").
- **Tag `v1.6.0`** per `DOCs/procedures/RELEASE-CHECKLIST.md` (`git tag -a`), then
  push. `release.yml` triggers on `v*` and extracts notes by `awk` on `## [1.6.0]`.
  `origin/main` is 35+ commits behind; whether push works from the container is
  unverified — pushing from the Mac is the safe path.

---

## Working-tree state you are inheriting

All of the following is **uncommitted** on `main` (this project never branches):

| File | Change |
|---|---|
| `tools/run_regression.sh` | End-to-end runner (this handoff's subject) |
| `src/UTILS/isp_fsck_utility.spin2` | Deep audit / fsck refactor |
| `src/UTILS/SD_FAT32_check.spin2` | **Deleted** (`git rm`), consolidated away |
| `src/UTILS/SD_FAT32_audit.spin2` | Header updated for the new role |
| `CHANGELOG.md` | v1.6.0 section, full untagged range since v1.5.3 |
| `.github/workflows/release.yml` | +fatchain suite, −`SD_FAT32_check` |
| `src/DEMO/SD_demo_shell.spin2` | Banner → v1.6.0 |
| `src/{UTILS,DEMO,EXAMPLES,regression-tests}/README.md`, `diagnostic-tests/README.md` | Folder-role reminders; regression README now documents the single-command sweep |
| `DOCs/Plans/WRITE-PATH-CORRUPTION-FIX-SPRINT-PLAN.md` | §6.2 (runner change), §Step 2 retired |

Everything above compiles clean (26/26 suites + all three vehicles).

⚠️ **`DOCs/procedures/RELEASE-CHECKLIST.md` was also updated** (§2 now describes
the single-invocation sweep) **but `DOCs/procedures/` is gitignored**
(`.gitignore:239`), so that edit will not travel via git. If the Mac has its own
copy, apply the same change there by hand.

---

## Verification already done (container, no hardware)

- `bash -n` clean; `--compile-only --include-format` → 26/26 + 3 vehicles
- Log-parse functions replayed against real archived logs: `SD_FAT32_audit_*`
  (39/39 parsed) and `SD_card_identify_*` (L1/L2/L3 extracted cleanly)
- Stubbed-hardware simulation covering: all-pass end-to-end; mid-run suite failure
  (continues, exit 1, failures listed); persistent INFRA (continues, own section,
  exit 1); transient flake (retried once, run stays green, exit 0);
  `--stop-on-failure` (halts, preserves card, skips closing audit); closing-audit
  failure (hard blocker, exit 1); `--log` tee; `--no-preflight`
- `git diff tools/run_test.sh` is empty — the single-suite runner is unmodified,
  so the destructive reformat logic still lives only in the regression runner
