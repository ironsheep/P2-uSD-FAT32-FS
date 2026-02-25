# Phase 1: Smart Pin SPI Implementation - Detailed Plan

**Phase Goal**: Replace bit-banged SPI with smart pins AND add multi-block operations for maximum throughput
**Status**: COMPLETE (2026-01-29)
**Parent Plan**: SPRINT-PLAN-driver-performance.md
**Created**: 2026-01-21

---

## Executive Summary

This phase replaces the current bit-banged SPI implementation with P2 smart pins AND adds multi-block operations, providing:
1. **Sysclk independence** - Same SPI speed regardless of CPU clock (270, 320, etc.)
2. **Higher throughput** - Hardware-timed transfers eliminate instruction overhead
3. **Reduced command overhead** - Multi-block reads/writes eliminate per-sector command cycles
4. **Foundation for Phase 2** - Enables precise speed control for adaptive timing

**Scope Addition**: Multi-block operations (CMD18/CMD25) from Phase 3 are incorporated here to establish complete baseline measurements before further optimization.

---

## Current Implementation Analysis

### Baseline Performance (from BENCHMARK-RESULTS.md)

| Metric | Current | Target |
|--------|---------|--------|
| SPI Clock | ~20 MHz | 25-50 MHz |
| Read 256KB | 1,467 KB/s | 4,000+ KB/s |
| Write 32KB | 425 KB/s | 1,200+ KB/s |
| Efficiency | 60% | 90%+ |

### Current SPI Functions (SD_card_driver.spin2)

#### 1. `transfer()` - General Purpose (line 1631-1650)
```spin2
PRI transfer(data,bits) : result | _cs, _mosi, _miso, _sck, delay
  ' Bit-banged SPI with REP loop
  ' ~18 cycles/bit at 320 MHz = ~17.7 MHz SPI
```
**Usage**: Commands, responses, single-byte operations
**Limitations**:
- Speed tied to sysclk
- Full-duplex (TX and RX simultaneous)
- REP overhead per transfer

#### 2. `readSector()` - Optimized Read (line 1507-1560)
```spin2
PRI readSector(sector) : result | ...
  ' Inline PASM with WRFAST for DMA-like writes to hub
  ' Waits for start token ($FE)
  ' Reads 512 bytes (128 longs) plus CRC
```
**Usage**: All sector reads
**Limitations**:
- Wait loop for start token is bit-banged
- Speed limited by instruction timing

#### 3. `writeSector()` - Optimized Write (line 1561-1629)
```spin2
PRI writeSector(sector) : result | ...
  ' Inline PASM with RDFAST for DMA-like reads from hub
  ' Sends start token, 512 bytes, CRC
  ' Spin2 handles response/busy wait
```
**Usage**: All sector writes
**Limitations**:
- Data transfer is fast, but response/busy handling is slow

#### 4. `cmd()` - Command Layer (line 1479-1506)
```spin2
PRI cmd(op,parm) : result | t
  ' Uses transfer() for each component
  ' Special handling for CMD8, CMD58 (32-bit response)
```
**Usage**: All SD commands
**Limitations**: Multiple transfer() calls add overhead

---

## Smart Pin Architecture

### Pin Assignments

| Pin Function | Current | Smart Pin Mode | Notes |
|--------------|---------|----------------|-------|
| CS | GPIO | GPIO (unchanged) | Active-low chip select |
| MOSI | Bit-bang | P_SYNC_TX | Synchronized to SCK |
| MISO | Bit-bang | P_SYNC_RX | Synchronized to SCK |
| SCK | Bit-bang | P_TRANSITION | Clock generation |

### Smart Pin Mode Details (from P2KB)

#### SCK: P_TRANSITION Mode (%00101)
```
Purpose: Generate precise SPI clock
X[15:0] = Period in clocks between transitions
Y = Number of transitions (2 per bit)
IN flag = High when complete
```

**Speed Calculation**:
```spin2
' For target SPI frequency:
x_period := clkfreq / (target_spi_freq * 2)

' Examples at 320 MHz:
'   25 MHz SPI: x_period = 320_000_000 / (25_000_000 * 2) = 6
'   50 MHz SPI: x_period = 320_000_000 / (50_000_000 * 2) = 3

' Examples at 270 MHz:
'   25 MHz SPI: x_period = 270_000_000 / (25_000_000 * 2) = 5
'   45 MHz SPI: x_period = 270_000_000 / (45_000_000 * 2) = 3
```

