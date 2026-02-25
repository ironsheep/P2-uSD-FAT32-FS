# Sprint Plan: Multi-Cog SD Card Driver Transformation

**Sprint Goal**: Transform SD_card_driver.spin2 into a multi-cog safe singleton with dedicated worker cog

**Status**: PLANNING

---

## Background

### Current State
- Single-cog driver with all state in VAR block
- Direct SPI access from calling cog
- No multi-cog safety
- Works but only safe for single-cog applications

### Target State
- Singleton pattern with all shared state in DAT block
- Dedicated worker cog owns SPI pins and all I/O
- API methods send commands via parameter block in hub memory
- Any cog can safely call file operations
- Lock serializes API command submission
- Regression tests prove multi-cog safety

---

## Design Rationale (Research Summary)

### Why Dedicated Cog Instead of Lock-Based Shared Access?

We evaluated multiple architectures. The dedicated cog approach wins because of **P2 pin architecture**:

**Critical P2 Constraint**: Each cog has its own DIR/OUT registers ($1FA-$1FF). When a cog calls `PINHIGH(pin)` or `PINL(pin)`, it sets bits in THAT COG's private direction and output registers.

**Lock-Based Approach Problems**:
```
Cog 0 wants to access SD:
  1. Acquire lock
  2. PINHIGH(cs), PINHIGH(mosi), PINL(sck)  ← Initialize THIS cog's DIR/OUT
  3. Do SPI transfer
  4. PINFLOAT(cs), PINFLOAT(mosi), PINFLOAT(sck)  ← Must tri-state before release!
  5. Release lock

Cog 1 wants to access SD:
  1. Acquire lock
  2. PINHIGH(cs), PINHIGH(mosi), PINL(sck)  ← Re-initialize for THIS cog
  3. Do SPI transfer
  4. PINFLOAT all pins
  5. Release lock
```

Every single operation requires full pin re-initialization. If a cog forgets to tri-state before releasing, undefined behavior when multiple cogs have DIR=1 on same pin.

**Dedicated Cog Approach**:
```
Worker Cog (initialized once at start):
  PINHIGH(cs), PINHIGH(mosi), PINL(sck)  ← Done ONCE

  repeat forever:
    wait for command
    execute (pins already configured)
    signal done

Other cogs: Just send commands via hub memory, never touch pins
```

**Verdict**: Dedicated cog eliminates per-operation pin overhead and risk of pin conflicts.

### Why Spin2 Worker (COGSPIN) Instead of PASM2 (COGINIT)?

| Factor | PASM2 Worker | Spin2 Worker | Winner |
|--------|--------------|--------------|--------|
| SPI bit-bang timing | Native | Inline PASM2 | **Tie** |
| SD card latency | ~1-10ms per op | ~1-10ms per op | **Tie** |
| FAT/directory logic | Complex in asm | Natural in Spin2 | **Spin2** |
| Code space | 496 longs max | Unlimited (hub) | **Spin2** |
| Maintainability | Difficult | Easy | **Spin2** |

The bottleneck is the SD card hardware, not the P2. The existing inline PASM2 for SPI transfers is kept for the timing-critical bit-banging. Everything else benefits from Spin2's readability.

### Why DAT Block for Singleton?

In Spin2:
- **VAR block**: Each object INSTANCE gets its own copy
- **DAT block**: SHARED across all instances of the object

When multiple .spin2 files each declare `OBJ fs : "SD_FileSystem"`, they all see the SAME DAT block. This is the singleton pattern:

```spin2
' Application.spin2
OBJ
  fs : "SD_FileSystem"      ' ──┐
                                │
' DataLogger.spin2              │     ┌──────────────────────┐
OBJ                             ├────►│  SD_FileSystem DAT   │
  fs : "SD_FileSystem"      ' ──┤     │  (one shared copy)   │
                                │     │  cog_id, api_lock,   │
' SensorManager.spin2           │     │  param_block, etc.   │
OBJ                             │     └──────────────────────┘
  fs : "SD_FileSystem"      ' ──┘

All three "fs" objects share the SAME DAT block!
```

