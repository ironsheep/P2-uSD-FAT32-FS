# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.6.0] - 2026-07-25

**Write-path corruption fixes; broader card compatibility; write-error reliability.**

Two data-corruption defects are fixed, both in **rewriting an existing file**. Files created once and written front to back — the common case, including data loggers that only append sector-aligned records — were never affected.

### Bug Fixes

- **Reopening a file and overwriting across a cluster boundary** (`openFileWrite()` + `seekHandle()` back into the file, then `writeHandle()`) now follows the file's existing chain. The data past the rewritten region survives instead of being orphaned.
- **Appending to a file whose length isn't a multiple of 512** (`openFileWrite()` + `writeHandle()`) now preserves the bytes already in that final sector instead of zeroing them.
- **Write failures are no longer silent.** A write that fails — full card, failing card, unresponsive card — returns an error instead of reporting success, and the error says what actually went wrong. This covers writing, closing, syncing, unmounting, and deleting.
- **Bulk reads** use the same clock-timing correction as writes, removing a read-reliability difference at some SPI speeds.
- **Remounting from a different binary** no longer fails with a spurious `E_NO_CARD`.
- **A stray write can no longer damage the filesystem's own structures** — `writeHandle()` refuses to write below the data region.

### Upgrade / recovery note

A card written by an earlier release may carry silent damage — but only if you rewrote existing files as described above.

- Run **`SD_FAT32_audit`** (or `SD_FAT32_fsck` to also repair) to find **lost clusters** left by a cross-boundary overwrite. fsck reclaims the space; it cannot restore the file's lost tail content.
- Zeroed leading bytes from a mid-sector append leave **no filesystem footprint — no tool can detect them.** Verify or restore affected files from backup.

### Changes

- **`SD_FAT32_audit` now does the deep scan, read-only.** It performs the same full check as `SD_FAT32_fsck` — including finding lost clusters — but changes nothing. Use `audit` to look, `fsck` to repair. The separate `SD_FAT32_check` tool is removed; `audit` replaces it.

### New Features

- **Cards that report placeholder data checksums now work.** Some counterfeit and marginal SDSC cards previously failed every read. They are detected at mount, flagged in `cardWarnings()` as `CW_NO_DATA_CRC`, and run at a clock speed probed as safe for that card. Cards with real checksums keep strict validation.
- **macOS-formatted cards mount and audit cleanly**, including small (SDSC) cards.
- **`SD_PINS_EXTERNAL` build flag**: use an external SD header (base pins 16–21) instead of the P2 Edge onboard slot.

## [1.5.3] - 2026-05-07

**Timeout calculation overflow fix; SDSC long-write support.**

This release fixes a latent 32-bit arithmetic overflow in the driver's timeout calculations that caused immediate spurious "timeout" failures on SDSC cards at lower system clocks. The driver was computing deadline values as `GETCT() + (clkfreq / N) * timeout_ms`, which overflowed signed 32-bit arithmetic whenever the product exceeded 2^31 sysclks. SDSC cards with long CSD-spec'd timeouts (TAAC + R2W_FACTOR can produce up to 24,000 ms write timeouts per spec) hit this overflow at any system clock where the calculation crossed the boundary, causing every read/write attempt to be flagged as timed-out before the operation even started. The fix converts all timeout deadlines from sysclk-based to millisecond-based using `GETMS()`, which is documented in the P2 Knowledge Base as the canonical method for human-scale timing operations and wraps after ~50 days. As a separate but related improvement, the SDSC write-timeout clamp was raised from 1,000 ms to 30,000 ms so the driver can honor full SDSC spec-allowed worst-case timings on cards that legitimately need them.

Validated by: SDHC regression suites continue to pass at all tested sysclks; @macca's 1GB SanDisk SU01G SDSC card now mounts and operates at sysclk=250 MHz where v1.5.2 silently failed.

### Bug Fixes

