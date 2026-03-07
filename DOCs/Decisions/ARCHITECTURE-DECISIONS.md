# SD Card Driver Architecture Decisions

This document captures the architectural decisions for the multi-cog SD card driver. Each decision includes the P2-specific constraints that make it the correct choice. Use this document as a reference when implementing or reviewing the driver.

---

## Decision 1: Dedicated Worker Cog (Not Lock-Based Sharing)

### The Question
How should multiple cogs safely access the SD card?

### Options Considered
1. **Lock-based sharing**: Any cog acquires lock, does SPI, releases lock
2. **Dedicated worker cog**: One cog owns SPI; others send commands via hub memory

### The P2 Constraints That Decide This

There are two independent hardware constraints that both point to the same answer. The SD card uses four pins: CS (basic I/O), and SCK, MOSI, MISO (smart pins). Each pin type has its own sharing problem.

#### Constraint 1: Direct I/O — Per-Cog DIR/OUT Registers

**Basic I/O pins (like CS) are controlled by per-cog registers.** Each cog has its own private DIR and OUT registers at addresses `$1FA-$1FF`. When Cog 0 executes `PINH(pin)`, it sets bits in Cog 0's DIR/OUT registers. Cog 1's registers are unaffected.

For the CS pin this means every cog that wants to assert chip select must independently set its own DIR/OUT bits — and must tri-state them before releasing the lock, or multiple cogs end up driving the same pin simultaneously.

```
Lock-Based CS Sharing (PROBLEMATIC):
─────────────────────────────────────
Cog 0 acquires lock
  → PINH(cs)                             ← Sets Cog 0's DIR/OUT
  → Do SPI transfer
  → PINFLOAT(cs)                         ← MUST tri-state before release!
  → Release lock

Cog 1 acquires lock
  → PINH(cs)                             ← Sets Cog 1's DIR/OUT (again!)
  → Do SPI transfer
  → PINFLOAT(cs)
  → Release lock
```

If any cog forgets to tri-state before releasing the lock, multiple cogs have `DIR=1` on the same pin, causing undefined behavior.

#### Constraint 2: Smart Pins — Global Configuration, Per-Cog Enable

**Smart pin configuration is global hardware state, not per-cog.** The `WRPIN`, `WXPIN`, and `WYPIN` instructions write to the pin's shared smart pin registers — configuring mode, clock routing, bit count, etc. These settings are visible to all cogs. Any cog that executes `WRPIN` on a smart pin reconfigures it for everyone.

The SPI data pins (SCK, MOSI, MISO) use smart pin modes:
- **SCK**: `P_TRANSITION` — autonomous clock generation
- **MOSI**: `P_SYNC_TX` — synchronous serial transmit, clocked by SCK
- **MISO**: `P_SYNC_RX` — synchronous serial receive, clocked by SCK

Smart pins must be reset (`DIR=0`) before configuration and enabled (`DIR=1`) after — but DIR is per-cog. This creates two problems for lock-based sharing:

1. **Configuration conflict**: If Cog 1 calls `WRPIN` while Cog 0's smart pin is active, it destroys the mode settings mid-transfer
2. **Enable conflict**: Smart pins use DIR for enable/disable. Multiple cogs with `DIR=1` on the same smart pin creates the same undefined behavior as basic I/O — but with the added risk of corrupting an autonomous hardware state machine

```
Lock-Based Smart Pin Sharing (WORSE THAN BASIC I/O):
─────────────────────────────────────────────────────
Cog 0 acquires lock
  → WRPIN(P_SYNC_TX), WXPIN(8-bit), DIRH(mosi)  ← Configures + enables
  → WRPIN(P_TRANSITION), DIRH(sck)               ← Clock running
  → Do SPI transfer
  → DIRL(mosi), DIRL(sck)                        ← Must disable smart pins!
  → Release lock

Cog 1 acquires lock
  → Must reconfigure WRPIN/WXPIN from scratch     ← Full smart pin setup
  → DIRH to re-enable
  → ...
```

Every operation requires full smart pin teardown and re-initialization — not just toggling direction bits, but reprogramming the mode, clock routing, bit count, and start-stop parameters.

#### Both Constraints Eliminated by Dedicated Cog

```
Dedicated Cog Approach (CORRECT):
─────────────────────────────────────
Worker Cog (at startup, once):
  → PINH(cs)                             ← CS: set DIR/OUT once
  → WRPIN/WXPIN/DIRH(sck, mosi, miso)   ← Smart pins: configure once

  repeat forever:
    → Wait for command in hub memory
    → Execute (pins already configured)
    → Signal completion

Other cogs:
  → Write command to hub memory
  → Wait for completion
  → Never touch pins (direct I/O or smart pins)
```

### Decision
**Use a dedicated worker cog.** It eliminates per-operation pin setup for both direct I/O and smart pins, and removes the risk of configuration conflicts entirely. No other cog touches the SPI pins — not DIR/OUT for CS, not WRPIN/WXPIN for smart pins.

---

## Decision 2: Spin2 Worker via COGSPIN (Not Pure PASM2)