The singleton guard in `start()` checks `if cog_id <> -1` - if already started, return success immediately. First caller starts the cog, subsequent callers get instant success.

### Parameter Block Communication (Not Smart Pins)

Standard P2 pattern using hub memory. No smart pins needed:

1. Define parameter block structure in DAT (hub RAM)
2. Pass address to worker cog via COGSPIN parameter
3. Worker polls `cmd` word; callers use `WAITATN` for efficient waiting
4. Worker signals completion via `COGATN` - instant wake-up, zero hub polling
5. Single hardware lock serializes API calls from multiple cogs

### Why COGATN for Completion Signaling?

Instead of caller polling hub memory for `cmd == 0`, we use the P2's inter-cog attention system:

| Approach | How It Works | Hub Bandwidth | Wake Latency |
|----------|-------------|---------------|--------------|
| **Hub Polling** | `repeat until pb_cmd == 0` | Constant hub access | Variable |
| **COGATN** | `WAITATN` (caller sleeps) | Zero while waiting | 0 clocks |

**COGATN Benefits:**
- Caller cog sleeps (power efficient)
- Zero hub bandwidth consumed during wait
- Instant wake-up when worker signals
- Clean separation of signaling from data

**Implementation:**
```spin2
' Caller stores its cog ID in parameter block
pb_caller := COGID()

' Caller sleeps waiting for attention signal
WAITATN

' Worker signals specific caller when done
COGATN(1 << pb_caller)
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SD_FileSystem (Singleton)                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DAT Block (shared across all instances)                                 │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ cog_id        LONG  -1        ' Worker cog ID (-1 = not started)   │ │
│  │ api_lock      LONG  -1        ' Lock for API call serialization    │ │
│  │ param_block   LONG  0[8]      ' Command/response communication     │ │
│  │ cog_stack     LONG  0[128]    ' Worker cog stack                   │ │
│  │ pin_cs/mosi/miso/sck          ' SPI pin assignments                │ │
│  │ buf[512]                      ' Sector buffer                      │ │
│  │ ... all filesystem state ...  ' FAT, directory, file state         │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  PUB start()    ─── singleton guard, starts worker if not running        │
│  PUB stop()     ─── stops worker cog                                     │
│  PUB open()     ─── sends CMD_OPEN via param_block                       │
│  PUB read()     ─── sends CMD_READ via param_block                       │
│  PUB write()    ─── sends CMD_WRITE via param_block                      │
│  PUB close()    ─── sends CMD_CLOSE via param_block                      │
│  ... etc ...                                                             │
│                                                                          │
│  PRI fs_worker() ─── runs in dedicated cog, owns SPI, processes cmds     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

  Any Cog ────► api_lock ────► param_block ────► Worker Cog ────► SPI/SD Card
                (serialize)    (hub memory)      (dedicated)
```

---

## Sprint Tasks

### Phase 1: Object Structure Transformation

- [ ] **1.1** Move all VAR declarations to DAT block
  - `cog_id` initialized to -1
  - `api_lock` initialized to -1
  - `buf[512]` sector buffer
  - All filesystem state variables
  - Worker cog stack

- [ ] **1.2** Define parameter block structure
  - Command word (0 = idle)
  - Status/result code
  - Caller cog ID (for COGATN signaling)
  - Parameter slots (4 longs)
  - Result data slots (2 longs)

- [ ] **1.3** Define command constants
  - CMD_NONE, CMD_MOUNT, CMD_OPEN, CMD_CLOSE
  - CMD_READ, CMD_WRITE, CMD_SEEK
  - CMD_MKDIR, CMD_DELETE, CMD_RENAME
  - CMD_READDIR, CMD_CHDIR
  - Error codes

### Phase 2: Worker Cog Implementation

