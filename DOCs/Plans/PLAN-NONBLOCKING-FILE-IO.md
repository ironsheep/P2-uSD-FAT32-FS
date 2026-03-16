# Plan: Non-Blocking File I/O

## Motivating Principle: Cog Independence

Each P2 cog is a fully independent 350 MHz processor. A cog is NEVER slowed by other cogs — it runs at full speed unless it **voluntarily waits** on a shared resource. Every cycle spent in WAITATN is a cycle of a full-speed processor doing absolutely nothing: a 5ms SD write = 1.75 million wasted cycles on the calling cog.

The blocking API forces the caller cog to halt completely while the worker cog handles SD I/O. Both cogs are independent processors — there is no architectural reason the caller must stop. It stops only because our API gives it no choice.

## Problem Statement

Every filesystem API call currently blocks the calling cog until the operation completes:

```spin2
' Current (blocking) — caller cog HALTED for entire SD operation
bytes := sd.readHandle(handle, @buffer, 512)    ' 1.75M+ wasted cycles on caller cog
```

The caller issues a command via `send_command()`, which writes to the parameter block and then executes `WAITATN()` — the caller cog truly halts (zero instructions execute) until the worker signals completion via `COGATN`. Both cogs are independent 350 MHz processors, but the caller is forced to waste 100% of its capacity while the worker does SPI I/O.

For embedded applications — data loggers, sensor systems, control loops — this is not just inconvenient, it's architecturally wrong. A control loop running at 1 kHz cannot afford to halt its cog for a sector write. A sensor acquisition cog cannot miss samples because it's waiting for a directory update. The P2's multi-cog architecture exists precisely so that these activities can run in parallel — our blocking API defeats that.

## Current Architecture Review

### The Blocking Path

```
Caller Cog                              Worker Cog
───────────                             ──────────
send_command():
  locktry(api_lock)                     [polling pb_cmd]
  pb_caller := COGID()
  pb_param0..3 := params
  pb_cmd := CMD_xxx ──────────────────► sees pb_cmd != CMD_NONE
  WAITATN()  ← BLOCKED                 dispatches command
     │                                  does SPI I/O (5-50ms)
     │                                  pb_status := result
     │                                  pb_cmd := CMD_NONE
     │                                  COGATN(1 << pb_caller) ──► WAKE
     ▼
  Read pb_status
  lockrel(api_lock)
  return result
```

**Key constraint**: The `api_lock` is held for the entire duration. No other cog can issue an SD command while one is in flight. This serialization is fundamental — the worker cog is single-threaded and the SPI bus is single-master.

### What Blocking Gives Us

1. **Simple API** — call returns with result, just like a function
2. **Automatic serialization** — lock held = no races
3. **Error handling** — return value is the error code
4. **Zero hub bandwidth** — WAITATN doesn't touch hub RAM

---

## Design: Async API Layer

### Core Concept

Add a parallel set of async methods that **start** an operation without waiting for completion. The caller gets a "pending" token and can check/poll for completion later:

```spin2
' Async pattern — caller stays active
sd.startReadHandle(handle, @buffer, 512)    ' Returns immediately
repeat
  do_control_loop_work()                    ' Caller does useful work
  if sd.isComplete()                        ' Quick poll
    bytes := sd.getResult()                 ' Get the result
    quit
```

### Two-Phase Protocol

**Phase 1: Start** — Caller writes params to mailbox, sets `pb_cmd`, but does NOT call `WAITATN()`. Instead, releases immediately. The lock stays held to prevent other cogs from issuing commands.

**Phase 2: Check/Complete** — Caller polls `pb_cmd == CMD_NONE` (worker clears it when done). When done, reads result and releases lock.

```
Caller Cog                              Worker Cog
───────────                             ──────────
startReadHandle():
  locktry(api_lock)
  pb_caller := COGID()
  pb_param0..3 := params
  pb_cmd := CMD_xxx ──────────────────► sees pb_cmd != CMD_NONE
  return PENDING                        dispatches command
                                        does SPI I/O (5-50ms)
[caller does other work]                pb_status := result
                                        pb_cmd := CMD_NONE
isComplete():                           COGATN(1 << pb_caller)
  return (pb_cmd == CMD_NONE)

getResult():
  result := pb_status / pb_data0
  lockrel(api_lock)
  return result
```

