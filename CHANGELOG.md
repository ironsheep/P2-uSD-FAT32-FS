# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2026-08-13

Data-losing file operations are fixed, failures the driver detected but discarded are now reported, and files a PC wrote behave correctly.

### New Features

- `handleError(handle)` reports why the last `readHandle()` or `writeHandle()` on a handle came up short. Both return a byte count, and a partial count is positive, so the read loop the tutorial shows ends the same way at end of file and on a card failure part-way through a file.
- The write path reports `E_NO_CONTIGUOUS_SPACE` when a pre-allocated contiguous reservation runs out, and `E_BAD_CHAIN` when a cluster chain walk lands in the metadata region. Both were previously reported as a zero-byte write.
- `lastFlushError()` and `clearFlushError()` report failures of the automatic idle flush. That flush is started by the worker cog, so a failure had no caller to return to: the data did not reach the card and every later call still reported success.
- `SD_INCLUDE_TEST_HOOKS` builds in fault injection — `setTestFailSector()`, `setTestFailWriteAfter()`, `getTestWriteCallCount()`, `setTestMaxClusters()`, `clearTestErrors()`. Enabled by `SD_INCLUDE_ALL`, and deliberately not by `SD_INCLUDE_DEBUG`.
- `debugSetTxAlignDelay()` and `debugGetTxAlignDelay()` tune the padding between the write path's clock setup and its data fetch, for measuring write phase margin on an unfamiliar board or card socket. Diagnostic only, gated behind `SD_INCLUDE_DEBUG`; the shipped default is centered on measured margin and needs no adjustment. Documented in `DOCs/SPI-PHASE-MARGIN-API.md`.
- `DOCs/ERROR-HANDLING-GUIDE.md` covers detecting and responding to every error the driver reports. `DOCs/MIGRATION-GUIDE-v1.7.0.md` covers moving from v1.6.x.

### Bug Fixes