- [ ] **2.1** Create `fs_worker()` method
  - Initialize SPI pins (one-time, this cog only)
  - Command polling loop
  - Command dispatch (CASE statement)
  - Result/status reporting
  - Signal completion via `COGATN(1 << pb_caller)`

- [ ] **2.2** Refactor existing operations as internal methods
  - `do_mount()` - internal mount logic
  - `do_open()` - internal open logic
  - `do_read()` - internal read logic
  - `do_write()` - internal write logic
  - `do_close()` - internal close logic
  - ... etc for all operations

- [ ] **2.3** Keep inline PASM2 for SPI transfers
  - `readSector()` - fast PASM2 SPI read
  - `writeSector()` - fast PASM2 SPI write
  - `transfer()` - bit-level SPI transfer

- [ ] **2.4** **FIX: Add timeout to `readSector()` start-token wait** ⚠️
  - Current code loops forever if card doesn't respond (lines 893-898)
  - Add ADDCT1/POLLCT1 timeout check in `.startloop`
  - Return error status on timeout instead of hanging
  - **This is a critical reliability bug**
  ```pasm2
  ' Current (BROKEN):
  .startloop
                  testp     _miso         wc
    if_c          jmp       #.startloop     ' HANGS FOREVER!

  ' Fixed:
                  GETCT     timeout
                  ADDCT1    timeout, ##clkfreq   ' 1 second timeout
  .startloop
                  POLLCT1   WC
    if_c          jmp       #.timeout_error      ' Bail on timeout
                  drvh      _sck
                  nop
                  drvl      _sck
                  testp     _miso         wc
    if_c          jmp       #.startloop
  ```

### Phase 3: Public API Transformation

- [ ] **3.1** Implement singleton `start()` method
  - Guard: if `cog_id <> -1` return true
  - Allocate hardware lock
  - Store pin configuration
  - Start worker cog via COGSPIN
  - Wait for mount completion
  - Return mount status

- [ ] **3.2** Implement `stop()` method
  - Stop worker cog
  - Return hardware lock
  - Reset cog_id to -1

- [ ] **3.3** Transform all public methods to command pattern
  - Acquire api_lock
  - Set pb_caller = COGID() for COGATN signaling
  - Set parameters in param_block
  - Set command word (triggers worker)
  - `WAITATN` for efficient completion waiting
  - Read result
  - Release api_lock

### Phase 4: Multi-Cog Regression Testing

- [ ] **4.1** Create `SD_RT_multicog_tests.spin2`
  - Test framework setup
  - Launch multiple test cogs

- [ ] **4.2** Implement concurrent access tests
  - Multiple cogs calling `open()` simultaneously
  - Multiple cogs reading same file
  - Multiple cogs reading different files
  - Multiple cogs writing to different files
  - Stress test: rapid open/read/close cycles

- [ ] **4.3** Implement singleton verification tests
  - Verify only one worker cog started
  - Verify multiple `start()` calls succeed without extra cogs
  - Verify DAT state is truly shared

- [ ] **4.4** Implement contention tests
  - High contention scenario (all 7 cogs hammering FS)
  - Verify no data corruption
  - Verify no deadlocks
  - Verify proper serialization

### Phase 5: Documentation and Cleanup

- [ ] **5.1** Update API documentation
  - Document singleton behavior
  - Document thread safety guarantees
  - Document error codes

- [ ] **5.2** Update CLAUDE.md if needed

- [ ] **5.3** Run full regression suite
  - All existing tests still pass
  - New multi-cog tests pass

---

## Parameter Block Protocol

```
Offset  Name        Direction       Description
──────────────────────────────────────────────────────────────
0       cmd         Caller→Worker   Command code (0 = idle/done)
4       status      Worker→Caller   Result status (0 = success)
8       caller      Caller→Worker   Caller's cog ID (for COGATN)
12      param0      Caller→Worker   First parameter
16      param1      Caller→Worker   Second parameter
20      param2      Caller→Worker   Third parameter
24      param3      Caller→Worker   Fourth parameter
28      data0       Worker→Caller   Result data (handle, count, etc.)
32      data1       Worker→Caller   Additional result data
```

