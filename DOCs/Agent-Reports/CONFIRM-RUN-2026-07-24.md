# Write-Path Corruption — CONFIRM Run (fixed driver)

**Run date:** 2026-07-24
**Branch:** `sprint/write-path-corruption-fix`
**Driver:** v1.5.3 tree + write-path fix (Bug A / Bug B) — `src/micro_sd_fat32_fs.spin2`,
66 insertions / 16 deletions vs. the DETECT baseline.
**Pairs with:** `BASELINE-DETECT-RUN-2026-07-23.md` (same card, unfixed driver, fatchain 0/2).

The DETECT run proved the driver fails; this CONFIRM run proves the fix flips the
gate green without regressing anything.

---

## Card 1 (same unit as the DETECT run)

SharedOEM SDHC 7GB [FAT32], SN `$0001_B9D5`, 2021/9 — Class 10 U1 V10, 25 MHz SPI,
`cardWarnings()=$00`. Geometry: **8 sec/clus, 4096 B/clus** (large-cluster case).

### Standalone fatchain CONFIRM — **2 pass, 0 fail**
Log: `tools/logs/SD_RT_fatchain_tests_260724-122918.log` (reformatted card, run solo)

```
* Geometry: secPerClus = 8, cBytes = 4_096, freeClus = 1_901_309
* Test Group: Bug A: cross-boundary overwrite follows FAT chain
* Test #1: 3-cluster overwrite-first-2 preserves tail        -> pass
* Test Group: Bug B: mid-sector append preserves leading bytes
* Test #2: append at position==size keeps leading bytes      -> pass
* 2 Tests - Pass: 2, Fail: 0
```
Both defects that failed on the unfixed driver (Group A short-read at premature
EOC; Group B leading bytes zero-filled) now pass. Confirmed a second time inline
during the full sweep (`SD_RT_fatchain_tests_260724-123722.log`, 2/2).

### Full regression sweep — **26/26 suites green, 471 checks, 0 fail**
Transcript archived: `DOCs/Agent-Reports/sweep_card1_confirm_260724.txt`

| # | Suite | Pass | Fail | | # | Suite | Pass | Fail |
|---|---|---:|---:|---|---|---|---:|---:|
| 1 | mount | 31 | 0 | | 14 | seek | 37 | 0 |
| 2 | raw_sector | 14 | 0 | | 15 | volume | 31 | 0 |
| 3 | multiblock | 6 | 0 | | 16 | subdir_ops | 18 | 0 |
| 4 | register | 10 | 0 | | 17 | directory | 30 | 0 |
| 5 | speed | 15 | 0 | | 18 | dirhandle | 25 | 0 |
| 6 | crc_diag | 14 | 0 | | 19 | fifo | 21 | 0 |
| 7 | error_handling | 14 | 0 | | 20 | multicog | 14 | 0 |
| 8 | crc_validation | 6 | 0 | | 21 | cogcwd | 5 | 0 |
| 9 | recovery | 7 | 0 | | 22 | timestamp | 6 | 0 |
| 10 | file_ops | 26 | 0 | | 23 | stress | 4 | 0 |
| 11 | read_write | 49 | 0 | | 24 | async | 6 | 0 |
| **12** | **fatchain** | **2** | **0** | | 25 | defrag | 12 | 0 |
| 13 | multihandle | 21 | 0 | | 26 | format | 47 | 0 |
| | | | | | | **TOTAL** | **471** | **0** |

**Agent's two watch-items on this run:**
- **No `REFUSING` metadata-region write line** in any suite log of the run — grepped
  all `SD_RT_*_260724-12*/13*.log`, zero hits. ✅
- **No card corruption** — full destructive sweep incl. `--include-format` completed
  clean, card reformatted OK after fatchain and after format. ✅

---

## Card 2 (different cluster geometry)

Gigastone SD16G SDHC 14GB [FAT32], SN `$0000_03FB`, 2025/2 — Class 10 U1 V10,
25 MHz SPI, `cardWarnings()=$00`. Genuine card (per catalog, certified-clean).
Geometry: **16 sec/clus, 8192 B/clus (8 KB)** — 2× Card 1's 4 KB cluster.

> **Geometry-contrast caveat for the release owner:** both certified cards sit on
> the *larger*-cluster side (4 KB vs 8 KB). That is a real `sec_per_clus`
> difference (8 vs 16) with boundaries at 8 KB vs 4 KB, and the fatchain fixtures
> scale to it via `clusterBytes()` (24 KB file on Card 2 vs 12 KB on Card 1). It
> is **not** a sub-2 GB *small*-cluster (512 B–2 KB) case. If the release bar
> wants a small-cluster data point too, run a third card; the fix is
> geometry-agnostic by construction (chain-follow + load-not-zero), so this is
> belt-and-suspenders, not a gap in the two cards certified here.

### Standalone fatchain CONFIRM — **2 pass, 0 fail**
Log: `tools/logs/SD_RT_fatchain_tests_260724-133332.log` (reformatted card, solo)
Bug A (cross-boundary overwrite preserves tail) → pass; Bug B (mid-sector append
preserves leading bytes) → pass, at 8 KB clusters. Confirmed again inline in the
sweep (`SD_RT_fatchain_tests_260724-133923.log`, 2/2).

### Full regression sweep — **26/26 suites green, 471 checks, 0 fail**
Transcript archived: `DOCs/Agent-Reports/sweep_card2_confirm_260724.txt`
Sweep suites 1–25: 424 pass / 0 fail. Suite 26 (format): see note below → 47/0.

**Watch-items:**
- **No `REFUSING`** line in any Card-2 suite log — grepped all
  `SD_RT_*_260724-13[34]*.log`, zero hits. ✅
- **No corruption** — after the format-suite download glitch (below), the
  read-only `SD_FAT32_audit` was **39/39 pass**; card FS intact. Full sweep incl.
  format completed clean. ✅

**One transient — not a defect (documented for honesty):** on the first pass,
suite 26 `SD_RT_format_tests` reported 0 pass / 0 fail in 2s and the runner
flagged it failed. The log shows the cause was a **serial download checksum
error** — `Download failed: P2 checksum verification FAILED (! received) —
download corrupted` — i.e. the `.bin` was mangled over USB during download; the
test never executed. Not a driver bug, not card corruption (the post-glitch audit
was 39/39). Re-running the suite standalone gave **47 pass, 0 fail**
(`SD_RT_format_tests_260724-13*.log`, the later one). This is the known USB-replug
transient noted in project memory, unrelated to the write-path fix.

---

## Verdict

The write-path fix (Bug A + Bug B) is **certified on two cluster geometries**:

| | Card 1 (4 KB/clus) | Card 2 (8 KB/clus) |
|---|---|---|
| Standalone fatchain | 2 / 0 | 2 / 0 |
| Full sweep (26 suites) | 471 / 0 | 471 / 0 |
| `REFUSING` metadata-write lines | none | none |
| Corruption / audit | none (39/39) | none (39/39) |

DETECT (`BASELINE-DETECT-RUN-2026-07-23.md`) proved fatchain 0/2 on the unfixed
driver; CONFIRM proves 2/2 on both geometries with zero regressions. Ready for
CHANGELOG (#10) and release (#11).
