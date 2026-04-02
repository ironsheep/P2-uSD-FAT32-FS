# SD Card Driver — Theory of Operations

*micro_sd_fat32_fs.spin2*

## Overview

The SD card driver provides full FAT32 filesystem access for the Parallax Propeller 2 (P2). It runs a dedicated worker cog that owns the SPI hardware, accepts commands from any calling cog via a shared mailbox, and serializes all card access through a hardware lock.

Key architectural features:
- **Smart pin SPI** with streamer DMA for hardware-accelerated sector transfers
- **Multi-file handle system** supporting simultaneous file and directory handles (default 6, user-configurable)
- **Per-cog current working directory** for safe multi-cog filesystem navigation
- **Single-writer policy** preventing concurrent write corruption
- **Hardware-accelerated CRC-16** using the P2's `GETCRC` instruction
- **Exported STRUCT types** for named access to SD card registers and FAT32 on-disk structures
- **Conditional compilation** with 7 feature flags for minimal or full builds
- **Next-fit cluster allocation** with wrap-around for efficient free-space reuse
- **Auto-flush on idle** -- worker cog flushes dirty handles after 200ms without commands
- **Defragmentation** -- query fragmentation, compact existing files, create contiguous files
- **Non-blocking file I/O** -- async read/write with poll-based completion

## Architecture

```
  ┌──────────────────────────────────────────────────────────┐
  │  Calling Cog(s) (up to 8)                                │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                  │
  │  │ Cog 0    │ │ Cog 1    │ │ Cog N    │                  │
  │  │ CWD: /   │ │ CWD: /A  │ │ CWD: /B  │                  │
  │  └────┬─────┘ └────┬─────┘ └────┬─────┘                  │
  │       │            │            │                         │
  │       └────────────┼────────────┘                         │
  │                    │ send_command()                        │
  │              ┌─────▼─────┐                                │
  │              │ Mailbox   │  pb_cmd, pb_param0..3          │
  │              │ (Hub RAM) │  pb_status, pb_data0..1        │
  │              └─────┬─────┘                                │
  │                    │                                      │
  │              ┌─────▼─────────────────┐                    │
  │              │ Worker Cog (fs_worker) │                    │
  │              │ - Owns SPI pins       │                    │
  │              │ - Command dispatch    │                    │
  │              │ - FAT32 operations    │                    │
  │              └─────┬─────────────────┘                    │
  │                    │                                      │
  │              ┌─────▼─────┐                                │
  │              │ Smart Pin │  P_TRANSITION (SCK)            │
  │              │ SPI + DMA │  P_SYNC_TX (MOSI)             │
  │              │           │  P_SYNC_RX (MISO)             │
  │              └─────┬─────┘                                │
  │                    │                                      │
  └────────────────────┼──────────────────────────────────────┘
                       │
                 ┌─────▼─────┐
                 │  SD Card  │
                 └───────────┘
```

## Driver Modes

The driver operates in three modes:

| Mode | Value | Set By | Allowed Operations |
|------|-------|--------|--------------------|
| `MODE_NONE` | 0 | Initial state | Only `mount()` or `initCardOnly()` |
| `MODE_RAW` | 1 | `initCardOnly()` | Raw sector read/write only |
| `MODE_FILESYSTEM` | 2 | `mount()` | Full filesystem + raw access |

Filesystem commands are rejected with `E_NOT_MOUNTED` when not in `MODE_FILESYSTEM`.

## Card Presence Detection

The P2 Edge Module microSD socket has no card-detect pin, and the SD specification defines no software-only detection method for SPI mode. The driver uses a behavioral approach: probe the card with CMD0 and analyze the MISO line response.

### How It Works

Before the CMD0 probe, the driver enables a P2 internal 15K pull-up resistor on the MISO pin:

```spin2
wrpin(miso, P_HIGH_15K)       ' Enable 15K pull-up on MISO
pinf(miso)                    ' Float pin (input with pull-up active)
waitus(10)                    ' Let pull-up settle
```

This creates a definitive electrical signal:

| Scenario | MISO Behavior | cmd() Result |
|----------|---------------|-------------|
| Card present | Card drives MISO, responds within 0-8 bytes | Non-zero (typically $01) |
| No card | Pull-up holds MISO high, every byte is $FF | 0 (timeout) |

The driver sends CMD0 up to 5 times, tracking whether any attempt received a non-timeout response. After the retry loop:

- **All timeouts** (MISO never driven): `E_NO_CARD` -- no card is physically present
- **At least one response but not $01**: `E_BAD_RESPONSE` -- card present but not initializing
- **Got $01**: card is present and idle, initialization continues

The pull-up is automatically cleared when the SPI smart pins are configured for normal operation.

### Why P2 Internal Pull-Ups

Every P2 I/O pin has configurable internal pull resistors. The 15K pull-up (`P_HIGH_15K`) is ideal: strong enough for reliable $FF reads with no card, weak enough that any SD card (output impedance under 100 ohms) easily overpowers it. This makes detection self-contained -- no external pull-up resistors are needed on any board design.

For full electrical analysis and SD specification research, see `DOCs/Reference/CARD-PRESENCE-DETECTION.md`.

## Conditional Compilation

The driver uses `#ifdef` / `#endif` blocks to exclude optional features from minimal builds. The core driver compiles to ~24 KB with no flags defined.

### Feature Flags

