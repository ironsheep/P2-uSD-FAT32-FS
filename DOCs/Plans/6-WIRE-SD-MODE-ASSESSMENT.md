# 6-Wire SD Native Mode: Preliminary Assessment

Architectural assessment for adding 4-bit SD native mode alongside existing SPI mode, with compile-time switching.

**Date:** 2026-03-06
**Status:** Preliminary assessment (not an implementation plan)

---

## 1. What 6-Wire SD Mode Means

### Pin Layout

| Pin | SPI Mode | SD Native Mode |
|-----|----------|----------------|
| CLK | SCK (host → card) | CLK (host → card) |
| CMD | — | CMD (bidirectional: commands + responses) |
| DAT0 | MISO (card → host) | DAT0 (bidirectional data) |
| DAT1 | — | DAT1 (bidirectional data) |
| DAT2 | — | DAT2 (bidirectional data) |
| DAT3 | CS (active low) | DAT3 (bidirectional data) |
| MOSI | MOSI (host → card) | — (merged into CMD line) |

SPI uses 4 wires (CS, MOSI, MISO, SCK). SD native mode uses 6 wires (CLK, CMD, DAT0-DAT3). The data bus is 4 bits wide instead of 1.

### Throughput Implication

At the same clock frequency (25 MHz), SD native mode transfers 4 bits per clock vs 1 bit per clock in SPI mode. A 512-byte sector takes:

| Mode | Bits per clock | Clocks for 512 bytes | Theoretical speedup |
|------|---------------|---------------------|-------------------|
| SPI | 1 | 4,096 | 1x |
| SD 4-bit | 4 | 1,024 | 4x |

This is the same speedup the streamer gave us over byte-by-byte loops — except it applies to the wire itself.

---

## 2. Protocol Differences: SPI vs SD Native

### Command/Response Format

| Aspect | SPI Mode (current) | SD Native Mode |
|--------|-------------------|----------------|
| Command send | MOSI, 48 bits | CMD line, 48 bits |
| Response format | R1: 1 byte on MISO | R1: 48 bits on CMD line |
| | R2: 2 bytes (CMD13) | R1b: 48 bits + busy on DAT0 |
| | R3/R7: 5 bytes (CMD58/CMD8) | R2: 136 bits (CID/CSD) |
| | | R3: 48 bits (OCR) |
| | | R6: 48 bits (RCA) |
| Card selection | CS pin (GPIO low) | CMD7 with RCA address |
| CRC-7 (commands) | Mandatory (we send it) | Mandatory |
| CRC-16 (data) | 1 CRC for serial stream | 4 independent CRCs (one per DAT line) |

### Data Transfer Format

| Aspect | SPI Mode | SD Native Mode |
|--------|----------|----------------|
| Data token | $FE before data | Start bit on DAT0 |
| Data width | 1 bit (MISO serial) | 4 bits (DAT0-DAT3 parallel) |
| Byte order | MSB first, serial | Nibble-interleaved across 4 lines |
| Busy signal | MISO held low | DAT0 held low |
| Multi-write stop | $FD token byte | CMD12 (STOP_TRANSMISSION) |
| CRC per sector | 1 x CRC-16 | 4 x CRC-16 (one per DAT line) |

### Init Sequence Differences

| Step | SPI Mode | SD Native Mode |
|------|----------|----------------|
| Mode entry | CMD0 with CS low | CMD0 (no CS) |
| Card identification | Not needed | CMD2 → get CID, CMD3 → get RCA |
| Card selection | CS pin | CMD7(RCA) to select |
| Bus width | Always 1-bit | Start 1-bit, ACMD6 to switch to 4-bit |
| Speed class | CMD6 optional | CMD6 for high-speed |

### Commands That Change

| Command | SPI behavior | SD native behavior |
|---------|-------------|-------------------|
| CMD0 | CS low → SPI mode entry | Reset, stay in SD mode |
| CMD2 | Not used in SPI | ALL_SEND_CID → 136-bit R2 |
| CMD3 | Not used in SPI | SEND_RELATIVE_ADDR → get RCA |
| CMD7 | Not used in SPI | SELECT_CARD(RCA) |
| CMD12 | R1 byte (our timing race) | R1b on CMD + busy on DAT0 |
| CMD13 | R2 = R1 + status byte | R1 on CMD line (different format) |
| ACMD6 | Not used in SPI | SET_BUS_WIDTH (1-bit or 4-bit) |

