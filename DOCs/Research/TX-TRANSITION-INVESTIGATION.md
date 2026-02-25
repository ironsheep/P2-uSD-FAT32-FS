# TX Streamer Transition Investigation

**Date**: 2026-02-16
**Status**: RESOLVED — fix verified with 236/236 regression tests passing
**Bug**: 1-bit right-shift on MOSI during writeSector on SanDisk Industrial (and likely other timing-sensitive cards)
**Fix**: `align_delay := spi_period - 2` between `xinit` and `wypin`, with `init_phase := #0`

---

## The Problem

When writing sectors to an SD card, the MOSI pin must transition between two operating modes:

1. **Smart pin** (P_SYNC_TX) — for command bytes, start token, CRC, response polling
2. **Streamer** (XINIT/WAITXFI DMA) — for 512-byte bulk sector data

This transition introduces a pin state discontinuity. On cards with tight SPI setup/hold margins (SanDisk Industrial SA16G), this discontinuity is sampled as an extra data bit, causing a **systematic 1-bit right-shift** in the received data.

### Shift Signature

Every byte value is exactly halved with carry-in from the previous byte:
- `$A3` → `$D1`, `$D0` → `$E8`
- `$DEADBEEF` → `$EF56DF77`
- `$55AA` (MBR) → `$2AD5`
- `$FE` (start token) → already shifted in some experiments

### Card-Specific Behavior

| Card | Result |
|------|--------|
| Gigastone ASTC 8GB | 256/256 pass — tolerates glitch |
| Gigastone SD16G 16GB | 236/236 pass — tolerates glitch |
| SanDisk SA16G 16GB | 192/236 — 1-bit shift on writes |
| Lexar MSSD0 64GB | 178/236 — similar pattern |

---

## SD Specification: SPI Bus Idle States

**Source**: Part 1 Physical Layer Simplified Specification v9.10 (2023-12-01)

### What the Spec Says

1. **Data lines idle HIGH** (via pull-up): "The DAT bus line level is high by the pull-up when no data is transmitted" (line 6162). This is stated in SD mode context, but "Bus timing is identical to SD mode" (line 29378) for SPI.

2. **SCK idles LOW** (SPI Mode 0, CPOL=0): Timing diagrams show clock starting at VSS level, data sampled on rising edge. **We comply with this** — P_TRANSITION idles LOW.

3. **CS HIGH between transactions**: "The host starts every bus transaction by asserting the CS signal low" (line 27223). **We comply.**

4. **DO/MISO tri-states when CS HIGH**: Card releases MISO when deselected (line 27718). **We handle this.**

5. **8 clocks required after each bus transaction** before clock shutdown (line 9822).

6. **Byte-aligned on 8-clock boundaries**: "Every command or data token shall be aligned with 8-clock cycle boundary" (line 27221).

### What the Spec Does NOT Say

- **No explicit MOSI idle level requirement** for SPI mode
- **No NCS (clocks between operations) parameter** — Table 7-7 "Timing Values" was REMOVED from the Simplified Specification
- **All SPI timing diagrams removed** (Figures 7-14 through 7-21, all marked "Removed in Simplified Specification")
- **No explicit "SPI Mode 0"** by name — only implied by timing diagram polarity

### Key Implication

The SD spec expects data lines to idle HIGH (pull-up convention). Our P_SYNC_TX smart pin idles HIGH after completing a byte transfer. **This is actually correct behavior for the SPI bus.**

The problem is not the idle-HIGH state itself — it's what happens when we BREAK that state during the transition to the streamer. The pinclear → pinl sequence takes MOSI from HIGH → floating → LOW. If this LOW appears during a clock edge, the card samples it as data.

---

## P2 Hardware Findings (from Chip Designer)

### Smart Pin + Streamer Output Model
- Streamer output and smart pin output are **OR'd** on the physical pin
- With TT=%01 (our configuration), SMART takes priority over OUT when active
- P_SYNC_TX in start-stop mode idles **HIGH** after completing a transfer
- This idle-HIGH OR'd with streamer data = all 1s (experimentally confirmed)

### Smart Pin Configuration Rules
- **WRPIN changes require DIR=0 (reset)** — includes TT bits, mode, input routing
- **WXPIN/WYPIN are safe while running (DIR=1)** — explicitly designed for live updates
- **WXPIN/WYPIN acknowledge (clear IN flag)** as side effect
- Our sp_transfer_8/sp_transfer_32 doing wxpin on active pin = **correct behavior**