#### MOSI: P_SYNC_TX Mode (%11100)
```
Purpose: Transmit data synchronized to external clock
X[5] = 0 (continuous) or 1 (start-stop)
X[4:0] = bit_count - 1 (e.g., 7 for 8 bits)
Y = Data to transmit (LSB first - needs REV for SD)
IN flag = High when buffer empty
```

**MSB-First Workaround** (SD cards are MSB-first, smart pins are LSB-first):
```spin2
' For 8-bit transmission:
data := REV data >> 24    ' Reverse and right-justify

' For 32-bit transmission:
data := REV data          ' Just reverse
```

#### MISO: P_SYNC_RX Mode (%11101)
```
Purpose: Receive data synchronized to external clock
X[5] = 0 (sample before edge) or 1 (sample on edge)
X[4:0] = bit_count - 1
Z = Received data (left-justified - needs SHR)
IN flag = High when reception complete
```

**Data Extraction**:
```spin2
' For 8-bit reception:
data := RDPIN(miso) >> 24    ' Right-justify from left

' For 32-bit reception:
data := RDPIN(miso)          ' Already full width
data := REV data             ' Reverse for MSB-first
```

---

## Implementation Strategy

### Approach: Hybrid Smart Pin + Fallback

1. **New smart pin functions** alongside existing bit-bang
2. **Gradual migration** - test each function independently
3. **Fallback option** - keep bit-bang for debugging/compatibility

### New Functions to Implement

```
┌─────────────────────────────────────────────────────────────────┐
│                     New Smart Pin Functions                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  initSPIPins()           - Configure smart pins at startup      │
│  setSPISpeed(freq)       - Set SPI clock frequency              │
│  sp_transfer(data,bits)  - Smart pin byte/word transfer         │
│  sp_readSector(sector)   - Smart pin 512-byte read              │
│  sp_writeSector(sector)  - Smart pin 512-byte write             │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                     Multi-Block Operations                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  readSectors(start,count,buf)   - CMD18 multi-block read        │
│  writeSectors(start,count,buf)  - CMD25 multi-block write       │
│  sendStopTransmission()         - CMD12 stop command            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Task Breakdown

### Task 1.1: Smart Pin Initialization

**Goal**: Configure all 4 SPI pins with appropriate smart pin modes

**Implementation**:
```spin2
DAT
  ' Smart pin configuration constants
  spi_clk_mode    LONG  P_TRANSITION | P_OE
  spi_tx_mode     LONG  P_SYNC_TX | P_OE
  spi_rx_mode     LONG  P_SYNC_RX

PRI initSPIPins() | clk_period
  '' Configure smart pins for SPI operation
  '' Called once during start() after pin assignment

  ' CS remains standard GPIO (no smart pin)
  pinh(cs)                              ' Deselect

  ' SCK - Transition mode for clock generation
  pinclear(sck)
  wrpin(sck, spi_clk_mode)
  ' X register set by setSPISpeed()

  ' MOSI - Sync TX, clocked by SCK
  pinclear(mosi)
  wrpin(mosi, spi_tx_mode | (sck - mosi) << 24)  ' B-input from SCK
  wxpin(mosi, %1_00111)                 ' Start-stop, 8-bit
  dirh(mosi)                            ' Enable

  ' MISO - Sync RX, clocked by SCK
  pinclear(miso)
  wrpin(miso, spi_rx_mode | (sck - miso) << 24)  ' B-input from SCK
  wxpin(miso, %0_00111)                 ' Pre-edge sample, 8-bit
  dirh(miso)                            ' Enable

  ' Set initial speed (400 kHz for card init)
  setSPISpeed(400_000)
```

**Files Modified**: `src/SD_card_driver.spin2`
**Lines Affected**: New DAT constants (~line 100), new PRI function
**Testing**: Verify pin configuration with debug output

---

### Task 1.2: SPI Speed Control

**Goal**: Function to set SPI clock frequency independent of sysclk

**Implementation**:
```spin2
DAT
  spi_period      LONG  0               ' Current clock period
  spi_freq        LONG  0               ' Current frequency (for reference)

PRI setSPISpeed(freq) | period
  '' Set SPI clock frequency
  '' @param freq - Target frequency in Hz (e.g., 25_000_000)

  period := clkfreq / (freq * 2)
  if period < 2
    period := 2                         ' Minimum safe period

  ' Update SCK transition period
  wxpin(sck, period)

  ' Store for reference
  spi_period := period
  spi_freq := clkfreq / (period * 2)    ' Actual achieved frequency

  debug("  [setSPISpeed] Target=", udec(freq/1000), "kHz, Actual=", udec(spi_freq/1000), "kHz")