---

## 3. P2 Hardware Support for 4-Bit SD

### Streamer: 4-Pin Modes Exist

The P2 streamer has native 4-pin parallel modes for adjacent pins:

| Direction | Streamer Symbol | Value | Description |
|-----------|----------------|-------|-------------|
| **Read** (pins → hub) | `X_4P_4DAC1_WFBYTE` | `$E000_0000` | 4 adjacent pins → WFBYTE |
| **Write** (hub → pins) | `X_RFBYTE_4P_4DAC1` | `$A000_0000` | RFBYTE → 4 adjacent pins |

These read/write 4 bits per streamer clock cycle from/to 4 adjacent pins, packing nibbles into bytes in hub RAM. This is exactly what SD 4-bit data transfer needs.

**Pin adjacency requirement:** The streamer's multi-pin modes require the pins to be adjacent (consecutive pin numbers). The 6-wire adapter card must place DAT0-DAT3 on 4 consecutive P2 pins.

### Streamer Mode Comparison

| | Current SPI | SD 4-Bit |
|---|---|---|
| **Read mode** | `$C081_0000` (1-pin input, MSB-first) | `$E081_0000` (4-pin input, MSB-first) |
| **Write mode** | `$8081_0000` (1-pin output, MSB-first) | `$A081_0000` (4-pin output, MSB-first) |
| **Base pin** | MISO (read) / MOSI (write) | DAT0 (lowest of DAT0-DAT3) |
| **Clocks per sector** | 4,096 (512 x 8 bits) | 1,024 (512 x 8 / 4 bits) |
| **SCK transitions** | 8,192 | 2,048 |

### CMD Line: Bidirectional Smart Pin

The CMD line is bidirectional — the host sends commands, the card sends responses on the same wire. This needs:

1. **Output mode** for sending 48-bit commands (similar to current MOSI)
2. **Input mode** for receiving 48-bit or 136-bit responses
3. **Direction switching** between send and receive

P2 smart pins can be reconfigured on the fly (`wrpin`/`wxpin`/`pinh`), so the CMD line can switch between P_SYNC_TX and P_SYNC_RX as needed. Alternatively, since commands are short (6 bytes), bit-banging the CMD line while using the streamer only for bulk data on DAT0-3 may be simpler and fast enough.

### CRC-16 x 4

SD native mode requires independent CRC-16 on each DAT line. The P2 GETCRC instruction works on hub memory, not pin streams. Options:

1. **Software CRC after receive**: De-interleave the 4-bit data into 4 separate byte streams, compute CRC-16 on each. Adds post-processing but is straightforward.
2. **Inline PASM CRC**: Accumulate CRC per-nibble during the transfer using PASM. More complex but avoids the de-interleave pass.
3. **Accept card's CRC**: Like SPI mode, trust the card's internal CRC and only verify on our side for diagnostics.

---

## 4. SPI Coupling Analysis: What Changes, What Doesn't

### Layer 1: Transport (MUST change)

Everything below this line is SPI-specific and must have a parallel SD-native implementation:

| Component | Lines | What changes |
|-----------|-------|-------------|
| `initSPIPins()` | 4529-4611 | Pin config: 4 data pins + CMD + CLK instead of CS/MOSI/MISO/SCK |
| `sp_transfer_8()` | 4705-4757 | Byte transfer primitive: 4-bit on DAT0-3 instead of 1-bit on MISO/MOSI |
| `sp_transfer_32()` | 4759+ | 32-bit transfer: same change |
| `applySPISpeed()` | 4627-4664 | Clock config: same P_TRANSITION, different period calculations |
| Streamer blocks (4x) | 5165, 5297, 5476, 5616 | 4-pin mode constants, 1/4 the clock count |
| `transfer()` | 6016+ | Bit-bang fallback: 4-bit GPIO instead of 1-bit |

### Layer 2: SD Protocol Framing (MUST change)