### Important: Lock Remains Held

The `api_lock` stays acquired from `start*()` until `getResult()`. This means:
- **No other cog can issue SD commands** while an async operation is in flight
- The caller MUST eventually call `getResult()` to release the lock
- This is the same serialization as the blocking path — just with the caller doing work in between

This is correct behavior. The SPI bus can only serve one command at a time. The async API doesn't enable parallel SD operations — it enables the **caller** to overlap computation with SD I/O.

---

## API Design

### New Public Methods

```spin2
PUB startReadHandle(handle, p_buffer, count) : status
'' Begin an asynchronous read. Returns immediately.
'' Caller must call isComplete()/getResult() to get the data.
'' The api_lock is held until getResult() is called.
''
'' @param handle - Valid read handle
'' @param p_buffer - Pointer to destination buffer
'' @param count - Number of bytes to read
'' @returns status - PENDING (1) on success, negative error on precondition failure

PUB startWriteHandle(handle, p_buffer, count) : status
'' Begin an asynchronous write. Returns immediately.
''
'' @param handle - Valid write handle
'' @param p_buffer - Pointer to source data
'' @param count - Number of bytes to write
'' @returns status - PENDING (1) on success, negative error on precondition failure

PUB isComplete() : done
'' Check if the current async operation has completed.
'' Does NOT release the lock or consume the result.
'' Safe to call repeatedly in a polling loop.
''
'' @returns done - TRUE (-1) if complete, FALSE (0) if still in progress

PUB getResult() : result
'' Get the result of the completed async operation and release the lock.
'' MUST only be called after isComplete() returns TRUE.
'' After this call, the api_lock is released and new commands can be issued.
''
'' @returns result - Operation result (bytes read/written, or negative error)

PUB cancelAsync() : result
'' Cancel a pending async operation.
'' Waits for the worker to finish (cannot interrupt SPI mid-transfer),
'' discards the result, and releases the lock.
'' Use this if the caller decides it no longer needs the result.
''
'' @returns result - SUCCESS
```

### New Constants

```spin2
CON
  PENDING = 1    ' Returned by start*() methods to indicate operation launched
```

### Implementation Sketch

```spin2
DAT
  async_active    BYTE    0     ' TRUE when an async operation is in flight
  async_caller    BYTE    0     ' Cog ID of the async caller

PUB startReadHandle(handle, p_buffer, count) : status
  ' Validate preconditions (same as readHandle)
  if handle < 0 or handle >= MAX_OPEN_FILES
    return set_error(E_INVALID_HANDLE)
  if not (h_flags[handle] & HF_READ)
    return set_error(E_INVALID_HANDLE)

  ' Acquire lock
  repeat until locktry(api_lock)

  ' Set up command (same as send_command but no WAITATN)
  pb_caller := COGID()
  pb_param0 := handle
  pb_param1 := p_buffer
  pb_param2 := count
  pb_cmd := CMD_READ_H

  async_active := true
  async_caller := COGID()
  status := PENDING

PUB isComplete() : done
  done := (pb_cmd == CMD_NONE) and async_active

PUB getResult() : result
  if not async_active
    return set_error(E_NO_ASYNC_OP)

  ' Wait for completion if not already done (safety)
  repeat until pb_cmd == CMD_NONE

  result := pb_status
  if pb_status >= 0
    result := pb_data0    ' Byte count for reads/writes
  else
    set_error(pb_status)

  async_active := false
  lockrel(api_lock)
```

### Worker Side: COGATN Still Sent

The worker still sends `COGATN(1 << pb_caller)` on completion. For blocking calls, this wakes the caller. For async calls, the ATN flag gets set but the caller isn't sleeping on WAITATN — it'll see it next time it calls `POLLATN()` or just ignore it (checking `pb_cmd` via `isComplete()` is sufficient).

**Concern**: If the caller uses POLLATN for its own inter-cog signaling, the "stale" COGATN from the async completion could be consumed unexpectedly. This is a known P2 limitation — ATN is a single flag, not a queue.

