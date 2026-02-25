# SPI Speed Characterization Plan

**Goal:** Determine the maximum reliable SPI clock speed for each SD card class using CRC error detection.

**Date:** 2026-02-02

---

## Executive Summary

This plan describes how to characterize the maximum safe SPI clock speed for SD cards in our catalog. Key points:

| Aspect | Approach |
|--------|----------|
| **Error Detection** | CRC-16 on reads (host verifies), write response tokens (card verifies) |
| **Speed Range** | 18-40 MHz in 10 steps |
| **Iterations** | 1,000-10,000 per speed level |
| **Test Duration** | ~10 minutes per card, ~2 hours for full catalog |
| **Flash Wear** | Random sector selection via P2 XORO32 limits wear to ~1% of card life |
| **Best Test Cards** | MLC "High Endurance" cards (3-10× TLC endurance) |

**Expected Outcomes:**
- PNY (MID $27): Confirm 20 MHz limit
- Budget cards: Confirm 25 MHz spec limit
- Premium cards (SanDisk Extreme, Lexar): May achieve 27-33 MHz

---

## Background

The SD SPI specification defines TRAN_SPEED ($32 = 25 MHz max) for all cards in SPI mode. However:
- Some cards may reliably operate faster than spec
- Some cards (PNY/Phison MID $27) require reduced speed (20 MHz)
- Marketing speed claims (100 MB/s, etc.) apply to native SD mode, not SPI

**Question:** Can we safely run premium cards (SanDisk Extreme, Lexar) faster than 25 MHz?

---

## CRC as Error Detection

### How SD Card CRC Works

| Operation | CRC Type | Who Generates | Who Verifies |
|-----------|----------|---------------|--------------|
| Commands | CRC-7 | Host | Card |
| Read Data | CRC-16 | Card | Host |
| Write Data | CRC-16 | Host | Card |

### Error Detection Strategy

**Reads:**
- Card sends 512-byte data block + 2-byte CRC-16
- V3 driver can compute CRC-16 on received data and compare
- Mismatch indicates transmission error (likely speed-related)

**Writes:**
- Host sends 512-byte data block + 2-byte CRC-16
- Card responds with Data Response Token:
  - `xxx0_0101` = Data accepted
  - `xxx0_1011` = CRC error (card rejected data)
  - `xxx0_1101` = Write error
- We can check this response token to detect CRC failures

**Key Insight:** CRC errors at high speeds indicate the signal integrity limit has been reached. This is a reliable, non-destructive way to find maximum speed.

---

## Testing Methodology

### Approach 1: Speed Ramp Test

```
For each card:
  For each SPI_CLOCK in [20, 22, 24, 25, 27, 30, 33, 36, 40 MHz]:
    Initialize card at this clock speed
    Run N iterations of test pattern
    Record: successes, CRC errors, other errors
    Calculate error rate
```

**Pros:** Systematic, finds exact threshold
**Cons:** Many iterations needed, card re-init at each speed

### Approach 2: Binary Search

```
Start with known-good (20 MHz) and target (40 MHz)
Binary search to find highest error-free speed
Verify with extended test at found speed
```

**Pros:** Faster to find threshold
**Cons:** May miss marginal speeds

### Approach 3: Stress Test at Fixed Speeds

```
Test at: 25 MHz (spec), 30 MHz (+20%), 35 MHz (+40%)
Run 10,000 operations at each speed
Report error rate at each level
```

**Pros:** Simple, practical results
**Cons:** May not find exact limit

**Recommendation:** Start with Approach 3 for initial characterization, then use Approach 1 for detailed analysis of promising cards.

---

## Test Operations

### Single-Sector Tests

| Test | Operation | What It Validates |
|------|-----------|-------------------|
| Read-Verify | Read sector, verify CRC-16 | Card → Host signal integrity |
| Write-Verify | Write sector, check response token | Host → Card signal integrity |
| Write-Read-Compare | Write pattern, read back, compare | Full round-trip integrity |

**Single-sector advantages:**
- Isolates pure SPI transfer speed
- No card controller buffering effects
- Deterministic timing
- Easy to analyze failures

### Multi-Sector Tests

| Test | Operation | What It Validates |
|------|-----------|-------------------|
| Sequential Read | Read N consecutive sectors | Sustained read throughput |
| Sequential Write | Write N consecutive sectors | Sustained write + card busy handling |
| Random Read | Read scattered sectors | Seek + read latency |

**Multi-sector advantages:**
- Reveals sustained performance
- Tests card controller behavior
- More realistic workload
- May expose thermal throttling

### Recommended Test Matrix

