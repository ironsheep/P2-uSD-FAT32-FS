# Regression Suite Coverage Analysis — v1.7.0-pre Tree

**Date:** 2026-08-10
**Tree state:** v1.7.0-pre, uncommitted on main (container phase complete, hardware certification in progress)
**Driver:** `src/micro_sd_fat32_fs.spin2`, 9,432 lines, 136 public methods
**Suite:** 27 suites, 505 framework-counted tests + ~20 in two local-idiom suites (see Section 10)
**Supersedes:** [REGRESSION-TEST-COVERAGE-ANALYSIS.md](REGRESSION-TEST-COVERAGE-ANALYSIS.md) (2026-04-01, v1.4.2 tree)

**Purpose:** Establish whether the regression suite is sufficient to certify that driver behavior
is identical (or strictly better) release-over-release, across every dimension that affects a
consumer of the driver: public API, error contract, on-disk FAT32 structures, driver modes,
concurrency, conditional compilation, and card geometry. Gaps are ranked and classified so they
can seed a coverage-hardening mini-sprint (post-v1.7.0 — the tree is frozen for certification).

**Method:** Static call-graph extraction (every `sd.<method>(` reference per suite), error-code
name-reference mapping, per-suite `#pragma exportdef` extraction, full test-name inventory
(538 lines), plus targeted verification reads of eight gap hypotheses with file:line evidence.
**Caveats:** (1) A referenced error code is not necessarily a *provoked* one — reference is the
upper bound of coverage. (2) Only direct calls are counted; exercise through utilities
(fsck/format) is noted separately. (3) Semantic depth was judged from test names plus spot reads,
not a full read of every suite.

---

## 1. Executive Summary

The suite is in the strongest state it has ever been. Every gap tier from the 2026-04-01
analysis has been closed (Section 2), the new error-injection facility (35 tests) reaches error
paths that analysis called untestable, boundary-value coverage is systematic, and all
conditional-compilation shapes — including the core-only build — compile and run in the sweep.
The format suite's 54-test on-disk structure verification (MBR, VBR + backup, FSInfo + backup,
FAT initialization, root directory) is exemplary.

The remaining gaps fall in three bands:

**Band A — certification-instrument integrity (affects the ACTIVE sprint):**
- The two local-idiom suites (multiblock, raw_sector) emit **no `STACK WATERMARK:` line** on
  their success paths, so `--stack-report` sweeps silently record `-` for them and the §18
  STACK_SIZE max-across-suites formula excludes two of the deepest multi-block code paths
  (Section 10). A manual mitigation exists for the current bench session.

**Band B — user-facing behavior with zero test coverage:**
- Five register-access APIs (CID, SCR, SD Status, OCR, manufacturer ID) never tested (Section 4).
- `searchDirectory()` matches raw name bytes with no attribute filter — LFN and deleted entries
  are candidate matches on PC-written cards; enumeration skips LFN, open-by-name does not
  (Section 6.3). Needs investigation.
- MODE_RAW rejection gate, directory growth across a cluster boundary, structural-corruption
  mount errors, and async failure propagation are all unexercised (Sections 5–8).

**Band C — low-priority diagnostics and aspirational items** (Section 12).

None of the Band B items is a known defect — they are certification blind spots: behavior the
driver implements but that no test would notice changing between releases.

---

## 2. Scorecard vs. the 2026-04-01 Analysis

Everything that analysis proposed has been implemented, most of it growing into whole suites:

| 2026-04 item | Status today |
|---|---|
| Tier 1 (boundaries, postconditions, dir-handle errors, use-after-close, guards) | Implemented v1.2.1 |
| Tier 2 (EOF behavior, size growth, CRC diag verify, unmount cycles, pool recycling) | Implemented v1.2.1 |
| O-12 cluster-boundary crossing with known data | read_write: 256KB random-access + boundary-span tests |
| O-13 disk-full simulation | `setTestMaxClusters()` hook + volume/error_injection tests |
| O-14 all-$00 / all-$FF patterns | read_write round-trip tests |
| O-15 double-mount behavior | mount: 3 tests (succeeds, preserves handles + CWD) |
| O-16 filename edge cases | file_ops: 1-char, 8.3-max, case-fold, no-extension |
| O-18 per-cog CWD isolation | Entire cogcwd suite (5 tests) |
| O-19 concurrent reader+writer stress | Entire stress suite (4 tests) |
| O-20 mutation testing | Done — [MUTATION-TEST-RESULTS.md](MUTATION-TEST-RESULTS.md) |
| "8 of 22 error codes tested" | Now 24 of 37 referenced (Section 5) — and the code count grew by 15 |

Since that analysis the suite also gained: error_injection (35), async (7), timestamp (6),
fatchain (2), and the error-reporting audit's assertion hardening across error_handling (19).

---

## 3. Public API Coverage — 109 of 136 Methods

Full matrix in Appendix A. Summary: **109 methods have at least one regression call site; 27 have
zero.** The 27 uncovered methods classified:

| Class | Methods | Priority |
|---|---|---|
| **Register access — user-facing** | `readCIDRaw`, `readSCRRaw`, `readSDStatusRaw`, `getOCR`, `getManufacturerID`, `eraseBlockSectors` | **HIGH** — see Section 4 |
| Known-planned debug (tracked in «#41»/«#36») | `debugZeroRootSector` | Already scheduled — acceptance test on a 40-file root, raw-survey verified |
| Public safety API | `checkStackGuard` (public path; the framework exercises the guard internally), `null` | Low |
| Diagnostic / characterization (by design outside regression) | `testCMD13`, `getLastCMD13Capture`, `setForceCmd13`, `getLastCMD18Result`, `debugOnClockChange`, `debugSetSampleMode`, `debugSetPreEdgeThreshold`, `debugGetEffectiveSampleMode`, `debugGetCurrentHp`, `debugSetAlignDelayOffset`, `debugGetEffectiveAlignDelay`, `debugEraseBlock`, `debugGetDirSec`, `getTestReadCallCount` | Low — but `getTestReadCallCount`'s sibling `getTestWriteCallCount` IS tested; symmetry is one line |
| Display-only output methods | `debugDumpRootDir`, `displaySector`, `displayEntry`, `displayFAT` | Low — but note the v1.6.0 lesson: `debugClearRootDir()` was a *debug* method whose doc-vs-behavior mismatch shipped. Untested display methods are where that class of defect lives. |

**Thin coverage** (1 call site — a single test both defines and is the only witness of the
behavior): `attemptHighSpeed`, `checkCMD6Support`, `checkHighSpeedCapability`, `startWriteHandle`,
`readVBRRaw`, `fileSize`, `debugReadSectorSlow`, plus ~10 CMD12/CMD18/CMD23 diagnostic getters
(full list in Appendix A). Thin is acceptable for diagnostics; `startWriteHandle` at one call
site is notable given async is a headline feature (see Section 8).

## 4. The Register-Access Gap

`SD_RT_register_tests` (10 tests) exercises **CSD only**. `readCIDRaw`, `readSCRRaw`,
`readSDStatusRaw`, `getOCR`, and `getManufacturerID` — all public, all documented, all compiled
under `SD_INCLUDE_REGISTERS` — have zero regression coverage. They ARE heavily exercised by
utilities (`SD_card_identify`, `SD_card_characterize`, the demo shell — Appendix A), which is why
they demonstrably work; but utility exercise is not certification: no sweep asserts their
behavior, so a regression in any of them ships silently. The worker commands behind them
(`CMD_READ_CID`, `CMD_READ_SCR`, `CMD_READ_SD_STATUS`, `CMD_TEST_CMD13`) are likewise the only
non-debug worker commands with no regression path (Appendix A note).

These are cheap tests: CID/SCR/SD-Status have fixed formats with assertable invariants
(CID CRC7+always-1 bit, SCR spec version vs. `checkCMD6Support`, OCR CCS bit vs. SDHC/SDXC
identity, MID vs. the card catalog in `DOCs/cards/`).

## 5. Error-Code Contract — 24 of 37 Referenced, 13 Never

Full matrix with classification in Appendix B. The 13 never-referenced codes, by what it would
take to provoke them:

| Provokable now (test-code only) | Hardware-fault only | Infrastructure exhaustion |
|---|---|---|
| `E_NOT_FAT32` (-22) — corrupt VBR FS-type/signature via `writeSectorRaw`, remount | `E_NO_RESPONSE` (-2) | `E_STACK_OVERFLOW` (-26) |
| `E_BAD_SECTOR_SIZE` (-23) — corrupt bytes-per-sector field, remount | `E_BAD_RESPONSE` (-3) | `E_NO_LOCK` (-64) |
| `E_BAD_FSINFO` (-24) — corrupt FSInfo signatures, remount | `E_CARD_BUSY` (-6) | `E_NO_COG` (-65) |
| `E_VERIFY_FAILED` (-63) — injection during `compactFile()` read-back | `E_NO_CARD` (-8) — needs empty slot | |
| `E_INVALID_PARAM` (-94) — `setDate()` with out-of-range args; its ONLY producer (`micro_sd_fat32_fs.spin2:1409`), and no test ever passes a bad date | `E_INIT_FAILED` (-21) | |

Verified: no suite corrupts on-disk structures and remounts — error_injection corrupts only via
the fault-injection API, recovery contains no `writeSectorRaw` at all, and mount/format use raw
access read-only. The mount-validation producers sit at `micro_sd_fat32_fs.spin2:3838-3858` and
`:6209`, unwitnessed. The left column is a natural single test group: corrupt, remount-expect-
error, restore (or reformat — the regression card is formattable by standing authorization).

`E_FILE_NOT_OPEN` (-45) is documented RESERVED (never produced) and error_handling references it
only as documentation — correct as-is.

## 6. On-Disk FAT32 Structure Coverage

### 6.1 Strong
Format suite verifies every MBR/VBR/FSInfo/FAT-init/root-dir field including backups (54 tests).
Chain topology: fragmented files (defrag), overwrite-preserves-tail and append-preserves-head
(fatchain), 256KB random access across cluster boundaries, delete-reclaims-space (read_write).
Cross-buffer cache coherence: CMD25-vs-cache (multiblock test 6), dir-create-dir invalidation
(subdir_ops), enumeration-sees-create-immediately (subdir_ops). Timestamps: field ranges, epoch
boundaries (midnight Jan 1 2000, end-of-day Dec 31), advancement (timestamp + volume).

### 6.2 Gap: directory growth across a cluster boundary — never reached
Largest directory the suite ever builds is 22 entries (directory_tests). At 8 sectors/cluster a
directory cluster holds 128 entries, so the extend-directory-with-new-cluster path — the
`allocateCluster` + `clearCluster` branch in `do_create()` (`micro_sd_fat32_fs.spin2:4174-4186`),
mirrored in `do_create_contiguous()` (`:6346-6358`) and `do_newdir()` (`:5060-5071`) — has never
executed under test, on any geometry. This is cluster-boundary arithmetic of exactly the kind the
current sprint's card pairing exists to vary. A test must compute entries-per-cluster from
`sectorsPerCluster()` at runtime (129 files at 8 sec/clus; 2,049 at 64 — so cap by geometry or
use the 8 sec/clus card).

### 6.3 Gap: LFN entries — enumeration skips, open-by-name does not (needs investigation)
Driver is 8.3-only, and enumeration handles foreign LFN entries: `do_readdir_h()` skips
`ATTR_LFN == $0F` explicitly (`:4965`); `do_readdir()` skips it via the VOLUME_ID bit in its
attribute mask (`:5597`). **But `searchDirectory()` (`:5833-5949`) — the open/create/delete/
rename path — has no attribute check at all**: it uppercases and `strcomp`s the raw 11 name
bytes of every slot, including LFN fragments and deleted ($E5) entries, relying on byte mismatch
rather than skipping. On a card written by a PC (every LFN'd file has 1+ LFN entries preceding
its 8.3 entry), false matches are improbable but not excluded by design — 11 bytes of UTF-16
fragments are being compared as an 8.3 name. No test fabricates LFN entries. This is the one
finding in this analysis that is a candidate *driver* issue rather than purely a test gap:
first-step is an investigation (can a crafted LFN fragment match a legal 8.3 target?), then an
interop test that raw-writes LFN entries and verifies enumeration, open, and delete behave.

### 6.4 Gap: FAT-sector-boundary chain crossing — incidental at best
One FAT sector maps 128 clusters. The largest file under test (256KB = 64 clusters at 8
sec/clus) crosses a FAT-sector boundary only if its chain happens to straddle a multiple of 128
— card-state dependent, never asserted. The FAT-walk arithmetic (`readNextSector` advance,
`allocateCluster` FAT-sector math, `freeClusterChain`) at the 128-cluster boundary is untested
by design intent. (The fsck chain walk exercises it against whatever the card holds — again
incidental.)

### 6.5 Not covered, accepted as impractical (bench-time)
Near-4GB file sizes (FAT32 limit arithmetic, sign-safety of positions > 2^31) — writing 4GB at
bench speeds is hours per run. A synthetic variant is possible (raw-write a directory entry with
a huge size, open, exercise seek/tell/eof arithmetic without data I/O) — listed as aspirational.

## 7. Driver Modes and State Machine

Covered: MODE_NONE rejection before mount and after unmount (mount suite, both directions),
mount/unmount cycling, double-mount semantics, unmount-flushes state.

**Gap:** the MODE_RAW rejection gate — worker dispatch at `micro_sd_fat32_fs.spin2:3141-3151`
rejects all filesystem commands with `E_NOT_MOUNTED` when `driver_mode <> MODE_FILESYSTEM` —
is never exercised: no test calls a filesystem operation after `initCardOnly()`. All three
suites that use `initCardOnly` (raw_sector, register, format) follow it only with raw/register
operations. Also untested: `mount()` upgrade from MODE_RAW. Both are two-line tests in an
existing suite.

## 8. Concurrency and Async

Covered: singleton `start()` from 3 cogs, concurrent reads (multicog), one-writer-one-reader and
dual-reader integrity (stress), per-cog error isolation (multicog), per-cog CWD isolation — and,
notably, a true dual-writer overlap: cogcwd test 4 runs 10 create/write/close/delete cycles on
two cogs simultaneously in different directories. Caveat: its assertions are CWD integrity, not
written-data integrity. Async: round-trip parity with blocking I/O, isComplete transition,
cancel-releases-lock, cross-cog interleave, double-start busy, foreign-cog rejection.

**Gaps:**
- **Async failure propagation is entirely untested.** Every `startReadHandle` uses a valid
  handle; no injection is armed during an async op; no test asserts a negative `getResult()`.
  Whether an I/O error inside the worker surfaces correctly through the async completion path —
  a headline v1.7.0 error-reporting concern — is uncertified. `startWriteHandle` has exactly one
  call site.
- Dual-writer with **data**-integrity assertions (extend stress: both cogs write distinct
  patterns, verify both files byte-for-byte).

## 9. Conditional Compilation — Strong

All shapes compile and run in the sweep (Appendix C): 9 suites at `SD_INCLUDE_ALL`, 5 at
core-only (no flags: dirhandle, fifo, multicog, multihandle, seek), and the rest at specific
combinations covering RAW/DEBUG/REGISTERS/SPEED/ASYNC/DEFRAG/TEST_HOOKS/STACK_CHECK. The Phase
1c consumer sweep additionally compiles EXAMPLES/DEMO/UTILS. No action needed. (Reminder from
the pnut-ts gotcha list: `-D` defines are global to all objects and the compile cache keys on
them — the per-suite build isolation in run_test.sh is what makes this matrix trustworthy.)

## 10. Framework Consistency and the Watermark Blind Spot (ACTIVE-SPRINT RELEVANT)

Two suites — **multiblock** and **raw_sector** — predate the framework's totals discipline and
use a local `recordPass()`/`recordFail()` idiom. On their success paths they print their own
banner and `END_SESSION` **without calling `utils.ShowTestEndCounts()`**
(`SD_RT_multiblock_tests.spin2:199-204`, `SD_RT_raw_sector_tests.spin2:368-371`; the framework
path is only reached on early-abort). Their banners do match the `"Tests - Pass:"` pattern that
`run_regression.sh:1113-1119` parses, so **scoring is correct**. But bypassing
`ShowTestEndCounts` costs three protections:

1. **No `STACK WATERMARK:` line in measurement builds.** `reportStackWatermark()` fires only
   inside `ShowTestEndCounts()` (`isp_rt_utilities.spin2:112-120`), and the sweep collector
   (`run_regression.sh:1140-1152`) greps only that format — a missing line is recorded as `-`
   *without failing anything*. So a `--stack-report` sweep silently excludes multiblock and
   raw_sector — two of the deepest multi-block CMD18/CMD25 paths — from the §18
   max-across-suites STACK_SIZE formula.
   **Mitigation available for the current bench session:** both suites independently print
   `"* Worker cog stack: N of M longs used"` via `sd.reportStackDepth()` under
   `SD_INCLUDE_STACK_CHECK` (which both exportdef). The operator must harvest those two numbers
   from the logs **manually** and include them in the max before applying the §18 formula.
2. **No `BAD TEST COUNTS` cross-check** (planned-vs-executed bookkeeping) for these suites.
3. **No 500ms drain delay** before `END_SESSION` — the exact truncation race documented in
   `isp_rt_utilities.spin2` (observed 2026-08-07) that the framework's delay exists to prevent.
   Their banners sit a few lines ahead of `END_SESSION`, which narrows but does not close the
   window.

The durable fix is converting both suites to the framework idiom (mechanical, container-
verifiable) — but it edits test sources, so under the §17/§18 freeze rules it re-enters at style
conformance and re-shakedown. Sequencing is Stephen's call: before §18 finalization (so the
formula sees all 27 suites automatically) or in the mini-sprint with manual harvest accepted for
v1.7.0, recorded on the sprint record.

