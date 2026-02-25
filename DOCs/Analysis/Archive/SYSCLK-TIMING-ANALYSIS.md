# Sysclk Timing Analysis for V2 SD Driver

**Date:** 2026-01-23
**Status:** Active Investigation
**Issue:** Multi-block operations fail at 270 MHz but pass at 320 MHz

---

## 1. Problem Statement

The V2 SD driver using smart pins and streamer fails at 270 MHz sysclk with specific failure pattern:

| Test | 320 MHz | 270 MHz | Result |
|------|---------|---------|--------|
| writeSectorsRaw + readSectorsRaw | PASS | **FAIL** | Data corruption |
| writeSectorsRaw + single readSectorRaw | PASS | PASS | - |
| single writeSectorRaw + readSectorsRaw | PASS | PASS | - |

**Key Observation:** Only sequential multi-block write followed by multi-block read fails.

---

## 2. Timing Parameter Calculations

### 2.1 SPI Period Calculation (Driver Code)

```spin2
half_period := (clkfreq + (freq * 2) - 1) / (freq * 2)   ' Ceiling division
if half_period < 4
    half_period := 4                                      ' Minimum clamp
```

### 2.2 NCO Frequency Calculation (Driver Code)

```spin2
xfrq := $4000_0000 / spi_period                          ' Integer division
```

### 2.3 Results by Sysclk Frequency

| Sysclk | half_period | full_period | actual_spi | xfrq | Notes |
|--------|-------------|-------------|------------|------|-------|
| 320 MHz | 7 | 14 | 22.86 MHz | $09249249 | TESTED: PASS |
| 310 MHz | 7 | 14 | 22.14 MHz | $09249249 | |
| 305 MHz | 7 | 14 | 21.79 MHz | $09249249 | Boundary |
| 300 MHz | 6 | 12 | 25.00 MHz | $0AAAAAAA | Exact 25 MHz |
| 270 MHz | 6 | 12 | 22.50 MHz | $0AAAAAAA | TESTED: FAIL |
| 250 MHz | 5 | 10 | 25.00 MHz | $0CCCCCCC | HDMI target |
| 200 MHz | 4 | 8 | 25.00 MHz | $10000000 | Exact division |

### 2.4 Quantization Boundaries

Where `half_period` value changes:
- **305 MHz**: hp changes 7→6
- **255 MHz**: hp changes 6→5
- **205 MHz**: hp changes 5→4

---

## 3. Hypothesis Testing

### Hypothesis 1: NCO Phase Alignment Error

**Theory:** Sample position within bit period varies with sysclk.

**Test:** Calculate sample position as percentage of bit period.

**Result:**
```
320 MHz: sample_pos = 50.0% of bit
270 MHz: sample_pos = 50.0% of bit
```

**Verdict: DISPROVED** - Both have identical 50% phase alignment.

---

### Hypothesis 2: Accumulated Phase Drift

**Theory:** Integer truncation in xfrq causes drift over 4096 bits.

**Test:** Calculate accumulated phase error over one sector.

**Results:**
```
320 MHz (hp=7):
  $40000000 % 7 = 1  (fractional, remainder=1)
  error per bit: 0.1429 phase units
  after 4096 bits: 585 phase units
  drift: 0.0000 cycles

270 MHz (hp=6):
  $40000000 % 6 = 4  (fractional, remainder=4)
  error per bit: 0.6667 phase units
  after 4096 bits: 2,731 phase units
  drift: 0.0000 cycles
```

**Verdict: INCONCLUSIVE** - 270 MHz has 4x higher truncation error, but absolute drift is negligible (< 0.0001 cycles). May contribute to edge cases.

---

### Hypothesis 3: P2KB "+1 Rule" for Fractional NCO

**Theory:** P2KB states "For fractional ratios, add 1 to ensure proper initial rollover timing."

**Analysis:**
- Driver: `xfrq := $4000_0000 / spi_period` (no +1)
- hp=7: xfrq = $09249249 (should be $0924924A?)
- hp=6: xfrq = $0AAAAAAA (should be $0AAAAAAB?)

**First Sample Timing:**
```
Without +1:
  hp=7: first sample at cycle 14.0 (exactly)
  hp=6: first sample at cycle 12.0 (exactly)

With +1:
  hp=7: first sample at cycle 14.0 (essentially same)
  hp=6: first sample at cycle 12.0 (essentially same)
```

**Verdict: UNLIKELY** - The +1 affects initial alignment but both calculate to exactly one full_period cycles to first sample.

---

### Hypothesis 4: Inline PASM Copy Latency

