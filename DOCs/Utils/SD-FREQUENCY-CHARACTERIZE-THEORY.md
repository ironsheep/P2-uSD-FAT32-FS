# SD Frequency Characterize - Theory of Operations

*SD_frequency_characterize.spin2*

## Overview

This utility sweeps the P2 system clock from 200 MHz to 350 MHz and runs a
write/read/verify test at each frequency. Its job is to answer: at which sysclk
frequencies does the SD driver hold up, and which failures are about the **chip
clock** versus failures about the **SPI clock**?

Unlike SD_speed_characterize (which holds sysclk constant and varies SPI rate),
this utility varies the *system clock* itself - exercising the streamer NCO,
inline PASM timing, smart-pin baud generation, and PLL stability across the
chip's full operating range.

## Why Three Modes Per Frequency

A naive sweep ("change sysclk, run write+read+verify") confounds two distinct
things in one number:

1. **Did the chip's PLL/streamer/timing tolerate this sysclk?**
2. **What did the SPI clock end up at, and could the card keep up?**

The driver's `mount()` computes the SPI smart-pin half-period (`hp`) from the
**sysclk at mount time**:

```
hp = sysclk / (2 * target_spi_freq)    (rounded up, minimum 4)
```

So if the program boots at 200 MHz and mounts there, `hp = 4` (SPI = 25 MHz).
If sysclk later climbs to 290 MHz without remount or `setSPISpeed()`, the SPI
clock physically becomes `290 / (2 * 4) = 36.25 MHz` - well outside the SD
card's 25 MHz spec. Failures past that point are *the SPI overclock*, not
sysclk timing.

To separate these concerns, this utility runs three independent passes (each
with its own boot-anchored mount at 200 MHz). At every target sysclk the test
applies one mode-specific action, then runs `writeSectorsRaw(8) +
readSectorsRaw(8) + verify`.

| Mode | Action at each target sysclk | What it tests |
|------|------------------------------|---------------|
| **C** | Nothing - leave SPI hp from boot mount | "User changes sysclk and forgets to tell the driver." Confirms how badly SPI overclocks when sysclk drifts. |
| **A** | `setSPISpeed(25_000_000)` | Sysclk-isolation: SPI held at 25 MHz so only sysclk varies. Pure question: *does the driver tolerate this sysclk?* |
| **B** | `unmount()` + `mount()` at this sysclk | Full re-init: exercises the 400 kHz card init, CMD0/CMD8/ACMD41 negotiation, high-speed switch, CRC tables, etc. at this sysclk. Mirrors what a program that *boots* at this sysclk would experience. |

### Why Three Separate Passes (Not Three Tests Per Frequency)

An earlier draft ran all three modes back-to-back at each frequency in a single
loop. That broke Mode C's semantics: Mode B's remount at frequency *N* leaves
fresh hp behind, so Mode C at frequency *N+1* would inherit that hp instead of
the boot-mount hp. With 20-MHz steps the SPI overclock was small enough that
Mode C trivially passed - hiding the real failure mode.

The current design runs each mode as its own self-contained pass: each pass
boots at 200 MHz, mounts there once, and sweeps the entire frequency range
without crosstalk from the other modes. Mode C is then truly stale boot-mount
hp. Mode A and Mode B are unaffected because they re-establish state at each
step.

## Why Linear Ascending Order

Earlier versions of the table interleaved frequency points (320, 310, 305,
300, ..., 200) with new entries appended at the end (..., 350, 340, 330). That
made the result table hard to read and made the boundary-detection logic fail
to identify pass-fail transitions cleanly.

Frequencies are now stored ascending 200 -> 350 MHz, with every step the test
wants to characterize:

```
200, 220, 240, 250, 255, 260, 270, 280, 290, 295, 300, 305, 310, 320, 330, 340, 350
```

Boundaries come from the natural transitions in the half-period table (where
`hp = ceil(sysclk / 50_000_000)` flips from one integer to the next): 200->220
crosses hp=4->5, 250->255 crosses 5->6, 300->305 crosses 6->7. The non-uniform
spacing is deliberate - tighter near the boundaries, sparser in the middle.

## Why Boot at 200 MHz

Each pass anchors at 200 MHz boot before sweeping. 200 MHz is:

- The lowest point in our test range, so always achievable.
- A clean integer relationship to 20 MHz crystal (XDIV=1, XMUL=10, post=1,
  VCO=200) - matches what the compiler emits for `_CLKFREQ = 200_000_000`,
  giving us a known-good starting point to compare our hand-coded clkset
  values against.
- A safe SPI ceiling: `hp = 4` -> SPI = 25 MHz, in spec for any modern SD
  card.

If the test booted at the *highest* frequency it intended to test (350 MHz),
a chip that can't run reliably at 350 MHz would never reach the rest of the
sweep.

## CLKMODE Encoding

