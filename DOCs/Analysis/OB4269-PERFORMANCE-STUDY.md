# OB4269 FAT32 Driver - Performance Study

**Document Purpose**: Analysis of current performance limits and Smart Pin improvement opportunities
**Driver**: Chris Gadd's FAT32 SD Card Driver (OBEX 4269)
**Date**: 2026-01-14

---

## Executive Summary

The OB4269 driver uses bit-banged SPI with inline PASM2 for sector transfers. While the PASM2 implementation is well-optimized, significant performance improvements are possible by migrating to Smart Pin hardware SPI. The driver's architecture cleanly separates performance-critical regions, making targeted optimization feasible.

**Key Finding**: Smart Pins can provide hardware-accelerated SPI at up to sysclk/2 with autonomous operation, potentially doubling or tripling sector transfer speeds.

---

## Current Implementation Analysis

### Performance-Critical Code Regions

The driver has three performance tiers:

#### Tier 1: Hot Path (>90% of I/O time)

| Method | Lines | Purpose | Current Implementation |
|--------|-------|---------|------------------------|
| `readSector()` | 510-547 | Read 512 bytes from card | Inline PASM2 with FIFO |
| `writeSector()` | 549-585 | Write 512 bytes to card | Inline PASM2 with FIFO |

These two methods dominate I/O time. They are the primary optimization targets.

#### Tier 2: Supporting Operations (~8% of I/O time)

| Method | Lines | Purpose | Current Implementation |
|--------|-------|---------|------------------------|
| `transfer()` | 587-603 | Send/receive SPI bytes | Inline PASM2, bit-banged |
| `cmd()` | 487-508 | Send SD card commands | Uses transfer() |

Command overhead is unavoidable but relatively minor compared to data transfer.

#### Tier 3: Filesystem Operations (~2% of time)

| Method | Purpose | Notes |
|--------|---------|-------|
| `allocateCluster()` | FAT table management | CPU-bound, not I/O limited |
| `searchDirectory()` | Directory traversal | Calls readSector() repeatedly |
| `freeSpace()` | Count free clusters | Scans entire FAT - very slow on large cards |

---

### Current readSector() Implementation

```spin2
PRI readSector(sector) : result | _cs, _mosi, _miso, _sck, data, loop_ctr, ptr
  if sector == sec_in_buf
    return
  sec_in_buf := sector
  longmove(@_cs,@cs,4)
  ptr := @buf
  cmd(17,sector << hcs)

  org
                drvl      _sck
                wrfast    ##$8000_0000,ptr      ' Setup FIFO write to hub
                mov       loop_ctr,#512/4       ' 128 longs
.startloop
                drvh      _sck                  ' Wait for start token
                nop
                drvl      _sck
                testp     _miso           wc
  if_c          jmp       #.startloop
                outh      _sck
.read_loop
                rep       @.end_rep,#32         ' 32 bits per long
                 drvl     _sck                  ' Clock low
                 rcl      data,#1               ' Shift in bit
                 drvh     _sck                  ' Clock high
                 testp    _miso           wc    ' Sample MISO
.end_rep
                rcl       data,#1               ' Final bit
                movbyts   data,#%%0123          ' Byte swap (MSB first → LSB first)
                wflong    data                  ' Write to hub via FIFO
                djnz      loop_ctr,#.read_loop
                rep       @.rend15,#16          ' Clock out CRC (16 bits, ignored)
                 drvl     _sck
                 nop
                 drvh     _sck
                 nop
.rend15
  end
  pinh(cs)
```

**Analysis**:
- Uses REP for zero-overhead inner loop (excellent)
- Uses FIFO for hub writes (excellent)
- Bit-bangs SPI clock (bottleneck)
- Each bit requires 4 instructions: drvl, rcl, drvh, testp
- **Cycles per bit**: ~4 cycles (at best)
- **Cycles per byte**: ~32 cycles
- **Cycles per sector**: ~16,384 cycles + overhead

---

### Current writeSector() Implementation

