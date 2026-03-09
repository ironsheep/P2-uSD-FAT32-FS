# SD Card Driver Regression Tests

Automated regression test suite for the P2 SD Card Driver. All tests execute on real Propeller 2 hardware with a physical SD card.

## Test Summary

### Core Test Suites (verified 2026-03-06)

| Test Suite | Description | Tests |
|------------|-------------|-------|
| **Mount Tests** | Card initialization, mounting, unmounting, pre/post-mount errors, double-mount | 29 |
| **File Operations** | Create, open, close, delete, rename, filename edge cases (V3 handle API) | 26 |
| **Read/Write Tests** | Data integrity, sector/cluster boundaries, constant patterns, tellHandle/EOF, multi-cluster, large files | 48 |
| **Directory Tests** | Directory listing, navigation, deep nesting, boundaries, many-file stress | 29 |
| **Seek Tests** | Random access, cross-sector seeks, seek boundaries | 37 |
| **Multicog Tests** | Singleton pattern, concurrent access, lock serialization | 14 |
| **Multihandle Tests** | Multiple simultaneous file handles, use-after-close, pool recycling | 21 |
| **Multiblock Tests** | Multi-sector streamer DMA transfers (CMD18/CMD25) | 6 |
| **Raw Sector Tests** | Direct sector read/write, large LBA addressing | 14 |
| **Format Tests** | FAT32 structure validation, cross-OS compatibility | 46 |
| **Subdirectory Ops Tests** | Cross-buffer cache coherence, empty files, subdir operations | 18 |
| **Core Total** | | **288** |

### Additional Test Suites

| Test Suite | Description | Tests |
|------------|-------------|-------|
| **Directory Handle Tests** | V3 directory handle enumeration, pool interaction, E_NOT_A_DIR_HANDLE | 25 |
| **Volume Tests** | Volume label, VBR access, syncAll, sync, setDate, disk full simulation | 27 |
| **Register Tests** | CSD register access, timeout values, capacity cross-check | 10 |
| **Speed Tests** | SPI frequency, CMD6, high-speed mode, speed boundaries | 15 |
| **CRC Diagnostic Tests** | CRC counters, validation toggle, CMD13 diagnostics | 14 |
| **Error Handling Tests** | Error conditions, invalid handles, dir handle type mismatch, rename edge cases | 14 |
| **CRC Validation Tests** | CRC error injection hooks, forced read/write CRC errors, hook state management | 6 |
| **Recovery Tests** | Recovery after read/write errors, CRC counter verification, remount recovery, handle isolation | 7 |
| **FIFO Tests** | String FIFO (isp_string_fifo) inter-cog communication | 21 |
| | **Additional Total** | **139** |
| | **Grand Total (20 suites)** | **427** |

## Prerequisites

- **pnut-ts** and **pnut-term-ts** - See detailed installation instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**
- Parallax Propeller 2 (P2 Edge or P2 board with microSD add-on) connected via USB
- FAT32-formatted SD card (see [Test Card Requirements](#test-card-requirements))

## Compiling and Running Tests

All tests are run from the `tools/` directory using the test runner script:

```bash
cd tools/
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2
```

The test runner compiles with `pnut-ts`, downloads to P2 hardware, captures debug output in headless mode, and saves logs to `tools/logs/`.

### Running All Core Test Suites

```bash
cd tools/

# Core functionality tests
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_read_write_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_directory_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_seek_tests.spin2

# Multi-cog and multi-handle tests
./run_test.sh ../src/regression-tests/SD_RT_multicog_tests.spin2 -t 120
./run_test.sh ../src/regression-tests/SD_RT_multihandle_tests.spin2

# Low-level transfer tests
./run_test.sh ../src/regression-tests/SD_RT_multiblock_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_raw_sector_tests.spin2

# Subdirectory and cache coherence tests
./run_test.sh ../src/regression-tests/SD_RT_subdir_ops_tests.spin2

# CRC error injection and recovery tests
./run_test.sh ../src/regression-tests/SD_RT_crc_validation_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_recovery_tests.spin2

# Error handling tests
./run_test.sh ../src/regression-tests/SD_RT_error_handling_tests.spin2

# Format test (WARNING: erases card!)
./run_test.sh ../src/regression-tests/SD_RT_format_tests.spin2 -t 300
```

**Note:** Format tests will **erase all data** on the card. The `-t` flag sets timeout in seconds (default 60).

---

## Test Card Requirements

Tests are designed to run on any FAT32-formatted SD card. Some tests (format, raw sector) may **erase data**.

### Recommended Test Card

- 32GB SDHC card (FAT32 formatted)
- Dedicated test card (no critical data)
- See `TestCard/TEST-CARD-SPECIFICATION.md` for detailed requirements

### Test Card Setup

The `TestCard/TESTROOT/` directory contains files that must be copied to the root of your test SD card before running the full test suite. These include test data files for read/write verification, seek testing, and directory navigation.

### Test Card Validation

Compile and run the validation test to verify your card meets requirements:

```bash
cd TestCard/
pnut-ts -d -I ../../src -I .. SD_RT_testcard_validation.spin2
pnut-term-ts -r SD_RT_testcard_validation.bin
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

---

## Test Utilities Framework

All test files use the shared `isp_rt_utilities.spin2` framework:

```spin2
OBJ
    utils : "isp_rt_utilities"

PUB testExample()
    utils.startTestGroup(@"Group Name")

    utils.startTest(@"Test description")
    result := sd.someOperation()
    utils.evaluateBool(result, @"operation succeeds", true)

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

## Hardware Configuration

The microSD add-on board connects to any 8-pin header group on the P2. Pins are defined as offsets from the base pin of the group:

| Offset | Signal | Description |
|--------|--------|-------------|
| +5 | CLK (SCK) | Serial Clock |
| +4 | CS (DAT3) | Chip Select |
| +3 | MOSI (CMD) | Master Out, Slave In |
| +2 | MISO (DAT0) | Master In, Slave Out |
| +1 | Insert Detect | Active low when card inserted (not used by driver) |

The default configuration uses base pin 56 (P2 Edge Module). Modify the `CON` section in the test files if using a different 8-pin group.

---

## License

MIT License - See LICENSE file for details.

Copyright (c) 2026 Iron Sheep Productions, LLC
