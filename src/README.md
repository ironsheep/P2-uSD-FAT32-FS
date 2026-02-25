# Source Files

All Spin2 source code for the P2 SD Card Driver, demo application, and utility programs.

## SD Card Driver

**micro_sd_fat32_fs.spin2** — The FAT32-compliant SD card filesystem driver for the Parallax Propeller 2.

Features:
- Smart pin SPI with streamer DMA for hardware-accelerated transfers
- Dedicated worker cog with hardware lock serialization
- Multi-file handle system (up to 6 simultaneous file and directory handles, configurable)
- Per-cog current working directory for safe multi-cog navigation
- Handle-based file API: open, read, write, seek, close
- Handle-based directory enumeration
- Directory operations: create, navigate, enumerate, delete, rename
- Low-level raw sector and multi-sector (CMD18/CMD25) bulk transfers
- Hardware-accelerated CRC-16 validation on all data transfers

### Using the Driver

Copy `micro_sd_fat32_fs.spin2` into your project directory (or use `-I` to point to it), then:

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

### Conditional Compilation

The driver builds in **minimal mode** by default (core file operations only). Enable optional modules with `#PRAGMA EXPORTDEF` in your top-level file before the OBJ declaration:

```spin2
#PRAGMA EXPORTDEF SD_INCLUDE_RAW        ' Raw sector access
#PRAGMA EXPORTDEF SD_INCLUDE_REGISTERS  ' Card register access (CID/CSD/SCR)
#PRAGMA EXPORTDEF SD_INCLUDE_SPEED      ' High-speed mode control
#PRAGMA EXPORTDEF SD_INCLUDE_DEBUG      ' Debug/diagnostic methods & CRC getters

' Or include everything:
#PRAGMA EXPORTDEF SD_INCLUDE_ALL
```

## DEMO/

Interactive terminal shell for exploring the SD card filesystem. Supports both DOS-style (`dir`, `type`, `del`) and Unix-style (`ls`, `cat`, `rm`) commands.

| File | Description |
|------|-------------|
| `SD_demo_shell.spin2` | Main shell application |
| `isp_serial_singleton.spin2` | Serial terminal driver (singleton, shared across cogs) |
| `isp_mem_strings.spin2` | In-memory string formatting utilities |
| `isp_stack_check.spin2` | Stack usage diagnostic (development only) |

See [DEMO/README.md](DEMO/README.md) for build instructions, command reference, and usage examples.

## UTILS/

Standalone utility programs for preparing SD cards for embedded use, diagnosing filesystem problems, and characterizing untested cards.

| Utility | Purpose | Destructive? |
|---------|---------|:------------:|
| **SD_format_card.spin2** | FAT32 card formatter | Yes |
| **SD_FAT32_audit.spin2** | Filesystem validator (read-only) | No |
| **SD_FAT32_fsck.spin2** | Filesystem check and repair | Yes |
| **SD_card_characterize.spin2** | Card register reader (CID/CSD/SCR/OCR) | No |
| **SD_speed_characterize.spin2** | Maximum SPI speed tester | No |
| **SD_frequency_characterize.spin2** | Sysclk frequency tester | No |
| **SD_performance_benchmark.spin2** | Read/write throughput measurement | Yes* |

*Creates temporary test files that are deleted after testing.

Support libraries used by the utilities:

| File | Used By |
|------|---------|
| `isp_format_utility.spin2` | Format card, demo shell |
| `isp_fsck_utility.spin2` | FSCK, audit, demo shell |
| `isp_string_fifo.spin2` | Lock-free inter-cog string FIFO (used by format and FSCK libraries) |

See [UTILS/README.md](UTILS/README.md) for build instructions and detailed documentation for each utility.

## Building

See the [project README](../README.md) for toolchain and hardware requirements.

### Running from tools/ (recommended)

```bash
cd tools/
./run_test.sh ../src/DEMO/SD_demo_shell.spin2
./run_test.sh ../src/UTILS/SD_card_characterize.spin2
```

### Compile and Run directly

Programs in DEMO/ and UTILS/ use `-I ..` to find the driver in this directory:

```bash
# Demo shell (from DEMO/ directory)
pnut-ts -I .. -I ../UTILS SD_demo_shell.spin2
pnut-term-ts -r SD_demo_shell.bin

# Utility (from UTILS/ directory)
pnut-ts -d -I .. SD_card_characterize.spin2
pnut-term-ts -r SD_card_characterize.bin
```

---

*Part of the [P2 microSD FAT32 Filesystem](../README.md) project — Iron Sheep Productions*