| Phase | Sector Count | Iterations | Purpose |
|-------|--------------|------------|---------|
| 1 | 1 sector | 1,000 | Quick sanity check |
| 2 | 1 sector | 10,000 | Statistical error rate |
| 3 | 8 sectors | 1,000 | Short multi-block |
| 4 | 128 sectors (64KB) | 100 | Sustained transfer |
| 5 | 1024 sectors (512KB) | 10 | Extended stress |

---

## Implementation Requirements

### V3 Driver Modifications

1. **Add CRC-16 verification on reads:**
   ```spin2
   PRI verify_read_crc(p_buf, received_crc) : valid
     computed := compute_crc16(p_buf, 512)
     return computed == received_crc
   ```

2. **Add write response token checking:**
   ```spin2
   PRI check_write_response() : status
     token := sp_transfer_8($FF)
     if (token & $1F) == $05
       return WRITE_ACCEPTED
     elseif (token & $1F) == $0B
       return WRITE_CRC_ERROR    ' Card detected our CRC was wrong
     else
       return WRITE_ERROR
   ```

3. **Add configurable SPI clock:**
   ```spin2
   PUB setSPIClock(hz)
     ' Calculate divisor from sysclk
     ' Reinitialize smart pins with new timing
   ```

### Test Utility Structure

```spin2
CON
  ' Test configuration
  TEST_SECTOR_BASE  = 1_000_000   ' Safe area away from FAT
  TEST_SECTOR_RANGE = 10_000      ' Randomize across 10K sectors (wear distribution)
  TEST_PATTERN_SEED = $DEADBEEF

VAR
  long  rand_seed                 ' For XORO32 random sector selection
  byte  write_buf[512]
  byte  read_buf[512]

PUB runSpeedTest(target_hz, iterations) : errors, total | sector, status
  ' Set SPI clock speed
  sd.setSPIClock(target_hz)

  ' Re-initialize card at new speed
  if sd.initCardOnly() <> SUCCESS
    return -1, 0  ' Card won't init at this speed

  ' Initialize random seed (same seed = reproducible sequence)
  rand_seed := TEST_PATTERN_SEED

  ' Run test iterations
  repeat iterations
    total++

    ' Get random sector within test range (distributes wear)
    sector := getRandomTestSector()

    ' Generate test pattern (unique per iteration)
    fillPatternBuffer(@write_buf, TEST_PATTERN_SEED + total)

    ' Write with CRC check
    status := sd.writeSectorRaw(sector, @write_buf)
    if status == WRITE_CRC_ERROR
      errors++
      next

    ' Read with CRC verify
    status := sd.readSectorRaw(sector, @read_buf)
    if status == READ_CRC_ERROR
      errors++
      next

    ' Compare buffers (detect silent corruption)
    if not buffersMatch(@write_buf, @read_buf)
      errors++

PRI getRandomTestSector() : sector
  ' Use P2's XORO32 for fast random sector selection
  org
    xoro32  rand_seed
  end
  sector := TEST_SECTOR_BASE + (rand_seed // TEST_SECTOR_RANGE)
```

---

## Test Sectors: Where to Test

### Option A: Dedicated Test Area (Recommended)

- Use sectors far from filesystem (sector 1,000,000+)
- Pre-verify area is beyond partition end
- Safe from corrupting filesystem

### Option B: Unmounted Raw Access

- Don't mount filesystem
- Use initCardOnly() only
- Full card available for testing

### Option C: Use Existing Test Files

- Create large test file via filesystem
- Get starting sector from FAT
- Test within allocated file space

**Recommendation:** Option B for characterization - simpler, safer, no filesystem dependencies.

---

## Expected Results by Card Class

Based on register analysis and known characteristics:

| Card Class | Expected Max | Reasoning |
|------------|--------------|-----------|
| PNY (MID $27) | 20 MHz | Known problematic, driver already limits |
| Budget OEM | 25 MHz | Spec limit, marginal silicon |
| Kingston/Samsung | 25-27 MHz | Quality silicon, slight headroom |
| SanDisk Extreme | 27-33 MHz | Premium controller, may exceed spec |
| Lexar (CCC=$DB7) | 27-33 MHz | Video-optimized, premium silicon |

**Hypothesis:** Cards with CCC=$DB7 (video classes) likely have better signal integrity margins because sustained video recording requires reliable high-speed transfers.

---

## P2 Hardware Considerations

### SPI Clock Generation

```
SPI_CLK = SYSCLK / (2 * divisor)

At SYSCLK = 200 MHz:
  divisor=4 → 25.0 MHz
  divisor=3 → 33.3 MHz
  divisor=2 → 50.0 MHz (likely too fast)

At SYSCLK = 300 MHz:
  divisor=6 → 25.0 MHz
  divisor=5 → 30.0 MHz
  divisor=4 → 37.5 MHz
```

### Signal Integrity Factors

