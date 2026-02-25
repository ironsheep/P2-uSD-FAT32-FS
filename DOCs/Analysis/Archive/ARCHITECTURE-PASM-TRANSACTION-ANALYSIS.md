# V2 Driver Architecture: Comprehensive PASM Transaction Analysis

**Date:** 2026-01-23
**Status:** Active Analysis
**Goal:** Maximize performance by consolidating time-critical operations into comprehensive PASM blocks

---

## 1. Design Philosophy

### Current Architecture Problem
The V2 driver has a dedicated worker cog running the Spin2 interpreter. Time-critical I/O operations are split across:
- Spin2 bytecode (non-deterministic timing)
- Small inline PASM blocks (deterministic, but with copy/execute/return overhead)
- Multiple Spin2↔PASM transitions per transaction

### Target Architecture
- **Spin2** handles orchestration: parameter setup, error handling, operation selection
- **Comprehensive PASM blocks** handle entire transactions: from intent to completion
- **Minimize transitions**: One PASM block per complete transaction
- **Minimize smart pin reconfigurations**: Setup once, use throughout
- **Use hardware timing**: CT events, WAITX, hardware polling instead of software loops

### Why This Works
The bottleneck is the SPI bus (~164 µs per sector at 25 MHz), not CPU overhead. Spin2 overhead between transactions is negligible. But WITHIN a transaction, cycle-deterministic PASM ensures:
- P2KB timing specs apply (2-cycle flag reset, 3-cycle output delay, etc.)
- Streamer alignment is precise
- No interpreter variability during time-critical sequences

---

## 2. Transaction Inventory

### 2.1 Single-Sector Read (CMD17)
**Current flow:**
```
Spin2: cmd(17, sector)              → calls sp_transfer (smart pin)
Spin2: wait for $FE token           → loop with sp_transfer_8
Spin2: pinclear(_miso)              → interpreter
Spin2: pinf(_miso)                  → interpreter
PASM:  org...end (streamer RX)      → 512 bytes via streamer
Spin2: wrpin/wxpin/pinh             → reconfigure smart pin
Spin2: sp_transfer_8 x2             → read CRC
Spin2: pinh(cs)                     → deselect
```

**Transitions:** 2 (Spin2→PASM→Spin2)
**Smart pin reconfigs:** 2 (disable for streamer, re-enable after)

### 2.2 Multi-Sector Read (CMD18)
**Current flow:**
```
Spin2: cmd(CMD18, sector)           → smart pin transfer
LOOP per sector:
  Spin2: waitDataToken()            → loop with sp_transfer_8
  Spin2: pinclear/pinf              → disable smart pin
  PASM:  org...end (streamer RX)    → 512 bytes
  Spin2: wrpin/wxpin/pinh           → re-enable smart pin
  Spin2: sp_transfer_8 x2           → CRC
Spin2: sendStopTransmission()       → CMD12
Spin2: pinh(cs)
```

**Transitions:** 2 × N sectors
**Smart pin reconfigs:** 2 × N sectors

### 2.3 Single-Sector Write (CMD24)
**Current flow:**
```
Spin2: cmd(24, sector)              → smart pin transfer
Spin2: sp_transfer_8($FE)           → data token
Spin2: pinclear/pinl(_mosi)         → disable smart pin
PASM:  org...end (streamer TX)      → 512 bytes
Spin2: wrpin/wxpin/pinh             → re-enable smart pin
Spin2: sp_transfer_8 x2             → CRC
Spin2: wait data response           → loop with sp_transfer_8
Spin2: wait busy complete           → loop with sp_transfer_8
Spin2: pinh(cs)
```

**Transitions:** 2
**Smart pin reconfigs:** 2

### 2.4 Multi-Sector Write (CMD25)
**Current flow:**
```
Spin2: cmd(CMD25, sector)           → smart pin transfer
LOOP per sector:
  Spin2: sp_transfer_8($FC)         → multi-block token
  Spin2: pinclear/pinl(_mosi)       → disable smart pin
  PASM:  org...end (streamer TX)    → 512 bytes
  Spin2: wrpin/wxpin/pinh           → re-enable smart pin
  Spin2: sp_transfer_8 x2           → CRC
  Spin2: waitDataResponse()         → loop
  Spin2: waitBusyComplete()         → loop
Spin2: sp_transfer_8($FD)           → stop token
Spin2: waitBusyComplete()
Spin2: pinh(cs)
```

