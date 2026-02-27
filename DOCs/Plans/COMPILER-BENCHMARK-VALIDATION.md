# Compiler Benchmark Validation: pnut-ts v1.52.1 vs v1.52.2

**Date**: Feb 27, 2026
**Purpose**: Validate that pnut-ts v1.52.2 produces byte-identical binaries to v1.52.1, confirming it is a safe compiler upgrade (speed improvement only).

---

## Result: PASS — All 34 binaries are byte-identical

Every MD5 checksum matches between the two compiler versions. The new compiler produces the exact same output, approximately **2x faster**.

| Metric | v1.52.1 | v1.52.2 | Change |
|---|---|---|---|
| **Total compile time** | 209,186 ms | 105,350 ms | **1.99x faster** |
| **Files compiled** | 34/34 OK | 34/34 OK | identical |
| **Checksum mismatches** | — | — | **0** |

---

## Per-File Comparison

### Regression Tests (18 files, compiled with `-d`)

| File | Size (B) | MD5 | v1.52.1 (ms) | v1.52.2 (ms) | Speedup |
|---|---|---|---|---|---|
| SD_RT_mount_tests.spin2 | 37,113 | `06e44e39...` | 4,449 | 2,416 | 1.84x |
| SD_RT_volume_tests.spin2 | 38,996 | `71ad4efa...` | 4,272 | 2,238 | 1.91x |
| SD_RT_file_ops_tests.spin2 | 40,511 | `cb0849a8...` | 4,810 | 2,506 | 1.92x |
| SD_RT_read_write_tests.spin2 | 44,631 | `ce351834...` | 4,209 | 2,259 | 1.86x |
| SD_RT_seek_tests.spin2 | 38,477 | `d8cf1d91...` | 3,948 | 2,137 | 1.85x |
| SD_RT_directory_tests.spin2 | 36,193 | `b568577c...` | 4,074 | 2,124 | 1.92x |
| SD_RT_dirhandle_tests.spin2 | 36,932 | `35fb9ca3...` | 4,205 | 2,188 | 1.92x |
| SD_RT_subdir_ops_tests.spin2 | 37,383 | `c86b53a6...` | 4,696 | 2,461 | 1.91x |
| SD_RT_multihandle_tests.spin2 | 37,500 | `f236ed70...` | 3,990 | 2,157 | 1.85x |
| SD_RT_multicog_tests.spin2 | 37,322 | `124c9340...` | 4,142 | 2,166 | 1.91x |
| SD_RT_error_handling_tests.spin2 | 35,918 | `7e6338c4...` | 4,115 | 2,136 | 1.93x |
| SD_RT_register_tests.spin2 | 35,715 | `7b5171a5...` | 4,174 | 2,167 | 1.93x |
| SD_RT_speed_tests.spin2 | 36,919 | `0a5b13e3...` | 4,107 | 2,142 | 1.92x |
| SD_RT_crc_diag_tests.spin2 | 36,933 | `b518ae7c...` | 4,523 | 2,372 | 1.91x |
| SD_RT_raw_sector_tests.spin2 | 38,393 | `393e9c31...` | 4,625 | 2,433 | 1.90x |
| SD_RT_multiblock_tests.spin2 | 38,063 | `d9fda0e3...` | 4,913 | 2,564 | 1.92x |
| SD_RT_format_tests.spin2 | 50,009 | `cf7efc19...` | 9,876 | 5,035 | 1.96x |
| SD_RT_fifo_tests.spin2 | 18,646 | `0fe77a70...` | 1,025 | 632 | 1.62x |
| **Subtotal** | **675,654** | | **80,153** | **42,133** | **1.90x** |

### Diagnostic Tests (4 files, compiled with `-d`)

| File | Size (B) | MD5 | v1.52.1 (ms) | v1.52.2 (ms) | Speedup |
|---|---|---|---|---|---|
| SD_card_info_tests.spin2 | 41,990 | `f231aef4...` | 4,929 | 2,594 | 1.90x |
| SD_freq_sweep_tests.spin2 | 49,086 | `01299525...` | 4,780 | 2,519 | 1.90x |
| SD_spi_limit_test.spin2 | 34,514 | `202ea328...` | 4,442 | 2,315 | 1.92x |
| SD_diag_fsck_window_test.spin2 | 57,852 | `94b1664d...` | 22,609 | 10,532 | 2.15x |
| **Subtotal** | **183,442** | | **36,760** | **17,960** | **2.05x** |

