# Conditional Compilation Guide

**User's guide to the P2-uSD-FAT32-FS pragma system, feature flags, multi-compiler support, and debug output control.**

---

## Overview

The P2-uSD-FAT32-FS driver uses a conditional compilation system to let you include only the features your application needs. The core driver compiles to ~24 KB with just filesystem operations. Enabling all optional features brings it to ~49 KB. Since the Propeller 2 has 512 KB of hub RAM this isn't usually a constraint, but the mechanism keeps the driver well-organized and gives you control over what ships in your binary.

Feature flags are declared in your **top-level application file** (the file that contains `_CLKFREQ` and the `OBJ` declaration for the driver). The flags propagate down to the driver at compile time using `#pragma exportdef` directives.

---

## Feature Flags

### Available Flags

| Flag | What It Enables | Category | Size |
|------|-----------------|----------|------|
| `SD_INCLUDE_ASYNC` | Non-blocking file I/O: `startReadHandle()`, `startWriteHandle()`, `isComplete()`, `getResult()`, `cancelAsync()` | **Application** | ~1 KB |
| `SD_INCLUDE_DEFRAG` | Defragmentation: `fileFragments()`, `isFileContiguous()`, `compactFile()`, `createFileContiguous()` | **Application** | ~1 KB |
| `SD_INCLUDE_RAW` | Raw sector read/write, `initCardOnly()`, multi-block CMD18/CMD25 | Utility | ~2 KB |
| `SD_INCLUDE_SPEED` | High-speed mode switch via CMD6 (up to 50 MHz SPI) | Utility | ~2 KB |
| `SD_INCLUDE_REGISTERS` | Card register access: CID, CSD, SCR, SD Status | Utility | ~3 KB |
| `SD_INCLUDE_DEBUG` | Debug/diagnostic methods and CRC error getters | Diagnostic | ~8 KB |
| `SD_INCLUDE_STACK_CHECK` | Worker cog stack depth measurement | Diagnostic | ~1 KB |
| `SD_INCLUDE_ALL` | Convenience: enables all of the above except STACK_CHECK | All | ~16 KB |

**Application** flags add user-facing capabilities to your program. **Utility** flags support standalone tools (format, benchmark, card characterization). **Diagnostic** flags are for development and debugging.

### Flag Dependencies

`SD_INCLUDE_SPEED` **requires** `SD_INCLUDE_REGISTERS`. The driver enforces this at compile time -- if you enable SPEED without REGISTERS, you get a clear compilation error:

```
SD_INCLUDE_SPEED_REQUIRES_SD_INCLUDE_REGISTERS
```

`SD_INCLUDE_ASYNC` is independent — it can be enabled alongside any other flags or alone. It **is** included by `SD_INCLUDE_ALL`.

`SD_INCLUDE_DEFRAG` is independent — it can be enabled alongside any other flags or alone. It **is** included by `SD_INCLUDE_ALL`.

`SD_INCLUDE_STACK_CHECK` is independent and is **not** included by `SD_INCLUDE_ALL`. It must be enabled separately when needed.

### What the Core Driver Includes (No Flags)

With no feature flags, the driver provides all standard filesystem operations:

- `mount()` / `unmount()`
- `createFileNew()` / `openFileRead()` / `openFileWrite()`
- `readHandle()` / `writeHandle()` / `seekHandle()`
- `closeFileHandle()` / `syncHandle()`
- `deleteFile()` / `renameFile()` / `moveFile()`
- `makeDirectory()` / `changeDirectory()` / `readDirectory()`
- `fileSize()` / `freeSpace()` / `sectorsPerCluster()` / `error()`

This is sufficient for the vast majority of applications. The example programs (`src/EXAMPLES/`) use no feature flags at all.

### SD_INCLUDE_ASYNC — Non-Blocking File I/O

Unlike the other feature flags (which enable diagnostic, debug, or low-level access), `SD_INCLUDE_ASYNC` adds **application-level functionality**: the ability to start a read or write and keep your cog running while the SD card completes the transfer.

This matters for embedded applications where the calling cog has real-time work — sensor polling, control loops, display updates — that can't pause for 5-50ms while the SD card finishes a sector write.

**Enable it:**

```spin2
#pragma exportdef SD_INCLUDE_ASYNC

OBJ
    sd : "micro_sd_fat32_fs"
```

**Use it — async write pattern:**