**Transitions:** 2 × N sectors
**Smart pin reconfigs:** 2 × N sectors

---

## 3. Smart Pin Analysis

### 3.1 Current Pin Usage

| Pin | During Streamer | During Smart Pin Transfer |
|-----|-----------------|---------------------------|
| SCK | Smart pin (clock generation) | Smart pin (clock generation) |
| MOSI | Direct drive (streamer TX) | Smart pin TX mode |
| MISO | Direct read (streamer RX) | Smart pin RX mode |
| CS | Direct drive | Direct drive |

**Key observation:** SCK stays in smart pin mode always. Only MOSI/MISO toggle between smart pin and direct mode.

### 3.2 Why We Currently Reconfigure

The streamer needs direct pin access:
- **Streamer RX**: Reads MISO directly, smart pin would interfere
- **Streamer TX**: Drives MOSI directly, smart pin would interfere

But for command/response and CRC, we need smart pin for shift-register behavior.

### 3.3 Optimization Opportunities

**Question to investigate:** Can we use smart pin in a mode that's compatible with streamer?

**Alternative:** If reconfiguration is unavoidable, do it in PASM where it's 2+2+2 = 6 cycles instead of interpreter overhead.

---

## 4. Proposed Comprehensive PASM Blocks

### 4.1 Multi-Sector Read Block

**Scope:** From CMD18 sent through all sectors read to CMD12 complete

```pasm
' Input: sector, count, p_buffer (in registers)
' Output: sectors_read

read_sectors_pasm
                ' === SEND CMD18 ===
                ' (smart pin transfers for command)

                ' === SECTOR LOOP ===
.sector_loop
                ' Wait for $FE token (hardware polling with timeout)
                mov     timeout, ##TIMEOUT_VALUE
.wait_token
                ' Clock 8 bits, check for $FE
                wypin   #16, _sck           ' 8 bits = 16 edges
                waitx   #8                  ' wait for transfer
                rdpin   rx_data, _miso
                cmp     rx_data, #$FE   wz
        if_z    jmp     #.got_token
                djnz    timeout, #.wait_token
                jmp     #.timeout_error

.got_token
                ' Disable MISO smart pin (6 cycles total)
                pinclear _miso
                pinf    _miso
                nop                         ' 2-cycle settling

                ' === STREAMER RX (512 bytes) ===
                setxfrq xfrq
                wrfast  #0, p_buf
                wypin   clk_count, _sck
                waitx   align_delay
                xinit   stream_mode, init_phase
                waitxfi

                ' Re-enable MISO smart pin (6 cycles)
                wrpin   _miso, spi_rx_mode
                wxpin   _miso, #%1_00111
                pinh    _miso
                nop                         ' 2-cycle flag reset

                ' Read CRC (discard)
                wypin   #32, _sck           ' 16 bits = 32 edges
                waitx   #16

                ' Advance buffer pointer
                add     p_buf, #512

                ' Loop for next sector
                djnz    count, #.sector_loop

                ' === SEND CMD12 (stop transmission) ===
                ' (smart pin transfers)

                ' === CLEANUP ===
                pinh    _cs

                ret
```

**Benefits:**
- ONE Spin2→PASM→Spin2 transition for entire multi-sector read
- Smart pin reconfig still happens but in deterministic PASM (6 cycles each)
- Token wait uses hardware polling, not interpreter loop
- All timing is cycle-accurate

### 4.2 Multi-Sector Write Block

**Similar structure** - encapsulate CMD25 through stop token and busy-wait.

---

## 5. Timer/Event Opportunities

### 5.1 Token Wait with Timeout

Instead of software loop counting iterations:
```pasm
                mov     pa, #0
                getct   timeout_ct
                add     timeout_ct, ##TIMEOUT_CYCLES
.wait_loop
                ' ... poll for token ...
                getct   pa
                cmp     pa, timeout_ct  wc
        if_nc   jmp     #.timeout_error
                jmp     #.wait_loop
```

### 5.2 Busy-Wait with CT Event

