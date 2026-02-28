# Release Checklist

Use this checklist before tagging each release. Every item must pass before the tag is created.

---

## 1. Code Freeze

- [ ] All feature work and bug fixes committed
- [ ] Working tree clean (`git status` shows no changes)

## 2. Full Regression Suite

Run all 20 test suites on hardware from `tools/`:

```bash
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_read_write_tests.spin2
./run_test.sh ../regression-tests/SD_RT_seek_tests.spin2
./run_test.sh ../regression-tests/SD_RT_directory_tests.spin2
./run_test.sh ../regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_subdir_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_dirhandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multihandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multiblock_tests.spin2
./run_test.sh ../regression-tests/SD_RT_raw_sector_tests.spin2
./run_test.sh ../regression-tests/SD_RT_volume_tests.spin2
./run_test.sh ../regression-tests/SD_RT_register_tests.spin2
./run_test.sh ../regression-tests/SD_RT_speed_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multicog_tests.spin2 -t 120
./run_test.sh ../regression-tests/SD_RT_fifo_tests.spin2
./run_test.sh ../regression-tests/SD_RT_crc_diag_tests.spin2
./run_test.sh ../regression-tests/SD_RT_crc_validation_tests.spin2
./run_test.sh ../regression-tests/SD_RT_recovery_tests.spin2
./run_test.sh ../regression-tests/SD_RT_error_handling_tests.spin2
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 300
```

- [ ] All 20 suites report PASS (END_SESSION detected)
- [ ] Note: seek_tests expected failures are known limits, not regressions

## 3. Compile Demo Shell

```bash
./run_test.sh ../src/DEMO/SD_demo_shell.spin2
```

- [ ] Compiles clean (no warnings, no errors)

## 4. Documentation Audit

### Driver docs

- [ ] `DOCs/SD-CARD-DRIVER-THEORY.md` — API names, command tables, and architecture match driver source
- [ ] `DOCs/SD-CARD-DRIVER-TUTORIAL.md` — Code examples compile-correct, method signatures match, no V1 references
- [ ] `DOCs/SD-CARD-UTILITIES.md` — Utility descriptions match current source behavior

### Utility theory docs

- [ ] `DOCs/Utils/SD-FAT32-FSCK-THEORY.md` — Matches current FSCK implementation (windowed bitmap, pass interleaving)
- [ ] `DOCs/Utils/SD-FAT32-AUDIT-THEORY.md` — Test counts match actual `auditRunTest()` calls in source
- [ ] `DOCs/Utils/SD-FORMAT-UTILITY-THEORY.md` — Describes CMD25 bulk writes, async API
- [ ] `DOCs/Utils/SD-SPEED-CHARACTERIZE-THEORY.md` — Default clock, speed levels match source
- [ ] `DOCs/Utils/SD-CARD-CHARACTERIZE-THEORY.md` — Register parsing matches source

### Spot checks

- [ ] Grep for removed API names (`readFile`, `writeFile`, `readDirectory` as standalone methods) — zero hits in docs
- [ ] Grep for single-letter variable names in method signatures — zero hits in source
- [ ] Grep for `''` on CON/DAT/VAR declaration lines — zero hits in source (except inside `#IFDEF` blocks)

## 5. README Audit

- [ ] `README.md` (top-level) — Test counts, file tree, feature list match current state
- [ ] `regression-tests/README.md` — Suite count and test totals match
- [ ] `src/README.md`, `src/DEMO/README.md`, `src/EXAMPLES/README.md`, `src/UTILS/README.md` — File lists match disk
- [ ] All `DOCs/*/README.md` — File lists match disk contents
- [ ] No references to `logs/` directories in any README
- [ ] `.release/README.md` — Tree matches release workflow, regression tests included
- [ ] `.release/src/*/README.md` — Descriptions match current source behavior

## 6. Changelog

- [ ] `CHANGELOG.md` `[Unreleased]` section is empty (all items moved to release version)
- [ ] Release version entry has correct date
- [ ] All user-facing changes since last release are listed
- [ ] Internal-only changes (refactors, renames, comment fixes) are omitted
- [ ] Credit given to all relevant tools and contributors (Spin Tools IDE, flexspin, etc.)

## 7. Release Workflow

- [ ] `.github/workflows/release.yml` copies all files that appear in `.release/README.md` tree
- [ ] New source files added since last release are included in the workflow
- [ ] Regression tests section present in workflow

## 8. Tag and Release

```bash
git tag -a v1.x.x -m "Release v1.x.x"
git push origin v1.x.x
```

- [ ] Tag pushed triggers GitHub Actions release workflow
- [ ] Release zip contains all expected files
- [ ] Release notes extracted correctly from CHANGELOG

---

*Created: 2026-02-28*
