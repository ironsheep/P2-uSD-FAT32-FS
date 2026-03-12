# Plan: Idle Worker Cog Task Execution

## Motivating Principle: Cog Independence

Each P2 cog is a fully independent 350 MHz processor. A cog is NEVER slowed by other cogs — it runs at full speed unless it **voluntarily waits** on a shared resource. This means idle cog cycles are genuinely wasted — they don't benefit any other cog. A cog polling `pb_cmd` in a tight loop is a 350 MHz processor burning millions of cycles per millisecond for zero useful output.

## Problem Statement

The SD driver's worker cog is a dedicated hardware resource (one of eight P2 cogs) that spends nearly all its time idle. The current idle loop:

```spin2
' Line 2114-2115 in micro_sd_fat32_fs.spin2
repeat until (cur_cmd := pb_cmd) <> CMD_NONE
```

This burns 100% of a 350 MHz processor on hub RAM polling. Between filesystem operations — which take milliseconds each and may be separated by seconds or minutes — the cog does nothing useful. Because cogs are independent, these wasted cycles cannot benefit any other cog. They are simply gone.

With only 8 cogs available, dedicating one exclusively to filesystem operations that occupy <1% of its time is a significant resource cost. If a caller cog needs periodic sensor polling or LED heartbeat, it must either do that work itself (consuming its own cycles) or dedicate yet another cog. The worker's idle cycles could absorb that work instead — freeing the caller cog to focus on its primary task at full speed.

The question: can we let caller cogs register background work for the worker to execute during idle time, while maintaining filesystem operation priority?

## Compiler and Language Status

- **pnut-ts compiler version**: v53
- **Driver version directive**: currently `{Spin2_v46}`, can be bumped to `{Spin2_v47}` or later
- **All TASK* features available**: TASKSPIN, TASKNEXT, TASKSTOP, TASKHALT, TASKRESUME, TASKCHK, TASKID, TASKWAIT, NEWTASK, THISTASK

## P2 Capabilities Reference

### Spin2 TASK System (requires {Spin2_v47}+)

Cooperative multitasking **within a single cog** — up to 32 tasks share the cog's execution time via explicit yielding:

| Method | Purpose |
|--------|---------|
| `TASKSPIN(id, method(params), @stack)` | Start task. ID 0-31 or NEWTASK. |
| `TASKNEXT()` | Yield to next task (~20-40 cycles). |
| `TASKSTOP(id)` | Permanently terminate task. |
| `TASKHALT(id)` | Pause task (state preserved). |
| `TASKRESUME(id)` | Resume halted task. |
| `TASKCHK(id)` | Status: 0=unused, 1=running, 2=halted. |
| `TASKID()` | Get current task's ID. |
| `TASKWAIT(condition)` | Yield until condition is true. |

Key characteristics:
- Each task has its own stack and program counter
- All tasks share the same cog registers, pins, and streamer
- Round-robin scheduling — tasks execute in order
- **Cooperative only** — a task runs until it explicitly yields via `TASKNEXT()` or `TASKWAIT()`
- Context switch: ~20-40 clock cycles

### Method Pointers in Spin2

```spin2
handler := @MethodName              ' Get method address
handler := @obj.MethodName          ' Child object method
result := handler(arg1, arg2)       ' Call through pointer
' Must store in LONG (not BYTE/WORD). No compile-time type checking.
```

### POLLATN / COGATN

```spin2
result := POLLATN()                 ' Non-blocking ATN check (2-9 cycles)
COGATN(1 << cog_id)                ' Send attention to specific cog
```

### POLLCT / ADDCT

```spin2
ADDCT1(target_count)                ' Arm CT1 event at target count
if POLLCT1()                        ' Non-blocking check: has CT1 fired?
```

---

## Design Options

### Option A: TASKSPIN with TASKHALT/TASKRESUME (Full Task System)

Use the Spin2 TASK system directly. The filesystem worker runs as Task 0 (the main entry point). Background methods are launched as additional tasks via TASKSPIN. When a filesystem command arrives, background tasks are halted; when the command completes, they're resumed.

```
Worker Cog Task Layout:
  Task 0 (main): Filesystem dispatcher
    → Monitors pb_cmd / POLLATN
    → On command: TASKHALT all background tasks, execute command, TASKRESUME all
    → When idle: TASKNEXT() to yield to background tasks

  Task 1: User background method #1 (via TASKSPIN)
    → Runs its method, calls TASKNEXT() periodically to cooperate
  Task 2: User background method #2
    → Same pattern
  ...up to Task N
```