**Mitigation**: Document that async callers should not rely on POLLATN for other purposes while an async SD operation is in flight. Or: don't send COGATN for async ops (worker checks a flag). But this complicates the worker for little benefit.

---

## Which Operations Should Be Async?

Not all operations benefit from async:

| Operation | Typical Time | Async Benefit? |
|-----------|-------------|----------------|
| readHandle (512 bytes) | 5-15ms | **Yes** — overlaps with processing |
| writeHandle (512 bytes) | 5-50ms | **Yes** — write-behind pattern |
| seekHandle | <1ms | No — too fast to matter |
| tellHandle | <1µs | No — instant (hub read only) |
| eofHandle | <1µs | No — instant |
| openFileRead | 5-20ms | Maybe — directory search time |
| createFileNew | 10-30ms | Maybe — allocate cluster + dir entry |
| closeFileHandle | 5-50ms | **Yes** — flush + dir update |
| mount/unmount | 50-500ms | **Yes** — but only done once |

### v1 Scope: Async Read and Write Only

**Decision**: v1 implements `startReadHandle` and `startWriteHandle` only.

**Rationale — where the wasted cycles actually live**: The embedded use case that motivates this feature is the steady-state loop — a sensor cog sampling at 1 kHz, a control loop maintaining a PID, a data logger streaming readings:

```
open file           ← once, at startup
repeat forever:
  acquire data      ← time-critical, can't miss
  write to file     ← 5-50ms blocking = disaster
  maybe read config ← periodic
close file          ← once, at shutdown (or never)
```

Read and write calls execute **thousands of times** inside the hot loop. Each blocking write wastes 1.75M+ cycles on the caller. Async read/write buys back those cycles on every single iteration. This is where essentially 100% of the reclaimed value lives.

**Why open doesn't need async**: Open is a transition operation — it happens once per file session. A 20ms blocking open at startup is irrelevant to a cog that's about to run a loop for hours. Furthermore, the caller usually can't do anything useful until it has the handle — you need the handle to start reading or writing. So the caller would start an async open, do some unrelated work, then retrieve the handle. Possible, but the use case is narrow and the payoff is a one-time savings rather than a recurring one.

**Why close doesn't need async (and the footgun it creates)**: Close is also a one-time transition cost — a 50ms blocking close at shutdown doesn't matter because the cog is done with its work. But beyond the low payoff, async close creates a dangerous anti-pattern: the caller typically **doesn't care about the close result** (the file is done), yet the two-phase protocol requires `getResult()` to release the api_lock. This creates a strong temptation to skip the `getResult()` call, which deadlocks the entire SD subsystem. For read/write, the `getResult()` contract is natural — the caller genuinely wants the byte count and error status. For close, it's pure ceremony to release the lock, and ceremony that users forget is a footgun.

If async close ever becomes needed in a future version, the right answer is likely a different pattern — something like `closeAsync()` that handles the lock release internally after the worker finishes, rather than forcing the caller through the two-phase start/getResult protocol. But that's a v2 concern.

**Summary**: v1 with just `startReadHandle` and `startWriteHandle` captures the hot-path wins where real cycles are being wasted, avoids adding async versions of operations that don't need them, and avoids the close footgun entirely.

---

## Why Auto-Lock-Release Does Not Work for Read/Write

The v1 scope discussion above proposes that a future async close could use auto-lock-release — the worker releases the lock internally after completing the close, so the caller never needs to call `getResult()`. A natural question is: why not use the same pattern for async read and write? If auto-release eliminates the "forgot to call getResult()" footgun for close, shouldn't it eliminate it for read/write too?

**The answer is no.** The lock in the two-phase protocol serves two distinct purposes, and auto-release violates the second one:

**Purpose 1 — During the operation**: The lock prevents another cog from issuing a command while the SPI bus is in use. This is the obvious purpose. Once the operation completes, this purpose is satisfied and the lock could theoretically be released.

**Purpose 2 — After the operation**: The lock prevents another cog from overwriting the mailbox result slots (`pb_status`, `pb_data0`) before the original caller reads them. This is the subtle but critical purpose.