### TT Bits (Output Control)
For non-DAC smart pin modes (including P_SYNC_TX):
- TT=%00: Output **disabled** regardless of DIR
- TT=%01: Output **enabled** regardless of DIR (our current setting via P_OE)
- Changing TT requires WRPIN, which requires DIR=0 (reset)
- Therefore TT toggle is NOT a way to avoid reset

---

## Transition Approaches: Tried and Untried

### Current Sequence (for reference)
```
sp_transfer_8($FE)                ← Start token (smart pin)
wypin(0, _mosi)                   ← EXPERIMENT: force shift register to zero
pinclear(_mosi)                   ← Full teardown (WRPIN=0, DIR=0)
pinl(_mosi)                       ← Drive LOW (DIR=1, OUT=0)
  org
    setxfrq xfrq
    rdfast  #0, p_buf
    xinit   stream_mode, #0       ← Streamer starts, NCO ramps from zero
    wypin   clk_count, _sck       ← Clock starts (card begins sampling)
    waitxfi
  end
wrpin(_mosi, spi_tx_mode)         ← Rebuild smart pin
wxpin(_mosi, %1_00111)
pinh(_mosi)
```

---

### Approach 1: pinclear → pinl → streamer (BASELINE)
**Status**: Current production code (minus wypin(0) experiment)
**Result**: 8 pass, 6 fail with wypin(0); similar without
**Problem**: HIGH → float → LOW glitch during transition

### Approach 2: No pinclear (leave smart pin running)
**Status**: TESTED — FAILED
**Result**: 1 pass, 13 fail. All readback = $FE (all 1s)
**Reason**: Smart pin idle-HIGH OR'd with streamer data = all 1s

### Approach 3: DIRL → DIRH (disable/re-enable without clearing mode)
**Status**: TESTED — FAILED
**Result**: 1 pass, 13 fail. All readback = $00
**Reason**: DIRL sets DIR=0, pin can't drive. Streamer writes to output register but DIR=0 means nothing reaches the physical pin.

### Approach 4: wypin(0) before pinclear
**Status**: TESTED — PARTIAL
**Result**: 8 pass, 6 fail. Failures MOVED from sector 4 to sectors 2 and 5.
**Analysis**: wypin(0) loads zero into shift register. But P_SYNC_TX idle-HIGH is a mode property, not a data property. The $FE start token's last bit is already 0, yet the pin idles HIGH. The wypin(0) acknowledges IN (clears flag) which may shift internal timing. Proves pin state matters but doesn't solve the root cause.

### Approach 5: Trailing zero in data (modify sp_transfer_8/sp_transfer_32)
**Status**: ANALYZED — NOT VIABLE
**Reason**: The idle-HIGH is a property of start-stop mode, not the last data bit. The $FE start token already ends with bit 0 on the wire. Yet the pin idles HIGH anyway. Making both routines trail with zero would have no additional effect.

### Approach 6: TT toggle (%01 → %00 → %01)
**Status**: ANALYZED — NOT VIABLE without designer confirmation
**Reason**: Changing TT bits requires WRPIN, which requires DIR=0 (reset). Same reset cycle as pinclear. Additionally, TT=%00 disables output — unclear if streamer can drive independently of TT gate. **Question pending for designer.**

### Approach 7: pinl BEFORE pinclear (reverse order)
**Status**: NOT TESTED
**Idea**: Set OUT=0 while smart pin still running, THEN pinclear.
**Problem**: With TT=%01, SMART overrides OUT. pinl(OUT=0) is invisible while smart pin is active. Pin stays HIGH until pinclear fires. Same glitch.

### Approach 8: pinh after pinclear instead of pinl (keep MOSI HIGH)
**Status**: NOT TESTED ← PROMISING
**Idea**: After pinclear, drive pin HIGH instead of LOW.
```
pinclear(_mosi)        ← WRPIN=0, DIR=0 (floating)
pinh(_mosi)            ← DIR=1, OUT=1 (drive HIGH)
[streamer]
```
**Rationale**: The SD spec expects data lines to idle HIGH. By keeping MOSI HIGH during the gap between smart pin and streamer, we match the expected bus state. The card is waiting for data and sees $FF (idle) until the streamer starts outputting real data. The transition is HIGH→data (aligned with clock) rather than LOW→data (potential glitch).
**Risk**: The streamer's first bit must arrive before or at the first clock rising edge. With phase=0 and the NCO ramp-up, there's a delay before the first bit outputs. During that delay, the pin would be HIGH (from pinh). If the first data bit is 0, the card might sample the HIGH instead. But this matches the CURRENT behavior too (pin was LOW, first bit could be 1) — so it's at least a different failure mode to test.