```spin2
PUB data_logger() | handle, status, bytes
    handle := sd.createFileNew(@"LOG.CSV")

    repeat
        acquire_sensor_data()

        ' Start the write — returns immediately
        sd.startWriteHandle(handle, @sensor_buf, 512)

        ' Cog keeps running at full 350 MHz while SD card writes
        repeat
            process_control_loop()
            update_display()
        until sd.isComplete()

        ' Retrieve the result and release the SD bus
        bytes := sd.getResult()
```

**The 5 async methods:**

| Method | Purpose |
|--------|---------|
| `startReadHandle(handle, buffer, count)` | Begin async read, returns `PENDING` (1) |
| `startWriteHandle(handle, buffer, count)` | Begin async write, returns `PENDING` (1) |
| `isComplete()` | Non-blocking poll — returns TRUE when done |
| `getResult()` | Get byte count (or error), releases the SD bus lock |
| `cancelAsync()` | Discard result, release lock |

**Key rule:** Always call `getResult()` or `cancelAsync()` after starting an async operation. The SD bus lock is held until you do — other cogs cannot issue SD commands while an async operation is in flight.

### SD_INCLUDE_DEFRAG — File Defragmentation

`SD_INCLUDE_DEFRAG` adds the ability to query, prevent, and repair file fragmentation. This is critical for the P2 boot file (`_BOOT_P2.BIX`) which must be stored in contiguous sectors, and beneficial for any file where multi-block CMD18/CMD25 transfer performance matters.

**Enable it:**

```spin2
#pragma exportdef SD_INCLUDE_DEFRAG

OBJ
    sd : "micro_sd_fat32_fs"
```

**Use it — boot file contiguity check:**

```spin2
PUB ensure_boot_contiguous() | result
    if not sd.isFileContiguous(@"_BOOT_P2.BIX")
        result := sd.compactFile(@"_BOOT_P2.BIX")
        if result < 0
            debug("Compaction failed: ", sdec_(result))
```

**The 4 defrag methods:**

| Method | Purpose |
|--------|---------|
| `fileFragments(p_path)` | Count non-contiguous runs in a file's cluster chain (1 = contiguous) |
| `isFileContiguous(p_path)` | Returns TRUE if fragment count is 1 |
| `compactFile(p_path)` | Relocate file's clusters into a contiguous chain (with read-back verify) |
| `createFileContiguous(p_path, file_size)` | Create a new file with pre-allocated contiguous clusters |

**Key rules:**
- `compactFile()` requires the file to be **closed** (no active handles) — returns `E_FILE_OPEN_FOR_COMPACT` otherwise
- `compactFile()` performs mandatory read-back verification after every cluster copy — a corrupted boot file bricks the device
- `createFileContiguous()` requires knowing the file size upfront — returns `E_NO_CONTIGUOUS_SPACE` if no run of sufficient length exists
- The driver also uses **next-fit allocation** (unconditional, no flag needed) to prevent fragmentation during normal writes

---

## How to Enable Features

### Simple Case (pnut-ts only)

If you only need to compile with pnut-ts (the primary compiler for this project), enabling features is straightforward. Place the `#pragma exportdef` directives **before** your `OBJ` declaration:

```spin2
CON
    _CLKFREQ = 350_000_000
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

' Enable raw sector access and debug diagnostics
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    sd : "micro_sd_fat32_fs"
```

Or to enable everything:

```spin2
#pragma exportdef SD_INCLUDE_ALL

OBJ
    sd : "micro_sd_fat32_fs"
```

### When Your File Also Needs the Flag Locally

`#pragma exportdef` propagates a flag to child objects (the driver). It does **not** define the flag in your own file. If your top-level code also has `#ifdef` blocks that check a flag, you need **both** directives:

```spin2
' Make it available locally AND propagate to the driver
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK

OBJ
    sd : "micro_sd_fat32_fs"

PUB go() | depth
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)

    ' This #ifdefneeds the local #defineto work:
#ifdef SD_INCLUDE_STACK_CHECK
    depth := sd.reportStackDepth()
    debug("Stack depth: ", udec(depth))
#endif
```

The rule is simple:

| Directive | Scope | Purpose |
|-----------|-------|---------|
| `#define` | Current file only | Controls `#ifdef` guards in your file |
| `#pragma exportdef` | Child objects (OBJ) | Makes the flag visible to the driver |

If your application code doesn't use `#ifdef` blocks for the flag (the common case), you only need `#pragma exportdef`.

---

## Multi-Compiler Support

The project supports three Spin2 compilers. Each handles flag propagation differently, so the codebase uses a three-branch conditional pattern to set flags correctly for whichever compiler is building the code.

### The Three Compilers