Minor: framework-counted inventory is 505 tests across 25 suites; the two local-idiom suites add
~20 more by their own banners. Doc-count checks should state which basis they use.

## 11. Card Geometry

Formatter capacity table (8/16/32/64 sec/clus buckets) is fully validated against the card
catalog (2026-07-31). The regression suite + driver cluster arithmetic have run at 8 and 16;
the in-flight «#41» pairing adds 64 (and retires 16-adjacent redundancy). **32 sec/clus remains
unexercised by any regression run** — the Gigastone 00000 32GB (`DOCs/cards/gigastone-00000-32gb.md`)
covers it whenever a third-card run is scheduled. After «#41», the residual geometry risk is low
(8 and 64 bracket the range) but nonzero for bucket-boundary behavior.

## 12. Ranked Gap List — Mini-Sprint Candidates

Venue: **C** = container-only (compile-verifiable now), **H** = needs bench. All post-v1.7.0
unless Stephen re-sequences G-1. Impact: certification blind spot unless marked otherwise.

| # | Gap | Venue | Effort | Notes |
|---|---|---|---|---|
| G-1 | Convert multiblock + raw_sector to framework idiom (fixes watermark blind spot, BAD TEST COUNTS, drain race) | C+H | S | §10. Interim: manual watermark harvest THIS sweep |
| G-2 | Register-API tests: CID/SCR/SD-Status/OCR/MID/eraseBlockSectors with format-invariant assertions | C+H | S | §4 — highest user-facing value |
| G-3 | Structural-corruption mount group: provoke E_NOT_FAT32 / E_BAD_SECTOR_SIZE / E_BAD_FSINFO, restore | H | M | §5 — card formatting authorized |
| G-4 | MODE_RAW rejection + raw→mount upgrade tests | C+H | XS | §7 |
| G-5 | Async failure-path tests: injection during async, negative getResult, bad-handle start; more startWriteHandle | C+H | M | §8 — v1.7.0 error-reporting theme |
| G-6 | LFN interop: searchDirectory investigation FIRST, then fabricated-LFN enumeration/open/delete tests | C+H | M | §6.3 — potential driver finding |
| G-7 | Directory cluster-growth test (geometry-aware, >128 entries at 8 sec/clus) | H | M | §6.2 |
| G-8 | E_INVALID_PARAM (bad setDate) + E_VERIFY_FAILED (injection during compact) provocation | C+H | XS | §5 |
| G-9 | Dual-writer data-integrity stress test | C+H | S | §8 |
| G-10 | Coverage gate script `tools/check_api_coverage.sh`: fail when a new PUB has zero regression call sites (allowlist for diagnostic classes) — makes this analysis self-sustaining release-over-release | C | S | §13 |
| G-11 | Multiblock boundary LBAs: last-sector-of-card, count-spanning cases | H | S | §Q8 — only count=0/1 today |
| G-12 | FAT-sector-boundary chain test (deliberate 128-cluster straddle) | H | M | §6.4 |
| G-13 | 32 sec/clus sweep on the 32GB catalog card | H | bench-time | §11 |
| G-14 | Aspirational: synthetic near-4GB size-arithmetic test | C+H | M | §6.5 |

Suggested mini-sprint shape (per task-execution convention, container batch first):
G-10, G-4, G-8, G-1 (framework conversion), then authoring G-2/G-5/G-6/G-9 to compile-clean,
then one hardware batch runs everything new plus G-3/G-7/G-11, with G-12/G-13/G-14 as stretch.

## 13. Release-over-Release Certification — What "Identical or Better" Requires

The suite already certifies most of the contract *when it is green on hardware*. To make the
comparison mechanical between releases:

1. **API-coverage gate (G-10)** — regenerate the Appendix A matrix from source in CI/container;
   a new public method with no test and no allowlist entry fails the gate. Same pattern as the
   existing `check_doc_counts.sh` family.
2. **Error-contract gate** — same script family: every `E_*` either referenced by a suite,
   allowlisted (hardware-fault class), or documented RESERVED.
3. **Per-suite score baseline** — run_regression already emits per-suite pass/fail; the sweep
   procedure already compares green-ness rather than raw totals (correct — counts legitimately
   drift). Keep that rule.
4. **Geometry statement in the certification record** — each certification names the sec/clus
   values it ran at (already practiced via card serials + DOCs/cards).