```spin2
PRI writeSector(sector) : result | _cs, _mosi, _miso, _sck, data, loop_ctr, ptr, t
  longmove(@_cs,@cs,4)
  ptr := @buf
  cmd(24,sector << hcs)
  transfer($FE,8)                              ' Start token

  org
                drvl      _sck
                rdfast    ##8000_0000,ptr       ' Setup FIFO read from hub
                mov       loop_ctr,#512/4       ' 128 longs
.write_loop
                rflong    data                  ' Read from hub via FIFO
                movbyts   data,#%%0123          ' Byte swap
                rep       @.end_rep,#32         ' 32 bits per long
                 rol      data,#1         wc    ' Get MSB
                 drvl     _sck                  ' Clock low
                 drvc     _mosi                 ' Output bit
                 drvh     _sck                  ' Clock high
.end_rep
                drvh      _mosi
                djnz      loop_ctr,#.write_loop
  end
  ' ... wait for completion ...
```

**Analysis**:
- Similar structure to readSector()
- Uses REP and FIFO (excellent)
- **Cycles per bit**: ~4 cycles
- **Same bottleneck**: Bit-banged SPI clock

---

## Current Performance Limits

### Theoretical Maximum (Bit-Banged)

At sysclk = 300 MHz:
- **Bit time**: ~4 cycles = ~13.3 ns
- **Byte time**: ~32 cycles = ~107 ns
- **Max bit rate**: ~75 Mbps
- **Max byte rate**: ~9.4 MB/s (theoretical)

### Practical Maximum (with overhead)

- Command overhead: ~500 cycles per sector
- Wait states: Variable (card dependent)
- **Realistic throughput**: ~4-6 MB/s for sequential reads

### SD Card Limits

| Card Type | Max SPI Clock | Max Throughput |
|-----------|---------------|----------------|
| SD (SDSC) | 25 MHz | 3.1 MB/s |
| SDHC | 50 MHz | 6.25 MB/s |
| SDHC High-Speed | 50 MHz | 6.25 MB/s |

**Note**: SPI mode is always slower than native SD mode. Cards support up to 50 MHz SPI clock.

---

## Smart Pin SPI Opportunity

### Available Smart Pin Modes

| Mode | Name | Purpose |
|------|------|---------|
| %11100 | P_SYNC_TX | Hardware SPI transmit |
| %11101 | P_SYNC_RX | Hardware SPI receive |
| %00101 | P_TRANSITION | Clock generation |

### Smart Pin Advantages

1. **Autonomous Operation**: Smart pins shift bits independently of COG
2. **Maximum Speed**: Can operate at sysclk/2 (150 MHz at 300 MHz sysclk)
3. **Double Buffering**: TX has buffer for gapless streaming
4. **Event-Driven**: COG can sleep while waiting for completion

### Smart Pin SPI Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     P2 COG                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Hub RAM Buffer (512 bytes)                     │   │
│  └───────────────────┬─────────────────────────────┘   │
│                      │ FIFO                             │
│  ┌───────────────────▼─────────────────────────────┐   │
│  │  Smart Pin TX (%11100)  ◄──── WYPIN data        │   │
│  │    - 32-bit shift register                      │   │
│  │    - Double-buffered                            │───┼──► MOSI
│  │    - Autonomous shifting                        │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Smart Pin RX (%11101)  ───► RDPIN data         │   │
│  │    - 32-bit shift register                      │◄──┼─── MISO
│  │    - IN flag when complete                      │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Smart Pin CLK (%00101)                         │   │
│  │    - Transition output mode                     │───┼──► SCK
│  │    - Programmable frequency                     │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Regular I/O Pin                                │───┼──► CS
│  │    - Simple high/low control                    │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## Performance Improvement Estimate

### Smart Pin SPI Implementation

**Clock Configuration**:
- Use P_TRANSITION mode on SCK pin
- Set period for desired SPI clock (e.g., 50 MHz)
- Smart pin generates continuous clock

**Data Transfer**:
- Configure TX pin with P_SYNC_TX, 8 or 32 bits
- Configure RX pin with P_SYNC_RX, 8 or 32 bits
- Load 32 bits at a time, smart pin shifts autonomously

