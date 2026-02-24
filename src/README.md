# P2 SD Card Driver

A high-performance FAT32-compliant microSD card filesystem driver for the Parallax Propeller 2 (P2) microcontroller.

## What's in this Package

```
sd-card-driver/
├── README.md                           This file
├── LICENSE                             MIT License
├── CHANGELOG.md                        Release history
│
├── src/                                Driver and application source
│   ├── micro_sd_fat32_fs.spin2            The SD card driver
│   ├── DEMO/                              Interactive terminal shell
│   │   ├── README.md                         Build and usage guide
│   │   ├── SD_demo_shell.spin2               Shell application
│   │   ├── isp_serial_singleton.spin2        Serial terminal driver
│   │   └── isp_mem_strings.spin2             String formatting utilities
│   └── UTILS/                             Standalone utility programs
│       ├── README.md                         Full utility documentation
│       ├── SD_format_card.spin2              FAT32 card formatter
│       ├── isp_format_utility.spin2          FAT32 format library
│       ├── SD_card_characterize.spin2        Card register reader
│       ├── SD_speed_characterize.spin2       SPI speed tester
│       ├── SD_frequency_characterize.spin2   Sysclk frequency tester
│       ├── SD_performance_benchmark.spin2    Throughput measurement
│       ├── SD_FAT32_audit.spin2              Filesystem validator (read-only)
│       ├── SD_FAT32_fsck.spin2               Filesystem check & repair
│       ├── isp_fsck_utility.spin2            Combined FSCK + Audit library (runs in temp cog)
│       └── isp_string_fifo.spin2             Lock-free inter-cog string FIFO
│
├── regression-tests/                   Automated test suite (263+ tests)
│   ├── README.md                          Test documentation
│   ├── isp_rt_utilities.spin2             Shared test framework
│   ├── SD_RT_*_tests.spin2                Test files (11 core + 7 additional suites)
│   └── TestCard/                          Test card setup
│       ├── TEST-CARD-SPECIFICATION.md        Card requirements
│       ├── SD_RT_testcard_validation.spin2   Card validation test
│       └── TESTROOT/                         Files to copy to test card
│
├── BENCHMARK-RESULTS.md                Performance data across 6 cards
├── CARD-CATALOG.md                     Tested SD cards with characterization
├── FAT32-API-CONCEPTS-REFERENCE.md     FAT32 API background reference
├── SD-CARD-DRIVER-THEORY.md            Architecture and driver internals
├── SD-CARD-DRIVER-TUTORIAL.md          Complete guide with examples
└── SD-CARD-SPI-COMPATIBILITY.md        SPI mode compatibility notes
```

## Prerequisites

- **pnut-ts** and **pnut-term-ts** - See detailed installation instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**
- Parallax Propeller 2 (P2 Edge or P2 board with microSD add-on) connected via USB

## Quick Start

### Using the Driver in Your Project

Copy `src/micro_sd_fat32_fs.spin2` into your project directory, then:

```spin2
OBJ
    sd : "micro_sd_fat32_fs"

CON
    SD_BASE = 56                      ' Base pin of 8-pin header group
    SD_SCK  = SD_BASE + 5             ' Serial Clock
    SD_CS   = SD_BASE + 4             ' Chip Select
    SD_MOSI = SD_BASE + 3             ' Master Out, Slave In
    SD_MISO = SD_BASE + 2             ' Master In, Slave Out

PUB main() | handle, buffer[128], bytes_read
    if not sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
        debug("Mount failed!")
        return

    handle := sd.openFileRead(@"CONFIG.TXT")
    if handle >= 0
        bytes_read := sd.readHandle(handle, @buffer, 512)
        sd.closeFileHandle(handle)

    sd.unmount()
```

### Running the Demo Shell

```bash
cd src/DEMO/
pnut-ts -d -I .. SD_demo_shell.spin2
pnut-term-ts -r SD_demo_shell.bin
```

Connect a serial terminal at 2,000,000 baud. See `src/DEMO/README.md` for full usage.

### Running a Utility

```bash
cd src/UTILS/
pnut-ts -d -I .. SD_card_characterize.spin2
pnut-term-ts -r SD_card_characterize.bin
```

See `src/UTILS/README.md` for all available utilities.

## Hardware

The microSD add-on board connects to any 8-pin header group on the P2. Pins are offsets from the base pin:

| Offset | Signal | Description |
|--------|--------|-------------|
| +5 | CLK (SCK) | Serial Clock |
| +4 | CS (DAT3) | Chip Select |
| +3 | MOSI (CMD) | Master Out, Slave In |
| +2 | MISO (DAT0) | Master In, Slave Out |
| +1 | Insert Detect | Active low when card inserted (not used by driver) |

The default configuration uses base pin 56 (P2 Edge Module), giving pins P58-P61.

## Documentation

| Document | Description |
|----------|-------------|
| [Tutorial](SD-CARD-DRIVER-TUTORIAL.md) | Complete guide with practical examples |
| [FAT32 API Reference](FAT32-API-CONCEPTS-REFERENCE.md) | FAT32 internals and standard API concepts |
| [Theory of Operations](SD-CARD-DRIVER-THEORY.md) | Architecture, handle system, SPI internals |
| [Benchmark Results](BENCHMARK-RESULTS.md) | Performance data across 6 tested cards |
| [Card Catalog](CARD-CATALOG.md) | Tested SD cards with characterization data |
| [SPI Compatibility](SD-CARD-SPI-COMPATIBILITY.md) | SPI mode compatibility notes |

## License

MIT License

Copyright (c) 2026 Iron Sheep Productions, LLC