| Component | Lines | What changes |
|-----------|-------|-------------|
| `cmd()` | 5015-5055 | Send on CMD line (not MOSI), receive response on CMD line (not MISO). Response is 48/136-bit, not 8-bit R1 |
| `waitDataToken()` | 5691-5720 | No $FE token in SD mode; watch for start bit on DAT0 |
| `waitDataResponse()` | 5722-5744 | No data response token; busy on DAT0 instead |
| `waitBusyComplete()` | 5746-5765 | Watch DAT0 (not MISO) for busy release |
| `sendStopTransmission()` | 5767-5826 | CMD12 on CMD line, response on CMD line, busy on DAT0 |
| `recoverToIdle()` | 5828-5849 | No CS deassert; send CMD0 or CMD15 (GO_INACTIVE) |
| CRC handling | 4666-4685, 5192-5217 | 4 independent CRC-16 streams instead of 1 |

### Layer 3: Card Init (MUST change)

| Component | Lines | What changes |
|-----------|-------|-------------|
| `initCard()` | 4811-5012 | Add CMD2/CMD3/CMD7 for card identification and selection. Add ACMD6 for 4-bit bus enable. No CS-based mode entry. |
| `probeCmd13()` | 5851-5903 | CMD13 response format is different in SD mode |
| `probeCmd23()` | 5906-5936 | CMD23 may actually work in SD native mode |

### Layer 4: Filesystem + Handle Logic (NO CHANGE)

Everything above the transport layer is bus-agnostic:

- FAT32 parsing, directory traversal, cluster chains
- Handle system, per-handle buffers
- Worker cog mailbox, API dispatch
- File operations (open, read, write, seek, close)
- Error codes, diagnostics framework

This is the majority of the driver (~4,000 of ~6,100 lines).

---

## 5. Architectural Approaches

### Approach A: Conditional Compilation (Recommended)

Use `#ifdef SD_4BIT_MODE` / `#else` to select between SPI and SD-native implementations at compile time.

```spin2
' In consumer's top-level file:
#pragma exportdef SD_4BIT_MODE    ' Enable 4-bit SD mode (omit for SPI)

' In the driver:
#ifdef SD_4BIT_MODE
PRI initTransport()
    ' Configure CLK, CMD, DAT0-DAT3
    ...
#else
PRI initTransport()
    ' Configure CS, MOSI, MISO, SCK (current code)
    ...
#endif
```

**Pros:**
- Zero overhead: only one transport compiled in
- Matches existing pattern (`SD_INCLUDE_RAW`, `SD_INCLUDE_DEBUG`, etc.)
- Single driver file maintained
- User picks mode at compile time based on their hardware

**Cons:**
- Duplicated transport code within the same file (maybe +800-1000 lines)
- Testing requires compiling and running both variants
- Merge conflicts when modifying shared code near `#ifdef` boundaries

### Approach B: Transport Object (OBJ Polymorphism)

Factor the transport layer into a separate object. The driver imports one of two transport implementations:

```spin2
' For SPI mode:
OBJ transport : "sd_transport_spi"

' For 4-bit mode:
OBJ transport : "sd_transport_4bit"
```

The driver calls `transport.readSector()`, `transport.writeSector()`, `transport.sendCommand()`, etc.

**Pros:**
- Clean separation: transport code in its own file
- No `#ifdef` clutter in the main driver
- Each transport implementation is self-contained and testable

**Cons:**
- Requires refactoring the driver's monolithic architecture (significant work)
- Object method calls add overhead vs inline code (extra cog instruction dispatch)
- Transport needs access to driver DAT variables (diagnostics, CRC counters) — coupling issue
- The streamer PASM blocks reference DAT variables that would need to cross object boundaries

### Approach C: Hybrid (Recommended Starting Point)

Keep the driver monolithic. Group all transport-layer methods into a clearly marked section. Use `#ifdef SD_4BIT_MODE` at the section level, not per-line:

```spin2
' ═══════════════════════════════════════════
' SECTION: TRANSPORT LAYER
' ═══════════════════════════════════════════

#ifdef SD_4BIT_MODE
' --- 4-bit SD native transport ---
PRI initTransport(clk_pin, cmd_pin, dat0_pin)
    ...
PRI sendCommand(op, arg) : response
    ...
PRI readSectorDMA(p_buf) : result
    ...
' (all 4-bit methods here)

#else
' --- SPI transport (current implementation) ---
PRI initSPIPins()
    ...
PRI sp_transfer_8(data) : result
    ...
PRI readSector(sector, buf_type) : result
    ...
' (all SPI methods here, unchanged)

#endif
```

**Pros:**
- Minimal refactoring of existing code — just move methods into a section
- Clean `#ifdef` at section boundaries, not scattered throughout
- Both implementations live in one file (single truth)
- No object call overhead
- DAT variables shared naturally

