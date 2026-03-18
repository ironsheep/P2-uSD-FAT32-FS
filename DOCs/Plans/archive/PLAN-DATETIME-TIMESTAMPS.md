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

**Combined `date_stamp` LONG (as packed in the driver)**:
```
[31:25] Year-1980  (7 bits)    ^@date_stamp.[31..25]
[24:21] Month      (4 bits)    ^@date_stamp.[24..21]
[20:16] Day        (5 bits)    ^@date_stamp.[20..16]
[15:11] Hour       (5 bits)    ^@date_stamp.[15..11]
[10:5]  Minute     (6 bits)    ^@date_stamp.[10..5]
[4:0]   Second/2   (5 bits)    ^@date_stamp.[4..0]
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
4. **No getDate()** — no way to read back the current time as the driver knows it

---

## API Design: Symmetric setDate / getDate

### Principle

The time API should be symmetric: whatever you can set, you can get back, in the same form. The caller thinks in human-readable units (year, month, day, hour, minute, second), not packed FAT32 bit fields. Both methods use the same 6 parameters in the same order.

### setDate (existing, enhanced)

```spin2
PUB setDate(year, month, day, hour, minute, second)
'' Set the current date and time for file timestamps.
'' Starts the auto-incrementing clock (CT1-based, 2-second tick).
'' After this call, all file create/modify timestamps use the live clock.
''
'' @param year - Year (e.g., 2026)
'' @param month - Month (1-12)
'' @param day - Day (1-31)
'' @param hour - Hour (0-23)
'' @param minute - Minute (0-59)
'' @param second - Second (0-59, rounded to even for FAT32 2-second granularity)
```

Enhancement for v1.4.0: uses FIELD operator to write directly into the packed `date_stamp` LONG, then arms CT1 to start the live clock.

### getDate (new)

```spin2
PUB getDate() : year, month, day, hour, minute, second
'' Get the current date and time as the driver knows it.
'' Returns the live clock value maintained by the worker cog's CT1 tick.
'' If setDate() was never called, returns the default timestamp (2009-01-27 07:00:00).
''
'' @returns year - Year (e.g., 2026)
'' @returns month - Month (1-12)
'' @returns day - Day (1-31)
'' @returns hour - Hour (0-23)
'' @returns minute - Minute (0-59)
'' @returns second - Second (0-58, even values only due to FAT32 2-second granularity)
```

**Implementation**: Uses FIELD operator to read directly from the packed `date_stamp` LONG. No `send_command()` needed — `date_stamp` is in DAT (hub RAM), readable by any cog:

```spin2
PUB getDate() : year, month, day, hour, minute, second
  year   := FIELD[fld_yr][0] + FAT_EPOCH_YEAR
  month  := FIELD[fld_mon][0]
  day    := FIELD[fld_day][0]
  hour   := FIELD[fld_hr][0]
  minute := FIELD[fld_min][0]
  second := FIELD[fld_sec][0] << 1              ' Convert second/2 back to seconds
```

**Why no mailbox round-trip**: `date_stamp` is a single LONG in hub RAM, readable by any cog at any time. The only concern is atomicity — could a caller read mid-update during `tick_clock()`? The tick modifies `date_stamp` in-place via FIELD operations, which are individual read-modify-write cycles on the containing LONG. In the worst case, a caller reads between two FIELD writes and sees, say, second=0 with the old minute (before the carry propagated). This is a 2-second-granularity clock used for file timestamps — a momentary inconsistency at a 2-second boundary is completely acceptable.

**Usage pattern**:

```spin2
' Set time at boot (from RTC, GPS, NTP, or hardcoded)
sd.setDate(2026, 3, 15, 14, 30, 0)