| Compiler | Built-in Define | Flag Propagation |
|----------|----------------|------------------|
| **Spin Tools IDE** | `__SPINTOOLS__` | `#define` automatically propagates to child objects |
| **flexspin** | `__FLEXSPIN__` | Requires both `#define` and `#pragma exportdef` |
| **pnut-ts** | *(neither defined)* | Requires both `#define` and `#pragma exportdef` (case insensitive) |

All three compilers accept lowercase directives. The project uses lowercase throughout for consistency with standard preprocessor conventions.

### Why Three Branches?

The compilers differ in flag propagation semantics:

- **Spin Tools** `#define` automatically exports to child objects. flexspin and pnut-ts require an explicit `#pragma exportdef` to propagate flags.
- **flexspin** requires both `#define` (local) and `#pragma exportdef` (propagation).
- **pnut-ts** directives are case insensitive. Only `#pragma exportdef` is needed (add `#define` if the flag is used locally).

### The Standard Pattern

Here is the three-branch pattern used throughout the project. This example enables `SD_INCLUDE_RAW` and `SD_INCLUDE_DEBUG`:

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG
#else
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_DEBUG
#endif
```

What each branch does:

- **Spin Tools branch** (`__SPINTOOLS__`): Uses `#define` only. The IDE automatically propagates defines to child objects, so no explicit export is needed.

- **flexspin branch** (`__FLEXSPIN__`): Uses `#define` for the local definition plus `#pragma exportdef` to propagate to child objects. Both are required.

- **pnut-ts branch** (`#else`): The fallback. Uses `#pragma exportdef` to propagate to the driver. Adds `#define` only if the current file itself needs to test the flag with `#ifdef`.

### Pattern Variations in the Codebase

**Selective features** (e.g., speed tests need SPEED + REGISTERS):

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_SPEED
#define SD_INCLUDE_REGISTERS
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_SPEED
#pragma exportdef SD_INCLUDE_SPEED
#define SD_INCLUDE_REGISTERS
#pragma exportdef SD_INCLUDE_REGISTERS
#else
#pragma exportdef SD_INCLUDE_SPEED
#pragma exportdef SD_INCLUDE_REGISTERS
#endif
```

**All features** (e.g., raw sector tests, format tests):

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_ALL
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#else
#pragma exportdef SD_INCLUDE_ALL
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK
#endif
```

Note: `SD_INCLUDE_STACK_CHECK` is added separately in the pnut-ts branch because `SD_INCLUDE_ALL` does not include it.

**Core only** (e.g., seek tests, directory tests with just stack check):

```spin2
#ifdef __SPINTOOLS__
#elseifdef __FLEXSPIN__
#else
#define SD_INCLUDE_STACK_CHECK
#pragma exportdef SD_INCLUDE_STACK_CHECK
#endif
```

The Spin Tools and flexspin branches are empty -- no optional features are enabled. The pnut-ts branch adds only the stack check diagnostic.

**No flags at all** (e.g., seek tests): Some test files omit the three-branch block entirely. They compile with the core-only driver, which is all they need.

### If You Only Use One Compiler

If your project only targets one compiler, you can simplify:

**pnut-ts only:**
```spin2
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    sd : "micro_sd_fat32_fs"
```

**flexspin only:**
```spin2
#define SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    sd : "micro_sd_fat32_fs"
```

**Spin Tools only:**
```spin2
#define SD_INCLUDE_RAW
#define SD_INCLUDE_DEBUG

OBJ
    sd : "micro_sd_fat32_fs"
```

The three-branch pattern is only needed when the same source must compile under multiple compilers.

---

## How the Driver Uses Feature Flags

Inside the driver (`micro_sd_fat32_fs.spin2`), each optional feature is completely enclosed in `#ifdef` / `#endif` blocks. When a flag is not defined, the compiler removes all related code: public methods, private methods, worker cog command handlers, and command code constants.

### SD_INCLUDE_ALL Expansion

The driver expands `SD_INCLUDE_ALL` into all six individual flags:

```spin2
#ifdef SD_INCLUDE_ALL
#ifndef SD_INCLUDE_ASYNC
#define SD_INCLUDE_ASYNC
#endif
#ifndef SD_INCLUDE_DEFRAG
#define SD_INCLUDE_DEFRAG
#endif
#ifndef SD_INCLUDE_RAW
#define SD_INCLUDE_RAW
#endif
#ifndef SD_INCLUDE_REGISTERS
#define SD_INCLUDE_REGISTERS
#endif
#ifndef SD_INCLUDE_SPEED
#define SD_INCLUDE_SPEED
#endif
#ifndef SD_INCLUDE_DEBUG
#define SD_INCLUDE_DEBUG
#endif
#endif
```