```

**Speed Table** (at various sysclk):

| sysclk | Target | Period | Actual |
|--------|--------|--------|--------|
| 320 MHz | 25 MHz | 6 | 26.7 MHz |
| 320 MHz | 50 MHz | 3 | 53.3 MHz |
| 270 MHz | 25 MHz | 5 | 27.0 MHz |
| 270 MHz | 45 MHz | 3 | 45.0 MHz |
| 200 MHz | 25 MHz | 4 | 25.0 MHz |
| 200 MHz | 50 MHz | 2 | 50.0 MHz |

**Testing**: Measure with logic analyzer at different sysclk settings

---

### Task 1.3: Smart Pin Transfer Function

**Goal**: Replace bit-banged `transfer()` with smart pin version

**Implementation**:
```spin2
PRI sp_transfer(data, bits) : result | rev_data, transitions
  '' Transfer data using smart pins (full-duplex)
  '' @param data - Data to transmit (MSB-first expected)
  '' @param bits - Number of bits (8 or 32)
  '' @return - Received data (MSB-first)

  ' Prepare TX data (reverse for LSB-first smart pin)
  if bits == 8
    rev_data := (REV data) >> 24
  else
    rev_data := REV data

  ' Configure bit count
  wxpin(mosi, %1_00000 | (bits - 1))    ' Start-stop mode, N bits
  wxpin(miso, %0_00000 | (bits - 1))    ' Pre-edge sample, N bits

  ' Load TX data
  wypin(mosi, rev_data)

  ' Generate clock pulses (2 transitions per bit)
  transitions := bits * 2
  wypin(sck, transitions)
  dirh(sck)                             ' Start clock

  ' Wait for completion (IN flag on SCK)
  repeat until pinr(sck) & $8000_0000

  ' Read RX data
  result := rdpin(miso)

  ' Reverse and justify for MSB-first
  if bits == 8
    result := (REV result) & $FF
  else
    result := REV result
```

**Compatibility Notes**:
- Same signature as original `transfer()`
- Can be swapped in-place for testing

**Testing**:
- Test CMD0, CMD8, CMD58 responses
- Verify byte ordering with known values

---

### Task 1.4: Smart Pin Sector Read

**Goal**: High-speed 512-byte read using smart pins

**Implementation Strategy**:

The current `readSector()` has two phases:
1. **Wait for start token** ($FE) - polling loop
2. **Read 512 bytes** - fast PASM loop

For smart pins:
1. Wait for start token using sp_transfer() or small polling loop
2. Bulk read using smart pin with WRFAST

```spin2
PRI sp_readSector(sector) : result | ptr, transitions, i
  '' Read sector using smart pins
  '' @param sector - Sector number
  '' @return - 0 on success, -1 on timeout

  if sector == sec_in_buf
    return 0
  sec_in_buf := sector

  ' Send CMD17 (READ_SINGLE_BLOCK)
  cmd(17, sector << hcs)

  ' Wait for start token ($FE)
  result := waitStartToken()
  if result < 0
    pinh(cs)
    return result

  ' Configure for 32-bit reception (4 bytes at a time)
  wxpin(miso, %0_11111)                 ' Pre-edge, 32-bit

  ' Read 512 bytes = 128 longs
  ptr := @buf
  repeat i from 0 to 127
    ' Clock 32 bits
    wypin(sck, 64)                      ' 64 transitions = 32 bits
    dirh(sck)
    repeat until pinr(sck) & $8000_0000

    ' Read and store (with byte swap for MSB-first)
    long[ptr] := REV rdpin(miso)
    ptr += 4

  ' Read and discard CRC (16 bits)
  wxpin(miso, %0_01111)                 ' 16-bit
  wypin(sck, 32)
  dirh(sck)
  repeat until pinr(sck) & $8000_0000
  rdpin(miso)                           ' Discard

  pinh(cs)
  return 0

