# P2 microSD FAT32 Filesystem

A high-performance FAT32-compliant microSD card filesystem driver for the Parallax Propeller 2 (P2) microcontroller.

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
- **Multi-Cog Safe**: Dedicated worker cog with hardware lock serialization
- **Per-Cog Working Directory**: Each cog maintains its own CWD for safe concurrent navigation
- **Regression Tested**: 345+ automated tests across 19 test suites

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
| **[Regression Testing](regression-tests/README.md)** | Test infrastructure, 345+ tests across 19 suites |
| **[Demo Shell](src/DEMO/README.md)** | Interactive terminal interface (dir, cd, type, copy, fsck) |

## Hardware Requirements

- Parallax Propeller 2 (P2) microcontroller
- P2 Edge Module ([P2-EC](https://www.parallax.com/product/p2-edge-module/) or [P2-EC32MB](https://www.parallax.com/product/p2-edge-module-32mb/))
- microSD Add-on Board ([#64009](https://www.parallax.com/product/micro-sd-card-add-on-board/)) - provides the microSD card slot
- FAT32-formatted SD card

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

Raw SPI efficiency reaches 80% of theoretical maximum (2,427 / 3,052 KB/s). Multi-sector commands provide 46-69% improvement over single-sector operations. 20 cards tested across 9 manufacturers — see [Card Performance](DOCs/SD-CARD-PERFORMANCE.md) for ranked comparisons and card selection guidance.

## Project Structure

```
P2-uSD-FAT32-FS/
├── src/                        # Driver and application source
│   ├── micro_sd_fat32_fs.spin2     # The SD card driver
│   ├── UTILS/                      # Standalone utility programs
│   │   ├── SD_format_card.spin2           # FAT32 card formatter
│   │   ├── SD_card_characterize.spin2     # Card register reader (CID/CSD/SCR)
│   │   ├── SD_speed_characterize.spin2    # Maximum SPI speed tester
│   │   ├── SD_frequency_characterize.spin2 # Sysclk frequency tester
│   │   ├── SD_FAT32_audit.spin2           # Filesystem validator (read-only)
│   │   ├── SD_FAT32_fsck.spin2            # Filesystem check & repair
│   │   ├── SD_performance_benchmark.spin2 # Read/write throughput bench
│   │   ├── isp_format_utility.spin2       # FAT32 format library
│   │   ├── isp_fsck_utility.spin2         # Combined FSCK + Audit library
│   │   └── isp_string_fifo.spin2          # Inter-cog string FIFO
│   └── DEMO/                       # Interactive demo application
│       ├── SD_demo_shell.spin2         # Terminal shell (dir, cd, type, etc.)
│       ├── isp_serial_singleton.spin2  # Serial terminal driver
│       ├── isp_mem_strings.spin2       # String formatting utilities
│       └── isp_stack_check.spin2       # Stack usage diagnostic
│
├── regression-tests/           # Regression test suite (345+ tests)
│   ├── SD_RT_*_tests.spin2        # 19 test files (mount, file ops, seek, etc.)
│   ├── isp_rt_utilities.spin2     # Shared test framework
│   └── TestCard/                  # Test card setup and validation
│
├── diagnostic-tests/           # Characterization & diagnostic tests
│   ├── SD_card_info_tests.spin2       # Struct-based register access
│   ├── SD_freq_sweep_tests.spin2      # SPI frequency sweep (15-25 MHz)
│   └── SD_spi_limit_test.spin2        # Single SPI frequency probe
│
├── tools/                      # Build and test scripts
│   ├── run_test.sh                 # Test runner (compile + download + capture)
│   └── logs/                       # Test output logs
│
├── DOCs/                       # Documentation
│   ├── SD-CARD-DRIVER-TUTORIAL.md   # Complete guide with examples
│   ├── SD-CARD-DRIVER-THEORY.md     # Architecture and driver internals
│   ├── SD-CARD-PERFORMANCE.md       # Card selection and performance rankings
│   ├── SD-CARD-UTILITIES.md            # Utility program documentation
│   ├── Analysis/                    # Design explorations and studies
│   ├── Archive/                     # Superseded documents
│   ├── cards/                       # Per-card data sheets and catalog
│   ├── Decisions/                   # Architecture decision records
│   ├── Plans/                       # Active plans and punch list
│   ├── Reference/                   # Technical references and guides
│   ├── Research/                    # Hardware research and investigations
│   └── Utils/                       # Utility theory of operations
│
└── REF/                        # Reference material and external code
```

## Known Limitations

- **8.3 filenames only** - no long filename (LFN) support
- **FAT32 only** - no FAT12, FAT16, or exFAT; cards >32GB ship as exFAT and must be reformatted (use the included format utility)
- **SPI mode only** - no SD native 4-bit bus mode
- **25 MHz SPI maximum** - CMD6 High Speed mode switch fails on all tested cards

## Credits

- **Original Driver Concept**: Chris Gadd (OB4269 from Parallax OBEX)
- **Driver Development**: Stephen M. Moraco, Iron Sheep Productions

## License

MIT License - See [LICENSE](LICENSE) for details.

---

*Part of the Iron Sheep Productions Propeller 2 Projects Collection*
