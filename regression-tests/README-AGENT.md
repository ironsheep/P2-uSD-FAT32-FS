# SD Card Driver Regression Testing

This document describes the comprehensive regression test suite for the P2 SD Card Driver project. The test infrastructure enables automated, repeatable validation of all driver functionality on real Propeller 2 hardware.

## Overview

The regression test suite consists of **11 specialized test files** covering different aspects of SD card functionality, supported by a test utilities framework and automated test runner. All tests execute on actual P2 hardware with a physical SD card, ensuring real-world validation.

### Test Summary

| Test Suite | Description | Tests |
|------------|-------------|-------|
| **Mount Tests** | Card initialization, mounting, unmounting, pre-mount errors | 21 |
| **File Operations** | Create, open, close, delete, rename files, type mismatch | 22 |
| **Read/Write Tests** | Data integrity, buffer operations, boundary conditions | 29 |
| **Directory Tests** | Directory listing, navigation, deep nesting, boundaries | 27 |
| **Seek Tests** | Random access, cross-sector seeks, seek boundaries | 37 |
| **Format Tests** | FAT32 structure validation, cross-OS compatibility | 43 |
| **Multiblock Tests** | Multi-sector streamer DMA transfers | 12 |
| **Multicog Tests** | Singleton pattern, concurrent access, lock serialization | 18 |
| **Multihandle Tests** | Multiple simultaneous file handles | 22 |
| **Raw Sector Tests** | Direct sector read/write, large LBA addressing | 14 |
| **Error Handling Tests** | Error conditions, invalid handles, state errors | 6 |
| **Total** | | **251** |

---

## Test Infrastructure

### Directory Structure

```
P2-uSD-FAT32-FS/
├── regression-tests/               # Test source files
│   ├── isp_rt_utilities.spin2          # Test framework (shared)
│   ├── SD_RT_mount_tests.spin2
│   ├── SD_RT_file_ops_tests.spin2
│   ├── SD_RT_read_write_tests.spin2
│   ├── SD_RT_directory_tests.spin2
│   ├── SD_RT_seek_tests.spin2
│   ├── SD_RT_format_tests.spin2
│   ├── SD_RT_multiblock_tests.spin2
│   ├── SD_RT_multicog_tests.spin2
│   ├── SD_RT_multihandle_tests.spin2
│   ├── SD_RT_raw_sector_tests.spin2
│   ├── SD_RT_error_handling_tests.spin2
│   ├── SD_RT_register_tests.spin2
│   ├── SD_RT_speed_tests.spin2
│   ├── SD_RT_dirhandle_tests.spin2
│   ├── SD_RT_subdir_ops_tests.spin2
│   ├── SD_RT_volume_tests.spin2
│   ├── SD_RT_crc_diag_tests.spin2
│   ├── SD_RT_fifo_tests.spin2
│   └── TestCard/                       # Test card validation
│       ├── TEST-CARD-SPECIFICATION.md      # Test card requirements
│       ├── SD_RT_testcard_validation.spin2 # Card validation test
│       └── TESTROOT/                       # Files to copy to test card
│
├── tools/                          # Test execution tools
│   ├── run_test.sh                     # Automated test runner
│   └── logs/                           # Test output logs
│
└── src/                            # Driver under test
    ├── micro_sd_fat32_fs.spin2         # The SD card driver
    ├── DEMO/                           # Interactive demo application
    │   ├── SD_demo_shell.spin2             # Terminal shell
    │   ├── isp_serial_singleton.spin2      # Serial terminal driver
    │   ├── isp_mem_strings.spin2           # String formatting utilities
    │   └── isp_stack_check.spin2           # Stack usage diagnostic
    └── UTILS/                          # Utility programs
        ├── SD_format_card.spin2            # FAT32 card formatter
        ├── SD_card_characterize.spin2      # Card register reader
        ├── SD_speed_characterize.spin2     # SPI speed testing
        ├── SD_frequency_characterize.spin2 # Sysclk frequency tester
        ├── SD_performance_benchmark.spin2  # Throughput measurement
        ├── SD_FAT32_audit.spin2            # Filesystem validator
        ├── SD_FAT32_fsck.spin2             # Filesystem check & repair
        ├── isp_format_utility.spin2        # FAT32 format library
        ├── isp_fsck_utility.spin2          # Combined FSCK + Audit library
        └── isp_string_fifo.spin2           # Inter-cog string FIFO
```