' Later, read it back (clock has been ticking)
year, month, day, hour, minute, second := sd.getDate()
debug("Current time: ", udec_(year), "-", udec_(month), "-", udec_(day), " ", udec_(hour), ":", udec_(minute), ":", udec_(second))
```

---

## Design: Incrementing Directly in Packed Space via FIELD Operator

### The Key Insight: Spin2 FIELD Operator

The P2's Spin2 language provides a `FIELD` operator that gives direct read/write/increment access to arbitrary bit fields within packed data in hub RAM. Using `^@variable.[highBit..lowBit]`, we create a field pointer once, then use `FIELD[ptr][0]` to read, write, increment, or decrement the field in-place — no shifting, no masking, no extraction, no repacking.

This eliminates the need for separate unpacked time variables entirely. The `date_stamp` LONG itself becomes the live clock storage.

### FIELD Pointer Setup

```spin2
DAT
  date_stamp    LONG    0               ' THE live packed timestamp (already exists)
  ct_active     BYTE    0               ' TRUE when clock is running

  ' FIELD pointers into date_stamp (initialized once at worker startup)
  fld_yr        LONG    0               ' ^@date_stamp.[31..25]  Year-1980 (7 bits, 0-127)
  fld_mon       LONG    0               ' ^@date_stamp.[24..21]  Month (4 bits, 1-12)
  fld_day       LONG    0               ' ^@date_stamp.[20..16]  Day (5 bits, 1-31)
  fld_hr        LONG    0               ' ^@date_stamp.[15..11]  Hour (5 bits, 0-23)
  fld_min       LONG    0               ' ^@date_stamp.[10..5]   Minute (6 bits, 0-59)
  fld_sec       LONG    0               ' ^@date_stamp.[4..0]    Second/2 (5 bits, 0-29)
```

**Initialization** (once, in worker cog startup):
```spin2
  fld_yr  := ^@date_stamp.[31..25]
  fld_mon := ^@date_stamp.[24..21]
  fld_day := ^@date_stamp.[20..16]
  fld_hr  := ^@date_stamp.[15..11]
  fld_min := ^@date_stamp.[10..5]
  fld_sec := ^@date_stamp.[4..0]
```

### tick_clock() — Direct In-Place Increment

```spin2
PRI tick_clock()
' Advance the live clock by 2 seconds. Operates directly on the packed
' date_stamp LONG via FIELD pointers — no unpacking, no repacking.

  FIELD[fld_sec][0]++                             ' Increment second/2
  if FIELD[fld_sec][0] >= 30                      ' 30 * 2 = 60 seconds → carry
    FIELD[fld_sec][0]~                            ' Clear to 0
    FIELD[fld_min][0]++
    if FIELD[fld_min][0] >= 60                    ' 60 minutes → carry
      FIELD[fld_min][0]~
      FIELD[fld_hr][0]++
      if FIELD[fld_hr][0] >= 24                   ' 24 hours → carry
        FIELD[fld_hr][0]~
        FIELD[fld_day][0]++
        if FIELD[fld_day][0] > daysInMonth(FIELD[fld_yr][0] + FAT_EPOCH_YEAR, FIELD[fld_mon][0])
          FIELD[fld_day][0] := 1
          FIELD[fld_mon][0]++
          if FIELD[fld_mon][0] > 12               ' 12 months → carry
            FIELD[fld_mon][0] := 1
            FIELD[fld_yr][0]++
```

**No repack step.** Every FIELD operation reads and writes directly in `date_stamp`. When `tick_clock()` returns, `date_stamp` is already the correct packed value, ready to be copied into directory entries.

### setDate() — Direct Field Writes

```spin2
PUB setDate(year, month, day, hour, minute, second)
  FIELD[fld_yr][0]  := year - FAT_EPOCH_YEAR
  FIELD[fld_mon][0] := month
  FIELD[fld_day][0] := day
  FIELD[fld_hr][0]  := hour
  FIELD[fld_min][0] := minute
  FIELD[fld_sec][0] := second >> 1                ' FAT32: seconds stored as second/2

  ' Arm the live clock
  ct_active := true
  ADDCT1(clkfreq * 2)                             ' First tick in 2 seconds
```

### getDate() — Direct Field Reads

```spin2
PUB getDate() : year, month, day, hour, minute, second
  year   := FIELD[fld_yr][0] + FAT_EPOCH_YEAR
  month  := FIELD[fld_mon][0]
  day    := FIELD[fld_day][0]
  hour   := FIELD[fld_hr][0]
  minute := FIELD[fld_min][0]
  second := FIELD[fld_sec][0] << 1                ' Convert second/2 back to seconds
