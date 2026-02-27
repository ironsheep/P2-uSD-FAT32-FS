# SD Card Driver Memory Footprint Analysis

**Driver**: `micro_sd_fat32_fs.spin2` v1.1.0 (post-v1.0.0, commit `05fc726`)
**Compiler**: pnut-ts v1.52.1
**Date**: Feb 27, 2026

---

## 1. Driver Object Size — Code vs Data

The driver is compiled standalone (as top-level via `PUB null()`), without debug enabled (`DEBUG_DISABLE = 1`).

### Minimal Build (no optional features)

No `SD_INCLUDE_*` flags defined — core filesystem operations only.

| Region | Address Range | Size | Description |
|---|---|---|---|
| Method table | `$00000`–`$00277` | **632 B** | 158 entries (157 methods + header) × 4 bytes |
| DAT (static data) | `$00278`–`$018D6` | **5,727 B** | Singleton state, buffers, handle tables |
| Bytecodes (code) | `$018D7`–`$05121` | **14,411 B** | Spin2 bytecode for 157 methods |
| **Object total** | | **20,770 B** | (20,772 with alignment) |
| VAR (runtime) | | **4 B** | Minimal — driver uses DAT for singleton state |

**Binary file**: 26,984 bytes (20,772 object + 6,212 P2 loader stub)

### Full Build (SD_INCLUDE_ALL)

All optional features enabled: raw sector access, card registers, high-speed mode, debug getters.

| Region | Address Range | Size | Description |
|---|---|---|---|
| Method table | `$00000`–`$0033B` | **828 B** | 207 entries (206 methods + header) × 4 bytes |
| DAT (static data) | `$0033C`–`$0199A` | **5,727 B** | Identical to minimal — same static state |
| Bytecodes (code) | `$0199B`–`$05AC9` | **16,687 B** | Spin2 bytecode for 206 methods |
| **Object total** | | **23,242 B** | (23,244 with alignment) |
| VAR (runtime) | | **4 B** | Same as minimal |

**Binary file**: 29,456 bytes (23,244 object + 6,212 P2 loader stub)

### Comparison

| | Minimal | Full | Delta |
|---|---|---|---|
| **Methods** | 157 | 206 | **+49** |
| **Method table** | 632 B | 828 B | +196 B |
| **DAT (data)** | 5,727 B | 5,727 B | **+0 B** |
| **Bytecodes (code)** | 14,411 B | 16,687 B | +2,276 B |
| **Object total** | 20,772 B | 23,244 B | **+2,472 B (+12%)** |
| **Binary (.bin)** | 26,984 B | 29,456 B | +2,472 B |
| **VAR** | 4 B | 4 B | +0 B |

**Key finding**: The DAT section is identical in both builds. All optional features add only code (method table entries + bytecodes). The conditional compilation gates only affect methods, not static data.

---

## 2. DAT Section Breakdown (5,727 bytes)

All static data lives in DAT because the driver is a singleton (one worker cog, shared state).

| Category | Size | Details |
|---|---|---|
| **Worker cog infrastructure** | 580 B | Cog ID (4), lock (4), mode (4), CMD13 state (4), mailbox (36), cog stack (512), stack guard (16) |
| **SPI pin configuration** | 44 B | CS/MOSI/MISO/SCK pin numbers (16), clock/TX/RX modes (12), period, freq, event, smartpin flag, debug counter |
| **Filesystem state** | 116 B | FAT/FAT2 sector addresses, sectors-per-FAT/cluster, root sector, cluster offset, per-cog CWD (`cog_dir_sec[8]`), entry address, date stamp, current sector/file index, flags, buffer tracking (`dir_sec_in_buf`, `fat_sec_in_buf`, `sec_in_buf`), bit delay, HCS, FSInfo sector/free count/next hint, VBR sector |
| **Card identification** | 24 B | OCR, manufacturer ID, max speed, slow flag, read/write timeouts |
| **Per-cog error storage** | 32 B | `last_error[8]` — one LONG per possible cog |
| **Diagnostic state** | 87 B | Last sector/buftype/token, buffer bytes, SPI period, CRC recv/calc/sent, match/mismatch/retry counters, CRC enabled flag, write result/R1/dresp/sector |
| **Sector caches** (×3) | **1,536 B** | `dir_buf` (512), `fat_buf` (512), `buf` (512) |
| **Directory entry + label** | 44 B | `entry_buffer` (32 B, typed as `dir_entry_t`), `vol_label` (12 B) |
| **Handle tables** (6 handles) | **3,264 B** | Per-handle: flags (1), attr (1), dir_offset (2), position (4), sector (4), start_clus (4), size (4), dir_sector (4), cluster (4), **buffer (512)**, buf_sector (4) = 544 B × 6 |
| **Total** | **5,727 B** | |

