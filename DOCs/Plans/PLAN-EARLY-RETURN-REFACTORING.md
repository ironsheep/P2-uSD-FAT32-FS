# Early Return Refactoring Plan

Precise work plan for converting remaining early `return` statements in `src/micro_sd_fat32_fs.spin2` to single-exit-point methods per Spin2 Authoring Guide Rule 5.2.

**Context:** The 2026-03-27 audit session refactored `setDate()` and `do_create_contiguous()`. This plan covers the remaining ~25 early returns across 10 methods.

**Risk level:** HIGH — these are in active I/O paths (async API, defrag, SPI protocol). Every change must be compile-verified and regression-tested on hardware.

**Compiler:** pnut-ts v1.53.2 installed at `$HOME/.local/bin/pnut_ts`
**Compile command:** `cd src && pnut_ts -q -D SD_INCLUDE_ALL micro_sd_fat32_fs.spin2`

---

## General Pattern

All early returns fall into three categories. Each has a standard refactoring pattern:

### Pattern A — Guard Clause Chain (2-3 precondition checks at method start)
```spin2
' BEFORE (early returns)
    if precondition_A_fails
        return set_error(E_XXX)
    if precondition_B_fails
        return set_error(E_YYY)
    ... main body ...

' AFTER (single exit)
    if precondition_A_fails
        status := set_error(E_XXX)
    elseif precondition_B_fails
        status := set_error(E_YYY)
    else
        ... main body ...
```

### Pattern B — Sequential Steps with Bail-Out (each step can fail)
```spin2
' BEFORE (early returns on each step)
    step1_result := doStep1()
    if step1_result < 0
        status := step1_result
        return
    step2_result := doStep2()
    if step2_result < 0
        status := step2_result
        return
    ... success ...

' AFTER (nested if/else or guard variable)
    step1_result := doStep1()
    if step1_result < 0
        status := step1_result
    else
        step2_result := doStep2()
        if step2_result < 0
            status := step2_result
        else
            ... success ...
```

### Pattern C — Return from Inside Loop
```spin2
' BEFORE (return from repeat)
    repeat ...
        if found_condition
            result := value
            return

' AFTER (quit from repeat, single exit)
    repeat ...
        if found_condition
            result := value
            quit
```

---

## Method 1: `PUB startReadHandle` (line ~1227)

**Category:** Pattern A — Guard clause chain
**Returns:** 2 (lines 1238, 1240)
**Complexity:** Low

```
Line 1238: return set_error(E_ASYNC_BUSY)     — if async_active
Line 1240: return set_error(E_NOT_MOUNTED)     — if cog_id == -1
```

**Refactoring:**
```spin2
    if async_active
        status := set_error(E_ASYNC_BUSY)
    elseif cog_id == -1
        status := set_error(E_NOT_MOUNTED)
    else
        repeat until LOCKTRY(api_lock)
        ... existing body ...
        status := PENDING
```

**Notes:** The body after the guards acquires the lock and sets up the async operation. All of that goes inside the `else` branch.

---

## Method 2: `PUB startWriteHandle` (line ~1254)

**Category:** Pattern A — Guard clause chain
**Returns:** 2 (lines 1264, 1266)
**Complexity:** Low

Identical structure to `startReadHandle`. Same refactoring pattern.

---

## Method 3: `PUB getResult` (line ~1288)

**Category:** Pattern A — Single guard clause
**Returns:** 1 (line 1295)
**Complexity:** Low

```
Line 1295: return set_error(E_NO_ASYNC_OP)     — if NOT async_active
```

**Refactoring:**
```spin2
    if NOT async_active
        status := set_error(E_NO_ASYNC_OP)
    else
        ... existing body ...
```

---

## Method 4: `PUB cancelAsync` (line ~1310)

**Category:** Pattern A — Single guard clause
**Returns:** 1 (line 1318)
**Complexity:** Low

Identical structure to `getResult`. Same refactoring pattern.

---

## Method 5: `PRI do_idle_flush` (line ~3701)

**Category:** Pattern C — Return from inside loop
**Returns:** 1 (line 3708)
**Complexity:** Low

```
Line 3708: return     — if pb_cmd <> CMD_NONE (command arrived, abort flush)
```

**Refactoring:** Read the full method to understand the loop structure. Replace `return` with `quit` to exit the repeat loop. The method has no return value (void), so `quit` is sufficient.

```spin2
    repeat ...
        if pb_cmd <> CMD_NONE
            quit                                ' Command arrived, abort flush
        ... rest of flush logic ...
```