```

### Why This Is Better Than Separate Unpacked Variables

The original Approach A maintained 6 separate LONGs (`cur_year..cur_second`) as the live clock, then repacked them into `date_stamp` after every tick. This meant:
- 6 LONGs (24 bytes) of DAT storage just for unpacked copies
- A repack expression (`(cur_year - FAT_EPOCH_YEAR) << 25 | cur_month << 21 | ...`) executed every 2 seconds
- `setDate()` had to write both the unpacked fields AND the packed LONG
- Two representations of the same data that could drift out of sync

With FIELD, there is **one representation**: the packed `date_stamp` LONG. The FIELD operator provides named, typed access to its fields without extraction or repacking. The `date_stamp` is always consistent because there's only one copy.

### Why This Is Better Than Manual Bit Manipulation

Without FIELD, incrementing in packed space would require explicit shift-and-mask operations:

```spin2
' Without FIELD (manual bit manipulation)
sec := date_stamp & $1F
sec++
if sec >= 30
  sec := 0
  date_stamp := (date_stamp & !$1F)                        ' Clear seconds field
  min := (date_stamp >> 5) & $3F
  min++
  date_stamp := (date_stamp & !($3F << 5)) | (min << 5)    ' Write minutes field
  ' ... and so on, with increasingly complex masks
```

This is error-prone (wrong mask = silent corruption) and harder to read than the FIELD version. The FIELD operator encapsulates the bit manipulation behind a clean indexed access syntax.

### CT1 Tick vs ISR

The P2 supports true hardware interrupts: `SETINT1` can be wired to a CT1 event, vectoring the cog to an ISR handler preemptively. For the timestamp clock:

**POLLCT1 (cooperative polling):**
- Checked once per main loop iteration (2-9 cycles)
- If the worker is mid-SPI-transfer when CT1 fires, the tick is "late" — caught on the next loop iteration
- Worst case: a few seconds of clock skew during very long operations, self-corrects
- Simpler: no ISR context save/restore, no register sharing concerns

**SETINT1 (true ISR):**
- CT1 fires and the cog immediately vectors to the handler — preempts even SPI transfers
- No late-fire skew: timestamp is always accurate to within the 2-second granularity
- Overhead: ~20-30 cycles for ISR entry/exit context save/restore
- ISR must save/restore any registers it touches; FIELD operations touch hub RAM (not cog registers), so this is clean
- More complex: ISR registration, priority concerns if other interrupts are in use

**Decision**: Use POLLCT1 for v1.4.0. The 2-second granularity means a "late" tick during a 50ms SD operation produces at most 50ms of skew — invisible at FAT32's 2-second resolution. The ISR approach is more accurate but adds complexity for no practical benefit at this granularity. If sub-second precision is ever needed, the ISR approach becomes worthwhile.

### On-Demand Calculation Alternative (Considered, Not Chosen)

An alternative approach captures `GETCT()` (the P2's free-running 32-bit cycle counter) at `setDate()` time and computes the elapsed time on demand:

```
elapsed_cycles := GETCT() - base_ct
elapsed_seconds := elapsed_cycles / clkfreq
current_time := base_time + elapsed_seconds
```

**Why not chosen:**
- `GETCT()` is 32 bits. At 350 MHz it wraps every ~12.3 seconds — far too fast for a timestamp counter. Would need 64-bit arithmetic or frequent wrap tracking.
- `GETSEC()` (seconds since boot) avoids the wrap problem (32-bit seconds = ~136 years), but still requires converting total elapsed seconds back to calendar date/time — iterating through years for leap year accounting, division for months/days. That's ~50 lines of math on every create/modify/getDate call.
- The CT1 tick approach amortizes this work: one simple increment every 2 seconds vs. a full seconds-to-calendar conversion on every use.
- With FIELD, the tick approach is especially clean — no conversion at all, just `FIELD[fld_sec][0]++` with carry.

---

## Implementation Tasks

### Task 1: Initialize FIELD Pointers

In the worker cog's startup (after pin initialization, before the main loop):

```spin2
  ' Initialize FIELD pointers for direct date_stamp access
  fld_yr  := ^@date_stamp.[31..25]
  fld_mon := ^@date_stamp.[24..21]
  fld_day := ^@date_stamp.[20..16]
  fld_hr  := ^@date_stamp.[15..11]
  fld_min := ^@date_stamp.[10..5]
  fld_sec := ^@date_stamp.[4..0]
