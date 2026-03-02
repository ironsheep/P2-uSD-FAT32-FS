# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-03-02

**Consistent error codes across the entire public API, card presence detection, and transport-layer diagnostics.**

### Breaking Changes

- 17 PUB methods now return `SUCCESS` (0) / negative error code instead of `true`/`false`: `mount`, `unmount`, `sync`, `newDirectory`, `changeDirectory`, `deleteFile`, `rename`, `moveFile`, `setVolumeLabel`, `initCardOnly`, `readSectorRaw`, `writeSectorRaw`, `readVBRRaw`, `readCIDRaw`, `readCSDRaw`, `readSCRRaw`, `readSDStatusRaw`
- Code testing `if sd.mount(...)` (truthy = success) must change to `if sd.mount(...) == sd.SUCCESS` -- see [Migration Guide](DOCs/MIGRATION-GUIDE-v1.2.0.md)

### New Features

- `E_NO_CARD` (-8): `mount()` and `initCardOnly()` now detect missing cards using a P2 internal pull-up on MISO and return a specific error code instead of generic `E_INIT_FAILED`
- `setSPISpeed()`: Public API method for setting SPI clock frequency at runtime
- `SD_INCLUDE_STACK_CHECK`: Conditional feature flag for worker cog stack depth measurement

### Improvements

- Transport layer returns specific error codes (`E_TIMEOUT`, `E_CRC_ERROR`, `E_BAD_RESPONSE`, `E_WRITE_REJECTED`, `E_CARD_BUSY`, `E_IO_ERROR`) instead of bare `-1` across `readSector`, `writeSector`, `allocateCluster`, and all SPI wait/response methods
- `writeSector()`: Returns 0/negative error codes instead of boolean, with specific failure reasons for timeout, CRC reject, card busy, and programming errors
- Magic numbers replaced with named constants throughout the driver (sector geometry, FAT32 structures, SPI commands, R1 response masks, card init timing)

### Documentation

- [Migration Guide](DOCs/MIGRATION-GUIDE-v1.2.0.md) for updating v1.0/v1.1 code to v1.2 error-code patterns
- [Card Presence Detection](DOCs/Reference/CARD-PRESENCE-DETECTION.md) reference with electrical analysis and SD spec research
- [Memory Sizing Guide](DOCs/Reference/MEMORY-SIZING-GUIDE.md) for hub RAM planning
- Theory of Operations expanded: card presence detection, card identification and adaptive timing
- Architecture Decision 13: Card presence detection via P2 internal pull-up

### Tests

- All 20 regression suites pass (389 tests)
- Test files use `sd.*` prefixed constants instead of local redefinitions
- Standardized file headers and MIT license footers across all `.spin2` files

## [1.1.0] - 2026-02-26

**FSCK scales to any card size, CRC error injection for fault testing, V1 legacy API removed.**

### Breaking Changes

- V1 legacy API removed (`readFile()`, `writeFile()`, `readDirectory()`, etc.) -- use handle-based API

### New Features

- CRC error injection hooks for hardware-level fault testing (`setTestForceReadError`, `setTestForceWriteError`)
- `readVBRRaw()` available with `SD_INCLUDE_REGISTERS` alone (no longer requires `SD_INCLUDE_RAW`)

### Improvements

- Volume label scan follows full root directory cluster chain
- FAT chain addressing supports cards up to 2 TB
- FSCK full validation works on cards of any size (windowed bitmap for cards >64 GB)
- Cross-compilation support for Spin Tools IDE and flexspin

### Tests

- Expanded to 389 tests across 20 suites (CRC injection, recovery, and error handling suites added)
- FSCK windowed bitmap diagnostic test for 128 GB cards

## [1.0.0] - 2026-02-25

**Initial release.**

### New Features

- FAT32-compliant SD card filesystem for the Parallax Propeller 2
- Smart pin SPI with streamer DMA for hardware-accelerated transfers
- Dedicated worker cog with hardware lock serialization
- Up to 6 simultaneous file and directory handles (configurable)
- Per-cog current working directory for safe multi-cog navigation
- Handle-based file and directory API: open, read, write, seek, enumerate, close
- Directory operations: create, navigate, delete, rename
- Raw sector read/write and multi-sector bulk transfers (CMD18/CMD25)
- Hardware-accelerated CRC-16 on all data transfers
- SDHC and SDXC cards supported; tested with cards up to 128 GB across 9 manufacturers

### Utilities

- FAT32 format with cross-OS compatibility (Windows, macOS, Linux)
- 4-pass filesystem check and repair (fsck)
- Read-only filesystem audit
- Card characterization, SPI speed testing, and performance benchmark
- Interactive terminal shell with DOS and Unix-style commands

### Tests

- 345+ automated tests across 19 test suites validated on hardware

### Documentation

- Driver tutorial, theory of operations, card catalog
- SD card performance guide with ranked comparisons

## [0.9.3] - 2026-02-24

### Improvements

- File handle limit increased from 4 to 6 (default)
- writeSector(): Cross-buffer cache coherence verified across all three sector caches
- File and directory creation validates entry address before writing (prevents MBR corruption)
- rename(): 8.3 extension parsing handles mixed-case filenames
- File and directory lookup uses case-insensitive matching
- Demo shell: Line ending and prompt display corrected

### Tests

- Subdirectory operations test suite added (18 tests)
- Buffer overflow guard infrastructure added
- Suite expanded to 263+ tests across 11 core suites

### Documentation

- External SD header guide with 8-pin header group reference table

## [0.9.2] - 2026-02-10

### Improvements

- Demo shell: Help text formatted for 80x25 terminal

## [0.9.1] - 2026-02-09

**Initial testing release** -- driver, utilities, demo shell, and 263+ regression tests.

[Unreleased]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.3...v1.0.0
[0.9.3]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/releases/tag/v0.9.1