**Notes:** Verify there is no code after the loop that should be skipped when aborting. If there is, use a `bAborted` flag:
```spin2
    bAborted := false
    repeat ...
        if pb_cmd <> CMD_NONE
            bAborted := true
            quit
    if NOT bAborted
        ... post-loop cleanup ...
```

---

## Method 6: `PRI do_compact_file` (line ~4872)

**Category:** Pattern B — Sequential steps with bail-out (12-step process)
**Returns:** 8 (lines 4884, 4893, 4898, 4904, 4921, 4929, 4944, 4956, 4961)
**Complexity:** HIGH — most complex method in this plan

This is a 12-step defragmentation process. Each step can fail, and later steps depend on earlier ones succeeding.

```
Line 4884: return     — Step 1: file not found
Line 4893: return     — Step 2: file is open
Line 4898: return     — Step 3: empty file (SUCCESS)
Line 4904: return     — Step 4: already contiguous (SUCCESS)
Line 4921: return     — Step 5: no contiguous space
Line 4929: return     — Step 6: copy phase I/O error
Line 4944: return     — Step 7: verify phase mismatch
Line 4956: return     — Step 8: FAT chain allocation failed
Line 4961: return     — Step 9: directory sector read failed
```

**Refactoring approach:** Use nested `if status >= 0` guards after each step. Steps 3 and 4 are early-success exits (set `status := SUCCESS`), not errors — they still need to reach the single exit point.

```spin2
    status := E_FILE_NOT_FOUND
    if searchDirectory(p_path) == 0
        ' Step 1 failed: file not found
    elseif isFileOpenAny(dir_sec, dir_off)
        status := E_FILE_OPEN_FOR_COMPACT
    elseif file_size == 0
        status := SUCCESS                       ' Step 3: empty file, nothing to do
    elseif frag_count == 1
        status := SUCCESS                       ' Step 4: already contiguous
    else
        ' Steps 5-12: find space, copy, verify, rewrite FAT, update directory
        new_first := findContiguousRun(cluster_count)
        if new_first < 0
            status := new_first
        else
            ' Step 6: Copy clusters
            status := copyClusterRange(...)
            if status >= 0
                ' Step 7: Verify copy
                status := verifyClusterCopy(...)
                if status >= 0
                    ' Step 8: Allocate new FAT chain
                    ... and so on, nesting each step ...
```

**Notes:**
- Read the full method (lines ~4872-4970) before starting. Understand all 12 steps.
- The nesting will get deep (6-7 levels). This is acceptable for correctness — the alternative is a state machine which would be a bigger refactor.
- Preserve all `DEBUG[CH_FILE]()` calls at each failure point.
- Compile and verify binary size is within a few bytes of the original (31996 bytes as of this writing).

---

## Method 7: `PRI countFileFragments` (line ~4992)

**Category:** Pattern A — Single guard clause
**Returns:** 1 (line 5001)
**Complexity:** Low

```
Line 5001: return     — if first_cluster < ROOT_CLUSTER (empty file)
```

**Refactoring:**
```spin2
    if first_cluster < ROOT_CLUSTER
        count := 0
    else
        ... existing FAT chain walk ...
```

---

## Method 8: `PRI findContiguousRun` (line ~5018)

**Category:** Pattern C — Return from inside loop (2 returns)
**Returns:** 2 (lines 5036, 5047)
**Complexity:** Medium

```
Line 5036: return     — FAT read I/O error inside scan loop
Line 5047: return     — Found sufficient contiguous run (success)
```

**Refactoring:** Replace both returns with `quit`, then check after the loop:

```spin2
    bDone := false
    repeat cluster from ROOT_CLUSTER to max_cluster
        if NOT bDone
            ... FAT scan logic ...
            if readSector(...) < 0
                first_cluster := E_IO_ERROR
                bDone := true
            ... check run length ...
            if run_length >= cluster_count
                first_cluster := run_start
                bDone := true
    fat_sec_in_buf := -1
```

**Notes:** The `fat_sec_in_buf := -1` cleanup at the end must execute regardless of exit path. Verify the existing code's cleanup requirements.

---

## Method 9: `PRI verifyClusterCopy` (line ~5111)

**Category:** Pattern C — Return from inside nested loops
**Returns:** 1 (line 5133)
**Complexity:** Medium

```
Line 5133: return     — byte mismatch detected during verify
```

**Refactoring:** Use `quit` from inner loop, then check and `quit` from outer loop:

```spin2
    status := SUCCESS
    repeat idx from 0 to sec_per_clus - 1
        ... read source and dest sectors ...
        repeat byte_idx from 0 to SECTOR_SIZE - 1
            if BYTE[@buf][byte_idx] <> BYTE[@dir_buf][byte_idx]
                DEBUG[CH_FILE]("  [verifyClusterCopy] Mismatch ...")
                status := E_VERIFY_FAILED
                quit
        if status < 0
            quit                                ' propagate to outer loop
```

---

## Method 10: `PRI sendStopTransmission` (line ~6366)

**Category:** Pattern C — Return from inside loop
**Returns:** 1 (line 6407)
**Complexity:** Medium

```
Line 6407: return     — timeout waiting for R1 response
```

**Refactoring:** Replace `return` with `quit`. Verify that post-loop code handles the timeout case correctly (check `status` after the loop).

---

## Method 11: `PRI sendCmd13Transaction` (line ~6449)

**Category:** Pattern C — Return from inside loop
**Returns:** 1 (line 6499)
**Complexity:** Medium

```
Line 6499: return     — timeout waiting for R1 response (sets r1=-1, CS high)
```

**Refactoring:** Replace `return` with `quit`. The `pinh(cs)` call on line 6500 must still execute. Ensure post-loop code handles the r1==-1 case.

**Notes:** Read the full method carefully. The CS pin management (pinh/pinl) is safety-critical — the pin must be released on all exit paths.

---

## Method 12: `PRI probeCmd13` (line ~6517)

**Category:** Pattern A — Guard clause chain (3 checks)
**Returns:** 3 (lines 6539, 6546, 6553)
**Complexity:** Low

All three returns do the same thing: set `cmd13_reliable := FALSE` and `card_warning_flags |= CW_CMD13_UNRELIABLE`.

**Refactoring:**
```spin2
    if r1 == -1
        DEBUG[CH_STATUS]("    [probeCmd13] TIMEOUT ...")
        cmd13_reliable := FALSE
        card_warning_flags |= CW_CMD13_UNRELIABLE
    elseif r1 & $80
        DEBUG[CH_STATUS]("    [probeCmd13] R1 bit 7 set ...")
        cmd13_reliable := FALSE
        card_warning_flags |= CW_CMD13_UNRELIABLE
    elseif ONES status >= 3
        DEBUG[CH_STATUS]("    [probeCmd13] STATUS has ... error bits ...")
        cmd13_reliable := FALSE
        card_warning_flags |= CW_CMD13_UNRELIABLE
    else
        cmd13_reliable := TRUE
        ... existing success handling ...
```

**Notes:** Since all three failure paths do the same cleanup, consider extracting the common action before the if/elseif chain and only running the success path conditionally.

---

## Method 13: `PRI checkCardStatus` (line ~6589)

**Category:** Pattern A — Single guard clause
**Returns:** 1 (line 6603)
**Complexity:** Low

```
Line 6603: return     — skip if CMD13 unreliable and not test-forced
```

**Refactoring:**
```spin2
    if cmd13_reliable OR test_force_cmd13
        ... existing body ...
```

---

## Implementation Order

Work from lowest risk to highest:

### Batch 1 — Simple Guard Clauses (8 methods, ~12 returns)
1. `getResult` — 1 return
2. `cancelAsync` — 1 return
3. `startReadHandle` — 2 returns
4. `startWriteHandle` — 2 returns
5. `countFileFragments` — 1 return
6. `checkCardStatus` — 1 return
7. `probeCmd13` — 3 returns
8. `do_idle_flush` — 1 return

**Verify:** Compile after each method. Run full regression suite after batch.

### Batch 2 — Loop Exits (3 methods, 5 returns)
9. `sendStopTransmission` — 1 return
10. `sendCmd13Transaction` — 1 return (CS pin safety-critical)
11. `findContiguousRun` — 2 returns
12. `verifyClusterCopy` — 1 return

**Verify:** Compile after each. Run regression suite + defrag tests after batch.

### Batch 3 — Complex Multi-Step (1 method, 8 returns)
13. `do_compact_file` — 8 returns (12-step process)

**Verify:** Compile. Run full regression suite + defrag-specific tests.

---

## Verification Checklist

After all refactoring:
- [ ] `pnut_ts -q -D SD_INCLUDE_ALL micro_sd_fat32_fs.spin2` compiles without error
- [ ] Binary size within ~100 bytes of baseline (31996 bytes)
- [ ] All 25 regression test suites pass on hardware
- [ ] `grep -c '^\s*return\b' micro_sd_fat32_fs.spin2` returns 0
- [ ] No `return` inside any `repeat` block