### Test Runner (`run_test.sh`)

The test runner automates the complete test cycle:

1. **Compile** - Uses `pnut-ts` compiler with debug enabled
2. **Download** - Transfers binary to P2 via serial
3. **Execute** - Runs in headless mode capturing all debug output
4. **Monitor** - Watches for `END_SESSION` marker to detect completion
5. **Log** - Archives output with timestamps for analysis

**Usage:**
```bash
cd tools/
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 120  # Extended timeout
```

**Exit Codes:**
- `0` - Test completed successfully (END_SESSION found)
- `1` - Compilation failed
- `2` - Download/run failed
- `3` - Timeout (END_SESSION not found)
- `4` - Usage error

### Test Utilities Framework (`isp_rt_utilities.spin2`)

The test utilities provide a consistent framework for all test files:

```spin2
OBJ
    utils : "isp_rt_utilities"

PUB testExample()
    utils.startTestGroup(@"Group Name")

    utils.startTest(@"Test description")
    result := sd.someOperation()
    utils.evaluateBool(result, @"operation succeeds", true)

    utils.startTest(@"Multi-value test")
    utils.setCheckCountPerTest(5)
    repeat idx from 0 to 4
        utils.evaluateSubValue(buffer[idx], @"byte value", expectedValues[idx])

    utils.ShowTestEndCounts()
```

**Key Functions:**
| Function | Purpose |
|----------|---------|
| `startTestGroup(pName)` | Begin a logical group of related tests |
| `startTest(pName)` | Begin a single test case |
| `evaluateBool(result, pMsg, expected)` | Check boolean result |
| `evaluateSingleValue(result, pMsg, expected)` | Check numeric value |
| `evaluateSubBool(...)` | Check boolean within multi-check test |
| `evaluateSubValue(...)` | Check value within multi-check test |
| `setCheckCountPerTest(n)` | Set expected sub-checks for current test |
| `ShowTestEndCounts()` | Display final pass/fail summary |

---

## Test Suites

### 1. Mount Tests (`SD_RT_mount_tests.spin2`)

**Purpose:** Validate SD card initialization, mounting, and unmounting operations.

**Test Groups:**
- **Card Initialization** - SPI communication, card detection, card type identification
- **Filesystem Mount** - FAT32 parsing, volume label reading, free space calculation
- **Mount/Unmount Cycle** - Repeated mount/unmount operations, resource cleanup
- **Error Handling** - Invalid pin configurations, missing card scenarios
- **Pre-Mount Error Validation** - Operations before mount fail gracefully

**Key Validations:**
- Card responds to SPI commands
- SDHC/SDXC block addressing works correctly
- FAT32 boot sector parsed correctly
- Volume label extracted properly
- Free space reported accurately
- Clean unmount without data corruption
- Pre-mount file operations return appropriate errors

---

### 2. File Operations Tests (`SD_RT_file_ops_tests.spin2`)

**Purpose:** Validate basic file creation, opening, closing, deletion, and renaming.

**Test Groups:**
- **File Creation** - `createFileNew()` creates files in root directory
- **File Opening** - `openFileRead()` / `openFileWrite()` locates and opens files
- **File Closing** - `closeFileHandle()` flushes buffers and updates directory
- **File Deletion** - `deleteFile()` removes files and frees clusters
- **File Existence** - `fileExists()` correctly reports file presence
- **File Renaming** - Rename operations preserve file content
- **Multiple Simultaneous Handles** - Open multiple files simultaneously
- **Type Mismatch Errors** - `openFileRead()` on directory, `openFileWrite()` on non-existent

**Key Validations:**
- Files appear in directory after creation
- File size reported correctly
- Deleted files no longer accessible
- Rename preserves data integrity
- Multiple files can coexist
- Opening directory as file returns E_NOT_A_FILE
- Opening non-existent file for write returns E_FILE_NOT_FOUND

---

### 3. Read/Write Tests (`SD_RT_read_write_tests.spin2`)

**Purpose:** Validate data integrity during read and write operations.