| Flag | Features Included |
|------|-------------------|
| `SD_INCLUDE_ASYNC` | Non-blocking file I/O: `startReadHandle()`, `startWriteHandle()`, `isComplete()`, `getResult()` |
| `SD_INCLUDE_DEFRAG` | Defragmentation: `fileFragments()`, `compactFile()`, `createFileContiguous()` |
| `SD_INCLUDE_RAW` | Raw sector read/write, `initCardOnly()`, multi-block (CMD18/CMD25) |
| `SD_INCLUDE_REGISTERS` | CID, CSD, SCR, SD Status register access, OCR, VBR read |
| `SD_INCLUDE_SPEED` | CMD6 high-speed mode query and switch (50 MHz) |
| `SD_INCLUDE_DEBUG` | Debug getters, CRC diagnostic methods, display utilities, test hooks |
| `SD_INCLUDE_ALL` | Enables all of the above (not STACK_CHECK) |

### Enabling Flags

Flags are exported from the top-level file using `#pragma exportdef` before the `OBJ` declaration:

```spin2
#pragma exportdef SD_INCLUDE_RAW
#pragma exportdef SD_INCLUDE_REGISTERS

OBJ
  sd : "micro_sd_fat32_fs"
```

Or enable everything:

```spin2
#pragma exportdef SD_INCLUDE_ALL

OBJ
  sd : "micro_sd_fat32_fs"
```

### Build Sizes (v1.5.0, code/data only)

| Configuration | Size |
|---------------|------|
| Core (no flags) | ~21 KB |
| `SD_INCLUDE_ALL` | ~26 KB |

## Worker Cog and Command Protocol

### Mailbox Registers

All cog-to-worker communication flows through shared hub RAM variables:

| Register | Direction | Purpose |
|----------|-----------|---------|
| `pb_cmd` | Caller -> Worker | Command opcode (0 = idle) |
| `pb_param0..3` | Caller -> Worker | Command parameters |
| `pb_caller` | Caller -> Worker | Calling cog's ID (for COGATN wakeup) |
| `pb_status` | Worker -> Caller | Result status code |
| `pb_data0..1` | Worker -> Caller | Result data (handle, count, pointer) |

### Command Flow

1. Caller acquires hardware lock (prevents other cogs from sending commands)
2. Caller writes `pb_param0..3`, `pb_caller := COGID()`, then `pb_cmd := command`
3. Caller sleeps via `WAITATN()` (efficient hardware sleep, not polling)
4. Worker completes command, sets `pb_cmd := CMD_NONE`, wakes caller via `COGATN(1 << pb_caller)`
5. Caller reads `pb_status` and `pb_data0` for results
6. Caller releases hardware lock

### Command Opcodes

**Core Filesystem Commands:**

| Command | Value | Parameters | Returns |
|---------|-------|------------|---------|
| `CMD_MOUNT` | 1 | (pins via DAT) | status |
| `CMD_UNMOUNT` | 2 | -- | status |
| *(3–8 unused)* | 3–8 | *(reserved gaps from removed V1 API)* | -- |
| `CMD_NEWDIR` | 9 | param0=dirname | status |
| `CMD_DELETE` | 10 | param0=filename | status |
| `CMD_RENAME` | 11 | param0=old, param1=new | status |
| `CMD_CHDIR` | 12 | param0=path | status |
| `CMD_READDIR` | 13 | param0=entry index | data0=entry ptr |
| `CMD_FILESIZE` | 14 | -- | data0=file size (unused -- no public caller after V1 removal) |
| `CMD_FREESPACE` | 15 | -- | data0=free sectors |
| `CMD_SYNC` | 16 | -- | status |
| `CMD_MOVEFILE` | 17 | param0=name, param1=dest | status |

**Handle-Based File Commands:**

| Command | Value | Parameters | Returns |
|---------|-------|------------|---------|
| `CMD_OPEN_READ` | 30 | param0=path | data0=handle |
| `CMD_OPEN_WRITE` | 31 | param0=path | data0=handle |
| `CMD_CREATE` | 32 | param0=path | data0=handle |
| `CMD_CLOSE_H` | 33 | param0=handle | status |
| `CMD_READ_H` | 34 | param0=handle, param1=buf, param2=count | data0=bytes |
| `CMD_WRITE_H` | 35 | param0=handle, param1=buf, param2=count | data0=bytes |
| `CMD_SEEK_H` | 36 | param0=handle, param1=position | status |
| `CMD_TELL_H` | 37 | param0=handle | data0=position |
| `CMD_FILESIZE_H` | 38 | param0=handle | data0=size |
| `CMD_SYNC_H` | 39 | param0=handle | status |
| `CMD_SYNC_ALL` | 40 | -- | status |
| `CMD_EOF_H` | 41 | param0=handle | data0=bool |

**Directory Handle Commands:**

| Command | Value | Parameters | Returns |
|---------|-------|------------|---------|
| `CMD_OPEN_DIR` | 43 | param0=path | data0=handle |
| `CMD_READ_DIR_H` | 44 | param0=handle | data0=entry ptr |
| `CMD_CLOSE_DIR_H` | 45 | param0=handle | status |

**Other Core Commands:**

| Command | Value | Parameters | Returns |
|---------|-------|------------|---------|
| `CMD_SET_VOL_LABEL` | 46 | param0=label string | status |

**Conditional Commands:**

