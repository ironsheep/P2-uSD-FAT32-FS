# Error Reporting Audit — Public API and Internal Error Flow

**Date:** 2026-07-31
**Subject:** `src/micro_sd_fat32_fs.spin2` (v1.6.1, 8205 lines)
**Question asked:** Are we ignoring errors instead of returning them? Can a user find out
what error occurred? Do we stop appropriately when an error occurs?
**Answer:** In several places, no. 24 findings below, 21 of them user-affecting. (19/11 as
first written; Class F was added the same day at Stephen's prompt, and A9/A10 on 2026-08-01
when `check_error_handling.sh` found two the read-through had missed. The user-affecting
count was also wrong from the Class F addition onward and was corrected 2026-08-01 — see the
note under §7, which is the live count.)

> **Line numbers in this document are as of commit `73e13b0`** (the tree this audit was
> read against). They are *not* maintained as the driver changes, and they are already
> stale: the `SD_INCLUDE_TEST_HOOKS` fault-injection facility landed immediately after
> this audit and shifted `micro_sd_fat32_fs.spin2` by roughly 110 lines from `do_newfile`
> onward. Re-anchoring 21 findings by hand would go stale again at the first fix, so the
> citations stay as captured and this stamp says what they mean. Locate a finding by the
> method name and the quoted code, not by the number. `tools/check_error_handling.sh`
> reports the live line for every finding it covers.

---

## 1. Scope and method

Every `PUB` in the driver (127 methods) was read, along with the error infrastructure
(`set_error`, `ERROR()`, `send_command`, the worker dispatcher) and every internal
`PRI` that a public method's error value flows through. The audit traces one thing:
**an error is detected somewhere in the driver — can the caller find out?**

Three failure modes are distinguished throughout:

| Mode | Meaning |
|------|---------|
| **Dropped** | The driver detected a failure and discarded it. Caller is told success. |
| **Misreported** | The caller is told a failure occurred, but the wrong one. |
| **Unreachable** | The failure is in the return value, but the caller cannot distinguish it from a legitimate result, and `ERROR()` was not set. |

Severity uses the project's release-gate classification (`CLAUDE.md`): **user-affecting**
means someone using the shipped driver in normal use could hit it and get wrong data, a
wrong result, a silent failure, or documentation that misdescribes the code.

---

## 2. The intended design

The driver has a sound error model, and it is worth stating plainly because most of the
findings are deviations from it rather than gaps in it:

1. Internal primitives return negative error codes (`readSector`, `writeSector`, `allocateCluster`).
2. `do_*` worker methods propagate those upward as their own return value.
3. The dispatcher stores the result in `pb_status` / `pb_data0`.
4. `send_command()` returns `pb_status` to the calling cog.
5. The `PUB` returns it to the user **and** calls `set_error()` so `ERROR()` can be
   queried later.
6. `ERROR()` is per-cog (`last_error[8]`), so concurrent cogs don't clobber each other.

Where this chain is followed end to end, the reporting is genuinely good. Some parts of
the driver are exemplary and should be the model for the fixes:

- **`readSector()` (6332–6531)** is careful and correct. Every failure path invalidates
  the sector cache (6405, 6428, 6435, 6520, 6523, 6529) so a failed read can never leave
  the cache claiming to hold a sector it doesn't. It distinguishes "CMD17 never
  acknowledged" from "no start token" (6402–6407), decodes data-error tokens against the
  SD spec (6424–6426), retries on CRC mismatch, and validates card-internal state via
  CMD13 afterward (6528).
- **`do_sync_all()` (4165–4186)** and **`do_unmount()` (3446–3476)** deliberately continue
  after a failure so as much data as possible reaches disk, then report the *first* error.
  The reasoning is documented in the method headers. This is the right pattern.
- **`do_write_h()`** carries a data-region write guard (3950–3952) that refuses to write
  below `root_sec` rather than corrupt FAT/VBR space.
- **`updateFSInfo()` (5157–5190)** reports success only when both the primary *and* backup
  FSInfo writes land, with the rationale recorded inline.

The findings below are places where this chain breaks.

---

## 3. Findings — Class A: errors dropped, caller told success

These are the serious ones. In each, the driver detects a failure and returns success.

### A1. `sync()` can never report failure — and is documented as if it can
**User-affecting. Severity: high.**

`PUB sync()` (1090–1099) is documented `@returns status - SUCCESS (0) on success,
negative error code on failure`. The dispatcher (2739–2741):