### Command Flow (with COGATN Signaling)

```
Caller Cog                              Worker Cog
───────────────────────────────────────────────────────────────
1. Acquire api_lock
2. Write caller = COGID()
3. Write param0..param3
4. Write cmd (non-zero)  ─────────────► 5. See cmd != 0
5. WAITATN (sleep)                      6. Read caller, params
   │                                    7. Execute operation
   │                                    8. Write status, data
   │                                    9. Write cmd = 0
   │                                   10. COGATN(1 << caller)
   ▼                                       │
6. Wake up  ◄──────────────────────────────┘
7. Read status, data
8. Release api_lock
```

**Key advantage**: Caller cog is asleep during steps 6-9 (zero hub bandwidth).

---

## File Handle Strategy

**Option A: Single Active File (Simple)**
- Only one file open at a time
- Matches current driver behavior
- Simplest implementation

**Option B: Handle Table (More Capable)**
- Support N simultaneous open files (e.g., 4)
- Handle = index into table
- Each entry: cluster, position, size, flags
- More complex but more useful

**Decision**: TBD - discuss with user

---

## Testing Strategy

### Test Card Requirements
- Use existing TESTROOT test files
- Known file sizes and contents for verification

### Multi-Cog Test Pattern
```spin2
CON
  NUM_TEST_COGS = 4

DAT
  test_stacks   LONG  0[NUM_TEST_COGS * 64]
  test_results  LONG  0[NUM_TEST_COGS]

PUB run_multicog_test() | i
  ' Start test cogs
  repeat i from 0 to NUM_TEST_COGS-1
    COGSPIN(NEWCOG, test_worker(i), @test_stacks[i * 64])

  ' Wait for all to complete
  repeat i from 0 to NUM_TEST_COGS-1
    repeat until test_results[i] <> 0

  ' Check results
  repeat i from 0 to NUM_TEST_COGS-1
    if test_results[i] < 0
      fail(string("Cog test failed"))

PRI test_worker(cog_index)
  ' Each cog does file operations
  fs.start(...)  ' Singleton - all get same instance
  handle := fs.open(test_file[cog_index])
  bytes := fs.read(handle, @buffer, 512)
  fs.close(handle)
  test_results[cog_index] := bytes  ' Report success
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| DAT initialization order issues | Medium | High | Explicit -1 init values |
| Stack size insufficient | Low | High | Start with 128 longs, monitor |
| Lock exhaustion | Low | Medium | Check LOCKNEW result |
| Command protocol bugs | Medium | High | Thorough testing |
| Inline PASM2 compatibility | Low | Medium | Keep existing proven code |

---

## Open Questions

1. **File handle strategy**: Single file or handle table?
2. **Error reporting**: How to report async errors to caller?
3. **Timeout handling**: Should API calls have timeouts?
   - *Note*: P2 events can implement timeouts by racing WAITATN against CT comparison.
   - Example: Configure SE1 for CT1 timeout, poll both POLLATN and POLLSE1 in loop.
   - Decision deferred - simple blocking calls first, add timeout option later if needed.
4. **Buffer ownership**: Who owns read/write buffers during transfer?

---

## Implementation Reference

### DAT Block Structure (Target)

```spin2
DAT
  ' ═══════════════════════════════════════════════════════════════════════
  ' SINGLETON CONTROL - Must be initialized to "not started" state
  ' ═══════════════════════════════════════════════════════════════════════
  cog_id        LONG    -1              ' Worker cog ID (-1 = not started)
  api_lock      LONG    -1              ' Hardware lock ID (-1 = not allocated)

  ' ═══════════════════════════════════════════════════════════════════════
  ' PARAMETER BLOCK - Communication between API and worker cog
  ' ═══════════════════════════════════════════════════════════════════════
  pb_cmd        LONG    0               ' Command (0 = idle/done)
  pb_status     LONG    0               ' Result status code
  pb_caller     LONG    0               ' Caller's cog ID (for COGATN signal)
  pb_param0     LONG    0               ' Parameter 0 (varies by command)
  pb_param1     LONG    0               ' Parameter 1
  pb_param2     LONG    0               ' Parameter 2
  pb_param3     LONG    0               ' Parameter 3
  pb_data0      LONG    0               ' Result data 0 (handle, count, etc.)
  pb_data1      LONG    0               ' Result data 1

  ' ═══════════════════════════════════════════════════════════════════════
  ' WORKER COG STACK
  ' ═══════════════════════════════════════════════════════════════════════
  cog_stack     LONG    0[128]          ' 128 longs = 512 bytes

  ' ═══════════════════════════════════════════════════════════════════════
  ' SPI PIN CONFIGURATION (set once at start)
  ' ═══════════════════════════════════════════════════════════════════════
  pin_cs        LONG    0
  pin_mosi      LONG    0
  pin_miso      LONG    0
  pin_sck       LONG    0

  ' ═══════════════════════════════════════════════════════════════════════
  ' FILESYSTEM STATE (moved from VAR)
  ' ═══════════════════════════════════════════════════════════════════════
  fat_sec       LONG    0               ' Starting sector of FAT
  fat2_sec      LONG    0               ' Starting sector of FAT2 (mirror)
  sec_per_fat   LONG    0               ' Sectors per FAT
  sec_per_clus  LONG    0               ' Sectors per cluster
  root_sec      LONG    0               ' Starting sector of root directory
  cluster_offset LONG   0               ' Cluster offset calculation
  dir_sec       LONG    0               ' Current directory sector
  entry_address LONG    0               ' Current entry byte address
  date_stamp    LONG    0               ' Timestamp for new files
  n_sec         LONG    0               ' Current sector number
  file_idx      LONG    0               ' Position within file
  flags         LONG    0               ' Open/new file flags
  sec_in_buf    LONG    0               ' Sector currently in buffer
  bit_delay     LONG    0               ' SPI bit delay
  hcs           LONG    0               ' High capacity support flag
  fsinfo_sec    LONG    0               ' FSInfo sector number
  fsi_free_count LONG   0               ' Cached free cluster count
  fsi_nxt_free  LONG    0               ' Cached next free cluster hint
  vbr_sec       LONG    0               ' Volume Boot Record sector

  ' ═══════════════════════════════════════════════════════════════════════
  ' BUFFERS (must be in DAT for worker cog access)
  ' ═══════════════════════════════════════════════════════════════════════
  buf           BYTE    0[512]          ' Main sector buffer
  entry_buffer  BYTE    0[32]           ' Directory entry buffer
  vol_label     BYTE    0[12]           ' Volume label (11 chars + null)
