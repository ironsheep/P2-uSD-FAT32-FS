# P2-uSD-Study Roadmap

Project roadmap for SD card driver development and testing.

---

## Driver Architecture

The project has a **single unified driver**: `src/micro_sd_fat32_fs.spin2`

This driver includes all features from the original development phases:
- Smart pin SPI with hardware-accelerated CRC-16
- Streamer DMA for 512-byte sector transfers
- Multi-sector operations (CMD18/CMD25)
- Handle-based multi-file API (up to 4 simultaneous files)
- Worker cog with hardware lock serialization
- Per-cog current working directory
- Directory handle enumeration
- Conditional compilation (`SD_MINIMAL` for smaller builds)

---

## Completed Work

### Phase 0: Foundation
- [x] Download and study OB4269 FAT32 driver
- [x] Create technical reference documentation
- [x] Analyze FAT32 spec compliance
- [x] Document cross-OS portability issues
- [x] Create test card content structure
- [x] Add volumeLabel() method to driver

### Driver Fixes
- [x] Fix 1: FAT mirroring in deleteFile()
- [x] Fix 2: Preserve high 4 bits when freeing clusters
- [x] Fix 3: FSInfo sector support
- [x] Fix 4: Add unmount() method
- [x] Fix 5: Add sync() method

### Card Characterization
- [x] Create card catalog system
- [x] Characterize 6 SD cards with CID data
- [x] Document PNY card SPI timing issues
- [x] Create performance benchmark suite

### Phase 1: Smart Pin SPI (2026-01-29)
- [x] initSPIPins() - Configure P_TRANSITION, P_SYNC_TX, P_SYNC_RX
- [x] setSPISpeed() - Sysclk-independent frequency control
- [x] sp_transfer_8() - Smart pin byte transfer
- [x] Streamer DMA for 512-byte sector reads/writes

### Phase 2: Adaptive Timing (2026-01-29)
- [x] CID manufacturer identification (PNY, SanDisk, Samsung)
- [x] CSD TRAN_SPEED parsing for max speed
- [x] CSD timeout extraction (TAAC, NSAC, R2W_FACTOR)
- [x] Brand-specific speed limiting

### Phase 3: Multi-Sector Operations (2026-01-29)
- [x] readSectors() - CMD18 multi-block read
- [x] writeSectors() - CMD25 multi-block write
- [x] File API integration (do_read/do_write optimization)
- [x] Performance verified: ~4x speedup over single-sector

### Phase 4: Format Utility (2026-01-28)
- [x] FAT32 parameter calculations from card capacity
- [x] Write MBR, VBR, FSInfo, backup boot sector
- [x] Initialize FAT tables and root directory
- [x] FAT32 audit tool for read-only validation

### Phase 5: Multi-File Handle API (2026-01-30)
- [x] Handle table for up to 4 simultaneous file/directory handles
- [x] Single-writer policy enforcement
- [x] Per-handle independent file positions
- [x] Singleton architecture with DAT-based shared state
- [x] Worker cog pattern for serialized SPI access

### Phase 6: Driver Consolidation (2026-02-04)
- [x] Merged all driver variants into single `micro_sd_fat32_fs.spin2`
- [x] Single `regression-tests/` directory for all tests
- [x] Conditional compilation: `SD_MINIMAL`, `SD_INCLUDE_RAW`, `SD_INCLUDE_REGISTERS`, `SD_INCLUDE_SPEED`
- [x] Feature matrix documented for minimal vs full builds

### Phase 7: Per-Cog CWD & Directory Handles (2026-02-07)
- [x] Per-cog current working directory (`cog_dir_sec[8]`)
- [x] `openDirectory()`, `readDirectoryHandle()`, `closeDirectoryHandle()` API
- [x] Directory handles share existing unified handle pool (no new arrays)
- [x] Handle type guards (file ops reject directory handles and vice versa)
- [x] searchDirectory() refactored to use local variable, no global side effects

### Phase 8: FSCK Utility (2026-02-05)
- [x] 4-pass filesystem check and repair (`SD_FAT32_fsck.spin2`)
- [x] Pass 1: Structural validation (MBR, VBR, FSInfo, FAT headers)
- [x] Pass 2: Directory scan with cross-reference bitmap
- [x] Pass 3: Unreferenced cluster detection and free
- [x] Pass 4: FAT sync (FAT2 = FAT1) and free count recalculation
- [x] 256KB cluster bitmap supports cards up to 64GB

