# Plan: DEBUG_MASK Channel Conversion for micro_sd_fat32_fs.spin2

**Date:** 2026-03-07
**Status:** PLANNED
**Prerequisite:** Spin2 v46 (`{Spin2_v46}` directive)

---

## 1. Problem

The driver has **402 debug() statements** across 88 methods. The P2 debug system has a hard limit of **255 unique debug records**. With `DEBUG_DISABLE = 1` (current production setting), none compile — but when a developer needs to debug, enabling debug produces 402 records, exceeding the limit by 60%.

The current workaround is all-or-nothing: either every debug statement compiles (and hits the limit), or none do. There is no way to enable debug output for just the subsystem under investigation.

---

## 2. Solution

Convert all 402 `debug()` statements to `debug[N]()` form with 10 named channels. Developers enable 2-3 channels at a time via `DEBUG_MASK`, staying well under 255 records while getting targeted diagnostic output.

---

## 3. Channel Assignments

### Channel Map

| Channel | Constant | Statements | Purpose |
|---|---|---|---|
| 0 | `CH_INIT` | ~69 | Card initialization, pin setup, speed config |
| 1 | `CH_MOUNT` | ~39 | Mount/unmount, filesystem geometry, FSInfo, volume label |
| 2 | `CH_FILE` | ~63 | File handle lifecycle: open, close, read, write, seek, sync |
| 3 | `CH_DIR` | ~49 | Directory operations: search, create, rename, move, chdir |
| 4 | `CH_SECTOR` | ~45 | Sector I/O, FAT chain walking, cluster allocation |
| 5 | `CH_STATUS` | ~43 | CMD13 probe/check, CMD23 probe, card status decoding |
| 6 | `CH_IDENT` | ~35 | Card identity: CID/CSD/SCR parsing, timeouts, manufacturer |
| 7 | `CH_HSPEED` | ~25 | High-speed mode: CMD6 query, switch, 50 MHz verification |
| 8 | `CH_API` | ~25 | Public API entry points, worker cog dispatch, stack guard |
| 9 | `CH_RECOVER` | ~9 | Error recovery: CMD12, bus recovery, wait timeouts |

**Total: 402 statements across 10 channels.**

### Typical Debug Scenarios

| Scenario | Channels | Records |
|---|---|---|
| Card won't initialize | CH_INIT | ~69 |
| Mount failure | CH_INIT + CH_MOUNT | ~108 |
| File read/write bug | CH_FILE + CH_SECTOR | ~108 |
| Directory corruption | CH_DIR + CH_SECTOR | ~94 |
| CMD13 investigation | CH_STATUS | ~43 |
| Speed negotiation | CH_IDENT + CH_HSPEED | ~60 |
| API call tracing | CH_API + CH_FILE | ~88 |
| Full init debug | CH_INIT + CH_MOUNT + CH_IDENT | ~143 |

Every combination stays well under 255.

---

## 4. Method-to-Channel Mapping

### CH_INIT (0) — Card Initialization (~69 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `initCard()` | 40 | — |
| `cmd()` | 3 | — |
| `initSPIPins()` | 11 | — |
| `applySPISpeed()` | 3 | — |
| `sp_transfer_8()` | 1 | — |
| `initCardOnly()` | 6 | `SD_INCLUDE_RAW` |
| `do_init_card_only()` | 5 | — |

### CH_MOUNT (1) — Mount/Unmount, Filesystem Geometry (~39 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `do_mount()` | 25 | — |
| `do_unmount()` | 1 | — |
| `updateFSInfo()` | 5 | — |
| `do_set_vol_label()` | 6 | — |
| `do_freespace()` | 1 | — |
| `do_sync()` | 1 | — |

### CH_FILE (2) — File Handle Operations (~63 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `do_open_read()` | 5 | — |
| `do_open_write()` | 5 | — |
| `do_create()` | 8 | — |
| `do_close()` | 2 | — |
| `do_close_h()` | 4 | — |
| `do_read_h()` | 10 | — |
| `do_write_h()` | 12 | — |
| `do_seek_h()` | 8 | — |
| `do_sync_h()` | 6 | — |
| `do_sync_all()` | 3 | — |