- Renaming a file to a full 12-character 8.3 name (`DATALOG1.TXT`) keeps the file usable. The last character of the extension was written over the directory entry's attribute byte, which set the directory and system bits; the file then could not be opened and no longer appeared in listings. Names of 11 characters or fewer were unaffected.
- File operations no longer match the volume-label entry. `rename()` on a dot-less label's name silently relabelled the volume; creating that name failed `E_FILE_EXISTS`, and opening it returned an empty file.
- Seeking a write handle to another sector, and reading through a handle that has unwritten data, both flush that data first. Either one previously discarded it, and after a seek every later flush from that handle was addressed to a sector that does not exist.
- An unreadable directory is no longer indistinguishable from a name that is not there, so a create no longer writes a second entry for a file that already exists.
- A metadata write that fails part-way no longer leaves the filesystem in a state that reports success. Cluster allocation, delete, directory creation, rename and move each check every write and leave the recoverable outcome on the card.
- Appending to an empty file created by a PC works; the first write previously failed `E_BAD_CHAIN` and the file could never be appended.
- `createFileContiguous()` on a name that already exists leaves free space unchanged; the rejected call previously stranded its pre-allocated clusters until an fsck.
- `changeDirectory()` onto an empty file returns `E_NOT_A_DIR` instead of succeeding and silently changing to the root directory.
- FAT entries carrying the reserved high bits — legal on volumes written by other systems — no longer send cluster-chain walks and free-space counts to wrong results.
- Multi-block writes and block erases invalidate the cached copies of the sectors they change, as single-sector writes already did. A later read could return the pre-write contents.
- A read that fails part-way no longer leaves a valid cache entry over the incomplete data, and reading past the end of a cluster chain no longer leaves the previous sector's identity attached to a zero-filled buffer.
- `unmount()` clears the cached sectors and cancels the background flush timer. A bare `unmount()` was followed about 200 ms later by the worker reading and writing FSInfo on a card the caller had finished with.
- Closing a file whose final flush failed no longer records the new size and timestamp in the directory. The entry advertised bytes that never reached the card.
- `mount()` on a corrupted card whose boot record claims zero sectors per cluster fails with `E_NOT_FAT32` instead of hanging the worker cog.
- The write path no longer issues a hub fetch inside the window where the clock pin is being set up. Data landing in that window could end up one bit out of phase with the clock, so the card stored a shifted sector and reported success — the acknowledgement it returns proves packet framing, not payload. Reads were never affected. Observed once during development and not in any released build; see the upgrade note below.
- `error()` describes the operation that just completed rather than the last failure since boot. Every method that issues a command records its outcome on both exit paths; the pure accessors are exempt so a diagnostic call cannot erase the error being diagnosed.
- `sync()` reports failure, and keeps the pending directory entry so a later sync can still write it. It previously discarded the entry whether or not it reached the card.
- `freeSpace()` returns 0 with an error rather than the partial count from an interrupted FAT scan.
- `stop()` returns the status of its final unmount. It halts the worker cog immediately afterward, so nothing else could report it.
- A worker-cog stack-guard violation reaches `error()` instead of only the debug channel, which the driver ships with disabled.
- `getResult()` and `cancelAsync()` refuse a cog that did not start the operation. They release the API lock as their last act, so such a call released a lock the caller never held.
- The card registers, high-speed negotiation and CMD6 paths report the specific failure instead of a single false. A card that lacks high-speed support is reported as lacking it, not as a failed query.
- A create that grows a directory reports the actual failure; `E_IO_ERROR` from a failed FAT write is no longer reported as `E_DISK_FULL`.
- A blocking call from the cog that owns an in-flight async operation returns `E_ASYNC_BUSY` — from every API, info getters included — instead of deadlocking; a losing concurrent `start*()` gets the same answer promptly instead of blocking for the winner's operation.
- `getResult()` and `cancelAsync()` report `E_STACK_OVERFLOW` when the worker's stack guard was violated during the operation, as blocking calls already do.
- `setDate()` rejects every out-of-range date or time field with `E_INVALID_PARAM`; negative values were previously accepted.
- `attemptHighSpeed()` verifies the 50 MHz switch by re-reading a sector captured at the known-good speed and comparing. It previously wrote to the card at the unverified speed and compared the result against itself, so the check could not detect the failure it existed to catch. Nothing is written at an unverified speed.
- `SD_FAT32_fsck` recovers directory entries stranded past a spurious end-of-directory marker, rewriting the marker as a deleted-entry tombstone so a conforming scan reaches them. It previously freed their cluster chains and left the entries in place pointing at them.
- `SD_FAT32_audit` and `SD_FAT32_fsck` check every sector read. An unchecked read left the previous sector in the buffer, which was then validated as directory entries or FAT data; a run that cannot read the media now says so and never reports `CLEAN`.
- `SD_card_identify` names Gigastone OEM cards (manufacturer ID `$12`) instead of reporting `Unknown`. `SD_card_characterize` already named them.
- The read/write example no longer null-terminates its buffer at a negative index when a read fails. The demo shell reports a read that failed part-way through `type` and `hexdump` instead of printing a byte count as if the file were complete, reports a `copy` whose writes were refused or short instead of reporting the source size as copied, and distinguishes a card with no free space from a free-space query that failed.

### Upgrade / recovery note

The instruction ordering that allowed this was present in every release from v0.9.3 through v1.6.1. **Whether any released build could actually produce the fault is not established, and the evidence suggests not:** no user has reported it, and it never occurred across four months of certification — 27 regression binaries per release, each with a different memory layout, all doing byte-level content verification. It was observed once, on one development commit. A one-bit shift is also not subtle; it makes text unreadable and binary structures obviously malformed, so an affected user would have known.

- `SD_FAT32_audit` and `SD_FAT32_fsck` cannot detect it, and a CLEAN result is not evidence either way — the filesystem structures stay intact and only sector *contents* would be wrong. Same shape as v1.6.0's mid-sector append defect.
- Opening a file and looking at it settles the question for most data. Rewriting an affected file with a v1.7.0 build is sufficient; no reformat is needed.
- Reads were never affected, so a card written by another system and only read by this driver was never at risk.

`DOCs/MIGRATION-GUIDE-v1.7.0.md` §0 covers this in full, including why the driver's own two checks could not catch it.

### Breaking Changes