### Phase 9: Demo Shell (2026-02-07)
- [x] Interactive terminal shell with command parser
- [x] Navigation: mount, dir, cd, pwd, mkdir, rmdir
- [x] File ops: type, hexdump, copy, rename, delete, touch
- [x] Diagnostics: audit, fsck, benchmark
- [x] Card info: stats, card, version
- [x] Handle-based directory enumeration

### Phase 10: Bug Fixes & Error Handling (2026-02-07)
- [x] Pre-mount operations now return `E_NOT_MOUNTED` (was returning stale 0)
- [x] `changeDirectory()` correctly rejects files (returns `E_NOT_A_DIR`)
- [x] Regression test coverage: 263+ tests across 11 core test suites

---

## Current Status

### Driver Certification: PASS (263+ tests, verified 2026-02-24)

| Test Suite | Pass | Total |
|------------|------|-------|
| Mount | 21 | 21 |
| File Ops | 22 | 22 |
| Read/Write | 38 | 38 |
| Directory | 28 | 28 |
| Seek | 37 | 37 |
| Multicog | 14 | 14 |
| Multihandle | 19 | 19 |
| Multiblock | 6 | 6 |
| Raw Sector | 14 | 14 |
| Format | 46 | 46 |
| Subdirectory Ops | 18 | 18 |

---

## Upcoming Work

### Exhaustive Error & Exception Testing
**Status**: Planned (see `TEST-COVERAGE-IMPROVEMENT-PLAN.md`)

Expand regression test coverage for error paths and edge cases:

- [ ] Systematic invalid handle testing (all operations)
- [ ] Disk full conditions
- [ ] Boundary conditions (0-byte files, exact sector sizes, deep nesting)
- [ ] CRC error injection via test hooks
- [ ] Recovery scenarios after errors
- [ ] Directory handle error paths

### Documentation & Release Preparation
**Status**: In Progress

- [x] README.md with API overview and examples
- [x] Driver Tutorial with practical examples
- [x] Regression Testing documentation
- [x] Card Catalog with performance data
- [x] Utilities Guide
- [ ] Error Code Reference: All E_* codes with descriptions
- [ ] CHANGELOG.md: Version history
- [ ] OBEX submission preparation

---

## Future Work (Post-Release)

### Advanced Features
- [ ] Long filename (LFN) support
- [ ] Read-ahead caching
- [ ] Write-back caching
- [ ] High-Speed mode (50 MHz via CMD6)

---

## Document Map

### Planning
| Document | Purpose |
|----------|---------|
| `ROADMAP.md` | High-level project timeline (this file) |
| `TEST-COVERAGE-IMPROVEMENT-PLAN.md` | Error/exception test coverage expansion |

### Project Documentation (in `DOCs/`)
| Document | Purpose |
|----------|---------|
| `SD-CARD-DRIVER-TUTORIAL.md` | Complete driver tutorial with examples |
| `REGRESSION-TESTING.md` | Test infrastructure and validation |
| `CARD-CATALOG.md` | SD card compatibility data |
| `UTILITIES.md` | Standalone utility programs |
| `Utils/` | Theory-of-operations for each utility |

---

## Milestones

### Completed
| Milestone | Date | Status |
|-----------|------|--------|
| Baseline documented | 2026-01-21 | Done |
| Phase 1 (Smart Pin SPI) | 2026-01-29 | Done |
| Phase 2 (Adaptive Timing) | 2026-01-29 | Done |
| Phase 3 (Multi-Sector) | 2026-01-29 | Done |
| Phase 4 (Format Utility) | 2026-01-28 | Done |
| Phase 5 (Multi-Handle API) | 2026-01-30 | Done |
| Phase 6 (Driver Consolidation) | 2026-02-04 | Done |
| Phase 7 (Per-Cog CWD + Dir Handles) | 2026-02-07 | Done |
| Phase 8 (FSCK Utility) | 2026-02-05 | Done |
| Phase 9 (Demo Shell) | 2026-02-07 | Done |
| Phase 10 (Bug Fixes) | 2026-02-07 | Done |

### Upcoming
| Milestone | Target | Status |
|-----------|--------|--------|
| Error/Exception Testing | TBD | Planned |
| Documentation & Release | TBD | In Progress |
| **Public Release** | TBD | Planned |

---

*Last updated: 2026-02-07*
