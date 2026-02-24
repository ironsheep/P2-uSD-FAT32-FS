# P2-SD-Card-Driver

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
- **Regression Tested**: 263+ automated tests across 11 core test suites verify mount, file operations, directory navigation, read/write, seek, multi-cog, multi-handle, multi-block, raw sector, format, and subdirectory cache coherence scenarios

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

The microSD add-on board plugs into any P2 8-pin header group. To use a different group, change `SD_BASE`:

```spin2
CON
    SD_BASE = 16                      ' External header on P16-P23
    SD_SCK  = SD_BASE + 5             ' P21
    SD_CS   = SD_BASE + 4             ' P20
    SD_MOSI = SD_BASE + 3             ' P19
    SD_MISO = SD_BASE + 2             ' P18
```

See the [Driver Tutorial](DOCs/SD-CARD-DRIVER-TUTORIAL.md#using-a-different-8-pin-header-group) for a complete header group reference table.

## Quick Start

### Basic File Operations

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

### Multi-File Example (Copy File)

```spin2
PUB copyFile(src_name, dest_name) | src_h, dest_h, buf[128], bytes
    src_h := sd.openFileRead(src_name)
    dest_h := sd.createFileNew(dest_name)

    if src_h >= 0 and dest_h >= 0
        repeat
            bytes := sd.readHandle(src_h, @buf, 512)
            if bytes == 0
                quit
            sd.writeHandle(dest_h, @buf, bytes)

        sd.closeFileHandle(src_h)
        sd.closeFileHandle(dest_h)
```

### Directory Navigation

**Index-based** (enumerates calling cog's CWD):
```spin2
PUB listDirectory() | entry, p_entry
    entry := 0
    repeat
        p_entry := sd.readDirectory(entry++)
        if p_entry == 0
            quit
        if sd.attributes() & $10
            debug("[DIR]  ", zstr(sd.fileName()))
        else
            debug("[FILE] ", zstr(sd.fileName()), " ", udec(sd.fileSize()), " bytes")
```

**Handle-based** (enumerate any directory without changing CWD):
```spin2
PUB listPath(p_path) | dh, p_entry
    dh := sd.openDirectory(p_path)
    if dh < 0
        debug("Cannot open directory")
        return
    repeat
        p_entry := sd.readDirectoryHandle(dh)
        if p_entry == 0
            quit
        if sd.attributes() & $10
            debug("[DIR]  ", zstr(sd.fileName()))
        else
            debug("[FILE] ", zstr(sd.fileName()), " ", udec(sd.fileSize()), " bytes")
    sd.closeDirectoryHandle(dh)
```

Use `readDirectory()` for simple CWD listing. Use `openDirectory()`/`readDirectoryHandle()`/`closeDirectoryHandle()` when you need to enumerate a specific path without changing CWD, or when multiple cogs enumerate concurrently.

## Documentation

- **[Driver Theory of Operations](DOCs/SD-CARD-DRIVER-THEORY.md)** - Architecture, handle system, SPI, and internals
- **[Driver Tutorial](DOCs/SD-CARD-DRIVER-TUTORIAL.md)** - Complete guide with practical examples
- **[Regression Testing](regression-tests/README.md)** - Test infrastructure and validation
- **[Card Catalog](DOCs/CARD-CATALOG.md)** - Tested SD cards with performance data
- **[Utilities Guide](DOCs/UTILITIES.md)** - Standalone utility programs
- **[Utility Internals](DOCs/Utils/)** - Theory of operations for each utility

## Project Structure

```
P2-uSD-Study/
├── src/                        # Driver and application source
│   ├── micro_sd_fat32_fs.spin2     # The SD card driver
│   ├── UTILS/                      # Standalone utility programs
│   │   ├── SD_format_card.spin2           # FAT32 card formatter
│   │   ├── SD_card_characterize.spin2  # Card register reader (CID/CSD/SCR)
│   │   ├── SD_speed_characterize.spin2 # Maximum SPI speed tester
│   │   ├── SD_FAT32_audit.spin2        # Filesystem validator (read-only)
│   │   ├── SD_FAT32_fsck.spin2         # Filesystem check & repair
│   │   ├── SD_performance_benchmark.spin2  # Read/write throughput bench
│   │   ├── isp_format_utility.spin2    # FAT32 format library
│   │   ├── isp_fsck_utility.spin2      # Combined FSCK + Audit library
│   │   └── isp_string_fifo.spin2       # Inter-cog string FIFO
│   └── DEMO/                       # Interactive demo application
│       └── SD_demo_shell.spin2         # Terminal shell (dir, cd, type, etc.)
│
├── regression-tests/           # Regression test suite
│   ├── SD_RT_*.spin2               # Test files (mount, file ops, seek, etc.)
│   └── isp_rt_utilities.spin2      # Shared test framework
│
├── tools/                      # Build and test scripts
│   ├── run_test.sh                 # Test runner (compile + download + capture)
│   └── logs/                       # Test output logs
│
├── DOCs/                       # Documentation, tutorials, analysis
└── REF/                        # Reference material and external code
```

## Performance

Measured at 350 MHz sysclk with 25 MHz SPI, smart pin hardware acceleration, streamer DMA, and multi-sector commands (CMD18/CMD25):

| Operation | SanDisk Industrial 16GB | Lexar Blue 128GB | Amazon Basics 64GB | Samsung PRO Endurance 128GB |
|-----------|:-:|:-:|:-:|:-:|
| File Read (256KB) | 745 KB/s | **1,444 KB/s** | 1,386 KB/s | 1,419 KB/s |
| File Write (32KB) | 321 KB/s | 616 KB/s | **774 KB/s** | 758 KB/s |
| Raw Multi-sector Read (32KB) | 2,393 KB/s | 2,420 KB/s | 2,425 KB/s | **2,427 KB/s** |
| Raw Multi-sector Write (32KB) | 2,170 KB/s | 2,275 KB/s | 2,305 KB/s | **2,319 KB/s** |
| Mount | 486 ms | 400 ms | 233 ms | 243 ms |

Raw SPI efficiency reaches 80% of theoretical maximum (2,427 / 3,052 KB/s). Multi-sector commands provide 46-69% improvement over single-sector operations.

Single-sector read throughput (internal card controller speed) varies widely:

| Card | Throughput | App Perf Class |
|------|------------|----------------|
| Samsung PRO Endurance 128GB | 1,283 KB/s | A2 |
| Amazon Basics 64GB | 1,245 KB/s | A2 |
| Lexar V30 U3 64GB | 1,239 KB/s | A2 |
| SanDisk Extreme 64GB | 1,005 KB/s | A2 |
| Samsung EVO Select 128GB | 937 KB/s | -- |
| SanDisk Nintendo Switch 128GB | 887 KB/s | A2 |
| Lexar Blue 128GB | 819 KB/s | A2 |
| SanDisk Industrial 16GB | 792 KB/s | -- |
| PNY 16GB | 734 KB/s | -- |

Performance varies significantly by card controller, not just speed class rating. 20 cards tested across 9 manufacturers. See [Card Catalog](DOCs/CARD-CATALOG.md) for detailed characterization and [Benchmark Results](DOCs/BENCHMARK-RESULTS.md) for full cross-card comparisons at 350 and 250 MHz.

## API Overview

### Mounting
| Method | Description |
|--------|-------------|
| `mount(cs, mosi, miso, sck)` | Initialize and mount SD card |
| `unmount()` | Sync and unmount SD card |

### File Operations (Handle-Based)
| Method | Description |
|--------|-------------|
| `openFileRead(pPath)` | Open file for reading, returns handle |
| `openFileWrite(pPath)` | Open file for writing, returns handle |
| `createFileNew(pPath)` | Create new file, returns handle |
| `readHandle(handle, pBuf, count)` | Read bytes from file |
| `writeHandle(handle, pBuf, count)` | Write bytes to file |
| `seekHandle(handle, pos)` | Set file position |
| `closeFileHandle(handle)` | Close file handle |

### Directory Operations
| Method | Description |
|--------|-------------|
| `changeDirectory(pPath)` | Navigate to directory (per-cog CWD) |
| `newDirectory(pName)` | Create new directory |
| `readDirectory(entry)` | Enumerate CWD entries by index |
| `openDirectory(pPath)` | Open directory for enumeration, returns handle |
| `readDirectoryHandle(handle)` | Read next entry from directory handle |
| `closeDirectoryHandle(handle)` | Close directory handle |
| `deleteFile(pName)` | Delete file or empty directory |
| `rename(pOld, pNew)` | Rename file or directory |

### Information
| Method | Description |
|--------|-------------|
| `freeSpace()` | Get free space in sectors |
| `volumeLabel()` | Get volume label string |
| `fileSize()` | Get size of open file |
| `error()` | Get last error code |

## Utilities

The `src/UTILS/` folder contains standalone utility programs:

- **SD_format_card.spin2** - Format SD cards with FAT32
- **SD_card_characterize.spin2** - Read and display card registers (CID, CSD, SCR)
- **SD_speed_characterize.spin2** - Test maximum reliable SPI speed
- **SD_FAT32_audit.spin2** - Validate FAT32 filesystem structure (read-only)
- **SD_FAT32_fsck.spin2** - Check and repair FAT32 filesystem (4-pass FSCK)
- **SD_performance_benchmark.spin2** - Measure read/write throughput

## Demo Shell

The `src/DEMO/SD_demo_shell.spin2` provides an interactive terminal interface:

```
SD:/> help
  mount        Mount SD card
  dir          List directory (alias: ls)
  cd <path>    Change directory
  type <file>  Display text file (alias: cat)
  copy <s> <d> Copy file (alias: cp)
  del <file>   Delete file (alias: rm)
  stats        Show filesystem statistics
  card         Show card identification
  audit        Filesystem integrity check
  fsck         Filesystem check & repair
  benchmark    Quick speed test
```

Connect at 2,000,000 baud (2 Mbit) to use the shell.

**Compile from the `src/DEMO/` directory:**

```bash
cd src/DEMO/
pnut-ts -d -I .. SD_demo_shell.spin2
```

See [`src/DEMO/README.md`](src/DEMO/README.md) for full build and usage documentation.

## Testing

The driver is validated by **263+ automated regression tests** across 11 core test suites, all running on real P2 hardware with actual SD cards:

| Test Suite | Tests | Coverage |
|------------|-------|----------|
| Mount | 21 | Card init, mount/unmount, pre-mount error handling |
| File Operations | 22 | Create, open, close, delete, rename (V3 handle API) |
| Read/Write | 38 | Data integrity, sector boundaries, multi-cluster, large files |
| Directory | 28 | Navigation, nesting (5 levels), handle enumeration |
| Seek | 37 | Random access, boundary conditions, cluster chain traversal |
| Multi-Cog | 14 | Singleton pattern, concurrent access, per-cog CWD isolation |
| Multi-Handle | 19 | Multiple simultaneous file handles, error boundaries |
| Multi-Block | 6 | CMD18/CMD25 multi-sector DMA read/write round-trips |
| Raw Sector | 14 | Direct sector read/write, patterns, large LBA addressing |
| Format | 46 | FAT32 structure validation, cross-OS compatibility |
| Subdirectory Ops | 18 | Cross-buffer cache coherence, empty files, rename in subdirs |

Additional test suites cover directory handles, volume operations, CRC diagnostics, speed/CMD6 APIs, register access, error handling, and FIFO infrastructure.

Tests compile with `pnut-ts`, download to P2, and capture debug output automatically. Run from the `tools/` directory:

```bash
cd tools/
./run_test.sh ../regression-tests/SD_RT_mount_tests.spin2
./run_test.sh ../regression-tests/SD_RT_file_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_read_write_tests.spin2
./run_test.sh ../regression-tests/SD_RT_directory_tests.spin2
./run_test.sh ../regression-tests/SD_RT_seek_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multicog_tests.spin2 -t 120
./run_test.sh ../regression-tests/SD_RT_multihandle_tests.spin2
./run_test.sh ../regression-tests/SD_RT_multiblock_tests.spin2
./run_test.sh ../regression-tests/SD_RT_raw_sector_tests.spin2
./run_test.sh ../regression-tests/SD_RT_subdir_ops_tests.spin2
./run_test.sh ../regression-tests/SD_RT_format_tests.spin2 -t 300
```

See [REGRESSION-TESTING.md](regression-tests/README.md) for complete test documentation.

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
