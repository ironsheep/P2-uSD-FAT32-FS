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
│   ├── ERROR-HANDLING-GUIDE.md            Every error the driver reports, and what to do
│   ├── CONDITIONAL-COMPILATION-GUIDE.md   Feature flags and what each adds
│   ├── SD-CARD-PERFORMANCE.md             Card selection and performance rankings
│   ├── SD-CARD-UTILITIES.md               Format, audit, fsck, characterize, benchmark
│   ├── MIGRATION-GUIDE-v1.7.0.md          Upgrading from v1.6.x
│   ├── MIGRATION-GUIDE-v1.2.0.md          Upgrading from v1.0/v1.1
│   ├── SPI-PHASE-MARGIN-API.md            Diagnostic timing knobs
│   ├── DRIVER-EVOLUTION-v1.6.0-to-v1.7.0.md  What was wrong, and what fixed it
│   └── images/                            Card photos for purchase recommendations
│
└── src/                                Driver and application source
    ├── micro_sd_fat32_fs.spin2            The SD card driver
    ├── isp_stack_check.spin2              Worker cog stack usage monitor
    ├── isp_mem_strings.spin2              String formatting (shared: demo shell + utilities)
    ├── EXAMPLES/                          Compilable example programs
    │   ├── README.md                         Build instructions
    │   ├── SD_example_read_write.spin2       Basic file read/write
    │   ├── SD_example_data_logger.spin2      Append-mode logging with sync
    │   ├── SD_example_directory_walk.spin2   Directory operations
    │   └── SD_example_multicog.spin2         Multi-cog concurrent access
    ├── DEMO/                              Interactive terminal shell
    │   ├── README.md                         Build and usage guide
    │   ├── SD_demo_shell.spin2               Shell application
    │   └── isp_serial_singleton.spin2        Serial terminal driver
    ├── UTILS/                             Standalone utility programs
    │   ├── README.md                         Full utility documentation
    │   ├── SD_format_card.spin2              FAT32 card formatter
    │   ├── isp_format_utility.spin2          FAT32 format library
    │   ├── SD_card_identify.spin2            Three-line card identification
    │   ├── SD_card_characterize.spin2        Card register reader
    │   ├── SD_performance_benchmark.spin2    Throughput measurement
    │   ├── SD_FAT32_audit.spin2              Filesystem validator (read-only)
    │   ├── SD_FAT32_fsck.spin2               Filesystem check & repair
    │   ├── isp_fsck_utility.spin2            Combined FSCK + Audit library (runs in temp cog)
    │   └── isp_string_fifo.spin2             Lock-free inter-cog string FIFO
    └── regression-tests/                  Regression test suite
        ├── README.md                         Test infrastructure guide
        ├── SD_RT_*_tests.spin2               28 test suites (590 tests)
        └── isp_rt_utilities.spin2            Shared test framework
```

## Prerequisites

### Toolchain (choose one)

- **Flexspin** — Open-source Spin2/PASM2/C compiler ([GitHub](https://github.com/totalspectrum/flexprop))
- **Spin Tools IDE** — Cross-platform Spin2/PASM2 IDE ([MaccaSoft](https://maccasoft.com/en/spin-tools-ide/))
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
    if sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK) < 0
        debug("Mount failed: ", sdec_(sd.error()))
    else
        handle := sd.openFileRead(@"CONFIG.TXT")
        if handle < 0
            debug("Open failed: ", sdec_(handle))
        else
            repeat
                bytes_read := sd.readHandle(handle, @buffer, 512)
                if bytes_read =< 0
                    quit                      ' 0 is end of file; negative is a failure
                process(@buffer, bytes_read)

            if bytes_read < 0
                debug("Read failed: ", sdec_(sd.handleError(handle)))

            sd.closeFileHandle(handle)

        sd.unmount()
```

Every method that can fail returns `SUCCESS` (0) or a negative error code — never a
boolean, so compare against 0 rather than testing truthiness. See
[ERROR-HANDLING-GUIDE.md](DOCs/ERROR-HANDLING-GUIDE.md).

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

> **Socket timing:** Two sockets wired to the same P2 can differ measurably in signal timing — on our bench, an external header-wired adapter adds a ~3 ns-class round-trip delay over the P2 Edge module's onboard socket. At the standard 25 MHz both carry wide margin, but a card that is itself timing-marginal may misbehave in one socket and work in the other. If you see socket-dependent card behavior, see the Socket Timing Differences section of the [Card Performance](DOCs/SD-CARD-PERFORMANCE.md) guide and the *Receive Alignment and Socket Timing* section of the [Theory of Operations](DOCs/SD-CARD-DRIVER-THEORY.md). Since v1.8.0 the read-path alignment sits at the centre of its measured passing band rather than the lower edge, which equalises read margin between sockets. The one socket-dependent failure we had under investigation turned out not to be a timing effect at all: it was a card left mid-transfer by the boot sequence on shared flash/microSD pins, and v1.8.0 fixes it at card initialisation.

## Documentation

| Document | Description |
|----------|-------------|
| [Tutorial](SD-CARD-DRIVER-TUTORIAL.md) | Complete guide with practical examples |
| [Theory of Operations](DOCs/SD-CARD-DRIVER-THEORY.md) | Architecture, handle system, SPI internals |
| [Error Handling Guide](DOCs/ERROR-HANDLING-GUIDE.md) | Detecting and responding to every error the driver reports |
| [Conditional Compilation](DOCs/CONDITIONAL-COMPILATION-GUIDE.md) | Feature flags and what each one adds |
| [Card Performance](DOCs/SD-CARD-PERFORMANCE.md) | Card selection, identification, and performance rankings |
| [Utilities](DOCs/SD-CARD-UTILITIES.md) | Format, audit, fsck, characterize, benchmark |
| [Migration to v1.7.0](DOCs/MIGRATION-GUIDE-v1.7.0.md) | Moving from v1.6.x — read this first when upgrading |
| [Migration to v1.2.0](DOCs/MIGRATION-GUIDE-v1.2.0.md) | Moving from v1.0/v1.1 error-code patterns |
| [SPI Phase-Margin API](DOCs/SPI-PHASE-MARGIN-API.md) | Diagnostic timing knobs for unfamiliar boards and sockets |
| [Driver Evolution v1.6.0–v1.7.0](DOCs/DRIVER-EVOLUTION-v1.6.0-to-v1.7.0.md) | Technical account of the defects fixed across three releases |

## Regression Tests

The regression test suite (590 tests across 28 test files) is included in `src/regression-tests/`. Each test compiles with pnut-ts and runs on P2 hardware, producing pass/fail results via debug output.

## License

MIT License

Copyright (c) 2026 Iron Sheep Productions, LLC
