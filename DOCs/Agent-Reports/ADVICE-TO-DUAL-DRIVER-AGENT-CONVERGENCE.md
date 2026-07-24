# Advice to the Dual-Driver Agent — Standalone ↔ Dual Convergence

**From:** the standalone SD FAT32 driver (`src/micro_sd_fat32_fs.spin2`), write-path
corruption sprint, v1.5.4.
**To:** the agent maintaining the dual DFS driver (DFS v1.3.2 / SD sub-driver v1.5.2,
per `HANDOFF-SD-WRITE-PATH-PORT-TO-STANDALONE.md`).
**Date:** 2026-07-24
**Purpose:** The two drivers share the Bug A (FAT-chain truncation on cross-boundary
overwrite) and Bug B (mid-sector zero-fill) fixes but have drifted in house style,
feature set, and version. This enumerates every divergence found while landing the
standalone fix, each anchored to a real `file:line`, so the two codebases can
reconverge deliberately rather than by accident.

The standalone fix is described in `DOCs/Plans/WRITE-PATH-CORRUPTION-FIX-SPRINT-PLAN.md`
§5.1 / §5.2; this doc is the outward-facing convergence record.

---

## Terminology

- **Standalone** = this repo's `src/micro_sd_fat32_fs.spin2` (a single-purpose SD
  FAT32 driver). All bare `file:line` references below are to this file at v1.5.4
  (post-fix).
- **Dual** = the DFS driver that embeds an SD sub-driver, described in the handoff.
  References to it cite the handoff by line, since its source is not in this repo.

---

## Divergence 1 — the handoff's model of the standalone is factually stale

`HANDOFF-...-PORT-TO-STANDALONE.md` §2/§3 describes a standalone that does not match
this file. Two concrete errors:

- **Claim (handoff:95–96):** "No named constants. It uses literals: `511` (not
  `SECTOR_MASK`), … `<< 2` (FAT entry shift). Keep using literals."
  **Reality:** the standalone uses **named constants** — `SECTOR_OFFSET_MASK`
  (`:254`) and `SECTOR_SHIFT` (`:253`) — throughout, e.g. the read-path chain follow
  at `:3768`.
- **Claim (handoff:97–98):** "EOC compare is signed: `do_read_h` uses
  `if next_cluster >= $0FFF_FFF8`."
  **Reality:** the standalone's `do_read_h` uses the **unsigned** compare
  `if next_cluster +>= FAT32_EOC_MIN` (`:3770`-area, constant at `:272`) — the same
  unsigned form the dual driver uses. There is no signed EOC compare to match.

Additional stale-model tells: the handoff's line map (`do_read_h` at 1650–1659,
`do_write` at 2163, `allocateCluster` at 4505) matches **none** of this file's
actual locations (`do_read_h` ≈ `:3730`, `allocateCluster` ≈ `:4990`, and there is
no `do_write` at all — see Divergence 5). The handoff was evidently written against
an older or different snapshot.

**Convergence action:** update the handoff/reference notes so the standalone is
described as *named-constant + unsigned `+>=`* — it already agrees with the dual
driver on signedness; only the constant **names** differ (Divergence 2).

---

## Divergence 2 — different names for identical concepts

The two drivers express the same quantities with different identifiers. This is the
main reason code cannot be pasted verbatim between them.

| Concept | Standalone (this file) | Dual (handoff:191) |
|---|---|---|
| Byte offset within a sector (`& 511`) | `SECTOR_OFFSET_MASK` (`:254`) | `SECTOR_MASK` |
| Byte↔sector shift (`<< 9` / `>> 9`) | `SECTOR_SHIFT` (`:253`) | `SECTOR_BITS` |
| Cluster→FAT-entry byte shift (`<< 2`) | bare literal `<< 2` (`:3842`, `:3768`) | `FAT_ENTRY_SHIFT` |

Note the standalone is *itself* inconsistent: it names the sector mask/shift but
leaves the FAT-entry shift as a bare `<< 2`. The dual driver names all three.

**Convergence action:** pick one vocabulary. The dual driver's `FAT_ENTRY_SHIFT` is
the better of the two for the FAT-entry shift; the standalone's `SECTOR_OFFSET_MASK`
is more descriptive than `SECTOR_MASK`. Whichever is chosen, apply it in both files
so a future shared-fix port is a straight copy.

---

## Divergence 3 — DEFRAG pre-allocation feature

The handoff (`:153`) assumes "the standalone has no DEFRAG pre-alloc branch, so
`new_cluster` likely becomes unused."

**Reality:** the standalone **has** the pre-allocation feature, gated by
`#ifdef SD_INCLUDE_DEFRAG`:

- `h_prealloc_end` per-handle field declared at `:756`;
- set by `do_create_contiguous` at `:5282` (after `allocateContiguousChain`);
- cleared by `do_close_h` at `:3716`;
- consumed by the two write-path boundary fast-paths at `:3907` and `:3993`.

Consequently `new_cluster` in `do_write_h` is **still live** (used by the prealloc
branch) and must not be deleted — a divergence from the handoff's "likely unused"
guidance. In a core build (`SD_INCLUDE_DEFRAG` off) it is unused but harmless; the
driver compiles clean both ways.

**Convergence action:** confirm whether the dual driver carries the same prealloc
fast-path. If it does, verify it reaches the same immunity conclusion as
Divergence 4 below; if it does not, that is a genuine feature gap to record.

---

## Divergence 4 — §5e finding: the prealloc fast-path is immune to Bug A

Answered in writing (plan §5.1). The prealloc branch advances `h_cluster + 1`
without reading the FAT. This is safe **by construction**, and can execute even
during an in-place cross-boundary overwrite:

- `allocateContiguousChain(new_first, cluster_count)` writes the sequential FAT
  links for the whole reserved run *before* any write, so for those clusters
  `FAT[N] == N+1`;
- `h_prealloc_end` is set only at `do_create_contiguous:5282` and cleared at
  `do_close_h:3716` (array inits to 0 at `:756`), so only contiguous files take the
  branch;
- therefore `h_cluster + 1` **is** the cluster the FAT chain names — the fast path
  *follows* the same link `writeAdvanceCluster` would, and never calls
  `allocateCluster`. Bug A is structurally impossible on it.

One pre-existing asymmetry to leave alone: past `h_prealloc_end` the branch reports
"Pre-allocated space exhausted" and returns partial rather than growing — that is
the documented contiguous-file contract, not Bug A.

**Convergence action:** if the dual driver shares the prealloc branch, adopt this
same written immunity argument rather than re-deriving it.

---

## Divergence 5 — §5f finding: no legacy `do_write` in the standalone

The handoff (`:80–86`) warns that the driver "still has a V2 non-handle
`PRI do_write(...)` at 2163" and requires the agent to assess whether it performs
in-place cross-boundary overwrites.

**Reality:** this standalone has **no** legacy `do_write`. `do_write_h` (`:3859`) is
the **sole** file-data write path:

- one caller — the worker dispatch at `:2832` (`CMD_WRITE_H`);
- both public entry points funnel there — `writeHandle` (`:998`, blocking) and
  `startWriteHandle` (`:1367`, async, same `pb_cmd := CMD_WRITE_H`);
- `do_open_write` (`:3531`) only opens; the remaining `PUB *write*` methods are
  raw-sector (`writeSectorRaw:1683`, `writeSectorsRaw:1718`), which bypass the
  filesystem entirely.

The other `allocateCluster` callers are directory-extend / new-chain and are
append/grow-only, so none can weaponize Bug A. The standalone is therefore *already*
in the consolidated state the handoff describes the dual driver as having reached —
there is no legacy path to port the fix into.

**Convergence action:** the "assess the legacy `do_write`" step in the handoff does
not apply to this file; mark it resolved (no legacy path).

---

## Divergence 6 — version numbering drift

The handoff (`:19`, `:361`) frames the port as mirroring the dual driver's
**DFS 1.3.1 → 1.3.2 / SD 1.5.1 → 1.5.2** bump, implying the standalone was at 1.5.1
heading to 1.5.2.

**Reality:** the standalone tree was at **v1.5.3** (see the `v1.5.3:` change markers
at `:6112`, `:6287`, `:6387`) when this sprint began, and the write-path fix ships
as **v1.5.4**. The two drivers' version lines are independent and already out of
step by two minor revisions on the SD side.

**Convergence action:** do not assume shared version numbers. When citing "the SD
sub-driver version," qualify which driver — the standalone's SD version (1.5.4) is
not the dual's SD sub-driver version (1.5.2).

---

## The shared fix (for reference)

Both drivers implement the same three corrections; the standalone's form (plan §5.2):

1. **`writeAdvanceCluster(handle)`** (`:3822`) — follow the existing FAT link on
   overwrite; `allocateCluster` only when the current cluster is `+>= FAT32_EOC_MIN`.
   Both boundary sites (`:3918`, `:4003`) call it instead of allocating
   unconditionally. (Bug A)
2. **Metadata-region guard** (`:3927`) — refuse any write to a sector `< root_sec`,
   returning partial `bytes_written`. Correct-by-construction backstop.
3. **Mid-sector load predicate** (`:3948`) —
   `(h_position & !SECTOR_OFFSET_MASK) < h_size` loads the existing sector when its
   first byte is in-file, preserving leading bytes on a mid-sector append. (Bug B)

If the dual driver's fix differs in any of these three, that difference is the next
convergence item to reconcile.
