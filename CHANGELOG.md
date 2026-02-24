# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Cross-buffer cache coherence bug in `writeSector()` — when writing a sector through one buffer type (e.g., BUF_DIR), other buffer types' caches (BUF_DATA, BUF_FAT) were not invalidated, causing stale data on subsequent reads through a different buffer type. This manifested as `dir` showing empty after `touch` in subdirectories.
- Demo shell FIFO line endings — 6 occurrences of `serial.str()` in format/audit/fsck output changed to `serial.fstr0()` for correct CR+LF line endings through FIFO path
- Demo shell `confirmYN()` prompt visibility — added CR flush and cursor positioning for reliable display

### Added

- New regression test suite: `SD_RT_subdir_ops_tests.spin2` (18 tests) covering subdirectory file operations, cross-buffer cache coherence, empty file handling, rename in subdirectories, and cross-directory navigation
- Refactored FSCK, audit, and format into reusable cog+FIFO libraries (`isp_fsck_utility.spin2`, `isp_string_fifo.spin2`)
- `sFormat()` bounds checking in `isp_mem_strings.spin2` — all formatting functions now take `maxLen` parameter to prevent buffer overflow
- Buffer overflow guard byte infrastructure across all regression tests

### Changed

- Multi-file handle system increased from 4 to 6 simultaneous handles (default)
- Regression test suite expanded to 263+ tests across 11 core test suites (was 251 across 11)

## [0.9.2] - 2026-02-10

### Fixed

- Demo shell help text rewritten as two-column layout to fit 80x25 terminal (was 33 lines, now 15)
- Help text DAT strings use CR+LF line endings for correct terminal output
- Input parser explicitly ignores LF; only CR terminates command input
- File display (`type` command) passes through both CR and LF from file data

## [0.9.1] - 2026-02-09

Initial release.

- FAT32-compliant SD card filesystem driver for the Parallax Propeller 2
- Smart pin SPI with streamer DMA for hardware-accelerated transfers
- Dedicated worker cog with hardware lock serialization
- Multi-file handle system (up to 6 simultaneous file and directory handles, configurable)
- Per-cog current working directory for safe multi-cog navigation
- Handle-based file API: open, read, write, seek, close
- Handle-based directory enumeration API
- Directory operations: create, navigate, enumerate, delete, rename
- Low-level raw sector read/write and multi-sector (CMD18/CMD25) bulk transfers
- Hardware-accelerated CRC-16 validation on all data transfers
- FAT32 format utility with cross-OS compatibility (Windows, macOS, Linux)
- FSCK utility: 4-pass filesystem check and repair
- FAT32 audit utility: read-only filesystem validation
- Card characterization, SPI speed testing, and performance benchmark utilities
- Interactive demo shell with DOS and Unix-style commands
- 263+ automated regression tests across 11 core test suites
- Documentation: tutorial, theory of operations, card catalog, benchmark results

### Credits

- Original driver concept by Chris Gadd (OB4269 from Parallax OBEX)
- Driver development by Stephen M. Moraco, Iron Sheep Productions


[Unreleased]: https://github.com/ironsheep/P2-uSD-FileSystem/compare/v0.9.2...HEAD
[0.9.2]: https://github.com/ironsheep/P2-uSD-FileSystem/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/ironsheep/P2-uSD-FileSystem/releases/tag/v0.9.1