- Breadboard vs PCB (breadboard adds capacitance/inductance)
- Wire length to SD card socket
- Pull-up resistor values
- Power supply stability
- Ground return path

**Important:** Test results on breadboard may differ from final PCB design. Breadboard typically limits speed more than PCB.

---

## Output Format

### Per-Card Summary

```
Card: SanDisk Extreme 64GB (SanDisk_SN64G_8.6_7E650771_202211)
Test Date: 2026-02-XX
Hardware: P2 Edge @ 200 MHz, breadboard setup

Speed Test Results:
| SPI Clock | Read Errors | Write Errors | Total Ops | Error Rate |
|-----------|-------------|--------------|-----------|------------|
| 20 MHz    | 0           | 0            | 10,000    | 0.000%     |
| 25 MHz    | 0           | 0            | 10,000    | 0.000%     |
| 27 MHz    | 0           | 0            | 10,000    | 0.000%     |
| 30 MHz    | 2           | 5            | 10,000    | 0.070%     |
| 33 MHz    | 47          | 123          | 10,000    | 1.700%     |

Recommended Max Speed: 27 MHz (0% error rate)
Marginal Speed: 30 MHz (0.07% error rate - may be acceptable)
```

### Catalog Integration

Add to Card Catalog summary table:
- **Tested Max SPI** column showing verified maximum speed
- Update Speed Rating based on actual test results vs register-based estimates

---

## Implementation Phases

### Phase 1: Infrastructure
- [ ] Add CRC-16 computation to V3 driver (or verify GETCRC works)
- [ ] Add write response token checking
- [ ] Add configurable SPI clock setter
- [ ] Create basic test utility

### Phase 2: Single-Sector Testing
- [ ] Test all cataloged cards at 20/25/30 MHz
- [ ] Record error rates
- [ ] Identify cards with headroom

### Phase 3: Extended Testing
- [ ] Multi-sector sustained tests on promising cards
- [ ] Binary search for exact speed limits
- [ ] Thermal stress testing (extended operation)

### Phase 4: Documentation
- [ ] Update Card Catalog with tested speeds
- [ ] Recommend safe speeds for each card class
- [ ] Document any cards that can exceed 25 MHz spec

---

## Questions to Answer

1. **Do CCC=$DB7 cards actually perform better at high speeds?**
   - Hypothesis: Yes, video optimization implies better signal margins

2. **Is there correlation between SD spec version and speed headroom?**
   - SD 4.xx vs SD 3.0x cards

3. **Do read and write fail at the same speed, or different?**
   - Expectation: Writes may fail first (card must verify incoming CRC)

4. **How much margin should we leave below the failure point?**
   - Suggestion: Use 90% of error-free max speed for production

5. **Does error rate increase with temperature (extended operation)?**
   - May need thermal testing for reliability

---

## Time Estimates

### Single Operation Timing

| Operation | Data Transfer | Card Busy | Total |
|-----------|---------------|-----------|-------|
| Read 1 sector @ 25 MHz | ~170 µs | ~100 µs | ~0.5 ms |
| Write 1 sector @ 25 MHz | ~170 µs | 2-50 ms | ~5-10 ms |
| Card re-init | - | - | ~500 ms |

**Key insight:** Write busy time (not transfer speed) dominates test duration.

### Test Duration Estimates

**Per speed level (10,000 iterations):**
- Read test: 10,000 × 0.5 ms = **5 seconds**
- Write test: 10,000 × 5 ms = **50 seconds**
- Read+Write combined: **~60 seconds**

**Per card (full characterization):**

| Speed Levels | Iterations | Time per Card |
|--------------|------------|---------------|
| 5 levels (coarse) | 1,000 | ~1-2 minutes |
| 10 levels (fine) | 1,000 | ~3-5 minutes |
| 10 levels | 10,000 | **~10 minutes** |
| 10 levels + verification | 10,000 + 50,000 | ~15 minutes |

**Full catalog characterization (12 cards):**
- Quick pass (1,000 iterations): **~30-45 minutes**
- Full pass (10,000 iterations): **~2 hours**
- With verification: **~3 hours**

### Recommended Speed Range

| Level | Speed | Purpose |
|-------|-------|---------|
| 1 | 18 MHz | Below PNY limit (baseline) |
| 2 | 20 MHz | PNY limit |
| 3 | 22 MHz | Between limits |
| 4 | 24 MHz | Near spec |
| 5 | 25 MHz | **Spec limit** |
| 6 | 27 MHz | Slight overclock |
| 7 | 30 MHz | 20% overclock |
| 8 | 33 MHz | 32% overclock |
| 9 | 36 MHz | Near P2 limit |
| 10 | 40 MHz | Aggressive (may not work) |

### Practical Test Strategy

