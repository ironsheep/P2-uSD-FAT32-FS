# Power-of-2 hp Streamer Write Alignment Failure (Universal)

**Date**: 2026-03-09
**Status**: Active investigation — confirmed on 2 of 3 cards; 1 card immune
**Cards tested**:
- PNY 16GB SDHC (Phison controller, MID=$27, CID: Phison SD16G) — **FAILS at hp=8**
- Gigastone 32GB SDHC (Transcend controller, MID=$74, CID: Transcend 00000, SN:$0000_01C7) — **FAILS at hp=8**
- Silicon Power Elite 64GB SDXC (SharedOEM, MID=$9F, CID: SPCC 0.7, SN:$0094_0105) — **PASSES hp=8**
**Related**: [PNY-MICROSD-SPI-ISSUES.md](../PNY-MICROSD-SPI-ISSUES.md), TX-TRANSITION-INVESTIGATION (2026-02-16, retained locally), [STREAMER-SPI-TIMING](../../Decisions/STREAMER-SPI-TIMING.md), CARD-CATALOG.md

---

## 1. Discovery

During frequency sweep characterization of the PNY card, write-verify (Phase 3) fails **exclusively at power-of-2 half-period values (hp=4 and hp=8)**, regardless of system clock frequency. Single-sector reads (Phase 1) and multi-block reads (Phase 2) pass at all speeds including hp=4 and hp=8.

The failure is 100% reproducible: every power-of-2 hp test fails, every non-power-of-2 hp test passes. hp=4 confirmed on Gigastone at 180 MHz sysclk.

---

## 2. Test Results

Frequency sweep test: `diagnostic-tests/SD_freq_sweep_tests.spin2`

### 2.1 — 350 MHz sysclk

| Target | hp | Actual SPI | Single | Multi | WrVerify | Overall |
|--------|----|-----------|--------|-------|----------|---------|
| 15 MHz | 12 | 14,583 kHz | PASS | PASS | PASS | PASS |
| 16 MHz | 11 | 15,909 kHz | PASS | PASS | PASS | PASS |
| 17 MHz | 11 | 15,909 kHz | PASS | PASS | PASS | PASS |
| 18 MHz | 10 | 17,500 kHz | PASS | PASS | PASS | PASS |
| 19 MHz | 10 | 17,500 kHz | PASS | PASS | PASS | PASS |
| 20 MHz | 9 | 19,444 kHz | PASS | PASS | PASS | PASS |
| 21 MHz | 9 | 19,444 kHz | PASS | PASS | PASS | PASS |
| **22 MHz** | **8** | **21,875 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **23 MHz** | **8** | **21,875 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **24 MHz** | **8** | **21,875 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| 25 MHz | 7 | 25,000 kHz | PASS | PASS | PASS | PASS |

### 2.2 — 270 MHz sysclk

| Target | hp | Actual SPI | Single | Multi | WrVerify | Overall |
|--------|----|-----------|--------|-------|----------|---------|
| 15 MHz | 9 | 15,000 kHz | PASS | PASS | PASS | PASS |
| 16 MHz | 9 | 15,000 kHz | PASS | PASS | PASS | PASS |
| **17 MHz** | **8** | **16,875 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **18 MHz** | **8** | **16,875 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **19 MHz** | **8** | **16,875 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| 20 MHz | 7 | 19,285 kHz | PASS | PASS | PASS | PASS |
| 21 MHz | 7 | 19,285 kHz | PASS | PASS | PASS | PASS |
| 22 MHz | 7 | 19,285 kHz | PASS | PASS | PASS | PASS |
| 23 MHz | 6 | 22,500 kHz | PASS | PASS | PASS | PASS |
| 24 MHz | 6 | 22,500 kHz | PASS | PASS | PASS | PASS |
| 25 MHz | 6 | 22,500 kHz | PASS | PASS | PASS | PASS |

### 2.3 — 250 MHz sysclk

| Target | hp | Actual SPI | Single | Multi | WrVerify | Overall |
|--------|----|-----------|--------|-------|----------|---------|
| 15 MHz | 9 | 13,888 kHz | PASS | PASS | PASS | PASS |
| **16 MHz** | **8** | **15,625 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **17 MHz** | **8** | **15,625 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| 18 MHz | 7 | 17,857 kHz | PASS | PASS | PASS | PASS |
| 19 MHz | 7 | 17,857 kHz | PASS | PASS | PASS | PASS |
| 20 MHz | 7 | 17,857 kHz | PASS | PASS | PASS | PASS |
| 21 MHz | 6 | 20,833 kHz | PASS | PASS | PASS | PASS |
| 22 MHz | 6 | 20,833 kHz | PASS | PASS | PASS | PASS |
| 23 MHz | 6 | 20,833 kHz | PASS | PASS | PASS | PASS |
| 24 MHz | 6 | 20,833 kHz | PASS | PASS | PASS | PASS |
| 25 MHz | 5 | 25,000 kHz | PASS | PASS | PASS | PASS |

