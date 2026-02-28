# Streamer/FIFO Timing Analysis

**Date:** 2026-01-30 (updated 2026-02-13)
**Driver:** micro_sd_fat32_fs.spin2
**Purpose:** Technical analysis of streamer-based sector transfers and sysclk dependencies

---

## Part 1: Streamer Setup for Sector Transfers

### 1.1 Streamer Mode Constants

The driver defines two streamer mode base values:

```spin2
STREAM_RX_BASE = $C081_0000   ' 1-pin input to hub, MSB-first (flash_loader wmode)
STREAM_TX_BASE = $8081_0000   ' hub to 1-pin output, MSB-first (flash_loader rmode)
```

**Mode word format:** `[31:28]=mode [27:24]=options [23:17]=pin [16:0]=count`

| Field | RX Mode | TX Mode | Description |
|-------|---------|---------|-------------|
| Mode | $C | $8 | $C=WFBYTE (pin→hub), $8=RFBYTE (hub→pin) |
| Options | $0 | $0 | Standard operation |
| Flags | $81 | $81 | X_ALT_ON (MSB-first) + X_WRITE_ON/X_PINS_ON |

The full mode word is constructed at runtime by OR'ing the base with the pin number and bit count:

```spin2
stream_mode := STREAM_RX_BASE | (miso << 17) | (512 * 8)   ' 4096 bits for RX
stream_mode := STREAM_TX_BASE | (mosi << 17) | (512 * 8)   ' 4096 bits for TX
```

---

### 1.2 Read Sector (RX) Streamer Setup

**Function:** `readSector(sector, buf_type)`

#### Protocol Flow:
1. Send CMD17 (READ_SINGLE_BLOCK) with sector address
2. Poll for start token ($FE) using smart pin transfers
3. **Streamer captures 512 bytes** (4096 bits) from MISO to hub
4. Read 2 CRC bytes and validate against hardware CRC-16 (see Section 1.6)
5. Deselect card

#### Critical Sequence (inline PASM):

```spin2
org
      setxfrq xfrq                    ' Set streamer NCO rate
      wrfast  #0, p_buf               ' Setup WRFAST to hub buffer
      wypin   clk_count, _sck         ' Start clock transitions (8192)
      waitx   align_delay             ' Wait one half-period to align
      xinit   stream_mode, init_phase ' Start streamer with phase offset
      waitxfi                         ' Wait for streamer to complete
end
```

#### Key Parameters:

| Parameter | Value | Description |
|-----------|-------|-------------|
| `clk_count` | 8192 | Clock transitions (512 bytes × 8 bits × 2 edges) |
| `stream_mode` | `$C081_0000 | (miso<<17) | 4096` | RX mode, pin, bit count |
| `xfrq` | $4000_0000 / spi_period | NCO frequency for sampling |
| `init_phase` | $4000_0000 | Mid-bit sampling for stability |
| `align_delay` | spi_period | Half-period alignment delay |

#### MISO Smart Pin Handling (CRITICAL):

```spin2
' BEFORE streamer:
pinclear(_miso)        ' Clear smart pin mode
pinf(_miso)            ' Float pin (input mode)

' AFTER streamer:
wrpin(_miso, spi_rx_mode)   ' Restore P_SYNC_RX | P_PLUS3_B
wxpin(_miso, %1_00111)      ' On-edge sample, 8 bits
pinh(_miso)                 ' Re-enable smart pin
```

**Why disable smart pin?** The P_SYNC_RX smart pin captures data based on its internal clock source (SCK via B-input). The streamer reads the raw pin state directly. If both are active, they interfere with each other.

---

### 1.3 Write Sector (TX) Streamer Setup

**Function:** `writeSector(sector, buf_type)`

#### Protocol Flow:
1. Send CMD24 (WRITE_SINGLE_BLOCK) with sector address
2. Send data start token ($FE)
3. **Streamer transmits 512 bytes** (4096 bits) from hub to MOSI
4. Calculate and send real CRC-16 (2 bytes, see Section 1.6)
5. Wait for data-response token ($x5 = accepted)
6. Wait for card programming complete (MISO goes HIGH)

#### Critical Sequence (inline PASM):