### CH_DIR (3) — Directory Operations (~49 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `searchDirectory()` | 5 | — |
| `do_open_dir()` | 4 | — |
| `do_read_dir_h()` | 2 | — |
| `do_close_dir_h()` | 1 | — |
| `do_newfile()` | 1 | — |
| `do_newdir()` | 10 | — |
| `do_chdir()` | 2 | — |
| `do_readdir()` | 1 | — |
| `do_rename()` | 9 | — |
| `do_movefile()` | 8 | — |
| `debugDumpRootDir()` | 6 | `SD_INCLUDE_DEBUG` |

### CH_SECTOR (4) — Sector I/O, FAT, Clusters (~45 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `readSector()` | 4 | — |
| `readSectors()` | 11 | — |
| `writeSector()` | 5 | — |
| `writeSectors()` | 6 | — |
| `readNextSector()` | 3 | — |
| `readFat()` | 1 | — |
| `allocateCluster()` | 3 | — |
| `followFatChain()` | 1 | — |
| `countFreeClusters()` | 1 | — |
| `readSectorRaw()` | 3 | `SD_INCLUDE_RAW` |
| `writeSectorRaw()` | 3 | `SD_INCLUDE_RAW` |
| `readVBRRaw()` | 1 | `SD_INCLUDE_RAW` |
| `readSectorSlow()` | 1 | `SD_INCLUDE_DEBUG` |
| `displaySector()` | 1 | `SD_INCLUDE_DEBUG` |
| `displayFAT()` | 1 | `SD_INCLUDE_DEBUG` |

### CH_STATUS (5) — CMD13/CMD23, Card Status (~43 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `probeCmd13()` | 7 | — |
| `checkCardStatus()` | 11 | — |
| `probeCmd23()` | 5 | — |
| `testCMD13()` | 18 | `SD_INCLUDE_RAW` |
| `do_test_cmd13()` | 0 | `SD_INCLUDE_DEBUG` (no debug stmts after collapse) |
| `readSCR()` | 1 | — |
| `readSDStatus()` | 1 | — |

### CH_IDENT (6) — Card Identity, Register Parsing (~35 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `identifyCard()` | 8 | — |
| `parseTransSpeed()` | 1 | — |
| `parseMfrId()` | 1 | — |
| `parseTimeouts()` | 3 | — |
| `setOptimalSpeed()` | 2 | — |
| `do_get_card_size()` | 3 | — |
| `readCIDRaw()` | 2 | `SD_INCLUDE_REGISTERS` |
| `readCSDRaw()` | 2 | `SD_INCLUDE_REGISTERS` |
| `readSCRRaw()` | 2 | `SD_INCLUDE_REGISTERS` |
| `readSDStatusRaw()` | 2 | `SD_INCLUDE_REGISTERS` |
| `getOCR()` | 1 | `SD_INCLUDE_REGISTERS` |
| `do_read_scr()` | 2 | `SD_INCLUDE_REGISTERS` |
| `do_read_cid()` | 2 | `SD_INCLUDE_REGISTERS` |
| `do_read_csd()` | 2 | `SD_INCLUDE_REGISTERS` |
| `do_read_sd_status()` | 2 | `SD_INCLUDE_REGISTERS` |

### CH_HSPEED (7) — High-Speed Mode (~25 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `queryHighSpeedSupport()` | 8 | `SD_INCLUDE_SPEED` (via caller) |
| `switchToHighSpeed()` | 4 | `SD_INCLUDE_SPEED` (via caller) |
| `do_attempt_high_speed()` | 11 | `SD_INCLUDE_SPEED` |
| `checkCMD6Support()` | 2 | `SD_INCLUDE_SPEED` |

### CH_API (8) — Public API, Worker Cog (~25 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `start()` | 4 | — |
| `stop()` | 1 | — |
| `mount()` | 5 | — |
| `unmount()` | 1 | — |
| `openFileRead()` | 2 | — |
| `openFileWrite()` | 2 | — |
| `createFileNew()` | 2 | — |
| `closeFileHandle()` | 2 | — |
| `readHandle()` | 1 | — |
| `writeHandle()` | 1 | — |
| `seekHandle()` | 1 | — |
| `syncHandle()` | 1 | — |
| `syncAllHandles()` | 1 | — |
| `sync()` | 1 | — |
| `cardSizeSectors()` | 2 | `SD_INCLUDE_RAW` |

### CH_RECOVER (9) — Error Recovery, Wait Timeouts (~9 statements)