**Theory:** Inline PASM is copied to cog before execution; timing varies.

**Analysis:**
- Copy time is in sysclk cycles, not wall-clock time
- P2 operations are cycle-deterministic
- At 320 MHz: 1 cycle = 3.125 ns
- At 270 MHz: 1 cycle = 3.704 ns

**Verdict: DISPROVED** - P2 timing is in cycles, not nanoseconds. Copy latency is the same in cycles at any frequency.

---

### Hypothesis 5: Pin Output Propagation Delay

**Theory:** Pin output delay affects timing differently at different sysclk.

**From P2KB p2kbArchIoPinTiming:**
```
Output propagation delay (normal mode): 3.5-5.0 ns typical
Smart pin output delay: 6-9 ns typical
```

**Analysis:**
- At 320 MHz: 6-9 ns = 1.9-2.9 cycles
- At 270 MHz: 6-9 ns = 1.6-2.4 cycles

This is a FRACTIONAL cycle difference! But:
- All pins have the same delay
- Relative timing (clock vs data) should be unaffected

**Verdict: UNLIKELY** - Same delay applies to both clock and data pins; relative timing preserved.

---

### Hypothesis 6: Inter-Operation State Corruption

**Theory:** State persists between writeSectorsRaw and readSectorsRaw causing corruption at certain frequencies.

**Evidence:**
- Sequential multi-block write+read: FAIL
- Mixed single/multi operations: PASS

**State that persists between operations:**
1. Smart pin configuration on MOSI (write) vs MISO (read) - different pins
2. Streamer NCO frequency - reset by setxfrq each operation
3. Streamer phase - reset by xinit each operation
4. WRFAST/RDFAST pointers - reset each operation

**Code flow analysis:**

After writeSectorsRaw():
```spin2
pinh(cs)                        ' CS deasserted
' MOSI smart pin enabled (for response reading)
' MISO smart pin state: configured for smart pin RX
' Streamer: idle after waitxfi
```

At start of readSectorsRaw():
```spin2
resp := cmd(CMD18, ...)         ' Uses sp_transfer_8 -> smart pins
pinclear(_miso)                 ' Clear MISO smart pin
pinf(_miso)                     ' Float pin (input mode)
stream_mode := ...              ' Configure streamer
xfrq := ...                     ' Calculate NCO rate
' Then inline PASM with setxfrq/wrfast/xinit
```

**Potential Issue:** The `pinclear(_miso)` clears smart pin mode but the pin hardware state may need settling time that varies with sysclk.

**Verdict: NEEDS INVESTIGATION** - This is the most likely cause. The transition from smart pin mode to streamer mode may have timing-sensitive state.

---

### Hypothesis 7: Smart Pin Flag Reset Timing Violation

**Theory:** After re-enabling MISO smart pin (wrpin/wxpin/pinh), the IN flag needs 2 cycles to reset. If sp_transfer_8 is called immediately, it may see stale flag state, causing synchronization issues.

**From P2KB (updated 2026-01-23):**
> Smart Pin IN flag reset: 2 clocks after WRPIN/WXPIN/WYPIN/RDPIN/AKPIN. Must NOP before polling.

**Code analysis (readSectors, after streamer):**
```spin2
' Re-enable MISO smart pin for CRC reads
wrpin(_miso, spi_rx_mode)      ; T=0
wxpin(_miso, %1_00111)         ; T=2
pinh(_miso)                    ; T=4
; IN flag valid at T=6 (2 cycles after pinh)

' Immediately called:
sp_transfer_8($FF)             ; T=6 - MAY be too early!
sp_transfer_8($FF)             ; CRC byte 2
```

**Why this could be frequency-dependent:**
- The sp_transfer_8() function polls the smart pin IN flag
- At 320 MHz with spi_period=7: more margin in polling loop iterations
- At 270 MHz with spi_period=6: tighter timing, first poll may see invalid flag

**Test:** Add explicit 2-cycle delay after pinh() before sp_transfer_8().

**Verdict: STRONG CANDIDATE** - This is a documented timing requirement we may be violating.

---

## 4. Integer Division Properties

### 4.1 Which half_periods give exact division?

| hp | $40000000 % hp | Type | Sysclk Range |
|----|----------------|------|--------------|
| 4 | 0 | INTEGER | 100-200 MHz |
| 5 | 4 | FRACTIONAL | 205-250 MHz |
| 6 | 4 | FRACTIONAL | 255-300 MHz |
| 7 | 1 | FRACTIONAL | 305-325 MHz |
| 8 | 0 | INTEGER | N/A |