The mailbox has a single set of result slots shared by all cogs. When the worker finishes a read:

```
Worker finishes:
  pb_status := bytes_read         (or negative error)
  pb_data0  := bytes_read
  pb_cmd    := CMD_NONE
```

If the worker auto-released the lock here, the following race becomes possible:

```
Cog A: startReadHandle() → worker completes → lock auto-released
Cog B: immediately acquires lock, issues deleteFile()
Cog B: worker writes pb_status := SUCCESS (0) for the delete
Cog A: getResult() → reads pb_status = 0 → thinks 0 bytes were read
```

Cog A asked for a read and got back the result of Cog B's delete. Silent data corruption — no error, no crash, just the wrong answer. The caller would believe the read returned 0 bytes (EOF) when the data was actually available.

**For close, auto-release works** precisely because the caller doesn't need to read the result. There is nothing in the mailbox that matters after a close. Whether it returned SUCCESS or E_IO_ERROR, the file is done and the handle is freed. The mailbox can safely be reused by the next cog.

**For read/write, the result is the entire point.** The caller needs the byte count. The caller needs the error status. The lock must stay held until the caller has consumed those values from the mailbox.

### Alternative Considered: Per-Cog Result Slots

One way to enable auto-release for all operations would be to replace the single `pb_status`/`pb_data0` with per-cog arrays:

```spin2
DAT
  pb_status_cog   LONG    0[8]    ' Result per cog
  pb_data0_cog    LONG    0[8]    ' Data per cog
```

The worker would write results to `pb_status_cog[pb_caller]`, and each cog would read only its own slot. No overwrite risk, so the lock could be released immediately after the worker finishes.

**Rejected because**:
- Adds 64 bytes of hub RAM (8 cogs x 2 LONGs) for a marginal benefit
- Complicates the worker's write path and every caller's read path
- Breaks the clean single-channel mailbox architecture that the blocking API uses
- The `getResult()` contract for read/write is **natural** — the caller genuinely wants the result, so the ceremony of calling `getResult()` is not ceremony at all, it's the purpose of the operation
- The footgun (forgetting `getResult()`) is specific to close, where the caller doesn't want the result. For read/write, forgetting `getResult()` means forgetting to use the data you asked for — a much more obvious bug

**Summary**: Auto-lock-release is the right pattern for close (v2) because the caller doesn't need the result. It is the wrong pattern for read/write (v1) because the lock protects the result channel, not just the SPI bus. The two-phase protocol for read/write is not a limitation — it's the correct design for operations where the caller needs the answer.

---

## Multi-Cog Considerations

### Lock Ownership

The `api_lock` is a hardware lock. Only the cog that acquired it can release it (`lockrel`). Since `startReadHandle()` acquires the lock and `getResult()` releases it, **both must be called from the same cog**. This is natural — the async pattern is "I started it, I'll finish it."

### What If the Caller Forgets to Call getResult()?

The lock is held forever. All other cogs trying to issue SD commands will spin on `locktry(api_lock)` indefinitely. This is a programmer error.

**Mitigation options**:
1. **Timeout in locktry loop** — other cogs detect the stuck lock and return E_TIMEOUT. Requires adding timeout to `send_command()`.
2. **Watchdog in worker** — if an async op completes and `getResult()` isn't called within N seconds, auto-release. Complicated and error-prone.
3. **Documentation** — state clearly that `getResult()` (or `cancelAsync()`) MUST be called. Programmer responsibility.

**Recommendation**: Option 3 for now. Option 1 as a future hardening pass.

### Mixing Blocking and Async

From the same cog, mixing is safe:
```spin2
sd.startReadHandle(h, @buf1, 512)    ' Async
process_data()
bytes := sd.getResult()              ' Complete async

bytes := sd.readHandle(h, @buf2, 512) ' Blocking — lock released, works fine
```

From different cogs, no problem — the lock serializes everything naturally.

---

## Alternative Considered: Callback Model

Instead of poll-based, the worker could call a user-registered callback method when the operation completes:

```spin2
sd.startReadHandle(handle, @buffer, 512, @my_callback)
' ... some time later, worker calls my_callback(result) ...
```