- **BREAKING**: `eofHandle()` and `isFileContiguous()` return a boolean only. They previously returned `TRUE`, `FALSE`, or a negative error code, and `TRUE` is -1 in Spin2 while `E_TIMEOUT` is also -1 — there was no correct way to call either one. `eofHandle()` reports `TRUE` when the query fails, `isFileContiguous()` reports `FALSE`, and `error()` distinguishes.
- **BREAKING**: `readHandle()` and `writeHandle()` return their error code when nothing at all was transferred, so a return of 0 from `readHandle()` now means end of file and nothing else. A read that failed on its first sector previously returned 0, and a file on a failing card was processed as a complete file. A failure part-way through still returns the partial count. A read loop that stops on `n =< 0` or `n > 0` needs no change; one that stops only on `n == 0` will not terminate on a persistent failure.
- **BREAKING**: `changeDirectory()` on a name with no entry returns `E_FILE_NOT_FOUND` (-40). `E_NOT_A_DIR` (-43) now means the name exists and is not a directory — the two conditions previously shared it. Code branching on `E_NOT_A_DIR` to mean "no such directory" must change. The volume label, invisible to file operations everywhere, reports `E_FILE_NOT_FOUND` rather than leaking its existence through the error code.
- **BREAKING**: `unmount()` on a card with invalid FSInfo signatures reports the new `E_BAD_FSINFO` (-24) rather than `E_IO_ERROR`.
- New error constants: `E_BAD_FSINFO` (-24), `E_BAD_CHAIN` (-25), `E_STACK_OVERFLOW` (-26), `E_DIR_NOT_EMPTY` (-44), `E_FILE_OPEN` (-47), `E_NO_COG` (-65). `E_NO_COG` replaces `E_NO_LOCK` when `start()` cannot get a cog. `E_FILE_NOT_OPEN` (-45) is documented as reserved; no code path produces it.
- **BREAKING**: `deleteFile()` on a directory that still contains entries returns the new `E_DIR_NOT_EMPTY` (-44) and deletes nothing. It previously removed the directory and freed only the directory's own cluster chain, leaving every file inside it allocated and unreachable — space that stayed lost until the card was reformatted. Empty a directory before removing it, children before parents. There is no recursive delete.
- **BREAKING**: `deleteFile()` on a file that any handle still has open returns the new `E_FILE_OPEN` (-47) and deletes nothing. The delete previously succeeded, after which the background flush could write that handle's buffered data into a cluster that had been freed and given to another file. Close the handle first.
- `stop()` and `closeDirectoryHandle()` return a status where they previously returned nothing. Existing calls compile and behave as before.

## [1.6.1] - 2026-07-27

Utility output and build instructions, and one debug method renamed to match what it does.

### Bug Fixes

- `SD_format_card`, `SD_FAT32_audit` and `SD_FAT32_fsck` build with `pnut-ts -d -I ..`, the command their documentation gives. The other three utilities were unaffected.
- `SD_card_identify` and `SD_card_characterize` print the manufacturing date as a date — `2021/09`, `2021-09` — in a fixed-width field that sorts positionally.
- `SD_FAT32_audit` reports each finding as `needs repair:` and states that the card was not modified. `SD_FAT32_fsck` reports the same findings as `repaired:`.
- `SD_format_card` prints its closing success or failure line in full.
- Error messages in the audit, format and benchmark utilities name the operation that failed.

### Breaking Changes

- **BREAKING**: `debugClearRootDir()` is renamed `debugZeroRootSector()` (`SD_INCLUDE_DEBUG`). It zeroes the first root-directory sector and frees no cluster chains, so entries in later sectors become unreachable and their clusters stay allocated. Treat the card as scratch afterwards; `SD_format_card` returns it to a clean state.

### Known Issues

- Maxwell NCard 4GB: `formatCard()` does not produce a mountable filesystem on this card. Other cards in the catalog format normally.

## [1.6.0] - 2026-07-25

**Write-path corruption fixes; broader card compatibility; write-error reliability.**

Two data-corruption defects are fixed, both in **rewriting an existing file**. Files created once and written front to back — including data loggers that only append sector-aligned records — were never affected.

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

**Timeout handling on SDSC (≤2 GB) cards.**

SDSC cards could fail every read and write at some system clocks: `mount()` succeeded at the slow init speed, then all traffic afterwards reported a timeout. SDHC and SDXC cards were unaffected.