With G-10 and the error gate in place, this document stops being a periodic manual effort:
the matrices regenerate, and only the semantic judgment (Sections 6–8) needs a human pass.

---

## 14. Code-Rooted Findings (addendum, 2026-08-10, same day)

Three targeted code-research passes were run to root the open findings of Sections 5–8 in the
actual driver source. They confirmed some findings, cleared others, and surfaced **new
user-affecting defects** now recorded on `DOCs/Plans/PUNCH-LIST.md` (section "2026-08-10
regression-coverage code audit"). Summary here; the punch list carries the dispositions.

### 14.1 searchDirectory: the attribute filter is missing at the center — CONFIRMED DEFECT FAMILY

`searchDirectory()` (`:5833-5952`) matches purely on the 11 uppercased name bytes; the attribute
byte is never read in the match loop, `$E5` entries are never skipped for matching, and the scan
stops at `$00` only after comparing. Attribute filtering exists only per-caller, unevenly, across
the 14 call sites. Consequences, all **plain-ASCII reachable** when the volume label is dot-less
and <=11 chars (the label store format at `:5437-5459` is byte-identical to the search key for
such names):

| Path | Filter present? | Outcome on a label match |
|---|---|---|
| `do_open` (moveFile) `:3992` | full mask | safe (`E_FILE_NOT_FOUND`) |
| `do_delete` `:5195` | `$0F` mask | safe — label NOT deleted (mask side-effect: read-only/hidden/system files report `E_FILE_NOT_FOUND` on delete — separate item) |
| `do_open_dir` `:4874` | dir-only | safe (`E_NOT_A_DIR`) |
| `do_open_read` `:4051` | dir-only | **opens the label as a 0-byte file** (benign EOF; wrong answer) |
| `do_open_write` `:4094` | dir-only | opens; first write fails closed `E_BAD_CHAIN`; close stamps the label's write date |
| `do_create`/`do_newfile`/`do_newdir` | none | **`E_FILE_EXISTS` for a name no enumeration shows** (enumeration skips the label — `:4965-4969`, `:5596` — so the conflict is invisible) |
| `do_rename` old-name `:5355-5413` | **none** | **silently renames the volume label** — the severe one; VBR label copy not updated, so the two label stores then disagree |
| `do_chdir` `:5265` | dir OR root-sec arm | **returns SUCCESS and sets CWD to root** — via the `firstCluster()==0 -> clus2sec(2)` redirect at `:5924-5925` |

Independent facets found alongside:
- **`do_chdir` zero-cluster hole is broader than the label**: ANY 0-byte cluster-0 entry —
  including ordinary PC-created empty files — makes `changeDirectory("EMPTY.TXT")` return
  SUCCESS and move the CWD to root.
- **`do_create_contiguous` leaks its pre-allocated chain** on `E_FILE_EXISTS`: the contiguous
  chain is allocated at `:6320-6325` BEFORE the existence check at `:6333` — lost clusters on
  every duplicate-name call, label or not.
- **Cluster-0 append gap**: `openFileWrite` on any 0-byte cluster-0 file (PC-created) fails its
  first write with `E_BAD_CHAIN` (`:4529-4534`) — fails closed, but the file is unappendable.
- LFN false-match: **provably impossible for ASCII long names** (the UTF-16 high bytes are `$00`,
  which truncates the compared string; a false match needs five consecutive >=U+0100 chars at a
  fragment index equal to the key's first letter) — adversarial only. Deleted-entry match needs
  a literal `$E5` first byte in user input (no name validation exists — `:5876-5899` folds case
  and nothing else); adversarial only. Both are backlog, not release items.
- History: behavior is long-standing (blames to 2026-04-02, `bfc7559`), not introduced this sprint.

**Recommended central fix** (for the mini-sprint): reject `ATTR_VOLUME_ID`/`ATTR_LFN`/`$E5`
slots inside `searchDirectory`'s match arm — one place all 14 callers share — demoting the eight
scattered per-caller filters from load-bearing to defense-in-depth. The chdir zero-cluster
redirect and the contiguous-chain leak need their own fixes.

### 14.2 Async: errors propagate correctly; the robustness holes are elsewhere

The Section 8 fear is **cleared**: worker failures reach the caller — `CMD_READ_H` maps a
negative `do_read_h` result into `pb_status` (`:3288-3290`), and `getResult()` (`:1601-1616`)
returns the negative code and `set_error()`s it for the collecting cog; short counts follow the
blocking API's exact contract with `handleError()` as the resolver. `ERROR()` is correct at
collect time by design (`:1540`). So G-5 is purely a test gap: no async test injects an I/O
failure or asserts a negative `getResult()`.

New latent defects found (punch-listed):
- **`getResult()` never calls `checkStackGuard()`** — `send_command` escalates a guard violation
  to `E_STACK_OVERFLOW` overriding even SUCCESS (`:3470-3480`); the async collect path has no
  equivalent, so worker memory corruption during an async op is undetectable.
- **Same-cog misuse deadlocks silently**: no `async_active` guard on blocking calls, `unmount()`,
  `stop()`, or `closeFileHandle()`; the API lock is not re-entrant, so the owner spins forever.
  `E_ASYNC_BUSY` is raised only by a second `start*()`. Also a non-atomic busy-check
  (`:1524/:1537` straddle the lock acquisition): a losing `startReadHandle` **blocks for the
  winner's whole operation** instead of returning `E_ASYNC_BUSY`.
- Start-time validation is nil (`:1524-1526`) — bad handles surface only at `getResult()`.
  Discoverable, not swallowed; `PENDING` is not well-formedness.
- `cancelAsync()` cannot abandon (SPI mid-transfer): the op **completes**, handle position moves,
  only the result is discarded (`:1629-1637`). The existing async test 4 masks this by reseeking;
  G-5's tests should pin it, and the API doc should state it.

### 14.3 Mount validation: exact shape for the G-3 corruption tests

Check order in `do_mount()` (`:3788-3935`), first failure wins: MBR readable (`E_IO_ERROR`) ->
partition type `$0B/$0C` at LBA0+`$1C2` (`E_NOT_FAT32`) -> VBR readable (`E_IO_ERROR`) ->
bytes/sector==512 at VBR+`$0B` (`E_BAD_SECTOR_SIZE`) -> sec/cluster power-of-two at VBR+`$0D`
(`E_NOT_FAT32`) -> numFATs==2 at VBR+`$10` (`E_NOT_FAT32`). Facts that reshape the tests:
- The `"FAT32   "` type string and the `$AA55` signature are **never checked** — corrupting them
  is a no-op. The FAT32 gate is the partition-type byte alone.
- **`secPerClus == 0` passes the power-of-two check** and reaches `root_sec // sec_per_clus` at
  `:3868` — **divide-by-zero in the worker cog**: a corrupted card hangs the driver instead of
  returning `E_NOT_FAT32`. Punch-listed.
- `E_BAD_FSINFO` is NOT a mount error: mount tolerates bad FSInfo and disables the hint
  (`:3906-3925`); -24 surfaces at unmount/sync (`:3964-3966`, `:5336-5338`) or via
  `lastFlushError()` — and only if the signatures break AFTER a clean mount read them (mount
  with bad signatures sets `$FFFF_FFFF`, which makes `updateFSInfo` a no-op at `:6198`). The
  test must corrupt via `writeSectorRaw` while mounted.
- **No backup fallback exists**: `backBootSec` is declared (`:566`) but never read; backup FSInfo
  (+7) is written (`:6222`) but never read. Corrupt the primary only.
- MBR-less (superfloppy) cards are not supported — `:3828` unconditionally parses a partition
  table. Worth a doc-claims check.
- RAW->FILESYSTEM upgrade is clean (`:3811-3819` skips re-init; mode assigned only on success at
  `:3932`) — a failed mount leaves MODE_RAW usable, which is exactly what corrupt/assert/repair/
  remount needs. `initCardOnly()` when mounted returns `E_NOT_MOUNTED` (odd but harmless code
  choice; noted for the doc pass).

### 14.4 FAT arithmetic: sound — with one asymmetry and one flattening

The `(cluster>>7 + fat_sec, (cluster<<2) & 511)` arithmetic is verbatim-consistent across all
seven walk sites, and the BUF_FAT cache-tag discipline (pre-invalidate `:7460`, commit only
after CRC acceptance `:7635-7639`, invalidate-before-write `:7870/:7880`) makes boundary
crossings safe by construction. Two real findings (punch-listed):
- **High-nibble mask asymmetry**: `freeClusterChain` (`:6266/:6285`), `readNextSector` (`:6154`),
  `do_read_h` (`:4327`), `writeAdvanceCluster` (`:4426`) follow raw 32-bit FAT entries unmasked,
  while `countFileFragments` (`:6545`) and `allocateCluster` (`:6064`) mask `FAT32_ENTRY_MASK`.
  A volume with nonzero reserved high bits (legal; written by other systems) sends the unmasked
  walkers to a wrong FAT sector. `allocateCluster` carefully PRESERVES those bits on write
  (`:6065/:6082`), so the asymmetry is real, not stylistic.
- **Dir-extend error flattening**: `do_create`/`do_create_contiguous` report a failed FAT write
  during directory extension (`E_IO_ERROR` from `allocateCluster`) as `E_DISK_FULL`
  (`:4175-4186`, `:6348-6359`); `do_newdir`/`do_newfile` propagate the true code. Also: on a
  `clearCluster` failure the new cluster is already chain-linked — the directory grows by one
  cluster of garbage entries (assertable with an injection test).
- **G-12 steering method** (test design): raw-write the FSInfo `FSI_Nxt_Free` hint to 126–127
  and remount — `allocateCluster(0)` trusts the hint (`:6009-6022`), so the next file creation
  starts its chain just below the 128-cluster FAT-sector boundary and the first growth crosses
  it. `setTestMaxClusters` is a ceiling only, cannot steer — and `do_freespace`/
  `countFreeClusters` ignore it while armed (free-space queries disagree with allocation).

### 14.5 Register getters: G-2 test-design facts

`readCIDRaw`/`readCSDRaw`/`readSCRRaw`/`readSDStatusRaw` fetch **live from the card per call**
(16/16/8/64 bytes; CID and CSD include the CRC7+stop byte at [15]); `getOCR`,
`getManufacturerID`, `eraseBlockSectors` are **init-time caches** (OCR stored once at CMD58,
`:7243`; MID forced to 0 on CID read failure, `:9032`). All work in MODE_RAW — the register
commands fall outside both worker mode-gate ranges. None of the four cached getters touches
`set_error()`, so tests must not judge them via `ERROR()`. Assertable invariants: CID/CSD
`buf[15] & 1 == 1`; `buf[0] == getManufacturerID()`; CSD version vs OCR CCS bit agreement;
SCR structure==0 and SD_SPEC >= 2 iff `checkCMD6Support()`; SD-Status bus-width==0 in SPI mode;
MID against the `DOCs/cards/` catalog.

### 14.6 Effect on the Section 12 gap list

- **G-6 upgrades from "investigation" to a confirmed defect family** — the mini-sprint item is
  now: central fix in `searchDirectory` + chdir zero-cluster fix + contiguous-leak fix + tests
  that witness each facet (label rename, chdir-on-empty-file, invisible `E_FILE_EXISTS`,
  cluster-0 append). Punch list owns the release disposition.
- **G-5 confirmed as test-only** for propagation, but gains three defect-witness tests
  (stack-guard on collect, same-cog busy guards, cancel-position semantics) once those fixes land.
- **G-3 redesigned** per 14.3: corrupt partition-type/bytes-per-sector/numFATs for the three
  mount errors; FSInfo corruption must happen while mounted and asserts at unmount; add the
  `secPerClus=0` case ONLY after its fix (today it hangs the worker).
- **G-12 has a concrete method** (FSInfo hint steering) — effort drops from M to S.
- **New G-15**: FAT high-nibble interop probe — OR `$F000_0000` into a live FAT link via
  `writeSectorRaw`, walk the chain, assert correct behavior after the masking fix.
- **New G-16**: dir-extend injection tests — `setTestFailSector` on a FAT sector during a
  directory extend; assert true error code (after the flattening fix) and directory consistency.

---

*Matrices generated 2026-08-10 from the uncommitted v1.7.0-pre working tree. Two rows in
Appendix A carry one phantom consumer each (`README.md` under `mount`, a log file under
`volumeLabel`) — doc/log artifacts caught by the consumer grep, not source consumers.
Section 14 added the same day from three code-research passes; line numbers refer to the
same tree.*


---

## Appendix A: Public API Coverage Matrix (136 methods)

### A.1 Lifecycle & mount

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `unmount` | 62 | crc_validation, crc_diag, fatchain, defrag, dirhandle, cogcwd, directory, error_handling, file_ops, error_injection, multicog, multiblock, seek, multihandle, read_write, mount, speed, register, recovery, stress, async, timestamp, format, volume, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+24 more) |
| `mount` | 54 | crc_diag, crc_validation, fatchain, defrag, directory, dirhandle, cogcwd, error_handling, file_ops, error_injection, speed, multiblock, seek, multicog, multihandle, register, async, mount, read_write, recovery, stress, format, volume, timestamp, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+29 more) |
| `stop` | 7 | error_injection, multicog, register, format | SD_demo_shell.spin2, SD_FAT32_fsck.spin2 (+6 more) |
| `start` | 5 | multicog | SD_demo_shell.spin2 |
| `initCardOnly` | 4 | raw_sector, register, format | isp_fsck_utility.spin2, isp_format_utility.spin2 (+17 more) |
| `null` | 0 | - | - |