**Rejected because**:
- The callback executes in the **worker cog's context**, not the caller's. This means the callback shares the worker cog's stack and timing
- The callback would delay the worker from servicing the next command
- Method pointers from the caller's object run correctly (hub RAM), but the execution context is surprising
- The poll model is simpler and gives the caller full control over when it processes the result

---

## Interaction with Idle Task Execution (PLAN-IDLE-COG-TASK-EXECUTION)

If both features are implemented:

```
Worker Loop:
  1. Check POLLATN / pb_cmd → filesystem command? Execute it.
  2. No command → idle tasks registered? Run one idle task slice.
  3. Repeat.
```

When an async filesystem command is in flight, the worker is **busy executing it** — idle tasks don't run during that time (they can't, the cog is doing SPI I/O). Idle tasks only run when `pb_cmd == CMD_NONE`.

No conflict between the two features. They're complementary.

---

## Implementation Tasks

### Task 1: Core Async Infrastructure
- Add `async_active`, `async_caller` DAT variables
- Add `PENDING` constant
- Add `isComplete()`, `getResult()`, `cancelAsync()` methods

### Task 2: Async Read
- Implement `startReadHandle()` — same validation as `readHandle()`, then non-blocking send

### Task 3: Async Write
- Implement `startWriteHandle()` — same validation as `writeHandle()`, then non-blocking send

### Task 4: Worker COGATN Handling
- Decide whether to suppress COGATN for async ops or document the ATN flag behavior
- If using POLLATN-based wake (from idle task plan), this needs coordination

### Task 5: Regression Tests
- Async read: start, poll, getResult — verify data matches blocking read
- Async write: start, do computation, getResult — verify file contents
- Interleave: async op from cog A, blocking op from cog B (B should block on lock until A completes)
- Cancel: startReadHandle, cancelAsync, then blocking readHandle — should work normally

---

## Resolved Design Decisions

### D1: isComplete() uses hub read, not POLLATN

`isComplete()` reads `pb_cmd` from hub RAM (2-9 cycles hub access). POLLATN would be faster (2 cycles) but destructively consumes the ATN flag — if the caller uses ATN for its own inter-cog signaling, the async completion flag would interfere. Hub read is safe, simple, and the cycle difference is negligible.

### D2: No async versions of mount/unmount/open/close

All are transition operations (once per session or once per file), not hot-loop operations. The recurring cycle savings live in read/write. See "v1 Scope" section above for the full analysis, including why async close creates a dangerous footgun (temptation to skip `getResult()`, deadlocking the SD subsystem).

### D3: E_ASYNC_BUSY (-95) returned on double-start

If the caller calls `startReadHandle()` or `startWriteHandle()` while an async operation is already active (`async_active == true`), the method returns `E_ASYNC_BUSY` without acquiring the lock or issuing a command. The caller must call `getResult()` or `cancelAsync()` to complete the in-flight operation before starting a new one.

### D4: Any cog can use async

Once the filesystem is mounted, any cog can issue commands — blocking or async. There is no "mounting cog" with special privileges. The `api_lock` serializes access; it doesn't restrict which cog can use it. The only constraint is that `startReadHandle()` and `getResult()` must be called from the **same cog**, because `lockrel()` can only release a lock acquired by that cog. This is already documented in the Lock Ownership section.

### D5: Naming — start/isComplete/getResult

`startReadHandle` / `startWriteHandle` / `isComplete` / `getResult` / `cancelAsync`. This naming is most explicit about the lifecycle: you start an operation, check if it's complete, then get the result. Alternatives considered and rejected:
- `asyncRead`/`asyncPoll`/`asyncFinish` — "async" prefix is redundant on every call
- `beginRead`/`checkRead`/`endRead` — "begin/end" implies scoping (like a transaction), which is misleading

### D6: Gated behind SD_INCLUDE_ASYNC

The async API is gated behind `#ifdef SD_INCLUDE_ASYNC`. The 5 PUB methods and 2 error codes add API surface and a new usage pattern that most applications won't need. The blocking API remains the default. `SD_INCLUDE_ALL` enables it along with all other optional features.
