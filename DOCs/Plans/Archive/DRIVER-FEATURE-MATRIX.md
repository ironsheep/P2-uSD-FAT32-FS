# SD Card Driver Feature Usage Matrix

**Date:** February 4, 2026
**Purpose:** Identify which regression tests and utilities require full driver vs. minimal driver.

---

## Summary

| Category | Total | Minimal | Full |
|----------|-------|---------|------|
| Regression Tests | 12 | 7 | 5 |
| Utilities | 7 | 0 | 7 |
| Demo | 1 | 0 | 1 |
| **Total** | **20** | **7** | **13** |

**Key finding:** All utilities require the full driver. Only regression tests have minimal-compatible options.

---

## Regression Tests

### Tests Compatible with Minimal Driver

These tests only use core file operations (mount, open, read, write, close, seek, directory ops).

| Test File | Description | Driver Requirement |
|-----------|-------------|-------------------|
| `SD_RT_directory_tests.spin2` | Directory create/change/delete operations | **MINIMAL** |
| `SD_RT_read_write_tests.spin2` | File read/write operations | **MINIMAL** |
| `SD_RT_seek_tests.spin2` | File seek/tell operations | **MINIMAL** |
| `SD_RT_multihandle_tests.spin2` | V3 multi-file handle operations | **MINIMAL** |
| `SD_RT_multicog_tests.spin2` | Multi-cog concurrent access | **MINIMAL** |
| `SD_RT_error_handling_tests.spin2` | Error handling and recovery | **MINIMAL** |
| `TestCard/SD_RT_testcard_validation.spin2` | Test card content verification | **MINIMAL** |

### Tests Requiring Full Driver

| Test File | Description | Features Used | Driver Requirement |
|-----------|-------------|---------------|-------------------|
| `SD_RT_mount_tests.spin2` | Mount/unmount and edge cases | `readSectorRaw` (graceful failure test) | **FULL** |
| `SD_RT_file_ops_tests.spin2` | File operations with diagnostics | `readSectorRaw` (diagnostics) | **FULL** |
| `SD_RT_raw_sector_tests.spin2` | Raw sector read/write | `initCardOnly`, `readSectorRaw`, `writeSectorRaw` | **FULL** |
| `SD_RT_multiblock_tests.spin2` | Multi-block transfers | `readSectorsRaw`, `writeSectorsRaw`, `readSectorRaw`, `writeSectorRaw` | **FULL** |
| `SD_RT_format_tests.spin2` | FAT32 format validation | `initCardOnly`, `cardSizeSectors`, `readSectorRaw` | **FULL** |

### Support Files (Not Standalone Tests)

| File | Description | Driver Requirement |
|------|-------------|-------------------|
| `SD_RT_utilities.spin2` | Shared test utilities | N/A (support code) |

---

## Utilities

**All utilities require the full driver** - they perform low-level card operations.

| Utility File | Description | Features Used |
|--------------|-------------|---------------|
| `SD_card_characterize.spin2` | Card identification & specs | `initCardOnly`, `readSectorRaw`, `readCIDRaw`, `readCSDRaw`, `readSCRRaw`, `getOCR` |
| `SD_speed_characterize.spin2` | Speed testing at various frequencies | `initCardOnly`, `cardSizeSectors`, `readSectorRaw`, `readSectorsRaw`, `readCIDRaw`, `getSPIFrequency`, `checkCMD6Support`, `setSPISpeed`, `attemptHighSpeed` |
| `SD_frequency_characterize.spin2` | Find max stable SPI frequency | `writeSectorsRaw`, `readSectorsRaw` |
| `SD_performance_benchmark.spin2` | Performance benchmarking | `initCardOnly`, `readCIDRaw`, `writeSectorsRaw`, `readSectorsRaw`, `readSectorRaw` |
| `SD_format_utility.spin2` | FAT32 card formatter | `initCardOnly`, `cardSizeSectors`, `writeSectorRaw` |
| `SD_format_card.spin2` | Format utility runner | Uses `SD_format_utility` (indirect full) |
| `SD_FAT32_audit.spin2` | FAT32 structure validation | `initCardOnly`, `cardSizeSectors`, `readSectorRaw` |