```spin2
org
      setxfrq xfrq                    ' Set streamer bit rate
      rdfast  #0, p_buf               ' Setup RDFAST from hub buffer
      xinit   stream_mode, #0         ' Start streamer output FIRST
      wypin   clk_count, _sck         ' THEN start clock transitions
      waitxfi                         ' Wait for streamer to complete
end
```

**Key difference from RX:** For TX, `xinit` comes BEFORE `wypin`. This ensures data is stable on MOSI before the first rising clock edge when the card samples.

#### MOSI Smart Pin Handling:

```spin2
' BEFORE streamer:
pinclear(_mosi)        ' Clear smart pin mode
pinl(_mosi)            ' Drive pin low (output mode)

' AFTER streamer:
wrpin(_mosi, spi_tx_mode)   ' Restore P_SYNC_TX | P_OE | P_PLUS2_B
wxpin(_mosi, %1_00111)      ' Start-stop mode, 8 bits
pinh(_mosi)                 ' Re-enable smart pin
```

---

### 1.4 NCO Frequency Calculation

The streamer uses an NCO (Numerically Controlled Oscillator) to time bit sampling/output. The NCO accumulates `xfrq` each sysclock; a sample/output occurs when the MSB transitions 0→1.

**Formula:**
```
xfrq = $8000_0000 / bits_per_second
     = $8000_0000 / (clkfreq / (spi_period * 2))
     = $4000_0000 / spi_period
```

**Example at 320 MHz targeting 25 MHz SPI:**
```
spi_period = ceil(320M / (25M * 2)) = ceil(6.4) = 7 clocks
xfrq = $4000_0000 / 7 = $0924_9249
actual_spi = 320M / 14 = 22.86 MHz
```

**Example at 270 MHz targeting 25 MHz SPI:**
```
spi_period = ceil(270M / (25M * 2)) = ceil(5.4) = 6 clocks
xfrq = $4000_0000 / 6 = $0AAA_AAAA
actual_spi = 270M / 12 = 22.5 MHz
```

---

### 1.5 Phase Alignment

For RX (reading), the streamer must sample data in the middle of each bit period for reliability.

```spin2
init_phase := $4000_0000    ' Start NCO at 50% - first sample after ~1/2 period
align_delay := spi_period   ' Wait one half-period before starting streamer
```

**Timing sequence:**
1. `wypin clk_count, sck` - SCK smart pin starts counting, first rising edge at T=spi_period
2. `waitx align_delay` - Wait one half-period
3. `xinit stream_mode, init_phase` - Start streamer at T=spi_period (aligned with first rising edge)
4. NCO starts at 50% phase, so first sample occurs ~spi_period later (middle of bit 0)

For TX (writing), no phase offset is needed:
```spin2
init_phase := #0    ' Start immediately - data leads clock
```

---

### 1.6 CRC-16 Data Integrity

The driver calculates and validates CRC-16-CCITT for all sector transfers using the P2's hardware-accelerated `GETCRC` instruction.

**CRC calculation (`calcDataCRC()`):**
```spin2
CON
  CRC_POLY_REFLECTED = $8408    ' CRC-CCITT reflected polynomial
  CRC_BASE_512       = $2C68    ' Pre-computed XOR base for 512-byte blocks

PRI calcDataCRC(pData, len) : crc | raw
  raw := GETCRC(pData, CRC_POLY_REFLECTED, len)
  crc := ((raw ^ CRC_BASE_512) REV 31) >> 16
```

**Read path:** After the streamer captures 512 bytes, two CRC bytes are received via smart pin transfers and compared against the hardware-computed CRC of the received data. Mismatches are counted for diagnostics.

**Write path:** Before sending CRC bytes after the streamer transmits 512 bytes, `calcDataCRC()` computes the real CRC-16 which is sent as two bytes (high byte first). This allows the card to reject corrupted data.

CRC validation is controlled by the `diag_crc_enabled` flag and applies to all transfer paths: `readSector()`, `readSectors()`, `readSectorSlow()`, `writeSector()`, and `writeSectors()`.

---

### 1.7 Multi-Block Streamer Transfers (CMD18/CMD25)

The driver supports multi-block reads (CMD18) and writes (CMD25) using the same streamer mechanism as single-block operations, looping per-sector within a single card transaction.

#### Multi-Block Read (`readSectors()` / CMD18):