### 2.4 — Summary: hp=8 is the common factor

| SYSCLK | hp=8 actual SPI | Failure |
|--------|----------------|---------|
| 250 MHz | 15,625 kHz | Write-verify 5/5 errors |
| 270 MHz | 16,875 kHz | Write-verify 5/5 errors |
| 350 MHz | 21,875 kHz | Write-verify 5/5 errors |

The failure tracks the half-period value (hp=8), NOT the SPI frequency. Three very different actual SPI speeds (15.6, 16.9, 21.9 kHz) all fail identically. All other hp values pass at all three sysclk values.

### 2.5 — Gigastone 32GB (Transcend $74) — Identical Pattern

The Gigastone card was tested at the same three sysclk values. Results are **identical** to PNY — hp=8 fails, all other hp values pass.

**350 MHz**: hp=8 (22-24 MHz targets, actual 21,875 kHz) → FAIL. All others PASS.
**270 MHz**: hp=8 (17-19 MHz targets, actual 16,875 kHz) → FAIL. All others PASS.
**250 MHz**: hp=8 (16-17 MHz targets, actual 15,625 kHz) → FAIL. All others PASS.

### 2.6 — Cross-Card Summary

| Card | MID | Controller | 350 MHz hp=8 | 270 MHz hp=8 | 250 MHz hp=8 | All other hp |
|------|-----|-----------|-------------|-------------|-------------|-------------|
| PNY 16GB | $27 | Phison | **FAIL** | **FAIL** | **FAIL** | PASS |
| Gigastone 32GB | $74 | Transcend | **FAIL** | **FAIL** | **FAIL** | PASS |

Two completely different card controllers from different manufacturers fail identically at hp=8. **This is not a card-specific issue — it is a P2 streamer write-path timing bug.**

### 2.7 — Silicon Power Elite 64GB (SharedOEM $9F) — ALL PASS Including hp=8

The SP Elite card was tested at all three sysclk values. **All 11 speeds pass at every sysclk, including hp=8.** This is the first card to tolerate the zero-margin alignment at hp=8.

**350 MHz**: ALL 11 PASS (hp=8 at 22-24 MHz targets, actual 21,875 kHz → PASS)
**270 MHz**: ALL 11 PASS (hp=8 at 17-19 MHz targets, actual 16,875 kHz → PASS)
**250 MHz**: ALL 11 PASS (hp=8 at 16-17 MHz targets, actual 15,625 kHz → PASS)

### 2.8 — Updated Cross-Card Summary

| Card | MID | Controller | 350 MHz hp=8 | 270 MHz hp=8 | 250 MHz hp=8 | All other hp | Rating |
|------|-----|-----------|-------------|-------------|-------------|-------------|--------|
| PNY 16GB | $27 | Phison | **FAIL** | **FAIL** | **FAIL** | PASS | D |
| Gigastone 32GB | $74 | Transcend | **FAIL** | **FAIL** | **FAIL** | PASS | C |
| SP Elite 64GB | $9F | SharedOEM | PASS | PASS | PASS | PASS | A |

The SP Elite's immunity to hp=8 indicates that the zero-margin alignment is **tolerable for cards with wider MOSI setup windows**. This reframes the issue: the P2 produces a marginal but technically valid timing at hp=8. Cards with tighter MOSI setup requirements (PNY, Gigastone) fail; cards with wider margins (SP Elite) tolerate it. The bug is real but card-dependent in impact — a **marginal timing issue** rather than a hard failure.

### 2.9 — hp=4 Confirmation (Gigastone at 180 MHz sysclk)

**HYPOTHESIS A CONFIRMED.** At 180 MHz sysclk, targets 23-25 MHz produce hp=4. All three fail write-verify with the identical 1-bit left shift pattern:

| Target | hp | Actual SPI | Single | Multi | WrVerify | Overall |
|--------|----|-----------|--------|-------|----------|---------|
| 15 MHz | 6 | 15,000 kHz | PASS | PASS | PASS | PASS |
| 16 MHz | 6 | 15,000 kHz | PASS | PASS | PASS | PASS |
| 17 MHz | 6 | 15,000 kHz | PASS | PASS | PASS | PASS |
| 18 MHz | 5 | 18,000 kHz | PASS | PASS | PASS | PASS |
| 19 MHz | 5 | 18,000 kHz | PASS | PASS | PASS | PASS |
| 20 MHz | 5 | 18,000 kHz | PASS | PASS | PASS | PASS |
| 21 MHz | 5 | 18,000 kHz | PASS | PASS | PASS | PASS |
| 22 MHz | 5 | 18,000 kHz | PASS | PASS | PASS | PASS |
| **23 MHz** | **4** | **22,500 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **24 MHz** | **4** | **22,500 kHz** | PASS | PASS | **FAIL** | **FAIL** |
| **25 MHz** | **4** | **22,500 kHz** | PASS | PASS | **FAIL** | **FAIL** |

Error pattern identical: `exp=$01 got=$02`, `exp=$35 got=$6A`, `exp=$6A got=$D4` — same 1-bit left shift as hp=8.

This confirms that the failure is triggered by **any power-of-2 hp value** where `$4000_0000 / hp` divides exactly, not just hp=8. Both hp=4 and hp=8 produce zero NCO truncation error and therefore zero setup margin.

---

## 3. Error Pattern: Consistent 1-Bit Left Shift

Every byte read back is the written byte shifted left by one bit:

```
Verify err iter 0 byte 1: exp=$01 got=$02   (0000_0001 -> 0000_0010)
Verify err iter 1 byte 0: exp=$35 got=$6A   (0011_0101 -> 0110_1010)
Verify err iter 2 byte 0: exp=$6A got=$D4   (0110_1010 -> 1101_0100)
```

Each value is exactly `expected << 1`. The card stored data one bit position off — a **write-path framing error** where the card sampled one clock cycle too late (or the data arrived one clock cycle too late relative to the sampling edge).

Since single reads (CMD17) and multi-block reads (CMD18) pass at hp=8, the **read path is not affected**. The issue is isolated to the streamer TX (write) path.

---

## 4. Driver Code: Write vs Read Streamer Paths

### 4.1 Write path (`writeSector()`, line ~5455-5479)

```pasm
    align_delay := spi_period - 2           ' hp - 2 cycles

    org
          dirl    _sck                      ' T=0:  Reset SCK counter
          drvl    _sck                      ' T=2:  Restart base period counter
          setxfrq xfrq                      ' T=4:  Set streamer bit rate
          rdfast  #0, p_buf                 ' T=6:  Setup RDFAST from hub buffer
          xinit   stream_mode, #0           ' T=8:  Start streamer (NCO from zero)
          waitx   align_delay               ' T=10: Wait align_delay cycles
          wypin   clk_count, _sck           ' T=10+align_delay: Start clock
          waitxfi                           ' Wait for streamer to complete
    end
```

Key parameters:
- `xfrq = $4000_0000 / spi_period` — one bit per full clock period
- `align_delay = spi_period - 2` — delay between streamer start and clock start
- Streamer init phase: `#0` (NCO ramps from zero)
- MOSI smart pin disabled; streamer drives pin directly

### 4.2 Read path (`readSector()`, lines ~5161-5170)

```pasm
    align_delay := spi_period               ' Full half-period
    init_phase := $4000_0000                ' Mid-bit phase offset

    org
          dirl    _sck                      ' Reset SCK counter
          drvl    _sck                      ' Restart base period counter
          setxfrq xfrq                      ' Set streamer NCO rate
          wrfast  #0, p_buf                 ' Setup WRFAST to hub buffer
          wypin   clk_count, _sck           ' Start clock FIRST
          waitx   align_delay               ' Wait one half-period
          xinit   stream_mode, init_phase   ' Start streamer with phase=0x4000_0000
          waitxfi                           ' Wait for streamer complete
    end
```

### 4.3 Critical differences

| Aspect | Read Path | Write Path |
|--------|-----------|------------|
| **Sequence** | Clock first, then streamer | Streamer first, then clock |
| **align_delay** | `spi_period` (full hp) | `spi_period - 2` (hp minus 2) |
| **NCO init phase** | `$4000_0000` (mid-bit) | `#0` (zero) |
| **Purpose** | Sample mid-bit for stability | Output data before clock edge |

---

## 5. Prior Art: TX-TRANSITION-INVESTIGATION (2026-02-16)

The `align_delay = spi_period - 2` formula was established in the TX Transition Investigation (2026-02-16, retained locally) to fix a **1-bit right-shift** on SanDisk Industrial cards. The timing model from that investigation:

```
First data bit appears at: T = 2 * spi_period  (from xinit)
First SCK rising edge at:  T = 2 + align_delay + spi_period

With align_delay = spi_period - 2:
  First SCK edge = 2 + (spi_period - 2) + spi_period = 2 * spi_period
  => "Perfect alignment" — data and clock arrive simultaneously
```

This was verified on SanDisk Industrial SA16G: 236/236 regression tests passed.

**But "perfect alignment" means zero setup margin.** The data bit and clock edge arrive at the same instant. If ANY timing variation causes the data to arrive even 1 sysclk late, the card samples the previous pin state.

---

## 6. Hypotheses

### HYPOTHESIS A: NCO Exact Division (Zero-Margin Alignment) — CONFIRMED (hp=4 and hp=8 both fail)

**Statement**: At hp=8, the NCO frequency `$4000_0000 / 8 = $0800_0000` divides exactly with no truncation. This produces a perfectly deterministic phase relationship where the first data bit arrives at EXACTLY `T = 2 * spi_period` — zero setup margin before the first clock edge. At all other tested hp values, integer truncation of the NCO division causes the first data bit to arrive slightly LATER than the ideal, providing accidental setup margin.

**Supporting evidence**:

NCO values for each hp:

| hp | xfrq = $4000_0000 / hp | Exact? | Truncation error |
|----|------------------------|--------|-----------------|
| 4 | $1000_0000 | **YES** | 0 |
| 5 | $0CCC_CCCC | no | 0.8 ($4000_0000 mod 5 = 4) |
| 6 | $0AAA_AAAA | no | 0.67 ($4000_0000 mod 6 = 4) |
| 7 | $0924_9249 | no | 0.57 ($4000_0000 mod 7 = 3) |
| **8** | **$0800_0000** | **YES** | **0** |
| 9 | $071C_71C7 | no | 0.11 ($4000_0000 mod 9 = 1) |
| 10 | $0666_6666 | no | 0.6 ($4000_0000 mod 10 = 4) |
| 11 | $05D1_745D | no | 0.73 ($4000_0000 mod 11 = 3) |
| 12 | $0555_5555 | no | 0.33 ($4000_0000 mod 12 = 4) |

With truncated xfrq, the NCO accumulates slightly LESS per cycle than the ideal rate. The first rollover (data bit output) occurs slightly LATER than `2 * spi_period` cycles. This tiny delay provides accidental setup time — the data is on the pin before the clock edge arrives.

With exact xfrq (hp=4, hp=8), the NCO rolls over at EXACTLY `2 * spi_period`. The data bit and clock edge arrive simultaneously. On cards with tight MOSI setup requirements (PNY/Phison), this zero-margin alignment means the card samples the previous pin state.

**Prediction**: hp=4 should also fail (also exact division). **CONFIRMED** — Gigastone at 180 MHz sysclk fails at hp=4 with identical 1-bit left shift pattern (Section 2.9).

**Prediction**: Other cards with wider margins would tolerate hp=8 but might show marginal behavior (occasional CRC errors rather than systematic shift).

**Confirmed**: The SP Elite card (Rating A, SharedOEM $9F) passes hp=8 at all three sysclk values. This card has wider MOSI setup margins and tolerates the zero-margin alignment. This is exactly what Hypothesis A predicts — the timing is marginal, not broken. Cards with tight setup requirements fail; cards with generous margins pass.

**What would disprove this**: If hp=4 passes on the PNY card, or if adding 1 sysclk to `align_delay` doesn't fix hp=8.

### HYPOTHESIS B: P_TRANSITION Base-Period Counter Phase Interaction

**Statement**: The SCK smart pin's P_TRANSITION base-period counter, after being reset by `dirl`/`drvl`, has a specific startup phase that interacts differently with hp=8 than other values. The counter counts 0 to hp-1 then toggles. The wypin instruction's delivery of the transition count may arrive at a different point in the counter cycle depending on hp and the elapsed time since drvl.

**Supporting evidence**: The write path does `dirl` then `drvl` (resetting and restarting the base-period counter), then 3 instructions later does `xinit`, then `waitx`, then `wypin`. The counter has been free-running since `drvl`. At `wypin` time, the counter's position depends on how many cycles have elapsed — which is `8 + align_delay = 8 + (hp - 2) = hp + 6`. For hp=8, the counter has run 14 cycles = 1 full period (8) + 6. For hp=7, it's run 13 cycles = 1 full period (7) + 6. The counter's phase at wypin time varies with hp.

**What would disprove this**: If the same failure occurs with a different number of instructions between drvl and wypin (changing the counter phase at wypin time).

