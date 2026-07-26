# SD Card Demo Shell

An interactive command-line shell for the P2 SD card filesystem driver. Download it to your P2 to browse, inspect, and manage SD cards directly from a serial terminal. Supports both DOS-style (`dir`, `type`, `del`) and Unix-style (`ls`, `cat`, `rm`) commands.

Beyond exercising driver features, the shell is a practical all-in-one card management tool: format a new card, check filesystem integrity with `audit`, repair corruption with `fsck`, and measure performance with `bench` — all without leaving the terminal session.

## Files

| File | Description |
|------|-------------|
| `SD_demo_shell.spin2` | Main shell application |
| `isp_serial_singleton.spin2` | Serial terminal driver (singleton, shared across cogs) |
| `isp_mem_strings.spin2` | In-memory string formatting utilities |

The shell also uses these files from other directories (included via `-I` flags):

| File | Location | Description |
|------|----------|-------------|
| `micro_sd_fat32_fs.spin2` | `src/` | SD card driver |
| `isp_fsck_utility.spin2` | `src/UTILS/` | FSCK/audit library (powers `audit` and `fsck` commands) |
| `isp_format_utility.spin2` | `src/UTILS/` | Format library (powers `format` command) |
| `isp_string_fifo.spin2` | `src/UTILS/` | Inter-cog string FIFO (used by fsck and format libraries) |

## Building and Running