```
      CMD_SYNC:
        do_sync()
        pb_status := SUCCESS
```

`do_sync()` (4499–4508) has no return value at all. It swallows a failed directory read
(4503–4504, DEBUG only) and ignores the `writeSector()` status entirely (4507). Worse, it
clears `F_NEWDIR` unconditionally on the way out (4509) — so the pending directory entry
is discarded from memory *even though it never reached disk*. The user calls `sync()` to
checkpoint data during a long operation, gets `SUCCESS`, and has lost the entry.

This is the `debugClearRootDir()` pattern named in the release gate: public documentation
asserting the opposite of what the code does.

### A2. `allocateCluster()` ignores all four FAT writes
**User-affecting. Severity: high. Corruption path.**

Lines 5085–5086 write the new cluster's FAT1/FAT2 entries; 5095–5096 write the chain-link
entries. None of the four statuses is checked:

```
        writeSector(fat_sec + result >> 7, BUF_FAT)                '  write FAT1 sector
        writeSector(fat2_sec + result >> 7, BUF_FAT)               '  write FAT2 sector (MIRROR)
```

If a FAT write fails, `allocateCluster()` returns the cluster number as a success. The
in-memory `fat_buf` says allocated; the card does not. The next allocation scan reads the
FAT back from the card, sees the cluster still free, and hands the *same cluster* to a
second file. Result: two files sharing one cluster chain — cross-linked files, the classic
FAT corruption, reported to the user as two successful writes.

Note the contrast three lines below: the chain-link *read* at 5088 **is** checked, and its
failure comment even acknowledges the consequence ("cluster orphaned"). The writes were
simply never given the same treatment.

### A3. `do_delete()` ignores the directory-entry write, then frees the clusters
**User-affecting. Severity: high. Corruption path.**

```
4452    dir_buf[entry_address & SECTOR_OFFSET_MASK] := DIR_ENTRY_DELETED
4453    writeSector(entry_address >> SECTOR_SHIFT, BUF_DIR)
4456    status := freeClusterChain(firstCluster())
```

The write that marks the entry deleted is unchecked; the cluster chain is then freed
regardless. On a failed directory write the on-disk state is: entry still live, clusters
marked free. The file appears to exist, its clusters get reallocated to something else,
and reading it returns another file's data. `deleteFile()` returns the `freeClusterChain`
status — which succeeded — so the user is told the delete worked.

### A4. `do_newdir()` ignores every write and returns SUCCESS unconditionally
**User-affecting. Severity: high.**

`newDirectory()` → `do_newdir()` (4364–4438) performs two sector writes, both unchecked:
the parent directory entry (4402) and the new directory's `.`/`..` cluster (4430). Both
are followed by read-back verifications (4405, 4434) whose results are *only printed to
DEBUG* — the verification is performed and then discarded. Line 4438 sets
`status := SUCCESS` on the path where all of this happened.

A directory creation that wrote nothing to the card reports success. With the driver's
default `DEBUG_MASK = 0`, nothing is printed either.

### A5. `do_newdir()` / `do_newfile()` use an unchecked `allocateCluster()` result
**User-affecting. Severity: high. Corruption path.**

```
4383        temp := allocateCluster(byte2clus(entry_address))
4384        clearCluster(temp)
...
4386    temp := allocateCluster(0)
4387    clearCluster(temp)
```

`allocateCluster()` returns `E_DISK_FULL` (-60) or `E_IO_ERROR` (-7) on failure. Neither
site checks. `clearCluster(-60)` computes `clus2sec(-60)` and issues `sec_per_clus`
sector writes at the resulting address — writing zeros somewhere unintended on the card.
`do_newfile()` has the identical defect at 4353–4354.

`do_create()` **does** guard this correctly at 3651–3654. The guard exists in the codebase;
it was simply never applied to the directory-creation paths. That makes this a
one-line-per-site fix with a proven local pattern.

### A6. The idle auto-flush discards every error it encounters
**User-affecting. Severity: high.**

`do_idle_flush()` (4149–4163) is the **automatic** background path by which buffered
writes reach the card after 200 ms of idle — for a caller that writes and doesn't
explicitly sync, this *is* the path their data takes.

```
4159    if h_flags[idx] & HF_DIRTY
4160      do_sync_h(idx)          ' status discarded
4162      updateFSInfo()          ' bSuccess discarded
```