```

### Singleton Start Pattern

```spin2
PUB start(_cs, _mosi, _miso, _sck) : result
  '' Start filesystem driver (singleton - only first call starts cog)
  '' Returns: true if started/running, false on failure

  ' ─── SINGLETON GUARD ───
  if cog_id <> -1
    return true                         ' Already running, success

  ' ─── FIRST-TIME INITIALIZATION ───

  ' Allocate hardware lock
  api_lock := LOCKNEW()
  if api_lock == -1
    return false                        ' No locks available

  ' Store pin configuration in DAT
  pin_cs := _cs
  pin_mosi := _mosi
  pin_miso := _miso
  pin_sck := _sck

  ' Initialize parameter block for mount command
  pb_cmd := CMD_MOUNT
  pb_status := 0

  ' Start worker cog
  cog_id := COGSPIN(NEWCOG, fs_worker(), @cog_stack)
  if cog_id == -1
    LOCKRET(api_lock)
    api_lock := -1
    return false                        ' No cogs available

  ' Wait for mount to complete
  repeat until pb_cmd == CMD_NONE

  ' Check mount result
  if pb_status <> 0
    COGSTOP(cog_id)
    cog_id := -1
    LOCKRET(api_lock)
    api_lock := -1
    return false                        ' Mount failed

  return true