```

Add the 6 FIELD pointer LONGs and `ct_active` BYTE to DAT. Add `days_table` (12 bytes).

### Task 2: Implement tick_clock() and Helpers

- `tick_clock()` — FIELD-based in-place increment with rollover (see code above)
- `daysInMonth(year, month)` — lookup from `days_table` with February leap year check
- `isLeapYear(year)` — `(year & 3) == 0`, except 2100

```spin2
DAT
  days_table  BYTE  31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

PRI daysInMonth(year, month) : days
  days := BYTE[@days_table][month - 1]
  if month == 2 and isLeapYear(year)
    days := 29

PRI isLeapYear(year) : result
  result := (year & 3) == 0
  if year == 2100
    result := false
```

### Task 3: Modify setDate() to Use FIELD and Arm CT1

Replace the current single-line bit-packing expression with FIELD writes:

```spin2
PUB setDate(year, month, day, hour, minute, second)
  FIELD[fld_yr][0]  := year - FAT_EPOCH_YEAR
  FIELD[fld_mon][0] := month
  FIELD[fld_day][0] := day
  FIELD[fld_hr][0]  := hour
  FIELD[fld_min][0] := minute
  FIELD[fld_sec][0] := second >> 1
  ct_active := true
  ADDCT1(clkfreq * 2)
```

### Task 4: Add POLLCT1 Handler to Worker Main Loop

Add to the restructured worker loop (from F1):

```spin2
  if ct_active and POLLCT1()
    tick_clock()
    ADDCT1(clkfreq * 2)
```

### Task 5: Update Modification Timestamp on Write Close/Sync

In `do_close_h()` (line 3114-3123), after updating file size:
```spin2
    ' If opened for write, update directory entry with final size AND modification time
    if h_flags[handle] & HF_WRITE
      if readSector(h_dir_sector[handle], BUF_DIR) < 0
        result := E_IO_ERROR
      else
        long[@dir_buf + h_dir_offset[handle] + DE_FILESIZE_OFFSET] := h_size[handle]
        long[@dir_buf + h_dir_offset[handle] + DE_WRT_TIME_OFFSET] := date_stamp  ' NEW: always current
        writeSector(h_dir_sector[handle], BUF_DIR)
```

Same change in `do_sync_h()` (line 3448). `date_stamp` is always the live packed value — no method call needed.

### Task 6: Add getDate() Public Method

```spin2
PUB getDate() : year, month, day, hour, minute, second
'' Get the current date and time as the driver knows it.
'' Returns the live clock value maintained by the worker cog's CT1 tick.
'' If setDate() was never called, returns the default timestamp.
''
'' @returns year - Year (e.g., 2026)
'' @returns month - Month (1-12)
'' @returns day - Day (1-31)
'' @returns hour - Hour (0-23)
'' @returns minute - Minute (0-59)
'' @returns second - Second (0-58, even values only)

  year   := FIELD[fld_yr][0] + FAT_EPOCH_YEAR
  month  := FIELD[fld_mon][0]
  day    := FIELD[fld_day][0]
  hour   := FIELD[fld_hr][0]
  minute := FIELD[fld_min][0]
  second := FIELD[fld_sec][0] << 1
```

Place adjacent to `setDate()` in the PUB method listing for discoverability.

### Task 7: Initialize Default Values

In `do_mount()`, the existing default `setDate(2009,01,27,07,00,00)` call will now write directly to `date_stamp` via FIELD, so `getDate()` returns sensible values even if the caller never calls `setDate()`. No additional work needed — the enhanced `setDate()` (Task 3) handles this automatically.

### Task 8: Set CrtTimeTenth at Creation

In `do_create()` and `do_open_write()` (new file path), after setting create stamp:
```spin2
    byte[@entry_buffer + 13] := 0    ' DIR_CrtTimeTenth — 0 is spec-compliant
