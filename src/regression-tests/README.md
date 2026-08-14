# SD Card Driver Regression Tests

Automated regression test suite for the P2 SD Card Driver. All tests execute on real Propeller 2 hardware with a physical SD card.

> **What belongs here:** automated **pass/fail** suites that assert via `isp_rt_utilities` and run under `tools/run_regression.sh`. Not user tools (those go in [`src/UTILS/`](../UTILS/)) and not ad-hoc developer probes (those go in [`diagnostic-tests/`](../../diagnostic-tests/)). A program that only *displays* results without asserting is a diagnostic, not a regression test.

## Test Summary

### Core Test Suites (verified 2026-04-01)

| Test Suite | Description | Tests |
|------------|-------------|-------|
| **Mount Tests** | Card initialization, mounting, unmounting, pre/post-mount errors, double-mount, structural corruption (raw-patched MBR/VBR/FSInfo), RAW-mode gate | 43 |
| **File Operations** | Create, open, close, delete, rename, filename edge cases, cluster-0 lazy-allocation fixtures (V3 handle API) | 35 |
| **Read/Write Tests** | Data integrity, sector/cluster boundaries, constant patterns, tellHandle/EOF, multi-cluster, large files | 49 |
| **Directory Tests** | Directory listing, navigation, deep nesting, boundaries, many-file stress, stale cluster, cluster-0 chdir rejection | 33 |
| **Seek Tests** | Random access, cross-sector seeks, seek boundaries | 38 |
| **Multicog Tests** | Singleton pattern, concurrent access, lock serialization | 15 |
| **Multihandle Tests** | Multiple simultaneous file handles, use-after-close, pool recycling | 22 |
| **Multiblock Tests** | Multi-sector streamer DMA transfers (CMD18/CMD25) | 7 |
| **Raw Sector Tests** | Direct sector read/write, large LBA addressing | 14 |
| **Format Tests** | FAT32 structure validation, cross-OS compatibility | 57 |
| **Subdirectory Ops Tests** | Cross-buffer cache coherence, empty files, subdir operations | 18 |
| **Core Total** | | **331** |

### Additional Test Suites

| Test Suite | Description | Tests |
|------------|-------------|-------|
| **Directory Handle Tests** | V3 directory handle enumeration, pool interaction, E_NOT_A_DIR_HANDLE | 25 |
| **Volume Tests** | Volume label, label protection from file operations, VBR access, syncAll, sync, setDate, disk full, auto-flush | 38 |
| **Register Tests** | CSD, CID, SCR, SD Status and OCR register access, timeout values, capacity cross-check, RAW-mode repeat | 17 |
| **Speed Tests** | SPI frequency, CMD6, high-speed mode, speed boundaries | 15 |
| **CRC Diagnostic Tests** | CRC counters, validation toggle, CMD13 diagnostics | 14 |
| **Error Handling Tests** | Error conditions, invalid handles, dir handle type mismatch, rename edge cases | 19 |
| **Error Injection Tests** | Targeted fault injection: named-LBA read/write failure, nth-write failure, one-shot vs sticky, clean disarm; failure paths turned back on the driver (primitive reporting, Tier-1 corruption, search failure, short counts); background flush reporting (slow: waits out idle windows); sync/freeSpace/stop status propagation; directory-extend true error codes | 36 |
| **CRC Validation Tests** | CRC error injection hooks, forced read/write CRC errors, hook state management | 6 |
| **Recovery Tests** | Recovery after read/write errors, CRC counter verification, remount recovery, handle isolation | 7 |
| **FIFO Tests** | String FIFO (isp_string_fifo) inter-cog communication | 21 |
| **Cog CWD Tests** | Per-cog working directory isolation, multi-cog CWD independence | 5 |
| **Stress Tests** | Concurrent reader/writer integrity, rapid open/close under contention | 4 |
| **Timestamp Tests** | setDate/getDate round-trip, parameter validation bounds, live clock advance, creation/modification stamps | 8 |
| **Async I/O Tests** | Non-blocking read/write, isComplete polling, cancelAsync, multi-cog interleave, per-cog ownership, same-cog busy guard, failure paths (injected read failure, partial count, collect-time errors) | 13 |
| **Defrag Tests** | fileFragments, isFileContiguous, compactFile, createFileContiguous, duplicate-create leak witness, next-fit allocation | 13 |
| **FAT Chain Tests** | Cross-boundary overwrite follows the FAT chain; mid-sector append preserves leading bytes | 2 |
| **Write Integrity Tests** | Content written is content stored: byte-level verification against an independently generated pattern across sector boundaries (511/512/513, 1023/1024/1025), cluster boundaries derived from `clusterBytes()` at run time, three files written interleaved, and a raw multi-block round-trip that bypasses the file layer. Classifies a mismatch as SHIFTED-LATE / SHIFTED-EARLY / OTHER so a write-phase fault is named on sight | 13 |
| | **Additional Total** | **256** |
| | **Grand Total (28 suites)** | **587** |