```

### API Method Pattern (All Public Methods Follow This)

```spin2
PUB open(filename) : handle
  '' Open a file for reading/writing
  '' Returns: handle >= 0 on success, -1 on failure

  if cog_id == -1
    return -1                           ' Not started

  ' Serialize API access
  repeat until LOCKTRY(api_lock)

  ' Set up command
  pb_caller := COGID()                  ' Store our cog ID for COGATN
  pb_param0 := filename                 ' Pointer to filename string
  pb_cmd := CMD_OPEN                    ' Trigger command

  ' Wait for completion (efficient - cog sleeps)
  WAITATN                               ' Sleep until worker signals us

  ' Get result
  if pb_status == 0
    handle := pb_data0                  ' Success: return handle
  else
    handle := -1                        ' Failure

  LOCKREL(api_lock)


PUB read(handle, p_buffer, count) : bytes_read
  '' Read bytes from open file
  '' Returns: number of bytes read, or -1 on error

  if cog_id == -1
    return -1

  repeat until LOCKTRY(api_lock)

  pb_caller := COGID()                  ' Store our cog ID for COGATN
  pb_param0 := handle
  pb_param1 := p_buffer                 ' Caller's buffer (hub address)
  pb_param2 := count
  pb_cmd := CMD_READ

  WAITATN                               ' Sleep until worker signals us

  if pb_status == 0
    bytes_read := pb_data0
  else
    bytes_read := -1

  LOCKREL(api_lock)
```

### Worker Cog Structure

```spin2
PRI fs_worker() | cmd, caller_mask
  '' Worker cog - owns SPI pins, processes all filesystem commands
  '' Runs until COGSTOP() called by stop()

  ' ─── ONE-TIME PIN INITIALIZATION ───
  ' Only this cog ever drives the SPI pins
  pinh(pin_cs)                          ' CS high (deselected)
  pinh(pin_mosi)                        ' MOSI high
  pinl(pin_sck)                         ' SCK low (SPI mode 0)

  ' ─── PROCESS INITIAL MOUNT COMMAND ───
  pb_status := do_mount()
  pb_cmd := CMD_NONE                    ' Signal completion
  ' Note: start() polls pb_cmd for mount (before caller can use WAITATN)

  ' ─── COMMAND PROCESSING LOOP ───
  repeat
    ' Wait for command
    repeat until (cmd := pb_cmd) <> CMD_NONE

    ' Dispatch command
    case cmd
      CMD_OPEN:
        pb_status := do_open(pb_param0)
        pb_data0 := current_handle      ' Return handle

      CMD_CLOSE:
        pb_status := do_close(pb_param0)

      CMD_READ:
        pb_status := do_read(pb_param0, pb_param1, pb_param2)
        pb_data0 := bytes_transferred

      CMD_WRITE:
        pb_status := do_write(pb_param0, pb_param1, pb_param2)
        pb_data0 := bytes_written

      CMD_SEEK:
        pb_status := do_seek(pb_param0, pb_param1)

      CMD_MKDIR:
        pb_status := do_mkdir(pb_param0)

      CMD_DELETE:
        pb_status := do_delete(pb_param0)

      CMD_READDIR:
        pb_status := do_readdir(pb_param0)
        pb_data0 := entry_valid

      CMD_CHDIR:
        pb_status := do_chdir(pb_param0)

      CMD_FILESIZE:
        pb_status := do_filesize(pb_param0)
        pb_data0 := file_size

      CMD_FREESPACE:
        pb_status := do_freespace()
        pb_data0 := free_sectors

      other:
        pb_status := ERR_INVALID_CMD

    ' ─── SIGNAL COMMAND COMPLETE ───
    caller_mask := 1 << pb_caller       ' Build mask for calling cog
    pb_cmd := CMD_NONE                  ' Clear command (visible to any observer)
    COGATN(caller_mask)                 ' Wake up the waiting caller cog!
