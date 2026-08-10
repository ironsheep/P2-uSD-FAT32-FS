# Migration Guide -- P2-uSD-FAT32-FS v1.7.0

If you have code written for v1.6.x, this guide covers what changed in v1.7.0.

Most programs need no changes. v1.7.0 is about making failures visible that the driver
previously computed and discarded, so the majority of the work is additive: new accessors,
new error codes, and return values on methods that had none. The items below are the ones
that can affect existing code.

For the full picture of how error reporting now works, see
[ERROR-HANDLING-GUIDE.md](ERROR-HANDLING-GUIDE.md).

---

## 1. `ERROR()` now describes the last operation, not the last failure

**Before:** the slot held the most recent *failure*, and a successful call left it alone.
A program that checked `ERROR()` after a call that succeeded could act on an error from
twenty operations earlier.

**Now:** every method that issues a command records its outcome on every exit — success as
well as failure. `ERROR()` after a call describes **that call**.

**What to change:** if you used `ERROR()` as a "has anything failed since I last looked"
flag, that no longer works — a later success overwrites it. Check it immediately after the
operation you care about.

Pure accessors are exempt and never touch the slot: `fileName()`, `fileSize()`,
`attributes()`, `volumeLabel()`, `sectorsPerCluster()`, `clusterBytes()`, `getDate()`,
`isComplete()`, `handleError()`, `lastFlushError()`, and `ERROR()` itself.

---

## 2. `eofHandle()` and `isFileContiguous()` return booleans only

These used to return `TRUE`, `FALSE`, **or** a negative error code. That encoding cannot
work in Spin2: `TRUE` is `-1` and `E_TIMEOUT` is also `-1`, so "at end of file" and "the
card timed out" were the same 32 bits.

**Any code testing these was already wrong on the error path.** `if sd.eofHandle(h)`
treated every error as end-of-file; `if sd.eofHandle(h) < 0` treated the normal at-EOF case
as an error. There was no correct call form.

**Now:**

| Method | On a failed query | Why that direction |
|---|---|---|
| `eofHandle()` | returns `TRUE` | a read-until-EOF loop stops instead of spinning on a card that is not answering — and it is what the old code effectively did, since every negative is non-zero and therefore truthy |
| `isFileContiguous()` | returns `FALSE` | the opposite direction, and the safe one here: a truthy error used to read as "yes, contiguous" and would let a caller skip a compaction the file actually needed |

`ERROR()` distinguishes in both cases.

**What to change:** `if sd.eofHandle(h)` — the idiom the tutorial always showed — is now
correct for the first time and needs no change. If you wrote a negative test to work
around the old encoding, remove it.

---

## 3. Methods that gained a return value

| Method | Was | Now |
|---|---|---|
| `stop()` | returned nothing | returns the final unmount's status |
| `closeDirectoryHandle()` | returned nothing | returns `SUCCESS` or a negative code |

Spin2 allows calling a value-returning method as a bare statement, so **existing calls
compile and behave exactly as before**. Adopt the return values where the outcome matters.

`stop()` is worth adopting: it is the last chance buffered data has to reach the card, and
it halts the worker cog immediately afterward, after which no retry is possible and nothing
can report what happened.

---

## 4. `sync()` now does what its name says

**Before:** `sync()` flushed one narrow piece of internal state — a pending directory
entry that only a mid-flight move operation could stage — and nothing else. Buffered file
data was untouched. The documentation said "flush all pending writes"; the code did not.

**Now:** `sync()` flushes **everything**: every open write handle's buffered data and
directory entry, then the FSInfo free-space sector. It is the same persistence pass
`unmount()` runs, without unmounting — call it before power-down or card removal.

Two consequences for existing code:

- **It takes real time now.** With dirty handles open, `sync()` performs card writes
  where it used to return immediately. Keep it out of tight loops; use `syncHandle()`
  to checkpoint a single file.