| Command | Value | Guard | Purpose |
|---------|-------|-------|---------|
| `CMD_READ_SECTORS` | 18 | `SD_INCLUDE_RAW` | Multi-block read (CMD18) |
| `CMD_WRITE_SECTORS` | 19 | `SD_INCLUDE_RAW` | Multi-block write (CMD25) |
| `CMD_READ_SECTOR_RAW` | 20 | `SD_INCLUDE_RAW` | Single sector read |
| `CMD_WRITE_SECTOR_RAW` | 21 | `SD_INCLUDE_RAW` | Single sector write |
| `CMD_INIT_CARD_ONLY` | 22 | `SD_INCLUDE_RAW` | Raw mode init (no FS) |
| `CMD_GET_CARD_SIZE` | 23 | `SD_INCLUDE_RAW` | Card capacity in sectors |
| `CMD_READ_SCR` | 24 | `SD_INCLUDE_REGISTERS` | Read SCR register |
| `CMD_DEBUG_SLOW_READ` | 25 | `SD_INCLUDE_DEBUG` | Byte-by-byte sector read |
| `CMD_DEBUG_CLEAR_ROOT` | 26 | `SD_INCLUDE_DEBUG` | Clear root directory |
| `CMD_READ_CID` | 27 | `SD_INCLUDE_REGISTERS` | Read CID register |
| `CMD_READ_CSD` | 28 | `SD_INCLUDE_REGISTERS` | Read CSD register |
| `CMD_READ_SD_STATUS` | 29 | `SD_INCLUDE_REGISTERS` | Read SD Status (ACMD13) |
| `CMD_CREATE_CONTIGUOUS` | 47 | `SD_INCLUDE_DEFRAG` | Create file with contiguous chain |
| `CMD_COMPACT_FILE` | 48 | `SD_INCLUDE_DEFRAG` | Defragment existing file |
| `CMD_FILE_FRAGMENTS` | 49 | `SD_INCLUDE_DEFRAG` | Count file fragmentation |

## Handle System

### Unified Handle Pool

File handles and directory handles share a single pool of `MAX_OPEN_FILES` slots (default 6, user-configurable). Each slot can hold either a file or a directory enumeration handle.

### Handle Flags

