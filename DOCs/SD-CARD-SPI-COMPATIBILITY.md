# SD Card SPI Compatibility Guide

This document captures research on microSD card SPI compatibility for embedded systems, specifically for use with the P2 SD Card Driver.

---

## Executive Summary

All microSD generations (microSD, microSDHC, microSDXC, microSDUC) are **required by the SD Physical Layer spec to support SPI mode**, but the quality of SPI implementations varies significantly by vendor and even by model/lot.

For robust SPI use:
- Treat "supports SPI" as a given at the standard level
- Choose conservative card types and specific brands/models with a track record of behaving well in SPI and embedded environments

---

## SD Card Generations and Capacities

The SD Association defines four main card families distinguished by capacity, not bus type:

| Generation | Capacity | Filesystem | Notes |
|------------|----------|------------|-------|
| **microSD (SDSC)** | Up to 2 GB | FAT12/16 | Standard Capacity |
| **microSDHC** | 2-32 GB | FAT32 | High Capacity |
| **microSDXC** | 32 GB - 2 TB | exFAT | Extended Capacity |
| **microSDUC** | 2-128 TB | exFAT | Ultra Capacity (rare) |

### Bus Modes

Cards can implement multiple bus modes:

| Bus Mode | Max Speed | Notes |
|----------|-----------|-------|
| Default / High-speed SD | 25 MB/s | Standard SD bus |
| UHS-I | 104 MB/s | Common on modern cards |
| UHS-II | 312 MB/s | Extra contacts, not on microSD |
| UHS-III / SD Express | Higher | Niche, no SPI benefit |

**Important:** The presence of UHS or newer features does NOT remove SPI support. SPI is an alternate protocol that must still be implemented for a device to carry the SD logo.

---

## Speed Class Markings

Speed logos describe minimum sequential write performance on the SD bus, **not SPI mode performance**:

| Marking | Minimum Write Speed |
|---------|---------------------|
| Speed Class C2, C4, C6, C10 | 2/4/6/10 MB/s |
| UHS Speed Class U1 | 10 MB/s |
| UHS Speed Class U3 | 30 MB/s |
| Video Speed Class V6-V90 | 6-90 MB/s |

### For SPI Use on Microcontrollers

- Any **C10 / U1** card is usually adequate
- The SPI bus itself will be the bottleneck
- Higher UHS/Video classes bring **no real benefit in SPI mode**
- Higher classes can imply more complex controllers and power behavior, which may be **less predictable** in embedded designs

---

## SPI Mode Support and Quirks

The microSD spec explicitly defines SPI as an alternate bus mode. Production cards normally support both SD mode and SPI mode.

### SPI Bus Properties

- Uses 4-wire interface: CS, SCK, MOSI, MISO
- Uses a subset of SD commands
- Some details (CRC behavior, command framing) differ from SD mode
- Bus rates far below SD/UHS maximums
- Typical MCU designs run under 25 MHz, often firmware-limited

### Common SPI-Specific Pitfalls

#### 1. Initialization Differences
- Cards can require **many CMD55+ACMD41 retries** before leaving idle
- Some need **extra dummy clocks** between commands
- Timing-sensitive during power-up sequence

#### 2. CRC Behavior
- CRC is supposed to be off by default in SPI (except CMD0/CMD8)
- **Some cards ship with CRC checking enabled**
- This breaks "bare" drivers that never compute CRC7/CRC16

#### 3. Voltage and Power-Up Timing
- Cards can be sensitive to ramp time and minimum off-times
- Marginal sockets or slow rise can cause "random SPI failures"

#### 4. Partial or Buggy Implementations
- Cheaper cards sometimes have insufficiently tested SPI microcode
- May pass phone/PC tests (SDIO mode) but misbehave under:
  - Long-running SPI workloads
  - Strange power cycles
  - Nonstandard command sequences

**Key insight:** Because SDIO hosts (phones, PCs, cameras) are the primary customer, some vendors pay less attention to SPI corner cases.

---

## Brand/Vendor Reliability for SPI

There is no single authoritative "SPI compatibility list", but trends emerge from endurance testing and embedded-user experience. **Always test a specific model/lot in your board.**

### Tested and Verified for P2 SPI

Based on our own testing with 16 cards across 7 manufacturers:

| Brand | P2 Test Results | Notes |
|-------|----------------|-------|
| **SanDisk** | Excellent | 5 cards tested (Industrial, Extreme, Extreme PRO, Nintendo Switch). 780-866 KB/s throughput. Industrial line recommended for embedded SPI. |
| **Samsung** | Excellent | EVO Select 128GB tested. 783 KB/s throughput. Reliable at 25 MHz. |
| **Lexar** | Excellent | V30 U3 64GB. **Fastest card tested** (1,059 KB/s). |
| **Gigastone** | Excellent | 3 cards tested (Camera Plus 64GB, High Endurance 16GB, 32GB). 368-944 KB/s. Primary test cards. |
| **PNY** | Works, slow | Phison controller. Reliable at 25 MHz SPI but very slow internal throughput (31 KB/s). |
| **Kingston** | Untested | Available in catalog, not yet characterized. Industrial lines recommended. |
| **Transcend** | Untested | Available in catalog, not yet characterized. |
| **Delkin** | Untested | Industrial/embedded series recommended for harsh environments. |

### Mixed or Negative Reports (Community)

| Brand/Type | Issues |
|------------|--------|
| **Silicon Power** | High failure rates in endurance testing. |
| **onn. (Walmart)** | Early sector error thresholds. |
| **Kioxia** (some models) | Variable results. |
| **XrayDisk** | High failure rates reported. |
| **No-name/cheap cards** | Highly variable, SPI often poorly validated. |

**Note:** Our testing focuses on SPI mode reliability with the P2 smart pin driver. Community reports cover broader endurance and data integrity concerns.

---

## Practical Selection Strategy for SPI Designs

For Propeller 2 and other MCU-based SPI hosts:

### Card Type Choices

| Recommendation | Reason |
|----------------|--------|
| **Prefer microSDHC (4-32 GB)** | Widely supported, avoids old SDSC corner cases |
| **Small microSDXC OK** | Well supported in modern drivers |
| **Avoid SD Express / SDUC** | No SPI benefit, adds complexity |

### Brand and Model Strategy

1. **Use major brands** with stable controller lines:
   - SanDisk Ultra/Extreme
   - Kingston Industrial
   - Transcend Industrial
   - Delkin Embedded/Industrial

2. **Standardize on one or two exact model numbers**

3. **Validate under worst-case conditions:**
   - Your actual SPI workload
   - Power cycling scenarios
   - Temperature extremes if applicable

### Driver and Hardware Best Practices

#### Initialization
- Implement full SPI initialization flow:
  - CMD0 (GO_IDLE_STATE)
  - CMD8 (SEND_IF_COND)
  - Repeated CMD55+ACMD41
  - CMD58 (READ_OCR)
  - Proper timeouts
  - Adequate dummy clocks

- Optionally implement CRC7/CRC16 to handle cards with CRC enabled

#### Clock Speed
- Keep SPI clock **modest during init** (100-400 kHz)
- Only raise clock after card leaves idle state
- All tested cards run reliably at 25 MHz SPI (the CSD TRAN_SPEED maximum)
- CMD6 High Speed mode (50 MHz) switch fails on all tested cards

#### Power Design
- Provide clean power-up sequence
- Full power-off between card swaps if applicable
- Adequate decoupling capacitors near card socket

---

## P2 SD Card Driver: Tested Cards

### Verified Working (263+ regression tests passing)

| Card | Manufacturer | Capacity | Throughput | Max SPI |
|------|-------------|----------|------------|---------|
| SanDisk Nintendo Switch 128GB | SanDisk | 128 GB | 780 KB/s | 25 MHz |
| SanDisk Extreme PRO 64GB | SanDisk | 64 GB | 866 KB/s | 25 MHz |
| Lexar V30 U3 64GB | Lexar | 64 GB | 1,059 KB/s | 25 MHz |
| Samsung EVO Select 128GB | Samsung | 128 GB | 783 KB/s | 25 MHz |
| Gigastone Camera Plus 64GB | Gigastone | 64 GB | 944 KB/s | 25 MHz |
| Gigastone High Endurance 16GB | Gigastone | 16 GB | 368 KB/s | 25 MHz |
| SanDisk Industrial 16GB | SanDisk | 16 GB | 824 KB/s | 25 MHz |
| PNY 16GB | PNY (Phison) | 16 GB | 31 KB/s | 25 MHz |

8 additional cards are catalogued but not yet characterized. See [Card Catalog](CARD-CATALOG.md) for full details.

### Notes

- All tested cards operate reliably at 25 MHz SPI
- Cards >32 GB ship as exFAT and must be reformatted as FAT32 (use the included format utility)
- PNY/Phison cards have very slow internal controllers but are fully functional
- CMD6 High Speed mode switch fails on all tested cards (card becomes unresponsive)

---

## References

- SD Physical Layer Simplified Specification
- SD Card endurance testing community reports
- Embedded systems community experience

---

## Document History

| Date | Change |
|------|--------|
| 2026-01-16 | Initial research compilation |
| 2026-02-07 | Updated with actual test data from 15-card catalog, corrected brand assessments |

---

*Part of the [P2-SD-Card-Driver](../README.md) project - Iron Sheep Productions*