### The Question
Should the worker cog be pure PASM2 (started with `COGINIT`) or Spin2 (started with `COGSPIN`)?

### The Analysis

| Factor | Pure PASM2 | Spin2 + Inline PASM2 |
|--------|------------|---------------------|
| Smart pin SPI transfers | Native | Inline PASM2 (same) |
| Streamer DMA bulk I/O | Native | Inline PASM2 (same) |
| FAT32 logic (cluster chains, directories) | Complex, error-prone | Natural, readable |
| Handle system (6 concurrent file/dir handles) | Very difficult | Straightforward |
| Maintainability | Difficult at this scale | Natural for complex logic |
| SD card latency | ~1-10ms per operation | ~1-10ms per operation |

**The bottleneck is the SD card, not the P2.** SD card operations take milliseconds. Whether the FAT logic runs in 2µs (PASM2) or 20µs (Spin2) is irrelevant when the card takes 5,000µs to respond.

The driver uses inline PASM2 for three hardware-interface layers, each requiring precise timing or access to P2 special instructions:

| Layer | Hardware Feature | What It Does |
|-------|-----------------|--------------|
| **Card init** | Bit-bang (`DRVC`/`TESTP`) | 400 kHz slow SPI before smart pins are configured |
| **Byte transfers** | Smart pins (`WYPIN`/`RDPIN`) | 8-bit SPI via `P_SYNC_TX`/`P_SYNC_RX` at 25 MHz |
| **Sector transfers** | Streamer DMA (`XINIT`/`XCONT`/`WAITXFI`) | 512-byte bulk reads/writes with hardware CRC-16 (`GETCRC`) |

Everything above the SPI layer — FAT32 parsing, directory traversal, cluster allocation, the handle system with per-handle 512-byte sector buffers, per-cog working directories — is Spin2. This is where the code complexity lives (~6,000 lines), and Spin2's structured control flow, named variables, and method abstraction make this volume of filesystem logic significantly easier to write, debug, and maintain than equivalent PASM2.

### Decision
**Use Spin2 worker via COGSPIN.** Inline PASM2 for hardware-accelerated SPI (smart pins + streamer DMA). Spin2 for everything above the SPI layer. This matches the P2-FLASH-FileSystem pattern.

---

## Decision 3: DAT Block Singleton Pattern

### The Question
How do we ensure all callers share the same driver instance?

### The Spin2 Memory Model

```spin2
VAR block: Each object INSTANCE gets its own copy
DAT block: SHARED across all instances of the object
```

When multiple `.spin2` files each declare `OBJ fs : "SD_FileSystem"`, they create separate object instances, but they all share the **same DAT block**:

```
Application.spin2                    ┌──────────────────────────┐
  OBJ fs : "SD_FileSystem"  ────────►│   SD_FileSystem DAT      │
                                     │   (one shared copy)      │
DataLogger.spin2                     │                          │
  OBJ fs : "SD_FileSystem"  ────────►│   cog_id = 3             │
                                     │   api_lock = 2           │
SensorManager.spin2                  │   param_block[...]       │
  OBJ fs : "SD_FileSystem"  ────────►│   buf[512]               │
                                     └──────────────────────────┘
```

### The Singleton Guard

```spin2
PUB start(cs, mosi, miso, sck) : result
  ' ─── SINGLETON GUARD ───
  if cog_id <> -1
    return true                 ' Already running - instant success

  ' First caller proceeds to start worker cog...
```

The first `start()` call initializes the worker cog. Subsequent calls see `cog_id <> -1` and return immediately. All callers share the same worker, buffer, and state.

### Decision
**Use DAT block for all shared state.** Initialize `cog_id` to `-1` at declaration. The singleton guard ensures exactly one worker cog regardless of how many objects are instantiated.

---

## Decision 4: Parameter Block + COGATN Signaling

### The Question
How do caller cogs communicate with the worker cog?

### Options Considered
1. **Hub polling**: Caller writes command, polls `cmd == 0` until done
2. **COGATN signaling**: Caller writes command, executes `WAITATN`, worker signals via `COGATN`

### Why COGATN Wins

| Aspect | Hub Polling | COGATN |
|--------|-------------|--------|
| Hub bandwidth during wait | Continuous reads | **Zero** |
| Caller cog state | Busy-looping | **Sleeping** |
| Wake latency | Variable (depends on poll rate) | **0 clocks** |
| Power efficiency | Poor | **Good** |

**COGATN is a hardware interrupt mechanism.** The caller cog truly sleeps—no instructions execute, no hub bandwidth consumed—until the worker sends attention.

### The Protocol

```
Caller Cog                              Worker Cog
───────────────────────────────────────────────────────────────
1. Acquire api_lock
2. pb_caller := COGID()
3. pb_param0..3 := parameters
4. pb_cmd := CMD_xxx  ─────────────────► 5. See cmd != 0
5. WAITATN (sleep)                       6. Execute operation
   │                                     7. pb_status := result
   │                                     8. pb_cmd := 0
   │                                     9. COGATN(1 << pb_caller)
   ▼                                         │
6. Wake instantly ◄──────────────────────────┘
7. Read pb_status, pb_data0
8. Release api_lock
```