### HYPOTHESIS C: Card-Internal Controller Timing — ELIMINATED

**Statement**: The PNY/Phison card's SPI controller has an internal PLL or clock recovery circuit that has a specific blind spot at frequencies near the actual SPI frequency produced by hp=8. The card's internal timing, not the P2's timing, is the source of the 1-bit shift.

**Status**: **ELIMINATED.** The Gigastone card (Transcend $74 controller) reproduces the exact same failure at hp=8 as the PNY card (Phison $27 controller). Two entirely different controller silicon exhibiting identical behavior rules out a card-specific cause. This is a P2-side issue.

---

## 7. Predicted hp=8 Failures Across CLKFREQ Range

For any given sysclk, hp=8 occurs when `ceil(clkfreq / (2 * spi_target)) = 8`, meaning `spi_target` falls in `[clkfreq/16, clkfreq/14)`.

Within the 200-350 MHz range (where 25 MHz SPI is achievable):

| CLKFREQ | SPI targets producing hp=8 (from 15-25 MHz sweep) |
|---------|--------------------------------------------------|
| 200 MHz | none (below 15 MHz sweep floor) |
| 210 MHz | none (15 MHz is exactly hp=7) |
| 220 MHz | **15 MHz** |
| 230 MHz | **15, 16 MHz** |
| 240 MHz | **15, 16, 17 MHz** |
| 250 MHz | **16, 17 MHz** (confirmed) |
| 260 MHz | **17, 18 MHz** |
| 270 MHz | **17, 18, 19 MHz** (confirmed) |
| 280 MHz | **18, 19 MHz** |
| 290 MHz | **19, 20 MHz** |
| 300 MHz | **19, 20, 21 MHz** |
| 310 MHz | **20, 21, 22 MHz** |
| 320 MHz | **20, 21, 22 MHz** |
| 330 MHz | **21, 22, 23 MHz** |
| 340 MHz | **22, 23, 24 MHz** |
| 350 MHz | **22, 23, 24 MHz** (confirmed) |

**Critical**: At `_CLKFREQ = 400 MHz`, the default 25 MHz SPI target produces hp=8. This is a real user scenario.

---

## 8. Impact Assessment

### 8.1 Current driver default (25 MHz SPI)

| _CLKFREQ | hp for 25 MHz | Status |
|-----------|--------------|--------|
| 200 MHz | 4 (min) | **UNTESTED** (also exact division — see Hypothesis A) |
| 250 MHz | 5 | PASS |
| 270 MHz | 6 | PASS (tested) |
| 300 MHz | 6 | PASS |
| 320 MHz | 7 | PASS |
| 350 MHz | 7 | PASS (tested) |
| **400 MHz** | **8** | **PREDICTED FAIL** |

At all tested sysclk values (250, 270, 350 MHz), the default 25 MHz SPI does NOT hit hp=8. Users would only hit hp=8 for 25 MHz SPI at 400 MHz sysclk.

### 8.2 User-selected SPI speeds via setSPISpeed()

Users calling `setSPISpeed()` with intermediate frequencies could hit hp=8 at any clkfreq. The prediction table in Section 7 shows the affected ranges.

---

## 9. Potential Fix Approaches

### Fix 1: Increase align_delay by 1 (`spi_period - 1`)

Changes `align_delay = spi_period - 2` to `spi_period - 1`. This adds 1 extra sysclk of data lead time before the first clock edge. For exact-division hp values, this provides 1 sysclk of setup margin instead of zero.

**Risk**: The original `spi_period - 2` was tuned to fix a 1-bit RIGHT-shift on SanDisk Industrial. Adding delay could re-introduce that failure. The SanDisk fix required the data and clock to arrive at the same time — making data arrive 1 sysclk earlier might cause the card to sample the NEXT bit instead of the current one on cards with tight hold-time requirements.

**Required testing**: Full sweep on PNY AND SanDisk Industrial AND at least one more card.

### Fix 2: Add NCO phase offset to TX streamer

Change `xinit stream_mode, #0` to `xinit stream_mode, init_phase` where `init_phase` is a small positive value (e.g., `$0100_0000`). This pre-loads the NCO accumulator, causing the first data bit to appear earlier.

**Risk**: Phase offset effect varies with hp value. A fixed offset helps hp=8 but changes timing for all other hp values too.

### Fix 3: hp=8 avoidance in applySPISpeed()

If hp calculates to 8, bump to 9 (slightly slower) or 7 (slightly faster, but may exceed target). This avoids the problem rather than fixing the root cause.

**Risk**: User-visible speed change. Hides the issue. hp=4 (also exact division) might need the same treatment. Fragile approach.