Both results are dropped. There is no cog to return them to — the flush is initiated by
the worker itself — so no mechanism currently exists for the user to ever learn that a
background flush failed. The data is gone and every subsequent API call returns success.

This one needs a design decision, not just a check: the natural fix is a sticky
`flush_error` field the worker sets and a public accessor (or a bit in `cardWarnings()`),
so the next API call can surface it.

### A7. Worker stack-guard violation is detected and thrown away
**User-affecting. Severity: medium.**

`send_command()` (3017–3019):

```
    if NOT checkStackGuard()
      DEBUG[CH_API]("  [send_command] STACK OVERFLOW after cmd ", udec_(op_cmd))
```

The check runs after *every* command — good instinct — but the result only reaches DEBUG.
`status` is not altered and `set_error()` is not called. The driver's default is
`DEBUG_MASK = 0`. So the driver detects worker-cog memory corruption on every single
command and tells no one. `checkStackGuard()` is public (1525), so the user *can* poll it,
but nothing in the API indicates they need to.

### A8. `stop()` discards the unmount result
**User-affecting. Severity: medium.**

```
853      if flags & F_MOUNTED
854        send_command(CMD_UNMOUNT, 0, 0, 0, 0)     ' status discarded
857      COGSTOP(cog_id)
```

`stop()` returns nothing at all. This is the last opportunity for buffered data to reach
the card, and `do_unmount()` computes a perfectly good status (3446–3476) describing
whether the sync, close, and FSInfo update succeeded. It is discarded, then the worker cog
is stopped, making the failure permanently unrecoverable and unobservable.

### A9. `do_rename()` ignores the directory-entry write
**User-affecting. Severity: high.**
*Found 2026-08-01 by `tools/check_error_handling.sh` on its first run — not by this audit.*

```
4681        writeSector(bookmark >> SECTOR_SHIFT, BUF_DIR)
4682        cog_dir_sec[pb_caller] := temp_sec
4684        status := SUCCESS
```

The rewritten 8.3 entry is the *entire* product of a rename. Its write is unchecked and
`status := SUCCESS` follows unconditionally, so a rename that never reached the card
reports success and the file keeps its old name. Identical in shape to A3, and it fixes
the same way.

### A10. `do_movefile()` ignores the source-entry delete write
**User-affecting. Severity: high. Corruption path.**
*Found 2026-08-01 by `tools/check_error_handling.sh` on its first run — not by this audit.*

```
4783          writeSector(bookmark >> SECTOR_SHIFT, BUF_DIR)
4785          do_close()
4786          status := SUCCESS
```

This write is what marks the *source* entry deleted. Unchecked, and `status := SUCCESS`
follows. On failure the on-disk state is one file with two live directory entries in two
directories, sharing one cluster chain — and deleting either one frees clusters the other
still points at. This is A3's failure mode reached from the other direction.