### Decision
**Use COGATN for completion signaling.** The parameter block lives in hub DAT. Callers sleep efficiently via `WAITATN`. A hardware lock serializes API access.

---

## Decision 5: Smart Pin SPI for Byte Transfers

### The Question
How should the driver implement SPI byte transfers?

### Why Smart Pins

The P2 smart pins provide autonomous SPI byte transfers with sysclk-independent timing. The driver configures three pins at startup:

| Pin | Smart Pin Mode | Purpose |
|-----|----------------|---------|
| SCK | `P_TRANSITION` | Clock generation with precise frequency control |
| MOSI | `P_SYNC_TX` | Data output synchronized to SCK |
| MISO | `P_SYNC_RX` | Data input synchronized to SCK |
| CS | GPIO | Manual control (basic I/O, not a smart pin) |

Smart pins replaced an initial bit-bang implementation after benchmarking showed significant room for improvement. The key advantages:

- **Sysclk-independent timing** — changing SPI speed is a single `WXPIN` update to SCK's period, no recalculation needed
- **Autonomous operation** — smart pins shift data in hardware; the cog loads/reads values and waits
- **Precise clock generation** — `P_TRANSITION` produces exact, jitter-free clock edges

**MSB-First Handling**: SD cards use MSB-first, but smart pins are LSB-first. Solution: `REV` instruction (2 cycles) before TX and after RX.

**Speed**: 400 kHz during card initialization (bit-bang, before smart pins are configured), then 25 MHz for normal operation.

### Decision
**Use smart pins for SPI byte transfers.** Configure once at startup, use for all command/response exchanges with the card.

---

## Decision 6: Streamer DMA for Sector Transfers

### The Question
How should the driver transfer 512-byte sectors to and from the SD card?

### Why the Streamer

The P2 streamer operates in serial mode, handling 1-bit input or output with its internal NCO providing precise timing. Combined with the smart pin clock generator from Decision 5, this creates a hardware SPI engine for bulk transfers with zero CPU involvement during the 512-byte payload.

Reference implementation: `flash_loader.spin2` by Chip Gracey demonstrates this pattern for SPI flash programming.

### How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│                   Streamer + Smart Pin for SPI                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Smart Pin (P_TRANSITION mode on SCK)                            │
│    - Generates SPI clock at programmed frequency                 │
│    - wxpin sets period, wypin sets transition count               │
│                                                                  │
│  Streamer (XINIT/XCONT/WAITXFI)                                  │
│    - Operates at NCO-controlled rate (setxfrq)                   │
│    - Reads MISO pin bit-by-bit, assembles bytes to hub           │
│    - Or reads hub bytes, outputs to MOSI pin bit-by-bit          │
│                                                                  │
│  Synchronization                                                 │
│    - NCO rate matches SPI bit rate                               │
│    - Alignment delay positions samples on correct clock edge     │
│    - READ: clock starts first, then streamer                     │
│    - WRITE: streamer starts first, then clock                    │
│                                                                  │
│  CRC-16                                                          │
│    - Hardware-accelerated via GETCRC with polynomial $8408       │
│    - Validated on every sector read and write                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### NCO Calculation

```spin2
' For smart pin clock with wxpin #N (N sysclks per transition):
' SPI clock = sysclk / (2N)
' Streamer NCO = $4000_0000 / N

' Example at 320 MHz sysclk, 22.9 MHz SPI:
' wxpin #7 → NCO = $4000_0000 / 7 = $0924_9249
```

### Critical Implementation Notes

- For READS: Disable MISO smart pin before streamer capture (streamer reads the pin directly; smart pin would interfere)
- For READS: Clock starts first, then streamer (`wypin` → `waitx` → `xinit`)
- For WRITES: Streamer starts first, then clock (`xinit` → `wypin`)
- SCK base-period counter is reset (`dirl`/`drvl`) before each transfer for deterministic clock phase alignment

### Decision
**Use the streamer for all 512-byte sector transfers.** This provides zero CPU involvement during bulk data movement, maximum throughput limited only by SPI clock speed, and hardware CRC-16 validation on every transfer.

**Full Details**: See `DOCs/Decisions/STREAMER-SPI-TIMING.md` for complete timing analysis, NCO calculations, and implementation patterns.

---

## Decision 7: Error Code Design

### The Question
How should errors be reported to callers?

### Convention
```
0           = Success
Negative    = Error (specific code indicates type)
Positive    = Valid data (byte count, handle, etc.)
```

### Error Code Ranges

| Range | Category | Examples |
|-------|----------|----------|
| 0 | Success | `SUCCESS` |
| -1 to -19 | SPI/Communication | `E_TIMEOUT`, `E_CRC_ERROR` |
| -20 to -39 | Card/Mount | `E_NOT_MOUNTED`, `E_NOT_FAT32` |
| -40 to -59 | File Operations | `E_FILE_NOT_FOUND`, `E_END_OF_FILE` |
| -60 to -79 | Resources | `E_DISK_FULL`, `E_NO_HANDLE` |
| -80 to -89 | Seek | `E_SEEK_PAST_END` |