### Fix 4: Conditional align_delay for exact-division hp values

```spin2
if (spi_period & (spi_period - 1)) == 0   ' Power-of-2 check
  align_delay := spi_period - 1             ' Extra margin for exact NCO division
else
  align_delay := spi_period - 2             ' Standard margin
```

**Risk**: Only addresses powers of 2 (hp=4, 8). If the issue is more general (just most visible at exact division), this is incomplete.

### Fix 5: Full characterization across multiple cards

Run the frequency sweep on SanDisk, Samsung, Kingston, etc. to determine if hp=8 is marginal for ALL cards or truly PNY-specific. This informs whether the fix needs to be universal or card-specific.

---

## 10. Open Questions

1. ~~**Does hp=4 also fail?**~~ **YES — CONFIRMED.** Gigastone at 180 MHz sysclk, hp=4 fails with identical 1-bit left shift. Hypothesis A fully validated.

2. **Is hp=8 marginal on other cards?** SP Elite passes cleanly (no CRC errors). Need SanDisk Industrial (known tight timing) and Samsung to complete the picture.

3. **What is the actual P2 streamer NCO output latency?** The timing model assumes first bit at `T = 2 * spi_period`, but the exact NCO→pin propagation delay may differ from the mathematical model.

4. **Does the P_TRANSITION base-period counter have startup latency?** If the first transition takes longer than subsequent ones (pipeline fill), the timing model's clock edge prediction may be off.

---

## 11. Recommended Next Steps

1. **Test hp=4 on PNY card** — validates/invalidates Hypothesis A (need clkfreq where sweep hits hp=4, or a targeted single-speed test)
2. **Run freq sweep on SanDisk Industrial** — the card that originally exposed the TX alignment bug; check if hp=8 shows any degradation
3. **Run freq sweep on Samsung and one other card** — broader margin check
4. **Test `align_delay = spi_period - 1`** on PNY across all speeds — if this fixes hp=8 without breaking hp=7, it's a strong candidate
5. **If step 4 works**: verify on SanDisk Industrial (the card sensitive in the other direction)

---

## 12. Log Files

### PNY 16GB (Phison $27)
- `tools/logs/SD_freq_sweep_tests_260309-184700.log` — 350 MHz sysclk
- `tools/logs/SD_freq_sweep_tests_260309-192932.log` — 270 MHz sysclk
- `tools/logs/SD_freq_sweep_tests_260309-192908.log` — 250 MHz sysclk

### Gigastone 32GB (Transcend $74)
- `tools/logs/SD_freq_sweep_tests_260309-220037.log` — 350 MHz sysclk
- `tools/logs/SD_freq_sweep_tests_260309-220102.log` — 270 MHz sysclk
- `tools/logs/SD_freq_sweep_tests_260309-220126.log` — 250 MHz sysclk

### Silicon Power Elite 64GB (SharedOEM $9F) — ALL PASS
- `tools/logs/SD_freq_sweep_tests_260309-220831.log` — 350 MHz sysclk (ALL PASS)
- `tools/logs/SD_freq_sweep_tests_260309-220859.log` — 270 MHz sysclk (ALL PASS)
- `tools/logs/SD_freq_sweep_tests_260309-220923.log` — 250 MHz sysclk (ALL PASS)

### hp=4 Confirmation (Gigastone 32GB at 180 MHz)
- `tools/logs/SD_freq_sweep_tests_260309-221656.log` — 180 MHz sysclk (hp=4 FAIL at 23-25 MHz targets)

---

## 13. Correction: card_is_slow Was Misapplied

The driver's `card_is_slow` flag (in `identifyCard()`) checked manufacturer ID `$1D` (AData), but the PNY card actually has MID `$27` (Phison). The flag never applied to the PNY card — it was already running at 25 MHz in all previous testing. The card catalog correctly identified the PNY card as Phison $27, but the driver code was checking the wrong MID.

The `card_is_slow` mechanism should be removed regardless of this investigation — no card with MID `$1D` is in the current test catalog, and the PNY card it was intended to protect uses a different MID.

---

## 14. Fix Decision: Conditional align_delay for Power-of-2 hp

### Reasoning

The root cause is confirmed: when `$4000_0000 / hp` divides exactly (hp=4, hp=8), the NCO accumulator produces zero truncation error, resulting in zero MOSI setup margin. The fix must add setup margin only at these exact-division points without disturbing the proven timing at other hp values.