```pasm
                ' Set up timeout event
                addct1  timeout_ct, ##BUSY_TIMEOUT

.busy_loop
                wypin   #16, _sck
                waitx   #8
                rdpin   rx_data, _miso
                cmp     rx_data, #$FF   wz
        if_z    jmp     #.busy_done

                ' Check timeout
                pollct1             wc
        if_c    jmp     #.busy_timeout
                jmp     #.busy_loop
```

---

## 6. Implementation Phases

### Phase 1: Analysis Complete ✓
- [x] Document current transaction flows
- [x] Identify all Spin2↔PASM transitions
- [x] Count smart pin reconfigurations
- [x] ~~Study smart pin modes for streamer compatibility~~ **RESOLVED**: Smart pins MUST be disabled for streamer

### Phase 2: Multi-Sector PASM Blocks (IN PROGRESS)
Focus on multi-sector first since that's where the timing failure occurs.
- [x] Create comprehensive `readSectors` PASM block (DONE - 2026-01-23)
- [ ] Create comprehensive `writeSectors` PASM block
- [x] Test at 320 MHz and 270 MHz (PARTIAL - see results below)
- [ ] Benchmark vs current implementation

**Test Results (2026-01-23):**
| Frequency | Before | After | Notes |
|-----------|--------|-------|-------|
| 320 MHz | Pass 6/Fail 0 | Pass 5/Fail 1 | Test 3 (single-write + multi-read) now fails |
| 270 MHz | Pass 2/Fail 4 | Pass 3/Fail 3 | Slight improvement but still failing |

**Key Findings:**
1. Comprehensive PASM improves determinism but doesn't fully solve frequency issue
2. MOSI must send $FF during token wait and CRC read (SD protocol requirement)
3. Must use `wrpin #0, pin` to fully clear smart pin mode, not just `dirl`
4. Test failures suggest issue may be in writeSectors timing (not yet converted)

### Phase 3: Single-Sector PASM Blocks (if needed)
Single-sector operations work at all frequencies. May not need changes.
- [ ] Evaluate if single-sector needs same treatment
- [ ] Create comprehensive readSector PASM block
- [ ] Create comprehensive writeSector PASM block

### Phase 4: Optimization
- [x] ~~Investigate smart pin modes for streamer compatibility~~ **RESOLVED**
- [ ] Implement CT-based timeouts
- [ ] Fine-tune timing alignment
- [ ] Final benchmarking

---

## 6.1 Phase 2 Detailed Design: readSectors Comprehensive PASM Block

### Current Problems to Solve

1. **Interpreter overhead in time-critical region**: Each `sp_transfer_8()` call involves Spin2 variable setup, inline PASM copy-to-cog, and interpreter return - all non-deterministic
2. **Token wait loop in Spin2**: `waitDataToken()` calls `sp_transfer_8()` in a Spin2 loop
3. **Smart pin reconfig via Spin2**: `wrpin/wxpin/pinh` called from interpreter

### Proposed Solution: Single Comprehensive PASM Block

**Scope:** From "wait for data token" through "CRC read" for ALL sectors in the transfer.

**Spin2 handles:** CMD18 send, error handling after PASM returns, CMD12 send, CS control

**PASM block handles (per sector loop):**
1. Wait for $FE token (with CT-based timeout)
2. Disable smart pin (6 cycles)
3. Streamer RX 512 bytes
4. Re-enable smart pin (6 cycles)
5. Read 2 CRC bytes
6. Advance buffer pointer
7. Loop for next sector

### Register Requirements

```
Input registers (set by Spin2 before org):
  _sck        - SCK pin number
  _miso       - MISO pin number
  rx_mode     - smart pin mode value (spi_rx_mode)
  stream_mode - streamer configuration
  xfrq        - streamer NCO frequency
  init_phase  - streamer initial phase
  align_delay - pre-streamer alignment delay
  clk_count   - clock transitions (8192)
  p_buf       - hub buffer pointer (updated per sector)
  count       - sectors remaining
  timeout_val - timeout in clock cycles

Output registers (read by Spin2 after end):
  sectors_ok  - sectors successfully read
  error_code  - 0=success, 1=token timeout, 2=error token

Scratch registers:
  rx_data     - received byte
  timeout_ct  - timeout counter target
  t           - temp
```

### Comprehensive PASM Block Design

