# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.1] - 2026-03-25

**Defragmentation support, next-fit allocation, contiguous file creation.**

### New Features

- `SD_INCLUDE_DEFRAG`: `fileFragments()`, `isFileContiguous()`, `compactFile()`, `createFileContiguous()` APIs
- `compactFile()` relocates a file's clusters into a contiguous chain with mandatory read-back verification
- `createFileContiguous()` pre-allocates a contiguous cluster chain for guaranteed non-fragmented writes
- FSCK/Audit reports fragmented file count and total fragments in summary output

### Improvements

- `allocateCluster()`: Next-fit scanning reduces fragmentation on sequential writes
- Allocation locality hint (`fsi_nxt_free`) persisted across mount/unmount cycles

### Bug Fixes

- `readSector()`: CRC match counter no longer incremented when CRC validation is disabled
- Disk-full simulation tests: Cluster cleanup between test phases prevents false failures

### Tests

- New SD_RT_defrag_tests suite: 12 tests covering fragment query, compaction, contiguous creation, next-fit allocation
- 25 suites, 464 tests, all passing on hardware

## [1.4.0] - 2026-03-17

**Worker loop restructure, live timestamps, auto-flush, non-blocking async I/O.**

### New Features

- `setDate()`, `getDate()`: Live clock with 2-second auto-advance for file timestamps
- Auto-flush dirty handles after 200ms idle (zero cost during active I/O)
- `SD_INCLUDE_ASYNC`: Non-blocking file I/O via `startReadHandle()`, `startWriteHandle()`, `isComplete()`, `getResult()`, `cancelAsync()`
- Demo shell: `date` command to show/set driver clock; directory listings show modification timestamps

### Improvements

- Worker cog loop restructured with dedicated clock tick and idle flush slots
- `run_regression.sh`: `--run-only` flag recompiles only stale .bin files (checks source and driver timestamps)

### Tests

- 452 tests across 24 suites, verified on hardware
- New suites: per-cog CWD isolation, concurrent stress, live timestamps, async I/O
- Mutation testing pass 2: 14/14 non-equivalent mutations killed (100%)

## [1.3.2] - 2026-03-10

**NCO write alignment fix, selective debug channels, controller-specific code removed.**

### Bug Fixes

- `writeSector()`, `writeSectors()`: Streamer write timing corrected for power-of-2 SPI half-period values (hp=4, hp=8) via NCO frequency adjustment
- Controller-specific SPI speed limiting removed; all cards use reported max speed capped at 25 MHz

### Improvements

- All 402 `debug()` statements converted to `debug[CH_xxx]()` across 10 named channels
- `DEBUG_MASK` replaces `DEBUG_DISABLE` as the single debug control knob
- `DEBUG_MASK = 0` for production; set channel bits to enable selective debug output
- Channels: INIT, MOUNT, FILE, DIR, SECTOR, STATUS, IDENT, HSPEED, API, RECOVER
- Version directive upgraded to `{Spin2_v46}` for channel support
- All preprocessor directives standardized to lowercase (`#ifdef`, `#define`, `#pragma exportdef`)
- Regression tests consolidated under `src/regression-tests/`

## [1.3.1] - 2026-03-07

**CMD13 STATUS byte fix, reduced driver footprint, updated memory sizing reference.**

### Bug Fixes

- `checkCardStatus()`: STATUS byte errors now detected correctly (was checking uninitialized return variable instead of R2 response)
- `last_cmd13_status`: Diagnostic field now captures the actual STATUS byte from CMD13

### Improvements

- Driver hub footprint reduced through SPI transaction consolidation

### Documentation

- Memory sizing guide updated with current v1.3.x footprint data across all configurations
- DEBUG_MASK channel plan: 10 selective debug channels mapped for all 402 debug statements

## [1.3.0] - 2026-03-06

**R1 response parsing fix, CMD12 tolerance, CMD23 probing, 427 regression tests across 20 suites.**

### Bug Fixes

- R1 response parsing: skip bytes with bit 7 set per SD spec Section 7.3.2.1 (fixes CMD13 false errors on cards with bus artifacts)
- CMD12 tolerance: multi-block reads recover via CS deassert on cards with aggressive read-ahead pipelines

### New Features

- `cardWarnings()`: Bitmask API for init-time capability discoveries
- CMD23 probing: automatic SET_BLOCK_COUNT detection and use when supported in SPI mode

### Improvements

- `recoverToIdle()`: CS deassert recovery per SD spec Section 7.2.2
- `readSectors()`: CMD23 path with auto-stop verification and fallback to CMD12

### Tests

- 427 tests across 20 suites, verified on SP Elite 64GB + Transcend 32GB
- Cluster boundary crossing, disk-full simulation, constant data patterns ($00/$FF round-trip)
- Double-mount idempotency, filename edge cases (min/max 8.3, case conversion)
- Unified regression runner with layered dependency ordering
- `setTestMaxClusters()`, `setForceCmd13()`, `clearTestErrors()`: Test hooks for disk-full simulation, CMD13 override, and hook reset
- `getLastCMD13Capture()`, `getLastCMD13PreCapture()`: Diagnostic byte stream accessors

## [1.2.1] - 2026-03-05

**CMD13 compatibility analysis, audit severity corrections, and regression test strengthening.**

### Improvements

- Audit: Partition type $0B (FAT32 CHS) accepted as valid alongside $0C (FAT32 LBA)
- Audit: Backup FSInfo mismatch downgraded from error to warning (common on FAT32 media)
- CMD13 compatibility analysis and probe infrastructure for cards with broken SPI-mode status reporting

### Tests

- 20 new tests across 7 suites (392→412 total), verified on hardware
- Sector boundary coverage: 511-byte and 513-byte read/write round-trip tests
- tellHandle() postconditions verified after read and write operations
- EOF handling: exact-EOF read, pre-EOF false check, partial-read remaining bytes
- fileSizeHandle() verified during write phase of boundary tests
- Guard zone overflow detection on directory read buffers
- Handle type mismatch: file operations on directory handles return E_NOT_A_DIR_HANDLE
- Use-after-close: all 7 handle operations return E_INVALID_HANDLE on closed handles
- Post-unmount state: APIs return E_NOT_MOUNTED, remount succeeds
- CRC error observability: getCRCMismatchCount() verified after injected read errors
- Handle pool recycling: mixed file and directory handles reuse freed slots

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

- All 20 regression suites pass (392 tests)

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

[Unreleased]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.3.2...v1.4.0
[1.3.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.3...v1.0.0
[0.9.3]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/releases/tag/v0.9.1