- **Timeout calculation overflow (12 sites).** Every `GETCT()`-based timeout deadline in the driver has been converted to a `GETMS()`-based deadline. Sites affected: ACMD41 init loop, `cmd()` R1 wait, `readSector` token poll, `waitDataToken`, `waitDataResponse`, `waitBusyComplete`, `sendStopTransmission`, `sendCmd13Transaction`, `readDataRegister` (R1 + token), `readSectorSlow`, and `do_erase_block`. Each conversion is mechanical: the deadline expression changes units from sysclks to milliseconds; the comparison stays a signed-difference check. SDHC behavior is unchanged because SDHC's smaller timeouts never overflowed.
- **SDSC write-timeout clamp raised.** Previous clamp at 1,000 ms was incidentally protecting against the overflow bug at low sysclks; raising it without the math fix would have made the bug worse. With the math fix in place, the clamp is raised to 30,000 ms, which is at or above the worst-case write timeout the SDSC spec allows. SDSC read-timeout clamp also added (5,000 ms max) for safety against pathological CSD values.
- **`debugEraseBlock` now uses GETMS-based deadline** following the same pattern as the other timeout sites.

### Field Reports

The bug was identified by @macca through careful debugging of a 1GB SanDisk SU01G SDSC card. He observed that mount succeeded at the driver's slow init speed (400 kHz) but failed after the driver's post-init speed bump to 25 MHz, traced the failure to the timeout calculation, and confirmed the fix by replacing the GETCT-based math with GETMS-based math. Many thanks for the detective work.

## [1.5.2] - 2026-05-05

**SPI phase-margin improvements (write path); card-aware test infrastructure.**

This release completes the phase-margin work begun in v1.5.1 by applying the analogous improvement to the bulk-write streamer path, and adds the test infrastructure to characterize marginal cards in a single diagnostic session. The write-path improvement was deferred from v1.5.1 pending field verification of the read-path fix; that verification is now complete and the write-path change ships here. The release also adds an `eraseBlockSectors()` getter to the production API and a card-aware test framework that prevents tests from accidentally measuring card-physics issues (erase-block stress, slow-card timeouts) when they intended to measure driver behavior.

Validated by: 4-card frequency-sweep across 200-350 MHz (originally-failing cards from the v1.5.1 read-path validation set) showing no regression vs v1.5.1 baseline.

### Bug Fixes

- **Bulk-write clock alignment improvement.** The explicit `WAITX align_delay` instruction in the bulk-write streamer block (`writeSector` and `writeSectors`) is removed. The earlier SCK reset sequence and smart-pin start latency together produce the correct alignment without an explicit wait — the streamer's first NCO output naturally settles before the first SCK edge in all observed conditions. Mirror change applied to both single-block (CMD24) and multi-block (CMD25) write paths.
- **Register reads and debug erase-block dispatch correctly in `SD_INCLUDE_ALL` builds.** The debug erase-block command shared an opcode with `readCID`, shadowing one dispatch path when `SD_INCLUDE_DEBUG` and `SD_INCLUDE_REGISTERS` were both enabled; the debug command was reassigned.

### New Features

- **`eraseBlockSectors()`**: production getter returning the card's reported erase block size in sectors (from CSD `SECTOR_SIZE` field). Useful for application-level write-batching and log-rotation strategies that align with flash erase boundaries. Typical values: 32 sectors (SDSC) or 128 sectors (SDHC/SDXC).

### Diagnostic API (gated by `SD_INCLUDE_DEBUG`, NOT FOR PRODUCTION USE)

- **`debugEraseBlock(start_sector)`**: erase one erase-block-sized region via CMD32/CMD33/CMD38 sequence. For diagnostic tools that need to distinguish recoverable card flash from failing card flash. Production code must not call this — the SD spec discourages explicit erase for normal block writes (the controller handles erase internally on RMW), and misuse risks filesystem corruption.

### Tests

- **Card-aware test helpers in `isp_rt_utilities.spin2`**: `cacheCardProfile()`, `safeTestRegionStart()`, `nonAdjacentSectors()`, `blockAlignedRange()`, `cardAdjustedTimeoutMs()`, `profileReport()`. Tests can now compute sector layouts from the card's actual erase-block size, avoiding accidental flash-stress measurements when a test was meant to measure driver behavior.
- **New `diagnostic-tests/SD_macca_diagnostic.spin2`**: single-binary card characterization with decision-tree branching. Phase A disambiguates between streamer-side and card-side failures via streamer-vs-slow-path comparison. Subsequent phases run conditionally based on Phase A's outcome: phase-tuning matrix (Phase B, 10 cells), SPI-speed sweep (Phase C1, 7 cells), sysclk sweep at proposed derate (Phase C2, 6 cells), or card-side diagnostics including CMD13 polling, sector-wear pattern, and erase-recover cycle (Phase D). All sector layouts and timeouts are computed from the card's CSD via the new `cacheCardProfile()` helper.
- **`diagnostic-tests/SD_frequency_characterize.spin2`**: multi-block sector count bumped from 8 to 32, structured ramp pattern replaced with deterministic xorshift32 (high-entropy bytes not maskable by 1-bit-shift framing errors), single-block (CMD24) leg added alongside the existing multi-block (CMD25) leg so both write streamer paths are exercised at every cell.

