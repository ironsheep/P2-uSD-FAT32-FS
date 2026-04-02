# Long File Name (LFN) Implementation Plan

**Status:** Not started
**Created:** 2026-02-26
**Updated:** 2026-03-30
**Scope:** Add VFAT Long File Name support to the P2-uSD-FAT32-FS driver

---

## Executive Summary

The driver currently supports only 8.3 short filenames. Files created by Windows, macOS, or Linux with names longer than 11 characters are invisible to our directory listings, and our create/delete/rename operations can corrupt LFN metadata already present on the card.

This plan adds full VFAT Long File Name support in five phases, progressing from safe read-only operations to full read/write/delete/rename. Each phase is independently testable and produces a working commit.

**Estimated scope:**
- ~1,200-1,500 lines of new driver code (+17-21% growth from current ~7,150 lines)
- ~950-1,200 lines of new regression test code (5 new test suites)
- ~150 lines of demo shell changes
- 5 phases

---

## Table of Contents

1. [Background: How LFN Works on Disk](#1-background-how-lfn-works-on-disk)
2. [Current Driver State](#2-current-driver-state)
3. [Phase 1: LFN Reading](#3-phase-1-lfn-reading)
4. [Phase 2: LFN File/Directory Creation](#4-phase-2-lfn-filedirectory-creation)
5. [Phase 3: LFN-Aware Deletion](#5-phase-3-lfn-aware-deletion)
6. [Phase 4: LFN-Aware Rename and Move](#6-phase-4-lfn-aware-rename-and-move)
7. [Phase 5: Polish and Edge Cases](#7-phase-5-polish-and-edge-cases)
8. [Regression Test Plan](#8-regression-test-plan)
9. [Demo Shell Changes](#9-demo-shell-changes)
10. [New Public API Surface](#10-new-public-api-surface)
11. [Memory and Performance Impact](#11-memory-and-performance-impact)
12. [Risks and Mitigations](#12-risks-and-mitigations)
13. [Conditional Compilation](#13-conditional-compilation)
14. [References](#14-references)

---

## 1. Background: How LFN Works on Disk

### 1.1 LFN Entry Structure

Each LFN entry is a standard 32-byte directory entry with attribute byte `$0F` so legacy systems ignore it. The 32 bytes are laid out as:

| Field | Offset | Size | Description |
|-------|--------|------|-------------|
| LDIR_Ord | 0x00 | 1 | Sequence: bits 0-5 = order (1-20), bit 6 = last-in-chain flag ($40) |
| LDIR_Name1 | 0x01 | 10 | Characters 0-4 as UTF-16LE (5 chars x 2 bytes) |
| LDIR_Attr | 0x0B | 1 | Must be $0F |
| LDIR_Type | 0x0C | 1 | Always $00 |
| LDIR_Chksum | 0x0D | 1 | Checksum of the corresponding 8.3 short name |
| LDIR_Name2 | 0x0E | 12 | Characters 5-10 as UTF-16LE (6 chars x 2 bytes) |
| LDIR_FstClusLO | 0x1A | 2 | Always $0000 |
| LDIR_Name3 | 0x1C | 4 | Characters 11-12 as UTF-16LE (2 chars x 2 bytes) |

Each entry holds **13 UTF-16LE characters**. Characters are split across three non-contiguous fields (Name1, Name2, Name3) because the attribute, type, checksum, and cluster fields must remain at their standard offsets so legacy systems see a valid (if nonsensical) entry.

### 1.2 On-Disk Layout

LFN entries are stored **immediately before** their corresponding 8.3 short name entry, in **reverse sequence order**:

```
Offset  Entry
0x000   LFN #3  (ord=$43, chars 26-38, last flag set)
0x020   LFN #2  (ord=$02, chars 13-25)
0x040   LFN #1  (ord=$01, chars 0-12)
0x060   SFN     (8.3 short name: "MYDOCU~1.TXT", attr=$20)
```

The highest-numbered LFN entry comes first on disk and has bit 6 set in LDIR_Ord (e.g., $43 = $40 | 3). The chain then counts down to sequence 1. The short name entry immediately follows.

### 1.3 Checksum Algorithm

All LFN entries in a chain share a checksum computed from the 11-byte 8.3 short name:

```
checksum := 0
repeat i from 0 to 10
    checksum := ((checksum >> 1) + ((checksum & 1) << 7) + short_name[i]) & $FF
```

This is a right-rotate-and-add over the 11 bytes of the short name (8 name + 3 extension, space-padded). If any LFN entry's checksum doesn't match, the chain is invalid and the long name is discarded.

### 1.4 Short Name Generation (Basis-Name + Numeric Tail)

When creating a file with a long name, a corresponding 8.3 "alias" must be generated. The spec (fatgen103) defines a two-stage algorithm:

**Stage 1 — Basis-Name Generation:**

1. Convert the UNICODE long name to uppercase
2. Convert to OEM character set. If any character has no OEM representation (code point > $7F) or is illegal in 8.3, replace with `_` (underscore) and set a **lossy conversion flag**
3. Strip **all** leading and embedded spaces (not just leading/trailing — `"My File"` becomes `"MYFILE"`)
4. Strip **all** leading periods (`"...hidden"` becomes `"HIDDEN"`)
5. Copy up to 8 characters of the base name (before the last period)
6. If the name has an extension (after the last period), copy up to 3 characters

**Stage 2 — Numeric Tail Generation:**

- If **no** lossy conversion occurred AND the name fits 8.3 AND no collision exists: use the basis-name directly (no `~N` tail)
- Otherwise: truncate base to 6 characters, append `~1`. On collision, increment: `~2`, `~3`, ... `~9`. Beyond `~9`, use 5-char base + `~10` through `~999999`

**Critical:** The generated short name must not collide with any name in the **unified namespace** (both short names and long names, case-insensitive).

Example: `"My Long Document.txt"` -> `"MYLONG~1.TXT"`
Example: `"README.TXT"` (no lossy conversion, fits 8.3, no collision) -> `"README  TXT"` (no tail)

### 1.5 Capacity

- Maximum long name: **255 UTF-16 characters**
- Maximum LFN entries per file: **20** (ceil(255/13))
- Maximum directory entries per file: **21** (20 LFN + 1 SFN = 672 bytes)
- Padding: after the last real character, one $0000 null terminator, then all remaining slots filled with $FFFF. **Exception:** if name length is an exact multiple of 13, no null and no $FFFF padding

### 1.6 Existing Documentation

The project already has an LFN reference in `DOCs/Reference/FAT32-API-CONCEPTS-REFERENCE.md` covering the entry structure, assembly algorithm, and attribute conventions.

---

## 2. Current Driver State

### 2.1 What Works Today

| Operation | 8.3 Names | Long Names | Notes |
|-----------|-----------|------------|-------|
| Mount card with LFN files | Yes | N/A | Mounts fine; LFN entries ignored |
| Directory listing | Yes | **No** | `do_read_dir_h()` skips attr=$0F entries (line 3853) |
| Search by name | Yes | **No** | `searchDirectory()` converts input to 8.3 (line 4482) |
| Create file | Yes | **No** | `do_newfile()` writes single 32-byte entry (line 3879) |
| Delete file | Yes | **Dangerous** | `do_delete()` marks only SFN entry $E5 (line 3996); **orphans LFN entries** |
| Rename file | Yes | **Dangerous** | `do_rename()` updates only SFN (line 4094); **creates checksum mismatch** |
| Move file | Yes | **Dangerous** | `do_movefile()` copies only SFN entry (line 4206); **orphans LFN entries** |
| Read file name | Yes | **No** | `fileName()` returns 8.3 format only (line 1331) |

### 2.2 Key Data Structures

**Current DAT section:**
```
dir_buf       BYTE    0[512]          ' Directory sector buffer
fat_buf       BYTE    0[512]          ' FAT sector buffer
buf           BYTE    0[512]          ' Data sector buffer
entry_buffer  dir_entry_t             ' Directory entry buffer (32 bytes)
vol_label     BYTE    0[12]           ' Volume label (11 chars + null)
```

**Per-handle state:** Tracks `h_flags`, `h_dir_offset`, `h_dir_sector`, `h_start_clus`, `h_size`, `h_position`, `h_sector`, `h_cluster`, `h_buf_sector`, and per-handle 512-byte buffers. Handle flags: `HF_FREE`=0, `HF_READ`=1, `HF_WRITE`=2, `HF_DIR`=4, `HF_DIRTY`=$80.

**Entry location tracking:**
- `entry_address` = `(sector << 9) | offset_in_sector` — byte-level address of the SFN entry found by `searchDirectory()`
- `entry_address & 511` extracts the offset within `dir_buf` for direct modification

### 2.3 Methods Requiring Changes

| Method | Line | What Changes |
|--------|------|-------------|
| `do_read_dir_h()` | 3783 | Collect LFN entries instead of skipping; assemble long name |
| `do_readdir()` | 4220 | Collect LFN entries instead of skipping |
| `searchDirectory()` | 4458 | Match against assembled LFN names, not just 8.3 |
| `fileName()` | 1331 | Return long name when available, 8.3 as fallback (Phase 5) |
| `do_newfile()` | 3879 | Write LFN entry chain + SFN entry |
| `do_newdir()` | 3909 | Write LFN entry chain + SFN entry for directories |
| `do_create()` | 3230 | Write LFN entry chain + SFN entry (handle-based create) |
| `do_delete()` | 3984 | Mark all LFN entries + SFN entry as $E5 |
| `do_rename()` | 4054 | Delete old chain, write new chain with updated name |
| `do_movefile()` | 4179 | Copy full LFN+SFN chain to destination, delete old chain |

### 2.4 Critical Invariant: entry_address

Throughout the driver, `entry_address` identifies the **SFN entry** location. For LFN support, we also need the **first LFN entry** location. The cleanest approach is to add new DAT variables:

```
lfn_first_address  LONG   0          ' Byte address of first LFN entry in chain (0 = no LFN)
lfn_entry_count    BYTE   0          ' Number of LFN entries preceding current SFN (0 = 8.3 only)
```

When `searchDirectory()` or `do_read_dir_h()` finds a file, both `entry_address` (SFN) and `lfn_first_address` (first LFN entry) are set. Delete, rename, and move operations use `lfn_first_address` to find the start of the chain.

---

## 3. Phase 1: LFN Reading

**Goal:** Read and display long filenames from cards formatted by Windows/macOS/Linux.

**Risk:** Low — read-only, no card modifications

### 3.1 New DAT Buffers

```spin2
' LFN assembly buffer
lfn_name_buf      BYTE    0[256]      ' Assembled long name (ASCII, null-terminated, max 255+1)
lfn_entries       BYTE    0[672]      ' Raw LFN entry storage (max 21 x 32 bytes)
lfn_entry_count   BYTE    0           ' Count of LFN entries collected (0 = 8.3 only)
lfn_first_address LONG    0           ' Byte address of first LFN entry in chain
lfn_valid         BYTE    0           ' TRUE if lfn_name_buf contains a valid assembled name
```

**Memory cost:** 256 + 672 + 1 + 4 + 1 = **934 bytes** in DAT section.

### 3.2 New Private Helper Methods

#### `lfn_checksum(p_short_name) : checksum` (~10 lines)

Compute the 8-bit checksum from an 11-byte 8.3 short name.

```spin2
PRI lfn_checksum(p_short_name) : checksum | i
    checksum := 0
    repeat i from 0 to 10
        checksum := ((checksum >> 1) + ((checksum & 1) << 7) + BYTE[p_short_name + i]) & $FF
```

#### `lfn_extract_chars(p_lfn_entry, p_out, p_count)` (~30 lines)

Extract up to 13 UTF-16LE characters from a single LFN entry's three name fields (offsets 1, 14, 28). Convert each UTF-16 code unit to ASCII (if the high byte is non-zero, substitute `_`). Write to `p_out` starting at position derived from the entry's sequence number.

Extraction offsets and character counts per field:
- Name1: offset 0x01, 5 characters (10 bytes)
- Name2: offset 0x0E, 6 characters (12 bytes)
- Name3: offset 0x1C, 2 characters (4 bytes)

Each UTF-16LE character is 2 bytes, low byte first. For ASCII range ($0000-$007F), take the low byte. For $0000, it's a null terminator. For $FFFF, it's padding (stop extracting).

#### `lfn_assemble(p_sfn_entry) : valid` (~60 lines)

After collecting LFN entries in `lfn_entries[]`, assemble the full name:
1. Compute expected checksum from the 8.3 name in `p_sfn_entry`
2. **Validate first collected entry** has LAST_LONG_ENTRY flag ($40) set in LDIR_Ord
3. **Validate sequence numbers** are monotonically decreasing: first collected = (N | $40), then N-1, N-2, ... down to 1. Per spec: "Values for LDIR_Ord must run from 1 to (n OR LAST_LONG_ENTRY). If they do not, the long entries are 'damaged' and are treated as orphans."
4. Verify each entry's checksum matches the expected value
5. Extract characters via `lfn_extract_chars()` into `lfn_name_buf`, processing entries from sequence 1 to N
6. Null-terminate at the first $0000 or end of entries
7. Set `lfn_valid := TRUE` on success, `FALSE` on any validation failure
8. On failure, clear `lfn_name_buf` — caller falls back to 8.3

### 3.3 Modify `do_read_dir_h()` (Line 3783)

**Current behavior (line 3853):** Skip LFN entries:
```spin2
if attrib == ATTR_LFN
    next
```

**New behavior:** Collect LFN entries, then assemble when SFN entry found:

```spin2
' Before the entry iteration loop begins, reset LFN state:
lfn_entry_count := 0
lfn_valid := FALSE

' New constant needed:
'   ATTR_LONG_NAME_MASK = $3F    (RO|HID|SYS|VOL|DIR|ARCHIVE)

' Inside the entry iteration loop, replace the LFN skip with:
' SPEC REQUIREMENT: Use masked check, not equality. Also check that byte 0 != $E5 (deleted).
if (attrib & ATTR_LONG_NAME_MASK) == ATTR_LFN and BYTE[p_hbuf + offset] <> DIR_ENTRY_DELETED
    ' Active LFN entry
    if lfn_entry_count < 21                                        ' guard against overflow
        bytemove(@lfn_entries + (lfn_entry_count * 32), p_hbuf + offset, 32)
        if lfn_entry_count == 0                                    ' first LFN entry seen (highest seq#)
            lfn_first_address := (h_sector[handle] << SECTOR_SHIFT) | offset
        lfn_entry_count++
    next
elseif BYTE[p_hbuf + offset] == DIR_ENTRY_DELETED
    ' Deleted entry breaks any in-progress LFN chain
    lfn_entry_count := 0
    next
else
    ' This is a normal entry (SFN). If we collected LFN entries, assemble them.
    if lfn_entry_count > 0
        lfn_valid := lfn_assemble(p_hbuf + offset)
    else
        lfn_valid := FALSE
        lfn_first_address := 0
    ' ... continue with existing entry_buffer copy and return
```

**Chain break rules:** Any non-LFN, non-SFN entry (deleted, volume label, etc.) between LFN entries and their SFN invalidates the chain. The `$E5` check on LDIR_Ord and the chain reset on deleted entries handle this.

### 3.4 Modify `do_readdir()` (Line 4220)

`do_readdir()` is a separate directory reading method used by the legacy API. It currently skips LFN entries implicitly (they have hidden/system/volume-id attributes). It needs the same LFN collection logic as `do_read_dir_h()`. The approach is identical: collect LFN entries, assemble on SFN entry.

### 3.5 Modify `searchDirectory()` (Line 4458)

**Critical spec requirement:** `searchDirectory()` must **always** collect LFN entries during its scan, regardless of whether the input name looks like an 8.3 name or a long name. This is required because:

1. A "long name search operation checks both the long and short directory entries" (fatgen103)
2. Even when searching by short name (e.g., `deleteFile(@"MYFILE.TXT")`), downstream operations (`do_delete()`, `do_rename()`, `do_movefile()`) need `lfn_first_address` and `lfn_entry_count` to properly handle any LFN entries that precede the matched SFN entry
3. Short and long names share a unified namespace — a search for `"readme.txt"` must match both an SFN `"README  TXT"` and an LFN `"readme.txt"`

**Modified scan algorithm:**

1. **Always collect:** During the directory scan loop, use the same masked LFN detection as `do_read_dir_h()` to collect LFN entries into `lfn_entries[]`. Reset collection on deleted entries.
2. **On each SFN entry:** If `lfn_entry_count > 0`, assemble the long name via `lfn_assemble()`. Then:
   - Compare the assembled long name case-insensitively against the input component
   - **Also** compare the 8.3 short name against the input (existing logic)
   - If either matches, set `bFound := TRUE` and populate both `entry_address` and `lfn_first_address`
3. **On SFN with no LFN chain:** Set `lfn_first_address := 0`, `lfn_entry_count := 0`. Compare 8.3 only (existing logic).
4. **Free entry tracking:** When looking for a free slot (for create), count consecutive free entries to find space for LFN chains (not just single entries).

**Implementation detail:** The comparison must be case-insensitive. Convert both the input and the assembled LFN to uppercase before comparing with `strcomp()`.

**Path components:** `searchDirectory()` processes path components separated by `/`. Each component is independently searched with both LFN and SFN matching. The path `/LongDirName/SHORT.TXT` would try LFN+SFN matching for both components.

### 3.6 New Public API Method

#### `longFileName() : p_name` (~5 lines)

```spin2
PUB longFileName() : p_name
'' Return pointer to the long filename of the most recently accessed entry.
'' Returns pointer to empty string if no LFN is present (use fileName() for 8.3 fallback).
    if lfn_valid
        p_name := @lfn_name_buf
    else
        p_name := @null_string          ' empty string, not null pointer
```

The demo shell and tests can call `longFileName()` first, and if it returns an empty string, fall back to `fileName()`.

### 3.7 Modify `fileName()` — Phase 1 Decision

**Option A (conservative, recommended for Phase 1):** Leave `fileName()` unchanged (line 1331). Add `longFileName()` separately. Caller decides which to use.

**Option B (transparent, deferred to Phase 5):** Modify `fileName()` to return the long name when available.

**Decision:** Option A for Phase 1 — no surprise behavior changes to existing callers.

### 3.8 Phase 1 Deliverables

- [ ] New DAT buffers: `lfn_name_buf`, `lfn_entries`, `lfn_entry_count`, `lfn_first_address`, `lfn_valid`
- [ ] New helpers: `lfn_checksum()`, `lfn_extract_chars()`, `lfn_assemble()`
- [ ] Modified: `do_read_dir_h()` (line 3783) — collect and assemble LFN entries
- [ ] Modified: `do_readdir()` (line 4220) — collect and assemble LFN entries
- [ ] Modified: `searchDirectory()` (line 4458) — match by LFN when input is long
- [ ] New API: `longFileName()`
- [ ] New test suite: `SD_RT_lfn_read_tests.spin2`
- [ ] Demo shell: `do_dir()` updated to show long names
- [ ] Verify: all 25 existing test suites still pass (444 tests, no behavior change for short names)

---

## 4. Phase 2: LFN File/Directory Creation

**Goal:** Create files and directories with long names, auto-generating 8.3 aliases.

**Risk:** Medium — writes directory entries, must produce valid on-disk structures

### 4.1 New Private Helper Methods

#### `lfn_generate_short_name(p_long_name, p_short_name_out, tail_number) : lossy` (~80 lines)

Generate an 8.3 alias from a long name, following the fatgen103 basis-name algorithm:

1. **Uppercase conversion:** Convert entire name to uppercase
2. **OEM conversion with lossy flag:** Replace any character > $7F with `_` and set `lossy := TRUE`. Also replace characters illegal in 8.3 (`+ , ; = [ ]` and control chars < $20, and `" * . / : < > ? \ |`) with `_` and set lossy flag
3. **Strip all leading and embedded spaces:** `"My File"` -> `"MYFILE"` (spec: "Strip all leading and embedded spaces")
4. **Strip all leading periods:** `"...hidden"` -> `"HIDDEN"` (spec: "Strip all leading periods")
5. **Split name and extension:** Find the **last** embedded period to separate base and extension. Copy up to 8 base characters, up to 3 extension characters
6. **Numeric tail (if needed):**
   - If `lossy == FALSE` and name fits 8.3 and `tail_number == 0`: use basis-name directly (no tail)
   - Otherwise: truncate base to `8 - len(tail_string)` characters, append `~N` where N = `tail_number`
   - `~1` through `~9` uses 6-char base; `~10` through `~99` uses 5-char base; up to `~999999`
7. **Space-pad:** Pad name to 8 and extension to 3 with spaces ($20)
8. **Return:** The 11-byte result in `p_short_name_out`; return `lossy` flag

**Collision loop (in caller):**
```
tail_number := 0
if lfn_needs_lfn(name)
    tail_number := 1
lossy := lfn_generate_short_name(name, @short_name, tail_number)
if lossy and tail_number == 0
    tail_number := 1
    lfn_generate_short_name(name, @short_name, tail_number)
repeat while shortNameExistsInDir(@short_name) or longNameExistsInDir(@short_name)
    tail_number++
    lfn_generate_short_name(name, @short_name, tail_number)
```

**Critical:** The collision check must search the **unified namespace** — both short names and long names (case-insensitive). Per spec: "no duplicate names can exist" across both namespaces.

#### `lfn_needs_lfn(p_name) : bool` (~15 lines)

Determine whether a filename requires LFN entries:
- Name portion > 8 characters? Yes
- Extension > 3 characters? Yes
- Contains lowercase? Yes
- Contains spaces? Yes
- Contains `+ , ; = [ ]`? Yes
- Multiple dots? Yes
- Leading dot? Yes
- Otherwise: No (pure 8.3 uppercase, no LFN entries needed)

#### `lfn_build_entries(p_long_name, p_short_name, p_lfn_buf) : entry_count` (~80 lines)

Build the chain of LFN directory entries in a buffer:

1. Compute checksum from `p_short_name` (11 bytes)
2. Calculate entry count: `ceil(strsize(p_long_name) / 13)`
3. For each entry (highest sequence number first in the buffer):
   - Set LDIR_Ord (sequence number, bit 6 on last)
   - Set LDIR_Attr = $0F
   - Set LDIR_Type = $00
   - Set LDIR_Chksum = checksum
   - Set LDIR_FstClusLO = $0000
   - Fill Name1, Name2, Name3 from the appropriate 13-char slice of the long name (as UTF-16LE: low byte = ASCII char, high byte = $00)
   - **Padding rule (fatgen103):** After the last real character, write one $0000 (null terminator), then fill all remaining character slots with $FFFF. **Exception:** if the name length is an exact multiple of 13, there is NO null terminator and NO $FFFF padding.
4. Return entry count

#### `findConsecutiveFreeEntries(count) : address` (~80 lines)

Search the current working directory's cluster chain for `count` consecutive free entries ($00 or $E5):

1. Start at `cog_dir_sec[pb_caller]`, iterate through directory sectors
2. For each 32-byte slot: check first byte for $00 (end-of-dir) or $E5 (deleted)
3. Track consecutive free slots; reset counter on any occupied entry
4. If a $00 (end-of-dir) entry is found, all remaining entries in that sector and subsequent sectors (up to cluster boundary) are also free
5. If `count` free entries found, return byte address of the first one
6. If directory cluster chain exhausted, **allocate a new cluster** and extend the chain:
   - Find a free cluster via `allocateCluster()`
   - Link it to the directory's chain
   - Zero-fill the new cluster (`clearCluster()` — all 0x00 entries = end-of-dir)
   - Return address of first entry in new cluster
7. If no cluster available, return `E_DISK_FULL`

**Critical note:** This is the most complex new method. It interacts with FAT allocation, directory cluster chains, and buffer coherence. Must be thoroughly tested, especially the sector-boundary and cluster-expansion cases.

#### `writeLfnChain(address, p_lfn_buf, entry_count)` (~40 lines)

Write a pre-built LFN entry chain to the directory at the given address:

1. For each of the `entry_count` entries:
   - Calculate the target sector and offset from the address
   - If sector differs from current `dir_buf`, flush and read new sector
   - Copy 32 bytes from `p_lfn_buf + (i * 32)` into `dir_buf` at the offset
   - Advance address by `DIR_ENTRY_SIZE`
2. Flush the final sector

This helper is reused by `do_newfile()`, `do_newdir()`, `do_create()`, and `do_rename()`.

### 4.2 Modify `do_newfile()` (Line 3879)

**Current flow:** `searchDirectory()` -> verify name doesn't exist -> set up `entry_buffer` -> `do_close()` writes entry.

**New flow:**

```
1. Receive name as input
2. If lfn_needs_lfn(name):
   a. lfn_generate_short_name(name, @short_name)
   b. Verify short name doesn't collide in directory (increment ~N if needed, max ~99)
   c. lfn_build_entries(name, @short_name, @lfn_entries) -> entry_count
   d. findConsecutiveFreeEntries(entry_count + 1) -> address
   e. writeLfnChain(address, @lfn_entries, entry_count)
   f. Set entry_address to the SFN entry location (address + entry_count * 32)
   g. Set lfn_first_address to the first LFN entry location
   h. Copy short_name into entry_buffer name field
   i. Continue with existing dirEntSet* calls
3. Else (pure 8.3 name):
   a. Existing logic (no change)
```

### 4.3 Modify `do_newdir()` (Line 3909)

Same pattern as `do_newfile()` — the only difference is the attribute byte ($10 for directory vs $20 for file) and the creation of `.` and `..` entries in the new directory's first cluster.

### 4.4 Modify `do_create()` (Line 3230)

`do_create()` is the handle-based file creation path (called by `createFileNew()` and `createFileContiguous()`). It needs the same LFN chain creation logic. Since `do_create()` and `do_newfile()` share significant code, consider extracting the LFN chain writing into the shared `writeLfnChain()` helper.

### 4.5 Phase 2 Deliverables

- [ ] New helpers: `lfn_generate_short_name()`, `lfn_needs_lfn()`, `lfn_build_entries()`, `findConsecutiveFreeEntries()`, `writeLfnChain()`
- [ ] Modified: `do_newfile()` (line 3879) — write LFN + SFN chain
- [ ] Modified: `do_newdir()` (line 3909) — write LFN + SFN chain
- [ ] Modified: `do_create()` (line 3230) — write LFN + SFN chain
- [ ] New test suite: `SD_RT_lfn_create_tests.spin2`
- [ ] Verify: files created by P2 are readable by Windows/macOS (cross-platform validation on host)
- [ ] Verify: all existing test suites still pass

---

## 5. Phase 3: LFN-Aware Deletion

**Goal:** When deleting a file, mark all LFN entries + SFN entry as deleted ($E5).

**Risk:** Medium — must not corrupt adjacent entries

### 5.1 The Problem Today

`do_delete()` at line 3996 marks only the SFN entry:
```spin2
dir_buf[entry_address & SECTOR_OFFSET_MASK] := DIR_ENTRY_DELETED
```

If the file had 3 LFN entries, those 3 entries are left intact with attr=$0F. This creates **orphaned LFN entries** that:
- Waste directory space
- May confuse other operating systems
- Could cause checksum mismatches if the space is reused

### 5.2 New Helper: `lfn_mark_chain_deleted(first_address, count)` (~40 lines)

Abstract the loop of marking LFN entries as deleted:

1. Calculate sector and offset for each entry
2. If sector differs from current `dir_buf` sector, flush current and read new sector
3. Set `dir_buf[offset] := $E5`
4. Track which sectors were modified
5. Flush all modified sectors at the end

**Sector boundary handling:** If LFN entries span two sectors (the chain crosses a 512-byte boundary), we need to write both sectors. This is the key complexity — the method must track when it crosses a sector boundary and flush before loading the next sector.

### 5.3 Modify `do_delete()` (Line 3984)

**New flow:**

After `searchDirectory()` locates the file (which now also sets `lfn_first_address` and `lfn_entry_count` from Phase 1):

```
1. If lfn_entry_count > 0:
   a. lfn_mark_chain_deleted(lfn_first_address, lfn_entry_count)
   b. Mark the SFN entry as $E5 (existing code)
2. Else:
   a. Existing code (mark only SFN as $E5)
3. Deallocate cluster chain (existing code, no change — freeClusterChain())
```

### 5.4 Phase 3 Deliverables

- [ ] New helper: `lfn_mark_chain_deleted()`
- [ ] Modified: `do_delete()` (line 3984) — delete entire LFN + SFN chain
- [ ] New test suite: `SD_RT_lfn_delete_tests.spin2`
- [ ] Verify: after deletion, no orphaned LFN entries remain (use raw sector reads to confirm)
- [ ] Verify: existing 8.3 delete tests still pass

---

## 6. Phase 4: LFN-Aware Rename and Move

**Goal:** Rename files with proper LFN chain management; support `moveFile()` with long names.

**Risk:** High — most complex phase; combines delete + create in one atomic operation

### 6.1 Rename: The Problem Today

`do_rename()` at line 4094 updates only the 8.3 name in the SFN entry:
```spin2
bytefill(p_buf, " ", SFN_TOTAL_LEN)
bytemove(p_buf, new_name, idx <# 12)
```

This leaves LFN entries pointing to the old name with a checksum that no longer matches the updated SFN. The result is a corrupted directory entry visible as garbled text in Windows.

### 6.2 Move: The Problem Today

`do_movefile()` at line 4206 copies only the 32-byte SFN entry to the destination directory:
```spin2
bytemove(@entry_buffer, @dir_buf + (bookmark & SECTOR_OFFSET_MASK), 32)
```

Then marks only the SFN entry as deleted in the source directory (line 4208). Any preceding LFN entries in the source are orphaned, and the moved file has no LFN entries in the destination.

### 6.3 Rename Strategy

Rename is effectively **delete old chain + create new chain**, preserving the file's cluster allocation, attributes, timestamps, and size:

```
1. searchDirectory(old_name) -> get SFN entry data + cluster chain info
2. Save: start_cluster, file_size, attributes, timestamps from entry_buffer
3. Delete old LFN + SFN chain (mark all as $E5 via lfn_mark_chain_deleted)
4. If lfn_needs_lfn(new_name):
   a. Generate new short name + LFN entries
   b. Find consecutive free entries (may reuse the ones we just freed)
   c. Write new LFN + SFN chain via writeLfnChain()
5. Else:
   a. Find one free entry
   b. Write new SFN entry
6. Restore saved cluster, size, attributes, timestamps to the new entry
```

**Atomicity concern:** If power is lost between step 3 (delete) and step 4 (create), the file's directory entry is gone but its cluster chain is still allocated. This is the same risk as any FAT32 rename (Windows has the same vulnerability). An FSCK pass would recover the lost clusters.

### 6.4 Modify `do_rename()` (Line 4054)

Replace the current in-place name update with the delete-and-recreate strategy. The method signature doesn't change (`old_name`, `new_name` -> `status`).

Key implementation details:
- Must save the entire `entry_buffer` (32 bytes) before deleting
- Must search in the same directory for the new name (collision check)
- Must restore timestamps and cluster pointers to the new entry after writing
- The `lfn_mark_chain_deleted()` from Phase 3 handles the old chain deletion

### 6.5 Modify `do_movefile()` (Line 4179)

`do_movefile()` moves a file between directories. The LFN chain management applies:

```
1. searchDirectory(name) -> get full entry data + LFN state
2. Save: entry_buffer, lfn_entries (if any), lfn_entry_count
3. Navigate to destination directory
4. If lfn_entry_count > 0:
   a. findConsecutiveFreeEntries(lfn_entry_count + 1) in destination
   b. writeLfnChain() + write SFN entry in destination
5. Else:
   a. do_newfile() in destination (existing logic)
6. Delete old LFN + SFN chain in source directory
```

The current code uses `do_newfile()` to create the entry in the destination, then copies the saved entry data over it. The LFN-aware version extends this to also write the saved LFN entries before the SFN entry.

### 6.6 Phase 4 Deliverables

- [ ] Modified: `do_rename()` (line 4054) — delete old chain, create new chain
- [ ] Modified: `do_movefile()` (line 4179) — LFN-aware move
- [ ] New test suite: `SD_RT_lfn_rename_tests.spin2`
- [ ] Verify: renamed/moved files readable by Windows/macOS
- [ ] Verify: existing 8.3 rename and move tests still pass

---

## 7. Phase 5: Polish and Edge Cases

**Goal:** Handle remaining edge cases, optimize, and finalize the API.

**Risk:** Low — refinements only

### 7.1 Items

1. **Transparent `fileName()` upgrade:** Modify `fileName()` (line 1331) to return the long name when `lfn_valid` is TRUE, falling back to 8.3. This makes all existing callers automatically see long names without code changes.

2. **Case-insensitive search refinement:** Ensure `searchDirectory()` matches long names case-insensitively (FAT32 spec requirement). Both the input and assembled LFN must be uppercased before comparison.

3. **Names that fit in 8.3 but have case:** Windows stores `"ReadMe.txt"` with an LFN entry to preserve mixed case, even though it fits in 8.3. Our driver should do the same: if the name has lowercase characters but otherwise fits in 8.3, create a single LFN entry + SFN entry.

4. **ntRes case bits (offset 0x0C):** Windows uses the reserved byte at offset 0x0C in the SFN entry to store case information for names that fit in 8.3: bit 3 = lowercase extension, bit 4 = lowercase name. For 8.3-only files with uniform case, set these bits instead of creating LFN entries. Reading these bits in `fileName()` would allow proper case display of 8.3 files created by Windows.

5. **Kanji lead byte ($E5 -> $05):** If a long name starts with the character $E5 (which means "deleted" in FAT), the SFN entry stores it as $05. Unlikely in practice but required for full compliance.

6. **Prohibited character validation:** Reject filenames containing `< > | ? * : " \` and control characters (0x00-0x1F). Return `E_INVALID_NAME` (new error code).

7. **Path length limit (260 characters):** Per fatgen103: "The total path length of a long name cannot exceed 260 characters, including the trailing NUL." Add a length check in `searchDirectory()` — if the full path exceeds 259 characters, return `E_INVALID_NAME`.

### 7.2 Phase 5 Deliverables

- [ ] Modified: `fileName()` (line 1331) — transparent LFN return
- [ ] Added: ntRes case bit handling for 8.3 names (read and write)
- [ ] Added: input validation for prohibited characters
- [ ] Added: `E_INVALID_NAME` error code
- [ ] Added: path length overflow protection (260-char limit per fatgen103)
- [ ] Added: trailing period stripping from input names (spec: "Trailing periods are ignored")
- [ ] Updated test suites with edge case tests
- [ ] New test suite: `SD_RT_lfn_boundary_tests.spin2`

---

## 8. Regression Test Plan

### 8.1 Preparation: Test Card Setup

Before running LFN read tests (Phase 1), the test card must have known LFN files created by a desktop OS. These are **preconditions** that the test comments will document.

**Setup script (run on macOS/Windows host before testing):**
1. Create directory `LFNTEST/` in the card root
2. Inside `LFNTEST/`, create files with known long names:
   - `Short.txt` — fits in 8.3 with case preservation
   - `A Simple Test File.txt` — spaces, 22 characters
   - `Document With Numbers 12345.dat` — 30 characters
   - `MixedCase.Extension` — mixed case, fits 8.3 length but not case
   - `VeryLongFileNameThatExceedsTwentySixCharacters.txt` — 48 chars, 4 LFN entries
   - `file-with-dashes.txt` — dashes, fits 8.3
   - `file+with+plus.txt` — plus signs, illegal in 8.3
3. Create subdirectory `LFNTEST/Long Directory Name With Spaces/`
4. Create file inside it: `Nested Long Name File.txt`

This card state is the **precondition** for Phase 1 read tests. Phase 2+ tests create their own LFN files on-device.

### 8.2 New Test Suite: `SD_RT_lfn_read_tests.spin2` (Phase 1)

**Feature flags:** `SD_INCLUDE_LFN` (and `SD_INCLUDE_DEBUG` for diagnostics)

#### Group 1: LFN Reading from Pre-Created Files (~8 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 1 | Read directory with LFN files | `openDirectory(@lfnTestDir)`, enumerate | All files visible (not skipped) |
| 2 | Long name retrieval | `longFileName()` after readDirectoryHandle | Returns full long name |
| 3 | Short name still available | `fileName()` after readDirectoryHandle | Returns 8.3 alias |
| 4 | Name with spaces | Find "A Simple Test File.txt" | Exact match via `evaluateStringMatch()` |
| 5 | Name > 26 chars (4 LFN entries) | Find the 48-char filename | Exact match |
| 6 | Mixed case preservation | Find "MixedCase.Extension" | Case preserved in long name |
| 7 | LFN subdirectory | `openDirectory()` on long-named dir | Opens successfully |
| 8 | Nested LFN file | Find file inside LFN directory | Full path works |

#### Group 2: Search by Long Name (~5 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 9 | Open file by long name | `openFileRead(@"A Simple Test File.txt")` | Returns valid handle |
| 10 | Case-insensitive search | `openFileRead(@"a simple test file.txt")` | Returns valid handle |
| 11 | Search non-existent LFN | `openFileRead(@"No Such Long Name.txt")` | E_FILE_NOT_FOUND |
| 12 | Search by 8.3 alias | `openFileRead(@"ASIMPL~1.TXT")` | Returns valid handle (same file) |
| 13 | changeDirectory by LFN | `changeDirectory(@"Long Directory Name With Spaces")` | Success |

#### Group 3: Checksum and Backward Compatibility (~3 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 14 | Valid checksum | Read entry with matching LFN checksum | `longFileName()` returns name |
| 15 | 8.3-only file | Read file with no LFN entries | `longFileName()` returns empty, `fileName()` returns 8.3 |
| 16 | Backward compat | Existing 8.3 test files | All still accessible by short name |

**Estimated lines:** 200-250

### 8.3 New Test Suite: `SD_RT_lfn_create_tests.spin2` (Phase 2)

**Feature flags:** `SD_INCLUDE_LFN`

#### Group 1: Basic LFN File Creation (~6 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 1 | Create LFN file | `createFileNew(@"My Test File.txt")` | Valid handle returned |
| 2 | Read back long name | Close, enumerate directory | `longFileName()` matches |
| 3 | Read back short name | Same entry | `fileName()` returns `MYTEST~1.TXT` or similar |
| 4 | Write and verify | Write data, close, reopen by LFN, read back | Data matches |
| 5 | Create 8.3-only file | `createFileNew(@"NORMAL.TXT")` | No LFN entries created |
| 6 | Create case-only LFN | `createFileNew(@"ReadMe.txt")` | LFN entry preserves case |

#### Group 2: Short Name Collision (~4 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 7 | First collision | Create "My Test File.txt" then "My Test Other.txt" | `~1` and `~2` aliases |
| 8 | Multiple collisions | Create 5 files with same 6-char base | `~1` through `~5` |
| 9 | Numeric overflow | Create 10+ colliding files | `~10`, `~11` etc. (5-char base) |
| 10 | Verify uniqueness | All short names in directory are unique | No duplicates |

#### Group 3: LFN Directory Creation (~3 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 11 | Create LFN directory | `newDirectory(@"My Long Dir Name")` | Success |
| 12 | Change into LFN dir | `changeDirectory(@"My Long Dir Name")` | CWD changes |
| 13 | Create file inside | Create file in LFN-named directory | Accessible by full path |

#### Group 4: Boundary Cases (~4 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 14 | 13-char name (1 LFN entry) | Create "1234567890123.txt" | 1 LFN + 1 SFN entry |
| 15 | 26-char name (2 LFN entries) | Create 26-char name | 2 LFN + 1 SFN entries |
| 16 | Max entries in sector | Fill directory sector near capacity, create LFN | Chain spans to next sector |
| 17 | Cluster expansion | Fill directory cluster, create LFN requiring new cluster | New cluster allocated |

**Estimated lines:** 250-300

### 8.4 New Test Suite: `SD_RT_lfn_delete_tests.spin2` (Phase 3)

**Feature flags:** `SD_INCLUDE_LFN`

#### Group 1: Delete LFN Files (~5 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 1 | Delete by long name | Create LFN file, delete by long name | File gone |
| 2 | Delete by short name | Create LFN file, delete by 8.3 alias | File gone, LFN entries also deleted |
| 3 | No orphaned entries | After delete, enumerate directory | No phantom LFN entries visible |
| 4 | Space reclaimed | After delete, create new file | Reuses freed entry space |
| 5 | Delete 8.3 file | Delete file with no LFN entries | Works as before |

#### Group 2: Directory Consistency (~3 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 6 | Interleaved operations | Create 3 LFN files, delete middle one, enumerate | Correct 2 files visible |
| 7 | Delete LFN directory | Create LFN-named dir, delete it | Removed cleanly |
| 8 | Delete and recreate | Delete LFN file, create new with same name | Works cleanly |

**Verification strategy:** Tests 2-3 should use raw sector reads (via `readSectorRaw()`) to confirm that LFN entry bytes are actually $E5, not just hidden from enumeration.

**Estimated lines:** 150-200

### 8.5 New Test Suite: `SD_RT_lfn_rename_tests.spin2` (Phase 4)

**Feature flags:** `SD_INCLUDE_LFN`

#### Group 1: Rename Operations (~6 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 1 | Rename LFN to LFN | Rename "Long Name.txt" to "New Long Name.txt" | New chain correct |
| 2 | Rename LFN to 8.3 | Rename "Long Name.txt" to "SHORT.TXT" | LFN entries removed, 8.3 only |
| 3 | Rename 8.3 to LFN | Rename "SHORT.TXT" to "Now A Long Name.txt" | LFN chain created |
| 4 | Rename 8.3 to 8.3 | Rename "OLD.TXT" to "NEW.TXT" | Works as before (no LFN) |
| 5 | Rename preserves data | Write data, rename, read back | Data intact |
| 6 | Rename preserves attrs | Set attributes, rename | Attributes unchanged |

#### Group 2: Move with LFN (~3 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 7 | Move LFN file to subdir | moveFile with long name | File in new location with LFN |
| 8 | Move preserves LFN | Move file, check `longFileName()` | Name unchanged |
| 9 | Move across directories | Root to subdir | Works with LFN chain |

**Estimated lines:** 200-250

### 8.6 New Test Suite: `SD_RT_lfn_boundary_tests.spin2` (Phase 5)

**Feature flags:** `SD_INCLUDE_LFN`

#### Group 1: Name Length Boundaries (~4 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 1 | Maximum name length (255 chars) | Create file with 255-char name | 20 LFN + 1 SFN entries |
| 2 | 254-char name | One less than max | 20 LFN entries |
| 3 | 256-char name (overflow) | Attempt to create | Error returned |
| 4 | Exact multiple of 13 (26 chars) | Create 26-char name | No null/$FFFF padding in last LFN entry |

#### Group 2: Name Content Edge Cases (~6 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 5 | Name with many dots | "file.name.with.dots.txt" | LFN correct, extension from last dot |
| 6 | Leading space | " leading.txt" | LFN preserves, SFN strips leading spaces |
| 7 | All uppercase fits 8.3 | "TESTFILE.TXT" | No LFN entries created |
| 8 | All lowercase fits 8.3 | "testfile.txt" | LFN or ntRes case bits |
| 9 | Empty extension | "filename" (no dot) | Valid LFN |
| 10 | Prohibited characters | `"file<name.txt"` | E_INVALID_NAME error |

#### Group 3: Spec Compliance (~5 tests)

| # | Test | Action | Expected |
|---|------|--------|----------|
| 11 | Corrupted sequence numbers | Raw-write LFN entries with wrong seq order, read back | `longFileName()` returns empty (orphaned) |
| 12 | Checksum mismatch detection | Raw-modify SFN name after LFN write, read back | `longFileName()` returns empty |
| 13 | Path length 260 chars | Build path near 260-char limit | Success at 259, error at 260+ |
| 14 | Short name no-tail case | Create "README.TXT" (all uppercase, fits 8.3) | No `~1` tail, no LFN entries |
| 15 | Unified namespace collision | Create LFN "MyTest.txt" (`MYTEST~1.TXT` alias), then short "MYTEST~1.TXT" | Second create gets `~2` or different alias |

**Estimated lines:** 200-250

### 8.7 Existing Test Suites: Regression Verification

**Every existing test suite must continue to pass unchanged.** Current baseline: 25 suites, 444 tests, all passing. The following are most likely to be affected by LFN changes:

| Test Suite | Risk | Why |
|------------|------|-----|
| `SD_RT_file_ops_tests.spin2` | Medium | Uses `createFileNew()`, `deleteFile()`, `rename()` with 8.3 names |
| `SD_RT_directory_tests.spin2` | Medium | Uses `newDirectory()`, `changeDirectory()` |
| `SD_RT_dirhandle_tests.spin2` | Medium | Uses `readDirectoryHandle()`, `fileName()` |
| `SD_RT_subdir_ops_tests.spin2` | Medium | Directory operations in subdirectories |
| `SD_RT_defrag_tests.spin2` | Low | File creation/deletion but only 8.3 names |
| `SD_RT_mount_tests.spin2` | Low | Mount/unmount only |
| `SD_RT_read_write_tests.spin2` | Low | File I/O only (names unchanged) |
| All other 18 suites | Low | No directory/file name operations |

**Regression strategy:** Run all 25 existing test suites after each phase via `run_regression.sh`. Any failure in existing tests is a blocker before proceeding.

### 8.8 Test Summary

| Test Suite | Phase | New Tests | Est. Lines |
|------------|-------|-----------|------------|
| `SD_RT_lfn_read_tests.spin2` | 1 | ~16 | 200-250 |
| `SD_RT_lfn_create_tests.spin2` | 2 | ~17 | 250-300 |
| `SD_RT_lfn_delete_tests.spin2` | 3 | ~8 | 150-200 |
| `SD_RT_lfn_rename_tests.spin2` | 4 | ~9 | 200-250 |
| `SD_RT_lfn_boundary_tests.spin2` | 5 | ~15 | 200-250 |
| **Total** | | **~65** | **1,000-1,250** |

After all phases: 30 suites, ~509 tests.

### 8.9 Test File Template

All LFN test files follow the established pattern:

```spin2
CON
    _CLKFREQ = 350_000_000
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

#ifdef __SPINTOOLS__
#define SD_INCLUDE_LFN
#define SD_INCLUDE_DEBUG
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_LFN
#pragma exportdef SD_INCLUDE_LFN
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG
#else
#pragma exportdef SD_INCLUDE_LFN
#pragma exportdef SD_INCLUDE_DEBUG
#endif

OBJ
    sd    : "micro_sd_fat32_fs"
    utils : "isp_rt_utilities"

DAT
    ' Test filenames — use LFN-length names
    longNameFile    BYTE    "My Long Test File.txt", 0
    ...

PUB go() | handle, result, p_name
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    ' ... test groups ...
    sd.unmount()
    utils.ShowTestEndCounts()
    debug("END_SESSION")
```

Key assertions for LFN tests:
- `evaluateStringMatch(sd.longFileName(), @"My Long Test File.txt", @"long name match")` — verify exact LFN
- `evaluateSingleValue(handle, @"handle valid", 0)` — verify operations succeed
- `evaluateBool(strsize(sd.longFileName()) > 0, @"has long name", true)` — verify LFN exists

---

## 9. Demo Shell Changes

### 9.1 Directory Listing (`do_dir()`, Line 444)

**Current (line 493):** Uses `fileName()` to display 8.3 names:
```spin2
p_name := sd.fileName()
```

**After Phase 1:** Modify to display long names with 8.3 fallback:

```spin2
p_name := sd.longFileName()
if strsize(p_name) == 0
    p_name := sd.fileName()             ' fallback to 8.3
```

**Column width:** The current fixed-width display uses `%s` in fstr calls (lines 529, 531). Long names will naturally extend the output. Since the shell is a debug/development tool, variable-width is acceptable. No truncation needed.

**Current output format:**
```
  Attr  Modified              Size  Name
  ----  ----------------  --------  --------------------------------
  D---  2026-03-25 14:30    <DIR>  MYDIR
  ----  2026-03-25 14:30      1024  MYFILE.TXT
```

**After LFN:**
```
  Attr  Modified              Size  Name
  ----  ----------------  --------  --------------------------------
  D---  2026-03-25 14:30    <DIR>  My Long Directory Name
  ----  2026-03-25 14:30      1024  A Simple Test File.txt
  ----  2026-03-25 14:30       512  SHORT.TXT
```

**Estimated change:** ~5 lines modified in `do_dir()`.

### 9.2 Tree Command (`tree_walk()`, Line 1509)

`tree_walk()` recursively displays directory structure. It calls `sd.fileName()` at approximately line 1538. Same change: try `longFileName()` first, fall back to `fileName()`.

**Estimated change:** ~3 lines modified.

### 9.3 File Operations (All Other Commands)

All shell file commands already accept string arguments from the command line. No changes needed to `do_type()`, `do_hexdump()`, `do_copy()`, `do_delete()`, `do_rename()`, `do_move()`, `do_mkdir()`, `do_cd()`, `do_touch()` — they pass the user's input string directly to the driver API. Once `searchDirectory()` supports LFN matching, these commands automatically work with long names.

The only caveat is the command-line parser. Currently the parser (`parse()` at line 1949) tokenizes by whitespace. Long filenames with spaces would need quoting. Two options:

**Option A (simple):** Require quotes around names with spaces: `type "My Long File.txt"`
**Option B (deferred):** Treat remaining tokens after the command as one argument for single-argument commands like `type`, `cd`, `mkdir`.

**Recommendation:** Option A for initial release. The parser already tokenizes into `tokens[]` array; modifying `parse()` to handle quoted strings is ~20 lines.

### 9.4 Help Text Update

Update `show_help()` (line 273) to mention long filename support:

```
Filenames: Supports long file names up to 255 characters.
           Use quotes for names with spaces: type "My File.txt"
           8.3 short names also work (e.g., MYFILE~1.TXT).
```

### 9.5 Demo Shell Summary

| Change | Phase | Est. Lines |
|--------|-------|------------|
| `do_dir()` — display long names | 1 | ~5 |
| `tree_walk()` — display long names | 1 | ~3 |
| `parse()` — quoted string support | 2 | ~20 |
| Help text update | 1 | ~5 |
| **Total** | | **~33** |

---

## 10. New Public API Surface

### 10.1 New Methods

| Method | Phase | Description |
|--------|-------|-------------|
| `longFileName() : p_name` | 1 | Return pointer to assembled long name (empty string if no LFN) |

### 10.2 Modified Methods (Behavior Change)

| Method | Phase | What Changes |
|--------|-------|-------------|
| `openFileRead(p_path)` | 1 | Accepts long names in path |
| `openFileWrite(p_path)` | 1 | Accepts long names in path |
| `createFileNew(p_path)` | 2 | Creates LFN entries when name requires it |
| `createFileContiguous(p_path, size)` | 2 | Creates LFN entries when name requires it |
| `openDirectory(p_path)` | 1 | Accepts long directory names in path |
| `readDirectoryHandle(handle)` | 1 | Populates `lfn_name_buf` in addition to `entry_buffer` |
| `deleteFile(p_name)` | 3 | Deletes LFN entries + SFN entry |
| `rename(p_old, p_new)` | 4 | Manages LFN chain transitions |
| `moveFile(p_name, p_dest)` | 4 | LFN-aware move |
| `newDirectory(p_name)` | 2 | Creates LFN entries when name requires it |
| `changeDirectory(p_name)` | 1 | Accepts long directory names |
| `fileName()` | 5 | Returns long name when available (transparent upgrade) |

### 10.3 New Error Codes

| Code | Value | Phase | Description |
|------|-------|-------|-------------|
| `E_INVALID_NAME` | -65 | 5 | Filename contains prohibited characters |

### 10.4 Backward Compatibility

All changes are backward-compatible:
- 8.3 filenames continue to work identically
- `fileName()` behavior is unchanged until Phase 5 (when it optionally returns long names)
- The existing handle-based API (`openFileRead()`, `readHandle()`, `writeHandle()`, etc.) is unaffected
- All existing error codes remain unchanged
- When `SD_INCLUDE_LFN` is not defined, the driver compiles identically to today

---

## 11. Memory and Performance Impact

### 11.1 DAT Memory

| Buffer | Size | Purpose |
|--------|------|---------|
| `lfn_name_buf` | 256 bytes | Assembled long name (ASCII + null) |
| `lfn_entries` | 672 bytes | Raw LFN entry chain (max 21 x 32) |
| `lfn_entry_count` | 1 byte | LFN chain length |
| `lfn_first_address` | 4 bytes | First LFN entry byte address |
| `lfn_valid` | 1 byte | LFN assembly validity flag |
| **Total** | **934 bytes** | |

The driver currently uses approximately 24-52 KB depending on conditional compilation. Adding 934 bytes is a modest ~2-4% increase.

### 11.2 Code Size

| Phase | Est. Lines | Compiled Size Impact |
|-------|------------|---------------------|
| Phase 1 (Read) | 200-250 | ~800 bytes |
| Phase 2 (Create) | 300-350 | ~1,200 bytes |
| Phase 3 (Delete) | 60-80 | ~300 bytes |
| Phase 4 (Rename/Move) | 100-120 | ~400 bytes |
| Phase 5 (Polish) | 50-80 | ~200 bytes |
| **Total** | **710-880** | **~2,900 bytes** |

### 11.3 Performance

| Operation | Impact | Reason |
|-----------|--------|--------|
| Directory listing | Slight slowdown | Must process LFN entries instead of skipping |
| File search | Slight slowdown | Must assemble and compare long names |
| File create | Slight slowdown | Must write N+1 entries instead of 1 |
| File delete | Slight slowdown | Must mark N+1 entries instead of 1 |
| File read/write | **No impact** | LFN is directory metadata only |

The performance impact is negligible in practice. LFN processing adds a few microseconds per directory entry; SD card I/O latency (milliseconds) dominates.

### 11.4 Stack Impact

LFN assembly uses the existing `lfn_entries` DAT buffer (672 bytes), not stack. The new private methods add modest stack usage (~20-30 longs for local variables). The worker cog stack (`STACK_SIZE`) should not need increasing, but verify with `checkStackGuard()` after testing.

---

## 12. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **Directory corruption on write** | High | Phase 2 writes are the most dangerous. Validate by reading back every chain we write. Test with fsck after every create. |
| **Cross-sector LFN chains** | High | LFN chains can span sector boundaries. `findConsecutiveFreeEntries()` and `writeLfnChain()` must handle this. Dedicated boundary tests (8.3 test 16). |
| **Cluster allocation for directory expansion** | High | When a directory is full and we need space for LFN entries, must allocate new cluster. Use existing `allocateCluster()` + `clearCluster()`. |
| **Short name collision loops** | Medium | `~1` through `~99` could theoretically loop. Cap at `~99` and return `E_DISK_FULL`. |
| **Orphaned entries on power loss** | Medium | Same as any FAT32 write. FSCK can recover. Not worse than Windows. |
| **Entry count miscalculation** | Medium | Off-by-one in LFN entry count = corrupted chain. Thorough test coverage with exact entry count verification via raw sector reads. |
| **Buffer coherence** | Medium | `dir_buf` caching must be invalidated when writing LFN entries across sectors. Use existing `dir_sec_in_buf := -1` pattern. |
| **Checksum mismatch** | Low | Verify with read-back tests: write LFN chain, re-read, confirm checksum matches. |
| **UTF-16 edge cases** | Low | We only support ASCII subset. Non-ASCII UTF-16 chars become `_`. Sufficient for embedded use. |
| **do_movefile() complexity** | Medium | Must save and replay entire LFN chain across directories. Test with raw sector verification of both source and destination. |

---

## 13. Conditional Compilation

### 13.1 New Feature Flag

Add `SD_INCLUDE_LFN` as a new conditional compilation flag:

```spin2
' In the consumer's top-level file:
#ifdef __SPINTOOLS__
#define SD_INCLUDE_LFN
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_LFN
#pragma exportdef SD_INCLUDE_LFN
#else
#pragma exportdef SD_INCLUDE_LFN
#endif
```

### 13.2 Driver Gating

In `micro_sd_fat32_fs.spin2`, gate LFN code with:

```spin2
#ifdef SD_INCLUDE_LFN
' ... LFN-specific DAT buffers ...
' ... LFN-specific methods ...
#endif
```

For methods like `searchDirectory()` that have both 8.3 and LFN paths, use inline conditionals:

```spin2
PRI searchDirectory(name_ptr) : found
    #ifdef SD_INCLUDE_LFN
    if lfn_needs_lfn(name_ptr)
        return searchDirectoryLFN(name_ptr)
    #endif
    ' ... existing 8.3 search code (unchanged) ...
```

For `do_read_dir_h()`, the LFN collection wraps the existing skip logic:

```spin2
#ifdef SD_INCLUDE_LFN
    if attrib == ATTR_LFN
        ' collect LFN entry into lfn_entries[]
        next
#else
    if attrib == ATTR_LFN
        next
#endif
```

### 13.3 SD_INCLUDE_ALL Includes LFN

Update the `SD_INCLUDE_ALL` expansion to also define `SD_INCLUDE_LFN`:

```spin2
#ifdef SD_INCLUDE_ALL
' ... existing flags ...
#ifndef SD_INCLUDE_LFN
#define SD_INCLUDE_LFN
#endif
#endif
```

### 13.4 Compile Size Impact

| Configuration | Approximate Size |
|---------------|-----------------|
| Core only (no flags) | ~24 KB |
| Core + LFN only | ~27 KB |
| SD_INCLUDE_ALL (with LFN) | ~55 KB |

---

## 14. References

### 14.1 Project Documents

- `DOCs/Reference/FAT32-API-CONCEPTS-REFERENCE.md` — LFN entry structure and assembly algorithm
- `DOCs/Analysis/REGRESSION-TEST-COVERAGE-ANALYSIS.md` — existing test coverage analysis
- `DOCs/Plans/PUNCH-LIST.md` — outstanding issues list
- `DOCs/SD-CARD-DRIVER-THEORY.md` — driver theory of operations

### 14.2 Specifications

- Microsoft FAT32 File System Specification (fatgen103) — Section on VFAT long file names
- SD Physical Layer Specification v9.10 — directory entry format
- `DOCs/Specs/` folder — local copies of specifications

### 14.3 Driver Source (current line references, as of v1.4.2)

- `src/micro_sd_fat32_fs.spin2` — the driver (~7,150 lines)
  - `dir_entry_t` struct: line 447
  - SFN constants: line 285 (`SFN_NAME_LEN=8`, `SFN_EXT_LEN=3`, `SFN_TOTAL_LEN=11`)
  - `ATTR_LFN` constant: line 254 (`$0F`)
  - **New constant needed:** `ATTR_LONG_NAME_MASK = $3F` (RO|HID|SYS|VOL|DIR|ARCHIVE) — used for masked LFN detection per fatgen103
  - `DIR_ENTRY_SIZE` / `DIR_ENTRIES_PER_SECTOR`: lines 258-259
  - `entry_buffer` declaration: line 672
  - `fileName()`: line 1331 (returns 8.3 formatted name from `entry_buffer`)
  - `fileSize()`: line 1350
  - `attributes()`: line 1357
  - `do_create()`: line 3230 (handle-based file creation)
  - `do_read_dir_h()`: line 3783 (LFN skip at line 3853)
  - `do_newfile()`: line 3879 (legacy file creation)
  - `do_newdir()`: line 3909 (directory creation)
  - `do_delete()`: line 3984 (marks only SFN entry at line 3996)
  - `do_rename()`: line 4054 (in-place SFN update at line 4094)
  - `do_movefile()`: line 4179 (copies only 32-byte SFN at line 4206)
  - `do_readdir()`: line 4220 (legacy directory read)
  - `searchDirectory()`: line 4458 (8.3 conversion at line 4482)

### 14.4 Test Infrastructure

- `src/regression-tests/isp_rt_utilities.spin2` — test framework with assertions
  - `evaluateStringMatch(pResult, pMessage, pExpected)` — string comparison (critical for LFN name verification)
  - `evaluateBufferMatch(pBuffer1, pBuffer2, length, pMessage)` — buffer comparison (for raw entry verification)
  - `evaluateSingleValue(result, pMessage, expectedResult)` — value assertions
  - `evaluateSubValue()` / `evaluateSubBool()` — sub-test assertions
  - `evaluateBool(result, pMessage, expectedResult)` — boolean assertions
  - `evaluateRange(result, pMessage, min, max)` — range assertions
  - Guard zones: `GUARD_SIZE=16`, sentinel byte `$CC`
- Current baseline: 25 suites, 444 tests, all passing

### 14.5 Demo Shell

- `src/DEMO/SD_demo_shell.spin2` — interactive terminal shell (~2,210 lines)
  - `do_dir()`: line 444 (directory listing; uses `fileName()` at line 493)
  - `tree_walk()`: line 1509 (recursive directory tree)
  - `parse()`: line 1949 (command-line tokenizer — needs quoted string support)
  - `show_help()`: line 273 (help text)

---

## Implementation Checkpoints

Each phase produces a commit and must pass all existing tests plus new phase tests:

1. **Phase 1 complete** — Commit: "Add LFN read support (longFileName API, directory enumeration, search by long name)"
   - New suite: `SD_RT_lfn_read_tests.spin2`
   - Demo shell: `do_dir()` and `tree_walk()` show long names
   - All 26 suites pass

2. **Phase 2 complete** — Commit: "Add LFN create support (createFileNew, newDirectory with long names)"
   - New suite: `SD_RT_lfn_create_tests.spin2`
   - Demo shell: `parse()` supports quoted strings
   - All 27 suites pass

3. **Phase 3 complete** — Commit: "Add LFN-aware deletion (complete chain cleanup)"
   - New suite: `SD_RT_lfn_delete_tests.spin2`
   - All 28 suites pass

4. **Phase 4 complete** — Commit: "Add LFN-aware rename and move"
   - New suite: `SD_RT_lfn_rename_tests.spin2`
   - All 29 suites pass

5. **Phase 5 complete** — Commit: "LFN polish: transparent fileName, case bits, validation, edge cases"
   - New suite: `SD_RT_lfn_boundary_tests.spin2`
   - All 30 suites pass (~503 tests)

---

## Appendix A: Example On-Disk Layout

### File: "My Document.txt" (15 characters)

Requires 2 LFN entries (ceil(15/13) = 2) + 1 SFN entry = 3 directory entries = 96 bytes.

```
Entry at offset 0x000: LFN #2 (last)
  Ord:    $42 ($40 | 2 = last flag + sequence 2)
  Name1:  "n" "t" \0  \xFF \xFF   (UTF-16LE: $6E00 $7400 $0000 $FFFF $FFFF)
  Attr:   $0F
  Type:   $00
  Chksum: computed from "MYDOCU~1TXT"
  Name2:  \xFF \xFF \xFF \xFF \xFF \xFF
  FstClus: $0000
  Name3:  \xFF \xFF

Entry at offset 0x020: LFN #1
  Ord:    $01 (sequence 1)
  Name1:  "M" "y" " " "D" "o"     (UTF-16LE: $4D00 $7900 $2000 $4400 $6F00)
  Attr:   $0F
  Type:   $00
  Chksum: same
  Name2:  "c" "u" "m" "e" "n" "t"  (UTF-16LE: $6300 $7500 $6D00 $6500 $6E00 $7400)
  FstClus: $0000
  Name3:  "." "t"                  (UTF-16LE: $2E00 $7400)

  Chars in entry #1 (positions 0-12): "My Document.t" (13 chars)
  Chars in entry #2 (positions 13-14): "xt" + null terminator + padding

Entry at offset 0x040: SFN
  Name:   "MYDOCU~1"
  Ext:    "TXT"
  Attr:   $20 (archive)
  ... timestamps, cluster, size ...
```

---

## Appendix B: Method Dependency Graph

```
Phase 1 (Read):
  lfn_checksum()           [new, standalone]
  lfn_extract_chars()      [new, standalone]
  lfn_assemble()           [new, calls checksum + extract]
  do_read_dir_h()          [modified, calls assemble]
  do_readdir()             [modified, calls assemble]
  searchDirectory()        [modified, calls assemble]
  longFileName()           [new API, reads lfn_name_buf]

Phase 2 (Create):
  lfn_needs_lfn()          [new, standalone]
  lfn_generate_short_name() [new, standalone]
  lfn_build_entries()      [new, calls checksum]
  findConsecutiveFreeEntries() [new, uses FAT allocation]
  writeLfnChain()          [new, writes dir entries across sectors]
  do_newfile()             [modified, calls needs/generate/build/find/write]
  do_newdir()              [modified, same as do_newfile]
  do_create()              [modified, same as do_newfile]

Phase 3 (Delete):
  lfn_mark_chain_deleted() [new, standalone]
  do_delete()              [modified, calls mark_chain_deleted]

Phase 4 (Rename/Move):
  do_rename()              [modified, calls Phase 3 delete + Phase 2 create]
  do_movefile()            [modified, saves LFN chain + Phase 3 delete + Phase 2 create]

Phase 5 (Polish):
  fileName()               [modified, checks lfn_valid]
  lfn_needs_lfn()          [enhanced, ntRes case handling]
  searchDirectory()        [enhanced, case-insensitive refinements]
```

---

## Appendix C: New Helper Method Summary

| Method | Phase | Lines | Gated By | Purpose |
|--------|-------|-------|----------|---------|
| `lfn_checksum()` | 1 | ~10 | SD_INCLUDE_LFN | Compute 8-bit checksum from 11-byte SFN |
| `lfn_extract_chars()` | 1 | ~30 | SD_INCLUDE_LFN | Extract 13 UTF-16LE chars from one LFN entry |
| `lfn_assemble()` | 1 | ~60 | SD_INCLUDE_LFN | Assemble full name with seq# and checksum validation |
| `lfn_needs_lfn()` | 2 | ~15 | SD_INCLUDE_LFN | Determine if filename requires LFN entries |
| `lfn_generate_short_name()` | 2 | ~80 | SD_INCLUDE_LFN | Basis-name + numeric tail per fatgen103 algorithm |
| `lfn_build_entries()` | 2 | ~80 | SD_INCLUDE_LFN | Build LFN entry chain in buffer |
| `findConsecutiveFreeEntries()` | 2 | ~80 | SD_INCLUDE_LFN | Find N consecutive free dir entry slots |
| `writeLfnChain()` | 2 | ~40 | SD_INCLUDE_LFN | Write LFN chain to directory (cross-sector) |
| `lfn_mark_chain_deleted()` | 3 | ~40 | SD_INCLUDE_LFN | Mark N LFN entries as $E5 (cross-sector) |
| **Total** | | **~435** | | |

---

## Appendix D: Specification Compliance Audit

**Audit date:** 2026-03-30
**Source specs:** MS-FAT32-Spec-fatgen103.pdf (primary), MS-FAT32-Spec-MIT.pdf (secondary)
**Source location:** `DOCs/Specs/`

**Note:** The SD Physical Layer spec chunks (`DOCs/Specs/Part1_chunks/chunk_aa` through `chunk_ar` and `Part1PhysicalLayer.txt`) contain zero filesystem or LFN information — they cover only the SD card hardware protocol. All LFN spec content resides in the two Microsoft FAT32 PDFs.

### D.1 Spec Requirements vs Plan Coverage

| # | Spec Requirement (fatgen103) | Plan Section | Status |
|---|------------------------------|-------------|--------|
| 1 | LFN entry structure: 32 bytes, 13 UTF-16LE chars across 3 fields | 1.1 | Correct |
| 2 | LDIR_Attr must be $0F (ATTR_LONG_NAME) | 1.1 | Correct |
| 3 | LDIR_Type must be $00 | 1.1 | Correct |
| 4 | LDIR_FstClusLO must be $0000 | 1.1 | Correct |
| 5 | LFN detection: `(attr & $3F) == $0F` masked check, not equality | 3.3 | **Fixed in this audit** — was `== $0F` |
| 6 | Deleted LFN: byte 0 == $E5 means free, even if attr=$0F | 3.3 | **Fixed in this audit** — added $E5 check |
| 7 | Reverse storage order: highest seq# first on disk, last flag ($40) | 1.2 | Correct |
| 8 | Sequence validation: 1 to (N\|$40), monotonic, else orphan | 3.2 | **Fixed in this audit** — added to `lfn_assemble()` |
| 9 | Checksum: right-rotate-and-add over 11-byte SFN | 1.3 | Correct |
| 10 | All LFN entries share same checksum; mismatch = orphan | 3.2 | Correct |
| 11 | Null padding: $0000 after last char, then $FFFF fill | 1.5 | **Fixed in this audit** — was imprecise |
| 12 | No null/$FFFF if name is exact multiple of 13 | 1.5 | **Fixed in this audit** — exception added |
| 13 | Max 255 UTF-16 characters per name | 1.5 | Correct |
| 14 | Max 20 LFN entries per file | 1.5 | Correct |
| 15 | Total path <= 260 chars including NUL | 7.1 | **Fixed in this audit** — was unspecified |
| 16 | Basis-name: strip embedded spaces, not just leading/trailing | 1.4 | **Fixed in this audit** — was incomplete |
| 17 | Basis-name: strip all leading periods | 1.4 | **Fixed in this audit** — was incomplete |
| 18 | Lossy conversion flag forces numeric tail | 1.4, 4.1 | **Fixed in this audit** — was missing |
| 19 | No-tail case: non-lossy + fits 8.3 + no collision = direct map | 1.4, 4.1 | **Fixed in this audit** — plan always added `~1` |
| 20 | Unified namespace: no duplicate names across SFN and LFN spaces | 4.1 | **Fixed in this audit** — was SFN-only |
| 21 | Case-insensitive search across both namespaces | 3.5 | Correct |
| 22 | searchDirectory must always collect LFN state for downstream ops | 3.5 | **Fixed in this audit** — was conditional |
| 23 | Long names preserve original case (not uppercased on disk) | Background | Correct (LFN stored as-is) |
| 24 | Short names stored uppercase | Background | Correct (existing driver behavior) |
| 25 | $E5/$05 Kanji lead byte substitution | 7.1 | Correct — identified as Phase 5 item |
| 26 | DIR_NTRes ($0C) "set to 0, never modify after" (official) | 7.1 | Correct — handled as undocumented extension |
| 27 | Deletion must mark all LFN entries + SFN as $E5 | 5.0 | Correct |
| 28 | Orphan detection: LFN without valid paired SFN = orphan | 3.2 | Correct |
| 29 | LFN entries identical across FAT12/16/32 | N/A | N/A (we only support FAT32) |
| 30 | Illegal SFN chars: `" * + , . / : ; < = > ? [ \ ] \|` and < $20 | 4.1 | Correct |
| 31 | Legal LFN additions over SFN: `+ , ; = [ ]` and spaces | Background | Correct |
| 32 | Trailing periods ignored in long names | 7.1 | Not explicitly handled — **add to Phase 5** |
| 33 | Leading/trailing spaces ignored in long names | 7.1 | Partially covered (leading space test exists) |

### D.2 Remaining Gap: Trailing Periods

The spec states: "Trailing periods are ignored." This means `"myfile.txt..."` should be treated as `"myfile.txt"`. The plan's Phase 5 prohibited character validation should strip trailing periods from input names before processing. Add to Phase 5 deliverables.

### D.3 Spec Items Intentionally Not Implemented

| Item | Reason |
|------|--------|
| Full UNICODE support (non-ASCII UTF-16) | Embedded systems use ASCII. Non-ASCII chars substituted with `_`. |
| OEM code page conversion | P2 has no OS/locale. We use identity mapping for $00-$7F, `_` for > $7F. |
| DBCS (Double-Byte Character Set) support | Not relevant for English-language embedded use. |
| LDIR_Type non-zero values | Spec reserves for "future extensions." We treat non-zero Type as invalid. |
