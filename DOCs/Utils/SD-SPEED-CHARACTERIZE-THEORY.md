# SPI Speed Characterize — Theory of Operations

*SD_speed_characterize.spin2*

## Overview

The speed characterization utility determines the maximum reliable SPI clock speed for a specific SD card. It uses a three-phase test methodology with increasing rigor at each of 11 speed levels, reporting the highest speed that passes all phases.

The utility is read-only -- it reads sectors from a safe area of the card but never writes.

## Test Methodology

### Three-Phase Approach

Each speed level is tested through three increasingly demanding phases. If any phase fails, testing stops for that speed and all higher speeds are skipped.

| Phase | Iterations | Type | Purpose |
|-------|-----------|------|---------|
| Phase 1 | 1,000 | Single-sector reads | Quick reliability check |
| Phase 2 | 10,000 | Single-sector reads | Statistical confidence |
| Phase 3 | 100 x 8 | Multi-sector reads (CMD18) | Sustained transfer test |

**Rationale**: Phase 1 catches obvious failures quickly. Phase 2 provides statistical confidence (a 0.01% error rate would show ~1 error in 10,000 reads). Phase 3 tests sustained high-speed transfers using CMD18 multi-block reads, which stress the SPI bus differently than single-sector reads due to continuous clocking without inter-sector pauses.

### Speed Levels

The utility tests 11 speeds from 18 MHz to 50 MHz:

```
18, 20, 22, 25, 27, 30, 33, 36, 40, 45, 50 MHz
```

Testing proceeds from lowest to highest. The first failure stops all further testing, since higher speeds are unlikely to pass if a lower speed fails.

### Error Detection

**CRC-16 verification**: After each single-sector read, the utility compares the received CRC-16 (sent by the card after the data block) against the CRC-16 calculated by the P2 hardware. A mismatch indicates a data transmission error.

**Timeout detection**: If `readSectorRaw()` returns FALSE, it counts as a timeout (card didn't respond or command failed).

**Multi-sector error detection**: For CMD18 reads, `readSectorsRaw()` returns the count of sectors successfully read. Any shortfall is counted as an error.

## Timing Accuracy Analysis

Before running tests, the utility displays a timing accuracy table showing the difference between target and actual achievable SPI frequencies.

The P2 SPI clock is derived from the system clock:
```
half_period = SYSCLK / (2 * target_freq)    (rounded up, minimum 4)
actual_freq = SYSCLK / (2 * half_period)
delta = ((actual - target) / target) * 100%
```

Because `half_period` must be an integer, the actual frequency is always a discrete step function of SYSCLK. The utility reports the delta percentage so users can understand exactly what speed the card is being tested at.

**Example at SYSCLK=200 MHz**:

| Target | Half Period | Actual | Delta |
|--------|------------|--------|-------|
| 18 MHz | 6 | 16.7 MHz | -7.4% |
| 25 MHz | 4 | 25.0 MHz | 0.0% |
| 33 MHz | 4 | 25.0 MHz | -24.2% |
| 50 MHz | 4 | 25.0 MHz | -50.0% |

This shows that at 200 MHz SYSCLK, speeds above 25 MHz all resolve to 25 MHz actual (half_period bottoms out at 4). Higher SYSCLK frequencies enable testing at higher actual SPI speeds.

## Test Sector Selection

Sectors are read from a safe area away from the filesystem structures:

```
TEST_SECTOR_BASE  = 1,000,000    (well past FAT area)
TEST_SECTOR_RANGE = 10,000       (10K sector range)
```

A pseudo-random LFSR (Linear Feedback Shift Register) generates sector offsets:

```spin2
rand_seed := rand_seed << 1
if rand_seed == 0
    rand_seed := $DEADBEEF
if rand_seed & $8000_0000
    rand_seed ^= $04C11DB7     ' CRC-32 polynomial
sector := TEST_SECTOR_BASE + (rand_seed +// TEST_SECTOR_RANGE)
```

Random sector selection ensures the card's internal wear leveling and caching don't artificially improve results by serving the same sector from cache.

## High Speed Mode (CMD6)

For speeds above 25 MHz, the utility checks if the card supports CMD6 (Function Switch) for High Speed mode:

1. Calls `sd.checkCMD6Support()` to query card capability
2. If supported, calls `sd.attemptHighSpeed()` before testing speeds > 25 MHz
3. Reports whether High Speed mode is active

Many cards do not support High Speed mode in SPI mode (even if they support it in SD native mode). The utility handles this gracefully and continues testing at the target speed regardless.

## Output and Recommendations

### Per-Level Output

For each speed level tested:
- Target frequency, actual frequency, half-period, delta percentage
- Phase 1/2/3 results: OK count, CRC error count, timeout count
- Pass/fail determination

### Summary

The final summary lists all tested speeds with pass/fail status and provides a recommended maximum speed -- the highest speed where all three phases passed.

```
RECOMMENDED MAX: 25 MHz
Actual: 25.0 MHz
```

This recommended speed can be used to configure the driver's SPI speed for production use with that specific card model.

## Practical Considerations

- **Run at target SYSCLK**: The P2 SPI clock divider depends on SYSCLK. Test at the same SYSCLK you plan to use in production (the utility defaults to 200 MHz).
- **Card variation**: Different cards from the same manufacturer can have slightly different speed tolerances. Test representative samples.
- **Temperature**: SPI reliability can vary with temperature. Test at expected operating conditions.
- **Conservative margin**: Consider using one speed level below the maximum for production to provide margin.