```pasm
' ═══════════════════════════════════════════════════════════════════════
' readSectors Comprehensive PASM Block
' Scope: Token wait → Streamer RX → CRC read, for ALL sectors
' ═══════════════════════════════════════════════════════════════════════
' INPUTS:  _sck, _miso, rx_mode, stream_mode, xfrq, init_phase,
'          align_delay, clk_count, p_buf, count, timeout_val
' OUTPUTS: sectors_ok, error_code

org
        mov     sectors_ok, #0                  ' Init success counter
        mov     error_code, #0                  ' Init error code

.sector_loop
        ' ─────────────────────────────────────────────────────────────
        ' WAIT FOR DATA TOKEN ($FE) - with hardware timeout
        ' ─────────────────────────────────────────────────────────────
        getct   timeout_ct                      ' Get current time
        add     timeout_ct, timeout_val         ' Set timeout target

.wait_token
        ' Clock 8 bits via smart pin
        wxpin   #$27, _miso                     ' 8 bits, start-stop
        akpin   _miso                           ' Clear pending flag
        dirh    _miso                           ' Enable smart pin
        wypin   #16, _sck                       ' 16 transitions = 8 bits
        nop
.waitRx testp   _miso               wz          ' IN=1 when complete
  if_nz jmp     #.waitRx

        rdpin   rx_data, _miso                  ' Read received byte
        rev     rx_data                         ' Reverse for MSB-first
        zerox   rx_data, #7                     ' Mask to 8 bits

        cmp     rx_data, #$FE           wz      ' Check for data token
  if_z  jmp     #.got_token                     ' Got token - proceed

        ' Check for error token ($01-$0F)
        cmp     rx_data, #$FF           wz
  if_nz jmp     #.error_token                   ' Not $FF = error

        ' Still $FF - check timeout
        getct   t
        sub     t, timeout_ct           wc      ' C=1 if not expired
  if_c  jmp     #.wait_token                    ' Keep waiting

        ' Timeout - set error and exit
        mov     error_code, #1                  ' Error 1 = timeout
        jmp     #.done

.error_token
        mov     error_code, #2                  ' Error 2 = error token
        jmp     #.done

.got_token
        ' ─────────────────────────────────────────────────────────────
        ' DISABLE SMART PIN (deterministic 4 cycles)
        ' NOTE: PASM syntax is WRPIN mode, pin (opposite of Spin2!)
        ' ─────────────────────────────────────────────────────────────
        dirl    _miso                           ' DIR=0 disables smart pin
        nop                                     ' Settling time (2 cycles)
        nop

        ' ─────────────────────────────────────────────────────────────
        ' STREAMER RX: 512 bytes from MISO to hub
        ' ─────────────────────────────────────────────────────────────
        setxfrq xfrq                            ' Set streamer bit rate
        wrfast  #0, p_buf                       ' Setup FIFO write to hub
        wypin   clk_count, _sck                 ' Start clock transitions
        waitx   align_delay                     ' Phase alignment
        xinit   stream_mode, init_phase         ' Start streamer
        waitxfi                                 ' Wait for completion

        ' ─────────────────────────────────────────────────────────────
        ' RE-ENABLE SMART PIN (deterministic 8 cycles)
        ' NOTE: PASM syntax is WRPIN mode, pin (opposite of Spin2!)
        ' Smart pin requires DIR=0 before WRPIN, then DIR=1 to enable
        ' ─────────────────────────────────────────────────────────────
        wrpin   rx_mode, _miso                  ' Set smart pin mode (PASM: D=mode, S=pin)
        wxpin   #$27, _miso                     ' 8 bits, start-stop mode
        dirh    _miso                           ' DIR=1 enables smart pin
        nop                                     ' 2-cycle IN flag reset time
        nop

        ' ─────────────────────────────────────────────────────────────
        ' READ AND DISCARD 2 CRC BYTES (must clock them out)
        ' ─────────────────────────────────────────────────────────────
        akpin   _miso                           ' Clear flag
        wypin   #32, _sck                       ' 32 transitions = 16 bits
        nop
.waitCrc testp  _miso               wz          ' Wait for completion
  if_nz jmp     #.waitCrc
        rdpin   t, _miso                        ' Discard CRC

        ' ─────────────────────────────────────────────────────────────
        ' ADVANCE TO NEXT SECTOR
        ' ─────────────────────────────────────────────────────────────
        add     sectors_ok, #1                  ' Increment success count
        add     p_buf, ##512                    ' Advance buffer pointer
        djnz    count, #.sector_loop            ' Loop for remaining sectors

.done
end
```