**Note:** hp=7 has remainder=1, hp=6 has remainder=4. The hp=6 range (including 270 MHz) has 4x higher truncation error.

### 4.2 Sysclk Frequencies with Exact 25 MHz SPI

```
200 MHz: hp=4, actual_spi=25.00 MHz (exact)
250 MHz: hp=5, actual_spi=25.00 MHz (exact)
300 MHz: hp=6, actual_spi=25.00 MHz (exact)
```

---

## 5. Test Matrix for Investigation

To find the exact failure boundary, test these frequencies:

| Frequency | hp | Expected | Priority |
|-----------|----|---------| ---------|
| 320 MHz | 7 | PASS (baseline) | Verified |
| 310 MHz | 7 | ? | High |
| 305 MHz | 7 | ? (boundary) | High |
| 300 MHz | 6 | ? (exact SPI) | High |
| 295 MHz | 6 | ? | Medium |
| 290 MHz | 6 | ? | Medium |
| 280 MHz | 6 | ? | Medium |
| 270 MHz | 6 | FAIL (verified) | Verified |
| 260 MHz | 6 | ? | Medium |
| 255 MHz | 6 | ? (boundary) | High |
| 250 MHz | 5 | ? (HDMI target) | High |
| 240 MHz | 5 | ? | Low |
| 200 MHz | 4 | ? (exact div) | High |

---

## 6. Proposed Fixes to Test

### Fix A: Add +1 to xfrq for fractional ratios

```spin2
' Current:
xfrq := $4000_0000 / spi_period

' Proposed:
xfrq := $4000_0000 / spi_period
if ($4000_0000 // spi_period) <> 0   ' If fractional
    xfrq += 1                         ' Add +1 per P2KB recommendation
```

### Fix B: Add settling delay after pinclear

```spin2
' In readSectors, after pinclear:
pinclear(_miso)
pinf(_miso)
waitx(spi_period)    ' Allow pin state to settle
' Then proceed with streamer
```

### Fix C: Explicit XSTOP before new operation

```spin2
' At start of read/write sectors:
org
    xstop                ' Ensure streamer fully stopped
end
```

### Fix D: Use exact-division frequencies only

Document that driver requires sysclk = N × 50 MHz for reliable operation.

### Fix E: Add 2-cycle delay after smart pin re-enable (Hypothesis 7)

**Rationale:** P2KB documents that IN flag needs 2 cycles after WRPIN/WXPIN/WYPIN/RDPIN/AKPIN to reset properly.

**Note on timing:** WAITX is 2+N cycles (2 exec + N wait), so `waitx #2` = 4 cycles. NOP is exactly 2 cycles, making it the correct choice for this delay.

```spin2
' In readSectors and writeSectors, after re-enabling smart pin:
wrpin(_miso, spi_rx_mode)
wxpin(_miso, %1_00111)
pinh(_miso)
org
    nop                      ' <-- ADD: 2 cycles - allow IN flag to reset per P2KB
end
sp_transfer_8($FF)           ' Now safe to poll smart pin
```

**Priority: HIGH** - This is based on documented P2 timing requirement, not speculation.

---

## 7. P2 I/O Timing Reference (from P2KB - CRITICAL)

**Source:** P2KB `io_pin_timing.yaml`, smart pin instruction YAMLs (updated 2026-01-23)

These timings are in **CLOCK CYCLES**, not nanoseconds. They are constant regardless of sysclk frequency.

### 7.1 Instruction-to-Pin Timing Table

| Operation | Timing | Clock Cycles | Notes |
|-----------|--------|--------------|-------|
| Output (DRVH/DRVL/PINH/PINL/etc.) | 3 clocks AFTER instruction | 5 total (2 exec + 3 propagation) | Pin starts transitioning 3 cycles after instruction completes |
| Input via INx register | 3 clocks BEFORE instruction | Data is 3 clocks old | Reading INA/INB gives stale data |
| Input via TESTP/TESTPN | 2 clocks BEFORE instruction | Data is 2 clocks old | Fresher than INx |
| Smart Pin IN flag reset | 2 clocks AFTER WRPIN/WXPIN/WYPIN/RDPIN/AKPIN | Must NOP before polling | Flag not valid immediately |

### 7.2 Instruction Execution Times