PRI waitStartToken() : result | t, byte
  '' Wait for data start token ($FE)
  '' @return - 0 on success, -1 on timeout

  wxpin(miso, %0_00111)                 ' 8-bit mode
  t := getct() + clkfreq                ' 1 second timeout

  repeat
    wypin(sck, 16)                      ' 16 transitions = 8 bits
    dirh(sck)
    repeat until pinr(sck) & $8000_0000
    byte := (REV rdpin(miso)) >> 24

    if byte == $FE
      return 0
    if byte <> $FF
      debug("  [waitStartToken] Unexpected: $", uhex_(byte))
    if getct() - t > 0
      debug("  [waitStartToken] TIMEOUT")
      return -1
```

**Optimization**: The inner loop can be further optimized with inline PASM, similar to the current `readSector()`.

**Testing**:
- Compare read data with bit-banged version
- Measure throughput improvement

---

### Task 1.5: Smart Pin Sector Write

**Goal**: High-speed 512-byte write using smart pins

**Implementation**:
```spin2
PRI sp_writeSector(sector) : result | ptr, data, i, resp, t
  '' Write sector using smart pins
  '' @param sector - Sector number
  '' @return - true on success, false on failure

  ' Send CMD24 (WRITE_BLOCK)
  cmd(24, sector << hcs)

  ' Send data start token ($FE)
  sp_transfer($FE, 8)

  ' Configure for 32-bit transmission
  wxpin(mosi, %1_11111)                 ' Start-stop, 32-bit

  ' Send 512 bytes = 128 longs
  ptr := @buf
  repeat i from 0 to 127
    data := REV long[ptr]               ' Reverse for LSB-first TX
    wypin(mosi, data)
    wypin(sck, 64)                      ' 64 transitions = 32 bits
    dirh(sck)
    repeat until pinr(sck) & $8000_0000
    ptr += 4

  ' Send dummy CRC (2 bytes = 16 bits)
  wxpin(mosi, %1_01111)                 ' 16-bit
  wypin(mosi, $FFFF)
  wypin(sck, 32)
  dirh(sck)
  repeat until pinr(sck) & $8000_0000

  ' Wait for data response token
  wxpin(mosi, %1_00111)                 ' Back to 8-bit
  wxpin(miso, %0_00111)

  t := getct() + clkfreq / 10           ' 100ms timeout
  repeat
    resp := sp_transfer($FF, 8)
    if resp <> $FF
      quit
    if getct() - t > 0
      debug("  [sp_writeSector] TIMEOUT waiting for response")
      pinh(cs)
      return false

  ' Verify response (0x05 = data accepted)
  if (resp & $1F) <> $05
    debug("  [sp_writeSector] Data rejected: $", uhex_(resp))
    pinh(cs)
    return false

  ' Wait for busy complete
  t := getct() + clkfreq / 2            ' 500ms timeout
  repeat
    resp := sp_transfer($FF, 8)
    if resp == $FF
      quit
    if getct() - t > 0
      debug("  [sp_writeSector] TIMEOUT waiting for busy")
      pinh(cs)
      return false

  pinh(cs)
  return true
```

**Testing**:
- Write known patterns, read back with bit-banged version
- Test with PNY card (known to be sensitive to timing)

---

### Task 1.6: Integration with initCard()

**Goal**: Use smart pins during card initialization

**Changes to initCard()**:

```spin2
PRI initCard() : result | t, resp, card_version, acmd41_arg
  ' ... existing Step 1-3 unchanged (power-on, 74 clocks) ...

  ' STEP 2: Configure smart pins (instead of bit_delay)
  initSPIPins()
  setSPISpeed(400_000)                  ' 400 kHz for init

  ' ... Steps 4-7 use smart pin transfer ...

  ' STEP 8: Switch to high speed
  pinh(cs)                              ' CS HIGH before speed change
  setSPISpeed(25_000_000)               ' Target 25 MHz

  ' Send dummy clocks with CS HIGH
  repeat 8
    sp_transfer($FF, 8)