| Flag | Value | Meaning |
|------|-------|---------|
| `HF_FREE` | 0 | Slot available |
| `HF_READ` | 1 | Open for reading |
| `HF_WRITE` | 2 | Open for writing |
| `HF_DIR` | 4 | Directory enumeration handle |
| `HF_DIRTY` | $80 | Buffer has pending writes (OR'd with mode) |

### Per-Handle State

Each handle slot contains:

| Array | Type | File Use | Directory Use |
|-------|------|----------|---------------|
| `h_flags` | BYTE | HF_READ or HF_WRITE | HF_DIR |
| `h_attr` | BYTE | FAT attributes byte | Directory attributes |
| `h_start_clus` | LONG | First cluster of file | First cluster of directory |
| `h_cluster` | LONG | Current cluster in chain | Current cluster during enum |
| `h_sector` | LONG | Current data sector | Current directory sector |
| `h_position` | LONG | Byte offset in file | Entry index (0-based) |
| `h_size` | LONG | File size in bytes | 0 (unused) |
| `h_dir_sector` | LONG | Sector of directory entry | 0 (unused) |
| `h_dir_offset` | WORD | Offset within dir sector | 0 (unused) |
| `h_buf[512]` | BYTE | Per-handle data buffer | Per-handle sector cache |
| `h_buf_sector` | LONG | Sector in buffer (-1=none) | Sector in buffer (-1=none) |
| `h_prealloc_end` | LONG | Last pre-allocated cluster (defrag only, 0=normal) | 0 (unused) |

### Handle Lifecycle

```
allocateHandle()     Find free slot (h_flags == HF_FREE)
       |
       v
  Populate state     Caller sets h_flags, h_start_clus, h_sector, etc.
       |
       v
  Use handle          readHandle / writeHandle / readDirectoryHandle
       |
       v
  closeFileHandle()   Flush dirty buffer, update dir entry, freeHandle()
  or closeDirectoryHandle()
       |
       v
  freeHandle()        Clear all state, h_flags := HF_FREE
```

### Handle Type Guards

File operations reject directory handles and vice versa:

- `readHandle()`, `writeHandle()`, `seekHandle()`, etc. check `h_flags[handle] & HF_DIR` and return `E_NOT_A_DIR_HANDLE` if set
- `readDirectoryHandle()` checks `h_flags[handle] <> HF_DIR` and returns `E_INVALID_HANDLE` if not a directory handle

### Single-Writer Policy

The driver prevents two handles from writing the same file simultaneously:

1. Each file is uniquely identified by its `(dir_sector, dir_offset)` pair
2. `isFileOpenForWrite()` scans all handles for a matching pair with `HF_WRITE` set
3. `openFileWrite()` and write operations call this check before proceeding
4. Multiple read handles to the same file are allowed
5. Violation returns `E_FILE_ALREADY_OPEN` (-92)

## Per-Cog Current Working Directory

Each P2 cog maintains its own current working directory:

```spin2
DAT
  cog_dir_sec   LONG    0[8]    ' Per-cog CWD sector (one per P2 cog)
```

- Indexed by `pb_caller` (the calling cog's ID)
- Initialized to `root_sec` for all 8 cogs at mount time
- `changeDirectory()` only modifies `cog_dir_sec[pb_caller]`
- `searchDirectory()` reads `cog_dir_sec[pb_caller]` as its starting point
- `readDirectory()` enumerates from `cog_dir_sec[pb_caller]`

This ensures Cog A can `cd /FOLDER1` while Cog B does `cd /FOLDER2` without interference.

## Buffer Management

### Shared Buffers

Three 512-byte shared buffers serve the worker cog's internal operations:

| Buffer | Cache Variable | Purpose |
|--------|---------------|---------|
| `buf` (512 bytes) | `sec_in_buf` | General data sector I/O |
| `dir_buf` (512 bytes) | `dir_sec_in_buf` | Directory sector reads |
| `fat_buf` (512 bytes) | `fat_sec_in_buf` | FAT table reads/writes |

Additionally, `entry_buffer` (32 bytes) holds the most recently read directory entry.

### Per-Handle Buffers

Each handle has its own 512-byte sector buffer:

```spin2
h_buf           BYTE    0[512 * MAX_OPEN_FILES]   ' 512 bytes per handle
h_buf_sector    LONG    0[MAX_OPEN_FILES]          ' Which sector is cached (-1 = none)
```

Per-handle buffers eliminate thrashing when alternating between multiple open files. The pointer to a handle's buffer is `@h_buf + (handle * 512)`.

### Memory Cost

| Component | Size |
|-----------|------|
| Shared buffers (buf + dir_buf + fat_buf) | 1,536 bytes |
| Entry buffer | 32 bytes |
| Per-handle state (32 bytes x 6) | 192 bytes |
| Per-handle buffers (512 bytes x 6) | 3,072 bytes |
| Per-cog CWD (8 LONGs) | 32 bytes |
| Worker cog stack | ~512 bytes |
| **Total (6 handles, default)** | **~5,376 bytes** |

### Choosing the Handle Count

The default `MAX_OPEN_FILES = 6` was established after directory handles were unified into the file handle pool. With the unified pool now serving both file and directory operations, the right count depends on how many cogs will perform file I/O concurrently and what each cog does.

**Per-cog handle demand.** A cog consumes one handle for each file or directory it has open at the same time. Handles represent reserved state (position, buffer, cluster chain) — the worker cog still serializes actual I/O, so handles don't create parallelism, they create *concurrency of open resources*.

| Usage Pattern | Handles Needed |
|---------------|----------------|
| Read or write a single file | 1 |
| Copy operation (read source + write destination) | 2 |
| Single file + directory enumeration | 2 |
| File copy + directory browsing | 3 |

**Sizing formula.** Count the cogs that will have files or directories open simultaneously (*N*), estimate each cog's peak handle demand, and add headroom for transient opens (e.g., a cog briefly opening a config file):

```
MAX_OPEN_FILES = (N × peak_handles_per_cog) + headroom
```

**Example scenarios** for 2–3 active cogs in an 8-cog system (1 cog reserved for the SD worker):

| Scenario | Cogs | Per-Cog | Headroom | Total |
|----------|------|---------|----------|-------|
| 2 cogs, each reads one file | 2 | 1 | +1 | 3 |
| 2 cogs, each does file copy | 2 | 2 | +1 | 5 |
| 2 cogs copying + dir scan | 2 | 3 | +1 | 7 |
| 3 cogs, single file + dir each | 3 | 2 | +1 | 7 |
| 3 cogs, each does file copy | 3 | 2 | +2 | 8 |

**Incremental memory cost** for additional handles (544 bytes each: 32 bytes state + 512 bytes buffer):

| MAX_OPEN_FILES | Handle Memory | Delta from 4 |
|----------------|---------------|--------------|
| 4 (old default) | 2,176 bytes | — |
| 6 (recommended) | 3,264 bytes | +1,088 |
| 8 | 4,352 bytes | +2,176 |
| 10 | 5,440 bytes | +3,264 |

**Recommended default: 6.** This covers the common case of 2–3 cogs with mixed file and directory operations, providing 2 handles per active cog plus room for a directory enumeration or transient open. The cost is 1,088 bytes above the previous default — a modest investment from the P2's 512KB hub RAM that avoids `E_TOO_MANY_FILES` errors during normal multi-cog operation. Applications with a single file-using cog can reduce to 2 or 3; applications where every cog does file I/O should size to their actual peak demand.

To override, define `MAX_OPEN_FILES` in the top-level object's CON block before the OBJ declaration:

```spin2
CON
  MAX_OPEN_FILES = 8          ' 3 cogs doing file copy + headroom

OBJ
  sd : "micro_sd_fat32_fs"
```

## SPI Implementation

### Smart Pin Configuration

The driver uses three smart pin modes for SPI mode 0 (CPOL=0, CPHA=0):

| Pin | Smart Pin Mode | Purpose |
|-----|---------------|---------|
| SCK | `P_TRANSITION | P_OE` | Clock generation, idle LOW |
| MOSI | `P_SYNC_TX | P_OE | P_PLUS2_B` | Synchronized transmit, clocked by SCK |
| MISO | `P_SYNC_RX | P_PLUS3_B` | Synchronized receive, clocked by SCK |

The `P_PLUS2_B` and `P_PLUS3_B` selectors route the SCK signal to the TX and RX pins respectively, based on the pin assignments (MISO, MOSI, CS, SCK are consecutive pins).

### Frequency Control

`setSPISpeed(freq)` calculates the SCK half-period using ceiling division to ensure the actual frequency never exceeds the target:

```
half_period = ceil(clkfreq / (freq * 2))
            = (clkfreq + (freq * 2) - 1) / (freq * 2)
```

The half-period is clamped to a minimum of 4 system clocks (the hardware minimum for reliable smart pin transitions). This means the maximum achievable SPI frequency depends on `clkfreq`:

- At 320 MHz: max SPI = 320/(4*2) = 40 MHz, but SD spec caps at 25 MHz
- At 200 MHz: half_period=4 yields exactly 25 MHz
- Below 200 MHz: SPI drops below 25 MHz (e.g., 160 MHz -> 20 MHz)

The driver starts at 400 kHz for card initialization (SD specification requirement), then `setOptimalSpeed()` switches to the card's maximum speed (up to 25 MHz) after init.

### Streamer DMA

Sector transfers use the P2's streamer engine for hardware-accelerated bulk data movement:

**Read (512 bytes from card):**
```
xinit  stream_mode, init_phase   ' Start RX streamer
waitxfi                          ' Wait for 512 bytes received
```

**Write (512 bytes to card):**
```
rdfast #0, p_buf                 ' Setup hub read pointer
xinit  stream_mode, #0           ' Start TX streamer
wypin  clk_count, sck            ' Generate clock pulses
waitxfi                          ' Wait for completion
```

The streamer transfers data between hub RAM and the SPI pins at the full SPI clock rate, without per-byte cog intervention.

## Card Identification and Adaptive Timing

After card initialization completes (CMD0/CMD8/ACMD41/CMD58), the driver reads two card registers to configure itself for the specific card inserted:

### What the Driver Reads

**CID register** (16 bytes, via CMD10): Contains manufacturer identity. The driver extracts the manufacturer ID byte (byte 0) to identify the card brand.

**CSD register** (16 bytes, via CMD9): Contains the card's electrical and timing characteristics. The driver extracts three fields:

| CSD Field | Location | What It Tells Us |
|-----------|----------|-----------------|
| TRAN_SPEED | Byte 3 | Maximum SPI clock frequency the card supports |
| TAAC + NSAC | Bytes 1-2 | Read access time (how long a read operation may take) |
| R2W_FACTOR | Byte 12, bits [4:2] | Write-to-read timeout ratio (writes take longer than reads) |

### How the Driver Uses This Data

**SPI clock speed** (`card_max_speed_hz`): TRAN_SPEED is a two-part encoded field -- a time value multiplier (bits [6:3]) and a rate unit (bits [2:0]). The driver decodes this to get the card's maximum transfer rate in Hz. Most SDHC/SDXC cards report 25 MHz. The SPI clock is set to the lesser of the card's reported maximum and 25 MHz (the SD SPI mode ceiling).

**Read timeouts** (`card_read_timeout_ms`): Used by `readSector()` and `waitDataToken()` when waiting for the card to deliver data. If the card doesn't respond within this window, the operation returns `E_TIMEOUT`.

- SDHC/SDXC (CSD v2.0): Fixed at 100ms per specification
- SDSC (CSD v1.0): Calculated from TAAC and NSAC with a 100x safety factor, minimum 100ms

**Write timeouts** (`card_write_timeout_ms`): Used by `writeSector()` and `waitBusyComplete()` when waiting for the card to finish programming flash. Write timeouts are longer than read timeouts because flash programming is inherently slower than reading.

- SDHC/SDXC: Fixed at 500ms (2x the 250ms spec value, for margin on cold writes and sector 0)
- SDSC: Read timeout multiplied by 2^R2W_FACTOR, clamped to 250ms-1000ms

### Fallback Defaults

If CID or CSD reads fail (rare but possible on marginal cards), the driver uses safe defaults:

| Parameter | Default | Rationale |
|-----------|---------|-----------|
| `card_max_speed_hz` | 25 MHz | SD SPI mode maximum |
| `card_read_timeout_ms` | 100 ms | SDHC spec value |
| `card_write_timeout_ms` | 500 ms | Conservative margin |

## Multi-Sector Operations

### CMD18 (READ_MULTIPLE_BLOCK)

`readSectors(start_sector, count, p_buffer)` reads consecutive sectors in a single command:

1. Send CMD18 with starting sector address
2. For each sector: wait for `$FE` token, streamer-receive 512 bytes, validate CRC
3. Send CMD12 (STOP_TRANSMISSION) to end the transfer
4. Verify card status with CMD13

### CMD25 (WRITE_MULTIPLE_BLOCK)

`writeSectors(start_sector, count, p_buffer)` writes consecutive sectors:

1. Send CMD25 with starting sector address
2. For each sector: send `$FC` token, streamer-transmit 512 bytes + CRC, wait for card busy
3. Send `$FD` stop token, wait for final programming
4. Verify card status with CMD13

Multi-sector operations are significantly faster than single-sector loops because they eliminate per-sector command overhead and allow the card's internal controller to optimize flash writes for sequential access.

## CRC-16 Validation

The driver validates data integrity using CRC-16-CCITT on every sector transfer:

```spin2
PRI calcDataCRC(pData, len) : crc | raw
  raw := GETCRC(pData, CRC_POLY_REFLECTED, len)
  crc := ((raw ^ CRC_BASE_512) REV 31) >> 16
```

- Uses the P2's hardware `GETCRC` instruction (no lookup table needed)
- `CRC_POLY_REFLECTED` ($8408) is the CRC-16-CCITT polynomial in LSB-first form
- `CRC_BASE_512` ($2C68) compensates for `GETCRC` initialization differences
- The `REV 31` + `>> 16` converts from reflected to standard bit order
- CRC validation is enabled by default (`diag_crc_enabled` = 1)
- **Reads:** Card sends CRC after 512 data bytes; driver calculates CRC from received data and compares
- **Writes:** Driver calculates CRC from data and sends it after the 512 data bytes

Match/mismatch counters and the `setCRCValidation()` toggle are available via `SD_INCLUDE_DEBUG` (see Conditional Compilation).

## Cluster Allocation

### Next-Fit Strategy

The driver uses a next-fit allocator rather than first-fit. After each allocation, `fsi_nxt_free` records the next cluster number to try, so sequential file writes don't re-scan from the beginning of the FAT. This reduces FAT sector reads from O(N) to O(1) for typical sequential writes.

### Allocation Flow

1. Choose starting scan position:
   - If extending an existing chain: start after the previous cluster
   - If starting a new chain: use the `fsi_nxt_free` hint from FSInfo
   - Fallback: cluster 2 (first data cluster)
2. Scan forward through the FAT looking for a zero (free) entry
3. If the scan reaches the end of the FAT without finding a free cluster, wrap to cluster 2 and continue
4. If the scan returns to the starting position after wrapping, the disk is full (`E_DISK_FULL`)
5. When a free cluster is found: mark it as EOC (`$0FFFFFFF`), link the previous cluster if extending, write both FAT copies, update `fsi_nxt_free` and `fsi_free_count`

### FSInfo Tracking

The driver maintains `fsi_free_count` and `fsi_nxt_free` incrementally during operation (rather than scanning the entire FAT). Both are persisted to the FSInfo sector at unmount.

## Auto-Flush on Idle

The worker cog monitors idle time between commands. When no command arrives for 200ms (`IDLE_FLUSH_MS`), the worker scans all handles for dirty buffers and flushes them to disk:

1. Worker polls `pb_cmd` in its main loop
2. Between polls, a clock counter tracks elapsed idle time
3. If `(getct() - idle_timer) >= idle_flush_clocks` and no command pending:
   - Scan all handles for `HF_DIRTY` flag
   - For each dirty handle: write the sector buffer to disk, update the directory entry with the current file size and timestamp, clear `HF_DIRTY`
4. Reset the idle timer after flush or after any command completes

This ensures data reaches the card even if the application forgets to call `syncHandle()` or `closeFileHandle()`. The 200ms threshold is short enough for data safety but long enough that it doesn't interfere with normal write bursts.

## Defragmentation

*Requires `SD_INCLUDE_DEFRAG`.*

FAT32 allocates clusters on demand, so files written over time may end up with clusters scattered across the disk. The defragmentation API provides three operations: query fragmentation, compact existing files, and create pre-allocated contiguous files.

### Fragment Counting

`fileFragments(path)` walks a file's FAT chain and counts transitions where `next_cluster != current_cluster + 1`. A contiguous file has fragment count 1. An empty file returns 0.

### Compacting an Existing File (compactFile)

`compactFile(path)` relocates a fragmented file's clusters into a contiguous chain using a copy-then-free strategy. The file must be closed (no open handles). The process:

1. **Find** the file and verify it is not open (`isFileOpenAny`)
2. **Skip** if empty or already contiguous (fragment count = 1)
3. **Count** total clusters by walking the FAT chain
4. **Find** a contiguous run of N free clusters via `findContiguousRun()` -- linear scan from cluster 2
5. **Copy** each cluster from old location to new contiguous location (`copyClusterData`)
6. **Verify** read-back of every copied cluster, byte-by-byte comparison (`verifyClusterCopy`). If any mismatch is found, the operation aborts with `E_VERIFY_FAILED` -- the original data is still intact
7. **Build** new FAT chain: sequential links (3->4->5->...->EOC) via `allocateContiguousChain`
8. **Update** directory entry to point to new first cluster
9. **Free** old cluster chain
10. **Invalidate** all sector caches

The copy-then-free ordering ensures the original data is always intact until verification succeeds. If power is lost during compaction, the original chain is still valid (the new chain is not linked from the directory until step 8).

### Creating a Contiguous File (createFileContiguous)

`createFileContiguous(path, file_size)` creates a new empty file with a pre-allocated contiguous cluster chain. This is useful for data logging and streaming where fragmentation must be avoided:

1. Calculate clusters needed: `ceil(file_size / bytes_per_cluster)`
2. Find a contiguous run via `findContiguousRun()`
3. Allocate the chain via `allocateContiguousChain()`
4. Create the directory entry with the first cluster set
5. Return a write handle with `h_prealloc_end` set to the last pre-allocated cluster

When `h_prealloc_end` is non-zero, `writeHandle()` skips the normal `allocateCluster()` path at cluster boundaries. Instead, it simply advances to the next sequential cluster (which is already allocated). This eliminates FAT reads/writes during the write path, improving write throughput. If writes exceed the pre-allocated space, the write returns 0 bytes written.

### Shared Helpers

`compactFile` and `createFileContiguous` share two low-level helpers:

- **`findContiguousRun(count)`** -- linear scan from cluster 2 looking for N consecutive free FAT entries. Returns the first cluster of the run or `E_NO_CONTIGUOUS_SPACE`.
- **`allocateContiguousChain(first, count)`** -- marks a sequential run of clusters as a linked chain in both FAT copies, with the last entry set to EOC.

## Non-Blocking File I/O

*Requires `SD_INCLUDE_ASYNC`.*

The standard `readHandle()` and `writeHandle()` block the caller via `WAITATN` until the worker completes. For applications where the calling cog must keep running (sensor polling, control loops, display updates), the async API provides non-blocking alternatives.

### How It Works

The async API reuses the existing command protocol but skips the `WAITATN` sleep:

1. **`startReadHandle()` / `startWriteHandle()`** -- acquires the API lock, writes mailbox parameters, sets `pb_cmd`, then returns immediately with `PENDING` (1). The lock is held throughout the operation.
2. **`isComplete()`** -- polls `pb_cmd == CMD_NONE` (the worker clears `pb_cmd` when done). Returns TRUE/FALSE without blocking.
3. **`getResult()`** -- waits if needed, reads the result from `pb_status`/`pb_data0`, releases the lock, and drains any stale `COGATN`. After this call, new commands can be issued.
4. **`cancelAsync()`** -- waits for the worker to finish (cannot interrupt SPI mid-transfer), discards the result, and releases the lock.

### Constraints

- Only one async operation can be in flight at a time (`E_ASYNC_BUSY` if a second is attempted)
- The API lock is held for the entire duration, so no other cog can issue commands until `getResult()` or `cancelAsync()` is called
- The caller must not modify the data buffer while the async write is in progress
- `SD_INCLUDE_ASYNC` is not part of `SD_INCLUDE_ALL` -- it must be enabled separately

## Exported STRUCT Types

The driver defines and exports packed struct types (requires `{Spin2_v45}`) for named access to SD card registers and FAT32 on-disk structures. Consumer objects access them via the `sd.` prefix (e.g., `sd.cid_t`, `sd.dir_entry_t`).

### SD Card Register Structs

| Struct | Size | Purpose |
|--------|------|---------|
| `cid_t` | 16 bytes | CID register: manufacturer ID, product name, serial number, manufacturing date |
| `csd_t` | 16 bytes | CSD register: card capacity, speed class, timing parameters |
| `scr_t` | 8 bytes | SCR register: SD spec version, bus widths, security features |

### FAT32 On-Disk Structure Structs

| Struct | Size | Purpose |
|--------|------|---------|
| `dir_entry_t` | 32 bytes | Directory entry: name, ext, attributes, timestamps, cluster, file size |
| `mbr_partition_t` | 16 bytes | MBR partition table entry: boot flag, type, LBA start/size |
| `vbr_t` | 512 bytes | Volume Boot Record (BPB): bytes/sector, clusters, FAT layout, volume label |
| `fsinfo_t` | 512 bytes | FSInfo sector: free cluster count, next free hint, signatures |

### Usage Pattern

Structs are overlaid onto buffers via typed pointers:

```spin2
OBJ
  sd : "micro_sd_fat32_fs"

PRI parseCID(p_buf)
  ' Overlay struct onto raw buffer
  sd.cid_t pCid := @p_buf
  debug("Manufacturer: ", uhex_byte_(pCid.mid))
  debug("Product: ", lstr_(@pCid.pnm, 5))
```

All structs are packed (Spin2 default) with offsets matching their respective hardware or on-disk layouts exactly. SD card register structs are big-endian (as received from card); FAT32 structs are little-endian (native P2 byte order).

## Error Codes

| Error | Value | Meaning |
|-------|-------|---------|
| `E_TIMEOUT` | -1 | Card didn't respond in time |
| `E_NO_RESPONSE` | -2 | Card not responding |
| `E_BAD_RESPONSE` | -3 | Unexpected response from card |
| `E_CRC_ERROR` | -4 | Data CRC mismatch |
| `E_WRITE_REJECTED` | -5 | Card rejected write operation |
| `E_CARD_BUSY` | -6 | Card busy timeout |
| `E_IO_ERROR` | -7 | General I/O error |
| `E_NO_CARD` | -8 | No card detected in slot |
| `E_NOT_MOUNTED` | -20 | Filesystem not mounted |
| `E_INIT_FAILED` | -21 | Card initialization failed |
| `E_NOT_FAT32` | -22 | Card not formatted as FAT32 |
| `E_BAD_SECTOR_SIZE` | -23 | Sector size not 512 bytes |
| `E_FILE_NOT_FOUND` | -40 | File doesn't exist |
| `E_FILE_EXISTS` | -41 | File already exists |
| `E_NOT_A_FILE` | -42 | Expected file, found directory |
| `E_NOT_A_DIR` | -43 | Expected directory, found file |
| `E_FILE_NOT_OPEN` | -45 | File not open |
| `E_END_OF_FILE` | -46 | Read past end of file |
| `E_DISK_FULL` | -60 | No free clusters available |
| `E_NO_CONTIGUOUS_SPACE` | -61 | No contiguous run of sufficient length (defrag) |
| `E_FILE_OPEN_FOR_COMPACT` | -62 | File is open, cannot compact (defrag) |
| `E_VERIFY_FAILED` | -63 | Read-back verification failed after compact (defrag) |
| `E_NO_LOCK` | -64 | Could not acquire hardware lock |
| `E_TOO_MANY_FILES` | -90 | All handle slots in use |
| `E_INVALID_HANDLE` | -91 | Handle out of range or not open |
| `E_FILE_ALREADY_OPEN` | -92 | File already open for writing |
| `E_NOT_A_DIR_HANDLE` | -93 | Wrong handle type for operation |
| `E_ASYNC_BUSY` | -95 | An async operation is already in flight |
| `E_NO_ASYNC_OP` | -96 | No async operation to get result from |

## Public API Summary

### Core API (always compiled)

**Lifecycle:**

| Method | Description |
|--------|-------------|
| `mount(cs, mosi, miso, sck)` | Initialize card and mount filesystem |
| `unmount()` | Flush all handles, update FSInfo, unmount |
| `stop()` | Stop worker cog and release hardware lock |
| `error()` | Last error code for calling cog |
| `checkStackGuard() : bIntact` | Verify worker cog stack guard is intact |

**Handle-Based File Operations:**

| Method | Description |
|--------|-------------|
| `openFileRead(pPath) : handle` | Open existing file for reading |
| `openFileWrite(pPath) : handle` | Open existing file for append writing |
| `createFileNew(pPath) : handle` | Create new file for writing |
| `readHandle(handle, pBuf, count) : bytes` | Read bytes from file |
| `writeHandle(handle, pBuf, count) : bytes` | Write bytes to file |
| `seekHandle(handle, position) : result` | Seek to byte position |
| `tellHandle(handle) : position` | Get current byte position |
| `eofHandle(handle) : bool` | Check if at end of file |
| `fileSizeHandle(handle) : size` | Get file size in bytes |
| `syncHandle(handle) : result` | Flush pending writes |
| `syncAllHandles() : result` | Flush all open handles |
| `closeFileHandle(handle) : result` | Close handle, flush writes |

**File Management:**

| Method | Description |
|--------|-------------|
| `deleteFile(pName) : result` | Delete file or empty directory |
| `rename(pOld, pNew) : result` | Rename file or directory |
| `moveFile(pName, pDest) : result` | Move file to directory |

**Directory Operations:**

| Method | Description |
|--------|-------------|
| `changeDirectory(pPath) : result` | Change calling cog's CWD |
| `newDirectory(pName) : result` | Create new directory |
| `readDirectory(entry) : pEntry` | Enumerate CWD by index |
| `openDirectory(pPath) : handle` | Open directory for handle-based enumeration |
| `readDirectoryHandle(handle) : pEntry` | Read next directory entry |
| `closeDirectoryHandle(handle)` | Close directory handle |

**Information:**

| Method | Description |
|--------|-------------|
| `freeSpace() : sectors` | Free space in 512-byte sectors |
| `sectorsPerCluster() : count` | Sectors per cluster (power of 2: 1..128), 0 if not mounted |
| `volumeLabel() : pStr` | Pointer to volume label string |
| `setVolumeLabel(pLabel) : result` | Set volume label |
| `fileName() : pStr` | Name from last directory read |
| `fileSize() : size` | File size from last directory read |
| `attributes() : attr` | Attributes from last directory read |
| `setDate(y,m,d,h,mi,s)` | Set date/time for new files |
| `getDate() : y, m, d, h, mi, s` | Get current clock (auto-increments from last `setDate()`) |
| `getSPIFrequency() : hz` | Current SPI clock frequency |
| `getCardMaxSpeed() : hz` | Card's reported max speed from CSD |
| `getManufacturerID() : mid` | Card manufacturer ID byte |
| `getReadTimeout() : ms` | Read timeout from CSD |
| `getWriteTimeout() : ms` | Write timeout from CSD |
| `isHighSpeedActive() : bool` | True if running at 50 MHz |

**Utilities:**

| Method | Description |
|--------|-------------|
| `setSPISpeed(freq)` | Set SPI clock frequency in Hz |
| `syncDirCache()` | Invalidate directory sector cache |
| `sync() : result` | Flush all pending writes |

### SD_INCLUDE_RAW

| Method | Description |
|--------|-------------|
| `initCardOnly(cs, mosi, miso, sck)` | Initialize card without mounting filesystem |
| `cardSizeSectors() : sectors` | Total 512-byte sectors on card |
| `readSectorRaw(sector, pBuf) : result` | Read sector at absolute LBA |
| `writeSectorRaw(sector, pBuf) : result` | Write sector at absolute LBA |
| `readSectorsRaw(start, count, pBuf) : sectors` | Multi-block read (CMD18) |
| `writeSectorsRaw(start, count, pBuf) : sectors` | Multi-block write (CMD25) |
| `testCMD13() : r2` | Send CMD13, return raw R2 response |

### SD_INCLUDE_REGISTERS

| Method | Description |
|--------|-------------|
| `readCIDRaw(pBuf) : result` | Read 16-byte CID register |
| `readCSDRaw(pBuf) : result` | Read 16-byte CSD register |
| `readSCRRaw(pBuf) : result` | Read 8-byte SCR register |
| `readSDStatusRaw(pBuf) : result` | Read 64-byte SD Status register (ACMD13) |
| `getOCR() : ocr` | Get cached OCR value |
| `readVBRRaw(pBuf) : result` | Read 512-byte Volume Boot Record |

### SD_INCLUDE_SPEED

| Method | Description |
|--------|-------------|
| `attemptHighSpeed() : bool` | Switch to 50 MHz with verification |
| `checkCMD6Support() : bool` | Check if card supports CMD6 |
| `checkHighSpeedCapability() : bool` | Query high-speed capability |

### SD_INCLUDE_DEBUG

| Method | Description |
|--------|-------------|
| `getLastCMD13() : r2` | Last CMD13 R2 response word |
| `getLastCMD13Error() : r2` | Last non-zero CMD13 result |
| `getLastReceivedCRC() : crc` | CRC-16 received from card |
| `getLastCalculatedCRC() : crc` | CRC-16 calculated from data |
| `getLastSentCRC() : crc` | CRC-16 sent with last write |
| `getCRCMatchCount() : count` | CRC match count |
| `getCRCMismatchCount() : count` | CRC mismatch count |
| `getCRCRetryCount() : count` | CRC retry count |
| `setCRCValidation(enabled)` | Enable/disable CRC checking |
| `getWriteDiag() : result_code, r1_resp, data_resp, sector_num` | Last write diagnostic data |
| `setTestForceReadError(count)` | Inject N forced CRC mismatches on reads (test hook) |
| `setTestForceWriteError(enabled)` | Inject one-shot write CRC corruption (test hook) |
| `getTestErrorCount() : count` | Count of injected test errors triggered |
| `clearTestErrors()` | Reset all test error injection state |
| `debugGetRootSec() : sector` | Root directory sector |
| `debugGetDirSec() : sector` | Calling cog's directory sector |
| `debugGetVbrSec() : sector` | VBR sector |
| `debugGetFatSec() : sector` | FAT start sector |
| `debugGetSecPerFat() : count` | Sectors per FAT |
| `debugDumpRootDir()` | Print root entries to debug |
| `debugClearRootDir() : result` | Zero root directory (destructive) |
| `debugReadSectorSlow(sector, pBuf) : result` | Byte-by-byte read (no streamer) |
| `debugGetReadSectorDiag(...)` | Last readSector diagnostic data |
| `debugGetReadSectorDiagExt(...)` | Extended diagnostic data |
| `displaySector()` | Hex dump of sector buffer |
| `displayEntry()` | Hex dump of directory entry |
| `displayFAT(cluster)` | Hex dump of FAT sector |
| `setTestMaxClusters(max)` | Set artificial cluster limit (disk-full testing) |

### SD_INCLUDE_DEFRAG

| Method | Description |
|--------|-------------|
| `fileFragments(pPath) : count` | Count non-contiguous fragments (1 = contiguous, 0 = empty) |
| `isFileContiguous(pPath) : bool` | TRUE if file has exactly 1 fragment |
| `createFileContiguous(pPath, size) : handle` | Create new file with pre-allocated contiguous chain |
| `compactFile(pPath) : result` | Relocate file clusters into contiguous chain (file must be closed) |

### SD_INCLUDE_ASYNC

| Method | Description |
|--------|-------------|
| `startReadHandle(handle, pBuf, count) : status` | Begin non-blocking read, returns PENDING |
| `startWriteHandle(handle, pBuf, count) : status` | Begin non-blocking write, returns PENDING |
| `isComplete() : bool` | Poll whether async operation has finished |
| `getResult() : result` | Get result and release lock (bytes read/written or error) |
| `cancelAsync() : result` | Wait for completion, discard result, release lock |

---

*Part of the [P2 microSD Filesystem](../README.md) project - Iron Sheep Productions*