### A.2 File handle API

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `closeFileHandle` | 355 | crc_validation, crc_diag, fatchain, directory, defrag, error_handling, dirhandle, file_ops, cogcwd, error_injection, speed, multicog, multiblock, recovery, multihandle, stress, mount, seek, read_write, async, timestamp, volume, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+9 more) |
| `openFileRead` | 197 | crc_diag, crc_validation, fatchain, directory, file_ops, dirhandle, cogcwd, defrag, error_handling, error_injection, async, multiblock, multicog, seek, stress, mount, read_write, multihandle, speed, recovery, volume, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+6 more) |
| `writeHandle` | 162 | crc_diag, fatchain, crc_validation, file_ops, error_handling, dirhandle, directory, cogcwd, defrag, error_injection, seek, multiblock, multicog, speed, recovery, mount, stress, read_write, multihandle, async, volume, timestamp, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+9 more) |
| `createFileNew` | 157 | file_ops, async, crc_diag, crc_validation, cogcwd, directory, fatchain, speed, dirhandle, error_injection, defrag, stress, multicog, mount, error_handling, multiblock, seek, read_write, multihandle, timestamp, recovery, volume, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+9 more) |
| `readHandle` | 145 | crc_diag, crc_validation, fatchain, defrag, file_ops, directory, error_injection, dirhandle, cogcwd, error_handling, async, multicog, seek, speed, recovery, stress, read_write, multihandle, mount | SD_example_read_write.spin2, SD_example_multicog.spin2 (+6 more) |
| `seekHandle` | 46 | fatchain, dirhandle, error_injection, seek, read_write, recovery, stress, multihandle, async | SD_diag_cmd13_capture.spin2, SD_worker_stack_depth_probe.spin2 |
| `fileSizeHandle` | 34 | file_ops, error_handling, seek, multicog, multihandle, read_write, stress, volume, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2, SD_demo_shell.spin2 |
| `sync` | 15 | error_injection, volume | - |
| `openFileWrite` | 13 | fatchain, defrag, file_ops, error_handling, multihandle, stress, recovery | SD_example_data_logger.spin2 |
| `eofHandle` | 9 | error_handling, read_write, multihandle | - |
| `syncHandle` | 9 | error_injection, error_handling, multihandle, read_write | SD_example_data_logger.spin2 |
| `tellHandle` | 9 | error_handling, error_injection, multihandle, read_write | - |
| `syncAllHandles` | 5 | volume | SD_zero_root_sector_probe.spin2, SD_worker_stack_depth_probe.spin2 |
| `createFileContiguous` | 2 | defrag | SD_worker_stack_depth_probe.spin2 |