### Approach 9: Extra clock-less $FF bytes before streamer data
**Status**: NOT TESTED
**Idea**: After the start token, send 1-2 $FF bytes via smart pin (with SCK running) to create a clean "idle HIGH" boundary. Then transition to streamer.
**Problem**: These extra bytes would be counted as data by the card, corrupting the 512-byte block length. The card expects exactly 512 bytes after the start token.

### Approach 10: Include start token in streamer burst
**Status**: NOT TESTED
**Idea**: Build buffer as [$FE, 512 bytes, CRC_hi, CRC_lo]. Stream 515 bytes. Start token is part of streamer data, so no transition mid-data.
**Problem**: Still need the transition BEFORE the start token (after the R1 response polling). Same glitch, just moved earlier. But there's less data at stake — the start token $FE is just one byte, and a 1-bit shift of $FE would be $FF, which the card might just see as idle. Worth thinking about.

### Approach 11: Delay the clock start relative to streamer start
**Status**: VERIFIED FIX — 236/236 regression tests pass on SanDisk Industrial SA16G
**Idea**: Add more separation between XINIT (streamer start) and WYPIN (clock start) so the NCO has more time to ramp and the first data bit is definitely on the pin before the first clock edge.
```pasm
xinit   stream_mode, #0        ' Start streamer
waitx   extra_delay             ' Wait for NCO to output first bits
wypin   clk_count, _sck        ' NOW start clock
waitxfi
```
**Rationale**: If the 1-bit shift is caused by the clock's first rising edge arriving before the streamer's first data bit, adding delay between xinit and wypin gives the NCO time to stabilize. The V2 code may have had naturally different timing here.

### Approach 12: Use phase≠0 for TX streamer
**Status**: PARTIALLY TESTED (was tried as $4000_0000 in V5, reverted to 0)
**History**: V5 used init_phase=$4000_0000 + align_delay=spi_period. This made things worse for some patterns. Reverted to phase=0 per V2. But we only tried one non-zero phase value. Other values might align differently.

### Approach 13: Continuous streamer for entire write transaction
**Status**: NOT TESTED — REQUIRES REDESIGN
**Idea**: Use the streamer for the ENTIRE write path after the R1 response: start token + 512 bytes + CRC. Build a 515-byte hub buffer, stream it all out. Only need smart pin for the command phase and response polling.
**Benefit**: One transition point (after response, before streamer) instead of two (before data AND after data).
**Cost**: Must pre-compute CRC before the streamer burst. Need to manage a 515-byte buffer. The transition still exists but is farther from the critical data.

### Approach 14: WRPIN to zero-mode (no smart pin) instead of pinclear
**Status**: NOT TESTED
**Idea**: `dirl(_mosi)` then `wrpin(_mosi, 0)` then `pinl(_mosi)` — explicitly set mode to none.
**Analysis**: This is functionally identical to pinclear. pinclear IS wrpin(0)+dirl. Same glitch.

### Approach 15: PINFLOAT then DRVL in PASM (tight timing)
**Status**: NOT TESTED
**Idea**: Instead of Spin2 pinclear+pinl (which have Spin2 overhead between them), do the entire transition in a tight PASM block:
```pasm
pinclear _mosi                 ' Mode=0, DIR=0
drvl     _mosi                 ' DIR=1, OUT=0 — IMMEDIATELY after pinclear
setxfrq  xfrq
rdfast   #0, p_buf
xinit    stream_mode, #0
wypin    clk_count, _sck
waitxfi
```
**Rationale**: Minimize the time the pin spends floating (DIR=0) between pinclear and pinl. Currently these are Spin2 calls with method overhead between them. In PASM, pinclear→drvl is 2 clocks apart. The floating/glitch window shrinks from ~microseconds to ~nanoseconds.
**Note**: The Spin2 `pinclear()` compiles to PASM anyway, but putting everything in one org/end block eliminates the Spin2 interpreter overhead between instructions.

---

## The Clock Edge Question

A critical unresolved question: **when does the first SCK rising edge arrive relative to the first streamer data bit?**

Current PASM sequence:
```pasm
xinit   stream_mode, #0       ' Streamer starts, NCO at phase=0
wypin   clk_count, _sck       ' Clock starts ~2 clocks later
```

