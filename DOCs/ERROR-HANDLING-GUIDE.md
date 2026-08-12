# SD Card Driver — Error Handling Guide

*micro_sd_fat32_fs.spin2*

**How to find out what went wrong, and what to do about it.**

This is the single reference for detecting and responding to errors from the driver. The
tutorial shows the happy path; this document covers everything after it.

---

## Table of Contents

1. [The One Rule](#the-one-rule)
2. [ERROR() — the per-cog outcome slot](#error--the-per-cog-outcome-slot)
3. [Return values that need a second question](#return-values-that-need-a-second-question)
4. [handleError() — why a read or write came up short](#handleerror--why-a-read-or-write-came-up-short)
5. [lastFlushError() — failures with no caller to return to](#lastflusherror--failures-with-no-caller-to-return-to)
6. [Operations that can partially succeed](#operations-that-can-partially-succeed)
7. [Booleans and status codes never mix](#booleans-and-status-codes-never-mix)
8. [Async is one operation, owned by one cog](#async-is-one-operation-owned-by-one-cog)
9. [Error code reference](#error-code-reference)
10. [Checklist by program shape](#checklist-by-program-shape)

---

## The One Rule

**Reading never changes state. Operations do.**

Every error accessor in this driver follows it. `ERROR()`, `handleError()` and
`lastFlushError()` can all be read as many times as you like without consuming anything;
each is overwritten only by the next operation that owns it, or — for `lastFlushError()` —
by an explicit clear.

That rule exists because the alternative generates support questions forever. If one
accessor cleared on read and another did not, every program would eventually read the
wrong one twice and get a lie the second time.

---

## ERROR() — the per-cog outcome slot

```spin2
status := sd.ERROR()
```

Each cog has its own slot, so cogs never overwrite each other's results.

**Write-on-exit.** Every method that issues a command records its outcome here on *every*
exit path — success as well as failure. So `ERROR()` describes **the operation you just
performed**, not the last failure since boot:

```spin2
  handle := sd.openFileRead(string("DATA.TXT"))
  if handle < 0
    debug("Open failed: ", sdec(sd.ERROR()))       ' describes THIS open
```

Before write-on-exit, a stale error from twenty operations ago could still be sitting in
the slot, and a program checking `ERROR()` after a successful call would act on it.

**Pure accessors are exempt, by design.** These read state and issue no command, so they
never touch the slot:

`fileName()`, `fileSize()`, `attributes()`, `volumeLabel()`, `sectorsPerCluster()`,
`clusterBytes()`, `getDate()`, `isComplete()`, `handleError()`, `lastFlushError()`, and
`ERROR()` itself.

Without that carve-out, diagnosing an error would erase it — a `debug(sd.fileName())`
between a failed `openFileRead()` and the `ERROR()` check would store `SUCCESS` over the
thing you were trying to look at.

---

## Return values that need a second question

Most methods return a status directly and need nothing more. A few return a **count** or a
**pointer**, and for those the return value alone cannot always distinguish success from
failure. Each has a designated second question:

| Method | Ambiguous return | Ask |
|---|---|---|
| `readHandle()` | a positive count shorter than requested | `handleError(handle)` |
| `writeHandle()` | a positive count shorter than requested | `handleError(handle)` |
| `readDirectoryHandle()` | `0` — end of directory *or* a failed read | `ERROR()` |
| `readDirectory()` | `0` — no such entry *or* a failed read | `ERROR()` |
| `readSectorsRaw()` | a count short of what was asked | `ERROR()` |
| `writeSectorsRaw()` | a count short of what was asked | `ERROR()` |
| `freeSpace()` | `0` — genuinely full *or* an incomplete scan | `ERROR()` |
| `eofHandle()` | `TRUE` — at EOF *or* the query failed | `ERROR()` |
| `isFileContiguous()` | `FALSE` — fragmented *or* the query failed | `ERROR()` |
| `attemptHighSpeed()` | `FALSE` — card declined *or* could not be asked | `ERROR()` |
| `checkCMD6Support()` | `FALSE` — SD 1.x *or* SCR unreadable | `ERROR()` |
| `checkHighSpeedCapability()` | `FALSE` — no such function *or* unaskable | `ERROR()` |

For the capability queries, a card that genuinely lacks the feature reports `SUCCESS` —
"no" is a real answer, not an error. Only "could not ask" sets an error code.

---

## handleError() — why a read or write came up short

```spin2
status := sd.handleError(handle)
```

`readHandle()` and `writeHandle()` return a byte **count**. A partial count is *positive*,
so this loop — the one the tutorial shows — ends identically at a clean end of file and on
a card failure part-way through:

```spin2
  repeat while (n := sd.readHandle(h, @buf, 512)) > 0
    process(@buf, n)
```

A file truncated 40% in is processed as a complete file. `handleError()` is what tells
them apart:

```spin2
  repeat while (n := sd.readHandle(h, @buf, 512)) > 0
    process(@buf, n)
  if sd.handleError(h) <> 0
    debug("Read failed part-way: ", sdec(sd.handleError(h)))
```

**Attributed to the handle**, so it is unambiguous with several files open, and it is not
disturbed by another cog's work.

**Write-on-exit, same as `ERROR()`.** Every `readHandle()`/`writeHandle()` on that handle
sets it — `SUCCESS` included — so it always describes the most recent one. A genuine end
of file reports `SUCCESS`.

**Read it before you close.** Closing returns the slot to the pool; a closed handle
reports `E_INVALID_HANDLE`, not a misleading `SUCCESS`.

### Read and write follow the same rule

| | Nothing transferred | Some bytes transferred, then failure |
|---|---|---|
| `readHandle()` | returns the **negative code** | returns the partial count |
| `writeHandle()` | returns the **negative code** | returns the partial count |

Once any byte has been transferred, both return the count rather than an error — otherwise
the caller loses track of how much of the file is valid, and `handleError()` carries the
reason. When *nothing* was transferred there is no count worth returning, so both return
the error code.

**This is why `0` is trustworthy.** A zero from `readHandle()` means a genuine end of file
and nothing else; a zero from `writeHandle()` means you asked it to write nothing. Both
`repeat while n > 0` and `repeat until n == 0` therefore stop for the right reason. Before
v1.7.0 a read that failed on its very first sector returned `0`, which made a dying card
indistinguishable from a finished file — see the migration guide.

---

## lastFlushError() — failures with no caller to return to

```spin2
status := sd.lastFlushError()
sd.clearFlushError()
```

If you write and then simply stop, the driver notices the card has been idle for 200 ms
and flushes your buffers on its own. **For a program that writes without explicit syncs,
that is the path the data actually takes.**

That flush is started by the worker cog itself, so there is no call of yours for it to fail
on. If it fails, nothing you call afterward will tell you: the data never reached the card,
and every later operation still reports success. Polling this is the only way to find out.

```spin2
  repeat idx from 0 to 999
    sd.writeHandle(handle, @data_point, DATA_SIZE)

    if idx // 100 == 99
      if sd.lastFlushError() <> 0
        debug("Background flush failed: ", sdec(sd.lastFlushError()))
        sd.clearFlushError()
        sd.syncHandle(handle)             ' the data is still buffered -- retry explicitly
```

It keeps the **first** failure, not the most recent — flushes run on a timer, so a later
clean one would otherwise erase the report before you looked. Reading does not clear it;
call `clearFlushError()` once handled.

**A failed flush leaves the handle dirty**, so the data is still in the driver's buffer and
a later `syncHandle()` or `closeFileHandle()` can still land it.

A flush cut short because one of your commands arrived is **not** a failure and is not
reported — the buffers stay dirty and the next idle window picks them up.

---

## Operations that can partially succeed

These do not complete atomically. Check the return, and understand what state a failure
leaves behind:

| Operation | On failure |
|---|---|
| `writeHandle()` | partial count if any byte was accepted, else the error code; the bytes counted but unflushed stay in the handle buffer |
| `readHandle()` | partial count if any byte moved, else the error code; position advanced only by what was delivered |
| `sync()` | continues through every open write handle, reports the **first** error; failed handles stay dirty, so a later `sync()` retries them |
| `syncHandle()` | the handle stays dirty; the data is still recoverable |
| `unmount()` / `stop()` | reports the failure; the shutdown still completes |
| `freeSpace()` | returns 0 rather than a plausible-but-wrong count |
| `deleteFile()` | the file is left **intact** rather than half-deleted |
| `rename()` / `moveFile()` | the original is left in place; the file never exists in two directories |
| `createFileNew()` | if the cluster chain could not be completed, no cluster is reported allocated |

The governing rule behind the last few: **a leak costs space, a cross-link costs data.** On
any partial failure the driver would rather strand a cluster than hand the same cluster to
two files.

---

## Booleans and status codes never mix

**A method returns either a boolean or a status code, never both.**

This is not a style preference. In Spin2 `TRUE` is `-1`, and `E_TIMEOUT` is also `-1` —
the same 32 bits. A method returning "TRUE, FALSE, or a negative error" has no correct
call form: `if sd.eofHandle(h)` treats every error as end-of-file, and
`if sd.eofHandle(h) < 0` treats the normal at-EOF case as an error. Two of the three
encodings collide and no comparison rescues it.

So the boolean methods return an honest boolean and the reason lives in `ERROR()`. Where a
boolean-returning method has an answer *and* a status to report, the answer is the return
value and the status reaches you through `ERROR()`.

`SUCCESS` is `0`, which is also `FALSE`. That is why a status-returning method is tested
with `<> SUCCESS`, never with `NOT`.

---

## Async is one operation, owned by one cog

There is a **single in-flight slot for the whole driver**, not one per cog. A second cog
starting an async operation while one is pending gets `E_ASYNC_BUSY` — promptly, even when
the two starts race.

The owning cog gets the same answer from its own **blocking** calls: `readHandle()`,
`closeFileHandle()`, `unmount()`, or any other blocking API called while that cog's async
operation is in flight returns `E_ASYNC_BUSY` instead of deadlocking on the non-re-entrant
lock. Collect with `getResult()` or cancel first. Info getters that return a value rather
than a status (`tellHandle()`, `fileSizeHandle()`) return the code itself; boolean and
count getters return their safe value (`eofHandle()` TRUE, counts 0) with `ERROR()`
holding `E_ASYNC_BUSY`.

`getResult()` and `cancelAsync()` also run the worker stack-guard check the blocking path
runs after every command: a violation reports `E_STACK_OVERFLOW`, overriding even a
successful result, because nothing a corrupted worker reported can be trusted.

The operation **belongs to the cog that started it**. Only that cog may collect it with
`getResult()` or drop it with `cancelAsync()`; another cog calling either gets
`E_NO_ASYNC_OP` and changes nothing. `isComplete()` reports `FALSE` in a cog that does not
own the operation — that cog has none.

The async calls release the API lock as their last act, so a cog collecting a result it
does not own would release a lock it never held, freeing the driver out from under the cog
that did.

---

## Error code reference

Codes are grouped in tiers so a range test tells you what kind of problem you have.

### Card level (-1 … -9)

| Code | Constant | Meaning |
|---|---|---|
| -1 | `E_TIMEOUT` | Card didn't respond in time |
| -2 | `E_NO_RESPONSE` | Card not responding |
| -3 | `E_BAD_RESPONSE` | Unexpected response from card |
| -4 | `E_CRC_ERROR` | Data CRC mismatch |
| -5 | `E_WRITE_REJECTED` | Card rejected write operation |
| -6 | `E_CARD_BUSY` | Card busy |
| -7 | `E_IO_ERROR` | General I/O error during read or write |
| -8 | `E_NO_CARD` | No card detected in slot |
| -9 | `E_BAD_PIN_CONFIG` | SPI pins too far apart |

### Filesystem level (-20 … -26)

| Code | Constant | Meaning |
|---|---|---|
| -20 | `E_NOT_MOUNTED` | Filesystem not mounted |
| -21 | `E_INIT_FAILED` | Card initialization failed |
| -22 | `E_NOT_FAT32` | Card not formatted as FAT32 |
| -23 | `E_BAD_SECTOR_SIZE` | Sector size not 512 bytes |
| -24 | `E_BAD_FSINFO` | FSInfo signatures invalid; the free-space hint cannot be updated |
| -25 | `E_BAD_CHAIN` | Cluster chain disagrees with the directory entry |
| -26 | `E_STACK_OVERFLOW` | Worker cog wrote past its stack — nothing it reports can be trusted |

`E_BAD_CHAIN` and `E_STACK_OVERFLOW` both mean *the driver's own state is wrong*, not that
the card failed. Treat them as reasons to stop and investigate, not to retry.

### File level (-40 … -65)

| Code | Constant | Meaning |
|---|---|---|
| -40 | `E_FILE_NOT_FOUND` | File doesn't exist |
| -41 | `E_FILE_EXISTS` | File already exists |
| -42 | `E_NOT_A_FILE` | Expected file, found directory |
| -43 | `E_NOT_A_DIR` | Expected directory, found file. `changeDirectory()` reports this only for a name that exists and is not a directory; a missing name (including the volume label, invisible to file APIs) reports `E_FILE_NOT_FOUND` |
| -44 | `E_DIR_NOT_EMPTY` | `deleteFile()` on a directory that still has entries — empty it first |
| -45 | `E_FILE_NOT_OPEN` | **Reserved** — never produced; a closed handle reports `E_INVALID_HANDLE` |
| -46 | `E_END_OF_FILE` | Read past end of file |
| -47 | `E_FILE_OPEN` | `deleteFile()` on a file that still has an open handle — close it first |
| -60 | `E_DISK_FULL` | No free clusters. A create that had to grow its directory reports this only for a genuinely full disk — a physical failure during the extend reports its own code (e.g. `E_IO_ERROR`) |
| -61 | `E_NO_CONTIGUOUS_SPACE` | No contiguous run of sufficient length |
| -62 | `E_FILE_OPEN_FOR_COMPACT` | File is open; cannot compact |
| -63 | `E_VERIFY_FAILED` | Read-back verification failed after compact |
| -64 | `E_NO_LOCK` | Couldn't allocate hardware lock |
| -65 | `E_NO_COG` | No free cog to run the worker (all eight in use) |

### Handle level (-90 … -96)

| Code | Constant | Meaning |
|---|---|---|
| -90 | `E_TOO_MANY_FILES` | All file handles in use |
| -91 | `E_INVALID_HANDLE` | Handle out of range, not open, or closed |
| -92 | `E_FILE_ALREADY_OPEN` | File already open for writing (single-writer policy) |
| -93 | `E_NOT_A_DIR_HANDLE` | Wrong handle type for the operation |
| -94 | `E_INVALID_PARAM` | Parameter value out of range |
| -95 | `E_ASYNC_BUSY` | An async operation is already in flight — from a second `start*()`, or from any blocking API call by the cog that owns it |
| -96 | `E_NO_ASYNC_OP` | No async operation, or it belongs to another cog |

---

## Two refusals that mean "do something first", not "this failed"

`E_DIR_NOT_EMPTY` (-44) and `E_FILE_OPEN` (-47) are both returned by `deleteFile()`, and
both are recoverable by the caller. Treating them as ordinary failures produces programs
that give up where they should take one more step.

```spin2
    result := sd.deleteFile(@name)
    if result == sd.E_FILE_OPEN
        sd.closeFileHandle(handle)                  ' the handle you still hold
        result := sd.deleteFile(@name)
    elseif result == sd.E_DIR_NOT_EMPTY
        ' remove the contents first -- children before parents, no recursion in the driver
        result := emptyThenDelete(@name)
    if result <> sd.SUCCESS
        debug("delete failed: ", sdec(result))
```

Both refusals exist because the old permissive behavior corrupted state silently: deleting
a populated directory stranded every child's cluster chain as unreachable space, and
deleting a file with an open handle let a later idle flush write that handle's stale
buffer into a cluster that had already been freed and reallocated. A refusal you can act
on is strictly better than a success that quietly damages the volume.

## Checklist by program shape

**Reading a file to the end.** Stop the loop on `<= 0`, then check `handleError()` after
it. The `<= 0` catches a failure that transferred nothing; `handleError()` catches the
harder case — a failure *part-way* through, which returns a positive count that looks like
a short final chunk.

**Writing a long run without syncing.** Poll `lastFlushError()` periodically. Nothing else
will ever tell you a background flush failed.

**Writing records that must all land.** Compare `writeHandle()`'s return against what you
asked for, not against zero. Check `handleError()` on any shortfall.

**Sizing a write against free space.** `freeSpace()` returns 0 with an error rather than a
partial count, so treat 0 as "ask why" rather than "the card is full."

**Enumerating a directory.** Check `ERROR()` after the loop — `0` ends the loop for both
"no more entries" and "could not read the directory."

**Shutting down.** Check `stop()`'s return. It performs the final unmount and then halts
the worker, after which no retry is possible and nothing can report what happened.

**Running on several cogs.** Each cog has its own `ERROR()` slot. Per-handle errors are
attributed to the handle rather than the cog, so they survive another cog's activity.

**Using async.** One operation at a time for the whole driver, owned by the cog that
started it.