```

**Compatibility Consideration**:
- Keep bit_delay variable for potential fallback
- Add conditional compilation or runtime switch if needed

---

### Task 1.7: Regression Testing

**Goal**: Verify all existing functionality works with smart pins

**Test Plan**:

| Test File | Purpose | Expected Result |
|-----------|---------|-----------------|
| SD_RT_mount_tests.spin2 | Card init, filesystem parsing | PASS |
| SD_RT_file_ops_tests.spin2 | Create/open/close/delete | PASS |
| SD_RT_read_write_tests.spin2 | Data integrity | PASS |
| SD_RT_directory_tests.spin2 | Directory operations | PASS |
| SD_RT_seek_tests.spin2 | File positioning | PASS |
| SD_RT_performance_benchmark.spin2 | Speed measurements | Improved |

**Test Matrix**:

| Card | Mount | Read | Write | Speed |
|------|-------|------|-------|-------|
| Gigastone 32GB | ○ | ○ | ○ | ○ |
| PNY 16GB | ○ | ○ | ○ | ○ |
| SanDisk Extreme 64GB | ○ | ○ | ○ | ○ |

---

### Task 1.8: Multi-Block Read (CMD18)

**Goal**: Implement multi-sector read for reduced command overhead

**Protocol** (from SD Spec):
```
CMD18 (READ_MULTIPLE_BLOCK):
  Command: 0x52 + 32-bit start sector + CRC
  Response: R1 ($00 = OK)

  For each sector:
    Wait for data token ($FE)
    Read 512 bytes
    Read 2 CRC bytes

  Send CMD12 (STOP_TRANSMISSION) to end
  Wait for card ready ($FF)
```

**Implementation**:
```spin2
CON
  CMD12 = 12      ' STOP_TRANSMISSION
  CMD18 = 18      ' READ_MULTIPLE_BLOCK

PRI readSectors(start_sector, count, p_buffer) : result | i, resp
  '' Read multiple consecutive sectors using CMD18
  '' @param start_sector - First sector to read
  '' @param count - Number of sectors to read
  '' @param p_buffer - Pointer to buffer (must be count * 512 bytes)
  '' @return - Number of sectors successfully read

  if count == 0
    return 0
  if count == 1
    ' Fall back to single-sector read
    readSector(start_sector)
    bytemove(p_buffer, @buf, 512)
    return 1

  ' Send CMD18 (READ_MULTIPLE_BLOCK)
  transfer(-1, 8)
  pinl(cs)
  transfer(-1, 8)
  transfer($40 | CMD18, 8)
  transfer(start_sector << hcs, 32)
  transfer($FF, 8)                      ' CRC (ignored in SPI mode)

  ' Wait for R1 response
  resp := waitR1Response()
  if resp <> $00
    debug("  [readSectors] CMD18 failed: $", uhex_(resp))
    pinh(cs)
    return 0

  ' Read each sector
  result := 0
  repeat i from 0 to count - 1
    ' Wait for data token ($FE)
    if waitDataToken() < 0
      debug("  [readSectors] Timeout waiting for sector ", udec_(i))
      quit

    ' Read 512 bytes into buffer
    readSectorData(p_buffer + i * 512)
    result++

  ' Send CMD12 to stop transmission
  sendStopTransmission()
  pinh(cs)

PRI waitR1Response() : resp | t
  '' Wait for R1 response (non-$FF byte)
  t := getct() + clkfreq / 10           ' 100ms timeout
  repeat
    resp := transfer(-1, 8)
    if resp <> $FF
      return resp
    if getct() - t > 0
      return $FF                        ' Timeout

PRI waitDataToken() : result | t, byte
  '' Wait for data start token ($FE)
  '' @return - 0 on success, -1 on timeout or error
  t := getct() + clkfreq                ' 1 second timeout
  repeat
    byte := transfer(-1, 8)
    if byte == $FE
      return 0
    if byte <> $FF
      debug("  [waitDataToken] Error token: $", uhex_(byte))
      return -1
    if getct() - t > 0
      return -1

PRI readSectorData(p_dest) | _miso, _sck, data, loop_ctr, ptr
  '' Read 512 bytes + CRC into destination buffer
  '' Uses optimized inline PASM
  longmove(@_miso, @miso, 2)
  ptr := p_dest

  org
                drvl      _sck
                wrfast    ##$8000_0000, ptr
                mov       loop_ctr, #512/4
  .read_loop
                rep       @.end_rep, #32
                 drvl     _sck
                 rcl      data, #1
                 drvh     _sck
                 testp    _miso           wc
  .end_rep
                rcl       data, #1
                movbyts   data, #%%0123
                wflong    data
                djnz      loop_ctr, #.read_loop
                ' Read 16 CRC bits (discard)
                rep       @.crc_end, #16
                 drvl     _sck
                 nop
                 drvh     _sck
                 nop
  .crc_end
  end