This was the source of the original "test hangs the chip" bug. The hand-coded
clkset literals used in pre-2026-05 versions were 21 bits and silently dropped
the post-divider field, landing every other field 4 bits out of place. The
first sweep iteration disabled the PLL and froze the chip.

The format, verified against compiler-emitted CLKMODE for `_CLKFREQ =
200_000_000` (which produced `$0100_09FB`):

```
D[31:25] = unused
D[24]    = PLL enable (1)
D[23:18] = XDIV - 1     (PLL input divider, 6 bits, 0..63 -> divider 1..64)
D[17:8]  = XMUL - 1     (VCO multiplier, 10 bits, 0..1023 -> multiplier 1..1024)
D[7:4]   = PPPP         (post divider, see table below)
D[3:2]   = CC           (crystal capacitor config)
D[1:0]   = SS           (clock source)
```

### PPPP Encoding (Post-Divider)

```
%1111 -> /1     %1011 -> /9     %0111 -> /17 (rare)
%0000 -> /2     %1010 -> /10
%0001 -> /4     %1001 -> /11
%0010 -> /6     %1000 -> /12
%0011 -> /8     ...
```

The `%1111` -> /1 case is a special bypass; values 0..14 give post-dividers in
the documented `[2, 4, 6, 8, ..., 30]` table.

### CC and SS Field Values

```
D[3:2] CC: %00 = Hi-Z (oscillator off)
           %01 = no caps, 1MOhm feedback
           %10 = 15pF caps (>= 16 MHz crystals)
           %11 = 30pF caps (< 16 MHz crystals)

D[1:0] SS: %00 = RCFAST       %10 = XI pin (crystal/external)
           %01 = RCSLOW       %11 = PLL output
```

For all entries this utility uses CC=%10 (15pF, 20 MHz crystal) and SS=%11
(PLL).

### Choosing XDIV/XMUL

Each entry chooses XDIV and XMUL so that `VCO = 20 MHz / XDIV * XMUL` equals
the target frequency, with PPPP = /1. This keeps VCO at or below the P2's
~350 MHz absolute max so the PLL stays within spec at every test point.
Examples:

| Target | XDIV | XMUL | VCO    | Post |
|--------|------|------|--------|------|
| 200    | 1    | 10   | 200    | /1   |
| 250    | 2    | 25   | 250    | /1   |
| 305    | 4    | 61   | 305    | /1   |
| 320    | 1    | 16   | 320    | /1   |
| 350    | 2    | 35   | 350    | /1   |

Avoiding "VCO = 2x target with /2 post-divide" (which would put VCO at
600+ MHz for 300+ MHz targets) is what kept the original buggy code from
working even after the field-position bug was identified.

## DEBUG_BAUD Lock

`DEBUG_BAUD = 2_000_000` is set in CON. Without this, Spin2's debug output
rebases its baud divisor against `_CLKFREQ` at compile time; if the baud
calculation drifts when sysclk changes mid-test (because of compiler heuristics
about debug timing), debug output becomes unreadable garbage. Locking the
target baud explicitly tells the runtime to compute the divisor against
current sysclk at every output and keeps the log readable across all 17
frequencies.

## What "PASS" and "FAIL" Mean

Each test does:

1. Fill an 8-sector (4 KB) buffer with a deterministic pattern:
   `byte[i] = (sector_num * 17 + byte_offset) & $FF`
2. `writeSectorsRaw(TEST_SECTOR_BASE, 8, write_buf)`
3. Clear the read buffer.
4. `readSectorsRaw(TEST_SECTOR_BASE, 8, read_buf)`
5. Compare every byte; count mismatches.

A PASS is zero mismatches across all 4 KB. A FAIL is any mismatch. A short
return from `writeSectorsRaw` or `readSectorsRaw` (less than 8 sectors)
also fails, and the first three byte mismatches are dumped for diagnostic
context.

## Boundary Analysis

After the sweep, the utility scans the Mode A result vector for adjacent
entries with different pass/fail status and prints them as transitions:

```
PASS->FAIL boundary: 280-290 MHz   (hp boundary: 6->6)
```

If the half-period changes across the boundary, that's flagged - distinguishing
a "smooth degradation" failure (same hp, just a higher SPI rate) from a
boundary that crosses an hp step.

Mode A is used for boundary analysis because it isolates sysclk effects from
SPI rate effects. Mode C boundaries would just track "SPI overclock
threshold," which is a property of the card, not the driver.

## Relationship to the Regression Suite

The regression suite mounts at 350 MHz and runs there - which is the Mode B
pattern (or, equivalently, "Mode A with the boot mount already at the right
hp"). It passes because every frequency in that scenario gets the correct
SPI hp from the start. This utility's Mode B columns confirm the regression
suite's pattern works across the whole range. The Mode C column documents
what happens if a user *changes* sysclk after mounting without telling the
driver - which is *not* what the regression suite does, and *not* a
regression suite bug.