### Thread-Safe Error Storage

Multiple cogs may call the API concurrently. Each cog needs its own error storage:

```spin2
DAT
  last_error    LONG    0[8]    ' One slot per possible cog

PUB error() : code
  return LONG[@last_error][COGID()]

PRI set_error(code) : code
  LONG[@last_error][COGID()] := code
  return code
```

### Decision
**Use negative error codes with per-cog storage.** This matches P2-FLASH-FileSystem and enables safe multi-cog operation.

---

## Decision 8: Timeout Policy (Not Retries)

### The Question
How should the driver handle communication failures?

### The Policy

**Layer 1 (SPI)**: Use timeouts, not retries.
```
If a transfer times out → return error immediately
The caller decides whether to retry
```

**Layer 2 (Card Init)**: Limited retries during initialization only.
```
CMD0 (GO_IDLE): Up to 5 attempts, 10ms apart
ACMD41 (init): Up to 200 attempts (spec allows 1 second)
Normal commands: No retries
```

**Layer 3 (API)**: Caller's responsibility.
```spin2
' Caller retry pattern:
repeat 3
  status := sd.read(handle, @buffer, 512)
  if status == sd.SUCCESS
    quit
  waitms(100)
```

### Rationale

The driver cannot know if a retry is safe:
- Was partial data written before failure?
- Is the card in an inconsistent state?
- Should we re-seek before retrying?

Only the caller has context to make these decisions.

### Critical Bug Fix Required

The current `readSector()` has an infinite loop waiting for the start token:

```pasm2
' CURRENT (BUG - hangs forever):
.startloop
                testp     _miso         wc
  if_c          jmp       #.startloop       ' ← No timeout!

' FIXED:
                GETCT     timeout
                ADDCT1    timeout, ##clkfreq    ' 1 second
.startloop
                POLLCT1   WC
  if_c          jmp       #.timeout_error       ' Bail on timeout
                drvh      _sck
                drvl      _sck
                testp     _miso         wc
  if_c          jmp       #.startloop
```

### Decision
**Use timeouts at SPI level; let callers decide on retries.** Fix the `readSector()` timeout bug immediately (Sprint Task 2.4).

---

## Decision 9: Multi-Block Operations (CMD18/CMD25)

### The Question
Should we implement multi-block read/write operations, or continue with single-sector operations?

### Analysis

**Single-sector approach** (current):
```
Read 64 sectors:
  64× CMD17 → R1 → wait token → 512 bytes → CRC → CS high
  = 64× command overhead
```

**Multi-block approach**:
```
Read 64 sectors:
  1× CMD18 → R1 → (wait token → 512 bytes → CRC) × 64 → CMD12
  = 1× command overhead + stop command
```

### Performance Impact

| Operation | Single-Sector | Multi-Block | Expected Gain |
|-----------|---------------|-------------|---------------|
| Read 8 sectors | 8× CMD17 | 1× CMD18 | 10-15% |
| Read 64 sectors | 64× CMD17 | 1× CMD18 | 15-25% |
| Write 8 sectors | 8× CMD24 | 1× CMD25 | 20-30% |
| Write 64 sectors | 64× CMD24 | 1× CMD25 | 30-40% |

Additional benefit: Cards internally optimize for sequential access during multi-block operations.

### Protocol Details

**Multi-Block Read (CMD18)**:
- Command: `$52` + sector + CRC
- Each sector: Wait for `$FE` token, read 512 bytes + CRC
- Stop: Send CMD12 (STOP_TRANSMISSION)

**Multi-Block Write (CMD25)**:
- Command: `$59` + sector + CRC
- Each sector: Send `$FC` token (not `$FE`!), 512 bytes + CRC, wait for response
- Stop: Send `$FD` token (not a command)

### Decision
**Implement multi-block operations in Phase 1** alongside Smart Pin SPI.

This provides:
1. Better baseline comparison data (measure gain from each optimization separately)
2. Compounded performance improvement
3. Foundation for file-level sequential I/O optimization

### Implementation
- `readSectors(start, count, p_buffer)` - CMD18 + CMD12
- `writeSectors(start, count, p_buffer)` - CMD25 + stop token
- Fall back to single-sector for count=1

See `DOCs/Plans/PHASE1-SMARTPIN-SPI.md` Tasks 1.8-1.10 for details.

---

## Decision 10: Single Path for All Card Access (Worker Cog Exclusive)

### The Question
Should card access ever bypass the worker cog for "simple" or "raw" operations?

### Background
The driver has two entry points:
- `mount()` - Full filesystem initialization
- `initCardOnly()` - Raw sector access without filesystem parsing

Originally, `initCardOnly()` bypassed the worker cog entirely, doing card initialization and subsequent operations directly from the calling cog. This created an architectural split where the same driver had two incompatible access patterns.

### The Problem with Dual-Path Access