**Test Groups:**
- **Basic Write** - Write known patterns to files
- **Basic Read** - Read back and verify patterns
- **Large Transfers** - Multi-sector writes and reads
- **Append Operations** - Adding data to existing files
- **Boundary Conditions** - Sector boundary crossing
- **Buffer Management** - Partial buffer operations
- **File Size Boundaries** - Empty file (0 bytes), single byte, exact sector (512), sector+1 (513), large (64KB)

**Key Validations:**
- Written data reads back identically
- Large files span multiple clusters correctly
- Append doesn't corrupt existing data
- Sector boundaries handled transparently
- Partial writes work correctly
- Empty files created and read correctly
- Large files traverse cluster chains correctly

---

### 4. Directory Tests (`SD_RT_directory_tests.spin2`)

**Purpose:** Validate directory listing and file attribute operations.

**Test Groups:**
- **Directory Enumeration** - `readDirectory()` index-based iteration
- **File Attributes** - Name, size, date/time retrieval
- **Directory Navigation** - `changeDirectory()` operations (per-cog CWD)
- **Multiple Files** - Listing with many directory entries
- **Special Entries** - Volume label, dot entries handling
- **Directory Boundary Conditions** - Deep nesting (5 levels), empty directories, max filename (8.3)

**Key Validations:**
- All files enumerated without missing entries
- File names returned correctly (8.3 format)
- File sizes match actual content
- Directory iteration terminates properly
- Volume label distinguished from files
- Deep directory nesting (5+ levels) navigable
- Empty directories contain only . and .. entries
- Max 8.3 filename length accepted

**Planned (not yet covered):**
- Handle-based directory enumeration (`openDirectory()`/`readDirectoryHandle()`/`closeDirectoryHandle()`)
- Per-cog CWD isolation (cog A in `/DIR1`, cog B in `/DIR2` simultaneously)
- Concurrent directory enumeration via handles from multiple cogs

---

### 5. Seek Tests (`SD_RT_seek_tests.spin2`)

**Purpose:** Validate random access and seek operations within files.

**Test Groups:**
- **Basic Seek** - `seekHandle()` to specific positions
- **Cross-Sector Seek** - Seeking across 512-byte boundaries
- **Random Access Pattern** - Non-sequential position jumps
- **Single-Byte Reads** - Random reads at specific positions
- **Seek Edge Cases** - EOF boundary, seek beyond EOF
- **Sequential vs Seek** - Verify seek doesn't affect sequential reads
- **Seek Boundary Conditions** - Seek(0) return to start, seek to exact EOF, seek in empty file

**Key Validations:**
- Seek to position 0 returns to file start
- Seek across sector boundaries works correctly
- Random access pattern reads correct data
- Seek beyond EOF fails appropriately
- Sequential read after seek continues correctly
- Seek to exact EOF position allows subsequent read returning 0
- Seek(0) in empty file succeeds, seek(1) fails

---

### 6. Format Tests (`SD_RT_format_tests.spin2`)

**Purpose:** Validate FAT32 format structure for cross-OS compatibility (Windows, macOS, Linux).

**Test Groups:**

#### MBR Verification (5 tests)
- Boot signature ($AA55)
- Partition bootable flag ($00 or $80)
- Partition type ($0C = FAT32 LBA)
- Partition start sector (8192 for 4MB alignment)
- Partition size

#### VBR/BPB Verification (19 tests)
- Jump instruction ($EB or $E9)
- Boot signature ($AA55)
- OEM name (printable ASCII)
- Bytes per sector (512)
- Sectors per cluster (power of 2)
- Reserved sectors (32)
- Number of FATs (2)
- Root entry count (0 for FAT32)
- Total sectors 16-bit (0 for FAT32)
- Media type ($F8 fixed disk)
- FAT size 16-bit (0 for FAT32)
- Hidden sectors (matches partition start)
- Total sectors 32-bit
- FAT32 sectors per FAT
- Root cluster number (2)
- FSInfo sector location (1)
- Backup boot sector location (6)
- Extended boot signature ($29)
- File system type string ("FAT32   ")