```

### Command Constants

```spin2
CON
  ' ─── Commands ───
  CMD_NONE      = 0         ' Idle / command complete
  CMD_MOUNT     = 1         ' Mount filesystem (internal, called by start)
  CMD_OPEN      = 2         ' Open file: param0=filename
  CMD_CLOSE     = 3         ' Close file: param0=handle
  CMD_READ      = 4         ' Read: param0=handle, param1=buffer, param2=count
  CMD_WRITE     = 5         ' Write: param0=handle, param1=buffer, param2=count
  CMD_SEEK      = 6         ' Seek: param0=handle, param1=position
  CMD_MKDIR     = 7         ' Create directory: param0=dirname
  CMD_DELETE    = 8         ' Delete file: param0=filename
  CMD_RENAME    = 9         ' Rename: param0=oldname, param1=newname
  CMD_READDIR   = 10        ' Read directory entry: param0=index
  CMD_CHDIR     = 11        ' Change directory: param0=dirname
  CMD_FILESIZE  = 12        ' Get file size: param0=handle
  CMD_FREESPACE = 13        ' Get free space
  CMD_SYNC      = 14        ' Flush buffers
  CMD_UNMOUNT   = 15        ' Clean unmount

  ' ─── Status/Error Codes ───
  ERR_OK        = 0         ' Success
  ERR_NOT_FOUND = -1        ' File/directory not found
  ERR_EXISTS    = -2        ' File/directory already exists
  ERR_FULL      = -3        ' Disk full
  ERR_IO        = -4        ' I/O error (card communication)
  ERR_INVALID   = -5        ' Invalid parameter
  ERR_NOT_OPEN  = -6        ' File not open
  ERR_READ_ONLY = -7        ' Write to read-only file
  ERR_NOT_DIR   = -8        ' Not a directory
  ERR_IS_DIR    = -9        ' Is a directory (can't open as file)
  ERR_INVALID_CMD = -10     ' Unknown command
```

### Multi-Cog Test Structure

```spin2
' SD_RT_multicog_tests.spin2
CON
  NUM_TEST_COGS = 4
  STACK_SIZE = 64

OBJ
  fs : "SD_card_driver"
  ut : "SD_RT_utilities"

DAT
  test_stacks   LONG    0[NUM_TEST_COGS * STACK_SIZE]
  test_results  LONG    0[NUM_TEST_COGS]   ' 0=running, >0=pass, <0=fail
  test_phase    LONG    0                   ' Coordination

PUB main()
  ut.start_test_run(string("Multi-Cog Tests"))

  ' Start filesystem (singleton)
  if not fs.start(CS_PIN, MOSI_PIN, MISO_PIN, SCK_PIN)
    ut.fail(string("Failed to start filesystem"))
    return

  run_singleton_tests()
  run_concurrent_read_tests()
  run_concurrent_write_tests()
  run_stress_tests()

  fs.stop()
  ut.end_test_run()

PRI run_singleton_tests() | cog1, cog2
  ut.start_group(string("Singleton Behavior"))

  ' Verify only one cog started
  ut.assert_equals(fs.getCogId(), fs.getCogId(), string("Same cog ID"))

  ' Call start() again - should succeed without starting another cog
  cog1 := fs.getCogId()
  fs.start(CS_PIN, MOSI_PIN, MISO_PIN, SCK_PIN)  ' Second start
  cog2 := fs.getCogId()
  ut.assert_equals(cog1, cog2, string("No new cog on second start"))

  ut.end_group()