### Largest DAT consumers

```
Handle buffers (h_buf, 6 × 512):  3,072 B   53.6%
Sector caches (3 × 512):          1,536 B   26.8%
Worker cog stack (128 LONGs):        512 B    8.9%
Everything else:                     607 B   10.6%
```

The **per-handle 512-byte buffers** dominate. With the default 6 handles, `h_buf` alone is 3 KB. Users who override `MAX_OPEN_FILES` to fewer handles save 544 bytes per handle eliminated.

---

## 3. Real-World Program Sizes

These are actual consumer programs that include the driver as an OBJ. All compiled without debug unless noted.

### SD_format_card (format utility — no debug)

| Object | Code/Data | VAR | Purpose |
|---|---|---|---|
| SD_format_card | 48 B | 4 B | Top-level (calls `fmt.format()`) |
| isp_format_utility | 3,808 B | 33,852 B | Format logic (32 KB CMD25 zero buffer in VAR) |
| **micro_sd_fat32_fs** | **23,242 B** | **4 B** | **The driver (SD_INCLUDE_ALL)** |
| isp_string_fifo | 2,443 B | 4 B | SPSC FIFO for cog-to-cog strings |
| isp_mem_strings | 1,755 B | 12 B | Printf-style formatting |
| **Totals** | **31,300 B** | **33,876 B** | |

**Binary**: 37,512 bytes
**Hub RAM at runtime**: 65,176 bytes (63.6 KB of P2's 512 KB)

The format utility's 33,852 B VAR is dominated by a 32 KB (`MULTI_BATCH_SIZE × 512 = 64 × 512`) zero buffer used for CMD25 batch sector clearing.

### SD_card_characterize (card onboarding — no debug)

**Binary**: 33,596 bytes

### SD_demo_shell (interactive terminal — no debug)

| Object | Code/Data | VAR (est.) | Purpose |
|---|---|---|---|
| SD_demo_shell | 12,074 B | — | Shell commands, input parsing |
| micro_sd_fat32_fs | 1,657 B | 4 B | Driver (shell's own instance, minimal) |
| isp_serial_singleton | 10,338 B | — | Full-duplex serial terminal |
| isp_format_utility | 3,808 B | 33,852 B | Card formatting |
| isp_fsck_utility | 23,242 B | ~264 KB | FSCK (includes driver + **256 KB bitmap**) |
| isp_string_fifo | 2,443 B | 4 B | Cog output FIFO |
| isp_mem_strings | 1,755 B | 12 B | Printf-style formatting |
| **Totals** | **55,328 B** | **331,876 B** | |

**Binary**: 61,540 bytes
**Hub RAM at runtime**: 387,204 bytes (378 KB of P2's 512 KB)

The demo shell is the largest consumer because `isp_fsck_utility` allocates a 256 KB cluster bitmap (`BITMAP_LONGS = 65,536` LONGs) in VAR. This is the windowed bitmap for FSCK on large cards.

### Regression tests (with debug, compiled via `pnut-ts -d`)

| Test Program | Binary | Features Used |
|---|---|---|
| SD_RT_format_tests | 50,005 B | SD_INCLUDE_ALL + format + fsck + test framework |
| SD_RT_file_ops_tests | 40,511 B | SD_INCLUDE_RAW + SD_INCLUDE_DEBUG |
| SD_RT_mount_tests | 37,113 B | SD_INCLUDE_RAW + SD_INCLUDE_DEBUG |

Debug builds are larger because the `-d` flag enables `debug()` string data and debug records throughout the test code (the driver itself still has `DEBUG_DISABLE = 1`).

---

## 4. Summary — Driver Footprint at a Glance

```
                              Code      Data      Total Object    VAR
                             ------    ------    ------------    -----
Minimal (core only):        15,043 B   5,727 B     20,772 B      4 B
Full (SD_INCLUDE_ALL):      17,515 B   5,727 B     23,244 B      4 B
                             ------    ------    ----------      -----
Optional features add:      +2,472 B      +0 B     +2,472 B     +0 B
```

**Code** = method table + Spin2 bytecodes (the executable logic).
**Data** = DAT section (static state: buffers, handle tables, pin config, cog stack).

The driver object contributes **23.2 KB** (full build) to any consumer program's code/data. The runtime VAR cost is negligible (4 bytes) because all driver state lives in DAT.

The two biggest memory consumers across all configurations are:
1. **Handle buffers** — 3,072 B in DAT (6 × 512 B per-handle sector buffers)
2. **Sector caches** — 1,536 B in DAT (3 × 512 B shared caches)

Together these account for 4,608 bytes — **80% of the DAT section**.