| Method | Stmts | Conditional |
|---|---|---|
| `sendStopTransmission()` | 2 | — |
| `recoverToIdle()` | 2 | — |
| `waitDataToken()` | 2 | — |
| `waitDataResponse()` | 1 | — |
| `waitBusyComplete()` | 1 | — |
| `displayEntry()` | 1 | `SD_INCLUDE_DEBUG` |

### Unassigned — Worker Cog Dispatch

| Method | Stmts | Conditional | Assigned |
|---|---|---|---|
| `fs_worker()` | 3 unconditional | — | CH_API |
| `fs_worker()` | 1 (WRITE_RAW bytemove trace) | `SD_INCLUDE_RAW` | CH_SECTOR |
| `send_command()` | 2 | — | CH_API |
| `checkStackGuard()` | 1 | — | CH_API |

---

## 5. Code Changes

### 5.1 Add Version Directive

The file must begin with `{Spin2_v46}` (or later) before any other code:

```spin2
{Spin2_v46}
' =============================================
' micro_sd_fat32_fs.spin2
' ...
```

### 5.2 Add Channel Constants and DEBUG_MASK

Add to the CON section, near `DEBUG_DISABLE`:

```spin2
CON ' Debug channel assignments for selective debug (see Debug-Strategy-Guide.md)
  CH_INIT    = 0              ' Card initialization, pin setup, speed config
  CH_MOUNT   = 1              ' Mount/unmount, filesystem geometry, FSInfo
  CH_FILE    = 2              ' File handle operations: open, close, read, write, seek, sync
  CH_DIR     = 3              ' Directory operations: search, create, rename, move
  CH_SECTOR  = 4              ' Sector I/O, FAT chain walking, cluster allocation
  CH_STATUS  = 5              ' CMD13/CMD23 probe and runtime status checks
  CH_IDENT   = 6              ' Card identity: CID/CSD/SCR parsing, timeouts
  CH_HSPEED  = 7              ' High-speed mode: CMD6 query, switch, verification
  CH_API     = 8              ' Public API entry points, worker cog, stack guard
  CH_RECOVER = 9              ' Error recovery: CMD12, bus recovery, wait timeouts

  ' Enable channels you are actively debugging (max 2-3 at a time to stay under 255 records).
  ' Examples:
  '   DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)           ' Debug mount failures
  '   DEBUG_MASK = (1 << CH_FILE) | (1 << CH_SECTOR)          ' Debug file read/write
  '   DEBUG_MASK = (1 << CH_STATUS)                           ' Debug CMD13 issues
  '   DEBUG_MASK = -1                                         ' ALL channels (will exceed 255!)
  DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)               ' Default: init + mount
```

### 5.3 Convert All debug() to debug[N]()

Every `debug(` call becomes `debug[CH_xxx](` where CH_xxx is determined by the method-to-channel mapping in Section 4.

**Example — before:**
```spin2
PRI initCard() : result | ...
  debug("[initCard] Starting card init...")
  debug("[initCard] Reference: SPI_SD_Implementation_Reference.md")
```

**After:**
```spin2
PRI initCard() : result | ...
  debug[CH_INIT]("[initCard] Starting card init...")
  debug[CH_INIT]("[initCard] Reference: SPI_SD_Implementation_Reference.md")
```

**Example — method with mixed channels (fs_worker):**
```spin2
PRI fs_worker() | ...
  debug[CH_API]("[fs_worker] Starting on cog ", udec_(COGID()))
  ...
  debug[CH_API]("[fs_worker] Received command ", udec_(cur_cmd))
  ...
#IFDEF SD_INCLUDE_RAW
      CMD_WRITE_SECTOR_RAW:
        ...
        debug[CH_SECTOR]("[WRITE_RAW] after bytemove: ...")
#ENDIF
  ...
  debug[CH_API]("[fs_worker] Unknown command: ", udec_(cur_cmd))
```

### 5.4 Interaction with DEBUG_DISABLE

`DEBUG_DISABLE = 1` still kills all debug output globally, regardless of `DEBUG_MASK`. The hierarchy is:

1. `-d` compiler flag must be present (otherwise zero debug code)
2. `DEBUG_DISABLE` must be 0 or undefined (otherwise zero debug code)
3. `DEBUG_MASK` bit N must be set for `debug[N]()` to compile