**How a test is counted.** One test is one *executed* `utils.startTest()` call — the same
unit the framework prints as `* Test #N`. Every suite, including `SD_RT_multiblock_tests`
and `SD_RT_raw_sector_tests` (converted to the framework in v1.7.0), scores through
`utils.ShowTestEndCounts()`. Sub-tests within a test (`evaluateSubValue()` and friends)
are not counted separately. The numbers above are reproducible from source:

```bash
cd src/regression-tests && grep -c "utils.startTest(" SD_RT_<suite>_tests.spin2
```

One correction applies: a `startTest()` inside a helper executes once per call — the mount
suite's `corruptCase()` helper runs 4 times, so its grep count of 40 executes as 43.

`tools/check_doc_counts.sh` compares documents to each other and cannot see drift between
a document and the suites on disk, so these counts are verified by the command above, not
by that script.

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

### Running the Full Suite (the normal path)

Use the regression runner. It runs **every** suite in dependency order in a
single, unattended, end-to-end pass — compile, card identify, incoming audit,
baseline format, all suites, closing audit, summary table:

```bash
cd tools/
./run_regression.sh --include-format --log ../DOCs/sweep.txt
```

What it does for you:

- **Preflight** — identifies the card (capacity, geometry, SN, warnings) and runs
  a read-only FAT32 audit of the card's incoming state, so the transcript records
  which card produced the results.
- **Card as scratch** — establishes a clean FAT32 baseline before the first suite
  and reformats around the destructive suites (`fatchain`, `format`). Authorizing
  a regression run authorizes formatting the card.
- **Runs to the end** — a failing suite is recorded and the sweep *continues*, so
  one pass gives you every suite's result. Use `--stop-on-failure` for forensic
  runs where the on-card damage is the evidence you want to inspect.
- **Rides out serial transients** — a failed download is retried once and, if it
  fails again, reported as `INFRA` (suite never executed), kept distinct from a
  real test failure.
- **Closing audit** — proves the sweep leaves the card healthy.

Exit code 0 means every suite ran, every suite passed, and the card ended clean.
`./run_regression.sh --help` lists all options.

### Running Individual Suites

For iterating on one suite. `run_test.sh` never reformats the card — the runner
above is the only thing that does.

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

# Multi-cog isolation and stress tests
./run_test.sh ../src/regression-tests/SD_RT_cogcwd_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_stress_tests.spin2

# Timestamp and async I/O tests
./run_test.sh ../src/regression-tests/SD_RT_timestamp_tests.spin2
./run_test.sh ../src/regression-tests/SD_RT_async_tests.spin2 -t 120

# Defrag tests
./run_test.sh ../src/regression-tests/SD_RT_defrag_tests.spin2 -t 120

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

<!-- api-audit: template — someOperation() is a placeholder for the reader's own call -->
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

**Card-Aware Test Helpers (v1.5.2+):**
| Function | Purpose |
|----------|---------|
| `cacheCardProfile(eraseBlk, capacity, readT, writeT, maxSpiHz, mfrId, cardClass)` | Cache card characteristics from driver getters; call once after mount |
| `safeTestRegionStart()` | First erase-block-aligned sector past FAT32 metadata |
| `nonAdjacentSectors(count, p_dest)` | Fill array with sectors each in a different erase block |
| `blockAlignedRange(sectorCount)` | Erase-block-aligned start sector for a range |
| `cardAdjustedTimeoutMs(baseMs)` | Scale a base timeout for SDSC vs SDHC class |
| `profileReport()` | Format-print cached profile for test reproducibility |

These helpers prevent tests from accidentally measuring card-physics issues (erase-block stress, slow-card timeouts) when they intend to measure driver behavior.

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