### Integration with readSectors()

```spin2
PRI readSectors(start_sector, count, p_buffer) : sectors_read | ...
  ' [Existing: count==0 check, variable setup, CMD18 send]

  ' NEW: Single comprehensive PASM block for all sector data transfers
  org
    ' ... comprehensive PASM block above ...
  end

  ' Spin2 handles results
  sectors_read := sectors_ok
  if error_code <> 0
    debug("  [readSectors] Error code=", udec_(error_code))

  ' CMD12 stop transmission (stays in Spin2 - not time-critical)
  if sendStopTransmission() < 0
    debug("  [readSectors] CMD12 failed")

  pinh(cs)
```

### Why This Fixes the Timing Issue

1. **No interpreter variability**: Token wait, smart pin reconfig, CRC read ALL happen in cycle-accurate PASM
2. **Deterministic timing**: Smart pin disable = 6 cycles, re-enable = 6 cycles, every time
3. **Sector loop in PASM**: No Spin2 overhead between sectors
4. **CT-based timeout**: Hardware timer instead of software loop counting

### Estimated Size

- Token wait: ~25 instructions
- Smart pin disable: 4 instructions
- Streamer: 6 instructions
- Smart pin re-enable: 5 instructions
- CRC read: ~8 instructions
- Loop control: 3 instructions
- Total: ~50 instructions (well within cog memory)

---

## 7. Critical Finding: Smart Pin + Streamer Initialization Order

### From P2KB (p2kbPasm2StreamerSmartpinControl):

> **"CRITICAL: Start Smart Pins BEFORE XINIT! ... This order prevents data corruption and timing issues"**

The flash_loader pattern shows:
```pasm
' Setup pins (ORDER CRITICAL!)
wrpin   spi_ck_mode, #SPI_CK
wxpin   #1, #SPI_CK
wypin   #0, #SPI_CK
wrpin   spi_tx_mode, #SPI_TX
wxpin   x_config, #SPI_TX
wrpin   spi_rx_mode, #SPI_RX
wxpin   x_config, #SPI_RX

' Start pins BEFORE streamer!
dirh    #SPI_CK
dirh    #SPI_TX
dirh    #SPI_RX

' Now start streamer
xinit   xfer_config, #0
```

### Current Driver Does the Opposite!

```spin2
pinclear(_miso)     ' DISABLE smart pin  <-- OPPOSITE of recommended!
pinf(_miso)         ' Float it
org
    xinit ...       ' Start streamer
end
wrpin/wxpin/pinh    ' Re-enable smart pin AFTER
```

### TEST RESULT: Smart Pins MUST Be Disabled (2026-01-23)

**Test performed:** Commented out `pinclear/pinf` and `wrpin/wxpin/pinh` to keep MISO smart pin enabled during streamer RX.

**Result:** **FAIL** - Severe data corruption at 320 MHz
- Pass: 1, Fail: 5
- All bytes read as `$FF` (no actual data captured)
- Streamer cannot read pin directly when smart pin is enabled

**Conclusion:** The current driver approach is CORRECT. Smart pins MUST be disabled for direct streamer access. The flash_loader pattern in P2KB applies to a different configuration (possibly TX-specific or different smart pin mode).

**Implication for architecture:** Smart pin reconfiguration is unavoidable, but we can minimize its overhead by doing it within PASM blocks (6 cycles vs interpreter overhead).

---

## 8. Questions to Resolve

1. ~~**Smart pin during streamer:**~~ **RESOLVED** - Smart pins MUST be disabled for streamer RX. Test confirmed keeping them enabled causes data corruption.

2. **PASM block size limits:** How large can an inline PASM block be? Is there a cog memory constraint?

3. **Register allocation:** The comprehensive PASM blocks need several registers. Need to map out register usage carefully.

4. **Error handling:** How to return error status from PASM block to Spin2 caller?

---

## 8. References

- P2KB: io_pin_timing.yaml - Instruction-to-pin timing (3-cycle output, 2-cycle flag reset)
- P2KB: Smart pin modes - Investigate compatibility with streamer
- DOCs/Analysis/Archive/SYSCLK-TIMING-ANALYSIS.md - Timing calculations and hypotheses
- Current driver: src/micro_sd_fat32_fs.spin2

