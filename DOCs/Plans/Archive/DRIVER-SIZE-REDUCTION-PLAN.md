# SD Card Driver Size Reduction Plan

**Date:** February 3, 2026
**Updated:** February 4, 2026
**Purpose:** Analyze options for reducing compiled size of SD_card_driver.spin2 to essential file operations, with advanced features as optional add-ons.

---

## Key Findings

### DEBUG_DISABLE Already Handles Debug Output

The driver already has `DEBUG_DISABLE = 1` in the CON block. Per P2KB documentation:

> "Can be globally disabled with DEBUG_DISABLE directive"
> "Performance impact is minimal when disabled"

**This is a recognized compiler feature** that completely removes all DEBUG statements at compile time. No separate "Diagnostics Module" is needed - debug output control is already solved.

### Single Flag vs. Multiple Flags

After analysis, a **single `SD_MINIMAL` flag** is recommended over separate flags for each optional module:

| Approach | Configurations to Test | User Decisions | Complexity |
|----------|----------------------|----------------|------------|
| 3 separate flags | 8 (2³) | 3 | High |
| 1 combined flag | 2 | 1 | Low |

**Rationale for single flag:**
1. **Simplicity wins** - One flag is easier for users to understand
2. **Testing burden** - 2 configurations vs 8 combinations
3. **Dependencies exist** - Speed Control partially needs Registers (CSD parsing)
4. **Marginal benefit** - Difference between modules is only ~5-10% each
5. **Real-world usage** - Users either need basic file I/O (minimal) or advanced features (full)

---

## Current Driver Analysis

### Size Breakdown (Estimated)

The current V3 driver (`src/SD_card_driver.spin2`) contains approximately:

| Category | PUB Methods | PRI Methods | Approx. Lines |
|----------|-------------|-------------|---------------|
| **Core File Operations** | 25 | 30 | ~1,500 |
| **V3 Handle API** | 15 | 12 | ~600 |
| **Raw Sector Access** | 8 | 4 | ~400 |
| **Card Registers** | 8 | 6 | ~300 |
| **Speed Control** | 10 | 4 | ~400 |
| **SPI/Low-Level** | - | 15 | ~800 |
| **Total** | ~65 | ~70 | ~4,000+ |

*Note: Diagnostics/Debug methods removed from estimate - handled by DEBUG_DISABLE*

### Memory Costs

- **DAT Section:** ~2,600 bytes (buffers, state, worker stack)
  - 3 × 512-byte sector buffers = 1,536 bytes
  - 4 × 512-byte per-handle buffers = 2,048 bytes (for MAX_OPEN_FILES=4)
  - State variables, stack, etc. = ~500 bytes
- **Code:** Substantial (needs measurement with compiler)

---

## Recommended Approach

### Simple Two-Configuration Model

```spin2
' SD_card_driver.spin2
CON
  DEBUG_DISABLE = 1           ' Production: disable debug output (existing)

' User defines SD_MINIMAL before OBJ declaration to get smallest build
' Default (no define) = full featured driver

#IFNDEF SD_MINIMAL
  #DEFINE SD_INCLUDE_RAW
  #DEFINE SD_INCLUDE_REGISTERS
  #DEFINE SD_INCLUDE_SPEED
#ENDIF
```

### User Usage

```spin2
' ═══════════════════════════════════════════════════════════════
' MINIMAL BUILD (~20-25% smaller)
' For applications that only need file read/write operations
' ═══════════════════════════════════════════════════════════════
#DEFINE SD_MINIMAL
OBJ
    sd : "SD_card_driver"

' ═══════════════════════════════════════════════════════════════
' FULL BUILD (default)
' Includes raw sector access, card registers, speed control
' ═══════════════════════════════════════════════════════════════
OBJ
    sd : "SD_card_driver"
```

### What Each Build Includes

| Feature | Minimal | Full |
|---------|---------|------|
| mount() / unmount() | ✅ | ✅ |
| File operations (open, read, write, close) | ✅ | ✅ |
| V3 Handle API (multi-file) | ✅ | ✅ |
| Directory operations | ✅ | ✅ |
| seek, tell, eof, fileSize | ✅ | ✅ |
| freeSpace, error, volumeLabel | ✅ | ✅ |
| Raw sector read/write | ❌ | ✅ |
| Card registers (CID/CSD/SCR/OCR) | ❌ | ✅ |
| High-speed mode (CMD6) | ❌ | ✅ |
| Card size query | ❌ | ✅ |

---

## Module Details

### Core Module (Always Included)

**Public Methods:**
- Lifecycle: `start()`, `stop()`, `null()`
- Mount: `mount()`, `unmount()`
- V3 Handle API: `openFileRead()`, `openFileWrite()`, `createFileNew()`, `closeFileHandle()`, `readHandle()`, `writeHandle()`, `seekHandle()`, `tellHandle()`, `eofHandle()`, `fileSizeHandle()`, `syncHandle()`, `syncAllHandles()`
- Legacy API: `openFile()`, `read()`, `write()`, `closeFile()`, `newFile()`, `seek()`, `tell()`, `fileSize()`
- Directory: `newDirectory()`, `changeDirectory()`, `deleteFile()`, `rename()`, `moveFile()`, `readDirectory()`
- Status: `error()`, `freeSpace()`, `volumeLabel()`
- Date: `setDate()`