**Registration API**:
```spin2
PUB registerIdleTask(p_method, p_stack, stack_size, user_param) : task_id
'' Register a background method. Caller provides stack memory.
'' Method signature: PRI myMethod(param)  — runs as a TASKSPIN task.
'' Method MUST call TASKNEXT() periodically (cooperative yielding).

PUB unregisterIdleTask(task_id) : result
'' Permanently stop and remove a background task via TASKSTOP.
```

**Worker dispatch loop**:
```spin2
PRI fs_worker() | cur_cmd, idx
  repeat
    ' Check for filesystem command
    if POLLATN()
      if (cur_cmd := pb_cmd) <> CMD_NONE
        ' === HALT all background tasks ===
        repeat idx from 0 to MAX_IDLE_TASKS - 1
          if task_ids[idx] <> 0
            TASKHALT(task_ids[idx])

        ' Execute filesystem command
        dispatch_command(cur_cmd)
        pb_cmd := CMD_NONE
        COGATN(1 << pb_caller)

        ' === RESUME all background tasks ===
        repeat idx from 0 to MAX_IDLE_TASKS - 1
          if task_ids[idx] <> 0
            TASKRESUME(task_ids[idx])

    ' Yield to background tasks (if any are running)
    TASKNEXT()
```

**Pros**:
- **True concurrent execution** — background tasks maintain their own execution state (program counter, local variables, stack) across yields. A task that's midway through a computation picks up exactly where it left off
- **Clean halt/resume** — TASKHALT/TASKRESUME is a hardware-supported mechanism. Halting a task is instant and preserves its full state. No need for the task to be at a "safe" point
- **Tasks can be long-running** — a background task can run a loop that takes minutes or hours. It just needs periodic TASKNEXT() calls. Between yields, it can do arbitrarily complex work
- **Multiple tasks truly interleave** — if 3 background tasks are registered, they all make progress in round-robin, not just one at a time
- **Task lifecycle management** — TASKCHK lets you check if a task is alive, halted, or stopped. TASKSTOP for permanent removal
- **Standard P2 idiom** — uses the language's built-in task system as designed

**Cons**:
- **Each task needs dedicated stack memory** — caller must provide a LONG array. Typical: 64-128 LONGs (256-512 bytes) per task. For 4 tasks: 1-2 KB of hub RAM consumed by stacks alone
- **Background methods MUST call TASKNEXT()** — a method that never yields starves both the filesystem dispatcher and all other tasks. The driver cannot enforce this. A misbehaving task monopolizes the cog until it yields
- **Filesystem latency = time until background task yields** — if a task does 5ms of work between TASKNEXT() calls, filesystem response has 0-5ms added latency. The driver halts tasks when a command arrives, but the halt only takes effect at the next TASKNEXT() — it doesn't preempt mid-execution
- **Version bump required** — must change `{Spin2_v46}` to `{Spin2_v47}`. Pnut-ts v53 supports this, but it's a user-visible change
- **Stack sizing is the caller's responsibility** — too small = stack overflow with no recovery. The driver can't validate stack adequacy. Overflow corrupts adjacent hub RAM silently
- **Crash isolation: none** — if a background task corrupts its stack or enters an infinite non-yielding loop, the entire worker cog is compromised. The filesystem becomes unresponsive. Only recovery: `cogstop` + `cogspin` restart of the worker
- **Registration complexity** — caller must allocate stack memory, know the right size, and pass it. More parameters than other options
- **TASKHALT during SPI is safe, but TASKRESUME timing matters** — halted tasks don't touch pins, so SPI is safe. But if a task was using GETCT for timing, the halt duration creates a time gap the task may not expect

---

### Option B: TASKSPIN without Halt (Cooperative Priority)

Like Option A but simpler: don't halt/resume background tasks during filesystem commands. Instead, rely entirely on cooperative yielding. The filesystem task and background tasks all call TASKNEXT() and share the cog cooperatively. The filesystem task checks `pb_cmd` on every wake.

```spin2
PRI fs_worker()
  repeat
    if (cur_cmd := pb_cmd) <> CMD_NONE
      dispatch_command(cur_cmd)
      pb_cmd := CMD_NONE
      COGATN(1 << pb_caller)
    TASKNEXT()                          ' Let background tasks run
```

