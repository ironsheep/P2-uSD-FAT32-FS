# NCO Write Alignment Analysis: Power-of-2 Half-Period Streamer Failure

The definitive analysis of the streamer write-path timing failure at power-of-2 SPI half-period values, with proven root cause, verified fix, and cross-card test results.

**Date:** 2026-03-09
**Status:** Final — fix verified on hardware across 2 cards × 4 sysclk values

---

## 1. Summary

The P2 streamer write path fails at SPI half-period (hp) values that are powers of 2 (hp=4, hp=8). The failure is a consistent 1-bit left shift in written data — the card stores each byte shifted left by one bit position. The root cause is the P2 NCO phase accumulator: when `$4000_0000 / hp` divides exactly (only for power-of-2 hp), the first data bit and first clock edge arrive simultaneously, producing zero MOSI setup margin. Cards with tight setup requirements (PNY/Phison, Gigastone/Transcend) fail; cards with generous margins (SP Elite/SharedOEM) tolerate it.

The fix subtracts 1 from `xfrq` when the NCO division is exact, creating artificial truncation that delays the first data bit by 1 sysclk — matching the accidental margin that all non-power-of-2 hp values already have from integer truncation.

---

## 2. Root Cause: NCO Exact Division

### P2 NCO Operation

The P2 streamer NCO uses a 32-bit phase accumulator:

```
phase = (phase & $7FFF_FFFF) + frequency
```

MSB is cleared before each addition. When the new MSB is set, "rollover" occurs and the streamer advances to the next data element.

### The Math

For write streamer: `xfrq = $4000_0000 / spi_period` (one bit per full SPI clock period, where `spi_period = 2 * hp`).

After `2 * spi_period` cycles, the accumulator reaches:

```
acc = 2 * spi_period * floor($4000_0000 / spi_period)
    = $8000_0000 - 2 * ($4000_0000 mod spi_period)
```

- **Power-of-2 hp** (4, 8): mod = 0 → acc = exactly $8000_0000 → rollover at cycle 2×hp (ON TIME)
- **All other hp** (5, 6, 7, 9...): mod > 0 → acc < $8000_0000 → needs one more cycle → rollover at cycle 2×hp+1 (ONE CYCLE LATE)

That 1-cycle-late rollover from integer truncation is **accidental setup margin**. The data bit arrives on MOSI 1 sysclk before the clock edge. For power-of-2 hp, data and clock arrive simultaneously — zero margin.

### NCO Truncation Table

| hp | xfrq = $4000_0000 / (2×hp) | Exact? | $4000_0000 mod (2×hp) | First rollover |
|----|---------------------------|--------|----------------------|---------------|
| 4 | $1000_0000 | **YES** | 0 | cycle 8 (on time) |
| 5 | $0CCC_CCCC | no | 4 | cycle 11 (1 late) |
| 6 | $0AAA_AAAA | no | 4 | cycle 13 (1 late) |
| 7 | $0924_9249 | no | 3 | cycle 15 (1 late) |
| **8** | **$0800_0000** | **YES** | **0** | **cycle 16 (on time)** |
| 9 | $071C_71C7 | no | 1 | cycle 19 (1 late) |
| 10 | $0666_6666 | no | 4 | cycle 21 (1 late) |
| 11 | $05D1_745D | no | 3 | cycle 23 (1 late) |
| 12 | $0555_5555 | no | 4 | cycle 25 (1 late) |

---

## 3. Error Pattern

Every byte read back is the written byte shifted left by 1 bit:

```
Verify err byte 1: exp=$01 got=$02   (0000_0001 → 0000_0010)
Verify err byte 0: exp=$35 got=$6A   (0011_0101 → 0110_1010)
Verify err byte 0: exp=$6A got=$D4   (0110_1010 → 1101_0100)
```

The card sampled MOSI one clock cycle too late — capturing the next bit's value instead of the current one. Only write-verify (Phase 3) fails; single-sector reads (Phase 1) and multi-block reads (Phase 2) pass at all speeds.

---

## 4. Test Evidence

### 4.1 Pre-Fix Results (3 cards × 3-4 sysclk values)

| Card | MID | Controller | hp=4 | hp=8 | All other hp |
|------|-----|-----------|------|------|-------------|
| PNY 16GB | $27 | Phison | FAIL | FAIL | PASS |
| Gigastone 32GB | $74 | Transcend | FAIL | FAIL | PASS |
| SP Elite 64GB | $9F | SharedOEM | PASS | PASS | PASS |