For production: keep `DEBUG_DISABLE = 1`. For debugging: set `DEBUG_DISABLE = 0` and configure `DEBUG_MASK` to enable only the channels you need.

### 5.5 Interaction with #IFDEF Feature Gates

Methods inside `#IFDEF SD_INCLUDE_RAW` (etc.) are already conditionally compiled. Adding `debug[N]()` channels inside these blocks means the debug statement must pass both gates:

1. The `#IFDEF` flag must be defined (method exists)
2. The channel's bit must be set in `DEBUG_MASK` (debug statement compiles)

This gives finer control — you can have `SD_INCLUDE_RAW` enabled (raw API available) but CH_SECTOR disabled (raw sector debug output suppressed).

---

## 6. Implementation Order

### Phase 1: Infrastructure (non-breaking)
1. Add `{Spin2_v46}` directive to top of file
2. Add channel constants and `DEBUG_MASK` to CON section
3. Compile check — no debug statements changed yet, existing `DEBUG_DISABLE = 1` still active

### Phase 2: Convert by channel (one channel at a time)
Convert all methods belonging to each channel, in this order:

| Step | Channel | Methods | Why this order |
|---|---|---|---|
| 2a | CH_API (8) | Public API, worker, stack guard | Smallest impact, easiest to verify |
| 2b | CH_RECOVER (9) | Wait methods, CMD12, recovery | Small set, isolated |
| 2c | CH_STATUS (5) | CMD13/CMD23 probe and check | Recently refactored, well understood |
| 2d | CH_IDENT (6) | Card identity, register parsing | Init-time only, low risk |
| 2e | CH_HSPEED (7) | High-speed mode | Already behind `#IFDEF`, isolated |
| 2f | CH_INIT (0) | Card init, pin setup | Largest channel, core init path |
| 2g | CH_MOUNT (1) | Mount/unmount, FSInfo | Depends on init working |
| 2h | CH_SECTOR (4) | Sector I/O, FAT, clusters | Data path — test carefully |
| 2i | CH_FILE (2) | File handle operations | Depends on sector I/O |
| 2j | CH_DIR (3) | Directory operations | Depends on file ops |

After each step: compile check (19/19 suites with `--compile-only`).

### Phase 3: Validation
1. Set `DEBUG_DISABLE = 0`, `DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)`
2. Compile — verify record count stays under 255
3. Run hardware regression on at least one test suite to confirm debug output works
4. Restore `DEBUG_DISABLE = 1` for production

---

## 7. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Exceeding 255 records with too many channels enabled | Channel sizes designed so any 3 channels < 255. Document in CON block. |
| `{Spin2_v46}` breaks existing code | Version directives are backward-compatible; v46 is a superset of v45 |
| Merge conflicts with sibling driver | Engineering guide update will document channel scheme for parallel adoption |
| Missed debug statement (still using plain `debug()`) | Post-conversion grep for `debug(` without `[` — any matches are unconverted |
| Consumer programs need `DEBUG_MASK` too | `DEBUG_MASK` is per-object. Consumer's `DEBUG_MASK` is independent of the driver's. |

---

## 8. Verification Grep

After all conversions, run this check:

```bash
grep -n 'debug(' src/micro_sd_fat32_fs.spin2 | grep -v 'debug\[' | grep -v "'" | grep -v '//'
```

Any matches are unconverted `debug()` statements that need a channel assignment. Zero matches means conversion is complete.

---

## 9. Consumer Impact

The `DEBUG_MASK` and channel constants are internal to the driver object. Consumer programs (tests, utilities, demo shell) are not affected:

- Consumer `debug()` statements remain as-is (they have their own record budget)
- Consumer programs do NOT need to define `DEBUG_MASK` unless they want their own channels
- The driver's `DEBUG_DISABLE = 1` continues to suppress all driver debug output in production
- To debug the driver from a consumer, set `DEBUG_DISABLE = 0` in the driver source and configure `DEBUG_MASK`

## 10. Documentation Updates

- Update `DOCs/CONDITIONAL-COMPILATION-GUIDE.md` to document `DEBUG_MASK`, channel constants, and `debug[N]()` usage for developers who want to enable selective driver debug output

---

*Plan produced 2026-03-07 — Iron Sheep Productions*
