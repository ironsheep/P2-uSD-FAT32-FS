# Regression Test Suite

Automated hardware-verified test suite for the P2 SD Card Driver. All 25 test suites (465 tests) execute on real Propeller 2 hardware with a physical SD card.

## Running Tests

From the `tools/` directory (one level above `src/`):

```bash
# Single suite
./run_test.sh ../src/regression-tests/SD_RT_mount_tests.spin2

# Full regression (all 24 default suites, stop-on-failure)
./run_regression.sh

# Including format test (WARNING: erases card!)
./run_regression.sh --include-format
```

## Test Suites

| Suite | Tests | Description |
|-------|-------|-------------|
| mount_tests | 29 | Card init, mount/unmount lifecycle |
| file_ops_tests | 26 | Create, open, close, delete, rename |
| read_write_tests | 48 | Data integrity, boundaries, large files |
| seek_tests | 37 | Random access, cross-sector seeks |
| directory_tests | 29 | Listing, navigation, deep nesting |
| multihandle_tests | 21 | Concurrent file handles |
| multicog_tests | 14 | Multi-cog concurrent access |
| volume_tests | 31 | Volume label, free space, auto-flush, disk full |
| dirhandle_tests | 25 | Directory handle enumeration |
| subdir_ops_tests | 18 | Subdirectory file operations |
| raw_sector_tests | 14 | Direct sector read/write |
| multiblock_tests | 6 | Streamer DMA multi-block transfers |
| register_tests | 10 | CID, CSD, SCR register access |
| speed_tests | 15 | CMD6 high-speed mode |
| crc_diag_tests | 14 | CRC counters and diagnostics |
| crc_validation_tests | 6 | CRC error injection |
| error_handling_tests | 14 | Error paths and misuse |
| recovery_tests | 7 | Recovery after CRC errors |
| fifo_tests | 21 | Inter-cog string FIFO |
| cogcwd_tests | 5 | Per-cog working directory isolation |
| stress_tests | 4 | Concurrent read/write stress |
| timestamp_tests | 6 | Live clock timestamps |
| async_tests | 6 | Non-blocking async I/O |
| defrag_tests | 12 | Defragmentation, compaction, contiguous allocation |
| format_tests | 46 | FAT32 format validation (optional, erases card) |

## Prerequisites

- **pnut-ts** and **pnut-term-ts** command-line tools
- Parallax Propeller 2 connected via USB
- FAT32-formatted SD card

## Test Framework

All tests use the shared `isp_rt_utilities.spin2` framework for assertions, guard zones, and pattern generation.

---

*Part of the [P2 SD Card Driver](../README.md) package -- Iron Sheep Productions*
