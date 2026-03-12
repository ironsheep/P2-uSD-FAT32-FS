# Plan: File Date/Time Timestamps with Auto-Incrementing Clock

## Cog Independence Note

The timestamp clock runs entirely within the worker cog (CT1 tick every 2 seconds). It has **zero impact on caller cogs** — no caller cycles consumed, no shared resource contention. The `setDate()` call from the caller is a one-time `send_command()` that takes microseconds. After that, the worker maintains the clock independently and applies timestamps at create/modify time without any caller involvement.

## Problem Statement

The driver has a `setDate()` method and a `date_stamp` DAT variable that gets packed into FAT32 directory entries at file/directory creation time. But it is **static** — the caller sets it once and it never changes. If the caller sets the date at boot and then creates files hours later, they all have the boot-time timestamp.

Additionally:
- `do_close_h()` and `do_sync_h()` update file **size** in the directory entry on close/sync but do **not** update the **modification timestamp** (DIR_WrtTime/DIR_WrtDate)
- `DIR_CrtTimeTenth` (tenths of second) is never set (always 0)

**Out of scope**: DIR_LstAccDate (last access date) — not implemented. The per-close I/O cost (sector read + write on every file close) is not justified for embedded use. Many production implementations disable this (Windows `NtfsDisableLastAccessUpdate`, Linux `noatime` mount option).

## FAT32 Timestamp Spec (MS FAT Specification, Section 6)

### Directory Entry Timestamp Fields

| Field | Offset | Size | When Updated | Granularity |
|-------|--------|------|-------------|-------------|
| DIR_CrtTimeTenth | 13 | 1 byte | File creation only | 10ms (0-199) |
| DIR_CrtTime | 14 | 2 bytes | File creation only | 2 seconds |
| DIR_CrtDate | 16 | 2 bytes | File creation only | 1 day |
| DIR_LstAccDate | 18 | 2 bytes | Any read or write | 1 day |
| DIR_WrtTime | 22 | 2 bytes | File modification (write) | 2 seconds |
| DIR_WrtDate | 24 | 2 bytes | File modification (write) | 1 day |

### Bit Layouts (already implemented in `setDate()`)

**Date word (16 bits)**:
```
Bits [15:9] = Year - 1980 (0-127 → 1980-2107)
Bits [8:5]  = Month (1-12)
Bits [4:0]  = Day (1-31)
```

**Time word (16 bits)**:
```
Bits [15:11] = Hour (0-23)
Bits [10:5]  = Minute (0-59)
Bits [4:0]   = Second / 2 (0-29 → 0-58 seconds, 2-second granularity)
```

**CrtTimeTenth (8 bits)**:
```
0-199: Tenths of a second at creation time
Values 0-99 refine DIR_CrtTime's 2-second granularity to 100ms
Values 100-199 add 1 second + tenths (since DIR_CrtTime has 2s resolution)
```

### Spec Requirements for Updates

- **At file creation**: Set DIR_CrtTimeTenth, DIR_CrtTime, DIR_CrtDate, DIR_WrtTime, DIR_WrtDate. DIR_WrtTime/Date must equal DIR_CrtTime/Date at creation
- **On file modification** (any write, then close/sync): Update DIR_WrtTime, DIR_WrtDate
- **On file access** (read): Spec says update DIR_LstAccDate — we will NOT implement this (see above)

## Current Driver State

### What Works
- `setDate(year, month, day, hour, minute, second)` — packs into `date_stamp` LONG (date in upper 16, time in lower 16)
- `date_stamp` applied at creation via `dirEntSetCreateStamp()` and `dirEntSetModifyStamp()`
- Default `setDate(2009,01,27,07,00,00)` if user never calls `setDate()` (in `do_mount()`, line 2842)

### What's Missing
1. **No auto-incrementing clock** — `date_stamp` is frozen at whatever the caller last set
2. **No modification timestamp on write close/sync** — `do_close_h()` and `do_sync_h()` update `DE_FILESIZE_OFFSET` but not `DE_WRT_TIME_OFFSET`
3. **No CrtTimeTenth** — always 0

---

## Design: Two Approaches Considered

### Approach A: Live Pre-Packed Stamp (CT-Timed Update)