**Phase 1: Quick Survey (30 min)**
- 5 speeds: 20, 25, 30, 33, 36 MHz
- 1,000 iterations each
- Goal: Find approximate max speed per card

**Phase 2: Fine Resolution (1 hour)**
- Focus on promising cards (those that hit 30+ MHz)
- Test every 2 MHz near the failure point
- 5,000 iterations each
- Goal: Find exact threshold

**Phase 3: Verification (30 min)**
- At determined max speed
- 50,000 iterations
- Goal: Confirm 0% error rate with statistical confidence

---

## Flash Wear Analysis

### Flash Memory Endurance

| Flash Type | P/E Cycles | Typical Cards |
|------------|------------|---------------|
| TLC NAND | 500-3,000 | Most consumer cards |
| MLC NAND | 3,000-10,000 | "High Endurance" cards |
| SLC NAND | 100,000 | Industrial grade |

### Impact of Write Testing

**Critical Issue:** Writing repeatedly to one sector will kill that block.

| Test Scenario | Writes | Sectors Used | P/E per Block | TLC Life Used |
|---------------|--------|--------------|---------------|---------------|
| Bad: One sector | 100,000 | 1 | 100,000 | **DEAD (>100%)** |
| Poor: 100 sectors | 100,000 | 100 | 1,000 | ~50-100% |
| OK: 1,000 sectors | 100,000 | 1,000 | 100 | ~5-10% |
| Good: 10,000 sectors | 100,000 | 10,000 | 10 | **~1%** |

### Wear Mitigation Strategy

**REQUIRED: Distribute test writes across many sectors using randomization**

#### Why Random is Better Than Sequential

Flash memory erases in large blocks (128KB-512KB = 256-1024 sectors). The access pattern affects how wear is distributed:

| Pattern | Erase Blocks Touched | Effect |
|---------|---------------------|--------|
| Sequential (N, N+1, N+2...) | Few (sectors cluster) | Wear concentrated in ~4-10 blocks |
| Random within range | Many (spread out) | Wear distributed across ~40+ blocks |

**Random sector selection is BETTER because:**
1. Touches more physical erase blocks → wear spread wider
2. May trigger card's internal wear leveling more effectively
3. Avoids worst-case alignment with erase block boundaries

#### P2 XORO32 Implementation

The P2's XORO32 instruction provides fast, high-quality randomization:

```spin2
CON
  TEST_SECTOR_BASE  = 1_000_000   ' Safe area away from FAT
  TEST_SECTOR_RANGE = 10_000      ' Randomize across 10,000 sectors

VAR
  long  rand_seed

PRI getRandomTestSector() : sector
  ' Use P2's XORO32 for fast random sector selection
  org
    xoro32  rand_seed
  end
  sector := TEST_SECTOR_BASE + (rand_seed // TEST_SECTOR_RANGE)

PUB initRandom(seed)
  ' Seed with known value for reproducibility during debugging
  rand_seed := seed
```

**Benefits of XORO32:**
- Single instruction (very fast)
- Good statistical distribution across range
- Deterministic when seeded (reproducible for debugging)
- Same seed → same sequence (useful for reproducing failures)

### Acceptable Wear Budget

For dedicated test cards, consuming 1-5% of card life is acceptable:
- 64GB card at ~1% wear = Still has 99% of original endurance
- Test cards are not production cards
- Mark test cards so they're not used for critical data later

### Cards with Higher Endurance

The Gigastone "High Endurance" MLC cards in our catalog are better for testing:
- MLC = 3,000-10,000 P/E cycles (vs 500-3,000 for TLC)
- Specifically designed for continuous recording (dashcams)
- Can handle more write stress

**Recommendation:** Use MLC "High Endurance" cards for extensive write testing, reserve TLC cards for read-focused tests.

---

## Risk Mitigation

- **Data loss:** Test in dedicated sectors, never near filesystem
- **Card damage:** SD cards are designed for voltage tolerance, SPI speed won't damage them
- **Flash wear:** Rotate test sectors across 10,000+ sector range (see wear analysis)
- **False positives:** Run enough iterations for statistical significance (10,000 minimum)
- **Environmental variance:** Note ambient temperature, test setup details

---

---

## Summary of Key Decisions

1. **Use CRC for error detection** - Non-destructive, reliable indication of speed limit
2. **Random sector selection** - P2 XORO32 distributes wear across ~40+ erase blocks
3. **10,000 iterations per speed** - Statistical significance for low error rates
4. **Test range 18-40 MHz** - Covers known limits through aggressive overclock
5. **Use MLC cards for heavy write testing** - Higher endurance protects investment
6. **Unmounted raw access** - No filesystem dependencies during characterization

---

*Plan created: 2026-02-02*
*Status: COMPLETE - Ready for implementation*