#### Backup Structure Verification (7 tests)
- Backup VBR matches primary (sector 6)
- FSInfo lead signature ($41615252 "RRaA")
- FSInfo structure signature ($61417272 "rrAa")
- FSInfo trail signature ($AA550000)
- FSInfo free cluster count
- FSInfo next free cluster hint
- Backup FSInfo matches primary (sector 7)

#### FAT Table Verification (5 tests)
- FAT[0] = $0FFFFFF8 (media type)
- FAT[1] = $0FFFFFFF (end of chain)
- FAT[2] = $0FFFFFFF (root directory EOC)
- FAT[3] = 0 (free)
- FAT2 mirrors FAT1

#### Root Directory Verification (4 tests)
- Volume label entry present (attribute $08)
- Volume label characters valid
- Second entry is end marker or empty
- Remaining bytes zeroed

#### Mount and Usability (3 tests)
- Mount succeeds after format
- Volume label readable
- Free space reported correctly

---

### 7. Multiblock Tests (`SD_RT_multiblock_tests.spin2`)

**Purpose:** Validate multi-sector streamer DMA operations for high-throughput transfers.

**Test Groups:**
- **Round-trip Multi-block** - `writeSectorsRaw(8)` → `readSectorsRaw(8)` → verify
- **Mixed Operations** - Multi-write with single-reads, single-writes with multi-read
- **Edge Cases** - count=1 (fallback), count=0 (immediate return)
- **Large Transfers** - 64 sectors (32KB) round-trip

**Key Validations:**
- Multi-sector writes maintain data integrity
- Multi-sector reads return correct data
- Mixing multi/single operations works correctly
- Edge case counts handled appropriately
- Large transfers complete without errors

---

### 8. Multicog Tests (`SD_RT_multicog_tests.spin2`)

**Purpose:** Validate multi-cog safety including singleton pattern and lock serialization.

**Test Groups:**
- **Singleton Pattern** - All cogs share same worker cog instance
- **Concurrent Mount** - Multiple cogs calling mount() simultaneously
- **Lock Serialization** - Concurrent file operations properly serialized
- **Stress Testing** - Rapid concurrent operations from multiple cogs

**Key Validations:**
- Worker cog ID identical across all client cogs
- No data corruption under concurrent access
- Lock contention handled correctly
- Resource cleanup works with multiple clients

---

### 9. Multihandle Tests (`SD_RT_multihandle_tests.spin2`)

**Purpose:** Validate handle-based multi-file API supporting up to 4 simultaneous files.

**Test Groups:**
- **Handle Allocation** - Opening up to 4 files simultaneously
- **Independent Positions** - Each handle maintains separate file position
- **Single-Writer Policy** - Only one write handle allowed per file
- **Handle Release** - Closing handles frees slots for reuse
- **Data Persistence** - Write → close → reopen → read cycle
- **Overflow Handling** - Attempting to open 5th file returns error

**Key Validations:**
- Can open 4 files simultaneously (3 read + 1 write)
- Each handle tracks position independently
- Write handle exclusivity enforced
- Closed handles properly released
- Written data persists through close/reopen cycle

---

### 10. Raw Sector Tests (`SD_RT_raw_sector_tests.spin2`)

**Purpose:** Validate low-level sector read/write bypassing the filesystem.

**Test Groups:**
- **Pattern Writes** - Multiple test patterns with boundary markers
- **Round-trip Verification** - Write → read → compare
- **Pattern Types** - Sequential, alternating, all-FF, all-00, incrementing
- **Sector Address Boundaries** - MBR access, large LBA addressing

**Test Sectors (100000+):**
- Pattern A: Sequential bytes with boundary markers
- Pattern B: Alternating $AA/$55
- Pattern C: All $FF (except markers)
- Pattern D: All $00 (except markers)
- Pattern E: Incrementing with sector offset

**Key Validations:**
- Raw sector writes complete successfully
- Raw sector reads return exact data written
- Boundary markers preserved correctly
- All pattern types verified
- MBR signature ($55 $AA) verifiable
- Large LBA addressing (sector 1,000,000) handled

---

### 11. Error Handling Tests (`SD_RT_error_handling_tests.spin2`)

**Purpose:** Validate error conditions, invalid handles, and edge case behaviors.

**Test Groups:**
- **File State Errors** - Invalid handle operations, read past EOF
- **Directory Errors** - Type mismatch scenarios
- **Handle Reuse Patterns** - Handle slot recycling, simultaneous access