**Cons:**
- File gets longer (+800-1000 lines)
- Still one monolithic file

**This is the recommended approach.** It preserves the existing architecture, adds no overhead, and follows the project's established conditional compilation pattern.

---

## 6. Mount API Change

The `mount()` signature must accommodate both pin configurations:

```spin2
#ifdef SD_4BIT_MODE
PUB mount(clk_pin, cmd_pin, dat0_pin) : result
    ' dat0_pin is the lowest of 4 adjacent pins (DAT0)
    ' DAT1 = dat0_pin + 1, DAT2 = dat0_pin + 2, DAT3 = dat0_pin + 3
#else
PUB mount(cs_pin, mosi_pin, miso_pin, sck_pin) : result
    ' Current 4-pin SPI signature
#endif
```

The 4-bit mode only needs 3 pin parameters because DAT1-DAT3 are derived from DAT0 (adjacent pins required by streamer). This is a compile-time API difference, not runtime.

---

## 7. What CMD23 Means in SD Native Mode

CMD23 (SET_BLOCK_COUNT) is likely to work in SD native mode — the SPI rejection we see is SPI-specific. This would eliminate CMD12 entirely for multi-block reads, giving us the cleanest possible transfer path: CMD23 + CMD18, card auto-stops, no abort needed.

This should be verified on hardware once the 6-wire adapter arrives.

---

## 8. Estimated Scope

| Work Area | Effort | Notes |
|-----------|--------|-------|
| Transport methods (new 4-bit implementations) | Medium | ~15 methods to write, leveraging existing patterns |
| Streamer blocks (4-pin modes) | Small | Change mode constants and clock counts |
| CMD line protocol (bidirectional) | Medium | New command/response framing, 48/136-bit parsing |
| Card init sequence | Medium | Add CMD2/CMD3/CMD7/ACMD6 steps |
| CRC-16 x 4 | Medium | De-interleave + 4 independent CRC calculations |
| Section reorganization | Small | Move existing transport methods into marked section |
| Mount API | Small | Compile-time signature change |
| Testing | Large | Full regression on both SPI and 4-bit hardware |

The filesystem layer, handle system, worker cog, and all public API methods above the transport layer require zero changes.

---

## 9. Pin Assignment Considerations

The 6-wire adapter card determines pin assignments. For the streamer's 4-pin mode, DAT0-DAT3 must be on consecutive P2 pins. Ideal layout:

```
DAT0 = P58    (currently MISO — same physical pin, same role for 1-bit)
DAT1 = P59    (currently MOSI)
DAT2 = P60    (currently CS)
DAT3 = P61    (currently SCK)
CLK  = P57    (new, adjacent below DAT0)
CMD  = P56    (new, adjacent below CLK)
```

Or any other arrangement where DAT0-DAT3 are consecutive. The adapter card design dictates this — the driver adapts via pin parameters.

---

## 10. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| CMD line bidirectional timing | Medium | Start with bit-bang CMD, optimize later |
| CRC-16 x 4 performance | Low | Software post-process; GETCRC is fast |
| Pin adjacency constraint | Low | Adapter card designed for this |
| SD native init complexity | Medium | Well-documented in SD spec; many reference implementations |
| CMD23 might still fail | Low | CMD12 tolerance already works; keep as fallback |
| File size growth | Low | ~1000 lines added, well-sectioned |

---

## 11. Summary

Adding 6-wire SD native mode is architecturally clean because the driver already has a natural transport/filesystem boundary. The P2 streamer's `X_4P_4DAC1_WFBYTE` and `X_RFBYTE_4P_4DAC1` modes provide hardware-accelerated 4-bit DMA for adjacent pins — the same pattern we use today for 1-bit SPI, just wider.

The recommended approach is **Approach C (Hybrid)**: organize transport methods into a marked section, use `#ifdef SD_4BIT_MODE` at the section level, write parallel 4-bit implementations. The filesystem layer (~4,000 lines) is untouched. Compile-time switching means zero overhead for either mode.

The 4x wire throughput improvement at the same clock frequency is the headline benefit. Combined with CMD23 (which may work in native mode), this could eliminate both the CMD12 timing race and the serial bottleneck in a single change.

---

*Preliminary assessment — Iron Sheep Productions, 2026-03-06*