### Expected Performance

| Metric | Current (Bit-Bang) | Smart Pin | Improvement |
|--------|-------------------|-----------|-------------|
| Bits/cycle | 0.25 | 1.0+ | 4x |
| Bytes/sector read | ~16,384 cycles | ~4,096 cycles | 4x |
| COG utilization during I/O | 100% | ~25% | Can do other work |
| Max SPI clock | ~75 MHz | 150 MHz | 2x |

**Practical improvement**: 2-4x faster sector transfers

### Implementation Complexity

| Change | Effort | Risk |
|--------|--------|------|
| Replace readSector() | Medium | Low |
| Replace writeSector() | Medium | Low |
| Replace transfer() | Low | Low |
| Update initCard() | Low | Low |

---

## Recommended Optimization Approach

### Phase 1: Replace transfer() (Low Risk)

The `transfer()` method is used for commands and low-speed operations. Replace with Smart Pin implementation:

```spin2
PRI transfer(data, bits) : result | mode
  ' Configure smart pins for SPI transfer
  PINCLEAR(mosi)
  PINCLEAR(miso)
  WRPIN(mosi, P_SYNC_TX | P_OE)
  WRPIN(miso, P_SYNC_RX | P_PLUS1_B)  ' Clock from adjacent pin
  WXPIN(mosi, bits - 1)               ' Bit count
  WXPIN(miso, bits - 1)
  PINHIGH(mosi)
  PINHIGH(miso)

  ' Transmit data
  WYPIN(mosi, data << (32 - bits))

  ' Generate clock pulses
  ' ... clock generation code ...

  ' Read result
  REPEAT UNTIL PINREAD(miso) & $8000_0000
  result := RDPIN(miso) >> (32 - bits)
```

### Phase 2: Replace Sector Transfers (Medium Effort)

Replace the inline PASM2 in readSector() and writeSector() with Smart Pin operations:

```spin2
PRI readSector_smartpin(sector) | i, data
  if sector == sec_in_buf
    return
  sec_in_buf := sector
  cmd(17, sector << hcs)

  ' Wait for start token (0xFE)
  repeat until transfer(-1, 8) == $FE

  ' Configure for 32-bit transfers
  PINCLEAR(miso)
  WRPIN(miso, P_SYNC_RX)
  WXPIN(miso, 31)                     ' 32 bits
  PINHIGH(miso)

  ' Read 128 longs
  repeat i from 0 to 127
    ' Generate 32 clock pulses
    generate_clocks(32)
    ' Wait for reception complete
    repeat until PINREAD(miso) & $8000_0000
    data := RDPIN(miso)
    data := data REVERSEBITS          ' MSB to LSB conversion
    long[@buf + i * 4] := data

  ' Read and discard CRC
  transfer(-1, 16)
  pinh(cs)
```

### Phase 3: Optimize Clock Generation

Use P_TRANSITION mode for continuous clock:

```spin2
PRI setup_spi_clock(frequency)
  PINCLEAR(sck)
  WRPIN(sck, P_TRANSITION | P_OE)
  WXPIN(sck, clkfreq / (frequency * 2))  ' Half-period
  PINHIGH(sck)

PRI generate_clocks(count)
  WYPIN(sck, count * 2)                   ' Transitions = 2x clocks
  ' Wait for completion or use event
```

---

## Other Performance Opportunities

### 1. freeSpace() Optimization

**Current**: Scans entire FAT (can take seconds on 32 GB card)
**Fix**: Use FSInfo sector's FSI_Free_Count (instant)

```spin2
PUB freeSpace() : result
  if free_clusters >= 0
    return free_clusters * sec_per_clus  ' Instant!
  ' Fall back to scan if FSInfo unavailable
  ' ... existing scan code ...
```

### 2. Cluster Allocation Hint

**Current**: Always searches from cluster 2
**Fix**: Use FSI_Nxt_Free hint from FSInfo sector

```spin2
PRI allocateCluster(cluster) : result | fat_idx
  fat_idx := (next_free_hint << 2)       ' Start from hint
  ' ... rest of search ...
```

