# Write-Path Corruption — Entry (DETECT) Regression Baseline

**Run date:** 2026-07-23
**Branch:** `sprint/write-path-corruption-fix`
**Driver version at run:** v1.5.3 tree + §1 `clusterBytes()` helper (unfixed write path — Bug A / Bug B still present)
**Purpose:** Prove the driver **fails before the fix**. This is the DETECT half of the
detect-before-fix / confirm-after-fix discipline. `SD_RT_fatchain_tests` is the
certification suite; it must fail here and pass after the write-path fix lands.

---

## Card under test

| Field | Value |
|---|---|
| Designator | SharedOEM SDHC 7GB [FAT32] SD 3.x rev0.0 |
| Serial | `$0001_B9D5` |
| Date | 2021/9 |
| Class / grade | Class 10, U1, V10 |
| SPI clock | 25 MHz |
| `cardWarnings()` | `$00` (clean — **not** a counterfeit asdfg unit) |
| Geometry (mounted) | 8 sec/clus, 4096 B/clus, 1,901,309 free clusters, ~7431 MB |

This is a healthy, mainstream card. Any failure below is the **driver's**, not the
card's — which is exactly what we want for a write-path-logic baseline.

---

## Result summary

**25 of 26 suites PASS. 1 suite FAILS — `SD_RT_fatchain_tests` (0 pass, 2 fail),
by design.** Totals: **469 pass, 2 fail** across all suites.

The two failures are the two write-path defects the sprint targets. Every other
suite — including the full `--include-format` run — is green on this card.

### Full roster (run order)

| # | Suite | Pass | Fail | Time |
|---|---|---:|---:|---:|
| 1 | SD_RT_mount_tests | 31 | 0 | 71s |
| 2 | SD_RT_raw_sector_tests | 14 | 0 | 2s |
| 3 | SD_RT_multiblock_tests | 6 | 0 | 3s |
| 4 | SD_RT_register_tests | 10 | 0 | 16s |
| 5 | SD_RT_speed_tests | 15 | 0 | 15s |
| 6 | SD_RT_crc_diag_tests | 14 | 0 | 16s |
| 7 | SD_RT_error_handling_tests | 14 | 0 | 3s |
| 8 | SD_RT_crc_validation_tests | 6 | 0 | 2s |
| 9 | SD_RT_recovery_tests | 7 | 0 | 2s |
| 10 | SD_RT_file_ops_tests | 26 | 0 | 16s |
| 11 | SD_RT_read_write_tests | 49 | 0 | 65s |
| **12** | **SD_RT_fatchain_tests** | **0** | **2** | **16s** |
| 13 | SD_RT_multihandle_tests | 21 | 0 | 16s |
| 14 | SD_RT_seek_tests | 37 | 0 | 16s |
| 15 | SD_RT_volume_tests | 31 | 0 | 45s |
| 16 | SD_RT_subdir_ops_tests | 18 | 0 | 3s |
| 17 | SD_RT_directory_tests | 30 | 0 | 32s |
| 18 | SD_RT_dirhandle_tests | 25 | 0 | 16s |
| 19 | SD_RT_fifo_tests | 21 | 0 | 1s |
| 20 | SD_RT_multicog_tests | 14 | 0 | 2s |
| 21 | SD_RT_cogcwd_tests | 5 | 0 | 3s |
| 22 | SD_RT_timestamp_tests | 6 | 0 | 12s |
| 23 | SD_RT_stress_tests | 4 | 0 | 16s |
| 24 | SD_RT_async_tests | 6 | 0 | 3s |
| 25 | SD_RT_defrag_tests | 12 | 0 | 25s |
| 26 | SD_RT_format_tests | 47 | 0 | 26s |
| | **TOTAL** | **469** | **2** | |

---

## The failure — `SD_RT_fatchain_tests` (log `SD_RT_fatchain_tests_260723-185203.log`)

Geometry reported by the suite at run time: `secPerClus = 8, cBytes = 4096,
freeClus = 1,901,309`.