| Instruction | Execution Cycles | Notes |
|-------------|------------------|-------|
| XINIT | 2 | Issues streamer command, zeros phase |
| WYPIN | 2 | Writes Y value to smart pin |
| SETXFRQ | 2 | Sets streamer NCO frequency |
| WRPIN | 2 | Configures smart pin mode |
| WXPIN | 2 | Sets smart pin X parameter |
| PINCLEAR | 2 | Clears smart pin configuration |
| PINF | 2 | Floats pin (input mode) |
| WAITX | 2 + N | Wait N cycles after 2-cycle execution |
| WAITXFI | Variable | Blocks until streamer completes |

### 7.3 Impact on SPI Bit Timing

The fixed-cycle delays consume different **percentages** of the bit period at different frequencies:

| Sysclk | spi_period (half) | full_bit | 3-cycle as % | 2-cycle as % |
|--------|-------------------|----------|--------------|--------------|
| 320 MHz | 7 cycles | 14 cycles | 21.4% | 14.3% |
| 270 MHz | 6 cycles | 12 cycles | 25.0% | 16.7% |
| 250 MHz | 5 cycles | 10 cycles | 30.0% | 20.0% |
| 200 MHz | 4 cycles | 8 cycles | 37.5% | 25.0% |

**Key insight:** At lower spi_periods, the fixed-cycle I/O delays consume a larger fraction of the bit time, leaving less margin for timing variations.

### 7.4 WYPIN-to-Clock Transition Analysis

In the driver's inline PASM for readSectors:
```
T=0:  wypin clk_count, _sck    ; 2 cycles to execute
T=2:  wypin completes
T=5:  Clock pin actually starts transitioning (3 cycles after instruction)
T=4:  waitx align_delay starts (2 cycles to execute waitx itself)
T=4+align_delay: xinit executes
```

So xinit happens at T = 4 + align_delay:
- At 320 MHz: T = 4 + 7 = 11 cycles after wypin start
- At 270 MHz: T = 4 + 6 = 10 cycles after wypin start

Relative to first clock transition (T=5):
- At 320 MHz: xinit at T=11, so 6 cycles after first transition (43% into first bit)
- At 270 MHz: xinit at T=10, so 5 cycles after first transition (42% into first bit)

**These are nearly identical**, which suggests the WYPIN timing alone isn't causing the issue.

### 7.5 Smart Pin Flag Reset Timing

**CRITICAL:** After WRPIN/WXPIN/WYPIN, the smart pin's IN flag is not valid for 2 clock cycles.

In the driver, after re-enabling the MISO smart pin:
```spin2
wrpin(_miso, spi_rx_mode)   ; T=0, executes in 2 cycles
wxpin(_miso, %1_00111)      ; T=2, executes in 2 cycles
pinh(_miso)                 ; T=4, executes in 2 cycles
; IN flag not valid until T=6 (2 cycles after last pin instruction)
```

If code immediately tries to use the smart pin (e.g., sp_transfer_8), it may see invalid flag state.

---

## 8. Next Steps

1. **Create frequency sweep test** - Test multi-block at 10 MHz intervals from 320 to 200 MHz
2. **Try Fix B first** - Add settling delay; lowest risk
3. **Test Fix A** - Add +1 to fractional xfrq
4. **Analyze failure data pattern** - Are errors consistent byte positions? Suggests alignment issue
5. **Add debug output** - Log exact timing values at different frequencies

---

## 9. Key References

### P2KB Documentation (primary sources for timing)
- **p2kbArchIoPinTiming** - `io_pin_timing.yaml` - CRITICAL: instruction_to_pin_timing section with complete timing table
- **p2kbPasm2Wrpin** - `wrpin.yaml` - in_flag_reset_latency: 2 cycles
- **p2kbPasm2Wxpin** - `wxpin.yaml` - in_flag_reset_latency: 2 cycles
- **p2kbPasm2Wypin** - `wypin.yaml` - in_flag_reset_latency: 2 cycles
- **p2kbPasm2Rdpin** - `rdpin.yaml` - in_flag_reset_latency: 2 cycles
- **p2kbPasm2Akpin** - `akpin.yaml` - in_flag_reset_latency: 2 cycles
- **p2kbPasm2Drvh** - `drvh.yaml` - pin_output_latency: 3 cycles
- **p2kbPasm2Drvl** - `drvl.yaml` - pin_output_latency: 3 cycles
- **p2kbPasm2Testp** - `testp.yaml` - pin_sampling_latency: 2 cycles
- **p2kbArchNcoTiming** - NCO frequency and +1 rule
- **p2kbPasm2Xinit** - XINIT instruction details

### Other References
- SD Spec: 25 MHz maximum SPI clock for full-speed operation
- Silicon Doc v35 - P2 timing specifications