### A.3 Async API

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `getResult` | 7 | async | SD_demo_shell.spin2 |
| `startReadHandle` | 7 | async | - |
| `isComplete` | 3 | async | - |
| `cancelAsync` | 2 | async | - |
| `startWriteHandle` | 1 | async | - |

### A.4 Directory & namespace

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `deleteFile` | 374 | crc_validation, fatchain, crc_diag, cogcwd, directory, file_ops, defrag, dirhandle, error_handling, error_injection, multicog, multiblock, seek, speed, mount, stress, multihandle, recovery, read_write, volume, timestamp, async, subdir_ops | SD_example_read_write.spin2, SD_example_multicog.spin2 (+8 more) |
| `changeDirectory` | 160 | cogcwd, dirhandle, directory, error_injection, error_handling, mount, subdir_ops | SD_example_directory_walk.spin2, SD_example_data_logger.spin2 (+2 more) |
| `openDirectory` | 48 | dirhandle, error_handling, error_injection, multihandle, timestamp, subdir_ops | SD_example_directory_walk.spin2, SD_demo_shell.spin2, SD_zero_root_sector_probe.spin2 |
| `closeDirectoryHandle` | 47 | error_injection, error_handling, dirhandle, multihandle, timestamp, subdir_ops | SD_example_directory_walk.spin2, SD_demo_shell.spin2, SD_zero_root_sector_probe.spin2 |
| `newDirectory` | 32 | dirhandle, cogcwd, file_ops, error_handling, directory, error_injection, multicog, mount, volume, subdir_ops | SD_example_directory_walk.spin2, SD_example_data_logger.spin2 (+2 more) |
| `readDirectoryHandle` | 31 | dirhandle, error_injection, timestamp, subdir_ops | SD_example_directory_walk.spin2, SD_demo_shell.spin2, SD_zero_root_sector_probe.spin2 |
| `fileName` | 19 | error_handling, dirhandle, directory, error_injection, timestamp, volume | SD_example_directory_walk.spin2, SD_demo_shell.spin2 |
| `readDirectory` | 10 | directory, volume | SD_example_directory_walk.spin2 |
| `attributes` | 6 | directory, dirhandle, error_handling | SD_example_directory_walk.spin2, SD_demo_shell.spin2 |
| `rename` | 6 | error_handling, file_ops, error_injection, subdir_ops | SD_example_directory_walk.spin2, SD_demo_shell.spin2, SD_worker_stack_depth_probe.spin2 |
| `syncDirCache` | 5 | file_ops, error_handling, error_injection | - |
| `moveFile` | 3 | directory, error_injection | SD_demo_shell.spin2 |
| `fileSize` | 1 | error_handling | SD_example_directory_walk.spin2, SD_demo_shell.spin2 |

### A.5 Volume & metadata

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `freeSpace` | 32 | crc_diag, fatchain, dirhandle, error_injection, directory, defrag, file_ops, register, speed, seek, mount, read_write, multihandle, stress, volume, format | SD_example_directory_walk.spin2, SD_demo_shell.spin2 (+4 more) |
| `volumeLabel` | 22 | crc_validation, crc_diag, file_ops, directory, error_handling, dirhandle, seek, speed, mount, recovery, register, multihandle, read_write, subdir_ops, format, volume | SD_example_read_write.spin2, SD_example_directory_walk.spin2 (+4 more) |
| `setDate` | 11 | timestamp, volume | SD_example_data_logger.spin2, SD_demo_shell.spin2 |
| `clusterBytes` | 10 | fatchain, defrag, directory, error_handling, error_injection, stress, read_write | - |
| `sectorsPerCluster` | 10 | fatchain, error_handling, defrag, directory, stress, read_write, volume | - |
| `fileFragments` | 9 | defrag, error_injection | SD_worker_stack_depth_probe.spin2 |
| `compactFile` | 6 | defrag | - |
| `setVolumeLabel` | 5 | volume | SD_demo_shell.spin2 |
| `getDate` | 3 | timestamp | SD_demo_shell.spin2 |
| `isFileContiguous` | 3 | defrag | SD_worker_stack_depth_probe.spin2 |

### A.6 Error reporting

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `ERROR` | 19 | error_handling, error_injection, speed, multihandle | SD_demo_shell.spin2 |
| `handleError` | 8 | error_injection | - |
| `reportStackDepth` | 7 | file_ops, directory, multiblock, mount, raw_sector, read_write, format | SD_stack_depth_test.spin2, SD_worker_stack_depth_probe.spin2, RT_stack_watermark_probe.spin2 |
| `cardWarnings` | 6 | crc_diag, crc_validation, error_injection, multiblock, raw_sector, recovery | SD_demo_shell.spin2, SD_card_identify.spin2 (+12 more) |
| `clearFlushError` | 6 | error_injection | - |
| `lastFlushError` | 5 | error_injection | SD_example_data_logger.spin2 |
| `checkStackGuard` | 0 | - | - |

### A.7 Raw sector & card info

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `readSectorRaw` | 24 | file_ops, error_handling, error_injection, multiblock, mount, raw_sector, format, volume | SD_demo_shell.spin2, isp_fsck_utility.spin2 (+24 more) |
| `writeSectorRaw` | 9 | error_injection, multiblock, raw_sector | isp_fsck_utility.spin2, isp_format_utility.spin2 (+13 more) |
| `writeSectorsRaw` | 6 | multiblock | isp_format_utility.spin2, SD_performance_benchmark.spin2 (+8 more) |
| `cardSizeSectors` | 5 | error_injection, multiblock, register, raw_sector, format | isp_fsck_utility.spin2, isp_format_utility.spin2 (+10 more) |
| `readSectorsRaw` | 5 | multiblock | SD_demo_shell.spin2, SD_performance_benchmark.spin2 (+7 more) |
| `readCSDRaw` | 2 | register | SD_card_characterize.spin2, SD_macca_diagnostic.spin2, SD_phase_sweep_test.spin2 |
| `readVBRRaw` | 1 | volume | - |
| `eraseBlockSectors` | 0 | - | SD_macca_diagnostic.spin2, SD_macca_diagnostic_v4.spin2 (+2 more) |
| `getManufacturerID` | 0 | - | SD_macca_diagnostic.spin2 |
| `getOCR` | 0 | - | SD_demo_shell.spin2, SD_card_identify.spin2 (+10 more) |
| `readCIDRaw` | 0 | - | SD_demo_shell.spin2, SD_card_identify.spin2 (+4 more) |
| `readSCRRaw` | 0 | - | SD_demo_shell.spin2, SD_card_identify.spin2 (+2 more) |
| `readSDStatusRaw` | 0 | - | SD_card_identify.spin2, SD_card_characterize.spin2, SD_card_info_tests.spin2 |
| `testCMD13` | 0 | - | SD_macca_diagnostic_v4.spin2 |