The failure correlates with hp value, NOT SPI frequency. Three different actual SPI speeds at hp=8 (15.6, 16.9, 21.9 kHz depending on sysclk) all fail identically.

### 4.2 Post-Fix Results (2 affected cards × 4 sysclk values)

**Gigastone 32GB:**

| SYSCLK | hp=4 | hp=8 | All other hp | Result |
|--------|------|------|-------------|--------|
| 180 MHz | **PASS** (was FAIL) | n/a | PASS | ALL 11 PASS |
| 250 MHz | n/a | **PASS** (was FAIL) | PASS | ALL 11 PASS |
| 270 MHz | n/a | **PASS** (was FAIL) | PASS | ALL 11 PASS |
| 350 MHz | n/a | **PASS** (was FAIL) | PASS | ALL 11 PASS |

**PNY 16GB:**

| SYSCLK | hp=4 | hp=8 | All other hp | Result |
|--------|------|------|-------------|--------|
| 180 MHz | **PASS** (was FAIL) | n/a | PASS | ALL 11 PASS |
| 250 MHz | n/a | **PASS** (was FAIL) | PASS | ALL 11 PASS |
| 270 MHz | n/a | **PASS** (was FAIL) | PASS | ALL 11 PASS |
| 350 MHz | n/a | **PASS** (was FAIL) | PASS | ALL 11 PASS |

8 sweep runs, 88 total speed points, all PASS.

---

## 5. The Fix

### Code Change (both writeSector and writeSectors)

```spin2
xfrq := $4000_0000 / spi_period                          ' One output per full clock period
if ($4000_0000 // spi_period) == 0                        ' Exact division (power-of-2 hp)?
  xfrq -= 1                                              ' Ensure 1-cycle late rollover like truncated values
align_delay := spi_period - 2                              ' NCO ramp delay minus 2 instruction cycles
```

### Why This Works

For hp=8: xfrq changes from $0800_0000 to $07FF_FFFF. After 16 cycles the accumulator reaches $7FFF_FFF0 (short of $8000_0000). After 17 cycles: $87FF_FFEF (rollover). First bit now at cycle 17 = 2×hp + 1, matching all non-power-of-2 values.

The actual SPI frequency change is negligible — 0.000006% for hp=8.

### Why Not align_delay Adjustment

Three align_delay approaches were tested and failed:

1. `spi_period - 1`: hp=4 still failed (1 extra sysclk not enough at minimum hp)
2. `spi_period` (full hp): hp=4 passed, but hp=6 failed with 1-bit RIGHT-shift (opposite error)
3. Conditional per-hp values: no single constant works because NCO timing varies with hp

The `align_delay = spi_period - 2` formula was proven in the TX-TRANSITION-INVESTIGATION (2026-02-16) to fix right-shift errors on SanDisk Industrial. Changing it for some hp values risks re-introducing those failures.

### Related Change: card_is_slow Removal

The driver previously had a `card_is_slow` flag that limited certain cards to 20 MHz SPI. This was removed because:
1. It checked the wrong MID ($1D instead of the PNY card's actual $27)
2. The real fix is the xfrq correction, not speed reduction
3. No controller-specific sensing should exist in the driver

---

## 6. Impact on Default Configuration

| _CLKFREQ | hp for 25 MHz SPI | Status |
|-----------|-------------------|--------|
| 200 MHz | 4 | Fixed by xfrq -= 1 |
| 250 MHz | 5 | Always worked |
| 270 MHz | 6 | Always worked |
| 300 MHz | 6 | Always worked |
| 350 MHz | 7 | Always worked |
| 400 MHz | 8 | Fixed by xfrq -= 1 |

Users at 400 MHz sysclk with the default 25 MHz SPI would have hit this bug. The fix makes all sysclk/SPI combinations safe.

---

## 7. References

- [STREAMER-SPI-TIMING](../Decisions/STREAMER-SPI-TIMING.md) — Original streamer timing design
- [STREAMER-TIMING-ANALYSIS](STREAMER-TIMING-ANALYSIS.md) — NCO precision analysis
- [PNY-HP8-STREAMER-WRITE-ALIGNMENT](../Research/support/PNY-HP8-STREAMER-WRITE-ALIGNMENT.md) — Full investigation tracking document
- P2KB: `p2kbArchNcoTiming`, `p2kbPasm2Setxfrq`, `p2kbPasm2Xinit`
- Diagnostic test: `diagnostic-tests/SD_freq_sweep_tests.spin2`

---

*Analysis completed: 2026-03-09*
*Fix verified on: PNY 16GB (Phison $27), Gigastone 32GB (Transcend $74), 4 sysclk values each*
