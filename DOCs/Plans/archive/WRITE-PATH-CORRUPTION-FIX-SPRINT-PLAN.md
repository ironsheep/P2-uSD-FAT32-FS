# Write-Path Corruption Fix — Sprint Plan

> **CLOSED 2026-07-25.** All commitments shipped; certified on two cluster
> geometries. Audit and carryovers:
> `DOCs/Plans/archive/2026-07-25-Write-Path-Corruption-Fix-Sprint-Closeout.md`.
> Shipped as **v1.6.0**, not the v1.5.4 this document says throughout — the
> untagged range carried new features, so SemVer called for a minor bump. The
> version text below was deliberately left as authored.

**Target:** `src/micro_sd_fat32_fs.spin2` (standalone SD FAT32 driver)
**Ships as:** **v1.5.4** (patch bump; current git tag `v1.5.3`)
**Source of record:** `DOCs/Agent-Reports/HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md`
**Authored:** 2026-07-23

---

## Purpose

Port two certified write-path corruption fixes from the dual-mode driver into
this standalone driver, and do it under the handoff's **detect-before-fix /
confirm-after-fix** discipline: build a regression suite that *fails on the
current driver*, prove it fails, apply the fix, prove it passes, then run the
full regression on two card geometries. Alongside the fix, upgrade the test
harness so every suite establishes its own preconditions and the full regression
runs head-to-tail without a human reformatting the card mid-run. Finally, feed
the single↔dual divergences back to the dual-driver agent so the two drivers
reconverge.

Both defects live only in `do_write_h`; both cause real data loss. Confirmed
present in our tree (verified 2026-07-23):

- **Bug A — FAT-chain truncation on cross-boundary overwrite (CRITICAL).**
  `do_write_h` calls `allocateCluster(h_cluster[handle])` **unconditionally** at
  both cluster-boundary advance sites (`micro_sd_fat32_fs.spin2:3870` and
  `:3948`). `allocateCluster` re-links the passed cluster forward
  (`:5021`), so an in-place overwrite of a multi-cluster file that crosses a
  boundary rewrites a live FAT link → truncates the chain → orphans the tail →
  user data lands on FAT/VBR → whole-volume corruption. The read/seek paths
  already follow the chain correctly (`:3759`, `:3802`, `:4009`); only the write
  producer is wrong.
- **Bug B — mid-sector write zero-fills leading bytes.** `do_write_h` chooses
  load-vs-zero-fill by file position at `:3894` (`if h_position[handle] <
  h_size[handle]`); an append/overwrite starting mid-sector zero-fills the
  sector and wipes existing bytes before the write point.

**Issue C** (the `send_command`/`WAITATN` concurrency item) is explicitly out of
scope per the handoff — it was a dual-driver worker-cog concern.

---

## Divergences from the handoff's assumptions (already established)

The handoff was written against a read-only reference baseline, not this shipped
tree. Confirmed differences that shape the port:

1. **We use named constants, not literals.** `SECTOR_OFFSET_MASK` (511),
   `SECTOR_SHIFT` (9), `SECTOR_SIZE` (512), `FAT32_EOC_MIN` (`$0FFF_FFF8`),
   `BUF_FAT`/`BUF_DATA` are all defined and used in `do_read_h`. New code mirrors
   **this file's** idiom — do **not** import literals per handoff §3.
2. **Our EOC compare is unsigned `+>=`**, not signed `>=` (`do_read_h:3760`,
   `:3803`). `writeAdvanceCluster` uses `+>=` to match.
3. **We have a `SD_INCLUDE_DEFRAG` prealloc branch** (defaulted on) at both
   boundary-advance sites (`:3859-3876`, `:3938-3954`). The handoff assumed none.
   The fix goes in the **non-prealloc `else` branch only**; the prealloc path is
   assessed separately (see §5).
4. **`freeSpace()` takes no device arg** and **`sectorsPerCluster()` is a direct
   DAT read** (not worker-routed). The §4.5a two-routed-calls hazard is milder
   here, but the local-first idiom is applied regardless (§2).
5. **Version is git-tag based** (`v1.5.3`), shipping **v1.5.4** — the handoff's
   1.5.1→1.5.2 numbering is stale for us.

These, plus anything found during execution, are the content of the
dual-driver advice doc (§8c).

---

## Entry baseline

- **Build:** clean — all 24 regression suites compile, 0 fail
  (`cd tools && ./run_regression.sh --compile-only`, run 2026-07-23).
- **Tests (hardware):** not yet measured this sprint; per the zero-tolerance
  overlay the suite is expected 100% green. Stephen runs the entry hardware
  baseline at sprint start (`sprint-start` invokes `baseline-health`).

## Sprint-start record (2026-07-23)