- **It can fail now.** It reports the first error encountered (it still attempts every
  handle). Failed handles stay dirty, so a later `sync()` retries them. The old method
  documented failure codes it could never actually produce.

---

## 5. `freeSpace()` returns 0 instead of a partial count

**Before:** if the FAT scan hit a read error part-way, the count accumulated so far was
returned as though it were the answer — a number that is simply too low, delivered as fact.
An application sizing a write against it got a wrong answer with no indication.

**Now:** an incomplete scan returns 0 and sets `ERROR()`.

**What to change:** treat `0` as "ask `ERROR()` why" rather than "the card is full."

---

## 6. New error codes

All additive except where noted.

| Code | Constant | Raised by |
|---|---|---|
| -24 | `E_BAD_FSINFO` | FSInfo signatures invalid; the free-space hint cannot be updated |
| -25 | `E_BAD_CHAIN` | a cluster chain that disagrees with the directory entry |
| -26 | `E_STACK_OVERFLOW` | the worker cog wrote past its stack |
| -44 | `E_DIR_NOT_EMPTY` | `deleteFile()` on a directory that still contains entries |
| -47 | `E_FILE_OPEN` | `deleteFile()` on a file that still has an open handle |
| -65 | `E_NO_COG` | `start()` when no cog is free |

**One changed return:** `unmount()` on a card with a corrupt FSInfo sector now reports
`E_BAD_FSINFO` where it previously reported `E_IO_ERROR`. Both are negative, so a
success/failure test is unaffected; only code matching the exact code needs attention.

`E_NO_COG` replaces a misuse of `E_NO_LOCK` at `start()`. The lock was fine — there was no
cog free. Different condition, different remedy.

`E_FILE_NOT_OPEN` (-45) is now documented as **reserved**. It has never been produced by
any code path; a closed handle reports `E_INVALID_HANDLE`. The constant stays defined so
existing references still compile.

### `deleteFile()` now refuses two cases it used to accept

These two are **not** additive, and they are the only behavior changes in this section.
Code that relied on either old behavior will see a new negative return.

**A non-empty directory is refused (`E_DIR_NOT_EMPTY`, -44).** `deleteFile()` previously
deleted a populated directory: it marked the entry deleted and freed the directory's own
cluster chain, but every child's chain was left allocated and unreachable. The space was
gone until the next format. The delete now walks the directory to its terminator, ignoring
`.`, `..` and deleted entries, and refuses if anything remains.

Migration — empty it first, children before parents:

```spin2
    ' Old: one call, silent space leak on a populated directory
    sd.deleteFile(@"LOGS")

    ' New: remove the contents, then the directory
    if sd.changeDirectory(@"LOGS") == sd.SUCCESS
        sd.deleteFile(@"DATALOG.CSV")
        sd.changeDirectory(@"..")
    result := sd.deleteFile(@"LOGS")            ' E_DIR_NOT_EMPTY if anything is left
```

There is deliberately **no recursive delete**. A force/recursive variant is a separate,
explicitly named API and is not part of this release.

**A file with an open handle is refused (`E_FILE_OPEN`, -47).** Deleting a file that a
handle still held used to succeed, after which the driver's idle flush could write that
handle's stale buffer into a cluster that had been freed and possibly reallocated to
another file. The delete now scans the handle table and refuses.

Migration — close, then delete:

```spin2
    ' Old: delete while the handle was still open
    sd.deleteFile(@"WORK.TXT")

    ' New
    sd.closeFileHandle(handle)
    result := sd.deleteFile(@"WORK.TXT")        ' E_FILE_OPEN if any handle is still open
```

If you are deleting a file you may have open elsewhere, treat `E_FILE_OPEN` as "close it
and retry", not as a hard failure.

---

## 7. New accessors

| Method | Answers |
|---|---|
| `handleError(handle)` | why the last read or write on that handle came up short |
| `lastFlushError()` | whether an automatic background flush has failed |
| `clearFlushError()` | clears the above |