> **Correction, 2026-08-02 (during «#28»).** This finding originally read "The move has
> already written the entry into the destination directory by this point." It has not.
> `do_newfile()` only stages `entry_buffer` and sets `F_NEWDIR`; the destination entry is
> actually written by the `do_close()` on the *following* line. The predicted failure — one
> file live in two directories over one chain — is real, but it is reached by the source
> delete failing and `do_close()` then adding the destination entry, not by a destination
> entry that already exists. The fix follows from the true order: abort before `do_close()`,
> and clear `F_NEWDIR` explicitly so that no *later* `do_close()` from an unrelated
> operation writes the stale destination entry. The source-delete-first ordering was kept
> deliberately — its abort path changes nothing on the card, and its unavoidable failure
> window leaks a recoverable chain rather than creating the duplicate.

**Not a defect — `do_attempt_high_speed()` (4992).** The script flags this bare
`writeSector()` too, and it is the one benign case: the method reads a sector, writes the
*same bytes* back, poisons the buffer and re-reads to prove the 50 MHz path works. A failed
write leaves the card holding the original data, so the read-back comparison is still
valid and still proves what it set out to prove. It takes an explicit
`' status intentionally ignored:` comment, not a fix.

---

## 4. Findings — Class B: the wrong error is reported

### B1. `searchDirectory()` reports an I/O failure as "file not found"
**User-affecting. Severity: high. This is the widest-blast-radius finding.**

`searchDirectory()` (4917–4996) returns a boolean. On a failed directory-sector read
(4961–4964) it returns `false` — the same value as a genuine "no such file":

```
4961    if readSector(n_sec, BUF_DIR) < 0
4962      DEBUG[CH_DIR]("  [searchDir] Directory read FAILED for sector ", udec_(n_sec))
4963      bFound := false
4964      quit
```

Mid-search sector advances (4994, `readNextSector`) swallow failures too — see C3.

Every path-based API sits on this function: `openFileRead`, `openFileWrite`,
`createFileNew`, `deleteFile`, `rename`, `moveFile`, `changeDirectory`, `compactFile`,
`fileFragments`. A transient SPI or card error during lookup is reported to the user as
`E_FILE_NOT_FOUND` (-40). The user retries, concludes the file is missing, and may recreate
or resync data based on a false premise.

The dangerous instance is the **existence check that fails open**. `do_create()` (3634),
`do_newfile()` (4342), and `do_newdir()` (4372) all treat `searchDirectory() == false` as
"name is available". If the read failed, the name may well be taken — and the driver
proceeds to write a second directory entry for a file that already exists, allocating a
fresh cluster chain while the original chain remains referenced by the original entry.
Two entries, two chains, one name.

Fix direction: `searchDirectory()` needs a tri-state result (found / not-found / I/O
error), or an out-parameter carrying the I/O status. The call sites that ask "does this
name exist?" before creating must fail closed on error.

### B2. `readFat()` returns stale data on failure, by design
**User-affecting. Severity: high.**

```
5011  if readSector((cluster >> 7 + fat_sec), BUF_FAT) < 0
5012    DEBUG[CH_SECTOR]("  [readFat] FAT read FAILED for cluster ", udec_(cluster))
5013    pFatEntry := @fat_buf                   '  Valid pointer but caller gets stale data
```

The comment states the defect. The caller receives a pointer into whatever the FAT buffer
last held and reads it as this cluster's chain link. `freeClusterChain()` (5229) walks
chains through this function — following a stale link means freeing clusters that belong
to a different file.

### B3. `start()` reports `E_NO_LOCK` when the cog launch fails
**Not user-affecting (diagnostic quality). Severity: low.**

```
838      if cog_id == -1
...
842        workerCogId := set_error(E_NO_LOCK)
```

Line 822 correctly uses `E_NO_LOCK` for an actual `LOCKNEW()` failure. Line 842 reuses it
for "no free cog," which is a different condition with a different remedy (free a cog vs.
free a lock). The two are indistinguishable to the caller. There is no `E_NO_COG` code
defined; adding one is the clean fix.

---

## 5. Findings — Class C: the error is unreachable by the caller

### C1. Short read on I/O error is indistinguishable from EOF
**User-affecting. Severity: high. Most likely to be hit in normal use.**

`do_read_h()` returns a partial count and no error on three distinct failure paths:

| Line | Failure | Action |
|------|---------|--------|
| 3805–3807 | data sector read failed | `quit` — return partial count |
| 3831–3833 | FAT chain read failed | `quit` — return partial count |
| 3836–3839 | unexpected end of chain | `quit` — return partial count |

`readHandle()` (982–996) only calls `set_error()` when the value is *negative* (994). A
partial count is positive, so `ERROR()` is never set.

The documented, natural read loop —

```spin2
repeat while (n := sd.readHandle(h, @buf, 512)) > 0
    process(@buf, n)
```

— terminates on a short read exactly as it would at EOF. **A file truncated by a card I/O
error is processed as a complete file, with no error indication anywhere in the API.**
The user cannot distinguish "read the whole file" from "the card failed 40% in," even by
polling `ERROR()`.

This is the finding I would fix first. The information exists in the driver at the moment
of failure and is simply not propagated. Options: return the negative error when zero
bytes were transferred and set a sticky per-handle error flag readable via a new
`handleError(handle)` accessor; or have `eofHandle()` become authoritative and document
that a short read must be followed by an `eofHandle()` check.

### C2. Partial write returns a count with no reason
**User-affecting. Severity: high.**

`do_write_h()` mirrors C1. It surfaces `E_IO_ERROR` only when *nothing* was written
(3961–3962); once any bytes have landed, a subsequent failure returns the partial count
(3963, 3975) with no error set. The metadata-region refusal (3950–3952) — which fires
precisely when the cluster chain walk has gone wrong — also just returns the partial
count. The most alarming internal condition in the write path is reported as a slightly
short write.

### C3. `readNextSector()` and `clearCluster()` have no return values
**User-affecting. Severity: medium (they are the mechanism behind B1, A4, A5).**

`readNextSector()` (5124–5155) has three failure paths (5135–5136, 5151–5152, 5154–5155),
all DEBUG-only. On failure the caller proceeds to interpret whatever the buffer holds —
stale directory data, or the zeros written at 5143–5148 — as real entries.

`clearCluster()` (5113–5122) ignores `writeSector()` (5121) and returns nothing, so a new
directory's cluster may retain old data while the driver reports the directory created.

### C4. APIs that never call `set_error()`
**User-affecting. Severity: medium.**

| Method | Line | Problem |
|--------|------|---------|
| `openDirectory()` | 1112–1113 | returns negative handle from `pb_data0`; `set_error()` never called |
| `readDirectoryHandle()` | 1123–1125 | returns 0 for **both** end-of-directory and any error |
| `readDirectory()` | 1140–1142 | same conflation |
| `closeDirectoryHandle()` | 1132 | status discarded entirely; method returns nothing |
| `freeSpace()` | 1204–1205 | returns 0 on failure — indistinguishable from "card full" |
| `readSectorsRaw()` | 1713–1716 | returns 0 on failure; partial count indistinguishable from short success |
| `writeSectorsRaw()` | 1727–1730 | same |

`freeSpace()` compounds it: `do_freespace()` (4480–4497) quits early on a FAT read failure
(4491–4492) and returns a **partial count**, and the dispatcher hardcodes
`pb_status := SUCCESS` (2737). A card error makes the volume look emptier than it is, with
no error anywhere — and an application that trusts that number to decide whether a write
will fit gets a wrong answer reported as fact.

### C5. `send_command()` doesn't set the error for the not-running case
**Not user-affecting on its own. Severity: low.**

```
2996  if cog_id == -1
2998    pb_data0 := E_NOT_MOUNTED
2999    status := E_NOT_MOUNTED
```

No `set_error()`. Callers that check the returned status recover it; the C4 methods, which
ignore status, leave `ERROR()` reporting something unrelated from an earlier operation.

---

## 6. Findings — Class D: semantics and documentation

### D1. `ERROR()` is sticky, but documented as per-operation
**User-affecting. Severity: high (documentation asserts what the code does not do).**

`set_error()` (2640–2647) is called **only on failure paths**. Nothing in the driver ever
writes `SUCCESS` into `last_error[]`, and there is no public method to clear it (confirmed
by search: no `clearError`, no `set_error(SUCCESS)` call site anywhere).

So `ERROR()` returns *the last error this cog ever hit*, not the status of the last
operation. The documentation at 1505–1509 says otherwise:

```
1506  '' Get last error for this cog - returns the error code from the most recent operation.
```

The natural idiom this invites —

```spin2
sd.writeHandle(h, @buf, 512)
if sd.ERROR() <> 0
    ' handle the error
```

— reports a stale failure from minutes earlier after a completely successful write. Every
error check written against the documented semantics is wrong.

Two coherent fixes: clear the slot at the start of each public call (true "last operation"
semantics, matches the docs, small cost per call), or keep sticky semantics, fix the
documentation, and add a `clearError()`. My recommendation is the **first** — it matches
what the documentation already promises and what users will assume from `errno`-style
APIs, and it makes the C4 gaps less dangerous because a stale value can no longer
masquerade as a fresh one.

### D2. `E_FILE_NOT_OPEN` is defined but never used
**Not user-affecting. Severity: informational.**

`E_FILE_NOT_OPEN` (-45) appears exactly once in the file — its own definition at line 196.
Operations on a closed handle return `E_INVALID_HANDLE` (-91) instead. Either wire it up
where it is the more precise answer, or retire it so the error table doesn't advertise a
code the driver never produces.

### D3. Async result retrieval doesn't verify the calling cog
**User-affecting under multi-cog use. Severity: medium.**

`startReadHandle()` / `startWriteHandle()` record `async_caller := COGID()` (1364, 1390),
but `getResult()` (1401–1421) and `cancelAsync()` (1423–1438) never check it. A second cog
calling `getResult()` consumes another cog's result, sets *its own* error slot from it, and
calls `LOCKREL()` on a lock it does not hold — releasing the API lock out from under the
true owner. `async_active` is a single global, so the API cannot represent per-cog async
state at all. At minimum this should return `E_NO_ASYNC_OP` when
`COGID() <> async_caller`; the documentation should state that async is single-cog-at-a-time.

---

## 6a. Findings — Class F: boolean returns where the reason is known but discarded

*Added 2026-07-31 at Stephen's prompt: "we moved to error codes a while ago — why is any
truthy left?"*

**The answer: the migration to error codes was applied at the public API boundary and did
not continue into the internal `PRI` layer.** Public methods return status codes. Below
them, the older boolean convention survives at 28 methods. The consequence is that errors
are *born* with full detail — `readSector()` distinguishes `E_TIMEOUT` from `E_CRC_ERROR`
from `E_BAD_RESPONSE` — then get **flattened to TRUE/FALSE** one or two layers up, and the
public method converts back to a generic code it had to guess at. The information is
destroyed in the middle of the stack, not at either end.

### F1. The project already solved this once, case-by-case
`initCard()` (5956) returns `bSuccess` but *also* sets a companion field
`last_init_error` (declared at 535, written at 6087 `E_NO_CARD`, 6091 `E_BAD_RESPONSE`,
6163 and 6179 `E_TIMEOUT`). Both callers propagate it — `do_mount():3328` and
`do_init_card_only():4733` both do `status := last_init_error`.

So the companion-field pattern is **already established project convention**, already
shipping, and already working in the highest-stakes path in the driver. It was applied
where the loss hurt most and not generalized. That is the actual history behind the
question.

### F2. Legitimate predicates — leave alone (9)
These answer a yes/no question about state and cannot meaningfully fail:
`isLeapYear` (2974), `validateHandle` (3059), `isFileOpenForWrite` (3072), `isFileOpenAny`
(5633), `isComplete` (1393), `isHighSpeedActive` (1932), `getLastCMD23Used` (2131),
`getCmd23Supported` (2154), `checkStackGuard` (1525 — boolean is right; §A7 is about
escalating what the *caller* does with it, not the return type).

### F3. Fallible operations flattened to boolean — reason lost (13)
**User-affecting. Severity: medium, high where marked.**

| Method | Line | What is lost |
|--------|------|--------------|
| `searchDirectory` | 4917 | **high** — I/O error vs not-found. This is finding B1 |
| `updateFSInfo` | 5157 | **high** — "no FSInfo to update" vs "write failed" |
| `writeAdvanceCluster` | 3845 | **high** — I/O failure vs disk full |
| `readDataRegister` | 7616 | timeout vs bad response vs card error |
| `readCSD` / `readCID` | 7672 / 7680 | same |
| `readSCR` / `readSDStatus` | 7941 / 7957 | same |
| `sendCMD6` | 7865 | same |
| `switchToHighSpeed` | 7909 | "card refused" vs "I/O failed" |
| `queryHighSpeedSupport` | 7875 | "not supported" vs "couldn't ask" |
| `do_check_hs_capability` | 4901 | same |
| `do_attempt_high_speed` | 4847 | same |

Two deserve calling out because the damage is already visible in the code:

**`updateFSInfo()` — the boolean is documented as causing pain.** `do_unmount()` carries a
comment at 3468–3470 explaining that it must gate on preconditions before trusting the
result, *because* FALSE conflates "nothing to update" with "the write failed":

```
  ' updateFSInfo returns FALSE for both "nothing to update" (no FSInfo sector
  ' / no cached free count) and "write failed" -- gate on those preconditions
  ' so a card without FSInfo does not get a spurious E_IO_ERROR on unmount.
```

That is a workaround for a return type, written into a comment, in the shipped code.

**`writeAdvanceCluster()` — feeds the partial-write path.** Both an I/O failure and a
genuine `E_DISK_FULL` return FALSE (3864, 3872), and `do_write_h()` turns both into the
same silent short write (finding C2). "Your card is failing" and "your card is full" are
completely different user stories and are currently indistinguishable.

### F4. Public capability queries conflate "no" with "couldn't ask" (3)
**User-affecting. Severity: medium.**
`attemptHighSpeed()` (1828), `checkCMD6Support()` (1840), `checkHighSpeedCapability()`
(1855) return FALSE both when the card genuinely lacks the capability and when the query
itself failed on I/O. A card with SPI trouble is reported as "high speed not supported,"
which sends the user diagnosing the wrong thing entirely.

### F5. The existing "hybrid" idiom is itself a trap
**User-affecting. Severity: medium. Found 2026-07-31 while evaluating F3/F4 fixes.**

`eofHandle()` (1040) and `isFileContiguous()` (1287) return TRUE/FALSE **or a negative
error code**. I initially recorded this as the better idiom to copy. It is not — it is a
latent defect in the shipped API, because a negative error code is *truthy* in Spin2:

```spin2
if sd.eofHandle(h)          ' h invalid -> returns -91 -> truthy -> reads as "at EOF"
    quit                    ' loop exits believing the file ended
```

`eofHandle()` on a bad handle reports "at EOF"; `isFileContiguous()` on an I/O error
reports "contiguous." Both are the *most dangerous* wrong answer for their respective
callers, and both are reachable through the documented API.

**And it is worse than truthiness — the values literally collide.** Verified against P2KB
(`p2kbSpin2Operators`): Spin2 logical and comparison operators "return -1 or 0", and `~~`
sets a variable to "-1 (all bits, TRUE)". **`TRUE` is -1, and `E_TIMEOUT` is -1.**
`eofHandle()` computes `is_eof := pb_data0 <> 0`, yielding -1 for "at EOF" — the same
32 bits as `E_TIMEOUT`. No comparison can separate them, in either direction. There is no
correct way to call this method today: `if sd.eofHandle(h)` treats every error as EOF, and
`if sd.eofHandle(h) < 0` treats the normal at-EOF case as an error.

The general statement: **three states (yes / no / could-not-determine) cannot be encoded in
one signed long** when `TRUE` = -1 overlaps the error range and `FALSE` = 0 overlaps
`SUCCESS`. The fix is to stop mixing the channels — a method returns a boolean *or* a status
code, never both, with failure detail in a companion field (the pattern `initCard()` already
uses). See plan §14.4.

**Consequence for the fix design:** any conversion that puts a negative code where a
boolean lived must account for Spin2 truthiness. `NOT` form breaks the same way —
`if NOT readCSD()` fires on failure today (FALSE), but with a status return `NOT SUCCESS`
is `NOT 0` = TRUE, so it would fire on *success*. There is no drop-in encoding that
preserves both senses. See plan §14 for the resulting approach.

---

## 7. Summary table

| # | Finding | Class | User-affecting | Severity |
|---|---------|-------|:--------------:|----------|
| C1 | Short read on I/O error looks like EOF | unreachable | yes | high |
| A2 | `allocateCluster()` ignores 4 FAT writes | dropped | yes | high |
| B1 | `searchDirectory()` I/O error → "not found"; create fails open | misreported | yes | high |
| A1 | `sync()` can never fail; `do_sync()` drops the entry | dropped | yes | high |
| A3 | `do_delete()` frees clusters after unchecked entry write | dropped | yes | high |
| A9 | `do_rename()` ignores the entry write, returns SUCCESS | dropped | yes | high |
| A10 | `do_movefile()` ignores the source-entry delete write | dropped | yes | high |
| A4 | `do_newdir()` ignores all writes, returns SUCCESS | dropped | yes | high |
| A5 | `clearCluster()` called with unchecked negative cluster | dropped | yes | high |
| A6 | Idle auto-flush discards all errors | dropped | yes | high |
| B2 | `readFat()` returns stale data on failure | misreported | yes | high |
| C2 | Partial write returns count, no reason | unreachable | yes | high |
| D1 | `ERROR()` sticky vs. documented per-operation | semantics | yes | high |
| A7 | Stack-guard violation → DEBUG only | dropped | yes | medium |
| A8 | `stop()` discards unmount status | dropped | yes | medium |
| C3 | `readNextSector()`/`clearCluster()` return nothing | unreachable | yes | medium |
| C4 | 7 APIs never call `set_error()`; `freeSpace()` partial-as-success | unreachable | yes | medium |
| D3 | Async ignores `async_caller`; wrong cog can `LOCKREL` | semantics | yes | medium |
| F3 | 13 fallible ops flattened to boolean (`updateFSInfo`, `writeAdvanceCluster`, …) | discarded | yes | medium |
| F4 | 3 capability queries conflate "no" with "couldn't ask" | misreported | yes | medium |
| F5 | `eofHandle()` / `isFileContiguous()` return TRUE/FALSE *or* an error code, and `TRUE` = `E_TIMEOUT` = -1 | misreported | yes | medium |
| B3 | `start()` reports `E_NO_LOCK` for cog-start failure | misreported | no | low |
| C5 | `send_command()` no `set_error()` when not running | unreachable | no | low |
| D2 | `E_FILE_NOT_OPEN` defined, never produced | semantics | no | info |

**21 findings are user-affecting** under the release-gate definition, out of 24 total.

*Count corrected 2026-08-01 while building the punch-list entries.* This line read "13 of
21" from the day Class F was added and was never reconciled with the table above it — the
table said 18 of 21 even then. Two things were wrong: the prose count was stale, and **F5
was never given a table row** despite its own section marking it user-affecting. Both are
fixed here. The per-finding `**User-affecting**` line in each section is the authority; the
table now agrees with it, finding for finding. Under the release gate each
must be fixed before or as part of the next release, or explicitly accepted by Stephen in
writing with the reason recorded.

---

## 8. Recommendations

### Tier 1 — silent corruption paths (fix first)
These write wrong data to the card while reporting success. All are small, local fixes
with an existing correct pattern elsewhere in the file to copy.

1. **A2** — check all four `writeSector()` calls in `allocateCluster()`; return `E_IO_ERROR`.
2. **A5** — guard `allocateCluster()` results in `do_newdir`/`do_newfile` exactly as
   `do_create()` does at 3651–3654.
3. **A3** — check the entry write in `do_delete()`; do not free the chain if it failed.
4. **A4** — check both writes in `do_newdir()`; make the read-back verifications
   authoritative instead of decorative.
5. **B2** — give `readFat()` a failure signal rather than a pointer to stale data.
6. **A9** — check the entry write in `do_rename()` before returning `SUCCESS`; same fix
   as A3.
7. **A10** — check the source-entry delete write in `do_movefile()`; on failure the file
   exists twice over one cluster chain, so do not report success.

### Tier 2 — errors the user cannot see (fix next)
6. **C1 / C2** — make short reads and partial writes distinguishable from clean ones.
   This is the largest behavioural change and deserves an explicit API decision; my
   recommendation is a per-handle sticky error plus a `handleError(handle)` accessor,
   because it doesn't change existing return-value contracts.
7. **D1** — clear `last_error[COGID()]` at the top of each public method so `ERROR()`
   means what the documentation says.
8. **B1** — tri-state `searchDirectory()`; make the pre-create existence checks fail closed.
9. **A6** — add a sticky worker-side flush error, surfaced on the next API call or via
   `cardWarnings()`.
10. **C4** — add the missing `set_error()` calls; give `freeSpace()` a way to report a
    failed scan instead of a wrong number.

### Tier 3 — correctness of reporting
11. **A1** — make `sync()` return `do_sync()`'s real status; stop clearing `F_NEWDIR` when
    the write failed. (Or, if `sync()` genuinely cannot fail by design, fix the docs —
    but the code shows it can.)
12. **A8** — give `stop()` a return status.
13. **A7** — escalate a stack-guard violation into a real error, not a DEBUG line.
14. **D3** — enforce `async_caller` in `getResult()`/`cancelAsync()`.
15. **B3 / C5 / D2** — add `E_NO_COG`, add the missing `set_error()`, resolve
    `E_FILE_NOT_OPEN`.

### Cross-cutting suggestion
Most of these share one root cause: **`writeSector()` and `allocateCluster()` return status
values that call sites are free to ignore, and Spin2 will not warn.** A grep-able
convention — every `writeSector(` call site either assigns its result or carries an
explicit `' status intentionally ignored: <reason>` comment — would make the remaining
gaps mechanically checkable, and would have caught A2, A3, A4, and A5 as a class rather
than one at a time. That check could join the four existing audit scripts.

### Test coverage note
None of the 464 regression tests currently fail because of these findings — they are all
failure-path defects, and the suites exercise the success paths on healthy cards. The
driver already has the error-injection hooks needed to test them
(`setTestForceReadError()`, `setTestForceWriteError()`, `setTestMaxClusters()`). Any fix
from Tier 1 or 2 should land with an injection test that fails before the fix, or the same
class of defect will return.

---

## 9. What is not wrong

To keep the report honest about proportion: the error *infrastructure* is well designed.
Per-cog error slots, a consistent negative-code scheme with meaningful tiers, an error code
for nearly every real condition, `set_error()` on the great majority of public methods,
and a genuinely careful `readSector()` with correct cache invalidation on every failure
path. The defects are gaps in applying a sound design — mostly unchecked `writeSector()`
call sites and boolean returns that cannot carry a third state — not a design that needs
replacing. Every Tier 1 fix has a working example of the correct pattern already in the
same file.