- **Build number:** ships as **v1.5.4** (git tag; current `v1.5.3`).
- **Branch:** `sprint/write-path-corruption-fix` (cut from `main`).
- **Working-tree audit (Stephen's decisions):**
  - Diagnostic `DEBUG_MASK` edits in `SD_RT_mount_tests` / `SD_RT_raw_sector_tests`
    are **intentional** (tests may carry non-zero masks; driver stays
    `DEBUG_MASK=0`) — committed as-is (`83a220b`).
  - Handoff + this plan committed as sprint foundation (`c3528d7`).
  - Housekeeping (SDSC analysis + 11 `diagnostic-tests/` repros) committed
    (`de443b4`). `diagnostic-tests/` does not ship.
  - `.claude/` is gitignored — skill-conventions/overlays/marker are local-only,
    left as-is by decision.
- **Tracking-readiness (entry):** READY — 0 tasks, 0 context keys, `MEMORY.md`
  10 lines. Nothing to prune.
- **Baseline-health (entry):** build clean (24/24 compile). Hardware test
  baseline is host-side, established by Stephen at execution.

---

## 1. Driver introspection helper — `clusterBytes()`

**Why:** The fatchain test must place a write exactly on a cluster boundary and
size fixtures to cluster geometry at run time; it needs bytes-per-cluster.

**Current state:** `sectorsPerCluster()` exists (`:1207`, direct read of
`sec_per_clus`, returns 0 unmounted). No `clusterBytes()`.

**Target:** Add a `PUB clusterBytes() : n` returning `sec_per_clus <<
SECTOR_SHIFT`, returning **0 when not mounted** (mirror `sectorsPerCluster`'s
gating so the test can detect an unmounted card instead of dividing by a garbage
size). Named-constant idiom (`SECTOR_SHIFT`), not `<< 9`.

**Integration:** Public API; used by §3. No worker round-trip (DAT read).

**Verification:** normal — returns 512×spc on a mounted volume of each geometry;
edge — returns 0 before mount / after unmount; error — n/a (pure accessor).

---

## 2. Shared test helpers — `assertFreeSpace`, `clustersForBytes`

**Why:** The fatchain suite gates on available free space and converts byte sizes
to cluster counts. These are reusable across future capacity-gated suites, so
they belong in the shared framework, not baked into one test.

**Current state (`src/regression-tests/isp_rt_utilities.spin2`):** has
`evaluateSubBool` (`:168`), `evaluateSubValue`, `fillBufferWithValue`,
`verifyBufferValue`, `startTestGroup`, `ShowTestEndCounts`. **Missing:**
`assertFreeSpace`, `clustersForBytes`.

**Target:** Add both to `isp_rt_utilities.spin2`, applying the **local-first
idiom** (handoff §4.5a) — never chain two worker-routed driver calls in one
Spin2 expression:

```spin2
' WRONG:  freeClusters := sd.freeSpace() / sd.sectorsPerCluster()
' RIGHT:
freeSectors  := sd.freeSpace()          ' each query resolves on its own line
spc          := sd.sectorsPerCluster()
freeClusters := freeSectors / spc
```

`assertFreeSpace(needClusters)` returns TRUE only when the mounted volume has at
least `needClusters` free; `clustersForBytes(nBytes)` rounds up
`nBytes / clusterBytes()` with each driver query resolved to its own local first.

**Integration:** OBJ handle to `sd` must be reachable from the util; if the util
cannot see the driver instance, the helper takes the needed geometry as
parameters and the suite passes them in. Confirm the util's existing access
pattern during implementation.

**Verification:** normal — gate passes on a card with room, converts sizes
correctly for 4 KB and 8 KB clusters; edge — `clustersForBytes(0)` = 0, exact
multiple vs. +1 byte; error — returns FALSE / 0 when unmounted (freeSpace/​
clusterBytes return 0) rather than reporting a false pass.

---

## 3. New suite — `SD_RT_fatchain_tests.spin2`

**Why:** This is the test that must *fail on the current driver and pass after
the fix*. It is the certification evidence for Bug A + Bug B.

**Current state:** does not exist. We do not have the DFS reference source on
this machine; the suite is authored from the handoff's behavioral spec (§5) using
our API names.

**Target — two groups, geometry-agnostic (sizes derived from `clusterBytes()`):**

- **Group A — cross-boundary overwrite follows the FAT chain.** Build a
  **3-cluster** file with a distinct verifiable pattern per cluster. Close,
  reopen for write, and overwrite **only the first two clusters** in place. Close,
  reopen for read, read the whole file back. **Assert the untouched 3rd cluster
  still holds its original pattern** and the full-file read does not short-read at
  a premature EOC. On the buggy driver the tail is orphaned → short read / wrong
  tail. **Do not simplify to a full overwrite** — a full overwrite passes on the
  buggy driver because the reader follows the rewritten-but-consistent chain.
- **Group B — mid-sector append preserves leading bytes.** Create a 100-byte
  file, close, reopen for write, seek to end (position == size, mid-sector),
  append 50 bytes. Read back and **assert the original 100 leading bytes are
  intact** (not zero-filled). Group B rolls up to a **single** `evaluateSubBool`
  result (handoff §4.5b.2 — do not mix `evaluateSubValue` with a full
  `evaluateBool` under one `startTest`, which produced bad test counts in the
  dual driver).

**Preconditions the suite establishes itself (ties to §4):** mount + verify
geometry; delete any stale fixture files before creating them; gate on
`assertFreeSpace(clustersForBytes(3 × clusterBytes()) + margin)` and, if not met,
report **SETUP NOT MET explicitly** (never silently skip); on exit, delete its
fixtures, `unmount()`, and emit the `END_SESSION` marker + driver stop so the
sequential runner cannot hang (handoff §4.5b.1).

**Integration:** OBJ = `micro_sd_fat32_fs` + `isp_rt_utilities`;
`#pragma exportdef SD_INCLUDE_RAW` (matches sibling suites needing VBR/geometry).
Wire into `tools/run_regression.sh` in the file-I/O layer, immediately after
`SD_RT_read_write_tests.spin2` (it is a write-path correctness test and should
run once basic read/write is proven).

**Verification:** this suite *is* verification; its own pass/fail is the gate.
Normal — both groups PASS on the fixed driver, both geometries. Edge — cluster
boundary lands exactly at 512-byte sector boundary. Error — SETUP NOT MET path
prints and does not report green.

---

## 4. Harness precondition audit (all suites)

**Why:** A test that inherits card state from a prior suite is order-dependent
(the handoff demands order-independence) and can pass on a buggy driver by luck.
Distinct from the §6 Step-0 capacity-gate skip: that is "the test never ran";
this is "the test ran against the wrong starting conditions." Stephen flagged
this as a first-class workstream.

**Current state:** suites vary. Some self-clean (e.g.
`SD_RT_error_handling_tests` deletes fixtures at start and end, `:101-106`,
`:376`); coverage across all 24 is unaudited.

**Target:** Audit every suite in `src/regression-tests/` against four criteria:
1. verifies mount succeeded and geometry is sane before asserting;
2. creates/cleans its own fixtures rather than assuming a pristine card;
3. asserts sufficient free space / correct geometry *before* the body when it
   depends on them;
4. leaves the card clean enough that the next suite's preconditions hold
   (order-independence).

Produce a findings table (suite × four criteria), fix the suites that fail a
criterion (add mount checks, pre-delete fixtures, add capacity gates, add
teardown). The more suites self-establish and self-clean, the fewer reformats §6
must inject.

**Integration:** feeds §6 (self-cleaning suites reduce forced reformats) and the
order-independence proof in §7.

**Verification:** normal — every suite passes its four criteria; the full
sequential run is order-independent (spot-check with a shuffled / `--from` start,
§7). Edge — a suite run in isolation (fresh card) and mid-sequence (residue) both
pass. Error — a suite that legitimately needs a clean card documents that and
triggers the §6 reformat rather than silently depending on it.

**Note:** the audit procedure (sweep suites for precondition establishment) is
not covered by a current skill — logged as a skill-evolution candidate (§ Exit).

### 4.1 Findings table (audit completed 2026-07-23)

All 26 files in `src/regression-tests/` audited (25 in the `run_regression.sh`
order plus the opt-in `SD_RT_format_tests`). Legend: **P** pass · **F** fail ·
**n/a** criterion does not apply to this suite.

| # | Suite | C1 mount/geometry | C2 own fixtures | C3 capacity/geometry gate | C4 leaves card clean |
|---|---|---|---|---|---|
| 1 | mount | P `:137-138` | P `:278`,`:298`,`:303` / `:316-319` | n/a | P `:327` |
| 2 | raw_sector | P `:106-109` | n/a (raw) | **F** — writes LBA 100 000-100 004, no `cardSizeSectors()` gate | **F** — no `stop()`; leaves 5 scratch sectors, undocumented |
| 3 | multiblock | P `:101-104` | n/a (raw) | **F** — writes LBA 200 000-200 113, needs ≥102 MB card, ungated | **F** — never unmounts (`:155`) |
| 4 | register | P `:77-80`, `:151-155` | n/a | n/a | P `:196` |
| 5 | speed | P `:87-90` | P `:107-108` / `:290-291` | n/a (2×512 B) | P `:293` |
| 6 | crc_diag | P `:81-84` | P `:102-103` / `:287-288` | n/a (512 B) | P `:290` |
| 7 | error_handling | P `:91-94` | P `:101-106` / `:368-373` — **reference pattern** | n/a | P `:376` |
| 8 | crc_validation | P `:83-86` | P `:101-102` / `:269-270` | n/a | P `:272` |
| 9 | recovery | P `:91-94`, `:264-265` | P `:108-111` / `:357-360` | n/a (~2 KB) | P `:362` |
| 10 | file_ops | P `:91-94` | P `:151-154` / `:533-536` | n/a | **F** — `debugClearRootDir()` `:109` (see 4.2) |
| 11 | read_write | P `:102-105` | P (inline pre-delete per fixture) | **F** — ~384 KB live (128 KB + 256 KB coexist `:562`-`:715`), no gate; `readVBRRaw` result unchecked `:795` → garbage `secPerClus` | P `:866-870` |
| 12 | fatchain | P `:94-97` | P `:123`,`:191` / `:179`,`:216` | P `:104-115` gate | P `:221` |
| 13 | multihandle | P `:76-79` | P `:88` / `:525` | n/a | P `:527` |
| 14 | seek | P `:60-63` | P `:72`,`:356` / `:374`,`:381` | n/a (2 KB) | P `:384` |
| 15 | volume | P `:110-113` | **F** — `cleanupTestFiles` `:664-674` omits `DF00`-`DF29`, `DFTEST.BIN`, `DFVERFY.BIN`, `VLFLUSH.TXT` | n/a (uses `setTestMaxClusters`) | **F** — same omission; aborted run leaks fixtures + altered volume label |
| 16 | subdir_ops | P `:85-88` | P `:157`,`:194-195` / `:392-397` | n/a | **F** — `debugClearRootDir()` `:97` (see 4.2) |
| 17 | directory | P `:92-95` | **F** — `cleanupTestItems` `:566-588` omits `DEEP1`-`DEEP5`, `DEEP.TXT`, `RTMANY`, `12345678.123`, `STALE`, `STPOLL.TXT` | **F** — 32 KB polluter write `:445-446` ungated | **F** — same omission |
| 18 | dirhandle | P `:84-87` | P `:96` / `:474` | n/a | P `:476` |
| 19 | fifo | n/a (no SD) | n/a | n/a | n/a |
| 20 | multicog | P `:113-119` | P `:450-452` / `:282` | n/a | P `:285` |
| 21 | cogcwd | P `:118-121` | P `:576` / `:144` | n/a | P `:146` |
| 22 | timestamp | P `:67-70` | P `:73-74` / `:88-89` | n/a | P `:91` |
| 23 | stress | P `:112-115` | P `:511-512` / `:137` | **F** — 5 KB + 3 KB ungated; `createStressFiles` `:516-518` returns early on failure, so all four tests fail confusingly instead of reporting SETUP NOT MET | P `:139` |
| 24 | async | P `:80-83` | P `:432` / `:115` | n/a | P `:117` |
| 25 | defrag | P `:86-89` | P `:99` / `:346` | **F** — Test 3 and Test 5 each write ~192 KB (3 × `FILL_WRITES`×`WRITE_SIZE`), no free-space gate | P `:348` |
| 26 | format (opt-in) | P `:98`,`:105-108`,`:410` | n/a (formats card) | **F** — header requires ≥64 MB; `cardSizeSectors()` read `:110` but only printed, never asserted | P `:428` (fresh FAT32) |

**Score:** 17 of 26 clean on all applicable criteria. 9 suites fail at least one
criterion: `raw_sector`, `multiblock`, `file_ops`, `read_write`, `volume`,
`subdir_ops`, `directory`, `stress`, `defrag`, `format`.

### 4.2 Headline finding — `debugClearRootDir()` leaks FAT clusters

`SD_RT_file_ops_tests.spin2:109` and `SD_RT_subdir_ops_tests.spin2:97` both call
`sd.debugClearRootDir()` unconditionally at start-up as a "clear corrupted root"
workaround. The driver implementation (`micro_sd_fat32_fs.spin2:2736-2743`)
zero-fills **only `root_sec`** — the first sector of the root directory — and
frees **no FAT clusters**:

```
CMD_DEBUG_CLEAR_ROOT:
  bytefill(@buf, 0, SECTOR_SIZE)
  if writeSector(root_sec, BUF_DATA) == SUCCESS
    dir_sec_in_buf := -1
    pb_status := SUCCESS
```

Two consequences, both directly relevant to this sprint:

1. **Permanent free-space leak.** Every root entry it erases keeps its cluster
   chain marked allocated in the FAT with nothing referencing it. Free space
   drops a little on every regression run and never comes back — which is a
   sufficient explanation on its own for the card progressively filling up and
   needing a manual reformat, independent of Bug A.
2. **Cross-suite destruction.** It deletes whatever another suite left in the
   first root sector, so it both depends on and damages global card state — the
   exact order-dependence criterion 4 exists to prevent.

It is also incomplete as a repair: it clears one sector, so entries living in the
second and later root sectors survive untouched.

**Remediation:** remove both call sites. Neither suite needs it — both already
pre-delete their own fixtures. Keep the driver API itself (it is a
`SD_INCLUDE_DEBUG` recovery tool), but no regression suite may call it.

### 4.3 Remediation list (risk-ordered)

1. **`file_ops:107-110`, `subdir_ops:95-98`** — remove the `debugClearRootDir()`
   calls (§4.2). Highest risk: silent, cumulative, card-wide.
2. **`directory`** — extend `cleanupTestItems()` to cover `DEEP1`-`DEEP5` (+
   `DEEP.TXT`), `RTMANY` (+ `12345678.123`), `STALE`, `STPOLL.TXT`, so an aborted
   run cannot poison the next one's `newDirectory()` assertions.
3. **`volume`** — extend `cleanupTestFiles()` to cover `DF00`-`DF29`,
   `DFTEST.BIN`, `DFVERFY.BIN`, `VLFLUSH.TXT`.
4. **`read_write`** — add a `clusterBytes()`/`freeSpace()` capacity gate for the
   ~384 KB peak, and check the `readVBRRaw()` result at `:795` (prefer the
   driver's `sectorsPerCluster()` / `clusterBytes()` over hand-parsing the VBR).
5. **`defrag`** — add a capacity gate ahead of the ~192 KB fragmentation builds.
6. **`stress`** — add a capacity gate and make `createStressFiles()` failure
   report SETUP NOT MET instead of cascading into four opaque failures.
7. **`raw_sector`, `multiblock`** — gate the scratch LBA range on
   `cardSizeSectors()`; document the range as scratch; give `multiblock` an
   `unmount()`.
8. **`format`** — assert the ≥64 MB card-size precondition it already reads.

Gates use the §2 helpers (`clustersForBytes`, `assertFreeSpace`) and the §1
`clusterBytes()`, with the fatchain suite's local-first idiom (`:104-115`) as the
model, so a card that is genuinely too small reports SETUP NOT MET rather than
failing opaquely.

---

## 5. Driver fix — `do_write_h` follow-or-allocate + guards

**Why:** The core corruption fix (Bug A + Bug B).

**Current code:** `do_write_h` at `:3812`; boundary-advance site 1 at
`:3858-3876`, site 2 at `:3936-3954`; Bug B predicate at `:3894`; `allocateCluster`
relink at `:5021`; `do_read_h` follow idiom to mirror at `:3751-3765` / `:3795-3808`.

**Target:**

**5a. Add `PRI writeAdvanceCluster(handle)`** mirroring **this file's**
`do_read_h` boundary idiom — named constants, unsigned `+>=`, `FAT32_EOC_MIN`,
`BUF_FAT`, `clus2sec`. On an in-place overwrite the current cluster already links
forward → FOLLOW it; allocate a fresh cluster only when the current cluster is
truly EOC:

```spin2
PRI writeAdvanceCluster(handle) : ok | cluster, fat_addr, next_cluster, new_cluster
  cluster := h_cluster[handle]
  if readSector(cluster >> 7 + fat_sec, BUF_FAT) < 0
    return false
  fat_addr := @fat_buf + ((cluster << 2) & SECTOR_OFFSET_MASK)
  next_cluster := LONG[fat_addr]
  if next_cluster +>= FAT32_EOC_MIN                      ' truly end-of-chain -> grow
    new_cluster := allocateCluster(cluster)
    if new_cluster < 0
      return false
    h_cluster[handle] := new_cluster
    h_sector[handle]  := clus2sec(new_cluster)
  else                                                  ' already linked -> FOLLOW
    h_cluster[handle] := next_cluster
    h_sector[handle]  := clus2sec(next_cluster)
  return true
```

**5b. Replace the unconditional `allocateCluster` in the non-prealloc `else`
branch** at both sites, preserving the `#ifdef SD_INCLUDE_DEFRAG` prealloc fast
path unchanged:
- Site 1 (`:3870`) → `if not writeAdvanceCluster(handle): count := 0`
- Site 2 (`:3948`) → `if not writeAdvanceCluster(handle): quit` (returns
  `bytes_written` so far)

**5c. Add the `root_sec` data-region write guard** at the top of the
`repeat while count > 0` loop (~`:3879`): if `h_sector[handle] < root_sec`, emit
the `REFUSING metadata-region write` debug line and `return bytes_written` (the
partial count so far, not 0). Correct-by-construction backstop; must never fire
in a passing run (§7 invariant).

**5d. Fix Bug B predicate** at `:3894` from `if h_position[handle] <
h_size[handle]` to load-when-the-sector's-first-byte-is-in-file:
```spin2
if (h_position[handle] & !SECTOR_OFFSET_MASK) < h_size[handle]
```
(`!` is this file's bitwise-NOT idiom, already used for `h_flags &= !HF_DIRTY`.)

**5e. DEFRAG prealloc assessment (answer in writing before ship).** The prealloc
branch advances `h_cluster + 1` assuming physical contiguity. Determine whether
that path can execute during an **in-place cross-boundary overwrite** (vs. only
during contiguous *growth* when `h_prealloc_end > 0`). If it can overwrite across
a boundary, it needs the same follow-vs-allocate correction; if it is
growth-only, document why it is immune. Do not ship until answered.

**5f. Legacy write-path immunity (answer in writing).** There is no legacy
non-handle `do_write` in this driver — `do_write_h` is the only file-data write
path (verified: the other `allocateCluster` callers at `:3617`, `:3627`, `:4280`,
`:4310`, `:4313`, `:5232` are directory-extend / new-chain, all append/grow-only).
Record this immunity finding formally (handoff §2 discipline).

**Integration:** producer/consumer inventory confirms **no consumer change** —
read (`:3759`, `:3802`), seek (`:4009`) already follow chains correctly. Remove
now-unused locals from `do_write_h` only if truly unused (the DEFRAG branch keeps
`new_cluster` live — confirm before deleting).

**Verification:** normal — §3 Group A/B PASS. Edge — file whose length is an exact
multiple of cluster size; overwrite that ends exactly on a boundary; single-cluster
file (no boundary crossing). Error — `allocateCluster` failure at a genuine EOC
grow returns partial `bytes_written`, not corruption; FAT read failure surfaces
`false`/partial, never a silent wrong-link. Invariant — `root_sec` guard never
fires in a passing run.

### 5.1 Pre-analysis (container, 2026-07-23) — read-only, no driver edit

Done ahead of the fix because it needs no hardware; **no driver line was
changed** (the edit must follow the §7 DETECT run). Confirm on re-read at fix time.

**Line numbers have shifted** from the §5 text above (the plan warned they would):
`do_write_h` now at `:3822`; boundary-advance **site 1 at `:3880`** (was `:3870`),
**site 2 at `:3958`** (was `:3948`); Bug B predicate at **`:3904`** (was `:3894`);
top of `repeat while count > 0` at **`:3889`**.

**§5e — DEFRAG prealloc path is immune. Answer: it CAN run during an in-place
cross-boundary overwrite, and it is still correct, by construction.**
`h_prealloc_end` is written in exactly one place, `do_create_contiguous:5282`,
after `allocateContiguousChain(new_first, cluster_count)` (`:5216`) has **already
written the FAT links** for the whole reserved run — so for those clusters
`FAT[N] == N+1`. It is cleared at `do_close_h:3716`, and the DAT array
(`:756`) initialises to 0, so every handle from `openFileWrite`/`createFileNew`
takes the normal path. Within one open a caller *can* seek back and overwrite
across a boundary; the prealloc branch then advances to `h_cluster + 1`, which is
**the same cluster the FAT chain names** — it follows rather than allocates, so it
cannot orphan a tail and never calls `allocateCluster`. Bug A is therefore
structurally impossible on that branch, and it needs no correction. One
pre-existing asymmetry to leave alone: past `h_prealloc_end` the branch reports
"Pre-allocated space exhausted" and returns partial instead of growing — that is
the documented contiguous-file contract, not Bug A.

**§5f — confirmed: `do_write_h` is the only file-data write path.** It has exactly
one caller, the worker dispatch at `:2832` (`CMD_WRITE_H`). Both public entry
points funnel there — `writeHandle:998` (blocking) and `startWriteHandle:1367`
(async, same `pb_cmd := CMD_WRITE_H`). No legacy non-handle `do_write` exists;
`do_open_write:3531` only opens. The remaining `PUB *write*` methods are raw-sector
(`writeSectorRaw:1683`, `writeSectorsRaw:1718`) which bypass the filesystem
entirely, plus diagnostics/getters. The other `allocateCluster` callers remain
directory-extend / new-chain (append-only) as recorded in §5f.

### 5.2 Implemented (2026-07-24) — driver fix landed, compile-verified

Applied to `src/micro_sd_fat32_fs.spin2` after the DETECT gate proved red
(`DOCs/Agent-Reports/BASELINE-DETECT-RUN-2026-07-23.md`: fatchain 0/2, 25/26 green).

- **5a — `PRI writeAdvanceCluster(handle)`** added immediately before `do_write_h`
  (now `:3822`). Mirrors `do_read_h`'s chain-follow idiom verbatim
  (`readSector(cluster >> 7 + fat_sec, BUF_FAT)`, `fat_addr := @fat_buf +
  ((cluster << 2) & SECTOR_OFFSET_MASK)`, `next_cluster +>= FAT32_EOC_MIN`).
  EOC → `allocateCluster(cluster)` (grow); else FOLLOW the link. Returns
  `false` on FAT-read or alloc failure.
- **5b — both boundary-advance sites** now call
  `if not writeAdvanceCluster(handle)` in the non-prealloc `else` branch — site 1
  (`:3918`) sets `count := 0`; site 2 (`:4003`) does `quit`. The
  `#ifdef SD_INCLUDE_DEFRAG` prealloc fast paths are unchanged.
- **5c — `root_sec` data-region guard** at the top of `repeat while count > 0`
  (`:3927`): `if h_sector[handle] < root_sec` → debug `REFUSING metadata-region
  write` + `quit` (returns partial `bytes_written`, never metadata corruption).
- **5d — Bug B predicate** at `:3948` is now
  `if (h_position[handle] & !SECTOR_OFFSET_MASK) < h_size[handle]` — loads the
  existing sector when its first byte is in-file, so a mid-sector append keeps
  the leading bytes.
- **Locals:** `new_cluster` kept — still live in the DEFRAG prealloc branch.
  No consumer change (read/seek already follow chains).

**Compile-verified both conditional paths:** `--compile-only --include-format`
→ 26/26 suites + reformat vehicle (DEFRAG on via `SD_INCLUDE_ALL`); a throwaway
core-only consumer with **no** `SD_INCLUDE_*` (DEFRAG off, `new_cluster` unused,
prealloc branch elided) → clean 32 KB build. `writeAdvanceCluster` and both new
call sites are outside any `#ifdef`, so they compile identically on both paths.

**Behavioral PASS still owed by the hardware CONFIRM gate (§7 Step 2 / task «#8»):**
reformat the DETECT card, rerun `SD_RT_fatchain_tests`, expect 2/2, then the
full two-geometry regression — all other suites must stay green.

---

## 6. Runner upgrade — head-to-tail regression with in-run reformat

**Why:** The fatchain DETECT run corrupts the card on the buggy driver, and some
suites need a known clean baseline. Today a human must reformat and resume with
`--from` mid-run. Since authorizing a regression run authorizes formatting the
card (project policy), the runner should establish a clean baseline and reformat
around destructive suites as a normal part of the run.

**Current state (`tools/run_regression.sh`):** runs 23 suites (+ optional
`--include-format`) in dependency order, stop-on-first-failure, per-file
reporting, `--from` resume. Format is destructive and opt-in only; no in-run
reformat.

**Target:** Within a regression run, treat the card as scratch by default:
auto-establish a clean FAT32 baseline and reformat around the destructive suites
(fatchain DETECT, corruption-recovery) so the full run goes end-to-end unattended
and leaves the card mountable. Guard: this destructive behavior lives in the
**regression runner only** — it must not leak into single-suite `run_test.sh` or
fire outside a regression context. Leverage §4 (self-cleaning suites) so forced
reformats are the backstop for genuinely destructive cases, not routine.

**Integration:** uses the driver's format capability (the `--include-format`
path already exercises `SD_RT_format_tests`); §7 depends on this for the
two-geometry head-to-tail runs.

**Verification:** normal — a full run with no manual intervention completes and
leaves a mountable card. Edge — resume via `--from` still works; a run that hits
a real failure still stops-on-first-failure and reports. Error — reformat failure
is surfaced loudly, not swallowed; single-suite `run_test.sh` is unaffected.

### 6.1 Implemented (2026-07-23) — `tools/run_regression.sh`

**Reformat vehicle:** `src/UTILS/SD_format_card.spin2` — already non-interactive,
prints `FORMAT SUCCESSFUL` / `FORMAT FAILED` and `END_SESSION`, honours
`-D SD_PINS_EXTERNAL`. Launched through the *unmodified* `run_test.sh`
(300 s timeout), so the destructive logic lives entirely in the regression runner.

**Policy (hardware runs, default on):**
- baseline reformat before the first suite — including on a `--from` resume,
  since §4 made the suites self-establishing;
- `REFORMAT_BEFORE` = `SD_RT_fatchain_tests` (needs a known free-space baseline
  for its capacity gate);
- `REFORMAT_AFTER` = `SD_RT_fatchain_tests` (on the unfixed driver its writes
  damage FAT/VBR — Bug A), `SD_RT_format_tests` (leaves its own label/geometry);
- de-duplicated by a `CARD_IS_FRESH` flag, so a `--from fatchain` resume formats
  once, not twice.

**Deliberate non-behavior — no auto-reformat after a suite FAILURE.** The §7
DETECT step needs the post-failure on-card damage as evidence; wiping it would
destroy the proof. The runner instead reports "card left as-is … when done:
`./run_regression.sh --reformat-only`".

**New flags:** `--no-reformat` (preserve card contents), `--reformat-only`
(reformat and exit — the recovery path; mutually exclusive with `--compile-only`).

**Reformat success is verified, not assumed:** a clean `run_test.sh` exit is not
enough — the runner re-reads the format log (stripping pnut-term-ts per-line
timestamps first, since they split words mid-line) and requires the literal
`FORMAT SUCCESSFUL` marker. Failure prints a red block naming the phase and log
path, then aborts the run (exit 1) rather than continuing on an unknown card.

**Other integration:** Phase 1b compiles the reformat vehicle up front (fail fast
rather than halfway through a hardware run) and reports it on its own line, so the
26/26 suite compile count is unchanged; the summary table gained a
`card reformats (N)` time row; the banner prints the card policy in effect.

**Verified without hardware:** `--compile-only --include-format` → 26/26 plus the
vehicle; `bash -n` clean; and a stubbed-hardware simulation (fake `run_test.sh` in
a scratch tree) exercised full run, `--from` resume + de-dup, suite failure
(no after-reformat, hint shown), mid-run reformat failure (summary + ABORTED),
clean-exit-but-failed-format detection, `--no-reformat` (zero formats),
`--reformat-only`, and the `--reformat-only --compile-only` rejection.
`git diff tools/run_test.sh` is empty — the guard holds.

### 6.2 Implemented (2026-07-24) — true end-to-end, single invocation

6.1 removed the *card-state* reasons a sweep needed babysitting. The CONFIRM run
then exposed the remaining ones: Card 2's sweep stopped at suite 26 on a **serial
download checksum error** — the binary never reached the P2, the suite never
executed, and 25 green suites were thrown away needing a manual `--from` resume.
This closes that gap.

**Continue-on-failure is now the default.** A failing suite is recorded and the
sweep continues to the end; the summary lists every failed suite with its log
path. `--stop-on-failure` restores the old halt-and-preserve-evidence behavior
for DETECT-style forensic runs. In continue mode a failing *destructive* suite IS
reformatted after, so one failure cannot cascade into every later suite.

**Infrastructure failures are separated from test results.** `run_test.sh` exit 2
(download/serial) means the suite never ran — retried once automatically, and if
it fails twice reported as `INFRA` in its own summary section, never counted as a
driver failure. Exit 3 (timeout) is deliberately NOT retried: a hang can be a real
defect and must not be papered over.

**Preflight + closing audit.** Before anything writes to the card,
`SD_card_identify` records which card is in the socket (capacity, geometry, SN,
warnings) directly into the transcript — the cert report no longer needs
hand-transcription — and a read-only `SD_FAT32_audit` captures the card's incoming
state. Incoming-audit failure is informational (the baseline reformat is about to
fix it); identify failure is fatal (no card, no run). After the last suite the
audit runs again and **must pass** — the run's own proof that the sweep leaves the
card healthy. `--no-preflight` skips both.

**`--log <file>`** tees the whole transcript, so the sweep can be launched in the
background and polled instead of chunked. This matters for agent-driven runs: a
full sweep is ~600 s, at or past a foreground command's ceiling, which is what
forced the chunk-and-resume pattern in the first place.

**Verified without hardware:** `--compile-only --include-format` → 26/26 plus all
three vehicles (format, identify, audit); `bash -n` clean; log-parse functions
replayed against real archived `SD_FAT32_audit_*` and `SD_card_identify_*` logs
(39/39 parsed, L1/L2/L3 extracted cleanly); and a stubbed-hardware simulation
covering all-pass end-to-end, mid-run suite failure (continues, exit 1, failures
listed), persistent INFRA (continues, own section, exit 1), transient flake
(retried once, run stays green, exit 0), `--stop-on-failure` (halts, preserves,
skips closing audit), closing-audit failure (hard blocker, exit 1), `--log` tee,
and `--no-preflight`. `git diff tools/run_test.sh` is still empty.

---

## 7. Certification protocol — detect → confirm → full regression (hardware)

**Why:** The handoff's §6 is the whole point: a test that looks green but never
ran, or that passes on the buggy driver, is worthless. This is a verification
workstream Stephen executes on the P2 host; the container cannot run it.

**Target — steps in order (each captured as evidence):**
- **Step 0 — prove the test runs.** Build §3 against the **current unfixed**
  driver; confirm Group A/B **execute** (no "SETUP NOT MET" on a card with room).
  A green run that skipped the body is a false green.
- **Step 1 — DETECT.** Run §3 on the unfixed driver; **expect FAIL** (Group A
  tail orphaned / short read; Group B leading bytes zeroed). Capture output; run
  the SD audit to show on-disk FAT/VBR damage as corroborating evidence. Reformat
  before Step 2.
- **Step 2 — CONFIRM.** Apply §5, reformat the **same** card, rerun §3; **expect
  PASS** (both groups). Record the A/B (old-FAIL → fixed-PASS) pair — that
  transition on one card is the certification evidence. A fatchain FAIL on the
  fixed driver is a live bug: fix in-session and rerun; do not ship on it.

  > **RETIRED as a separate step (2026-07-24).** Do NOT run fatchain standalone
  > before the sweep. `run_regression.sh` lists `SD_RT_fatchain_tests` in
  > `REFORMAT_BEFORE`, so suite 12 already gets a freshly formatted card — the
  > exact condition a solo run was providing. Running it twice bought nothing but
  > an extra manual step, and it is what made CONFIRM a two-invocation procedure.
  > The A/B pair is captured in `DOCs/Agent-Reports/CONFIRM-RUN-2026-07-24.md`;
  > from here fatchain is certified inline as suite 12 of the single sweep. For an
  > ad-hoc fast signal use `./run_regression.sh --from fatchain`.
- **Step 3 — full regression, both geometries.** Run the complete sequential
  suite, per-file reported, on **two cards of different cluster geometry**
  (small-cluster vs large-cluster — Bug A only triggers at certain cluster
  sizes). Both must be deterministic, green, and order-independent (spot-check
  with a shuffled / `--from` start). Reference: dual driver certified 1,347/0 on
  each of an SD16G (8 KB clusters) and an 8 GB card (4 KB clusters).
- **Step 4 — invariants.** `root_sec` guard never fires in a passing run; any
  SETUP-NOT-MET is investigated (capacity/geometry limit documented, or harness
  gap fixed); **any card corruption on the fixed driver is a hard blocker.**

**Verification:** the A/B pair exists and is recorded; both geometries green and
order-independent; invariants hold.

---

## 8. Documentation deliverables

**8a. CHANGELOG / release notes (`CHANGELOG.md`).** Add the **v1.5.4** section
per `DOCs/procedures/changelog-style-guide.md` (terse, additive, ≤25 words/entry).
Bug-Fixes entries for Bug A (FAT-chain truncation on cross-boundary overwrite) and
Bug B (mid-sector zero-fill), plus a Field-Reports/validation note citing the A/B
certification and both geometries.

**8b. Behavioral spec update (`DOCs/SD-CARD-DRIVER-THEORY.md`).** Update the
write-path / FAT-chain section to document the follow-or-allocate semantics on
cross-boundary overwrite, the `root_sec` metadata-region guard, and the
mid-sector load-vs-zero-fill rule. Where the theory doc and code disagree, code
is authoritative — record any correction.

**8c. Dual-driver advice doc
(`DOCs/Agent-Reports/ADVICE-TO-DUAL-DRIVER-AGENT-CONVERGENCE.md`).** New
deliverable. Capture every single↔dual divergence found (see "Divergences"
above + anything surfaced in execution):
1. handoff §3 is factually stale about the standalone (claims literals + signed
   `>=`; we use named constants + unsigned `+>=`);
2. constant-name divergence for identical concepts (`SECTOR_OFFSET_MASK` vs
   `SECTOR_MASK`, `SECTOR_SHIFT` vs `SECTOR_BITS`, bare `<< 2` vs
   `FAT_ENTRY_SHIFT`);
3. DEFRAG feature divergence (standalone has the prealloc branch the handoff says
   it lacks);
4. version-numbering drift (standalone at 1.5.3, handoff assumed 1.5.1→1.5.2);
5. the §5e/§5f findings (prealloc immunity, no legacy write path).

**Verification:** notes follow the changelog style guide; theory doc matches
shipped behavior; advice doc enumerates each divergence with a file:line anchor.

---

## 9. Release — v1.5.4

**Why:** Ship the certified fix.

**Target:** After §7 passes on both geometries and §8 is complete, cut **v1.5.4**
(git tag), following `DOCs/procedures/RELEASE-CHECKLIST.md`. Confirm
`release.yml` **enumerates the new `src/` tree files** (the new suite is under
`src/regression-tests/` — verify it is captured or intentionally excluded per the
release-notes scope) and that **`diagnostic-tests/` does not ship**.

**Verification:** normal — tag cut, CHANGELOG `[Unreleased]` empty, release bundle
contains the intended `src/` files and excludes `diagnostic-tests/`. Edge — the
new regression suite's ship/exclude status is deliberate, not accidental. Error —
release workflow dry-run surfaces any missing enumerated file before the tag.

---

## Section ↔ task cross-reference

Tasks tagged `write-path-fix`. **`seq` deliberately departs from plan-section
order** to enforce the handoff's detect-before-fix discipline: the DETECT run
(§7) and the harness/runner upgrades (§4, §6) execute *before* the driver fix
(§5), so the fatchain suite proves it catches the bug on the unfixed driver
before the fix exists.

| Plan § | Deliverable | Task | seq | Where |
| ------ | ----------- | ---- | --- | ----- |
| §1 | `clusterBytes()` helper | «#1» | 1 | container |
| §2 | shared helpers `assertFreeSpace`/`clustersForBytes` | «#2» | 2 | container |
| §3 | `SD_RT_fatchain_tests.spin2` + runner wiring | «#3» | 3 | container |
| §4 | harness precondition audit (24 suites) | «#4» | 4 | container |
| §6 | runner head-to-tail reformat infra | «#5» | 5 | container |
| §7 DETECT | reproduce bug on unfixed driver (capture FAIL) | «#6» | 6 | **hardware** |
| §5 | driver fix — `writeAdvanceCluster` + guards + Bug B | «#7» | 7 | container |
| §7 CONFIRM | confirm PASS + full regression, 2 geometries | «#8» | 8 | **hardware** |
| §8b+§8c | theory update + dual-driver advice doc | «#9» | 9 | container |
| §8a | CHANGELOG v1.5.4 | «#10» | 10 | container |
| §9 | release v1.5.4 | «#11» | 11 | container/host |

## Exit-gate notes

- **Code research:** complete. Both bug sites, the relink weapon, the read-path
  idiom, the helper inventory, the runner, the producer/consumer inventory, and
  the legacy-path resolution are all established with file:line citations. No
  blocking open questions remain.
- **Hardware dependency:** §7 (and the entry/exit hardware baselines) run on the
  macOS P2 host; the container performs all authoring and compile-checks
  (§1–§6, §8) and cannot execute the hardware gates.
- **Skill-evolution candidate:** the §4 harness precondition audit (sweep suites
  for precondition establishment) is a reusable procedure no current skill
  covers — appended to `feedback_skill_evolution_candidates.md` for retrospective
  triage.