---

## Demo Applications

| Demo File | Description | Features Used | Driver Requirement |
|-----------|-------------|---------------|-------------------|
| `SD_demo_shell.spin2` | Interactive SD card shell | `cardSizeSectors`, `readCIDRaw`, `getSPIFrequency`, `isHighSpeedActive` | **FULL** |

---

## Feature Usage Detail

### Raw Sector Access (`SD_INCLUDE_RAW`)

| Feature | Used By |
|---------|---------|
| `initCardOnly()` | SD_RT_raw_sector_tests, SD_RT_format_tests, SD_speed_characterize, SD_performance_benchmark, SD_format_utility, SD_card_characterize, SD_FAT32_audit |
| `readSectorRaw()` | SD_RT_mount_tests, SD_RT_file_ops_tests, SD_RT_raw_sector_tests, SD_RT_multiblock_tests, SD_RT_format_tests, SD_speed_characterize, SD_performance_benchmark, SD_card_characterize, SD_FAT32_audit |
| `writeSectorRaw()` | SD_RT_raw_sector_tests, SD_RT_multiblock_tests, SD_format_utility |
| `readSectorsRaw()` | SD_RT_multiblock_tests, SD_speed_characterize, SD_performance_benchmark, SD_frequency_characterize |
| `writeSectorsRaw()` | SD_RT_multiblock_tests, SD_performance_benchmark, SD_frequency_characterize |
| `cardSizeSectors()` | SD_RT_format_tests, SD_speed_characterize, SD_format_utility, SD_FAT32_audit, SD_demo_shell |

### Card Registers (`SD_INCLUDE_REGISTERS`)

| Feature | Used By |
|---------|---------|
| `readCIDRaw()` | SD_speed_characterize, SD_performance_benchmark, SD_card_characterize, SD_demo_shell |
| `readCSDRaw()` | SD_card_characterize |
| `readSCRRaw()` | SD_card_characterize |
| `getOCR()` | SD_card_characterize |

### Speed Control (`SD_INCLUDE_SPEED`)

| Feature | Used By |
|---------|---------|
| `getSPIFrequency()` | SD_speed_characterize, SD_demo_shell |
| `setSPISpeed()` | SD_speed_characterize |
| `attemptHighSpeed()` | SD_speed_characterize |
| `checkCMD6Support()` | SD_speed_characterize |
| `isHighSpeedActive()` | SD_demo_shell |

---

## Recommendations

### For Minimal Driver Testing

When testing `SD_MINIMAL` builds, run these tests:
```bash
cd tools
./run_test.sh ../regression-tests/SD_RT_directory_tests.spin2
./run_test.sh ../regression-tests/SD_RT_read_write_tests.spin2
./run_test.sh ../regression-tests/SD_RT_seek_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multihandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multicog_tests.spin2
./run_test.sh ../regression-tests/SD_RT_error_handling_tests.spin2
./run_test.sh ../regression-tests/TestCard/SD_RT_testcard_validation.spin2
```

### For Full Driver Testing

Full driver tests include all minimal tests plus:
```bash
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_raw_sector_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multiblock_tests.spin2
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 300
```

### Test Modification Consideration

Two tests use `readSectorRaw()` only for diagnostics, not core functionality:
- `SD_RT_mount_tests.spin2` - tests that raw reads fail gracefully before mount
- `SD_RT_file_ops_tests.spin2` - uses raw reads for debug dump of root directory

These could potentially be modified to work with minimal driver by:
1. Using `#IFDEF SD_INCLUDE_RAW` around diagnostic code
2. Skipping those specific test cases when raw access unavailable

This would increase minimal-compatible tests from 7 to 9.

---

## Implications for SD_MINIMAL

| Scenario | Coverage |
|----------|----------|
| Minimal driver build | 7 of 12 regression tests pass (58%) |
| Full driver build | 12 of 12 regression tests pass (100%) |
| Utilities with minimal | 0 of 7 work (0%) |
| Utilities with full | 7 of 7 work (100%) |

**Conclusion:** The minimal driver is suitable for applications that only need file I/O. All characterization, benchmarking, formatting, and diagnostic utilities require the full driver.