The streamer NCO must accumulate from 0 to $8000_0000 before outputting the first bit. With xfrq = $4000_0000/spi_period, this takes ~2*spi_period sysclks.

The clock (P_TRANSITION) fires its first transition after one half-period (set by wxpin). That's spi_period sysclks after the wypin.

So the timeline is roughly:
```
T=0:                    xinit (streamer NCO starts at 0)
T=2 clocks:             wypin on SCK (clock transition counter starts)
T=spi_period:           First SCK rising edge (card samples MOSI)
T=2*spi_period:         Streamer outputs first data bit
```

**If this timeline is correct, the first clock edge arrives BEFORE the first data bit.** The card samples whatever was on MOSI (LOW from pinl, or HIGH from pinh) as the first data bit. This is the 1-bit shift.

This makes **Approach 11 (delay clock start)** very promising. If we add `waitx spi_period` between xinit and wypin, the timeline becomes:
```
T=0:                    xinit
T=spi_period:           wypin on SCK
T=2*spi_period:         Streamer outputs first data bit AND first SCK rising edge
```

Now the first data bit and first clock edge arrive at the same time. No phantom bit.

**This also explains why the RX path works**: In readSector, the order is wypin(SCK) THEN waitx THEN xinit. The clock starts first, and the streamer begins sampling after a delay. For receiving, this is correct — you want to sample AFTER the clock edge, not before. For transmitting, you want data ON the pin BEFORE the clock edge. The V5 code that tried to "mirror RX" got this backwards.

---

## Next Steps (COMPLETED)

**Approach 11 was the fix.** `align_delay := spi_period - 2` with `init_phase := #0`.

Remaining items:
1. ~~Designer questions tonight~~ — see Archive/DESIGNER-QUESTIONS-20260216.md (still useful for understanding TT bits)
2. ~~Test Approach 8~~ — not needed, Approach 11 works
3. **Test on additional cards** — verify fix on Gigastone, Lexar, Samsung, etc.
4. **CRC retry recovery** — add 8 NCS clocks between retries (plan Step 2)
5. **Formatter multi-sector upgrade** — switch initFAT() to CMD25 batches (plan Step 3)

---

## Reference: RX vs TX Timing Comparison

### RX (readSector) — WORKS PERFECTLY
```pasm
wypin   clk_count, _sck       ' Start clock FIRST
waitx   align_delay            ' Wait one half-period
xinit   stream_mode, init_phase ' Then start streamer (phase=$4000_0000)
waitxfi
```
Clock runs, data arrives on MISO, streamer samples mid-bit with phase offset. Card is driving MISO in response to our clock.

### TX (writeSector) — HAS BUG
```pasm
xinit   stream_mode, #0       ' Start streamer FIRST
wypin   clk_count, _sck       ' Then start clock
waitxfi
```
Streamer starts outputting to MOSI, clock makes card sample. But if the NCO hasn't output the first bit before the first clock edge, the card samples stale pin state.

**The asymmetry is the clue.** RX gives the clock a head start. TX gives the streamer a head start — but the streamer's NCO ramp-up may be slower than the clock's first transition.

---

## Resolution (2026-02-16)

### The Fix

```pasm
xinit   stream_mode, #0          ' Start streamer; NCO ramps from zero
waitx   align_delay              ' Wait spi_period - 2 instruction cycles
wypin   clk_count, _sck          ' Start clock — first edge aligned with first data bit
waitxfi
```

With `align_delay := spi_period - 2`:
- `init_phase := #0` (not $4000_0000) — NCO ramps naturally from zero
- xinit takes 2 instruction cycles before waitx starts counting
- First data bit appears at T = 2 * spi_period from xinit (NCO rollover)
- First SCK rising edge at T = 2 + align_delay + spi_period = 2 * spi_period
- Perfect alignment: data bit is on MOSI exactly when clock samples it

### Why spi_period - 2 (not spi_period)

Each PASM instruction takes 2 sysclk cycles. After `xinit` executes at T=0, the `waitx` instruction begins at T=2 (not T=0). So the total delay before `wypin` is 2 + align_delay, not just align_delay. Setting `align_delay = spi_period - 2` compensates for the 2 instruction cycles of xinit.

### Verification

All 10 regression test suites: **236/236 tests pass** on SanDisk Industrial SA16G (the timing-sensitive card that exposed the bug).