**Why conditional, not universal?** The `spi_period - 2` formula was established in the TX-TRANSITION-INVESTIGATION (2026-02-16) to fix a 1-bit right-shift on SanDisk Industrial at all other hp values. Changing to `spi_period - 1` universally risks re-introducing that right-shift failure on SanDisk and similar cards. The conditional approach preserves the proven timing for non-power-of-2 hp values while adding 1 sysclk of margin where it's needed.

**Why not hp avoidance?** Bumping hp=8→9 or hp=4→5 changes the user's actual SPI speed. It hides the problem and creates confusing behavior where `setSPISpeed(22_000_000)` gives a different speed than expected. The conditional delay fixes the root cause transparently.

**Detection**: `(hp & (hp - 1)) == 0` is the standard power-of-2 check. In the useful hp range (4-12), only hp=4 and hp=8 are powers of 2. hp=16 (also power of 2) would produce SPI speeds below the usable range for typical sysclk values.

### Implementation

In the write-path PASM block, before the `org`:
```spin2
if (spi_period & (spi_period - 1)) == 0
  align_delay := spi_period - 1    ' +1 sysclk margin for exact NCO division
else
  align_delay := spi_period - 2    ' standard timing (proven on SanDisk Industrial)
```

---

## 15. NCO Fractional Accumulation Math — Root Cause Identified

### P2KB Reference

The P2 Knowledge Base (`p2kbArchNcoTiming`) documents the NCO operation:

```
1. MSB is masked (cleared) before addition
2. Frequency value adds to phase accumulator
3. If new MSB is set, "rollover" occurs
4. On rollover, streamer advances to next data element

formula: phase = (phase & $7FFF_FFFF) + frequency
```

The P2KB common values table explicitly notes: **"For fractional ratios (1/3, 1/5, 1/10), add 1 to ensure proper initial rollover timing."** Our driver used plain integer division WITHOUT the +1.

### The Math

After `2 * spi_period` cycles, the NCO accumulator reaches:

```
acc = 2 * spi_period * floor($4000_0000 / spi_period)
    = 2 * ($4000_0000 - ($4000_0000 mod spi_period))
    = $8000_0000 - 2 * ($4000_0000 mod spi_period)
```

- **Power-of-2 hp** (4, 8): `$4000_0000 mod hp = 0` → acc = exactly `$8000_0000` → rollover at cycle `2*hp` (ON TIME)
- **All other hp** (5, 6, 7, 9...): `$4000_0000 mod hp > 0` → acc < `$8000_0000` → needs one more cycle → rollover at cycle `2*hp + 1` (ONE CYCLE LATE)

That 1-cycle-late rollover from integer truncation is **accidental setup margin**. The data bit arrives on MOSI 1 sysclk before the clock edge. For power-of-2 hp, data and clock arrive simultaneously — zero margin.

This is deterministic, not jitter. Every non-power-of-2 hp gets free margin from truncation. Only hp=4 and hp=8 don't.

---

## 16. Fix Attempts — align_delay Adjustments (FAILED)

### Attempt 1: Conditional align_delay (hp=4→spi_period, hp=8→spi_period-1, else→spi_period-2)

**Result**: hp=4 still FAILED. The conditional was correct (verified both write paths), but `spi_period` (=4 at hp=4) wasn't enough extra delay.

### Attempt 2: Universal align_delay = spi_period - 1

**Result**: hp=4 still FAILED. hp=5,6,7,8+ untested but hp=8 expected to pass.

### Attempt 3: Universal align_delay = spi_period

**Result**: hp=4 PASSED, but hp=6 FAILED (1-bit RIGHT-shift — the opposite error). Too much delay pushes data too far ahead, and hp=6 cards now sample the NEXT bit.

### Key Insight from Attempts

There is no single constant offset to `align_delay` that works for all hp values. The relationship between NCO timing and clock alignment is hp-dependent. The `spi_period - 2` formula works for all non-power-of-2 hp because they all share the same 1-cycle-late rollover from truncation. Power-of-2 values are the outliers.

---

## 17. Successful Fix: xfrq -= 1 for Exact Division

### Approach

Instead of adjusting `align_delay` (which changes the clock-to-data relationship differently per hp), adjust the NCO frequency itself. For exact-division hp values, subtract 1 from xfrq to create artificial truncation:

```spin2
xfrq := $4000_0000 / spi_period
if ($4000_0000 // spi_period) == 0    ' exact division (power-of-2 hp)?
  xfrq -= 1                           ' ensure 1-cycle late rollover like truncated values
align_delay := spi_period - 2         ' proven formula unchanged
```