```
WRONG: Dual-path architecture
──────────────────────────────────────────────────────────────────
                                    ┌─────────────────────┐
Cog0 calls initCardOnly() ─────────►│ Card (via Cog0)     │
                                    │ Smart pins on Cog0  │
                                    └─────────────────────┘

Later, Cog1 calls mount() ─────────►┌─────────────────────┐
                                    │ Worker on Cog1      │
                                    │ Smart pins on Cog1  │ ← CONFLICT!
                                    └─────────────────────┘
```

This caused:
1. **Pin ownership conflicts** - Two cogs configure the same pins
2. **Card state confusion** - Card initialized by Cog0, Cog1 tries to re-init
3. **Code duplication** - `if cog_id <> -1` checks scattered everywhere
4. **Testing surface doubled** - Two code paths to verify

### Decision: ALL Card Access Through Worker Cog

```
CORRECT: Single-path architecture
──────────────────────────────────────────────────────────────────
                                    ┌─────────────────────────────┐
                                    │      Worker Cog             │
Cog0 calls initCardOnly() ─────────►│  - Owns SPI pins            │
         or mount()                 │  - All card commands        │
                                    │  - All sector I/O           │
Cog1 calls file operations ────────►│  - CMD13 status tracking    │
                                    │  - Mode enforcement         │
                                    └─────────────────────────────┘
```

Both `initCardOnly()` and `mount()` start the worker cog. The difference:
- `initCardOnly()` → Worker initializes card only (MODE_RAW)
- `mount()` → Worker initializes card + parses filesystem (MODE_FILESYSTEM)

### Mode Management

```spin2
CON
  MODE_NONE       = 0    ' Not initialized
  MODE_RAW        = 1    ' Raw sector access only
  MODE_FILESYSTEM = 2    ' Full filesystem access

DAT
  driver_mode     BYTE    MODE_NONE
```

**Command Rejection by Mode:**

| Command | MODE_NONE | MODE_RAW | MODE_FILESYSTEM |
|---------|-----------|----------|-----------------|
| `mount()` | Start worker + init | Allowed (upgrade) | Already mounted |
| `initCardOnly()` | Start worker + init | Already initialized | REJECT |
| `readSectorRaw()` | REJECT | Allowed | Allowed |
| `writeSectorRaw()` | REJECT | Allowed | Allowed |
| `openFile()` | REJECT | REJECT | Allowed |
| `read()` / `write()` | REJECT | REJECT | Allowed |
| `unmount()` | No-op | Stop worker | Close files, stop worker |

**Mode Transitions:**

| From | To | Allowed? | Method |
|------|-----|----------|--------|
| NONE → RAW | Yes | `initCardOnly()` |
| NONE → FS | Yes | `mount()` |
| RAW → FS | Yes | `mount()` - adds filesystem parsing |
| FS → RAW | **No** | Must `unmount()` first, then `initCardOnly()` |
| RAW → NONE | Yes | `unmount()` |
| FS → NONE | Yes | `unmount()` |

**Rationale for RAW → FS being allowed:**
A diagnostic tool might examine raw sectors first, then switch to filesystem mode if the card appears healthy.

**Rationale for FS → RAW being rejected:**
If files are open, dropping to raw mode would corrupt the filesystem. Explicit unmount ensures proper cleanup.

### Implementation Changes Required

1. **`initCardOnly()`**: Start worker cog, send `CMD_INIT_CARD_ONLY` command
2. **Remove "direct access" fallbacks**: Delete all `if cog_id == -1` branches that do direct card access
3. **Add mode tracking**: Worker maintains `driver_mode`, rejects invalid commands
4. **Format utility**: Works unchanged - uses `initCardOnly()` which now goes through worker
5. **Verification tools**: Work unchanged - raw sector methods still available in MODE_RAW

### Decision
**ALL card hardware access goes through the worker cog. No exceptions.**

This eliminates pin conflicts, simplifies testing, and enforces clean mode transitions.

---

## Decision 11: Three Separate Sector Buffers in Hub RAM

### The Question
How many sector buffers should the driver maintain, and where should they reside?

### Options Considered

1. **Single buffer (512 bytes)** - All sector types share one buffer
2. **Two buffers (1024 bytes)** - FAT separate, data/directory combined
3. **Three buffers (1536 bytes)** - FAT, directory, and data each have dedicated buffers
4. **LUT/Cog RAM buffers** - Use cog's 4KB local memory instead of hub RAM

### Memory Architecture Constraint: Spin2 Interpreter Occupies Cog/LUT RAM

The Spin2 interpreter is approximately **4,784 bytes** - larger than cog RAM alone. It spans:

| Memory | Size | Contents When Running Spin2 |
|--------|------|----------------------------|
| Cog RAM | 2KB | Core interpreter code (loaded at boot) |
| LUT RAM | 2KB | Extended interpreter code (loaded by interpreter) |
| Hub RAM | Variable | Hub-exec portions, bytecode, user data |

**Implication**: When running Spin2, both cog RAM and LUT RAM are occupied by the interpreter. **User data must reside in hub RAM** - there is no alternative for a Spin2-based driver.

### Streamer Constraint: Cannot Write to Cog/LUT RAM

Even if we rewrote the driver in pure PASM (freeing cog/LUT for data), the P2 streamer has a fundamental limitation:

- **Streamer capture modes** (`X_1P_1DAC1_WFBYTE`, etc.) write to hub RAM via WRFAST
- **There is no streamer mode that writes to cog or LUT RAM**
- The `X_*_LUT` modes are for OUTPUT (LUT → pins), not INPUT (pins → LUT)

Data flow would still require hub RAM as an intermediary:
```
SD Card → Streamer → Hub RAM (required) → SETQ+RDLONG → Cog RAM
```

The extra copy overhead would likely negate any benefit from faster cog RAM access.

### Cache Thrashing Analysis

The critical factor for buffer count is **cache thrashing** during compound operations. Consider reading a 64KB file spanning 8 clusters:

**With 3 buffers (current architecture)**:
```
Read FAT for cluster 1    → FAT buffer loaded (1 read)
Read 8 data sectors       → Data buffer used (8 reads)
Read FAT for cluster 2    → FAT buffer STILL VALID (0 reads - cached!)
Read 8 data sectors       → Data buffer used (8 reads)
... repeat ...

Total: ~72 sector reads (FAT lookups mostly cached)
```

**With 1 buffer (hypothetical)**:
```
Read FAT for cluster 1    → Buffer loaded with FAT (1 read)
Read data sector 0        → Buffer reloaded with data (1 read) - FAT evicted!
Read data sector 1        → Buffer reloaded (1 read)
... after 8 data sectors ...
Read FAT for cluster 2    → Buffer reloaded with FAT (1 read) - data evicted!
Read data sector 0        → Buffer reloaded with data (1 read)
... constant thrashing ...

Total: ~136 sector reads (every operation evicts the previous)
```

**Performance Impact**:

| Configuration | Thrashing Behavior | Performance Impact |
|---------------|-------------------|-------------------|
| 3 buffers | FAT, DIR, DATA cached independently | Optimal |
| 2 buffers | FAT cached; DIR/DATA may thrash | ~10-20% slower |
| 1 buffer | Constant thrashing | ~50-100% slower |

### When Each Buffer Configuration Makes Sense

**3 buffers is optimal when:**
- Large files span multiple clusters (most real-world use)
- Directory searches in directories with many entries
- Mixed operations (read file, check directory, read another file)

**2 buffers might suffice when:**
- Files are always in single clusters
- Operations are purely sequential with no directory interaction

**1 buffer is problematic for:**
- Nearly all real filesystem operations beyond trivial single-sector access

### Hub RAM Cost is Negligible

The P2 has **512 KB of hub RAM**. Buffer memory cost:

| Configuration | Memory | % of Hub RAM |
|---------------|--------|--------------|
| 1 buffer | 512 bytes | 0.1% |
| 2 buffers | 1,024 bytes | 0.2% |
| 3 buffers | 1,536 bytes | 0.3% |

The additional 512-1024 bytes for multiple buffers is trivial compared to the potential 50-100% performance degradation from cache thrashing.

### Decision
**Use three separate sector buffers in hub RAM:**

```spin2
DAT
  dir_buf       BYTE    0[512]    ' Directory sector buffer
  fat_buf       BYTE    0[512]    ' FAT sector buffer
  buf           BYTE    0[512]    ' Data sector buffer

  dir_sec_in_buf LONG   0         ' Directory sector currently cached
  fat_sec_in_buf LONG   0         ' FAT sector currently cached
  sec_in_buf     LONG   0         ' Data sector currently cached
```

**Rationale:**
1. **Hub RAM is the only option** - Spin2 interpreter occupies cog/LUT RAM
2. **Streamer requires hub RAM** - Even pure PASM can't avoid hub as intermediary
3. **Cache thrashing is expensive** - 50-100% performance loss with single buffer
4. **Memory cost is negligible** - 1.5KB of 512KB hub RAM (0.3%)
5. **Complexity is minimal** - Each buffer has simple independent cache tracking

**Future consideration**: If memory becomes critical, the directory buffer could merge with the data buffer (2-buffer configuration) since directory and data operations rarely interleave. The FAT buffer should always remain separate.

---

## Summary: Why This Architecture (Decisions 1-11)

| Component | Decision | P2-Specific Reason |
|-----------|----------|-------------------|
| Cog model | Dedicated worker | Per-cog DIR/OUT registers |
| Worker language | Spin2 + inline PASM2 | SD card is bottleneck, not P2 |
| State sharing | DAT block singleton | Spin2 memory model |
| Signaling | COGATN | Zero-cost waiting, instant wake |
| SPI method | Smart Pins (revised) | Sysclk independence, higher throughput |
| Multi-block | CMD18/CMD25 | Reduced command overhead |
| Streamer | Hub DMA for sectors | Zero-CPU bulk transfers |
| Buffers | 3× hub RAM | Spin2 occupies cog/LUT; streamer needs hub |
| Errors | Negative codes, per-cog | Thread-safe multi-cog access |
| Failures | Timeouts, not retries | Caller has context to decide |

These decisions work together to create a driver that is:
- **Safe**: Multiple cogs can call APIs without conflicts
- **Efficient**: COGATN signaling, optimal FIFO usage
- **Reliable**: Timeout protection prevents hangs
- **Maintainable**: Spin2 for logic, PASM2 only where needed