PRI sendStopTransmission() | resp, t
  '' Send CMD12 to stop multi-block operation
  '' CMD12 has special timing - send after last data byte

  ' Send CMD12
  transfer($40 | CMD12, 8)
  transfer(0, 32)                       ' Argument (ignored)
  transfer($61, 8)                      ' CRC for CMD12

  ' Skip stuff byte (card may send one extra byte)
  transfer(-1, 8)

  ' Wait for R1 response
  resp := waitR1Response()

  ' Wait for card ready (not busy)
  t := getct() + clkfreq / 2            ' 500ms timeout
  repeat
    resp := transfer(-1, 8)
    if resp == $FF
      return
    if getct() - t > 0
      debug("  [sendStopTransmission] Timeout waiting for ready")
      return
```

**Expected Performance Gain**:
- Eliminates 6 command bytes + response per sector after the first
- ~10-15% improvement for multi-sector reads
- Greater improvement at higher sector counts

**Testing**:
- Read 8 consecutive sectors, verify data matches single-sector reads
- Benchmark vs 8 individual readSector() calls

---

### Task 1.9: Multi-Block Write (CMD25)

**Goal**: Implement multi-sector write for reduced command overhead

**Protocol** (from SD Spec):
```
CMD25 (WRITE_MULTIPLE_BLOCK):
  Command: 0x59 + 32-bit start sector + CRC
  Response: R1 ($00 = OK)

  For each sector:
    Send data token ($FC for multi-block, NOT $FE!)
    Send 512 bytes
    Send 2 CRC bytes
    Wait for data response (xxx00101 = accepted)
    Wait for busy complete ($FF)

  Send Stop Token ($FD)
  Wait for card ready ($FF)
```

**Key Differences from Single-Block**:
- Data token is `$FC` (not `$FE`)
- Stop token is `$FD` (not a command)
- No CMD12 needed for writes

**Implementation**:
```spin2
CON
  CMD25 = 25      ' WRITE_MULTIPLE_BLOCK
  TOKEN_MULTI_WRITE = $FC   ' Data token for multi-block write
  TOKEN_STOP_TRAN  = $FD    ' Stop token for multi-block write

PRI writeSectors(start_sector, count, p_buffer) : result | i, resp
  '' Write multiple consecutive sectors using CMD25
  '' @param start_sector - First sector to write
  '' @param count - Number of sectors to write
  '' @param p_buffer - Pointer to data (must be count * 512 bytes)
  '' @return - Number of sectors successfully written

  if count == 0
    return 0
  if count == 1
    ' Fall back to single-sector write
    bytemove(@buf, p_buffer, 512)
    if writeSector(start_sector)
      return 1
    return 0

  ' Send CMD25 (WRITE_MULTIPLE_BLOCK)
  transfer(-1, 8)
  pinl(cs)
  transfer(-1, 8)
  transfer($40 | CMD25, 8)
  transfer(start_sector << hcs, 32)
  transfer($FF, 8)                      ' CRC (ignored in SPI mode)

  ' Wait for R1 response
  resp := waitR1Response()
  if resp <> $00
    debug("  [writeSectors] CMD25 failed: $", uhex_(resp))
    pinh(cs)
    return 0

  ' Write each sector
  result := 0
  repeat i from 0 to count - 1
    ' Send multi-block data token ($FC)
    transfer(TOKEN_MULTI_WRITE, 8)

    ' Send 512 bytes from buffer
    writeSectorData(p_buffer + i * 512)

    ' Send dummy CRC (2 bytes)
    transfer($FF, 8)
    transfer($FF, 8)

    ' Wait for data response
    resp := waitDataResponse()
    if (resp & $1F) <> $05
      debug("  [writeSectors] Sector ", udec_(i), " rejected: $", uhex_(resp))
      quit

    ' Wait for programming complete
    if waitBusyComplete() < 0
      debug("  [writeSectors] Timeout on sector ", udec_(i))
      quit

    result++

  ' Send stop token ($FD)
  transfer(TOKEN_STOP_TRAN, 8)

  ' Skip stuff byte
  transfer(-1, 8)

  ' Wait for card ready
  if waitBusyComplete() < 0
    debug("  [writeSectors] Timeout after stop token")

  pinh(cs)

PRI writeSectorData(p_src) | _mosi, _sck, data, loop_ctr, ptr
  '' Write 512 bytes from source buffer
  '' Uses optimized inline PASM
  longmove(@_mosi, @mosi, 2)
  ptr := p_src

  org
                drvl      _sck
                rdfast    ##$8000_0000, ptr
                mov       loop_ctr, #512/4
  .write_loop
                rflong    data
                movbyts   data, #%%0123
                rep       @.end_rep, #32
                 rol      data, #1        wc
                 drvl     _sck
                 drvc     _mosi
                 drvh     _sck
  .end_rep
                drvh      _mosi
                djnz      loop_ctr, #.write_loop
  end