### Documentation

- `DOCs/cards/sandisk-su01g-1gb.md`: full register decode and test results for the SanDisk SU01G 1GB SDSC (the only SDSC card in the catalog).
- `DOCs/cards/CARD-CATALOG.md`: new speed rating "E" (SDSC class, recommend ≤ 12.5 MHz) plus catalog entry for the SU01G.
- `DOCs/User-Reports/2026-05-05-macca-v151-test-results.md`: @macca's v1.5.1 test results showing streamer-specific failure mode on his SDSC card.
- `DOCs/Plans/2026-05-05-macca-diagnostic-design.md`: design doc for the macca diagnostic test, including the principle that tests should be card-aware by default.

## [1.5.1] - 2026-05-05

**SPI phase-margin improvements (read path) for marginal cards.**

This release addresses driver behavior on cards with tight timing margins, particularly older or slower SD cards that may have shown intermittent failures at certain system clock frequencies. The read path now adapts its MISO sampling strategy to the system-clock-to-SCK ratio, and a clock-alignment bug in the bulk-read sequence is corrected. The write path's analogous improvement is held for a follow-up release after field validation. A new diagnostic API (gated behind `SD_INCLUDE_DEBUG`) is provided for tooling that needs to characterize marginal cards.

Validated by: 25/25 regression suites at sysclk=350 MHz; 51/51 freq-sweep cells across 200-350 MHz in three modes (sysclk isolation, runtime clkset+remount, and runtime clkset with diagnostic clock-state refresh).

### Bug Fixes

- SPI clock pins are now wired up for any pin layout, not just the default P2 Edge layout (the routing is computed from the actual pin assignments).
- `mount()` and `initCardOnly()` now propagate a specific error code when the worker cog fails to start, instead of returning a generic error.
- **Bulk-read clock alignment fix at low system clocks.** On certain system-clock frequencies, the first SCK pulse of a bulk sector read could arrive a full half-period later than intended, causing the streamer to begin sampling MISO before the card had started clocking out data. The driver now arranges its setup so the first SCK pulse always lands on schedule regardless of system clock. Bulk writes are unchanged in this release pending field verification — they will be addressed in a follow-up after the read-side fix is validated.
- **SD-card init-sequence hygiene.** Reordered one step in card initialization so the MISO pin's smart-pin state is reset before its mode is configured. No observable behavior change on a first mount; eliminates a subtle mis-order that could surface only on re-mount paths.

### New Features

- `E_BAD_PIN_CONFIG` (-9): mount fails early when SCK is more than ±3 pins from MOSI or MISO.
- **Adaptive MISO sampling for slower system clocks.** The driver now varies how it samples MISO based on the system-clock-to-SCK ratio. At higher system clocks (with a wide SCK bit cell) it samples on the SCK edge for best fast-card behavior; at lower system clocks (where the bit cell is narrow) it samples slightly before the edge for more margin against slower or older cards. This is fully internal to the driver — no application changes required, and existing applications get the new behavior automatically. Default behavior at high system clocks is byte-identical to prior releases.
- **Tunable internal alignment for bulk transfers.** The streamer's first-sample alignment for 512-byte sector reads is now controlled by an internal offset (default 0, preserving prior behavior). The default may be revised to a non-zero value in a future release once field measurements identify the optimum across cards. Production applications do not tune this directly; the right value is baked into the driver.

### Diagnostic API (gated by `SD_INCLUDE_DEBUG`, NOT FOR PRODUCTION USE)

