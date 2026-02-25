# Sprint Plan: High-Speed SPI Mode & Card Configuration

## Overview

This driver is **SPI Mode only**. We target both Default Speed (25 MHz) and High Speed (50 MHz) operation, with the driver self-configuring based on card capabilities.

### Performance Targets

| Mode | Clock | Theoretical Throughput |
|------|-------|------------------------|
| Default Speed (DS) | 25 MHz | 3.125 MB/s |
| High Speed (HS) | 50 MHz | 6.25 MB/s |

### Constraints

- **SPI Mode**: Single data line (MISO), no 4-bit parallel
- **3.3V Signaling**: No UHS-I modes (require 1.8V)
- **4 Pins**: CS, MOSI, MISO, SCK on pins 58-61

---

## Phase 1: Card Configuration Import

### Goal
Read all relevant card registers at mount time and use them to configure driver behavior.

### Registers to Read

#### 1.1 OCR (Operating Conditions Register) - 32 bits
**Command**: CMD58 (READ_OCR)
**Status**: Already implemented

| Field | Bits | Use |
|-------|------|-----|
| CCS | [30] | Card Capacity Status (SDSC vs SDHC/SDXC) |
| Busy | [31] | Power-up complete |

#### 1.2 CSD (Card Specific Data) - 128 bits
**Command**: CMD9 (SEND_CSD)
**Status**: Partially implemented (capacity only)

| Field | Bits | Use |
|-------|------|-----|
| CSD_STRUCTURE | [127:126] | Version (0=v1.0, 1=v2.0) |
| TAAC | [119:112] | Async access time (SDSC only) |
| NSAC | [111:104] | Sync access time in clocks (SDSC only) |
| **TRAN_SPEED** | [103:96] | **Max transfer rate - KEY FIELD** |
| CCC | [95:84] | Command class support |
| READ_BL_LEN | [83:80] | Max read block length |
| R2W_FACTOR | [28:26] | Write time multiplier |
| WRITE_BL_LEN | [25:22] | Max write block length |

**TRAN_SPEED Decoding**:
- `0x32` = 25 MHz (Default Speed - all cards)
- `0x5A` = 50 MHz (High Speed capable)

#### 1.3 SCR (SD Configuration Register) - 64 bits
**Command**: ACMD51 (SEND_SCR)
**Status**: Not implemented

| Field | Bits | Use |
|-------|------|-----|
| SD_SPEC | [59:56] | Physical layer version |
| SD_SPEC3 | [47] | Version 3.0+ support |
| SD_BUS_WIDTHS | [51:48] | Bus width support (info only) |
| CMD_SUPPORT | [33:32] | CMD20, CMD23 support |

#### 1.4 CID (Card Identification) - 128 bits
**Command**: CMD10 (SEND_CID)
**Status**: Not implemented

| Field | Bits | Use |
|-------|------|-----|
| MID | [127:120] | Manufacturer ID |
| OID | [119:104] | OEM/Application ID |
| PNM | [103:64] | Product Name (5 chars) |
| PRV | [63:56] | Product Revision |
| PSN | [55:24] | Serial Number |
| MDT | [19:8] | Manufacturing Date |

*CID is for logging/debugging, not timing configuration.*

### Driver Configuration from Card Data

```
At mount time:
1. Read OCR → Determine SDSC vs SDHC/SDXC
2. Read CSD → Extract TRAN_SPEED, timing parameters
3. Read SCR → Check feature support
4. Configure driver:
   - Set appropriate timeouts based on card type
   - Store max supported clock rate
   - Enable/disable features based on CMD_SUPPORT
```

### Timeout Configuration

| Card Type | Read Timeout | Write Timeout | Source |
|-----------|--------------|---------------|--------|
| SDSC | Calculate from TAAC+NSAC | Read × R2W_FACTOR | CSD fields |
| SDHC/SDXC | 100 ms (fixed) | 250 ms (fixed) | Spec mandate |

---

## Phase 2: High Speed Mode Implementation

### Goal
Implement CMD6 (SWITCH_FUNC) to enable 50 MHz High Speed mode.

### 2.1 Query High Speed Support