### Bug Fixes

- **SDSC cards no longer report spurious timeouts.** The condition depended on system clock — a card that failed completely at one `_CLKFREQ` could work at another.
- **SDSC cards that legitimately need long write times are honored.** The driver now allows up to 30 seconds for a write where it previously gave up after 1 second, and caps reads at 5 seconds against cards reporting implausible values.

### Field Reports

Found and diagnosed by @macca on a 1GB SanDisk SU01G, including a confirmed fix. Many thanks.

## [1.5.2] - 2026-05-06

**Write-path timing margin; erase-block size getter.**

### Bug Fixes

- **Bulk writes have more clock-timing margin on cards with tight timing**, completing the read-path work from v1.5.1. Both single-block and multi-block writes are covered.
- **`readCID()` works in `SD_INCLUDE_ALL` builds.** Enabling the debug and register features together could shadow it.

### New Features

- **`eraseBlockSectors()`**: the card's erase block size in sectors. Useful for aligning write batching or log rotation to flash erase boundaries — typically 32 (SDSC) or 128 (SDHC/SDXC).

### Diagnostic API (gated by `SD_INCLUDE_DEBUG`, NOT FOR PRODUCTION USE)

- **`debugEraseBlock(start_sector)`**: erase one erase-block-sized region. For tools distinguishing recoverable card flash from failing flash. Production code must not call this — the card erases internally on normal writes, and misuse risks filesystem corruption.

### Documentation

- Card catalog: SanDisk SU01G 1GB SDSC entry, and a new "E" speed rating (SDSC class, ≤12.5 MHz recommended).

## [1.5.1] - 2026-05-05

**Read-path timing margin for marginal cards.**

Older and slower cards could fail intermittently at certain system clocks. No application changes are needed to get the improved behavior; at high system clocks, behavior is byte-identical to prior releases.

### Bug Fixes

- **Reads are more reliable on slower and older cards.** The driver now adapts how it samples data to the system-clock-to-SCK ratio, giving more margin where the bit cell is narrow.
- **Bulk reads start on schedule at low system clocks.** The first clock pulse could arrive late, so the driver began sampling before the card was driving data.
- **SPI works with any pin layout**, not only the default P2 Edge arrangement.
- **`mount()` and `initCardOnly()` report a specific error** when the worker cog fails to start, instead of a generic one.

### New Features

- **`E_BAD_PIN_CONFIG` (-9)**: `mount()` fails early when SCK is more than ±3 pins from MOSI or MISO.

### Diagnostic API (gated by `SD_INCLUDE_DEBUG`, NOT FOR PRODUCTION USE)

For tooling that characterizes cards that misbehave. Production applications must not call these — the driver picks the right values itself — and they may change without notice: `debugSetSampleMode()`, `debugSetPreEdgeThreshold()`, `debugGetEffectiveSampleMode()`, `debugGetCurrentHp()`, `debugSetAlignDelayOffset()`, `debugGetEffectiveAlignDelay()`, and `debugOnClockChange()` (refresh clock-dependent state after a runtime `clkset()`; production guidance remains `unmount()` → `clkset()` → `mount()`).

## [1.5.0] - 2026-04-02

**Stale directory cluster fix, new API, feature flag reorganization.**

### Bug Fixes

- **`newDirectory()`**: a directory created in a recycled cluster no longer inherits stale data — the cluster is zeroed before use.

### New Features

- **`sectorsPerCluster()`**: public getter for the filesystem's cluster size.
- **`SD_INCLUDE_ASYNC` and `SD_INCLUDE_DEFRAG`**: application-level feature flags, both included by `SD_INCLUDE_ALL`.

## [1.4.2] - 2026-03-26

**Audit fix, allocator wrap-around fix, theory doc updated.**

### Bug Fixes

- Audit: Volume label scan searches all root directory entries (not just offset 0)
- `allocateCluster()`: Next-fit scan wraps correctly when `test_max_clusters` limit is active

### Improvements

- Theory of Operations: New sections for cluster allocation, auto-flush, defragmentation, async I/O
- Theory of Operations: Updated feature flags, command opcodes, error codes, and API tables
- Demo shell: Defrag commands enabled via `SD_INCLUDE_DEFRAG`

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