Keep a pre-packed `date_stamp` LONG in DAT that is **always current**. A CT-based periodic timer fires every 2 seconds (matching FAT32's timestamp granularity) and re-packs the LONG with the current time. At file create/modify, the driver just copies the LONG — zero computation, zero latency.

**How it works**:
1. `setDate()` initializes unpacked time fields (`cur_year`, `cur_month`, `cur_day`, `cur_hour`, `cur_minute`, `cur_second`) and packs `date_stamp`
2. `setDate()` also records a CT target 2 seconds in the future via `ADDCT1`
3. The worker cog's main loop polls `POLLCT1()` alongside `pb_cmd`
4. When CT1 fires (every 2 seconds): increment `cur_second` by 2, handle rollovers (second→minute→hour→day→month→year), re-pack `date_stamp`, set next CT1 target
5. At create/modify time: just copy `date_stamp` — it's already correct

```spin2
DAT
  ' Unpacked current time (maintained by CT1 tick)
  cur_year      LONG    0
  cur_month     LONG    0
  cur_day       LONG    0
  cur_hour      LONG    0
  cur_minute    LONG    0
  cur_second    LONG    0
  ct_active     BYTE    0         ' TRUE when clock is running
```

**Worker main loop change**:
```spin2
repeat
  if POLLCT1()                                    ' 2-second tick?
    tick_clock()                                  ' Increment time, repack date_stamp
    ADDCT1(CLKFREQ * 2)                           ' Schedule next tick
  if (cur_cmd := pb_cmd) <> CMD_NONE
    dispatch_and_signal(cur_cmd)
  elseif idle_count > 0
    run_one_idle_task()
```

**`tick_clock()` method** (~30 lines):
```spin2
PRI tick_clock() | days_in_month
  cur_second += 2
  if cur_second >= 60
    cur_second := 0
    cur_minute++
    if cur_minute >= 60
      cur_minute := 0
      cur_hour++
      if cur_hour >= 24
        cur_hour := 0
        cur_day++
        days_in_month := daysInMonth(cur_year, cur_month)
        if cur_day > days_in_month
          cur_day := 1
          cur_month++
          if cur_month > 12
            cur_month := 1
            cur_year++
  ' Repack the stamp
  date_stamp := (cur_year - FAT_EPOCH_YEAR) << 25 | cur_month << 21 | cur_day << 16 | cur_hour << 11 | cur_minute << 5 | cur_second >> 1
```

**At create/modify time** — this is all that's needed:
```spin2
dirEntSetCreateStamp(@entry_buffer, date_stamp)   ' Already current!
dirEntSetModifyStamp(@entry_buffer, date_stamp)   ' Already current!
```

**Pros**:
- Zero computation at create/modify time — just a LONG copy
- Time is always available without calling any method
- Naturally matches FAT32's 2-second granularity (tick every 2 seconds)
- Simple rollover logic (no epoch math, no division)
- Uses only CT1 — leaves CT2/CT3 free for other purposes
- POLLCT1 is 2-9 cycles — negligible cost per main loop iteration

**Cons**:
- Consumes one CT event (CT1) permanently while clock is active
- POLLCT1 must be checked in the main loop — if the worker is busy with a long SD operation (e.g., multi-block write taking 100ms+), CT1 fires are "late" but not lost. The next POLLCT1 catches it and the 2-second cadence resumes. Worst case: a few seconds of clock skew during very long operations, which self-corrects
- Adds 6 LONGs + 1 BYTE of DAT storage for unpacked time

### Approach B: On-Demand GETSEC() Derivation

Compute the current time from scratch whenever a timestamp is needed, using `GETSEC()` elapsed seconds since `setDate()` was called:

```
current_seconds_since_epoch = base_seconds_since_epoch + (GETSEC() - base_getsec)
```

No periodic timer. Call `getCurrentStamp()` at create/modify time, which:
1. Gets elapsed seconds via `GETSEC() - base_getsec`
2. Adds to `base_fat_seconds` (set by `setDate()`)
3. Converts total seconds back to year/month/day/hour/minute/second
4. Packs into the FAT32 date_stamp LONG

```spin2
DAT
  base_fat_seconds  LONG    0     ' Seconds since FAT epoch when setDate() was called
  base_getsec       LONG    0     ' GETSEC() value when setDate() was called

PRI getCurrentStamp() : stamp | elapsed, total_sec, year, month, day, hour, minute, second
  if base_fat_seconds == 0
    return date_stamp                         ' Fallback: no setDate() called, use static stamp
  elapsed := GETSEC() - base_getsec
  total_sec := base_fat_seconds + elapsed
  secondsToDateTime(total_sec, @year, @month, @day, @hour, @minute, @second)
  stamp := (year - FAT_EPOCH_YEAR) << 25 | month << 21 | day << 16 | hour << 11 | minute << 5 | second >> 1
```

**Pros**:
- No CT event consumed — no hardware resource used
- No periodic polling — no main loop change needed
- No accumulated rollover errors — pure arithmetic from a base point
- Only 2 LONGs of DAT storage

**Cons**:
- `secondsToDateTime()` is ~40-50 lines of division/modulo math, called on every create/modify
- Computation at write time: dividing total seconds into years, months, days requires iterating through years for leap year accounting. Not slow (microseconds in Spin2), but not zero either
- Requires both `dateTimeToSeconds()` and `secondsToDateTime()` helper methods (~80-100 lines total)
- More code size than Approach A

### Recommendation: Approach A (Live Pre-Packed Stamp)

Approach A is the better fit for this driver:

1. **Zero create/modify latency** — the stamp is always pre-packed and ready. This matters because creates and writes are performance-sensitive paths
2. **Simpler code at point of use** — no method call, just use `date_stamp` as today
3. **The CT1 cost is acceptable** — the worker cog doesn't use any CT events today. CT1 firing every 2 seconds is negligible overhead
4. **Natural fit with the worker cog** — the worker already runs a main loop that we're modifying for idle tasks. Adding `POLLCT1()` is one line
5. **No epoch arithmetic** — rollover logic (second→minute→hour etc.) is straightforward and well-understood

### Date/Time Helpers (Both Approaches)

Both approaches need a `daysInMonth()` helper:

```spin2
PRI daysInMonth(year, month) : days
  ' Returns days in the given month, accounting for leap years
  days := BYTE[@days_table][month - 1]
  if month == 2 and isLeapYear(year)
    days := 29

DAT
  days_table  BYTE  31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

PRI isLeapYear(year) : result
  result := (year & 3) == 0                    ' Divisible by 4
  if year == 2100                              ' Only century exception in FAT range (1980-2107)
    result := false
```

Approach B additionally needs `dateTimeToSeconds()` and `secondsToDateTime()` (~80 lines).
Approach A only needs `daysInMonth()` and `isLeapYear()` (~15 lines).

---

## Implementation Tasks

### Task 1: Add Live Clock Infrastructure (Approach A)

- Add unpacked time DAT variables (`cur_year` through `cur_second`, `ct_active`)
- Implement `tick_clock()` — 2-second increment with rollover
- Implement `daysInMonth()` and `isLeapYear()` helpers
- Modify `setDate()` to initialize unpacked fields, pack `date_stamp`, arm CT1
- Add `POLLCT1()` check to worker main loop, with `ADDCT1(CLKFREQ * 2)` re-arm

### Task 2: Update Modification Timestamp on Write Close/Sync

In `do_close_h()` (line 3114-3123), after updating file size:
```spin2
    ' If opened for write, update directory entry with final size AND modification time
    if h_flags[handle] & HF_WRITE
      if readSector(h_dir_sector[handle], BUF_DIR) < 0
        result := E_IO_ERROR
      else
        long[@dir_buf + h_dir_offset[handle] + DE_FILESIZE_OFFSET] := h_size[handle]
        long[@dir_buf + h_dir_offset[handle] + DE_WRT_TIME_OFFSET] := date_stamp  ' NEW: always current via CT1
        writeSector(h_dir_sector[handle], BUF_DIR)
```

Same change in `do_sync_h()` (line 3448). With Approach A, `date_stamp` is always pre-packed and current — no method call needed.

### Task 3: Set CrtTimeTenth at Creation

In `do_create()` and `do_open_write()` (new file path), after setting create stamp:
```spin2
    ' Set creation tenths (0 for now — could use GETMS() % 2000 / 10 for sub-2s precision)
    byte[@entry_buffer + 13] := 0    ' DIR_CrtTimeTenth — offset 13 in dir_entry_t
```

This is low priority. Value of 0 is spec-compliant.

### Task 4: Regression Tests

- Test that `setDate()` followed by file creation produces correct timestamps
- Test that closing a write handle updates DIR_WrtTime/DIR_WrtDate
- Test that timestamps advance: `setDate()`, wait 4 seconds, create file — verify different timestamp
- Test default timestamp (no `setDate()` call) still produces valid date

---

## Design Decisions

### Decision: CT1-Based Live Clock (Approach A)

Use CT1 to fire every 2 seconds (matching FAT32 granularity). The worker cog polls POLLCT1 in its main loop and increments the unpacked time fields, then re-packs `date_stamp`. This makes `date_stamp` always current with zero computation at the point of use (file create/modify). Consumes CT1 on the worker cog; CT2/CT3 remain available.

### Decision: Backward Compatible

If `setDate()` is never called, behavior is identical to today — static default timestamp. The auto-incrementing clock only activates when `base_fat_seconds != 0` (i.e., `setDate()` was called).

---

## Code Size Estimate (Approach A)

- `tick_clock()`: ~30 lines (increment + rollover + repack)
- `daysInMonth()` + `isLeapYear()`: ~15 lines
- `days_table`: 12 bytes DAT
- `setDate()` changes: ~10 lines (unpack into fields, arm CT1)
- Worker main loop: ~3 lines (POLLCT1 check)
- Close/sync changes: ~2 lines each (copy `date_stamp` to dir entry)
- New DAT variables: 6 LONGs + 1 BYTE (25 bytes)

Total: ~60 lines of new code, 37 bytes of new DAT. All Spin2, no PASM needed.

## Open Questions

1. **Should CrtTimeTenth use sub-second precision?** Could use `GETMS() // 2000 / 10` for 100ms resolution. Low value for embedded use. Recommend: set to 0 for v1.
2. **Should `setDate()` validate ranges?** Currently no validation. Could clamp month to 1-12, day to 1-31, etc. Recommend: no validation — caller's responsibility, matching current behavior.
