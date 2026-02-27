# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-02-26

### Driver

- Volume label scan follows full root directory cluster chain (was limited to first 16 entries)
- FAT chain end-of-chain comparisons use unsigned operators for 2 TB addressing

### Utilities

- FSCK full validation now works on cards of any size (windowed bitmap; cards >64 GB scanned in 2M-cluster passes)
- Flexspin cross-compilation support added to format utility

### Testing

- Expanded to 345+ tests across 19 suites
- FSCK windowed bitmap diagnostic test for 128 GB cards

## [1.0.0] - 2026-02-25

**Initial release.**

### Driver

- FAT32-compliant SD card filesystem for the Parallax Propeller 2
- Smart pin SPI with streamer DMA for hardware-accelerated transfers
- Dedicated worker cog with hardware lock serialization
- Up to 6 simultaneous file and directory handles (configurable)
- Per-cog current working directory for safe multi-cog navigation
- Handle-based file and directory API: open, read, write, seek, enumerate, close
- Directory operations: create, navigate, delete, rename
- Raw sector read/write and multi-sector bulk transfers (CMD18/CMD25)
- Hardware-accelerated CRC-16 on all data transfers

### Utilities

- FAT32 format with cross-OS compatibility (Windows, macOS, Linux)
- 4-pass filesystem check and repair (fsck)
- Read-only filesystem audit
- Card characterization, SPI speed testing, and performance benchmark

### Demo

- Interactive terminal shell with DOS and Unix-style commands

### Card Compatibility

- SDHC and SDXC cards supported; tested with cards up to 128 GB across 9 manufacturers
- 22 cards cataloged, 13 benchmarked at both 350 MHz and 250 MHz sysclk
- Driver goal is 2 TB (FAT32/SDXC maximum); >1 TB requires sector addressing fix (see punch list)

### Known Limits

- FSCK full cluster-chain validation covers cards up to ~64 GB (P2 hub RAM constraint); larger cards receive structural checks only (VBR, FSInfo, FAT sync)
- Audit (read-only) has no card size constraint — all checks are structural

### Testing

- 345+ automated tests across 19 test suites validated on hardware

### Documentation

- Driver tutorial, theory of operations, card catalog
- SD card performance guide with ranked comparisons
- DOCs directory organized by topic

### Credits

- Original driver concept by Chris Gadd (OB4269 from Parallax OBEX)
- Driver development by Stephen M. Moraco, Iron Sheep Productions

## [0.9.3] - 2026-02-24

### Driver

- writeSector(): Cross-buffer cache coherence corrected
- do_create()/do_newfile()/do_newdir(): Entry address guard prevents MBR corruption
- do_rename(): 8.3 extension parsing corrected for mixed-case filenames
- searchDirectory(): Case-insensitive matching corrected

### API

- File handle limit increased from 4 to 6 (default)

### Utilities

- FSCK, audit, and format refactored into reusable cog+FIFO libraries
- sFormat() bounds checking added across all string formatting functions
- Demo shell: Line ending and prompt display corrected

### Testing

- Subdirectory operations test suite added (18 tests)
- Buffer overflow guard infrastructure added
- Suite expanded to 263+ tests across 11 core suites

### Documentation

- External SD header guide with 8-pin header group reference table

## [0.9.2] - 2026-02-10

### Utilities

- Demo shell: Help text reformatted for 80x25 terminal, line ending handling corrected

## [0.9.1] - 2026-02-09

**Initial testing release** — driver, utilities, demo shell, and 263+ regression tests.

[Unreleased]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.3...v1.0.0
[0.9.3]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/releases/tag/v0.9.1