**Key Validations:**
- `readHandle()` on invalid handle returns E_INVALID_HANDLE (-91)
- Read past EOF returns partial data then 0
- Closed handle slots can be reused by new opens
- Same file can be opened for read while open for write

---

## Running the Full Test Suite

To run all regression tests:

```bash
cd tools/

# Core functionality tests
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_read_write_tests.spin2
./run_test.sh ../regression-tests/SD_RT_directory_tests.spin2
./run_test.sh ../regression-tests/SD_RT_seek_tests.spin2

# Error handling tests
./run_test.sh ../regression-tests/SD_RT_error_handling_tests.spin2

# Advanced feature tests
./run_test.sh ../regression-tests/SD_RT_multihandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multiblock_tests.spin2
./run_test.sh ../regression-tests/SD_RT_raw_sector_tests.spin2

# Multi-cog tests (extended timeout)
./run_test.sh ../regression-tests/SD_RT_multicog_tests.spin2 -t 120

# Format test (destructive - erases card!)
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 120
```

**Note:** Format tests require extended timeout and will **erase all data** on the card.

---

## Test Card Requirements

Tests are designed to run on any FAT32-formatted SD card. Some tests (format, raw sector) may **erase data**.

### Recommended Test Card
- 32GB SDHC card (FAT32 formatted)
- Dedicated test card (no critical data)
- See `regression-tests/TestCard/TEST-CARD-SPECIFICATION.md` for detailed requirements

### Test Card Validation
Run the test card validation to verify your card meets requirements:
```bash
./run_test.sh ../regression-tests/TestCard/SD_RT_testcard_validation.spin2
```

### Hardware Configuration
```spin2
CON
    SD_CS   = 60    ' Chip Select
    SD_MOSI = 59    ' Master Out Slave In
    SD_MISO = 58    ' Master In Slave Out
    SD_SCK  = 61    ' Serial Clock
```

---

## Interpreting Results

### Successful Test Output

```
==============================================
  SD Card Driver - Mount Tests
==============================================

=== Test Group: Card Initialization ===

* Test #1: Initialize card
   mount() returns true: result = 4_294_967_295
    -> pass

...

============================================================
* 17 Tests - Pass: 17, Fail: 0
============================================================

* Mount/Unmount Tests Complete
END_SESSION
```

### Failed Test Output

```
* Test #5: Verify file content
   byte at 0: result = 65 (expected 0)
    -> FAIL
```

### Test Count Warnings

```
*  BAD TEST COUNT: 17 <> 16 (missing 1 tests)
```

This indicates a mismatch between `startTest()` calls and `evaluate*()` calls. Usually benign if all tests pass.

---

## Extending the Test Suite

### Adding a New Test File

1. Create `regression-tests/SD_RT_<name>_tests.spin2`
2. Include the utilities object: `utils : "isp_rt_utilities"`
3. Follow the test pattern with `startTestGroup()`, `startTest()`, `evaluate*()`
4. End with `utils.ShowTestEndCounts()` and `debug("END_SESSION")`

### Adding Tests to Existing Files

```spin2
' Add to existing test group
utils.startTest(@"New test description")
result := sd.newOperation()
utils.evaluateBool(result, @"operation name", expectedValue)
```

---

## Continuous Integration

The test suite is designed for automated CI execution. The test runner returns appropriate exit codes for CI systems to detect pass/fail status.

**GitHub Actions Integration:**
- Build verification on push/PR
- Full regression suite on release tags
- Test logs archived as artifacts

---

## Version History

| Date | Changes |
|------|---------|
| Feb 2026 | Test coverage improvements: added SD_RT_error_handling_tests.spin2 (6 tests), added pre-mount error validation to mount tests, added type mismatch errors to file ops, added file size and seek boundary tests, added directory boundary tests, added sector address boundary tests. Total: 251 tests |
| Feb 2026 | Consolidated test suite, added TestCard validation |
| Jan 2026 | Added multiblock, multicog, multihandle tests |
| Jan 2026 | Added comprehensive FAT32 format tests (43 tests) |
| Jan 2026 | Initial test framework and core test suites |

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