```

Low priority. Value of 0 is spec-compliant.

### Task 9: Regression Tests

- Test that `setDate()` followed by file creation produces correct timestamps
- Test that closing a write handle updates DIR_WrtTime/DIR_WrtDate
- Test that timestamps advance: `setDate()`, wait 4 seconds, create file — verify different timestamp
- Test default timestamp (no `setDate()` call) still produces valid date
- Test `getDate()` round-trip: call `setDate(2026, 3, 15, 14, 30, 0)`, then `getDate()`, verify all 6 values match
- Test `getDate()` advances: call `setDate()`, wait 4 seconds, call `getDate()`, verify second has advanced
- Test `setDate()` rejects out-of-range values: month=13, day=32, hour=25, year=1979, year=2108 all return E_INVALID_PARAM
- Test `setDate()` rejection doesn't corrupt current timestamp: set valid date, attempt invalid date, getDate() still returns the valid date

---

## Design Decisions

### Decision: FIELD Operator for In-Place Packed Increment

Use Spin2's `FIELD` operator to read, write, and increment directly within the packed `date_stamp` LONG. No separate unpacked variables, no extraction, no repacking. One representation, always consistent, always ready for directory entry writes.

### Decision: CT1-Based Live Clock with POLLCT1

Use CT1 to fire every 2 seconds (matching FAT32 granularity). The worker cog polls POLLCT1 in its main loop and calls `tick_clock()` which increments the packed fields in-place. True ISR via SETINT1 is more accurate but unnecessary at 2-second granularity.

### Decision: Backward Compatible

If `setDate()` is never called, behavior is identical to today — static default timestamp. The auto-incrementing clock only activates when `ct_active` is set (i.e., `setDate()` was called).

---

## Code Size Estimate

- FIELD pointer initialization: ~6 lines
- `tick_clock()`: ~20 lines (FIELD increment + rollover)
- `daysInMonth()` + `isLeapYear()`: ~15 lines
- `days_table`: 12 bytes DAT
- `setDate()` changes: ~8 lines (FIELD writes + arm CT1)
- `getDate()`: ~8 lines (FIELD reads + doc comment)
- Worker main loop: ~3 lines (POLLCT1 check)
- Close/sync changes: ~2 lines each (copy `date_stamp` to dir entry)
- New DAT variables: 6 FIELD pointer LONGs + 1 BYTE `ct_active` + 12 bytes `days_table` (37 bytes)

Total: ~62 lines of new code, 37 bytes of new DAT. All Spin2, no PASM needed.

### Decision: setDate() Validates All Six Fields

`setDate()` must validate all 6 parameters before writing to the packed `date_stamp`. Invalid values written via FIELD would produce corrupt timestamps — and unlike the old single-expression packing (which silently truncated via bit width), FIELD writes can place out-of-range values into adjacent fields, corrupting the entire LONG.

**Validation rules:**

| Parameter | Valid Range | On Failure |
|-----------|-----------|------------|
| year | 1980-2107 | Return E_INVALID_PARAM |
| month | 1-12 | Return E_INVALID_PARAM |
| day | 1-daysInMonth(year, month) | Return E_INVALID_PARAM |
| hour | 0-23 | Return E_INVALID_PARAM |
| minute | 0-59 | Return E_INVALID_PARAM |
| second | 0-59 | Return E_INVALID_PARAM |

```spin2
PUB setDate(year, month, day, hour, minute, second) : result
  if year < 1980 or year > 2107
    return set_error(E_INVALID_PARAM)
  if month < 1 or month > 12
    return set_error(E_INVALID_PARAM)
  if day < 1 or day > daysInMonth(year, month)
    return set_error(E_INVALID_PARAM)
  if hour > 23 or minute > 59 or second > 59
    return set_error(E_INVALID_PARAM)

  FIELD[fld_yr][0]  := year - FAT_EPOCH_YEAR
  FIELD[fld_mon][0] := month
  FIELD[fld_day][0] := day
  FIELD[fld_hr][0]  := hour
  FIELD[fld_min][0] := minute
  FIELD[fld_sec][0] := second >> 1
  ct_active := true
  ADDCT1(clkfreq * 2)
  result := SUCCESS
```

Note: This changes `setDate()` from a void method to one that returns a status code. This is consistent with the v1.2.0 convention where all operation methods return SUCCESS (0) or a negative error code.

**Regression test**: Call `setDate()` with out-of-range values (month=13, day=32, hour=25, year=1979, year=2108) and verify each returns E_INVALID_PARAM without modifying the current timestamp.

### Decision: CrtTimeTenth Set to 0

`DIR_CrtTimeTenth` is a single byte that refines the creation timestamp to 100ms precision within the 2-second `DIR_CrtTime` window. Always set to 0. This is spec-compliant, and no embedded use case needs sub-second creation-time precision. The implementation cost of capturing `GETMS()` and computing the offset within the 2-second window is not justified.
