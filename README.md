# P2 microSD FAT32 Filesystem

A high-performance FAT32-compliant microSD card filesystem driver for the Parallax Propeller 2 (P2) microcontroller. ([Why FAT32?](#why-fat32))

![Project Status](https://img.shields.io/badge/status-active-brightgreen)
![Platform](https://img.shields.io/badge/platform-Propeller%202-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

This project provides a robust, high-performance SD card driver for the P2 microcontroller with full FAT32 filesystem support. The driver uses P2 smart pins for hardware-accelerated SPI communication and supports multiple simultaneous file handles.

## Features

- **FAT32 Filesystem Support**: Full read/write access to FAT32-formatted SD cards
- **High-Performance SPI**: Smart pin hardware acceleration with streamer DMA
- **Multi-File Handles**: Up to 6 simultaneous file and directory handles (configurable)
- **Cross-OS Compatibility**: Works with cards formatted on Windows, macOS, and Linux
- **SDHC/SDXC Support**: Block-addressed cards tested up to 128GB (reformatted as FAT32)
- **CRC Validation**: Hardware-accelerated CRC-16 on all data transfers
- **Directory Operations**: Create, navigate, and enumerate directories (index-based and handle-based)
- **File Operations**: Create, open, read, write, seek, rename, delete
- **Live Timestamps**: `setDate()`/`getDate()` with 2-second auto-advance for file creation and modification stamps
- **Auto-Flush**: Dirty handles flushed after 200ms idle — protects against card removal data loss
- **Non-Blocking Async I/O**: Optional `startReadHandle()`/`startWriteHandle()` for overlapping computation with SD I/O (`SD_INCLUDE_ASYNC`)
- **Built-in Card Formatter**: Format any SD card as FAT32 directly from the P2 — no PC required
- **Filesystem Repair**: Integrated read-only audit (39 checks) and 4-pass fsck with auto-repair
- **Multi-Cog Safe**: Dedicated worker cog with hardware lock serialization
- **Per-Cog Working Directory**: Each cog maintains its own CWD for safe concurrent navigation
- **Regression Tested**: 452 automated tests across 24 test suites

## Documentation

| Document | Description |
|----------|-------------|
| **[Driver Tutorial](DOCs/SD-CARD-DRIVER-TUTORIAL.md)** | Complete guide with practical examples — start here |
| **[Driver Theory of Operations](DOCs/SD-CARD-DRIVER-THEORY.md)** | Architecture, handle system, SPI engine, and internals |
| **[Card Performance](DOCs/SD-CARD-PERFORMANCE.md)** | SD card selection guide and ranked performance comparisons |
| **[Card Catalog](DOCs/cards/CARD-CATALOG.md)** | All tested cards with register data and throughput |
| **[FAT32 API Concepts](DOCs/Reference/FAT32-API-CONCEPTS-REFERENCE.md)** | FAT32 background for embedded developers |
| **[Utilities Guide](DOCs/SD-CARD-UTILITIES.md)** | Standalone utility programs (format, audit, fsck, benchmark) |
| **[Utility Internals](DOCs/Utils/)** | Theory of operations for each utility |
| **[Regression Testing](src/regression-tests/README.md)** | Test infrastructure, 452 tests across 24 suites |
| **[Example Programs](src/EXAMPLES/README.md)** | Compilable examples: read/write, data logger, directory walk, multi-cog |
| **[Demo Shell](src/DEMO/README.md)** | Full-featured terminal shell with card formatting, filesystem repair, file management, and benchmarking |

## Hardware Requirements

- Parallax Propeller 2 (P2) microcontroller
- P2 Edge Module ([P2-EC](https://www.parallax.com/product/p2-edge-module/) or [P2-EC32MB](https://www.parallax.com/product/p2-edge-module-32mb/))
- microSD Add-on Board ([#64009](https://www.parallax.com/product/micro-sd-card-add-on-board/)) - provides the microSD card slot
- microSD card (SDHC or SDXC — format with the included [format utility](src/UTILS/SD_format_card.spin2) or any OS formatter)

### Default Pin Configuration (P2 Edge)

| Signal | Pin | Description |
|--------|-----|-------------|
| CS (DAT3) | P60 | Chip Select |
| MOSI (CMD) | P59 | Master Out, Slave In |
| MISO (DAT0) | P58 | Master In, Slave Out |
| SCK (CLK) | P61 | Serial Clock |

The microSD add-on board plugs into any P2 8-pin header group. See the [Driver Tutorial](DOCs/SD-CARD-DRIVER-TUTORIAL.md#using-a-different-8-pin-header-group) for pin reassignment and a complete header group reference table.

## Quick Start

```spin2
OBJ
    sd : "micro_sd_fat32_fs"

CON
    SD_CS   = 60
    SD_MOSI = 59
    SD_MISO = 58
    SD_SCK  = 61

PUB main() | handle, buffer[128], bytes_read
    ' Mount the SD card
    if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
        debug("Mount failed!")
        return

    ' Read a file using handle-based API
    handle := sd.openFileRead(@"CONFIG.TXT")
    if handle >= 0
        bytes_read := sd.readHandle(handle, @buffer, 512)
        sd.closeFileHandle(handle)
        debug("Read ", udec(bytes_read), " bytes")

    ' Create and write a file
    handle := sd.createFileNew(@"OUTPUT.TXT")
    if handle >= 0
        sd.writeHandle(handle, @"Hello, P2!", 10)
        sd.closeFileHandle(handle)

    ' Unmount when done
    sd.unmount()
```

For multi-file operations, directory navigation, and the full API reference, see the [Driver Tutorial](DOCs/SD-CARD-DRIVER-TUTORIAL.md).

## Performance

Measured at 350 MHz sysclk with 25 MHz SPI, smart pin hardware acceleration, streamer DMA, and multi-sector commands (CMD18/CMD25):

| Operation | SanDisk Industrial 16GB | Lexar Blue 128GB | Amazon Basics 64GB | Samsung PRO Endurance 128GB |
|-----------|:-:|:-:|:-:|:-:|
| File Read (256KB) | 745 KB/s | **1,444 KB/s** | 1,386 KB/s | 1,419 KB/s |
| File Write (32KB) | 321 KB/s | 616 KB/s | **774 KB/s** | 758 KB/s |
| Raw Multi-sector Read (32KB) | 2,393 KB/s | 2,420 KB/s | 2,425 KB/s | **2,427 KB/s** |
| Raw Multi-sector Write (32KB) | 2,170 KB/s | 2,275 KB/s | 2,305 KB/s | **2,319 KB/s** |
| Mount | 486 ms | 400 ms | 233 ms | 243 ms |

Raw SPI efficiency reaches 80% of theoretical maximum (2,427 / 3,052 KB/s). Multi-sector commands provide 46-69% improvement over single-sector operations. 23 cards tested across 9 manufacturers — see [Card Performance](DOCs/SD-CARD-PERFORMANCE.md) for ranked comparisons and card selection guidance.

> **Sysclk and performance:** Both 350 MHz and 250 MHz sysclk produce the same 25 MHz SPI clock, but higher sysclk reduces Spin2 inter-transfer overhead between SPI bursts, yielding 10-20% better file throughput. For best performance, use `_CLKFREQ = 350_000_000`. See the [Performance Guide](DOCs/SD-CARD-PERFORMANCE.md) for detailed analysis.

## Project Structure

```
P2-uSD-FAT32-FS/
├── src/                        # Driver and application source
│   ├── micro_sd_fat32_fs.spin2     # The SD card driver
│   ├── UTILS/                      # Standalone utility programs
│   │   ├── SD_format_card.spin2           # FAT32 card formatter
│   │   ├── SD_card_identify.spin2         # Two-line card identification
│   │   ├── SD_card_characterize.spin2     # Card register reader (CID/CSD/SCR)
│   │   ├── SD_performance_benchmark.spin2 # Read/write throughput bench
│   │   ├── SD_FAT32_audit.spin2           # Filesystem validator (read-only)
│   │   ├── SD_FAT32_fsck.spin2            # Filesystem check & repair
│   │   ├── isp_format_utility.spin2       # FAT32 format library
│   │   ├── isp_fsck_utility.spin2         # Combined FSCK + Audit library
│   │   └── isp_string_fifo.spin2          # Inter-cog string FIFO
│   ├── EXAMPLES/                    # Compilable example programs
│   │   ├── SD_example_read_write.spin2    # Basic file read/write
│   │   ├── SD_example_data_logger.spin2   # Append-mode logging with sync
│   │   ├── SD_example_directory_walk.spin2 # Directory operations
│   │   └── SD_example_multicog.spin2      # Multi-cog concurrent access
│   └── DEMO/                       # Interactive demo application
│       ├── SD_demo_shell.spin2         # Terminal shell (dir, cd, type, etc.)
│       ├── isp_serial_singleton.spin2  # Serial terminal driver
│       ├── isp_mem_strings.spin2       # String formatting utilities
│       └── isp_stack_check.spin2       # Stack usage diagnostic
│
│   ├── regression-tests/          # Regression test suite (452 tests)
│   │   ├── SD_RT_*_tests.spin2        # 24 test files (mount, file ops, seek, async, etc.)
│   │   ├── isp_rt_utilities.spin2     # Shared test framework
│   │   └── TestCard/                  # Test card setup and validation
│
├── diagnostic-tests/           # Characterization & diagnostic tests
│   ├── SD_card_info_tests.spin2         # Struct-based register access
│   ├── SD_diag_fsck_window_test.spin2   # FSCK windowed bitmap diagnostic
│   ├── SD_freq_sweep_tests.spin2        # SPI frequency sweep (15-25 MHz)
│   └── SD_spi_limit_test.spin2          # Single SPI frequency probe
│
├── tools/                      # Build and test scripts
│   └── run_test.sh                 # Test runner (compile + download + capture)
│
├── DOCs/                       # Documentation
│   ├── SD-CARD-DRIVER-TUTORIAL.md   # Complete guide with examples
│   ├── SD-CARD-DRIVER-THEORY.md     # Architecture and driver internals
│   ├── SD-CARD-PERFORMANCE.md       # Card selection and performance rankings
│   ├── SD-CARD-UTILITIES.md            # Utility program documentation
│   ├── Analysis/                    # Design explorations and studies
│   ├── cards/                       # Per-card data sheets and catalog
│   ├── Decisions/                   # Architecture decision records
│   ├── Plans/                       # Active plans and punch list
│   ├── Reference/                   # Technical references and guides
│   ├── Research/                    # Hardware research and investigations
│   └── Utils/                       # Utility theory of operations
```

## Known Limitations

- **8.3 filenames only** — no long filename (LFN) support
- **SDXC cards need reformatting** — cards >32 GB ship as exFAT; use the included format utility (no PC needed)
- **SPI mode only** — no SD native 4-bit bus mode
- **25 MHz SPI maximum** — CMD6 High Speed mode switch fails on all tested cards

### Card Size Support

The driver's goal is full support for cards up to **2 TB** (the FAT32 and SDXC maximum defined by the Microsoft FAT32 specification and SD Physical Layer Specification). Tested with cards up to **128 GB** across 23 cards from 9 manufacturers.

The FSCK utility provides full cluster-chain validation on cards of any size. For cards exceeding approximately 64 GB, a windowed bitmap approach processes the cluster space in 2M-cluster passes, extending full 4-pass validation (chain integrity, cross-link detection, lost cluster recovery, FAT sync) to any card.

> **Right-size your card.** Larger cards mean larger FAT tables, longer mount times, and longer FSCK scans. Choose the smallest card that comfortably meets your storage needs. For most embedded applications, 8–32 GB provides ample capacity with the best overall performance. See the [Card Performance Guide](DOCs/SD-CARD-PERFORMANCE.md#right-sizing-your-card) for details.

---

## Why FAT32?

*Our storage subsystem uses FAT32 rather than exFAT to avoid the patent and licensing constraints that still apply to exFAT in commercial products. exFAT remains covered by Microsoft intellectual property, and compliant implementations are generally expected to be licensed, which can add cost, legal complexity, and contractual obligations that are disproportionate for many embedded systems. In contrast, the relevant FAT patents (including those covering long filenames) have expired, so a clean-room FAT32 implementation can be shipped royalty-free, making it a safer and more predictable choice from an IP and compliance standpoint.*

*Technically, FAT32 also remains the most broadly compatible filesystem for removable media in the embedded space. It is supported by virtually all major desktop and mobile operating systems, works out of the box with common SD and microSD cards up to 32 GB, and has a relatively small code and RAM footprint -- important advantages on microcontrollers. By standardizing on FAT32, our driver delivers simple integration, excellent cross-platform interoperability, and a clear legal posture, which together make it a practical and low-risk foundation for products that need removable storage without the overhead of exFAT licensing.*

---

## Credits

- **Original Driver Concept**: Chris Gadd (OB4269 from Parallax OBEX)
- **Driver Development**: Stephen M. Moraco, Iron Sheep Productions

## License

MIT License - See [LICENSE](LICENSE) for details.

---

*Part of the Iron Sheep Productions Propeller 2 Projects Collection*