### A.8 Speed & timing

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `setSPISpeed` | 10 | speed | SD_spi_limit_test.spin2, SD_macca_diagnostic.spin2 (+7 more) |
| `getSPIFrequency` | 9 | speed | SD_demo_shell.spin2, SD_card_identify.spin2 (+5 more) |
| `isHighSpeedActive` | 3 | speed | - |
| `getCardMaxSpeed` | 2 | speed, register | SD_demo_shell.spin2, SD_card_identify.spin2 (+4 more) |
| `getReadTimeout` | 2 | speed, register | SD_macca_diagnostic.spin2, SD_macca_diagnostic_v4.spin2, SD_macca_diagnostic_v3.spin2 |
| `getWriteTimeout` | 2 | speed, register | SD_macca_diagnostic.spin2, SD_macca_diagnostic_v4.spin2, SD_macca_diagnostic_v3.spin2 |
| `attemptHighSpeed` | 1 | speed | SD_speed_characterize.spin2 |
| `checkCMD6Support` | 1 | speed | SD_speed_characterize.spin2 |
| `checkHighSpeedCapability` | 1 | speed | - |

### A.9 Test hooks

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `clearTestErrors` | 73 | crc_validation, defrag, error_injection, recovery, volume | SD_diag_cmd13_capture.spin2 |
| `getTestErrorCount` | 34 | crc_validation, error_injection | - |
| `setTestFailSector` | 16 | error_injection | - |
| `setTestFailWriteAfter` | 8 | error_injection | - |
| `setTestForceReadError` | 8 | crc_validation, error_injection, recovery | - |
| `setTestMaxClusters` | 5 | defrag, error_injection, volume | - |
| `getTestWriteCallCount` | 4 | error_injection | - |
| `setCRCValidation` | 4 | crc_diag | - |
| `setTestForceWriteError` | 4 | crc_validation, error_injection, recovery | - |
| `setTestFailReadAfter` | 1 | error_injection | - |
| `getTestReadCallCount` | 0 | - | - |
| `setForceCmd13` | 0 | - | SD_diag_cmd13_capture.spin2 |

