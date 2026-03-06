# Technical Decisions: SD Card Driver

This document captures research findings and architectural decisions for the SD card driver. These are conclusions that inform design but don't require sprint action items.

---

## TD-001: FIELD Operator Not Applicable

**Date**: 2026-01-17
**Status**: DECIDED - Not using FIELD

### Background

The Spin2 FIELD operator provides efficient packed bit-field access for arrays of small values:
- 1-bit flags: 8 per byte
- 2-bit states: 4 per byte
- 4-bit nibbles: 2 per byte
- Arbitrary bit widths packed across byte/word boundaries

```spin2
' Example: 800 boolean flags in 100 bytes
DAT
  flagStorage   BYTE    0[100]
VAR
  LONG  flagField

PUB init()
  flagField := ^@flagStorage.[0]      ' 1-bit fields

PUB setFlag(index)
  FIELD[flagField][index]~~           ' Set to 1
```

### Analysis

We examined the driver for FIELD applicability:

| Pattern | Current Implementation | FIELD Applicable? |
|---------|----------------------|-------------------|
| **flags variable** | Single LONG with `decod` bit masks | **No** - single word, not array |
| **Attribute byte** | Direct `& %0001_1110` masking | **No** - single byte extraction |
| **FAT entries** | 32-bit values at fixed offsets | **No** - must match FAT32 format |
| **Directory entries** | 32-byte fixed structures | **No** - must match FAT32 format |
| **CSD parsing** | Bit shifts on 128-bit register | **No** - one-time extraction |
| **buf[512]** | Raw sector data | **No** - on-disk format |

### Decision

**Do not use FIELD in this driver.**

**Rationale:**
1. FIELD is designed for large arrays (hundreds/thousands of items) - we don't have these
2. Most data structures must match FAT32 on-disk format exactly
3. Flag variables are single words, not arrays
4. Even with multiple file handles (4-8), a simple `BYTE` array is clearer and faster
5. No memory pressure - we have 512KB hub RAM

**Direct bit operations are preferred because they are:**
- Simpler to read and maintain
- Faster (no field pointer indirection)
- Appropriate for fixed on-disk formats

### Future Consideration

If we ever need to track large numbers of items (e.g., sector allocation bitmap for thousands of sectors), FIELD would be reconsidered. Current design doesn't require this.

---

## TD-002: Smart Pins for SPI - Deep Analysis

**Date**: 2026-01-17
**Revised**: 2026-01-21
**Status**: DECIDED - Full Smart Pin Implementation (Option 2, revised)

### Overview

This analysis examines Smart Pins for SPI against five criteria:
1. Clock speed independence from system clock
2. Pin setup (one-time vs. per-transfer)
3. Streamer applicability
4. Timeout and error handling
5. Raw performance

### 1. Clock Speed Independence

**The Problem**: Applications set `_CLKFREQ` at the top of their code for various reasons:
- HDMI drivers need specific derived clocks (e.g., 252 MHz for 1080p)
- Audio applications need precise sample rates
- Power-sensitive applications may run slower

**Current code dependency** (micro_sd_fat32_fs.spin2 line 721):
```spin2
bit_delay := clkfreq / 100_000    ' ~50kHz for init
' Later (line 847):
bit_delay := 2                     ' Fast mode
```

The `waitx delay` in the transfer loop depends on `clkfreq`:

| System Clock | bit_delay for 50kHz init | Actual SPI Rate |
|-------------|-------------------------|-----------------|
| 80 MHz | 800 | 50 kHz |
| 160 MHz | 1600 | 50 kHz |
| 252 MHz | 2520 | 50 kHz |
| 300 MHz | 3000 | 50 kHz |

**Smart Pin advantage**: Period is specified in system clocks via X register:
```spin2
' P_TRANSITION for clock generation
period := clkfreq / spi_rate      ' Calculate once at init
WXPIN(sck_pin, period)            ' Set period

' If clkfreq changes, recalculate:
period := clkfreq / spi_rate
WXPIN(sck_pin, period)            ' Update dynamically
```

**Verdict**: **SIMILAR** - Both require calculation from clkfreq. Smart Pins don't provide true clock independence; they just move where the calculation happens.

---

### 2. Pin Setup Analysis

**Current implementation pin manipulation**:

| Location | CS | MOSI | MISO | SCK |
|----------|-----|------|------|-----|
| `mount()` | pinh (deselect) | pinh | - | pinh |
| `initCard()` | pinh | pinh (idle high) | - | pinl (mode 0) |
| `cmd()` start | pinl (select) | - | - | - |
| `cmd()` end | pinh (deselect) | - | - | - |
| `transfer()` | - | drvc per bit | testp per bit | drvl/drvh per bit |
| `readSector()` | - | - | testp per bit | drvl/drvh per bit |
| `writeSector()` | - | drvc per bit | - | drvl/drvh per bit |