### 3. Read-Ahead Caching

**Current**: Single 512-byte buffer
**Potential**: Multi-sector read-ahead for sequential access

```spin2
' Could read multiple sectors when sequential access detected
PRI readSectorWithReadAhead(sector) | i
  if sequential_access_detected
    for i from 0 to READ_AHEAD_COUNT
      readSector(sector + i)             ' Fill cache
```

---

## Summary of Recommendations

### Priority 1: Cross-OS Fixes (Required)
See `OB4269-TECHNICAL-ADJUSTMENTS.md`
- FAT mirroring fix
- High 4 bits preservation
- FSInfo sector support

### Priority 2: Performance (Optional but Valuable)

| Optimization | Effort | Benefit | Risk |
|--------------|--------|---------|------|
| Smart Pin transfer() | Low | 2x command speed | Low |
| Smart Pin sector I/O | Medium | 2-4x data transfer | Low |
| FSInfo free space | Already in fixes | Instant freeSpace() | None |
| Allocation hint | Already in fixes | Faster file creation | None |

### Priority 3: Advanced (Future)

| Optimization | Effort | Benefit | Risk |
|--------------|--------|---------|------|
| Multi-sector reads | High | Better sequential perf | Medium |
| DMA-style streaming | High | Near-hardware speed | Medium |
| Multi-cog access | High | Concurrent I/O | High |

---

## PASM2 Conversion Analysis

### Current Implementation Status

The driver strategically uses inline PASM2 for the performance-critical data paths while keeping higher-level logic in Spin2.

#### Functions Already in PASM2

| Function | Lines | Purpose | PASM Technique |
|----------|-------|---------|----------------|
| `readSector()` | 763-791 | Read 512 bytes from card | `REP` loop, `wrfast`/`wflong` FIFO |
| `writeSector()` | 800-815 | Write 512 bytes to card | `REP` loop, `rdfast`/`rflong` FIFO |
| `transfer()` | 836-848 | SPI bit exchange | `REP` loop with `testp`/`drvc` |

These three functions handle >95% of the I/O time and are already optimized.

#### Functions in Spin2 (Analysis)

| Function | Lines | Spin2 Overhead | PASM Candidate? | Rationale |
|----------|-------|----------------|-----------------|-----------|
| `cmd()` | 727-753 | ~50 bytecodes/call | **Maybe** | Called every sector op, but logic is complex |
| `readNextSector()` | 555-563 | ~30 bytecodes | No | FAT chain logic, I/O bound anyway |
| `readFat()` | 521-523 | ~10 bytecodes | No | Trivial wrapper |
| `allocateCluster()` | 525-546 | ~80 bytecodes | No | Complex FAT traversal with conditionals |
| `searchDirectory()` | 438-493 | ~200 bytecodes | No | String handling, complex branching |
| `countFreeClusters()` | 261-275 | ~40 bytecodes | No | Called once on unmount only |
| `clus2sec()` / `sec2clus()` | 569-576 | ~5 bytecodes each | No | Simple math, negligible |

### Detailed Analysis of Potential Candidates

#### `cmd()` Function - Moderate Priority

**Current implementation**: Spin2 calling PASM `transfer()`

```
cmd() workflow:
1. transfer(-1, 8)      ← PASM
2. pinl(cs)             ← Spin2 (1 bytecode)
3. transfer(-1, 8)      ← PASM
4. transfer($40|op, 8)  ← PASM
5. transfer(parm, 32)   ← PASM
6. transfer(crc, 8)     ← PASM
7. repeat/transfer      ← Spin2 loop + PASM
8. pinh(cs)             ← Spin2 (1 bytecode)
```

**Analysis**: The actual SPI transfers are already PASM. The Spin2 overhead is:
- Function call/return: ~10 cycles
- Pin control: ~2 cycles each
- Loop control: ~5 cycles per iteration

**Verdict**: Converting `cmd()` to full PASM would save ~2-5µs per sector operation. This is measurable but minor compared to the ~100µs+ for actual data transfer.

#### `readNextSector()` Function - Not Recommended