Both accessors follow the same rule as `ERROR()`: reading never clears them.

`handleError()` is the one most programs should adopt. `readHandle()` returns a byte count,
and a partial count is *positive*, so the documented read loop ends identically at a clean
end of file and on a card failure part-way through — a file truncated 40% in is processed
as a complete file. See the guide for the checked form of the loop.

---

## 8. Async is enforced as single-cog

`getResult()` and `cancelAsync()` now return `E_NO_ASYNC_OP` when called from a cog that
did not start the operation, and `isComplete()` reports `FALSE` there.

**This rejects only calls that were already incorrect.** Those methods release the API lock
as their last act, so a cog collecting a result it did not own was releasing a lock it never
held, freeing the driver out from under the cog that did. No correct consumer is affected.

---

## 9. A read or write that transferred nothing returns its error, not `0`

**This is the one item in this release that can change the behavior of a working loop.**

**Before:** a `readHandle()` that failed on its very first sector returned `0` — the same
value that means end of file. A file on a dying card was processed as a complete file, with
no indication anything went wrong. `writeHandle()` mostly returned the error code in that
situation, but three of its failure paths returned `0` as well, so it disagreed with itself.

**Now:** whenever nothing at all was transferred, both return the negative error code. `0`
from `readHandle()` means a genuine end of file and nothing else. A failure *part-way*
through still returns the partial count, so you never lose track of how much of the file is
valid — that case is what `handleError()` is for, and it has not changed.

**What to check in your code.** A read loop that stops on `> 0` or `<= 0` is already
correct and needs no change:

```spin2
  repeat while (n := sd.readHandle(h, @buf, 512)) > 0     ' fine
  repeat
    n := sd.readHandle(h, @buf, 512)
    if n <= 0                                             ' fine
      quit
```

A loop that stops **only** on exactly zero will no longer terminate on a persistent failure:

```spin2
  repeat
    n := sd.readHandle(h, @buf, 512)
    if n == 0                                             ' CHANGE THIS to  n <= 0
      quit
```

Also check accumulators. `total += sd.readHandle(...)` will now subtract on failure rather
than add zero, so a total that used to come out merely short can come out wrong. Guard the
call, or check `total` against the file size afterward.

Our own `SD_example_multicog.spin2` had the `== 0` form and was corrected in this release.

---

## 10. `SD_INCLUDE_TEST_HOOKS`

Fault injection — making a named sector's read or write fail on purpose — lives behind its
own feature flag. It is enabled by `SD_INCLUDE_ALL` and deliberately **not** by
`SD_INCLUDE_DEBUG`.

A debug build is a legitimate thing to ship; diagnostic getters are how you get field data
back from a card that misbehaves in the wild. The test hooks are not shippable — they
include methods whose whole purpose is to corrupt the next write. Keeping them separate
means turning on field diagnostics never turns on fault injection.

If you build with `SD_INCLUDE_ALL` and ship the result, move to the specific
`SD_INCLUDE_*` flags you actually use.

---

## Summary: what actually breaks

Almost nothing. In order of likelihood:

1. A read loop that stops **only** on `n == 0` (§9) — it will no longer terminate on a
   persistent read failure. This is the one change that can hang a working program, and it
   is a one-character fix to `n <= 0`.
2. Using `ERROR()` as a sticky "did anything fail" flag — it is now overwritten by success.
3. `sync()` in a timing-sensitive path (§4) — it now performs real card writes where it
   used to return immediately. The result is what the documentation always promised, but
   the latency is new.
4. Matching `unmount()`'s exact error code on a corrupt-FSInfo card.
5. Treating `freeSpace() == 0` as "card full" rather than checking `ERROR()`.
6. A negative test on `eofHandle()` or `isFileContiguous()` written to work around the old
   mixed encoding.

Everything else in this release is additive.