**Private Methods Required:**
- `fs_worker()` (worker cog loop)
- `send_command()` (command dispatch)
- Handle management: `allocateHandle()`, `freeHandle()`, `validateHandle()`, etc.
- File operations: `do_mount()`, `do_open_read()`, `do_write_h()`, etc.
- FAT navigation: `readFat()`, `allocateCluster()`, `searchDirectory()`, etc.
- SPI core: `initSPIPins()`, `sp_transfer_8()`, `cmd()`, `readSector()`, `writeSector()`
- CRC: `calcDataCRC()`

### Optional Module: Raw Sector Access

**Controlled by:** `SD_INCLUDE_RAW` (included unless `SD_MINIMAL` defined)

**Public Methods:**
- `initCardOnly()` - Initialize card without mounting filesystem
- `readSectorRaw()`, `writeSectorRaw()` - Single sector operations
- `readSectorsRaw()`, `writeSectorsRaw()` - Multi-block operations
- `cardSizeSectors()` - Get card capacity

**Private Methods:**
- `do_init_card_only()`
- `do_get_card_size()`
- `readSectors()`, `writeSectors()` (multiblock implementations)

**Use cases:** Disk imaging, custom filesystems, low-level utilities

### Optional Module: Card Registers

**Controlled by:** `SD_INCLUDE_REGISTERS` (included unless `SD_MINIMAL` defined)

**Public Methods:**
- `readCIDRaw()`, `readCSDRaw()`, `readSCRRaw()` - Raw register access
- `getOCR()` - Operating conditions register
- `readVBRRaw()` - Volume boot record
- `getManufacturerID()` - Card manufacturer info

**Private Methods:**
- `do_read_cid()`, `do_read_csd()`, `do_read_scr()`
- `readCID()`, `readCSD()`, `readSCR()`
- `parseMfrId()`

**Use cases:** Card identification, capability detection, diagnostics

### Optional Module: Speed Control

**Controlled by:** `SD_INCLUDE_SPEED` (included unless `SD_MINIMAL` defined)

**Public Methods:**
- `attemptHighSpeed()` - Try to enable high-speed mode
- `getSPIFrequency()`, `getCardMaxSpeed()` - Query speeds
- `setSPISpeed()` - Manual speed control
- `isHighSpeedActive()` - Check current mode
- `checkCMD6Support()`, `checkHighSpeedCapability()` - Card capabilities
- `getReadTimeout()`, `getWriteTimeout()` - Timeout values

**Private Methods:**
- `sendCMD6()`, `queryHighSpeedSupport()`, `switchToHighSpeed()`
- `parseTransSpeed()`, `parseTimeouts()`
- `identifyCard()`, `setOptimalSpeed()`

**Use cases:** High-throughput applications, performance optimization

---

## Estimated Results

| Configuration | Est. Code Reduction | Est. Buffer Reduction |
|--------------|--------------------|-----------------------|
| Full (default) | 0% | 0% |
| SD_MINIMAL | ~20-25% | 0% |
| SD_MINIMAL + 2 handles | ~20-25% | ~1KB (2 fewer buffers) |

*Note: Previous estimate of 35-40% included diagnostics module which is now handled by DEBUG_DISABLE*

---

## Implementation Phases

### Phase 1: Analysis & Measurement
1. Compile current driver with DEBUG_DISABLE=1, measure actual size
2. Identify method dependencies (which PRI methods each PUB needs)
3. Create dependency graph

### Phase 2: Code Reorganization
1. Add `#IFNDEF SD_MINIMAL` / `#ENDIF` gates around optional code
2. Gate worker cog command handlers for optional features
3. Test both configurations compile correctly

### Phase 3: Validation
1. Run regression tests with full build
2. Run regression tests with minimal build
3. Measure actual size reduction

### Phase 4: Documentation
1. Update README with `SD_MINIMAL` usage
2. Document what's included/excluded
3. Provide example configurations

---

## Existing Size Reduction Options

These options already exist in the driver:

| Option | How to Use | Savings |
|--------|-----------|---------|
| Disable debug output | `DEBUG_DISABLE = 1` (default) | Removes all debug code |
| Reduce file handles | `MAX_OPEN_FILES = 2` in OBJ | ~1KB (2 fewer buffers) |

---

## Open Questions (Resolved)

1. ~~**Diagnostics Module:** Should debug methods be separate?~~
   - **Resolved:** No - `DEBUG_DISABLE` already handles this

2. ~~**Multiple flags vs single flag?**~~
   - **Resolved:** Single `SD_MINIMAL` flag for simplicity

3. **Legacy API:** Should the legacy single-file API be in core or separate?
   - **Recommendation:** Keep in core for backward compatibility

4. **Multiblock operations:** Are `readSectorsRaw()`/`writeSectorsRaw()` used by core file operations?
   - **Need to verify** - if yes, they must stay in core

5. **Worker cog commands:** Each module adds commands - does this affect worker cog size?
   - The `fs_worker()` command dispatch will need conditional compilation

---

## Summary

| Control | Purpose | Default |
|---------|---------|---------|
| `DEBUG_DISABLE = 1` | Remove debug output | Enabled (no debug) |
| `SD_MINIMAL` | Exclude advanced features | Not defined (full build) |
| `MAX_OPEN_FILES = N` | Reduce handle count | 4 handles |

For most embedded applications doing simple file I/O, defining `SD_MINIMAL` provides a ~20-25% smaller driver while retaining all essential file operations.