CMD6 with Mode=0 (Check Function):
```
Argument: 0x00FFFFF1
  - Access Mode: Check (don't switch)
  - Function Group 1: High Speed (function 1)
```

Response: 512-bit status structure containing:
- Function group support bits
- Function switching status
- Busy status

### 2.2 Switch to High Speed Mode

CMD6 with Mode=1 (Switch Function):
```
Argument: 0x80FFFFF1
  - Access Mode: Switch
  - Function Group 1: High Speed (function 1)
```

After successful switch:
- Card operates at up to 50 MHz
- TRAN_SPEED in CSD reports 0x5A
- Driver adjusts `bit_delay` for higher clock

### 2.3 Clock Timing Adjustment

Current driver uses `bit_delay` for SPI timing:
```spin2
bit_delay := 3_200   ' ~50 kHz during init
bit_delay := 2       ' Fast mode after init (~25 MHz?)
```

For 50 MHz operation:
```spin2
bit_delay := 1       ' Minimum delay for ~50 MHz
```

Need to verify actual achieved clock rates with logic analyzer.

### 2.4 High Speed Mode Verification

Test procedure:
1. Mount card
2. Read TRAN_SPEED from CSD
3. Send CMD6 to query HS support
4. If supported, switch to HS mode
5. Verify with test read/write operations
6. Measure actual throughput

---

## Phase 3: Certification & Testing

### 3.1 Card Compatibility Matrix

Test with variety of cards:
- [ ] SanDisk Ultra (SDHC)
- [ ] SanDisk Extreme (SDHC)
- [ ] Samsung EVO (SDHC/SDXC)
- [ ] Kingston Canvas (SDHC)
- [ ] Generic/budget cards
- [ ] Older SDSC cards (if available)

For each card, record:
- Manufacturer (from CID)
- TRAN_SPEED value
- High Speed support (CMD6 query)
- Successful HS switch
- Achieved throughput at 25 MHz
- Achieved throughput at 50 MHz

### 3.2 Throughput Measurement

Create benchmark test:
```
1. Sequential read: 1 MB in 512-byte blocks
2. Sequential write: 1 MB in 512-byte blocks
3. Calculate bytes/second
4. Compare to theoretical max
```

### 3.3 Reliability Testing

For each speed mode:
- Read/write pattern tests
- Large file transfers
- Stress testing (repeated mount/unmount)
- Error rate monitoring

---

## Implementation Tasks

### Phase 1 Tasks
- [ ] Add `readSCR()` function using ACMD51
- [ ] Add `readCID()` function using CMD10
- [ ] Extend `readCSD()` to extract all timing fields
- [ ] Create card info structure to hold configuration
- [ ] Implement timeout calculation for SDSC cards
- [ ] Add card info logging at mount time

### Phase 2 Tasks
- [ ] Implement CMD6 command support
- [ ] Add `queryHighSpeed()` function
- [ ] Add `switchHighSpeed()` function
- [ ] Add clock rate adjustment mechanism
- [ ] Verify timing with logic analyzer
- [ ] Update `bit_delay` calculation for 50 MHz

### Phase 3 Tasks
- [ ] Create throughput benchmark test
- [ ] Test multiple card brands
- [ ] Document card compatibility matrix
- [ ] Measure actual clock rates achieved
- [ ] Document any cards that fail at 50 MHz

---

## Success Criteria

1. **Card Configuration**: Driver reads and logs CSD, SCR, CID at mount
2. **Self-Configuring**: Driver sets timeouts based on card type
3. **High Speed Query**: Can detect if card supports 50 MHz
4. **High Speed Switch**: Successfully switch to 50 MHz on capable cards
5. **Measured Throughput**: Document actual MB/s achieved
6. **Compatibility**: Works with 90%+ of tested cards

---

## References

- SD Physical Layer Simplified Specification v9.10
- Part1_chunks/chunk_an: SPI Mode (Chapter 7)
- Part1_chunks/chunk_ae: CMD6 Switch Function
- Part1_chunks/chunk_al: CSD Register fields
- Part1_chunks/chunk_am: SCR Register fields