Background tasks:
```spin2
PRI background_method(param)
  repeat
    do_some_work()
    TASKNEXT()                          ' Yield back to dispatcher
```

**Pros**:
- **Simplest TASK-based design** — no halt/resume bookkeeping
- **Background tasks are peers** — all tasks cooperate equally
- **Less code in the dispatcher** — no halt/resume loops

**Cons**:
- **Filesystem latency is worse** — without halting background tasks, a filesystem command must wait for ALL other tasks to yield before the dispatcher gets its next turn. With N tasks, worst case: the dispatcher checks pb_cmd, then waits for N task yields before checking again
- **No priority** — background tasks get equal CPU time with the filesystem. A user who registers 4 chatty tasks gives the filesystem only 1/5 of the cog's time
- **Same stack/yield/crash cons as Option A** — caller-provided stacks, mandatory TASKNEXT(), no crash isolation
- **Wrong mental model** — the filesystem is the primary function of this cog. Background tasks are a bonus. This option treats them as equals, which will surprise users when filesystem performance degrades proportionally to the number of background tasks

---

### Option C: Polled Dispatch (Method Pointer Table, No TASK System)

No TASK system. The worker cog's idle loop directly calls registered methods in round-robin order, with a POLLATN check between each call:

```spin2
repeat
  if POLLATN()
    if (cur_cmd := pb_cmd) <> CMD_NONE
      dispatch_and_signal(cur_cmd)
  elseif idle_count > 0
    run_one_idle_task()
```

Background methods are plain Spin2 methods with a specific signature:
```spin2
PRI myTask(param) : result
  ' Do a small slice of work
  ' Return 0 to be called again, non-zero to self-remove
```

The worker calls one method per idle loop iteration, then immediately checks for filesystem commands.

**Pros**:
- **No version bump needed** — works with current `{Spin2_v46}`
- **No stack allocation** — methods run on the worker's existing stack. Zero hub RAM overhead per task
- **Guaranteed filesystem priority** — every idle task call is bracketed by pb_cmd/POLLATN checks. A filesystem command can never be delayed by more than one task method's execution time
- **No yield requirement** — methods don't need to call TASKNEXT(). They just return. The driver calls them again next loop
- **Simple registration** — `registerIdleTask(@method, param)`. No stack pointer needed
- **Crash recovery is simpler** — if a method returns, the cog is fine. Only an infinite loop within a method is problematic (same as any function call)

**Cons**:
- **Methods MUST return quickly** — a method that runs for 100ms blocks filesystem access for 100ms. This is the fundamental tradeoff. Unlike TASK-based options, there's no way to preempt a running method
- **No persistent state between calls** — each call to a method starts fresh (no local variables preserved between invocations). A method that needs to track progress must store its state in hub RAM via the `param` pointer. This makes stateful background work more verbose
- **Only one method executes per idle slot** — no interleaving. If 4 methods are registered, each gets called once every 4 loop iterations. Methods don't make progress simultaneously
- **Stack depth shared** — deep call chains in background methods share the worker's stack. Could overflow if background methods are deeply nested AND a filesystem command arrives mid-execution (but actually: methods return before the next command check, so stack depth is the MAX of filesystem or background, not the SUM)

---

### Option D: TASK for Filesystem + Polled Dispatch for Background (Hybrid)

A variation: use TASKSPIN to run the filesystem dispatcher as a named task, but run background work via polled method pointers from the main loop. This separates the "filesystem" concern from the "idle work" concern while avoiding task stacks for background methods.