The `#ifndef` guards prevent double-definition if you happen to enable both `SD_INCLUDE_ALL` and an individual flag.

### Gated Sections

The driver is organized into numbered sections. Optional features occupy their own sections:

| Section | Flag | Public Methods |
|---------|------|----------------|
| Section 8: Raw Sector Access | `SD_INCLUDE_RAW` | `initCardOnly()`, `readSectors()`, `writeSectors()`, `cardSizeSectors()` |
| Section 9: Card Registers | `SD_INCLUDE_REGISTERS` | `readCIDRaw()`, `readCSDRaw()`, `readSCRRaw()`, `readSDStatusRaw()`, `getReadTimeout()`, `getWriteTimeout()`, `getCardMaxSpeed()` |
| Section 10: Speed Control | `SD_INCLUDE_SPEED` | `attemptHighSpeed()`, `checkHighSpeedCapability()`, `setSPISpeed()`, `isHighSpeedActive()` |
| Section 11: Debug / Diagnostics | `SD_INCLUDE_DEBUG` | `getReadDiag()`, `getWriteDiag()`, `getCRCDiag()`, `debugSlowRead()`, `debugZeroRootSector()` |

If a flag is not defined, calling any of its methods causes a **linker error** at compile time. There is no silent failure -- you get a clear "method not found" message pointing you to the missing feature flag.

### Worker Cog Command Dispatch

The worker cog's command handler also uses `#ifdef` blocks around each feature's command cases. Only the command codes for enabled features exist in the dispatch table. Disabled command codes are not compiled, so they cannot be accidentally invoked.

---

## Enabling Debug Output

The P2-uSD-FAT32-FS driver and its associated files use the Spin2 `DEBUG_DISABLE` constant to control whether `debug()` statements produce output. This is a standard Spin2 mechanism -- when `DEBUG_DISABLE = 1`, the compiler removes all `debug()` calls from the binary.

### Driver Debug Is Disabled by Default

The driver uses `DEBUG_MASK = 0` for production:

```spin2
CON ' debug channel assignments for selective debug output
  DEBUG_MASK = 0              ' Production: all debug suppressed
```

With `DEBUG_MASK = 0`, no `debug[CH_xxx]()` statements compile — zero debug code in the binary. To enable debug, set `DEBUG_MASK` to include the channels you need (see "Selective Debug Output with DEBUG_MASK" below).

### Debug in Your Application Code

Your top-level application file has its **own** `DEBUG_DISABLE` setting, independent of the driver's. Most application and test files set `DEBUG_DISABLE = 0` to enable their own debug output:

```spin2
CON
    _CLKFREQ = 350_000_000
    DEBUG_DISABLE = 0              ' Enable debug output in this file

OBJ
    sd : "micro_sd_fat32_fs"      ' Driver still has DEBUG_DISABLE = 1

PUB go()
    debug("Starting application")  ' This WILL appear in debug output
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    ' Internal driver debug() calls are still suppressed
```

Each `.spin2` file controls its own debug output independently. Setting `DEBUG_DISABLE = 0` in your file enables debug for **your code only**. The driver's internal debug statements remain suppressed regardless.

### Debug Settings Across the Project

The project files use these settings:

| File | Debug Control | Reason |
|------|--------------|--------|
| `micro_sd_fat32_fs.spin2` (driver) | `DEBUG_MASK = 0` | Channel-based; set non-zero to debug specific subsystems |
| `SD_example_*.spin2` (examples) | `DEBUG_DISABLE = 0` | Show progress/results to user |
| `SD_demo_shell.spin2` (demo) | `DEBUG_DISABLE = 1` | Uses serial terminal instead of debug |
| `isp_fsck_utility.spin2` | `DEBUG_DISABLE = 1` | Uses FIFO strings instead of debug |
| `isp_serial_singleton.spin2` | `DEBUG_DISABLE = 1` | Owns pin 62 for serial TX (conflicts with debug) |
| `SD_RT_*_tests.spin2` (tests) | `DEBUG_DISABLE = 0` (default) | Tests don't set it, so debug is enabled |

### How to See Driver-Internal Debug Output

If you need to see what the driver is doing internally (for deep debugging), set `DEBUG_MASK` to enable the channels you need:

```spin2
' In micro_sd_fat32_fs.spin2:
  DEBUG_MASK = (1 << CH_FILE) | (1 << CH_SECTOR)   ' Debug file I/O
```

**Important caveats:**