PRI run_concurrent_read_tests() | i
  ut.start_group(string("Concurrent Reads"))

  ' Reset results
  repeat i from 0 to NUM_TEST_COGS-1
    test_results[i] := 0

  ' Launch test cogs
  repeat i from 0 to NUM_TEST_COGS-1
    COGSPIN(NEWCOG, read_test_worker(i), @test_stacks[i * STACK_SIZE])

  ' Wait for all to complete
  repeat i from 0 to NUM_TEST_COGS-1
    repeat until test_results[i] <> 0
    if test_results[i] < 0
      ut.fail(string("Read worker failed"))

  ut.end_group()

PRI read_test_worker(cog_index) | handle, buf[128], bytes
  ' Each worker reads a different file
  handle := fs.open(@test_files[cog_index])
  if handle < 0
    test_results[cog_index] := -1
    return

  bytes := fs.read(handle, @buf, 512)
  fs.close(handle)

  if bytes > 0
    test_results[cog_index] := bytes    ' Success
  else
    test_results[cog_index] := -2       ' Read failed

PRI run_stress_tests() | i, iterations
  ut.start_group(string("Stress Test"))

  iterations := 100
  repeat i from 0 to NUM_TEST_COGS-1
    test_results[i] := 0

  repeat i from 0 to NUM_TEST_COGS-1
    COGSPIN(NEWCOG, stress_worker(i, iterations), @test_stacks[i * STACK_SIZE])

  repeat i from 0 to NUM_TEST_COGS-1
    repeat until test_results[i] <> 0
    ut.assert_greater(test_results[i], 0, string("Stress worker completed"))

  ut.end_group()

PRI stress_worker(cog_index, iterations) | handle, buf[128], n
  repeat iterations
    handle := fs.open(string("/TESTROOT/test.txt"))
    if handle >= 0
      fs.read(handle, @buf, 64)
      fs.close(handle)
      n++
  test_results[cog_index] := n
```

---

## Existing Code to Preserve

The following inline PASM2 sections should be kept largely unchanged (they're proven and performant):

1. **`readSector()`** (lines 881-918) - Fast PASM2 SPI sector read
2. **`writeSector()`** (lines 920-956) - Fast PASM2 SPI sector write
3. **`transfer()`** (lines 958-976) - Bit-level SPI transfer

These need only minor changes:
- Access pin variables from DAT instead of VAR
- May need to pass pin values as parameters if PASM2 can't directly access DAT longs

---

## Migration Checklist

### Before Starting
- [ ] Ensure all existing regression tests pass
- [ ] Create backup branch

### Phase 1 Checklist
- [ ] Create new file or branch for transformed driver
- [ ] Move all VAR to DAT with proper initialization
- [ ] Add parameter block structure
- [ ] Add command constants
- [ ] Verify compilation

### Phase 2 Checklist
- [ ] Create fs_worker() shell
- [ ] Refactor mount logic to do_mount()
- [ ] Refactor open/close to do_open(), do_close()
- [ ] Refactor read/write to do_read(), do_write()
- [ ] Implement command dispatch loop
- [ ] Test basic single-cog operation

### Phase 3 Checklist
- [ ] Implement singleton start() with guard
- [ ] Implement stop()
- [ ] Transform all PUB methods to command pattern
- [ ] Test single-cog operation through new API

### Phase 4 Checklist
- [ ] Create SD_RT_multicog_tests.spin2
- [ ] Implement singleton verification tests
- [ ] Implement concurrent read tests
- [ ] Implement concurrent write tests
- [ ] Implement stress tests
- [ ] All tests pass

### Final Checklist
- [ ] All original regression tests still pass
- [ ] New multi-cog tests pass
- [ ] Documentation updated
- [ ] Code reviewed

---

## Notes

- Keep existing inline PASM2 for SPI - it's proven and fast
- Worker cog uses Spin2 via COGSPIN (not pure PASM2)
- All pin initialization happens once in worker cog
- Sector buffer stays in DAT (shared, worker-owned)
- The transformation preserves existing functionality while adding multi-cog safety

---

*Last Updated: 2026-01-17*
*Sprint Status: PLANNING*