### Utilities (7 files, no debug)

| File | Size (B) | MD5 | v1.52.1 (ms) | v1.52.2 (ms) | Speedup |
|---|---|---|---|---|---|
| SD_format_card.spin2 | 37,516 | `6fa6a56c...` | 5,134 | 2,713 | 1.89x |
| SD_FAT32_fsck.spin2 | 44,068 | `110ecdd3...` | 13,230 | 5,935 | 2.23x |
| SD_FAT32_audit.spin2 | 44,068 | `05af27e0...` | 13,225 | 5,945 | 2.22x |
| SD_card_characterize.spin2 | 33,600 | `93578c91...` | 4,917 | 2,544 | 1.93x |
| SD_frequency_characterize.spin2 | 30,216 | `d4786706...` | 4,613 | 2,390 | 1.93x |
| SD_performance_benchmark.spin2 | 293,560 | `e5786a98...` | 4,668 | 2,550 | 1.83x |
| SD_speed_characterize.spin2 | 30,280 | `e23cda32...` | 4,636 | 2,411 | 1.92x |
| **Subtotal** | **513,308** | | **50,423** | **24,488** | **2.06x** |

### Demo (1 file, no debug)

| File | Size (B) | MD5 | v1.52.1 (ms) | v1.52.2 (ms) | Speedup |
|---|---|---|---|---|---|
| SD_demo_shell.spin2 | 61,544 | `6d30eb76...` | 26,115 | 12,092 | 2.16x |

### Examples (4 files, no debug)

| File | Size (B) | MD5 | v1.52.1 (ms) | v1.52.2 (ms) | Speedup |
|---|---|---|---|---|---|
| SD_example_read_write.spin2 | 27,212 | `68d8c31c...` | 3,685 | 1,925 | 1.91x |
| SD_example_data_logger.spin2 | 27,384 | `d906b26a...` | 3,699 | 1,929 | 1.92x |
| SD_example_directory_walk.spin2 | 27,504 | `e7b35555...` | 3,704 | 1,929 | 1.92x |
| SD_example_multicog.spin2 | 27,416 | `b564ec32...` | 3,728 | 1,936 | 1.93x |
| **Subtotal** | **109,516** | | **14,816** | **7,719** | **1.92x** |

---

## Summary by Category

| Category | Files | Total Size | v1.52.1 (ms) | v1.52.2 (ms) | Speedup |
|---|---|---|---|---|---|
| Regression tests | 18 | 675,654 B | 80,153 | 42,133 | 1.90x |
| Diagnostic tests | 4 | 183,442 B | 36,760 | 17,960 | 2.05x |
| Utilities | 7 | 513,308 B | 50,423 | 24,488 | 2.06x |
| Demo | 1 | 61,544 B | 26,115 | 12,092 | 2.16x |
| Examples | 4 | 109,516 B | 14,816 | 7,719 | 1.92x |
| **Total** | **34** | **1,543,464 B** | **209,186** | **105,350** | **1.99x** |

---

## Observations

1. **Binary output is identical** — zero checksum mismatches across all 34 files. v1.52.2 is a pure performance improvement.

2. **Speedup is consistent** — ranges from 1.62x (smallest file, SD_RT_fifo_tests at 18 KB) to 2.23x (SD_FAT32_fsck at 44 KB). Larger/more complex files tend to show greater speedup.

3. **Largest absolute savings** — SD_demo_shell: 14 seconds faster (26s → 12s). SD_diag_fsck_window_test: 12 seconds faster (23s → 11s).

4. **Full project compile** — drops from 3.5 minutes to 1.75 minutes.

---

## Methodology

- Tool: `tools/compiler_benchmark.sh` (records size, MD5, and wall-clock time per file)
- Regression and diagnostic tests compiled with `-d` (debug enabled)
- Utilities, demo, and examples compiled without debug
- Each file compiled individually with appropriate `-I` include paths
- Raw benchmark logs: `tools/logs/compiler_benchmark_v1.52.1_260227-153636.txt` and `tools/logs/compiler_benchmark_v1.52.2_260227-154237.txt`