1. Enable at most 2-3 channels at a time. Any 3 channels combined stay under the 255 debug record compiler limit.

2. This is a **temporary diagnostic change** -- restore `DEBUG_MASK = 0` before committing.

3. An alternative approach: use the `SD_INCLUDE_DEBUG` feature flag to access the driver's diagnostic getters (`getReadDiag()`, `getWriteDiag()`, `getCRCDiag()`). These methods return internal diagnostic state through the normal API, without needing to enable the driver's debug output. This is the recommended approach for production debugging.

### SD_INCLUDE_DEBUG vs DEBUG_MASK

These are two different mechanisms that are easily confused:

| Mechanism | What It Controls | Scope |
|-----------|-----------------|-------|
| `SD_INCLUDE_DEBUG` | Whether debug **API methods** are compiled into the driver | Feature flag (compile-time) |
| `DEBUG_MASK` | Which `debug[CH_xxx]()` **print statements** compile | Driver-internal constant |

You can (and typically do) enable `SD_INCLUDE_DEBUG` while leaving `DEBUG_MASK = 0` in the driver. This gives you access to the debug API (diagnostic getters, CRC error injection hooks) without enabling the driver's hundreds of internal debug print statements.

### Selective Debug Output with DEBUG_MASK (v1.3.2+)

The driver assigns each `debug()` call to one of 10 named channels using `debug[CH_xxx]()` syntax. The `DEBUG_MASK` constant controls which channels compile, allowing you to enable debug output for just the subsystem you are investigating without exceeding the 255 debug record limit.

To enable driver-internal debug, set `DEBUG_MASK` to the channels you need:

```spin2
' In micro_sd_fat32_fs.spin2:
  DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)    ' Debug mount failures (~103 records)
```

Available channels:

| Channel | Records | What It Shows |
|---------|---------|---------------|
| `CH_INIT` (0) | 64 | Card initialization, SPI pin setup, speed config |
| `CH_MOUNT` (1) | 39 | Mount/unmount, VBR parsing, FSInfo |
| `CH_FILE` (2) | 59 | File open/close/read/write/seek/sync |
| `CH_DIR` (3) | 49 | Directory search, create, rename, move |
| `CH_SECTOR` (4) | 45 | Sector I/O, FAT chain, cluster allocation |
| `CH_STATUS` (5) | 44 | CMD13/CMD23 probes, card status |
| `CH_IDENT` (6) | 34 | CID/CSD/SCR parsing, card identity |
| `CH_HSPEED` (7) | 24 | CMD6 high-speed mode negotiation |
| `CH_API` (8) | 35 | Public API entry points, worker dispatch |
| `CH_RECOVER` (9) | 9 | Error recovery, CMD12, bus recovery |

Common debug scenarios:

```spin2
  DEBUG_MASK = (1 << CH_FILE) | (1 << CH_SECTOR)   ' File read/write issues (~104 records)
  DEBUG_MASK = (1 << CH_STATUS)                     ' CMD13 investigation (~44 records)
  DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT) | (1 << CH_IDENT)  ' Full init debug (~137 records)
```

Any 3 channels combined stay under the 255-record limit. Remember to restore `DEBUG_MASK = 0` before committing.

---

## Quick Reference

### Minimal application (core filesystem only)

```spin2
CON
    _CLKFREQ = 350_000_000
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

OBJ
    sd : "micro_sd_fat32_fs"

PUB go() | handle
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    handle := sd.createFileNew(@"HELLO.TXT")
    sd.writeHandle(handle, @"Hello, world!", 13)
    sd.closeFileHandle(handle)
    sd.unmount()
```

No feature flags needed.

### Application with raw sector access

```spin2
#pragma exportdef SD_INCLUDE_RAW

OBJ
    sd : "micro_sd_fat32_fs"
```

### Application with all features (multi-compiler)

```spin2
#ifdef __SPINTOOLS__
#define SD_INCLUDE_ALL
#elseifdef __FLEXSPIN__
#define SD_INCLUDE_ALL
#pragma exportdef SD_INCLUDE_ALL
#else
#pragma exportdef SD_INCLUDE_ALL
#endif

OBJ
    sd : "micro_sd_fat32_fs"
```

### Application with debug diagnostics

```spin2
#pragma exportdef SD_INCLUDE_DEBUG

OBJ
    sd : "micro_sd_fat32_fs"

PUB go() | result_code, r1, data_resp, sector
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
    ' ... perform operations ...
    result_code, r1, data_resp, sector := sd.getWriteDiag()
    debug("Last write: result=", sdec(result_code), " sector=", udec(sector))
```