See [Prerequisites](../../README.md#prerequisites) for toolchain and hardware requirements.

### Compile and Run

From this `DEMO/` directory:

```bash
pnut-ts -I .. -I ../UTILS SD_demo_shell.spin2
pnut-term-ts -r SD_demo_shell.bin
```

The `-I ..` flag tells the compiler to find the SD card driver in the parent directory. The `-I ../UTILS` flag is needed for the fsck, audit, and format libraries used by the shell's diagnostic commands.

**Important:** Do NOT use the `-d` (debug) flag when compiling the demo shell. The debug runtime emits cog-start frames on pin 62 that corrupt the serial output when the SD worker cog starts mid-session (e.g., during `mount`). The demo shell uses `isp_serial_singleton.spin2` for all terminal I/O, not the debug system.

## Terminal Setup

Make sure pnut-term-ts is configured for 2,000,000 baud serial in its settings. The shell uses PST control characters for screen clearing (CLS = 16) and cursor control.

## Using the Shell

### Startup

When the shell starts, it clears the screen and displays a welcome banner:

```
P2 SD Card Filesystem Shell
- type 'help' for commands
```

The prompt shows the current directory and mount status:

```
SD:/> _                  (mounted, at root)
SD:/MYDIR> _             (mounted, in MYDIR)
SD:(unmounted)> _        (card not mounted)
```

### First Steps

The SD card must be mounted before any filesystem operations:

```
SD:(unmounted)> mount
Mounting SD card...
Mounted successfully
  Card: PNY SD16G (16 GB)
  SPI:  25000000 Hz
  Free: 15.9 GB
SD:/>
```

### Browsing Files

```
SD:/> dir
 Directory of /

  Attr    Name          Size
  ----    --------      ----------
  D---    MYDIR/
  -A--    README.TXT    1,234
  -A--    DATA.BIN      65,536

       2 File(s)     66,770 bytes
       1 Dir(s)

SD:/> cd MYDIR
SD:/MYDIR> dir
 Directory of /MYDIR

  Attr    Name          Size
  ----    --------      ----------
  -A--    NOTES.TXT     512

       1 File(s)     512 bytes

SD:/MYDIR> cd /
SD:/>
```

### Reading Files

```
SD:/> type README.TXT
Hello from the P2 SD card driver!
This is a demo text file.
[58 bytes]

SD:/> hexdump DATA.BIN
00000000  48 65 6c 6c 6f 20 57 6f  72 6c 64 21 0d 0a 00 00  |Hello World!....|
... (truncated at 512 bytes)
```

### File Operations

```
SD:/> copy README.TXT BACKUP.TXT
Copied 58 bytes to BACKUP.TXT

SD:/> ren BACKUP.TXT SAVED.TXT
Renamed 'BACKUP.TXT' to 'SAVED.TXT'

SD:/> touch EMPTY.TXT
Created: EMPTY.TXT

SD:/> mkdir NEWDIR
Created directory: NEWDIR

SD:/> del EMPTY.TXT
Deleted: EMPTY.TXT
```

### Card Information

```
SD:/> stats
  Volume label: P2FMTER
  Free space:   15.9 GB (31199056 sectors)
  Cluster size: 16 sectors (8192 bytes)

SD:/> card
  Manufacturer: PNY (0x27)
  Product:      SD16G
  Revision:     2.0
  Serial:       0x0BADCAFE
  Date:         06/2023

SD:/> version
  SD Card Driver - Iron Sheep Productions
  SPI Frequency: 25000000 Hz
```

### Diagnostics

**Audit** - read-only filesystem integrity check.
**FSCK** - filesystem check and repair.

Both commands delegate to the same four-pass engine the standalone utilities use
(`isp_fsck_utility`), so their output is identical to it. The canonical,
capture-stamped transcript lives in
[`DOCs/SD-CARD-UTILITIES.md`](../../DOCs/SD-CARD-UTILITIES.md) — see the
`SD_FAT32_audit` and `SD_FAT32_fsck` sections.

`fsck` prompts for confirmation before writing:

```
SD:/> fsck
  WARNING: FSCK will modify the SD card to fix errors.
  Continue? (Y/N): y
```

**Benchmark** - read-only throughput measurement. Timings vary by card; run it on
yours rather than relying on the figures below.

```
SD:/> bench
Initializing card...

=== Read-Only Throughput Benchmark ===
Card: 7431 MB, SPI: 25000000 Hz
Test area: sectors 1000+

Single-sector (100 reads)... 123 ms, 415 KB/s
Multi-sector x8 (100 reads)... 89 ms, 573 KB/s
Multi-sector x32 (25 reads)... 71 ms, 720 KB/s
```

### Utility Commands

| Command | Description |
|---------|-------------|
| `demo` | Create sample files for testing |
| `cls` / `clear` | Clear the terminal screen |
| `help` | Show all available commands |

## Complete Command Reference

### Navigation
| Command | Aliases | Description |
|---------|---------|-------------|
| `mount` | | Mount the SD card |
| `unmount` | `eject` | Safely unmount the SD card |
| `dir` | `ls` | List directory contents |
| `tree` | | Display directory tree |
| `cd <path>` | | Change directory (`cd ..`, `cd /`, `cd SUBDIR`) |
| `pwd` | | Print current working directory |

### File Operations
| Command | Aliases | Description |
|---------|---------|-------------|
| `type <file>` | `cat` | Display text file contents |
| `hexdump <file>` | `hd` | Display file in hex dump format |
| `copy <src> <dst>` | `cp` | Copy a file |
| `ren <old> <new>` | | Rename a file or directory |
| `mv <src> <dst>` | `move` | Move a file or directory |
| `del <file>` | `rm` | Delete a file |
| `touch <file>` | | Create an empty file |
| `mkdir <dir>` | | Create a new directory |
| `rmdir <dir>` | | Remove an empty directory |

### Information
| Command | Aliases | Description |
|---------|---------|-------------|
| `stats` | `info` | Show filesystem statistics |
| `label` | `vol` | Show volume label |
| `card` | `cid` | Show card identification (CID register) |
| `version` | | Show driver version and SPI frequency |
| `alias` | | Show all command aliases |

### Diagnostics
| Command | Aliases | Description |
|---------|---------|-------------|
| `format` | | Format the SD card (prompts before erasing) |
| `audit` | | Read-only filesystem integrity check |
| `fsck` | | Filesystem check and repair (prompts before modifying) |
| `bench` | `benchmark`, `perf` | Read throughput benchmark |

## Hardware Configuration

The microSD add-on board connects to any 8-pin header group on the P2. Pins are defined as offsets from the base pin of the group:

| Offset | Signal | Description |
|--------|--------|-------------|
| +5 | CLK (SCK) | Serial Clock |
| +4 | CS (DAT3) | Chip Select |
| +3 | MOSI (CMD) | Master Out, Slave In |
| +2 | MISO (DAT0) | Master In, Slave Out |
| +1 | Insert Detect | Active low when card inserted (not used by driver) |

The default configuration uses base pin 56 (P2 Edge Module):

```spin2
CON
    SD_BASE = 56
    SD_SCK  = SD_BASE + 5    ' P61 - Serial Clock
    SD_CS   = SD_BASE + 4    ' P60 - Chip Select
    SD_MOSI = SD_BASE + 3    ' P59 - Master Out Slave In
    SD_MISO = SD_BASE + 2    ' P58 - Master In Slave Out
```

To use a different 8-pin group, change `SD_BASE` in the `CON` section of `SD_demo_shell.spin2`.

## Architecture

The demo shell runs as a single-cog application:

1. **Main loop** - reads commands from serial, parses tokens, dispatches to handlers
2. **SD card driver** - runs its own worker cog for SPI operations (started on `mount`)
3. **Serial driver** - singleton serial terminal on the programming port (P62/P63)

The shell maintains its own current working directory string (`cwd`) for the prompt display, synchronized with the driver's per-cog CWD via `changeDirectory()`.

---

*Part of the [P2 microSD FAT32 Filesystem](../../README.md) project — Iron Sheep Productions*