---

## Decision 12: Hardware CRC-16 Validation on All Sector Transfers

### The Question
Should the driver validate CRC-16 checksums on sector transfers?

### Why CRC Matters

The SPI bus is the unprotected link in the data path. The card's internal ECC protects flash memory, but data in transit over SPI is only protected by CRC-16 — if the host doesn't validate it, corruption is silent.

```
┌─────────┐     SPI Bus      ┌─────────┐     Internal     ┌───────┐
│   P2    │ ←──────────────→ │ SD Card │ ←──────────────→ │ Flash │
│  (Host) │   CRC protects   │Controller│   ECC protects   │Memory │
└─────────┘   THIS segment   └─────────┘   THIS segment   └───────┘
```

Without CRC validation, SPI timing issues or electrical noise produce silent data corruption — FAT table damage, directory corruption, or file data errors that only become visible when the card is read on another system.

### P2 Hardware CRC via GETCRC

The P2's `GETCRC` instruction provides hardware-accelerated CRC calculation. For a 512-byte sector: ~1,032 clocks (~3.2 µs at 320 MHz), adding only 1.6% overhead to a 25 MHz SPI sector transfer.

SD cards use CRC-16-CCITT (polynomial x^16 + x^12 + x^5 + 1). P2's `GETCRC` uses a reflected (LSB-first) algorithm internally, so matching the SD spec requires a transformation:

```spin2
CON
    CRC_POLY_REFLECTED = $8408       ' CRC-16-CCITT in LSB-first form (REV16 of $1021)
    CRC_BASE_512       = $2C68       ' GETCRC of 512 zero bytes (P2's internal offset)

PRI calcSectorCRC(pBuf) : crc | raw
    raw := GETCRC(pBuf, CRC_POLY_REFLECTED, 512)
    crc := ((raw ^ CRC_BASE_512) REV 31) >> 16
```

The transformation:
1. `GETCRC` with reflected polynomial `$8408`
2. XOR with `$2C68` removes P2's non-zero base offset
3. `REV 31` converts LSB-first 32-bit result to MSB-first
4. `>> 16` extracts the 16-bit CRC

### How the Driver Uses It

- **Reads**: Card sends 512 bytes + 2-byte CRC. Driver calculates CRC over received data and validates against the card's CRC. Mismatch returns `E_CRC_ERROR`
- **Writes**: Driver calculates CRC over outgoing data and sends valid CRC bytes. Card-side CRC checking is enabled via CMD59 during initialization. Card rejects corrupted writes with Data Response `$0B`
- **Caller decides**: retry, abort, or report on `E_CRC_ERROR`

### Decision
**Validate CRC-16 on every sector transfer using P2 hardware GETCRC.** The 1.6% overhead is negligible, and it catches SPI transfer corruption that would otherwise be silent. This matches production-quality drivers (Linux, Windows).

---

## Decision 13: Card Presence Detection via P2 Internal Pull-Up (2026-03-02)

### The Question
How should the driver detect whether an SD card is physically present in the slot, given that the P2 Edge Module microSD socket has no card-detect pin?

### Background: SD Spec Provides No SPI-Mode Detection Method

The SD Physical Layer Simplified Specification v9.10 (December 2023) was reviewed in detail:

1. **Section 6.2 "Card Detection"** is blank in the publicly available simplified spec. The full mechanism is in the non-public Mechanical Addendum.
2. **Mechanical card-detect switch** (the standard approach) requires a physical switch in the socket that signals insertion/removal. The P2 Edge Module microSD socket does not expose a card-detect pin.
3. **DAT3/CS pull-up method** (ACMD42) only works in SD bus mode. In SPI mode, DAT3 is repurposed as CS, which the host actively drives. The host cannot passively sense a pull-up on a line it drives.
4. **No software-only detection method is defined** for SPI mode.

The only implicit guidance (Section 7.2): "The selected card always responds to the command." If no response comes, no card is present.

Full research: `DOCs/Reference/CARD-PRESENCE-DETECTION.md`

### Electrical Analysis: Card Present vs. No Card

The key distinction is on the MISO line:

| Scenario | MISO Behavior |
|----------|---------------|
| Card present, CS low | Card actively drives MISO (responds within NCR = 0-8 bytes) |
| Card present, CS high | Card drives MISO high (tri-state with internal pull-up) |
| **No card, with pull-up** | **MISO reads steady $FF (nothing drives it)** |
| No card, floating | MISO reads noise (unreliable) |

**The decisive signal**: A present card responds to CMD0 with a non-$FF byte within the NCR window. With no card and a pull-up on MISO, every byte read is $FF and cmd() always times out.

### The P2 Advantage: Built-In Programmable Pull-Up Resistors

Every P2 I/O pin has configurable internal pull resistors:

| Constant | Resistance | Suitability |
|----------|-----------|-------------|
| `P_HIGH_1K5` | 1.5K | Too strong (may affect card signals) |
| `P_HIGH_15K` | 15K | Ideal (reliable detection, easily overpowered by card) |
| `P_HIGH_150K` | 150K | Too weak (slow settling, noise susceptible) |

