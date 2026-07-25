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

---

## Divergence 7 — utility output voicing (recreate this on your side)

Added 2026-07-25, after the v1.6.0 recert. This is not a driver change — it is a
change to what the **utilities print** — but it came out of a defect class we hit
five times in one sprint, so it is worth porting deliberately rather than
rediscovering.

### The problem

Four of five defects fixed in that sprint were the same shape: **a health check
that structurally could not report ill health.** The worst of them was the
read-only audit printing

```
  REPAIR: Synced 3 FAT sectors
  REPAIR: Freed 2 lost clusters
```

on a run that wrote nothing. The tool claimed actions it had not taken. A user
reading a log excerpt — or grepping one — would conclude the card had been
modified by a tool documented as read-only. That is corrosive to exactly the
guarantee the tool exists to provide.

A second, subtler error was in the audit's own banner:

```
*** AUDIT MODE: every REPAIR line below is hypothetical ***
```

The *findings* are not hypothetical. They are real problems on a real card. Only
the *repairs* are unapplied. Conflating the two teaches the reader to discount
genuine findings.

### The fix — one choke point, not per-site edits

`isp_fsck_utility.spin2` has 13 repair-reporting sites. Only one was mode-aware.
Rather than patch 13 strings, route them all through a single tag:

```spin2
DAT
tagRepair   BYTE    "repaired", 0
tagWould    BYTE    "needs repair", 0

PRI repairTag() : pStr
' Voice for every repair line: "repaired" when the fix was applied, "needs repair"
' on a read-only audit. Single choke point -- a new repair site gets the correct
' voice for free by formatting %s with this, exactly as doRepairWrite() is the
' single choke point that makes MODE_AUDIT's read-only guarantee structural.

    if dryRun
        pStr := @tagWould
    else
        pStr := @tagRepair
```

Every site then formats `%s` with it:

```spin2
fifo.putFmt2(@"  %s: %d lost clusters", repairTag(), v_lostCount)
```

This mirrors the architectural pattern that already makes read-only *structural*
rather than a matter of discipline: the whole file has exactly **one**
`sd.writeSectorRaw` call site, behind `if dryRun: return`. Same idea applied to
output. A repair site added later cannot get the voice wrong.

Note the formatter dependency: `%s` is supported by `isp_mem_strings`'
`sFormatStr*` and takes a pointer to a zero-terminated string. Confirm your
formatter does the same before porting.

### The messages name the PROBLEM, never the action

This is what makes one text work under both tags. Do not write imperative or
past-tense actions — write the finding:

| Don't | Do |
|---|---|
| `REPAIR: Synced %d FAT sectors` | `%s: %d FAT sectors out of sync with the backup` |
| `REPAIR: Freed %d lost clusters` | `%s: %d lost clusters` |
| `REPAIR: Truncated at cluster %d` | `%s: chain runs past the file size at cluster %d` |
| `REPAIR: Backup VBR mismatch - copying` | `%s: backup VBR out of sync with the primary` |
| `REPAIR: FSInfo free count %d -> %d` | `%s: FSInfo free count wrong (says %d, actually %d)` |
| `REPAIR: FAT[2] root cluster was free` | `%s: root cluster marked free` |

Both readings then land correctly:

```
  needs repair: 2 lost clusters        (audit -- found, not fixed)
  repaired: 2 lost clusters            (fsck  -- found and fixed)
```

### Machine-readable anchors are preserved verbatim

The regression runner gates on these; they are contract, not prose, and they did
**not** change:

```
=== AUDIT COMPLETE ===        === FSCK COMPLETE ===
Errors: %d  Repairs needed: %d
Errors: %d  Repairs: %d
Structural checks: %d pass, %d fail
STATUS: CLEAN | STATUS: REPAIRS NEEDED | STATUS: REPAIRED | STATUS: ERRORS REMAIN
```

The human sentence goes **above** the anchor, never in place of it:

```
Nothing was repaired -- run SD_FAT32_fsck to fix what is listed above.
STATUS: REPAIRS NEEDED
```

Keep both. Prose for the person, anchor for the machine.

### Header

```
Before:  === FAT32 Filesystem Audit (read-only -- no writes) ===
         *** AUDIT MODE: every REPAIR line below is hypothetical ***

After:   === FAT32 Filesystem Audit ===
         Read-only -- nothing on this card is changed.
```

### Two related fixes worth porting at the same time

1. **Log truncation at `END_SESSION`.** `pnut-term-ts` stops logging the instant
   it sees the end marker, so a status line emitted one or two `debug()` calls
   before it is truncated mid-word and never reaches the log. This silently
   dropped `STATUS:` from every audit log, and `FORMAT SUCCESSFUL` from every
   *successful* format — the latter forcing the regression runner to accept two
   different success markers as a workaround. Fix: `waitms(500)` before the final
   `debug("END_SESSION")`. Applied to `SD_FAT32_audit.spin2`,
   `SD_FAT32_fsck.spin2`, and `SD_format_card.spin2`.

2. **Internal identifiers leaking into user output.** Messages like
   `readCIDRaw FAILED`, `ERROR: readSectorsRaw returned -5`, and
   `MBR readSectorRaw status: -2` name driver internals a tool user never calls.
   Replaced with what the reader can act on: `Could not read the card ID
   register`, `ERROR: bulk read failed, status -5`, `MBR read status: -2`.

**Convergence action:** apply the same tag mechanism, problem-not-action message
voicing, anchor preservation, end-marker drain, and identifier cleanup to the dual
driver's utility set. If your utilities share source with ours, the diffs port
directly; if they diverged, the *rules* above are what matter, not the strings.