**Reason**: This function's purpose is FAT chain traversal, which involves:
- Calculating cluster numbers (math)
- Calling `readSector()` for FAT lookup (already PASM)
- Conditional branching based on cluster boundaries

The I/O dominates; the Spin2 logic is not the bottleneck.

#### Filesystem Functions - Not Recommended

Functions like `searchDirectory()`, `allocateCluster()`, `deleteFile()` involve:
- Complex string manipulation
- Multiple conditional branches
- FAT table traversal with variable-length chains
- Directory entry parsing

These are poorly suited to PASM because:
1. Complex control flow is verbose in PASM
2. They're called infrequently (file open/close, not per-sector)
3. Spin2's readability aids maintenance

### PASM Conversion Decision Matrix

| Factor | Weight | `cmd()` | `readNextSector()` | `allocateCluster()` | `searchDirectory()` |
|--------|--------|---------|-------------------|--------------------|--------------------|
| Call frequency | High | Every sector | Sequential reads | File extend | File open |
| Current overhead | Medium | ~50 cycles | ~30 cycles | ~80 cycles | ~200 cycles |
| Code complexity | High | Medium | Medium | High | Very High |
| I/O bound? | High | No | Yes | Yes | Yes |
| **Recommendation** | - | **Maybe** | No | No | No |

### Conclusion: PASM Conversion

**The driver is already well-optimized.** The three critical data-path functions (`readSector()`, `writeSector()`, `transfer()`) are in PASM using P2's most efficient techniques:

1. **REP blocks** - Zero-overhead loops
2. **FIFO streaming** - `wrfast`/`rdfast` for hub access
3. **Bit-level operations** - `rcl`, `rol`, `testp`, `drvc`

**The only marginal candidate** is `cmd()`, which could be converted to save a few microseconds per sector. However:
- The improvement would be ~2-5% at best
- The current hybrid approach (Spin2 control + PASM transfer) is maintainable
- Smart Pin SPI (documented above) would provide much larger gains

**Recommendation**: Focus optimization efforts on Smart Pin SPI rather than converting more Spin2 to PASM. The current PASM coverage hits the critical 95% of I/O time.

---

## Future Investigation: Events and Interrupts

The P2 provides hardware mechanisms that could further optimize waiting:

### WAITX vs Active Polling

Current `transfer()` uses `waitx delay` for timing. For slower SPI clocks during init, this is appropriate.

### Event-Driven Waiting

For operations that wait on external conditions (card ready, response received), the P2 offers:

| Mechanism | Use Case | Benefit |
|-----------|----------|---------|
| `WAITSE1` | Wait for Smart Pin event | COG sleeps until data ready |
| `WAITATN` | Wait for interrupt | Multi-cog coordination |
| `POLLSE1` | Non-blocking check | Continue other work while waiting |
| `COGATN` | Signal between cogs | Async I/O notification |

### Potential Applications

1. **Card busy polling**: After write, card pulls MISO low while busy. Could use pin event instead of polling loop.
2. **Multi-cog I/O**: One cog handles SPI, signals completion to application cog.
3. **DMA-style streaming**: Smart Pins with events for continuous data flow.

*These techniques require P2KB documentation for proper implementation.*

---

## Conclusion

The OB4269 driver is well-implemented for a bit-banged approach. Smart Pin SPI offers the most significant performance improvement opportunity with moderate implementation effort. The existing code structure with separate readSector()/writeSector() methods makes targeted optimization straightforward.

**Key findings**:
1. **Already optimized**: readSector/writeSector/transfer are PASM with REP and FIFO
2. **Marginal gains available**: cmd() could be PASM but <5% improvement
3. **Best opportunity**: Smart Pin SPI for 2-4x data transfer speed
4. **Future potential**: Event-driven waiting for reduced CPU utilization

**Recommended next step**: Implement Smart Pin version of transfer() method as a proof-of-concept, then extend to sector operations if successful.

---

*Performance study prepared for P2 microSD FAT32 Filesystem project*
*Updated 2026-01-16: Added PASM2 conversion analysis*