**Key observations**:
- **CS**: Must toggle per-transaction (SmartPins won't help - keep direct control)
- **SCK**: Toggled every bit - **perfect for P_TRANSITION**
- **MOSI**: Driven every bit - **candidate for P_SYNC_TX**
- **MISO**: Sampled every bit - **candidate for P_SYNC_RX**

**Smart Pin setup pattern** (from P2KB production code):
```pasm2
' ONE-TIME SETUP (at driver start)
' ────────────────────────────────
' Clock pin: P_TRANSITION mode
DIRL    sck_pin                     ' Reset
WRPIN   ##P_TRANSITION | P_OE, sck_pin
WXPIN   period, sck_pin             ' Bit period
DIRH    sck_pin                     ' Enable

' MOSI: P_SYNC_TX, clocked by sck_pin
DIRL    mosi_pin
WRPIN   ##P_SYNC_TX | P_OE, mosi_pin
WXPIN   ##(sck_pin << 24) | %1_00111, mosi_pin  ' Clock source + 8-bit start-stop
DIRH    mosi_pin

' MISO: P_SYNC_RX, clocked by sck_pin
DIRL    miso_pin
WRPIN   ##P_SYNC_RX, miso_pin
WXPIN   ##(sck_pin << 24) | %0_00111, miso_pin  ' Clock source + 8-bit pre-edge
DIRH    miso_pin

' PER-TRANSFER (for 8-bit byte)
' ────────────────────────────────
REV     tx_data                     ' MSB→LSB for SD card
SHL     tx_data, #24                ' Left-justify for 8-bit
WYPIN   tx_data, mosi_pin           ' Load TX data
WYPIN   #16, sck_pin                ' 16 edges = 8 bits
' Wait for completion via IN flag or event
TESTP   miso_pin WC                 ' Check IN flag
RDPIN   rx_data, miso_pin           ' Read received
SHR     rx_data, #24                ' Right-justify
REV     rx_data                     ' LSB→MSB
```

**Verdict**: **SMART PINS VIABLE** - One-time setup, per-transfer just loads data and triggers clock.

---

### 3. Streamer Applicability

The P2 Streamer provides DMA-like functionality with:
- `RDFAST`/`WRFAST` for hub↔FIFO setup
- NCO-driven timing for autonomous transfers
- Direct pin output modes

**Current code already uses FIFO** (micro_sd_fat32_fs.spin2 lines 891, 928):
```pasm2
wrfast    ##$8000_0000,ptr    ' Setup write FIFO for readSector
rdfast    ##8000_0000,ptr     ' Setup read FIFO for writeSector
wflong    data                 ' Stream to hub
rflong    data                 ' Stream from hub
```

**Streamer for SPI assessment**:

| Streamer Mode | Applicability to SPI |
|--------------|---------------------|
| Hub→Pins direct | **No** - needs bit-serial, not parallel |
| Hub→LUT→Pins | **No** - same issue |
| Pins→Hub | **No** - needs bit-serial |
| With SmartPins | **Maybe** - could trigger SmartPin transfers at NCO rate |

**Critical issue**: Streamer drives pins as parallel buses (1-32 bits simultaneously). SPI is serial (1 bit at a time, clocked). The streamer's value is in feeding the FIFO, which the current code already exploits.

**Verdict**: **STREAMER NOT APPLICABLE** for SPI serialization, but current FIFO usage (`wrfast`/`rdfast`/`wflong`/`rflong`) is already optimal for hub streaming.

---

### 4. Timeout and Error Handling - **CRITICAL BUG FOUND**

**Current timeout implementation**:

| Function | Has Timeout? | Implementation |
|----------|-------------|----------------|
| `cmd()` | **YES** | `getct() + clkfreq` (1 sec) |
| `initCard()` ACMD41 | **YES** | `getct() + clkfreq * 2` (2 sec) |
| `writeSector()` post-write | **YES** | `getct() + clkfreq` (1 sec) |
| `readSector()` start-token wait | **NO** ⚠️ | Loops forever! |
| `readSector()` data transfer | **NO** | REP loop runs to completion |
| `writeSector()` data transfer | **NO** | REP loop runs to completion |

**THE BUG** (micro_sd_fat32_fs.spin2 lines 893-898):
```pasm2
.startloop
                drvh      _sck
                nop
                drvl      _sck
                testp     _miso         wc
  if_c          jmp       #.startloop     ' ← INFINITE LOOP IF CARD HANGS!
```

This waits for the SD card's start token (MISO goes low). If the card never responds, **the cog hangs forever**.

**Smart Pin + Event solution for timeout**:
```pasm2
' Setup timeout event (SE1 = CT comparison)
GETCT   timeout
ADD     timeout, ##160_000_000      ' 1 second at 160MHz
ADDCT1  timeout, #0                 ' Load CT1 comparator
SETSE1  #%00_110001                 ' SE1 = CT >= CT1

' Setup MISO data-ready event (SE2 = pin IN rise)
' Note: With SmartPin, IN flag rises when byte received
SETSE2  #%001 << 6 + miso_pin       ' SE2 = IN rises on miso_pin

' Race between timeout and data
' NOTE: P2KB confirms no single instruction waits for multiple events.
'       Must poll both in a loop (from p2kbArchEventSystem "protocol_timeout" pattern):
.wait_loop:
        POLLSE1 WC                  ' Timeout?
  IF_C  JMP     #.timeout_error
        POLLSE2 WC                  ' Data ready?
  IF_C  JMP     #.data_ready
        JMP     #.wait_loop

.timeout_error:
        ' Handle card timeout - recoverable error
        ...

.data_ready:
        RDPIN   data, miso_pin      ' Read received byte
        ...
```

**P2KB Confirmation**: The P2 Event System (p2kbArchEventSystem) documents four individual WAITSE instructions (WAITSE1-4), each blocking on exactly ONE event. There is no "wait for any of N events" instruction. Multi-event monitoring requires polling via POLLSE1-4 in a loop. This is a ~4-8 clock overhead per iteration, negligible for timeout monitoring.

**Verdict**: **SMART PINS + EVENTS = ROBUST TIMEOUT** - This is a significant advantage over current code.

---

### 5. Raw Performance Comparison

**Current bit-bang timing** (per bit in transfer loop):
```pasm2
                 rcl      result,#1     wc    ' 2 clocks
                 drvl     _sck                ' 2 clocks
                 drvc     _mosi               ' 2 clocks
                 waitx    delay               ' delay clocks (2 for fast mode)
                 drvh     _sck                ' 2 clocks
                 waitx    delay               ' delay clocks
                 testp    _miso         wc    ' 2 clocks
' Total per bit: 12 + 2*delay clocks
' At delay=2: 16 clocks/bit = 5 MHz SPI at 80MHz, 10 MHz at 160MHz
```

**Smart Pin timing** (per byte, not per bit):
```pasm2
                REV       data                ' 2 clocks
                SHL       data, #24           ' 2 clocks
                WYPIN     data, mosi_pin      ' 2 clocks
                WYPIN     #16, sck_pin        ' 2 clocks (trigger 8 bits)
' Wait for hardware to shift (8 * X clocks where X = period)
                TESTP     miso_pin WC         ' 2 clocks (check IN)
                RDPIN     data, miso_pin      ' 2 clocks
                SHR       data, #24           ' 2 clocks
                REV       data                ' 2 clocks
' Total per byte: ~16 clocks setup + 8*period hardware
```

**Throughput comparison** (at 160 MHz sysclk):

| Method | Min Period | SPI Rate | 512-byte Sector |
|--------|-----------|----------|-----------------|
| Current bit-bang (delay=2) | 16 clks/bit | 10 MHz | ~410 µs |
| SmartPin (period=8) | 8 clks/bit | 20 MHz | ~205 µs |
| SmartPin (period=4) | 4 clks/bit | 40 MHz | ~102 µs |
| SD card max | - | 25 MHz | - |

**However**: SD card SPI is typically limited to 25 MHz by the card, and many cards work poorly above 10-15 MHz. The bottleneck is the card, not the P2.

**MSB-first overhead**: 4 clocks per byte (2× REV + SHL + SHR). For 512 bytes: 2048 extra clocks ≈ 13µs at 160 MHz. Negligible.

**Verdict**: **PERFORMANCE SIMILAR** for real-world SD card usage. SmartPins could theoretically go faster, but cards are the bottleneck.

---

### Summary Matrix

| Criterion | Current Bit-Bang | Smart Pins | Winner |
|-----------|-----------------|------------|--------|
| Clock independence | Requires bit_delay calc | Requires period calc | **Tie** |
| Pin setup overhead | Per-bit manipulation | One-time setup | **SmartPins** |
| Streamer integration | Uses FIFO directly | Same FIFO + SP | **Tie** |
| **Timeout handling** | **Missing in PASM!** | Events enable timeout | **SmartPins** |
| Raw throughput | ~10 MHz practical | ~25 MHz possible | **Tie** (card bottleneck) |
| Code complexity | Explicit, understandable | More abstract | **Current** |
| Proven reliability | Years of use | New implementation | **Current** |

---

### Final Decision

**STATUS: REVISED** - Option 2 (Full Smart Pin Implementation)

**Original Decision (2026-01-17)**: Hybrid approach - keep bit-bang, fix timeouts only.

**Revised Decision (2026-01-21)**: Implement full Smart Pin SPI architecture.

**What Changed**:

After establishing baseline benchmarks (see `DOCs/Reference/BENCHMARK-RESULTS.md`), we found:
- Current implementation achieves only 60% efficiency (1.5 MB/s vs 2.5 MB/s theoretical)
- Sysclk independence is valuable for users running different clock frequencies
- Card characterization completed - we have test coverage for implementation changes

**Selected Approach**:

| Pin | Smart Pin Mode | Purpose |
|-----|----------------|---------|
| SCK | P_TRANSITION | Clock generation with precise frequency control |
| MOSI | P_SYNC_TX | Data output synchronized to SCK |
| MISO | P_SYNC_RX | Data input synchronized to SCK |
| CS | GPIO | Manual control (unchanged) |

**Key Technical Details**:
- MSB-first handling: Use `REV` instruction before TX, after RX (single-cycle)
- Keep `wrfast`/`rdfast` for hub streaming (unchanged)
- Keep bit-bang fallback during development for A/B testing

**Performance Targets**:

| Metric | Baseline | Target |
|--------|----------|--------|
| Read 256KB | 1,467 KB/s | 4,000+ KB/s |
| Write 32KB | 425 KB/s | 1,200+ KB/s |
| SPI Clock | ~20 MHz | 25-50 MHz |

---

### Implementation Actions

**Phase 1 Sprint (In Progress)**:
- Task 1.1: initSPIPins() - Configure smart pin modes
- Task 1.2: setSPISpeed() - Sysclk-independent frequency control
- Task 1.3: sp_transfer() - Smart pin byte/word transfer
- Task 1.4: sp_readSector() - Optimized 512-byte read
- Task 1.5: sp_writeSector() - Optimized 512-byte write
- Task 1.6: Integration with initCard()
- Task 1.7: Regression testing

See `DOCs/Plans/PHASE1-SMARTPIN-SPI.md` for full implementation plan.

---

## TD-003: Streamer Not Applicable for SPI (SUPERSEDED)

**Date**: 2026-01-17
**Status**: SUPERSEDED — Streamer IS used for bulk sector reads/writes (see TD-006)

> **Note (2026-02-16):** This decision was made before the streamer was successfully applied to 1-pin SPI transfers using STREAM_RX_BASE ($C081_0000) and STREAM_TX_BASE ($8081_0000) modes with NCO-based bit timing. The streamer now handles all 512-byte sector data transfers, achieving 4-5x throughput vs. byte-at-a-time smart pin transfers. The original analysis below was incorrect about the streamer's capability for single-pin serial work.

### Background

The P2 Streamer provides high-speed DMA-like transfers between hub memory, LUT, and pins. We evaluated whether it could improve SD card SPI transfers.

### Analysis

The Streamer operates in these modes:
- **Parallel pin output**: 1-32 bits simultaneously to pin groups
- **Parallel pin input**: Capture pins to hub
- **LUT-based**: Transform data through LUT
- **RGB conversion**: Colorspace conversion for video

**SPI requirement**: Serial bit transfer (1 bit per clock), MSB-first, full-duplex.

The Streamer is fundamentally a **parallel** transfer engine. It can't serialize data to a single pin with clock synchronization.

**What the current code already does well**:
```pasm2
wrfast    ##$8000_0000,ptr    ' Setup FIFO
...
wflong    data                 ' Stream to hub at full speed
```

This is the optimal use of the Streamer's FIFO for getting data into/out of hub RAM during the bit-serial SPI transfer.

### Decision

**Do not use Streamer for SPI serialization.**

The current approach (inline PASM2 bit-serial with FIFO streaming) is already optimal:
- Streamer FIFO handles hub memory transfers
- PASM2 handles bit serialization
- These are the correct tools for their respective jobs

### Future Consideration

If we ever implement a parallel bus interface (SDIO 4-bit mode), the Streamer would be directly applicable.

---

## TD-004: Communication Error Handling Policy

**Date**: 2026-01-17
**Status**: DECIDED

### Overview

This defines how the SD card driver handles communication errors, retries, and reports failures to callers. Based on patterns from P2-FLASH-FileSystem for consistency.

---

### 1. Error Code Design

**Convention**: 0 = success, negative values = specific errors

```spin2
CON { Error Codes }
  ' Success
  SUCCESS           = 0

  ' SPI/Communication Errors (-1 to -19)
  E_TIMEOUT         = -1        ' Card didn't respond in time
  E_NO_RESPONSE     = -2        ' Card not responding (check wiring)
  E_BAD_RESPONSE    = -3        ' Unexpected response from card
  E_CRC_ERROR       = -4        ' Data CRC mismatch
  E_WRITE_REJECTED  = -5        ' Card rejected write operation
  E_CARD_BUSY       = -6        ' Card busy, operation couldn't complete

  ' Card/Mount Errors (-20 to -39)
  E_NOT_MOUNTED     = -20       ' Filesystem not mounted
  E_INIT_FAILED     = -21       ' Card initialization failed
  E_NOT_FAT32       = -22       ' Card not formatted as FAT32
  E_BAD_SECTOR_SIZE = -23       ' Sector size not 512 bytes
  E_CARD_REMOVED    = -24       ' Card was removed during operation

  ' File Operation Errors (-40 to -59)
  E_FILE_NOT_FOUND  = -40       ' File doesn't exist
  E_FILE_EXISTS     = -41       ' File already exists
  E_NOT_A_FILE      = -42       ' Expected file, found directory
  E_NOT_A_DIR       = -43       ' Expected directory, found file
  E_FILE_OPEN       = -44       ' File already open
  E_FILE_NOT_OPEN   = -45       ' File not open
  E_END_OF_FILE     = -46       ' Read past end of file
  E_FILE_READ_ONLY  = -47       ' Can't write to read-only file
  E_INVALID_PATH    = -48       ' Path syntax error
  E_PATH_TOO_LONG   = -49       ' Path exceeds maximum length

  ' Resource Errors (-60 to -79)
  E_DISK_FULL       = -60       ' No free clusters
  E_DIR_FULL        = -61       ' Directory can't hold more entries
  E_NO_HANDLE       = -62       ' Out of file handles
  E_BAD_HANDLE      = -63       ' Invalid handle number
  E_NO_LOCK         = -64       ' Couldn't allocate hardware lock

  ' Seek Errors (-80 to -89)
  E_SEEK_PAST_END   = -80       ' Attempted seek beyond file end
  E_BAD_SEEK_ARG    = -81       ' Invalid seek argument
```

---

### 2. Per-Cog Error Storage (Thread-Safe)

```spin2
DAT
  ' Per-cog error storage for multi-cog safety
  last_error    LONG    0[8]    ' One slot per possible cog

PUB error() : status
  '' Returns error code from most recent operation on this cog
  return LONG[@last_error][COGID()]

PRI set_error(code) : code_out
  '' Set error code for this cog, return the code (for chained returns)
  LONG[@last_error][COGID()] := code
  return code
```

**Usage pattern**:
```spin2
PUB open(filename) : handle
  if cog_id == -1
    return set_error(E_NOT_MOUNTED)
  ' ... operation ...
  if success
    return set_error(SUCCESS)
  else
    return set_error(E_FILE_NOT_FOUND)
```

---

### 3. Retry Policy

**Layer 1: SPI Transfer Retries** (handled internally, not exposed)

| Operation | Max Retries | Delay Between | Rationale |
|-----------|-------------|---------------|-----------|
| Command response wait | 0 | N/A | Use timeout instead |
| Start token wait | 0 | N/A | Use timeout instead |
| Write completion wait | 0 | N/A | Use timeout instead |

**We use timeouts, not retries, at the SPI level.** If a transfer times out, it's reported up - the caller decides whether to retry the higher-level operation.

**Layer 2: Command Retries** (during init only)

| Operation | Max Retries | Delay Between | Rationale |
|-----------|-------------|---------------|-----------|
| CMD0 (GO_IDLE) | 5 | 10ms | Card may need multiple attempts |
| ACMD41 (init) | 200 | 10ms | Spec allows up to 1 second |
| Normal commands | 0 | N/A | Fail immediately |

**Layer 3: API-Level Retries** (caller's responsibility)

The driver does NOT automatically retry failed operations. The caller decides:

```spin2
' Caller retry pattern
retry_count := 3
repeat
  status := sd.read(handle, @buffer, 512)
  if status == sd.SUCCESS
    quit
  if --retry_count == 0
    debug("Read failed after 3 retries: ", sd.string_for_error(sd.error()))
    quit
  waitms(100)    ' Brief delay before retry
```

**Rationale**: The driver can't know if a retry is safe (e.g., was partial data written?). The caller has context to decide.

---

### 4. Timeout Values

```spin2
CON { Timeout Values }
  ' All timeouts in clock cycles (multiply by clkfreq for seconds)
  TIMEOUT_CMD_RESPONSE  = 1     ' 1 second for command response
  TIMEOUT_READ_TOKEN    = 1     ' 1 second for read start token
  TIMEOUT_WRITE_BUSY    = 1     ' 1 second for write completion
  TIMEOUT_INIT          = 2     ' 2 seconds for ACMD41 init loop
```

**Implementation**:
```spin2
t := getct() + clkfreq * TIMEOUT_CMD_RESPONSE
repeat
  result := transfer(-1, 8)
  if result <> $FF
    quit
  if getct() - t > 0
    return set_error(E_TIMEOUT)
```

---

### 5. Error Reporting to User

**Method 1: Return value**
```spin2
PUB read(handle, p_buffer, count) : bytes_read
  '' Returns bytes read (>= 0) on success, negative error code on failure
```

**Method 2: Separate error() call**
```spin2
bytes := sd.read(handle, @buf, 512)
if bytes < 0
  debug("Error: ", sd.string_for_error(sd.error()))
```

**Method 3: Human-readable strings**
```spin2
PUB string_for_error(code) : p_str
  '' Returns pointer to error description string
  case code
    SUCCESS:          return @"Success"
    E_TIMEOUT:        return @"Timeout: card not responding"
    E_NOT_MOUNTED:    return @"Filesystem not mounted"
    E_FILE_NOT_FOUND: return @"File not found"
    ' ... etc ...
    other:            return @"Unknown error"
```

---

### 6. Hard Failure Handling

**Definition**: A hard failure is an unrecoverable error where the card is no longer usable.

**Hard failure conditions**:
- Card removed during operation
- Repeated communication failures (card damaged?)
- Card returns illegal state

**Hard failure response**:
```spin2
PRI hard_fail(code) : result
  '' Mark filesystem as unmounted and return error
  flags &= !F_MOUNTED           ' Clear mounted flag
  sec_in_buf := -1              ' Invalidate buffer
  return set_error(code)

' Usage in low-level code:
if repeated_timeout_count > 3
  return hard_fail(E_CARD_REMOVED)
```

**After hard failure**:
- All subsequent operations return `E_NOT_MOUNTED`
- Caller must call `mount()` again to re-initialize
- Caller should inform user: "SD card error - please reinsert card"

---

### 7. Error Code Ranges Summary

| Range | Category | Examples |
|-------|----------|----------|
| 0 | Success | SUCCESS |
| -1 to -19 | SPI/Communication | E_TIMEOUT, E_CRC_ERROR |
| -20 to -39 | Card/Mount | E_NOT_MOUNTED, E_NOT_FAT32 |
| -40 to -59 | File Operations | E_FILE_NOT_FOUND, E_END_OF_FILE |
| -60 to -79 | Resources | E_DISK_FULL, E_NO_HANDLE |
| -80 to -89 | Seek | E_SEEK_PAST_END |

---

### 8. Consistency with P2-FLASH-FileSystem

| Aspect | FLASH-FS Pattern | SD Driver (Same) |
|--------|------------------|------------------|
| Error code sign | Negative = error | ✓ Same |
| Per-cog storage | `errorCode LONG 0[8]` | ✓ Same |
| error() method | Returns last error | ✓ Same |
| string_for_error() | Human-readable | ✓ Same |
| Lock cleanup on error | Always release | ✓ Same |
| Fail-fast validation | Check before lock | ✓ Same |

---

### Action Items for Sprint

1. Add error code CON block to driver
2. Add `last_error` DAT storage
3. Add `error()` public method
4. Add `string_for_error()` public method
5. Update all functions to use `set_error()` pattern
6. Implement `hard_fail()` for unrecoverable errors
7. Document timeout values in CON block

---

## TD-005: Multi-Block Operations (CMD18/CMD25)

**Date**: 2026-01-21
**Status**: DECIDED - Implement in Phase 1

### Background

SD cards support multi-block read (CMD18) and write (CMD25) operations that transfer multiple consecutive sectors with a single command, reducing per-sector overhead.

### Analysis

**Current Single-Sector Approach**:
```
Per sector: CMD17 → R1 → wait → 512 bytes → CRC → CS high
Overhead: ~10 bytes command/response per sector
```

**Multi-Block Approach**:
```
Once: CMD18 → R1
Per sector: wait → 512 bytes → CRC
End: CMD12 (stop)
Overhead: ~10 bytes total (not per-sector)
```

### Expected Performance Improvement

| Sector Count | Single-Sector Overhead | Multi-Block Overhead | Reduction |
|--------------|------------------------|----------------------|-----------|
| 8 sectors | 80 bytes | 20 bytes | 75% |
| 64 sectors | 640 bytes | 20 bytes | 97% |

At 25 MHz SPI, 640 bytes = ~200µs saved per 64-sector operation.

**Additional Benefits**:
- Cards internally optimize for sequential access
- Reduces CPU time spent on command handling
- Better alignment with card's internal erase block operations

### Protocol Differences

| Aspect | Single Block | Multi-Block Read | Multi-Block Write |
|--------|--------------|------------------|-------------------|
| Command | CMD17/CMD24 | CMD18 | CMD25 |
| Data token | $FE | $FE (each sector) | $FC (each sector) |
| Stop | Automatic | CMD12 | $FD token |
| CRC | Required | Required (each) | Required (each) |

**Critical**: Multi-block write uses `$FC` data token, not `$FE`. Stop is `$FD` token, not CMD12.

### Decision

**Implement multi-block operations in Phase 1** alongside Smart Pin SPI to:
1. Establish baseline improvement from multi-block alone
2. Measure compounded benefit with Smart Pins
3. Provide foundation for file-level sequential I/O

### Implementation

```spin2
readSectors(start, count, p_buffer)   ' CMD18 + CMD12
writeSectors(start, count, p_buffer)  ' CMD25 + $FD stop token
```

See `DOCs/Plans/PHASE1-SMARTPIN-SPI.md` Tasks 1.8-1.10 for detailed implementation.

---

## TD-006: CRC Bytes Handled Separately from Streamer

**Date**: 2026-02-16
**Status**: DECIDED

### Background

The P2 streamer handles bulk sector data transfers (512 bytes = 4096 bits) for both reads and writes. Each SD sector transfer is followed by a 2-byte CRC-16. The question: should the streamer transfer 514 bytes (data + CRC) or 512 bytes (data only) with CRC handled separately?

### Current Implementation

The streamer transfers exactly **512 bytes** (4096 bits). After the streamer completes:

1. Smart pin is re-enabled (wrpin/wxpin/pinh)
2. CRC bytes are read/written via `sp_transfer_8()` (byte-at-a-time smart pin)

**Read sequence:**
```
[streamer: 512 bytes via STREAM_RX_BASE] → [re-enable smart pin] → [sp_transfer_8 x 2 for CRC]
```

**Write sequence:**
```
[streamer: 512 bytes via STREAM_TX_BASE] → [re-enable smart pin] → [sp_transfer_8 x 2 for CRC]
```

### Performance Impact

At 25 MHz SPI:
- 512-byte streamer transfer: ~328 microseconds
- 2-byte CRC via sp_transfer_8: ~640 nanoseconds (~0.2% overhead)
- Pin mode switching (pinclear/wrpin/wxpin/pinh): negligible (few sysclocks)

Total overhead of separate CRC handling: **< 0.5%** of sector transfer time.

### Decision

**Handle CRC bytes separately from the streamer.**

**Rationale:**
1. **Negligible performance cost** — 0.2% overhead is immaterial
2. **Code clarity** — CRC bytes are logically distinct from sector data; separate handling makes the protocol visible in code
3. **CRC validation** — Received CRC must be compared against calculated CRC; having the bytes in known variables (not buried at offset 512-513 of a buffer) simplifies validation logic
4. **Buffer management** — Sector buffers are exactly 512 bytes; adding 2 CRC bytes would require 514-byte buffers or separate extraction
5. **Smart pin already needed** — After streamer completes, smart pin must be re-enabled anyway for the data response token (writes) or CMD13 (reads); CRC transfer fits naturally in this transition

### Alternative Considered

Streamer transfers 514 bytes (512 data + 2 CRC):
- Would save pin mode transition but adds buffer complexity
- CRC bytes would need extraction from buffer end
- Buffer size would need to be 514+ bytes or use separate overflow area
- Marginal gain not worth the complexity

---

## TD-007: Streamer and Smart Pin Coexistence on MOSI

**Date**: 2026-02-16
**Status**: DECIDED — pinclear/rebuild cycle is REQUIRED

### Background

The MOSI pin serves two roles in the SD card driver:
1. **Smart pin** (`P_SYNC_TX`, 8-bit start-stop mode) for byte-at-a-time transfers: commands, tokens, CRC bytes
2. **Streamer target** (`STREAM_TX_BASE`, NCO-driven) for bulk 512-byte sector data

Every writeSector/writeSectors call must transition between these two modes:
```
sp_transfer_8($FE/$FC)   ← smart pin sends data token
pinclear(_mosi)           ← tear down smart pin (WRPIN=0, DIR=0)
pinl(_mosi)               ← drive low (DIR=1, output mode)
[streamer xinit/waitxfi]  ← streamer drives MOSI
wrpin(spi_tx_mode)        ← rebuild smart pin (P_SYNC_TX | P_OE | P_PLUS2_B)
wxpin(%1_00111)           ← 8-bit start-stop mode
pinh(_mosi)               ← DIRH enable smart pin
sp_transfer_8(crc_hi)    ← smart pin sends CRC
```

### Hardware Findings (from P2 Chip Designer)

**1. Streamer and smart pin outputs are OR'd on the physical pin.**

This means the inactive source MUST output zero, or it will corrupt the active source's data.

**2. P_SYNC_TX idle output is HIGH (not zero).**

Experimentally verified: removing the pinclear/rebuild cycle produced all-`$FE` readback (the data start token value OR'd with everything). The smart pin's idle state after completing its 8-bit transfer is 1 (high), consistent with start-stop protocol idle = mark state.

**3. DIRL does not help — it disables pin output entirely.**

Experimentally verified: using DIRL before streamer and DIRH after produced all-`$00` readback. With DIR=0, the pin pad output driver is off — the streamer cannot drive the physical pin. The card sees no data.

**4. SCK (P_TRANSITION) is safe — counted transitions, idle between bursts.**

The clock is driven by `wypin(count, sck)` with an exact transition count. After the requested transitions complete, the clock goes idle LOW. During the pinclear/rebuild cycle on MOSI, no clock edges are generated. Confirmed safe by chip designer.

### Decision

**The pinclear/rebuild cycle is REQUIRED.** There is no way to avoid it given the OR'd output architecture and P_SYNC_TX's high idle state.

The correct sequence for each streamer TX burst:
1. `pinclear(_mosi)` — clear smart pin mode (WRPIN=0), sets DIR=0, zeroes pin output
2. `pinl(_mosi)` — DRVL sets DIR=1 and OUT=0, pin is output driven low
3. `xinit/wypin/waitxfi` — streamer drives MOSI with no smart pin interference
4. `wrpin/wxpin/pinh` — rebuild smart pin with identical config every time

### Remaining Investigation: SanDisk Industrial 1-Bit Shift

The pinclear/rebuild cycle works correctly on Gigastone cards (250/250 tests pass). On SanDisk Industrial, the 4th sequential CMD24 write shows a systematic 1-bit right-shift. This is a separate issue from the mode coexistence problem — the pinclear/rebuild is necessary and correct, but something about the timing-sensitive SanDisk Industrial's response to the pin state transition still needs investigation.

Symptoms: `$A3→$D1`, `$D0→$E8`, `DEADBEEF→EF56DF77`, `$55AA→$2AD5`.

**Note:** readSector uses the same `pinclear(_miso)` / `pinf(_miso)` pattern for MISO before the streamer RX. This works correctly on all cards tested.

---

## TD-008: FAT High 4 Bits Not Preserved on Delete

**Date**: 2026-02-25
**Status**: DECIDED - Won't fix

### Background

The FAT32 spec states that the high 4 bits of each 32-bit FAT entry are reserved and should be preserved on writes. Our `allocateCluster()` correctly preserves them:

```spin2
high_bits := result & $F000_0000
long[@fat_buf + buf_idx] := high_bits | $0FFF_FFFF
```

However, `do_delete()` writes a full 32-bit zero when freeing clusters:

```spin2
long[@fat_buf + ((p_cluster << 2) & 511)] := 0
```

This clears the reserved high 4 bits along with the low 28.

### Analysis

- When a FAT entry is **free** (low 28 bits = 0), no OS reads the high 4 bits. Windows, macOS, and Linux all treat any entry with low 28 bits zero as a free cluster regardless of the high bits.
- Microsoft's own `chkdsk` and Apple's `fsck_msdos` both write full 32-bit zeros when freeing clusters.
- No real-world interchange issue has been documented in 25+ years of FAT32.
- The only risk would be a future spec revision assigning meaning to those bits on free entries, which has not happened.

### Decision

**Not addressing.** The spec-compliant fix is trivial (`long[addr] := long[addr] & $F000_0000`) but provides no practical benefit. Allocate-path preservation is the one that matters for data integrity, and that is already correct.

---

## TD-009: CMD13 Compatibility — Probe + Advisory API

**Date**: 2026-03-05
**Status**: DECIDED — Strategy A (probe at init) + Strategy C (cardWarnings API)
**Analysis**: [CMD13-COMPATIBILITY-ANALYSIS.md](../Analysis/CMD13-COMPATIBILITY-ANALYSIS.md)

### Background

A user reported that an older AData 16GB SDHC card (MID $1D, revision 0.2, manufactured 2013) blocks on mount because `checkCardStatus()` returns E_IO_ERROR after every CMD13 call. The card's CMD13 response has R1 bit 7 = 1 (spec violation) and STATUS = $3F (6/8 error bits set simultaneously — physically impossible). All data operations work perfectly when CMD13 is bypassed.

Research confirms CMD13 failures in SPI mode are a known class of issue on older/budget controllers. Status-reporting commands are among the least reliably implemented parts of the SPI command set.

### Alternatives Considered

Six strategies were evaluated across two dimensions — detection and reporting:

**Detection:**
- **(A) Probe once at init** — send CMD13 after card init, check for spec violations. Simple, catches consistently broken cards.
- **(F) Runtime tracking** — monitor CMD13 over time, auto-downgrade. No evidence of intermittent CMD13 failure exists. Adds overhead to every CMD13 call.

**Reporting:**
- **(B) Positive mount() return** — changes mount() contract, breaks callers checking `result == 0`.
- **(C) New cardWarnings() API** — clean separation, mount() unchanged, extensible bitmask, opt-in for callers.
- **(D) Overload error() channel** — semantically wrong (warning is not error), overwrites on next operation.

### Decision

**Use Strategy A + C:**

1. **CMD13 probe at end of initCard()** — send CMD13, check R1 bit 7 and impossible error combinations. Set `cmd13_reliable` flag (DAT BYTE, default TRUE).

2. **Gate all four checkCardStatus() call sites** on `cmd13_reliable`. If FALSE, skip CMD13 and return SUCCESS.

3. **New `cardWarnings() : flags` PUB method** — returns `card_warning_flags` bitmask. New constant `CW_CMD13_UNRELIABLE = $01`.

4. **Debug message at mount** when CMD13 is unreliable.

### Rationale

- **No behavior change for working cards** — the vast majority of cards implement CMD13 correctly. CMD13 remains active for them, providing post-write verification.
- **Automatic detection** — no user configuration needed. The probe catches cards that are consistently broken.
- **Clean reporting** — mount() contract unchanged. Callers who care check `cardWarnings()`, callers who don't are unaffected. Extensible for future advisories.
- **Minimal implementation** — one probe, one flag, four if-checks, one new PUB method, one CON constant.
- **Runtime tracking deferred** — Strategy F solves a problem we haven't observed. Can be added later if intermittent CMD13 behavior is ever reported.

---

## TD-010: Audit Severity — Downgrade Benign Metadata Mismatches to Warnings

**Date**: 2026-03-05
**Status**: DECIDED — Downgrade two checks; keep VBR backup as FAIL
**Analysis**: [AUDIT-SEVERITY-ANALYSIS.md](../Analysis/AUDIT-SEVERITY-ANALYSIS.md)

### Background

The same AData card triggered two audit failures that are common, benign inconsistencies on real-world FAT32 media:

1. `[FAIL] Partition type ($0C = FAT32 LBA)` — card has $0B (FAT32 CHS)
2. `[FAIL] Backup FSInfo matches primary` — primary and backup differ

Research confirms both are normal. Every mainstream OS mounts such volumes without issue.

### Checks Affected

| Check | Current | Proposed | Rationale |
|-------|---------|----------|-----------|
| **Partition type $0B** | `[FAIL]` | `[PASS]` (accept both $0B and $0C) | Both are FAT32. Driver uses LBA start field regardless. $0B is not an error. |
| **Backup FSInfo mismatch** | `[FAIL]` | `[WARN]` | FSInfo holds performance hints only. OSes routinely don't sync the backup. Zero operational risk. |
| **Backup VBR mismatch** | `[FAIL]` | `[FAIL]` (no change) | VBR holds irreplaceable filesystem geometry. A mismatch should be flagged so FSCK can repair it. No evidence of false positives. |

### Decision

1. **Partition type**: Change audit to accept both $0B and $0C as valid FAT32. This is a PASS, not a warning — $0B is a legitimate partition type.

2. **Backup FSInfo mismatch**: Downgrade from `[FAIL]` to `[WARN]`. Increment `v_warningCount` instead of `v_failCount`.

3. **Backup VBR mismatch**: Keep as `[FAIL]`. The VBR contains irreplaceable filesystem geometry (bytes/sector, sectors/cluster, FAT size, root cluster). Unlike FSInfo hints, this data cannot be recalculated. A mismatched backup means the disaster recovery copy is stale — exactly the kind of issue the audit should flag so FSCK can repair it. No user report or research has shown this to be a false positive.

### Rationale

- **$0B is not an error** — it's a valid FAT32 type code. Failing on it produces false negatives that make working cards appear defective.
- **FSInfo backup is cosmetic** — it holds recalculable performance hints. OSes routinely don't sync the backup. Zero operational risk.
- **VBR backup is not cosmetic** — it holds irreplaceable geometry. Failing on a mismatch is correct audit behavior that drives FSCK repair.
- **Warning infrastructure exists** — the fsck utility already tracks `v_warningCount` and displays it in the summary. The audit side just needs to use it.
- **No changes to FSCK behavior** — FSCK already correctly repairs both backup mismatches by copying primary to backup. That behavior is appropriate for a repair tool.

---

## TD-011: (Reserved for next decision)

---

*Document created: 2026-01-17*
*Last updated: 2026-03-05*
