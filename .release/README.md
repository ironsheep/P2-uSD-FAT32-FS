# P2 SD Card Driver

A high-performance FAT32-compliant microSD card filesystem driver for the Parallax Propeller 2 (P2) microcontroller.

## What's in this Package

```
sd-card-driver/
├── README.md                           This file
├── LICENSE                             MIT License
├── CHANGELOG.md                        Release history
├── SD-CARD-DRIVER-TUTORIAL.md          Complete guide with examples
│
├── DOCs/                               Reference documentation
│   ├── SD-CARD-DRIVER-THEORY.md           Architecture and driver internals
│   ├── SD-CARD-PERFORMANCE.md             Card selection and performance rankings
│   └── images/                            Card photos for purchase recommendations
│
└── src/                                Driver and application source
    ├── micro_sd_fat32_fs.spin2            The SD card driver
    ├── DEMO/                              Interactive terminal shell
    │   ├── README.md                         Build and usage guide
    │   ├── SD_demo_shell.spin2               Shell application
    │   ├── isp_serial_singleton.spin2        Serial terminal driver
    │   └── isp_mem_strings.spin2             String formatting utilities
    └── UTILS/                             Standalone utility programs
        ├── README.md                         Full utility documentation
        ├── SD_format_card.spin2              FAT32 card formatter
        ├── isp_format_utility.spin2          FAT32 format library
        ├── SD_card_characterize.spin2        Card register reader
        ├── SD_performance_benchmark.spin2    Throughput measurement
        ├── SD_FAT32_audit.spin2              Filesystem validator (read-only)
        ├── SD_FAT32_fsck.spin2               Filesystem check & repair
        ├── isp_fsck_utility.spin2            Combined FSCK + Audit library (runs in temp cog)
        └── isp_string_fifo.spin2             Lock-free inter-cog string FIFO
```

## Prerequisites

### Toolchain (choose one)

- **Flexspin** — Open-source Spin2/PASM2/C compiler ([GitHub](https://github.com/totalspectrum/flexprop))
- **Propeller Tool** — Parallax's official IDE ([Downloads](https://www.parallax.com/propeller-tool/))
- **pnut-ts + pnut-term-ts** — Command-line Spin2 compiler and terminal. See detailed install instructions for **[macOS](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-macOS.md#installing-pnut-term-ts-on-macos)**, **[Windows](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-win.md#installing-pnut-term-ts-on-windows)**, and **[Linux/RPi](https://github.com/ironsheep/P2-vscode-langserv-extension/blob/main/TASKS-User-RPi.md#installing-pnut-term-ts-on-rpilinux)**

### Hardware

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
pnut-ts -I .. -I ../UTILS SD_demo_shell.spin2
pnut-term-ts -r SD_demo_shell.bin
```

Make sure pnut-term-ts is configured for 2,000,000 baud serial in its settings. See `src/DEMO/README.md` for full usage.

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
| [Theory of Operations](DOCs/SD-CARD-DRIVER-THEORY.md) | Architecture, handle system, SPI internals |
| [Card Performance](DOCs/SD-CARD-PERFORMANCE.md) | Card selection, identification, and performance rankings |

## Regression Tests

A comprehensive regression test suite (345+ tests across 19 test files) is available in the [GitHub repository](https://github.com/ironsheep/P2-uSD-FAT32-FS). The tests are not included in this release package but can be cloned from the repo if needed.

## License

MIT License

Copyright (c) 2026 Iron Sheep Productions, LLC