## [1.3.2] - 2026-03-10

**NCO write alignment fix, selective debug channels, controller-specific code removed.**

### Bug Fixes

- `writeSector()`, `writeSectors()`: Streamer write timing corrected for power-of-2 SPI half-period values (hp=4, hp=8) via NCO frequency adjustment
- Controller-specific SPI speed limiting removed; all cards use reported max speed capped at 25 MHz

### Improvements

- Debug output is selectable by subsystem rather than all-or-nothing. `DEBUG_MASK` replaces `DEBUG_DISABLE` as the single control: 0 for production, or set channel bits to see only the traffic you care about — INIT, MOUNT, FILE, DIR, SECTOR, STATUS, IDENT, HSPEED, API, RECOVER. The driver requires `{Spin2_v46}` or later for channel support.

## [1.3.1] - 2026-03-07

**CMD13 STATUS byte fix, reduced driver footprint, updated memory sizing reference.**

### Bug Fixes

- `checkCardStatus()`: STATUS byte errors now detected correctly (was checking uninitialized return variable instead of R2 response)
- `last_cmd13_status`: Diagnostic field now captures the actual STATUS byte from CMD13

### Improvements

- Driver hub footprint reduced through SPI transaction consolidation

### Documentation

- Memory sizing guide updated with current v1.3.x footprint data across all configurations

## [1.3.0] - 2026-03-07

**R1 response parsing fix, CMD12 tolerance, and CMD23 block-count support.**

### Bug Fixes

- R1 response parsing: skip bytes with bit 7 set per SD spec Section 7.3.2.1 (fixes CMD13 false errors on cards with bus artifacts)
- CMD12 tolerance: multi-block reads recover via CS deassert on cards with aggressive read-ahead pipelines

### New Features

- `cardWarnings()`: Bitmask API for init-time capability discoveries
- CMD23 probing: automatic SET_BLOCK_COUNT detection and use when supported in SPI mode

### Improvements

- `recoverToIdle()`: CS deassert recovery per SD spec Section 7.2.2
- `readSectors()`: CMD23 path with auto-stop verification and fallback to CMD12

## [1.2.9] - 2026-03-06

**Prerelease for v1.3.0.** Diagnostic capture for card status reporting, released for field testing. Everything here also ships in v1.3.0 — use that instead.

## [1.2.1] - 2026-03-05

**Audit severity corrections for conditions that are normal on FAT32 media.**

### Improvements

- Audit: Partition type $0B (FAT32 CHS) accepted as valid alongside $0C (FAT32 LBA)
- Audit: Backup FSInfo mismatch downgraded from error to warning (common on FAT32 media)

## [1.2.0] - 2026-03-03

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

### Documentation

- [Migration Guide](DOCs/MIGRATION-GUIDE-v1.2.0.md) for updating v1.0/v1.1 code to v1.2 error-code patterns
- [Card Presence Detection](DOCs/Reference/CARD-PRESENCE-DETECTION.md) reference with electrical analysis and SD spec research
- [Memory Sizing Guide](DOCs/Reference/MEMORY-SIZING-GUIDE.md) for hub RAM planning
- Theory of Operations expanded: card presence detection, card identification and adaptive timing
- Architecture Decision 13: Card presence detection via P2 internal pull-up

## [1.1.0] - 2026-02-28

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

### Documentation

- External SD header guide with 8-pin header group reference table

## [0.9.2] - 2026-02-10

### Improvements

- Demo shell: Help text formatted for 80x25 terminal

## [0.9.1] - 2026-02-09

**Initial testing release** -- driver, utilities, demo shell, and 263+ regression tests.

## [0.9.0] - 2026-02-09

**Packaging-only tag.** Release workflow and user-facing documentation; no driver code.

[1.7.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.6.1...v1.7.0
[1.6.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.6.0...v1.6.1
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
[1.3.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.2.9...v1.3.0
[1.2.9]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.2.1...v1.2.9
[1.2.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.3...v1.0.0
[0.9.3]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/ironsheep/P2-uSD-FAT32-FS/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/ironsheep/P2-uSD-FAT32-FS/releases/tag/v0.9.0