1. Send CMD18 (READ_MULTIPLE_BLOCK) with starting sector
2. **Per sector:** Poll for $FE start token, streamer captures 512 bytes, validate CRC
3. After all sectors: Send CMD12 (STOP_TRANSMISSION), verify with CMD13

The per-sector streamer sequence is identical to single-block reads (Section 1.2). Smart pins are disabled/re-enabled around each streamer transfer.

#### Multi-Block Write (`writeSectors()` / CMD25):

1. Send CMD25 (WRITE_MULTIPLE_BLOCK) with starting sector
2. **Per sector:** Send $FC start token, streamer transmits 512 bytes, send real CRC, wait for data-response and busy
3. After all sectors: Send $FD stop token (NOT CMD12), wait for busy, verify with CMD13

The per-sector TX streamer sequence adds a `waitx settle_delay` before `xinit` to allow the MOSI pin to stabilize after smart pin reconfiguration:

```spin2
org
      setxfrq xfrq
      rdfast  #0, p_buf
      waitx   settle_delay     ' Stabilize MOSI after pinclear/pinl
      xinit   stream_mode, #0
      wypin   clk_count, _sck
      waitxfi
end
```

---

## Part 2: Sysclk-Dependent Code Regions

### 2.1 SPI Timing Calculation (setSPISpeed)

```spin2
PUB setSPISpeed(freq) | half_period, actual_freq
  ' Calculate half-period in system clocks
  half_period := (clkfreq + (freq * 2) - 1) / (freq * 2)  ' Ceiling division

  ' Guard against too-small period
  if half_period < 4
    half_period := 4

  actual_freq := clkfreq / (half_period * 2)
  spi_period := half_period
  wxpin(sck, half_period)    ' Apply to SCK smart pin
```

**Sysclk dependency:** Uses `clkfreq` to calculate timing. This is CORRECT behavior - it adapts to the actual clock frequency.

#### Sysclk vs Actual SPI Speed (targeting 25 MHz)

The ceiling division and integer half-periods create quantization steps. The driver always achieves the highest SPI speed that does not exceed the target.

**Threshold: 200 MHz sysclk.** At or above 200 MHz, the driver achieves 20-25 MHz SPI (full speed). Below 200 MHz, the half-period clamp (minimum 4) kicks in and actual SPI = clkfreq / 8, declining linearly.

| Sysclk | Half-Period | Actual SPI | % of 25 MHz |
|--------|-------------|------------|-------------|
| **350 MHz** | **7** | **25.00 MHz** | **100%** |
| 340 MHz | 7 | 24.29 MHz | 97% |
| 330 MHz | 7 | 23.57 MHz | 94% |
| 320 MHz | 7 | 22.86 MHz | 91% |
| 310 MHz | 7 | 22.14 MHz | 89% |
| **300 MHz** | **6** | **25.00 MHz** | **100%** |
| 290 MHz | 6 | 24.17 MHz | 97% |
| 280 MHz | 6 | 23.33 MHz | 93% |
| 270 MHz | 6 | 22.50 MHz | 90% |
| 260 MHz | 6 | 21.67 MHz | 87% |
| **250 MHz** | **5** | **25.00 MHz** | **100%** |
| 240 MHz | 5 | 24.00 MHz | 96% |
| 230 MHz | 5 | 23.00 MHz | 92% |
| 220 MHz | 5 | 22.00 MHz | 88% |
| 210 MHz | 5 | 21.00 MHz | 84% |
| **200 MHz** | **4** | **25.00 MHz** | **100%** |
| 190 MHz | 4 (clamped) | 23.75 MHz | 95% |
| 180 MHz | 4 (clamped) | 22.50 MHz | 90% |
| 170 MHz | 4 (clamped) | 21.25 MHz | 85% |
| 160 MHz | 4 (clamped) | 20.00 MHz | 80% |

**Notes:**
- Exact 25 MHz at every 50 MHz boundary: 200, 250, 300, 350 MHz (where clkfreq / (half_period * 2) divides evenly)
- Between boundaries, the actual SPI drops due to half-period rounding up. For example, 320 MHz (22.86 MHz) is slower than 300 MHz (25.00 MHz) because half-period rounds from 6.4 to 7
- Below 200 MHz, half-period is clamped to 4 and the SPI speed is simply clkfreq / 8
- All speeds in this table are within the SD card specification (max 25 MHz for default speed mode)
- No manual speed adjustment is needed at any sysclk above 160 MHz; the driver adapts automatically