PRI waitDataResponse() : resp | t
  '' Wait for data response token after write
  t := getct() + clkfreq / 10           ' 100ms timeout
  repeat
    resp := transfer(-1, 8)
    if resp <> $FF
      return resp
    if getct() - t > 0
      return $FF

PRI waitBusyComplete() : result | t, resp
  '' Wait for card to finish programming (MISO goes HIGH)
  '' @return - 0 on success, -1 on timeout
  t := getct() + clkfreq / 2            ' 500ms timeout per sector
  repeat
    resp := transfer(-1, 8)
    if resp == $FF
      return 0
    if getct() - t > 0
      return -1
```

**Expected Performance Gain**:
- Eliminates 6 command bytes + response per sector after the first
- Card can optimize internal flash writes for sequential access
- ~20-40% improvement expected for multi-sector writes
- Greater improvement with larger write counts

**Testing**:
- Write 8 consecutive sectors, read back and verify
- Test with PNY card (sensitive to timing)
- Benchmark vs 8 individual writeSector() calls

---

### Task 1.10: Multi-Block Benchmark

**Goal**: Measure performance improvement from multi-block operations

**Test Cases**:

| Test | Single-Sector | Multi-Block | Expected Gain |
|------|---------------|-------------|---------------|
| Read 8 sectors | 8× CMD17 | 1× CMD18 | 10-15% |
| Read 64 sectors | 64× CMD17 | 1× CMD18 | 15-25% |
| Write 8 sectors | 8× CMD24 | 1× CMD25 | 20-30% |
| Write 64 sectors | 64× CMD24 | 1× CMD25 | 30-40% |

**Benchmark Function**:
```spin2
PRI benchmarkMultiBlock() | t, single_time, multi_time, i
  '' Compare single-sector vs multi-sector performance

  debug("=== Multi-Block Benchmark ===")

  ' Prepare test data
  repeat i from 0 to 511
    buf[i] := i

  ' --- READ TEST (64 sectors = 32KB) ---
  debug("Read 64 sectors:")

  ' Single-sector method
  t := getct()
  repeat i from 0 to 63
    readSector(1000 + i)
  single_time := getct() - t

  ' Multi-sector method
  t := getct()
  readSectors(1000, 64, @large_buffer)
  multi_time := getct() - t

  debug("  Single: ", udec(single_time / (clkfreq/1000)), " ms")
  debug("  Multi:  ", udec(multi_time / (clkfreq/1000)), " ms")
  debug("  Gain:   ", udec(single_time * 100 / multi_time), "%")

  ' --- WRITE TEST (64 sectors = 32KB) ---
  debug("Write 64 sectors:")

  ' Single-sector method
  t := getct()
  repeat i from 0 to 63
    writeSector(2000 + i)
  single_time := getct() - t

  ' Multi-sector method
  t := getct()
  writeSectors(2000, 64, @large_buffer)
  multi_time := getct() - t

  debug("  Single: ", udec(single_time / (clkfreq/1000)), " ms")
  debug("  Multi:  ", udec(multi_time / (clkfreq/1000)), " ms")
  debug("  Gain:   ", udec(single_time * 100 / multi_time), "%")