### A.10 CRC & command diagnostics

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `getCRCMatchCount` | 10 | crc_diag, mount | - |
| `getCRCMismatchCount` | 10 | crc_diag, crc_validation, error_injection, mount, recovery | SD_la_streamer_diag.spin2 |
| `getCRCRetryCount` | 9 | crc_validation, crc_diag, error_injection, mount | SD_la_streamer_diag.spin2 |
| `getLastCMD13Error` | 5 | crc_diag, mount, raw_sector | SD_macca_diagnostic.spin2, SD_macca_diagnostic_v4.spin2, SD_diag_cmd13_capture.spin2 |
| `getLastCMD13` | 3 | crc_diag, mount | SD_macca_diagnostic.spin2, SD_tempcog_repro.spin2 (+3 more) |
| `getLastCMD18FailPath` | 3 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCalculatedCRC` | 3 | crc_diag, mount | SD_freq_sweep_tests.spin2, SD_la_streamer_diag.spin2 (+2 more) |
| `getLastCMD12R1` | 2 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD12Result` | 2 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD13PreCapture` | 2 | raw_sector | SD_diag_cmd13_capture.spin2 |
| `getLastCMD18R1` | 2 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD18SectorsRead` | 2 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD18Token` | 2 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD23Used` | 2 | multiblock | - |
| `getLastReceivedCRC` | 2 | crc_diag, mount | SD_tempcog_repro.spin2, SD_freq_sweep_tests.spin2 (+3 more) |
| `getWriteDiag` | 2 | error_injection, raw_sector | isp_format_utility.spin2, SD_single_then_multi_repro.spin2 (+6 more) |
| `getCmd23Supported` | 1 | multiblock | - |
| `getCmdR1Diag` | 1 | raw_sector | SD_lba_scan_50K.spin2, SD_lba_range_repro.spin2 (+3 more) |
| `getLastCMD12Capture` | 1 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD12PreCapture` | 1 | multiblock | SD_diag_cmd13_capture.spin2 |
| `getLastCMD23R1` | 1 | multiblock | - |
| `getLastCMD23Verify` | 1 | multiblock | - |
| `getLastSentCRC` | 1 | crc_diag | - |
| `debugOnClockChange` | 0 | - | SD_macca_diagnostic.spin2, SD_frequency_characterize.spin2 |
| `getLastCMD13Capture` | 0 | - | SD_diag_cmd13_capture.spin2 |
| `getLastCMD18Result` | 0 | - | SD_diag_cmd13_capture.spin2 |

### A.11 Debug getters & sampling controls

| Method | Regression call sites | Suites | Non-test consumers |
|---|---:|---|---|
| `debugGetRootSec` | 9 | file_ops, error_injection, multiblock | SD_root_sector_raw_survey.spin2, SD_zero_root_sector_probe.spin2 |
| `debugGetFatSec` | 5 | file_ops, error_injection | - |
| `debugGetReadSectorDiag` | 2 | file_ops, error_injection | SD_la_streamer_diag.spin2, SD_audit_repro.spin2 |
| `debugGetReadSectorDiagExt` | 1 | file_ops | - |
| `debugGetSecPerFat` | 1 | file_ops | - |
| `debugGetVbrSec` | 1 | file_ops | - |
| `debugReadSectorSlow` | 1 | file_ops | SD_macca_diagnostic.spin2, SD_streamer_speed_test.spin2 (+3 more) |
| `debugDumpRootDir` | 0 | - | - |
| `debugEraseBlock` | 0 | - | SD_macca_diagnostic.spin2, SD_macca_diagnostic_v4.spin2 |
| `debugGetCurrentHp` | 0 | - | SD_tempcog_repro.spin2, SD_macca_diagnostic.spin2, SD_phase_sweep_test.spin2 |
| `debugGetDirSec` | 0 | - | - |
| `debugGetEffectiveAlignDelay` | 0 | - | SD_tempcog_repro.spin2 |
| `debugGetEffectiveSampleMode` | 0 | - | - |
| `debugSetAlignDelayOffset` | 0 | - | SD_macca_diagnostic.spin2, SD_phase_sweep_test.spin2, SD_macca_diagnostic_v3.spin2 |
| `debugSetPreEdgeThreshold` | 0 | - | - |
| `debugSetSampleMode` | 0 | - | SD_macca_diagnostic.spin2, SD_phase_sweep_test.spin2, SD_macca_diagnostic_v3.spin2 |
| `debugZeroRootSector` | 0 | - | SD_zero_root_sector_probe.spin2 |
| `displayEntry` | 0 | - | - |
| `displayFAT` | 0 | - | - |
| `displaySector` | 0 | - | - |

**Summary:** 136 public methods total; 109 have at least one regression call site; 27 have zero.

## Appendix B: Error Code Coverage (37 codes)

| Code | Value | Referenced by suites | Class |
|---|---:|---|---|
| `E_TIMEOUT` | -1 | error_handling, multihandle | covered |
| `E_NO_RESPONSE` | -2 | - | hardware-fault only (needs bad/absent card) |
| `E_BAD_RESPONSE` | -3 | - | hardware-fault only (needs bad/absent card) |
| `E_CRC_ERROR` | -4 | error_injection | covered |
| `E_WRITE_REJECTED` | -5 | error_injection | covered |
| `E_CARD_BUSY` | -6 | - | hardware-fault only (needs bad/absent card) |
| `E_IO_ERROR` | -7 | crc_validation, error_injection, recovery | covered |
| `E_NO_CARD` | -8 | - | hardware-fault only (needs bad/absent card) |
| `E_BAD_PIN_CONFIG` | -9 | mount | covered |
| `E_NOT_MOUNTED` | -20 | mount | covered |
| `E_INIT_FAILED` | -21 | - | hardware-fault only (needs bad/absent card) |
| `E_NOT_FAT32` | -22 | - | provokable via raw-sector corruption + remount (gap) |
| `E_BAD_SECTOR_SIZE` | -23 | - | provokable via raw-sector corruption + remount (gap) |
| `E_BAD_FSINFO` | -24 | - | provokable via raw-sector corruption + remount (gap) |
| `E_BAD_CHAIN` | -25 | error_injection | covered |
| `E_STACK_OVERFLOW` | -26 | - | infrastructure exhaustion (hard to provoke safely) |
| `E_FILE_NOT_FOUND` | -40 | defrag, file_ops, dirhandle, error_handling, error_injection, multiblock, subdir_ops | covered |
| `E_FILE_EXISTS` | -41 | directory, error_handling, file_ops, error_injection, multihandle | covered |
| `E_NOT_A_FILE` | -42 | file_ops | covered |
| `E_NOT_A_DIR` | -43 | directory, error_handling, dirhandle | covered |
| `E_DIR_NOT_EMPTY` | -44 | file_ops, mount | covered |
| `E_FILE_NOT_OPEN` | -45 | error_handling | reserved (never produced; referenced by error_handling only) |
| `E_END_OF_FILE` | -46 | error_handling | covered |
| `E_FILE_OPEN` | -47 | file_ops | covered |
| `E_DISK_FULL` | -60 | error_injection, volume | covered |
| `E_NO_CONTIGUOUS_SPACE` | -61 | defrag | covered |
| `E_FILE_OPEN_FOR_COMPACT` | -62 | defrag | covered |
| `E_VERIFY_FAILED` | -63 | - | provokable via injection during compactFile (gap) |
| `E_NO_LOCK` | -64 | - | infrastructure exhaustion (hard to provoke safely) |
| `E_NO_COG` | -65 | - | infrastructure exhaustion (hard to provoke safely) |
| `E_TOO_MANY_FILES` | -90 | dirhandle, multihandle | covered |
| `E_INVALID_HANDLE` | -91 | error_handling, multihandle, seek, multicog | covered |
| `E_FILE_ALREADY_OPEN` | -92 | error_handling, multihandle | covered |
| `E_NOT_A_DIR_HANDLE` | -93 | dirhandle, error_handling | covered |
| `E_INVALID_PARAM` | -94 | - | provokable directly (setDate with bad args) (gap) |
| `E_ASYNC_BUSY` | -95 | async | covered |
| `E_NO_ASYNC_OP` | -96 | async | covered |

## Appendix C: Conditional-Compilation Matrix (27 suites)

| Suite | Flags |
|---|---|
| async | SD_INCLUDE_ALL, SD_INCLUDE_ASYNC |
| cogcwd | SD_INCLUDE_ALL |
| crc_diag | SD_INCLUDE_DEBUG |
| crc_validation | SD_INCLUDE_ALL |
| defrag | SD_INCLUDE_DEBUG, SD_INCLUDE_DEFRAG, SD_INCLUDE_TEST_HOOKS |
| directory | SD_INCLUDE_STACK_CHECK |
| dirhandle | NONE(core-only) |
| error_handling | SD_INCLUDE_DEBUG, SD_INCLUDE_RAW |
| error_injection | SD_INCLUDE_ALL |
| fatchain | SD_INCLUDE_RAW |
| fifo | NONE(core-only) |
| file_ops | SD_INCLUDE_DEBUG, SD_INCLUDE_RAW, SD_INCLUDE_STACK_CHECK |
| format | SD_INCLUDE_ALL, SD_INCLUDE_STACK_CHECK |
| mount | SD_INCLUDE_DEBUG, SD_INCLUDE_RAW, SD_INCLUDE_STACK_CHECK |
| multiblock | SD_INCLUDE_ALL, SD_INCLUDE_STACK_CHECK |
| multicog | NONE(core-only) |
| multihandle | NONE(core-only) |
| raw_sector | SD_INCLUDE_ALL, SD_INCLUDE_STACK_CHECK |
| read_write | SD_INCLUDE_RAW, SD_INCLUDE_STACK_CHECK |
| recovery | SD_INCLUDE_ALL |
| register | SD_INCLUDE_RAW, SD_INCLUDE_REGISTERS, SD_INCLUDE_SPEED |
| seek | NONE(core-only) |
| speed | SD_INCLUDE_REGISTERS, SD_INCLUDE_SPEED |
| stress | SD_INCLUDE_ALL |
| subdir_ops | SD_INCLUDE_DEBUG, SD_INCLUDE_RAW |
| timestamp | SD_INCLUDE_ALL |
| volume | SD_INCLUDE_DEBUG, SD_INCLUDE_RAW, SD_INCLUDE_REGISTERS, SD_INCLUDE_TEST_HOOKS |

| Flag | Suites enabling it |
|---|---:|
| `SD_INCLUDE_ALL` | 10 |
| `SD_INCLUDE_RAW` | 8 |
| `SD_INCLUDE_DEBUG` | 7 |
| `SD_INCLUDE_REGISTERS` | 3 |
| `SD_INCLUDE_SPEED` | 2 |
| `SD_INCLUDE_ASYNC` | 1 |
| `SD_INCLUDE_DEFRAG` | 1 |
| `SD_INCLUDE_TEST_HOOKS` | 2 |
| `SD_INCLUDE_STACK_CHECK` | 7 |
| NONE (core-only) | 5 |

## Appendix D: Test Counts by Suite

| Suite | Framework `startTest` count |
|---|---:|
| crc_diag | 14 |
| fifo | 21 |
| crc_validation | 6 |
| defrag | 12 |
| dirhandle | 25 |
| error_handling | 19 |
| directory | 30 |
| fatchain | 2 |
| cogcwd | 5 |
| error_injection | 35 |
| file_ops | 29 |
| register | 10 |
| multicog | 15 |
| multiblock | 0* |
| speed | 15 |
| read_write | 49 |
| recovery | 7 |
| raw_sector | 0* |
| multihandle | 22 |
| seek | 38 |
| mount | 31 |
| stress | 4 |
| async | 7 |
| format | 54 |
| timestamp | 6 |
| volume | 31 |
| subdir_ops | 18 |
| **Total (framework-counted)** | **505** |

`*` multiblock (6 tests) and raw_sector (~14 tests) use a local recordPass/recordFail idiom instead of the framework's startTest; their tests are counted by their own banners, not by the framework. Those two suites add roughly 20 more tests beyond the framework-counted total above.