---

### 2.2 Card Initialization SPI Clock (initCard)

```spin2
setSPISpeed(400_000)    ' 400 kHz for card init (SD spec: 100-400 kHz)
```

**Sysclk dependency:** Uses `setSPISpeed()` which calculates timing from `clkfreq`. The SD specification requires 100-400 kHz during card initialization.

---

### 2.3 Timeout Calculations

**Pattern used throughout the driver:**

```spin2
t := getct() + clkfreq                              ' 1 second timeout
timeout := getct() + (clkfreq / 100) * card_read_timeout_ms   ' CSD-based timeout
t := getct() + clkfreq * 2                          ' 2 second timeout
t := getct() + (clkfreq / 1000) * card_write_timeout_ms       ' Write timeout
```

**Sysclk dependency:** All use `clkfreq` and `getct()` correctly. These automatically adapt to any sysclk frequency.

---

### 2.4 Streamer NCO Frequency

```spin2
xfrq := $4000_0000 / spi_period   ' One sample per full clock period
```

**Sysclk dependency:** Depends on `spi_period` which was calculated from `clkfreq`. This is CORRECT - the NCO rate automatically scales with the SPI clock period.

---

### 2.5 Fixed Delays

```spin2
waitms(100)    ' After power-up stabilization
waitus(10)     ' Pin configuration delays
waitus(100)    ' Smart pin settle time
waitms(10)     ' Between ACMD41 retries
```

**Sysclk dependency:** `waitms()` and `waitus()` are provided by the Spin2 runtime and use `clkfreq` internally. These are SAFE at any sysclk.

---

## Part 3: 270 MHz vs 320 MHz Behavior Differences

### 3.1 Quantization Effects

The integer division in timing calculations creates quantization error that differs by sysclk:

| Sysclk | Target | Half-Period | Actual SPI | Error |
|--------|--------|-------------|------------|-------|
| 320 MHz | 25 MHz | 7 clocks | 22.86 MHz | -8.6% |
| 270 MHz | 25 MHz | 6 clocks | 22.5 MHz | -10% |
| 320 MHz | 20 MHz | 8 clocks | 20 MHz | 0% |
| 270 MHz | 20 MHz | 7 clocks | 19.3 MHz | -3.5% |

The actual SPI frequency is always ≤ target (due to ceiling division), but the margin varies.

---

### 3.2 NCO Phase Accumulator Precision

The NCO accumulates xfrq each sysclock. Phase precision differs:

**At 320 MHz, 7-clock period:**
- xfrq = $4000_0000 / 7 = $0924_9249
- Phase increment per sysclock = 9.14% of full cycle
- Sampling jitter: ±0.5 sysclock = ±7.1% of bit period

**At 270 MHz, 6-clock period:**
- xfrq = $4000_0000 / 6 = $0AAA_AAAA
- Phase increment per sysclock = 10.67% of full cycle
- Sampling jitter: ±0.5 sysclock = ±8.3% of bit period

The higher phase increment at 270 MHz means less precise sampling timing, potentially contributing to marginal data errors.

---

### 3.3 Alignment Delay Precision

```spin2
align_delay := spi_period    ' Wait one half-period before streamer
```

The `waitx align_delay` instruction has ±1 sysclock jitter. At lower sysclk, this represents a larger fraction of the bit period:

- At 320 MHz, 7-clock period: ±1/7 = ±14.3% alignment error
- At 270 MHz, 6-clock period: ±1/6 = ±16.7% alignment error

---

### 3.4 Smart Pin Clock Domain Crossing

The smart pins (P_SYNC_TX, P_SYNC_RX, P_TRANSITION) operate synchronously with sysclk. When the streamer (also sysclk-synchronous) hands off to/from smart pins, there's a domain boundary that works correctly because both are on the same clock.

However, the SD card is an external device with its own timing requirements. The SPI clock we generate must meet the card's setup/hold times regardless of our sysclk. At lower sysclk:
- Fewer clocks per SPI period = less margin for timing variations
- Card internal timing requirements unchanged

---

## Part 4: Validation Strategy for Other Frequencies