### Group A — Bug A: cross-boundary overwrite must follow the FAT chain — **FAIL**
```
* Test #1: 3-cluster overwrite-first-2 preserves tail
Sub-Test: full file read (no premature EOC)
Value: 0 (expected 4_294_967_295)   ' i.e. got FALSE, expected TRUE
-> Sub-FAIL
```
A 3-cluster file was built, then only its first two clusters were overwritten in
place. On read-back the full-file read short-reads at a premature EOC: the
unconditional `allocateCluster()` at the boundary-advance sites re-linked a live
FAT link, truncating the chain and orphaning the 3rd cluster. Exactly Bug A.

### Group B — Bug B: mid-sector append must preserve leading bytes — **FAIL**
```
* Test #2: append at position==size keeps leading bytes
Value mismatch at 0: got $$0 expected $$5A
Sub-Test: leading 100 bytes intact (not zero-filled)
Value: 0 (expected 4_294_967_295)
-> Sub-FAIL
```
A 100-byte file was reopened for write, seeked to end (mid-sector), and 50 bytes
appended. The original leading bytes came back `$00` instead of `$5A` — the
mid-sector write zero-filled the sector before writing. Exactly Bug B.

Both failures reproduce the handoff's behavioral spec precisely.

---

## On-card forensics after the failure

Captured with `SD_FAT32_audit` immediately after the fatchain failure, **before**
the resume reformatted the card (`SD_FAT32_audit_260723-185222.log`):

```
=== FAT32 Filesystem Audit (read-only) ===
Tests: 39  Pass: 39   Fail: 0
=== AUDIT COMPLETE ===
```

**Notable:** on this healthy card the FAT/VBR metadata stayed structurally
consistent — the audit is fully green. The corruption is **data-level** (orphaned
tail cluster, zero-filled leading bytes), not the whole-volume FAT/VBR damage
observed on the counterfeit asdfg-class cards. Data point for the downstream
analysis: Bug A's severity manifestation is card/geometry-dependent — a healthy
card silently loses the file's tail without tripping a structural audit.

---

## Harness note — one runner bug found and fixed during this run

The first sweep aborted at the **baseline reformat** ("CARD REFORMAT FAILED"),
but the format had actually **succeeded** (`FORMAT COMPLETE`, 1,897,594 clusters,
both FATs written). Cause: `_reformat_card()` in `tools/run_regression.sh` verified
success by grepping the log for `FORMAT SUCCESSFUL`, which `SD_format_card.spin2`
emits only two `debug()` lines before `END_SESSION`; pnut-term-ts stops logging the
instant it sees `END_SESSION`, so on a *successful* format that line is truncated
mid-word and never reaches the log. **Fixed** (`tools/run_regression.sh:184-201`):
accept `FORMAT COMPLETE` (emitted by `isp_format_utility` only under `if ok`, with
four trailing lines, so it survives) or `FORMAT SUCCESSFUL`, and treat
`FORMAT FAILED` as decisive. All four reformats in the successful sweep verified OK.

This is a **test-harness** fix, not a driver change. The driver write path is
untouched — the two fatchain failures stand.

---

## How the run was executed

`run_regression.sh` halts at the first failing suite; `SD_RT_fatchain_tests` is
*designed* to fail here, so a plain run would stop at suite 12 and leave suites
13–26 unmeasured. A wrapper drove the full sweep: on a suite failure it recorded
the result, captured on-card forensics with `SD_FAT32_audit` when the failed suite
was destructive (fatchain / format), then resumed from the next suite with a fresh
FAT32 baseline (`run_regression.sh` reformats before its first suite). Two passes
total: pass 1 ran suites 1–12 (stopped at the fatchain failure), pass 2 resumed at
suite 13 and completed through 26 clean.

- Sweep transcript: `scratchpad/sweep_transcript.txt` (session-local)
- Per-suite logs: `tools/logs/SD_RT_*_<ts>.log`
- Forensic audit: `tools/logs/SD_FAT32_audit_260723-185222.log`

---

## Bottom line for the fix agent

- The DETECT gate is **proven red**: `SD_RT_fatchain_tests` = 0/2 on the unfixed
  driver, both groups, on a known-good card.
- Nothing else regressed — 25/26 suites and 469 individual checks are green,
  including format. The write-path fix must turn fatchain to **2/2** while keeping
  every other suite green (the CONFIRM run).
- Downstream analysis input: Bug A does **not** trip a structural FS audit on a
  healthy card — the loss is silent tail truncation, severity is card-dependent.