For hp=8: xfrq changes from `$0800_0000` to `$07FF_FFFF`. After 16 cycles: acc = `$7FFF_FFF0` (short of $8000_0000). After 17 cycles: acc = `$87FF_FFEF` (rollover). First bit now arrives at cycle 17 = `2*hp + 1`, same as all non-power-of-2 values.

For hp=4: xfrq changes from `$1000_0000` to `$0FFF_FFFF`. After 8 cycles: acc = `$7FFF_FFF8` (short). After 9 cycles: acc = `$8FFF_FFF7` (rollover). First bit at cycle 9 = `2*hp + 1`.

The actual SPI frequency change is negligible: for hp=8, xfrq goes from $0800_0000 to $07FF_FFFF — a 0.000006% change in the NCO rate, well below any measurable effect.

### Why This Works

- Leaves `align_delay = spi_period - 2` untouched (proven on SanDisk Industrial)
- Only affects the 2 hp values that need it (4 and 8)
- All hp values now have uniform first-rollover timing at `2*spi_period + 1`
- Non-power-of-2 hp values are completely unchanged
- The fix is the inverse of the P2KB "+1 for fractional" recommendation — instead of making fractional values exact (removing margin), we make exact values fractional (adding margin)

### Verification Results — Gigastone 32GB with Fix Applied

| SYSCLK | hp=4 | hp=8 | All other hp | Result |
|--------|------|------|-------------|--------|
| 180 MHz | **PASS** (was FAIL) | n/a | PASS | **ALL 11 PASS** |
| 250 MHz | n/a | **PASS** (was FAIL) | PASS | **ALL 11 PASS** |
| 270 MHz | n/a | **PASS** (was FAIL) | PASS | **ALL 11 PASS** |
| 350 MHz | n/a | **PASS** (was FAIL) | PASS | **ALL 11 PASS** |

Fix applied to both write paths: `writeSector()` (single-block CMD24) and `writeSectors()` (multi-block CMD25).

### PNY 16GB (Phison $27) with Fix Applied

| SYSCLK | hp=4 | hp=8 | All other hp | Result |
|--------|------|------|-------------|--------|
| 180 MHz | **PASS** (was FAIL) | n/a | PASS | **ALL 11 PASS** |
| 250 MHz | n/a | **PASS** (was FAIL) | PASS | **ALL 11 PASS** |
| 270 MHz | n/a | **PASS** (was FAIL) | PASS | **ALL 11 PASS** |
| 350 MHz | n/a | **PASS** (was FAIL) | PASS | **ALL 11 PASS** |

Both cards (Gigastone and PNY) that previously failed at power-of-2 hp now pass all speeds at all sysclk values with the `xfrq -= 1` fix.

---

## 18. Log Files — Fix Verification

### Gigastone 32GB with xfrq-=1 Fix
- `tools/logs/SD_freq_sweep_tests_260309-223355.log` — 180 MHz sysclk (hp=4 NOW PASSES)
- `tools/logs/SD_freq_sweep_tests_260309-223421.log` — 350 MHz sysclk (hp=8 NOW PASSES)
- `tools/logs/SD_freq_sweep_tests_260309-223445.log` — 270 MHz sysclk (hp=8 NOW PASSES)
- `tools/logs/SD_freq_sweep_tests_260309-223510.log` — 250 MHz sysclk (hp=8 NOW PASSES)

### PNY 16GB with xfrq-=1 Fix
- `tools/logs/SD_freq_sweep_tests_260309-223749.log` — 350 MHz sysclk (ALL PASS)
- `tools/logs/SD_freq_sweep_tests_260309-223815.log` — 270 MHz sysclk (ALL PASS)
- `tools/logs/SD_freq_sweep_tests_260309-223839.log` — 250 MHz sysclk (ALL PASS)
- `tools/logs/SD_freq_sweep_tests_260309-223906.log` — 180 MHz sysclk (hp=4 NOW PASSES)

### Failed Fix Attempts (align_delay adjustments)
- `tools/logs/SD_freq_sweep_tests_260309-221931.log` — 180 MHz, conditional align_delay (hp=4 still failed)
- `tools/logs/SD_freq_sweep_tests_260309-222131.log` — 180 MHz, universal spi_period-1 (hp=4 still failed)
- `tools/logs/SD_freq_sweep_tests_260309-222157.log` — 180 MHz, universal spi_period (hp=4 passed, hp=6 FAILED)
- `tools/logs/SD_freq_sweep_tests_260309-222228.log` — 180 MHz, conditional hp=4→spi_period (hp=4 still failed)

---

*Investigation started: 2026-03-09*
*Last updated: 2026-03-09*
*For use in: Streamer timing optimization, driver hardening*