```

---

## Risk Mitigation

### Risk 1: Smart Pin Timing Issues

**Concern**: Clock and data may not align correctly
**Mitigation**:
- Start with conservative timing (X[5]=0 on MISO for pre-edge sampling)
- Test with logic analyzer
- Keep bit-banged fallback

### Risk 2: MSB/LSB Reversal Overhead

**Concern**: REV instructions may add significant overhead
**Mitigation**:
- REV is single-cycle instruction
- Profile actual impact
- Consider byte-swapping in bulk operations

### Risk 3: PNY Card Compatibility

**Concern**: PNY cards required special busy-wait handling
**Mitigation**:
- Test PNY card early and often
- Ensure busy-wait timing unchanged
- May need clock generation during busy polling

### Risk 4: Initialization Sequence Sensitivity

**Concern**: Some cards sensitive to exact init timing
**Mitigation**:
- Use bit-bang for init clocks (74+ pulses with CS high)
- Only switch to smart pins after CMD0
- Test with all available cards

### Risk 5: Multi-Block CMD12 Timing

**Concern**: CMD12 (STOP_TRANSMISSION) has special timing requirements
**Mitigation**:
- Send CMD12 immediately after last data byte CRC
- Handle "stuff byte" that some cards send before R1
- Add adequate timeout for busy period after stop
- Test extensively with PNY card (most timing-sensitive)

### Risk 6: Multi-Block Write Token Confusion

**Concern**: Multi-block uses different tokens ($FC data, $FD stop) than single-block ($FE)
**Mitigation**:
- Define clear constants: TOKEN_MULTI_WRITE, TOKEN_STOP_TRAN
- Verify response token (0x05) after each sector
- Handle partial write failures gracefully

---

## Implementation Order

### Part A: Smart Pin Foundation
1. **Task 1.1**: initSPIPins() - Basic smart pin setup
2. **Task 1.2**: setSPISpeed() - Clock frequency control
3. **Task 1.3**: sp_transfer() - Replace basic transfer
4. **Task 1.7**: Run regression tests (partial)

### Part B: Smart Pin Sector Operations
5. **Task 1.4**: sp_readSector() - Optimize reads
6. **Task 1.7**: Run read tests
7. **Task 1.5**: sp_writeSector() - Optimize writes
8. **Task 1.7**: Run write tests
9. **Task 1.6**: Integration with initCard()
10. **Task 1.7**: Full regression test suite

### Part C: Multi-Block Operations
11. **Task 1.8**: readSectors() - CMD18 multi-block read
12. **Task 1.9**: writeSectors() - CMD25 multi-block write
13. **Task 1.10**: Multi-block benchmark
14. **Task 1.7**: Final regression test suite with all features

---

## Success Criteria

### Smart Pin Criteria
| Criteria | Target | Measurement |
|----------|--------|-------------|
| All regression tests pass | 100% | Run test suite |
| SPI speed at 25+ MHz | 25 MHz | Logic analyzer |
| Same speed at 270/320 MHz sysclk | ±5% | Benchmark at both clocks |
| Single-sector read improvement | 2× baseline | Benchmark |
| No card-specific failures | 0 | Test all cards |

### Multi-Block Criteria
| Criteria | Target | Measurement |
|----------|--------|-------------|
| Multi-block read works | All 3 cards | Test CMD18 |
| Multi-block write works | All 3 cards | Test CMD25 |
| Multi-read gain (64 sectors) | >15% vs single | Benchmark |
| Multi-write gain (64 sectors) | >25% vs single | Benchmark |
| Data integrity verified | 100% | Read-back verification |

### Combined Performance Targets
| Metric | Baseline | Smart Pin Only | Smart Pin + Multi-Block |
|--------|----------|----------------|-------------------------|
| Read 256KB | 1,467 KB/s | 3,000+ KB/s | 4,000+ KB/s |
| Write 32KB | 425 KB/s | 900+ KB/s | 1,200+ KB/s |

---

## Appendix A: P2KB Reference

### P_SYNC_TX Mode Constants
```spin2
P_SYNC_TX     = %11100 << 1             ' Mode bits
P_OE          = %01 << 6                ' Output enable
P_INVERT_A    = %1 << 28                ' Invert A-input (data)
P_INVERT_B    = %1 << 27                ' Invert B-input (clock)
P_PLUS1_B     = %001 << 24              ' B-input from pin+1
```

### P_SYNC_RX Mode Constants
```spin2
P_SYNC_RX     = %11101 << 1
P_PLUS1_B     = %001 << 24              ' B-input from pin+1
```

### P_TRANSITION Mode Constants
```spin2
P_TRANSITION  = %00101 << 1
P_OE          = %01 << 6
```

---

## Appendix B: Pin Configuration Examples

### Adjacent Pins (optimal)
```
SCK  = P61 (P_TRANSITION)
MOSI = P59 (P_SYNC_TX, B-input = SCK via offset)
MISO = P58 (P_SYNC_RX, B-input = SCK via offset)
CS   = P60 (GPIO)
```

### B-Input Calculation
```spin2
' For P_SYNC_TX on MOSI (P59), clock on SCK (P61):
' Offset = SCK - MOSI = 61 - 59 = 2
' B-input mode: %010 << 24 for pin+2
```

---

*Document created: 2026-01-21*
*Status: COMPLETE*
*Phase: 1 of 6*
*Completed: 2026-01-29 - All 129 regression tests passing*