**Assessment**: This adds the complexity of TASK (version bump, task management) without the benefit (background methods still can't be preempted, still need to return quickly). It's the worst of both worlds. **Rejected.**

---

### Option E: TASK with Preemptive Halting via POLLCT Guard

Extend Option A with a CT-based watchdog. When a filesystem command arrives, the dispatcher sets a CT timeout and resumes checking. If a background task hasn't yielded within N microseconds, the dispatcher can't preempt it (TASK is cooperative), but it can at least flag the condition for diagnostics.

**Assessment**: The TASK system is fundamentally cooperative. A CT timer can detect a non-yielding task but can't stop it. The only recovery is `TASKSTOP` which permanently kills the task — and we'd need to be in the dispatcher's context to call it, which we can't be if the non-yielding task is running. This doesn't solve the problem. **Rejected.**

---

### Option F: Dual-Mode (Polled for Short Tasks, TASK for Long-Running)

Offer both models. Short tasks use the polled dispatch (Option C). Long-running tasks that need persistent state use TASKSPIN (Option A). The dispatcher handles both:

```spin2
repeat
  if POLLATN()
    if (cur_cmd := pb_cmd) <> CMD_NONE
      halt_all_spin_tasks()               ' Halt TASK-based background tasks
      dispatch_and_signal(cur_cmd)
      resume_all_spin_tasks()             ' Resume TASK-based background tasks
  elseif polled_task_count > 0
    run_one_polled_task()                 ' Call-and-return method pointer
  else
    TASKNEXT()                            ' Yield to TASK-based tasks (if any)
```

**Pros**:
- **Best of both worlds** — simple tasks use simple registration; complex tasks get full TASK support
- **User chooses the right model** for each background method
- **Polled tasks still get filesystem priority guarantee**

**Cons**:
- **Most complex implementation** — two registration APIs, two dispatch mechanisms, two sets of bookkeeping
- **Confusing for users** — "should I register as polled or as a task?" requires understanding the internal dispatch model
- **Interaction between models** — polled tasks run between POLLATN checks; TASK tasks run during TASKNEXT. The two groups don't interleave cleanly with each other
- **Debugging difficulty** — when something goes wrong, the interaction of both mechanisms makes root cause analysis harder
- **Premature generality** — we don't yet have a concrete use case that requires the TASK model. Building it speculatively violates the project's "don't over-engineer" principle

---

## Comparative Analysis

| Factor | A: TASK+Halt | B: TASK No Halt | C: Polled | F: Dual-Mode |
|--------|-------------|-----------------|-----------|-------------|
| Version bump needed | Yes (v47) | Yes (v47) | **No** | Yes (v47) |
| Hub RAM per task | 256-512 bytes | 256-512 bytes | **0 bytes** | 0-512 bytes |
| FS priority guaranteed | Mostly (halt delay) | **No** | **Yes** | Yes |
| Task state preserved | **Yes** | **Yes** | No (manual) | Depends on mode |
| Long-running tasks | **Yes** | **Yes** | No (must return) | Yes |
| Crash isolation | None | None | **Better** (return) | Mixed |
| Implementation size | ~80 lines | ~40 lines | **~50 lines** | ~130 lines |
| Registration simplicity | 4 params (+ stack) | 4 params (+ stack) | **2 params** | Mixed |
| Yield requirement | Must TASKNEXT() | Must TASKNEXT() | **No** (just return) | Depends |
| Max FS latency added | Until next yield | Until ALL yield | **1 method call** | 1 call or 1 yield |

### The Core Tradeoff

The fundamental tension is between **persistent task state** and **guaranteed filesystem priority**:

- **TASK-based (A, B)**: Background tasks preserve their execution state across yields. They can be complex, long-running, and stateful. But they can block the filesystem for as long as they run between yields, and there's no way to enforce good behavior.

- **Polled (C)**: Background methods can only block the filesystem for the duration of a single method call. Priority is guaranteed. But methods must manage their own state between invocations, which is more verbose for complex background work.

---

## Prerequisite: Convert Worker to POLLATN-Based Wake

Regardless of which option is chosen, the worker's idle loop needs to change from `pb_cmd` polling to POLLATN-based signaling. This is needed for all options and also benefits the timestamp CT1 timer:

**Current** (busy-poll):
```spin2
repeat until (cur_cmd := pb_cmd) <> CMD_NONE
```

**New** (POLLATN + COGATN):
```spin2
' In send_command() (caller side), after writing pb_cmd:
COGATN(1 << cog_id)           ' Wake worker immediately

' In fs_worker() (worker side):
repeat
  if POLLCT1()                 ' Timestamp tick (from PLAN-DATETIME-TIMESTAMPS)
    tick_clock()
    ADDCT1(CLKFREQ * 2)
  if POLLATN()                 ' Filesystem command?
    if (cur_cmd := pb_cmd) <> CMD_NONE
      dispatch_and_signal(cur_cmd)
  elseif idle_count > 0        ' Background work?
    run_one_idle_task()
```

This change:
- Makes `send_command()` → worker wake instantaneous (COGATN instead of polling lag)
- Creates the natural insertion point for background work
- Allows the timestamp CT1 to be checked alongside commands

---

## Recommendation Discussion

### For v1: Option C (Polled Dispatch)

Option C is the pragmatic starting point:

1. **No version bump** — `{Spin2_v46}` stays, zero risk of compiler behavior changes
2. **Zero hub RAM per task** — no stack allocation, no sizing guesswork
3. **Filesystem priority is structural** — command check between every background method call. Cannot be violated by a misbehaving background method (unless it infinite-loops, which breaks any approach)
4. **Simple API** — `registerIdleTask(@method, param)` — no stack pointer, no yield requirement
5. **Proven pattern** — polling dispatch is the standard embedded approach for cooperative background work

The main limitation — methods must return quickly and manage their own state — is manageable for the expected use cases (LED blink, sensor poll, watchdog pet, deferred computation). Complex long-running tasks that need persistent state are better served by their own cog anyway.

### If TASK Features Are Needed Later: Upgrade to Option A

If a concrete use case requires persistent task state (a background task that runs for minutes and needs to remember where it was), Option A (TASK + Halt/Resume) can be added. The polled dispatch API doesn't change — it's additive.

**But**: the version bump to `{Spin2_v47}` and the stack allocation complexity should only be taken on when there's a real need, not speculatively.

---

## API Design (Option C: Polled Dispatch)

### New Public Methods

```spin2
PUB registerIdleTask(p_method, user_param) : task_id
'' Register a method to be called by the worker cog during idle time.
'' The method is executed ONCE as a probationary run to measure execution time.
'' If it exceeds MAX_IDLE_TASK_CYCLES, registration is rejected with E_TASK_TOO_SLOW.
'' Once accepted, the method is called repeatedly with user_param as its argument.
'' Execution time is monitored on every call — exceeding the budget deregisters the task.
''
'' Method signature: PRI/PUB myMethod(param) : result
''   result = 0: keep calling me
''   result != 0: remove me from the task list (self-unregister)
''
'' The method is a plain method. No scheduling primitives (TASKNEXT, etc.) are needed.
'' The driver handles all scheduling internally via a trampoline wrapper.
''
'' RULES:
''   1. Must return within MAX_IDLE_TASK_CYCLES (default 1ms at 350 MHz)
''   2. Must not call any SD driver API methods (would deadlock — the lock is not held)
''   3. Must not touch SPI pins (worker cog owns them)
''   4. May read/write hub RAM freely
''   5. May use GETCT/GETMS/GETSEC for timing
''
'' @param p_method - Method pointer (use @methodName or @obj.methodName)
'' @param user_param - LONG passed to every invocation
'' @returns task_id - Slot index (0 to MAX_IDLE_TASKS-1), E_TOO_MANY_TASKS, or E_TASK_TOO_SLOW

PUB unregisterIdleTask(task_id) : result
'' Remove a previously registered idle task.
''
'' @param task_id - Slot index returned by registerIdleTask()
'' @returns result - SUCCESS or E_INVALID_TASK

PUB getIdleTaskCount() : count
'' Return the number of currently registered idle tasks.
''
'' @returns count - Number of active idle tasks
```

### Thread Safety: Via Worker Commands

Registration/unregistration are called from caller cogs. The task table lives in DAT and is read by the worker. To avoid races, route through the existing command mailbox:

```spin2
CON
  CMD_REG_TASK    = 38    ' Register idle task: p0=method_ptr, p1=user_param → data0=task_id
  CMD_UNREG_TASK  = 39    ' Unregister idle task: p0=task_id → status
```

The PUB methods call `send_command()` with these codes. The worker processes them like any other command, ensuring atomic access to the task table.

### DAT Variables

```spin2
CON
  MAX_IDLE_TASKS = 4      ' Keep small — each adds worst-case latency to FS response

DAT
  idle_methods    LONG    0[MAX_IDLE_TASKS]   ' Method pointers (0 = empty slot)
  idle_params     LONG    0[MAX_IDLE_TASKS]   ' User parameters
  idle_count      LONG    0                   ' Number of active tasks
  idle_next       LONG    0                   ' Round-robin index
```

Memory cost: 36 bytes (8 LONGs + 1 LONG count + 1 LONG index). No per-task stack.

### Worker Main Loop (Final Form)

Integrating with POLLATN wake and CT1 timestamp timer:

```spin2
PRI fs_worker() | cur_cmd
  ' ... pin initialization ...

  repeat
    ' === CLOCK: 2-second timestamp tick ===
    if ct_active and POLLCT1()
      tick_clock()
      ADDCT1(CLKFREQ * 2)

    ' === PRIORITY 1: Filesystem command ===
    if POLLATN()
      if (cur_cmd := pb_cmd) <> CMD_NONE
        dispatch_command(cur_cmd)
        pb_cmd := CMD_NONE
        COGATN(1 << pb_caller)

    ' === PRIORITY 2: Idle background work ===
    elseif idle_count > 0
      run_one_idle_task()


PRI run_one_idle_task() | method_ptr, param, result, attempts
  attempts := 0
  repeat while attempts < MAX_IDLE_TASKS
    if idle_methods[idle_next] <> 0
      method_ptr := idle_methods[idle_next]
      param := idle_params[idle_next]
      result := method_ptr(param)
      if result <> 0
        ' Task requested self-removal
        idle_methods[idle_next] := 0
        idle_count--
      idle_next := (idle_next + 1) // MAX_IDLE_TASKS
      return                                    ' Ran one task — back to command check
    idle_next := (idle_next + 1) // MAX_IDLE_TASKS
    attempts++
```

### The Contract for Background Methods

```
YOUR METHOD WILL BE CALLED REPEATEDLY BY THE WORKER COG.

1. RETURN QUICKLY (1-5 ms). Your execution time directly adds to filesystem latency.
2. RETURN 0 to keep being called. Return non-zero to self-remove.
3. NEVER call SD driver API methods (deadlock).
4. NEVER touch SPI pins CS/MOSI/MISO/SCK.
5. You may freely read/write hub RAM, use GETCT/GETMS/GETSEC, toggle non-SPI pins.
6. Your method runs on the worker cog's stack. Keep call depth shallow.
7. Use the param LONG to point to your state structure in hub RAM.
```

---

## Trampoline Pattern: Decoupling User Code from Internal Scheduling

### The Problem

If the driver uses the Spin2 TASK system internally (Options A, B, F), the user's background method must call `TASKNEXT()` to yield. This couples the user's code to the driver's internal scheduling mechanism. If we later change how we dispatch (or if the user wants to reuse the same method from their own cog, or from a test harness), `TASKNEXT()` calls in user code either break or behave incorrectly.

Even with Option C (polled dispatch), the "return quickly" contract is an implicit form of coupling — but it's a natural one. "Return when you're done with one unit of work" is a universal programming concept. "Call `TASKNEXT()` at the right frequency" is not.

### The Solution: Driver-Owned Trampoline

The driver wraps every user method call in a trampoline that handles all scheduling concerns. The user writes a **plain method** that does one unit of work and returns. No TASK knowledge required. No yield calls. No scheduling primitives.

**User code** — completely decoupled:
```spin2
PUB myIdleWork(p_state) : result
  ' Do one small unit of work
  temperature := readSensor(ADC_PIN)
  LONG[p_state] := temperature
  result := 0    ' Keep calling me
```

**Driver internal** — trampoline wraps the call:
```spin2
PRI background_task_runner() | start_ct, elapsed, method_ptr, param, result
  repeat
    if num_registered > 0
      method_ptr := idle_methods[current_idx]
      param := idle_params[current_idx]

      ' --- Measure execution time ---
      start_ct := GETCT()
      result := method_ptr(param)
      elapsed := GETCT() - start_ct

      ' --- Enforce time budget ---
      if elapsed > MAX_IDLE_TASK_CYCLES
        deregister_task(current_idx)         ' Exceeded budget — removed
      elseif result <> 0
        deregister_task(current_idx)         ' Self-removal requested
      else
        current_idx := (current_idx + 1) // num_registered

    TASKNEXT                                 ' Driver controls the yield
```

The `TASKNEXT` lives in the driver's trampoline, not in user code. If we later switch from TASK to polled dispatch, or to some other mechanism, the user's method is unchanged. The only contract is: **do a bounded amount of work and return.**

### What This Achieves

1. **Decoupling** — the user's method is a plain method with no scheduling primitives. It works identically if called from their own cog, from a test harness, or from our idle dispatcher. Zero knowledge of the driver's internal dispatch mechanism is required.

2. **Freedom to change internals** — if we later decide TASK isn't the right mechanism (or switch to polled dispatch, or a hybrid), the user's code doesn't change. Only the trampoline adapts.

3. **Natural latency contract** — "return quickly" is intuitive. "Call TASKNEXT at the right frequency" is not. The user thinks in units of work, not scheduler ticks.

4. **Portability** — the same background method can be unit-tested by calling it directly from a test cog. No TASK system needed for testing.

### Implication for Option Selection

The trampoline pattern means the **user-facing API is identical regardless of which internal dispatch option we choose**. Options A, B, C, and F all present the same registration interface and the same user method signature. The choice of internal mechanism (TASK vs polled vs hybrid) is a driver-internal decision that the user never sees.

This shifts the option comparison from "what must the user do differently?" to "what are the internal engineering tradeoffs?" — which is where the decision should live.

---

## Probationary Run: Rejecting Slow Methods at Registration

### The Problem

A user method that runs for 50ms blocks filesystem commands for 50ms. The contract says "return quickly" but the driver cannot enforce this at compile time. By the time we discover a method is too slow, the damage (filesystem latency spike) has already happened.

### The Solution: Measure at Registration Time

When `registerIdleTask()` is called, the driver executes the method **once** as a trial run, measures its execution time, and rejects it if it exceeds the budget:

```spin2
CON
  MAX_IDLE_TASK_CYCLES = 350_000    ' 1ms at 350 MHz — configurable
  E_TASK_TOO_SLOW      = -96

PRI do_register_idle_task() | p_method, param, start_ct, elapsed
  p_method := pb_param0
  param := pb_param1

  if idle_count >= MAX_IDLE_TASKS
    pb_status := E_TOO_MANY_TASKS
    return

  ' === PROBATIONARY RUN: execute once and measure ===
  start_ct := GETCT()
  p_method(param)
  elapsed := GETCT() - start_ct

  if elapsed > MAX_IDLE_TASK_CYCLES
    pb_status := E_TASK_TOO_SLOW
    return

  ' Passed — add to the task list
  idle_methods[idle_count] := p_method
  idle_params[idle_count] := param
  pb_data0 := idle_count                    ' Return task_id = slot index
  idle_count++
  pb_status := SUCCESS
```

The caller gets a clear accept/reject at registration time:
```spin2
task_id := sd.registerIdleTask(@myIdleWork, @my_state)
if task_id == sd.E_TASK_TOO_SLOW
  debug("Method too slow for background execution")
```

### Runtime Monitoring: Ongoing Enforcement

The probationary run catches obvious violations, but a method's execution time can be data-dependent. The first run might be fast (empty data set), later runs slow (full buffer). The trampoline monitors **every invocation**:

```spin2
' Inside background_task_runner():
start_ct := GETCT()
result := method_ptr(param)
elapsed := GETCT() - start_ct

if elapsed > MAX_IDLE_TASK_CYCLES
  deregister_task(current_idx)               ' One violation = removed
  idle_violation_count++                     ' Diagnostic counter
```

One violation and the method is deregistered. This is strict, but correct — a single 50ms stall delays every filesystem command from every cog. The offending caller can check task status or catch the next `registerIdleTask` result.

### Limitations (Documented Honestly)

1. **Detection, not prevention**: The probationary run and runtime monitoring **detect** slow methods but cannot **prevent** the damage of one slow call. If the method takes 50ms, filesystem commands are delayed 50ms during that call. We catch it and deregister, but that one call already happened.

2. **First-run may not be representative**: Cold cache, empty data structures, or uninitialized state may make the probationary run faster than typical execution. The runtime monitoring backstops this.

3. **Cannot abort mid-execution**: Spin2 cooperative TASK has no preemption. Once a method is called, it runs to completion. CT events can detect elapsed time but cannot interrupt — they're polled, not vectored. The only mitigation is the "return quickly" contract and the post-hoc deregistration.

4. **GETCT wraparound**: At 350 MHz, the 32-bit counter wraps every ~12.3 seconds. A method that runs for more than 12 seconds would produce a small elapsed value, evading detection. This is not a real concern — a 12-second method would have been caught as a 12-second stall long before wraparound matters.

---

## Use Case Examples

### 1. LED Heartbeat
```spin2
DAT
  led_last_ms   LONG  0

PRI blink_led(p_state) : result
  if GETMS() - LONG[p_state] > 500
    PINNOT(LED_PIN)
    LONG[p_state] := GETMS()
  result := 0    ' Keep running

' Registration:
sd.registerIdleTask(@blink_led, @led_last_ms)
```

### 2. Sensor Polling (Shared Hub Buffer)
```spin2
DAT
  sensor_reading  LONG  0

PRI poll_adc(p_dest) : result
  LONG[p_dest] := PINREAD(ADC_PIN) >> 14    ' Read ADC, store for main cog
  result := 0

' Main cog reads sensor_reading from hub RAM at any time
sd.registerIdleTask(@poll_adc, @sensor_reading)
```

### 3. Watchdog Pet
```spin2
PRI pet_watchdog(pin) : result
  PINHIGH(pin)
  WAITUS(1)
  PINLOW(pin)
  result := 0

sd.registerIdleTask(@pet_watchdog, WDT_PIN)
```

### 4. One-Shot Deferred Work (Chunked)
```spin2
DAT
  work_context  LONG  0[4]   ' [p_data, offset, total_len, accumulator]

PRI compute_crc_chunk(p_ctx) : result | offset, chunk_end
  offset := LONG[p_ctx + 4]
  chunk_end := offset + 64 <# LONG[p_ctx + 8]    ' Process 64 bytes per call
  repeat while offset < chunk_end
    LONG[p_ctx + 12] ^= BYTE[LONG[p_ctx]][offset++]    ' Simplified CRC
  LONG[p_ctx + 4] := offset
  result := (offset >= LONG[p_ctx + 8]) ? 1 : 0        ' Return 1 when done (self-remove)

sd.registerIdleTask(@compute_crc_chunk, @work_context)
```

---

## Open Questions

1. **MAX_IDLE_TASKS = 4 or 8?** Each slot is 8 bytes. 4 seems sufficient for expected use cases. 8 costs only 32 more bytes but doubles worst-case filesystem latency if all slots run max-budget methods.

2. **Should idle tasks run when an async I/O is pending?** (See PLAN-NONBLOCKING-FILE-IO.) When the worker is executing a filesystem command, idle tasks don't run (the cog is busy). But what about the brief idle moments between SPI transactions within a multi-sector operation? Currently, no — the worker is in the middle of a `do_read_h()` call and can't yield. This is correct behavior.

3. **Feature gate: `#ifdef SD_INCLUDE_IDLE_TASKS`?** The idle loop change is small (~30 lines for dispatch) but adds 3 PUB methods and 2 CMD codes. Recommend: yes, gate it to keep minimal builds small.

4. **Should `registerIdleTask()` work before `mount()`?** Currently the worker cog doesn't start until `mount()` or `start()`. Background tasks would need the worker running. Options: (a) require mount first, (b) let `registerIdleTask()` auto-start the worker in MODE_NONE, (c) add a `startWorker()` method that starts the cog without mounting. Recommend: (a) for simplicity.

5. **What if a background method infinite-loops?** The cog becomes unresponsive. Filesystem operations from all cogs time out. The only recovery is the caller detecting timeout and calling `stop()` + `mount()` to restart the worker. This is the same failure mode as a hardware SPI hang — the driver doesn't have a watchdog today. Document it as a programmer-error condition.

6. **TASK upgrade path**: The trampoline pattern means the user-facing API is identical regardless of internal dispatch mechanism. If TASK features are later needed for persistent-state background work, the existing `registerIdleTask` API doesn't change — only the driver's internal trampoline is swapped. A separate `registerIdleSpinTask(@method, @stack, stack_size, param)` could be added alongside for TASK-based registration, but only when a concrete use case demands it.

7. **MAX_IDLE_TASK_CYCLES tuning**: Default 350,000 cycles (1ms at 350 MHz). Should this be user-configurable? A `setIdleTaskBudget(cycles)` method would let the user trade filesystem latency for more generous background work budgets. Recommend: hardcoded for v1, configurable if demand arises.

8. **Should the caller be notified of runtime deregistration?** When a method is deregistered for exceeding its time budget at runtime, the caller currently has no notification — the method simply stops being called. Options: (a) status flag per slot that the caller can poll, (b) increment a violation counter readable via `getIdleTaskViolations()`, (c) documentation only ("if your method stops being called, it was too slow"). Recommend: (b) — a single counter is cheap and debuggable.