A present SD card has an output impedance typically under 100 ohms, easily overpowering a 15K pull-up. This makes the detection completely reliable.

**This eliminates any dependency on external board pull-up resistors.** The driver enables the pull-up itself before the CMD0 probe, making card detection self-contained and portable across all P2 board designs.

### The Detection Method: CMD0 Probe with Pull-Up

**Sequence:**

```
1. Enable P_HIGH_15K pull-up on MISO
2. Float MISO pin (input with pull-up active)
3. Wait 10 us for pull-up to settle
4. Send >=74 clock pulses (standard power-up sequence)
5. Send CMD0 up to 5 times, tracking got_response flag:
   - cmd() returns 0 on timeout (all $FF = no driver on MISO)
   - cmd() returns non-zero = something is driving MISO
6. After loop:
   - All timeouts (got_response == false) -> E_NO_CARD
   - At least one non-$FF response but not $01 -> E_BAD_RESPONSE (card present, not initializing)
   - Got $01 -> card present and idle, continue init
7. Pull-up automatically cleared when initSPIPins() configures MISO for smart pin SPI
```

**Why this works:**
- SD spec guarantees NCR = 0-8 bytes. A working card responds to CMD0 within microseconds.
- Our cmd() has a 1-second timeout per attempt. A card that doesn't respond in 1 second is not going to.
- Five retries with 10ms delays = ~5 seconds total. If nothing responds, nothing is there.
- The failure mode ($FF from pull-up, no driver on MISO) is electrically distinct from "card present but broken" (card drives MISO to something).

### New Error Code

```spin2
CON
  E_NO_CARD = -8    ' No card detected in slot (MISO idle during CMD0 probe)
```

This sits in the card-level error tier (E_TIMEOUT=-1 through E_IO_ERROR=-7), adding the most fundamental failure: no hardware present.

### Error Flow

```
User calls mount()
  -> do_mount()
    -> initCard()
      -> Enable P_HIGH_15K on MISO
      -> CMD0 loop: all timeouts, got_response stays false
      -> result := false, last_init_error := E_NO_CARD
    -> do_mount sees initCard() failed
    -> pb_status := last_init_error  (= E_NO_CARD)
  -> mount() returns E_NO_CARD to caller
```

**Caller usage:**
```spin2
result := sd.mount(CS, MOSI, MISO, SCK)
if result == sd.E_NO_CARD
  debug("No SD card inserted")
elseif result < 0
  debug("Mount failed: ", sdec(result))
```

### Decision

**Detect card presence using P2 internal pull-up on MISO + CMD0 timeout analysis.**

1. **Enable `P_HIGH_15K` on MISO** before the CMD0 probe sequence in `initCard()`
2. **Track `got_response` flag** across all CMD0 retries
3. **Return `E_NO_CARD`** when all CMD0 attempts time out (MISO never driven)
4. **Propagate through `do_mount()`** so `mount()` returns `E_NO_CARD` to the caller

**Rationale:**
- Self-contained: No external pull-up resistors required on any board
- Reliable: Electrically definitive ($FF from pull-up vs. card-driven response)
- Zero cost: Pull-up is automatically cleared by normal SPI pin initialization
- Specific: Callers get `E_NO_CARD` instead of generic `E_INIT_FAILED`
- SD spec compliant: Uses the only available approach (behavioral detection) since the spec defines no SPI-mode detection method

---

## Summary: Why This Architecture

| Component | Decision | P2-Specific Reason |
|-----------|----------|-------------------|
| Cog model | Dedicated worker | Per-cog DIR/OUT registers |
| Worker language | Spin2 + inline PASM2 | SD card is bottleneck, not P2 |
| State sharing | DAT block singleton | Spin2 memory model |
| Signaling | COGATN | Zero-cost waiting, instant wake |
| SPI method | Smart Pins (revised) | Sysclk independence, higher throughput |
| Multi-block | CMD18/CMD25 | Reduced command overhead |
| Streamer | Hub DMA for sectors | Zero-CPU bulk transfers |
| Buffers | 3× hub RAM | Spin2 occupies cog/LUT; streamer needs hub |
| Errors | Negative codes, per-cog | Thread-safe multi-cog access |
| Failures | Timeouts, not retries | Caller has context to decide |
| CRC validation | GETCRC formula discovered | `((GETCRC ^ $2C68) REV 31) >> 16` replaces 512-byte table |
| **Card detection** | **P_HIGH_15K pull-up + CMD0 probe** | **P2 built-in pull resistors eliminate external hardware** |

These decisions work together to create a driver that is:
- **Safe**: Multiple cogs can call APIs without conflicts
- **Efficient**: COGATN signaling, optimal FIFO usage
- **Reliable**: Timeout protection prevents hangs; card presence reliably detected
- **Maintainable**: Spin2 for logic, PASM2 only where needed

---

*Document created: 2026-01-17*
*Last updated: 2026-03-02 (Decision 13: Card presence detection via P2 internal pull-up)*
*For use by: Implementation agents, code reviewers*