### 4.1 Recommended Test Matrix

| Sysclk | SPI Target | Expected Result |
|--------|------------|-----------------|
| 320 MHz | 25 MHz | Baseline (known working) |
| 300 MHz | 25 MHz | Should work |
| 280 MHz | 25 MHz | Marginal zone |
| 270 MHz | 25 MHz | Validated (was previously failing due to test bugs) |
| 320 MHz | 20 MHz | Reduced speed reference |
| 270 MHz | 20 MHz | Should work at lower SPI |

### 4.2 Test Procedure

1. **Compile driver with target _CLKFREQ**
2. **Run mount tests** - Basic card communication
3. **Run file ops tests** - Single-sector read/write
4. **Run format tests** - Heavy multi-sector writes
5. **Run multi-block tests** - CMD18/CMD25 with streamer

### 4.3 Potential Adjustments

**Option A: Reduce SPI frequency at lower sysclk**
```spin2
if clkfreq < 300_000_000
  setSPISpeed(20_000_000)   ' 20 MHz instead of 25 MHz
else
  setSPISpeed(25_000_000)
```

**Option B: Add extra phase margin**
```spin2
' Increase alignment delay at lower sysclk
if clkfreq < 300_000_000
  align_delay := spi_period + (spi_period / 4)   ' Extra 25% margin
else
  align_delay := spi_period
```

**Option C: Reduce streamer NCO rate slightly**
```spin2
' Sample slightly slower for more margin
xfrq := ($4000_0000 / spi_period) - ($4000_0000 / (spi_period * 8))   ' ~12.5% slower
```

### 4.4 Diagnostic Additions

Add debug output for timing verification:
```spin2
PUB debugTimingInfo()
  debug("Timing: clkfreq=", udec_(clkfreq/1_000_000), " MHz")
  debug("  spi_period=", udec_(spi_period), " clocks")
  debug("  actual_spi=", udec_(spi_freq/1000), " kHz")
  debug("  xfrq=$", uhex_long_(($4000_0000 / spi_period)))
```

---

## Part 5: Known Issues and Historical Context

### 5.1 Early 270 MHz Failure Pattern (Resolved)

Early development saw multi-block failures at 270 MHz:
- Sequential multi-block operations (writeSectorsRaw -> readSectorsRaw) failed
- Mixed operations (multi-write + single-reads, or single-writes + multi-read) worked
- 3,472 byte mismatches in 8-sector test
- 24,800 byte mismatches in 64-sector test

**Root cause:** These failures were traced to test framework bugs (integer overflow in timeout calculations: `clkfreq * 30` overflows 32-bit LONG at sysclk > 71 MHz), not driver issues.

### 5.2 270 MHz Validation (Resolved)

**Fully validated at 270 MHz.** After fixing test framework bugs, all regression tests pass at both 320 MHz and 270 MHz (263+ tests at each frequency). The driver's streamer timing is robust across the tested frequency range.

---

## Summary

### Sysclk-Dependent Regions (by impact level):

| Region | Impact | Notes |
|--------|--------|-------|
| NCO xfrq calculation | HIGH | Different phase precision at different sysclk |
| spi_period calculation | HIGH | Quantization affects actual SPI frequency |
| align_delay precision | MEDIUM | Jitter is larger fraction of period at low sysclk |
| Timeouts | LOW | Correctly use clkfreq, auto-adapt |
| Fixed waitus/waitms | NONE | Runtime handles sysclk internally |

### Key Features:

- **CRC-16 integrity** on all transfers (hardware GETCRC, see Section 1.6)
- **Multi-block operations** CMD18/CMD25 with per-sector streamer (see Section 1.7)
- **Single-block operations** CMD17/CMD24 with streamer (see Sections 1.2, 1.3)
- **Slow-path fallback** `readSectorSlow()` for diagnostics (byte-by-byte with CRC)

### Recommendations:

1. Both 320 MHz and 270 MHz are validated and working
2. If targeting lower sysclk frequencies, reduce SPI speed to 20 MHz first
3. If issues arise at new frequencies, add extra phase margin in align_delay
4. The driver's `setSPISpeed()` (public) adapts automatically to any sysclk via `clkfreq`

---

*Document created: 2026-01-30, updated 2026-02-13*