The following methods are exposed only when the consumer adds `#pragma exportdef SD_INCLUDE_DEBUG` (or `SD_INCLUDE_ALL`). They exist to support diagnostic tooling that probes the driver's phase-margin tuning when investigating cards that misbehave. Production applications must NOT call them — the production driver picks the right values internally. These methods are subject to change without notice as the production tuning logic evolves.

- **`debugSetSampleMode(mode)`**: override how MISO is sampled (auto, before-edge, or on-edge).
- **`debugSetPreEdgeThreshold(hp_thresh)`**: change the system-clock-to-SCK ratio at which auto-mode switches between sampling strategies.
- **`debugGetEffectiveSampleMode()`**: read back which sampling mode is currently in effect.
- **`debugGetCurrentHp()`**: read back the current SPI half-period (in system clocks).
- **`debugSetAlignDelayOffset(offset)`**: shift the streamer's first-sample alignment for bulk transfers by a signed number of system clocks.
- **`debugGetEffectiveAlignDelay()`**: read back the bulk-transfer alignment value the driver will use next.
- **`debugOnClockChange()`**: refresh the driver's clock-dependent state after the application has changed the system clock at runtime, without forcing a full card re-initialization. Production guidance for runtime clock changes remains: `unmount()`, then `clkset()`, then `mount()` again. This method is provided only so diagnostic tools can isolate host-side runtime timing as a test variable.

### Tests

- Pin offset validation tests in mount suite
- New `diagnostic-tests/SD_phase_sweep_test.spin2`: 2 × 12 grid sweep (sample mode × align_delay offset) per compile-time sysclk, with §4.5 margin-summary post-processing identifying largest contiguous passing-band per mode plus three falsification triggers (no band / multiple plateaus / band center outside predicted [+3, +9]).
- `diagnostic-tests/SD_frequency_characterize.spin2` Mode C now calls `debugOnClockChange()` after each `clkset()`, isolating host-side runtime timing from card-init state.

### Documentation

- `DOCs/Plans/PLAN-SPI-PHASE-MARGIN-IMPROVEMENT.md`: full sprint plan (4 phases + 4 side-fixes + auxiliary track) with KB-grounded sweep prediction model.
- `DOCs/Analysis/2026-05-04-spi-clock-divisor-margin-table.md`: foundational analysis (divisor table, sample-point deviation, knob inventory, before/after correction tables).
- `DOCs/Analysis/2026-05-04-spi-pin-setup-order-audit.md`: per-site pin-setup ordering audit against P2KB invariants.
- `DOCs/User-Reports/2026-05-04-macca-1GB-card-clock-sensitivity.md`: end-user reports + KB-verified analysis.
- `DOCs/User-Reports/2026-05-04-evanh-streamer-stability-feedback.md`: community feedback (verified against `p2kbPasm2Wrfast`, `p2kbArchSmartPin00101TransitionOutput`, `p2kbArchIoPinTiming`).

## [1.5.0] - 2026-04-02

**Stale directory cluster fix, new API, feature flag reorganization.**

### Bug Fixes

- `newDirectory()`: New directory cluster zeroed before use on recycled clusters

### New Features

- `sectorsPerCluster()`: Public getter for filesystem cluster size
- `SD_INCLUDE_ASYNC` and `SD_INCLUDE_DEFRAG`: application-level feature flags included by `SD_INCLUDE_ALL`

### Tests

- Stale cluster regression test: 20-file directory in recycled cluster with non-zero fill data
- Disk-full write test dynamically adapts to cluster size via `sectorsPerCluster()`
- 25 suites, 465 tests, all passing on hardware

## [1.4.2] - 2026-03-26

**Audit fix, allocator wrap-around fix, theory doc updated.**

### Bug Fixes

- Audit: Volume label scan searches all root directory entries (not just offset 0)
- `allocateCluster()`: Next-fit scan wraps correctly when `test_max_clusters` limit is active

### Improvements

- Theory of Operations: New sections for cluster allocation, auto-flush, defragmentation, async I/O
- Theory of Operations: Updated feature flags, command opcodes, error codes, and API tables
- Demo shell: Defrag commands enabled via `SD_INCLUDE_DEFRAG`

### Tests

- 25 suites, 464 tests, all passing on hardware

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

[Unreleased]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.6.0...HEAD
[1.6.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.5.3...v1.6.0
[1.5.3]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.4.2...v1.5.0
[1.4.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.4.0...v1.4.1
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
