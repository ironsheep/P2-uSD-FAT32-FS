# CMD12 Response Anomaly on Silicon Power Elite 64GB: Final Analysis

> **Updated (2026-03-06):** The CMD12 analysis and CS deassert recovery remain correct. A related but distinct issue was discovered: the driver's R1 response parsing accepts the first non-$FF byte as R1, but the SD spec requires bit 7 = 0 for valid R1. This caused false errors in CMD13 (see **[CMD13-ROOT-CAUSE-ANALYSIS.md](CMD13-ROOT-CAUSE-ANALYSIS.md)**). For CMD12 during multi-block reads, the bit-7 check alone is **not sufficient** because streaming file data can have any bit pattern — CS deassert recovery remains the correct solution.

The definitive analysis of the CMD12 (STOP_TRANSMISSION) framing issue on the Silicon Power Elite 64GB SDXC card, with proven root cause, verified fix, and CMD23 experiment results.

**Date:** 2026-03-06
**Status:** Final — all findings verified on hardware

---

## 1. Summary

Multi-block reads (CMD18) on the Silicon Power Elite 64GB work correctly — all requested sectors arrive with valid CRC-16. The failure is in CMD12 (STOP_TRANSMISSION): the card's SPI output pipeline begins streaming the next sector's data before CMD12 can stop it. This creates a timing race where residual data bytes are read as the CMD12 R1 response, producing an invalid response ($E0, bit 7 set).

The driver handles this with CMD12 tolerance: when all requested sectors are received and CRC-verified, the data is kept and CS deassert recovers the bus. This is the SD specification's defined out-of-band reset mechanism.

CMD23 (SET_BLOCK_COUNT) would eliminate the race entirely, but no card in our 20-card catalog supports CMD23 in SPI mode.

---

## 2. The Proven Root Cause: SPI Full-Duplex Timing Race

### What SPI Full Duplex Means

Every `sp_transfer_8()` call clocks 8 bits simultaneously on both wires:
- **MOSI** (host→card): command bytes we send
- **MISO** (card→host): data the card sends back

You cannot send without receiving, and vice versa. The 7 bytes of CMD12 we send also produce 7 MISO bytes — which the driver was discarding.

### The Pre-Capture Proof

We modified `sendStopTransmission()` to capture the MISO bytes received during CMD12 command transmission. Results from the SP Elite:

```
CMD12 MISO during send: $FF $FF $FE $CC $CC $CC $FF
```

| Byte | MOSI (we sent) | MISO (card sent) | Meaning |
|------|---------------|------------------|---------|
| [0] | `$4C` (CMD12 opcode) | `$FF` | Card idle |
| [1] | `$00` (arg byte 1) | `$FF` | Card idle |
| [2] | `$00` (arg byte 2) | **`$FE`** | **Data token — card queued next sector** |
| [3] | `$00` (arg byte 3) | `$CC` | Sector data byte 0 |
| [4] | `$00` (arg byte 4) | `$CC` | Sector data byte 1 |
| [5] | CRC | `$CC` | Sector data byte 2 |
| [6] | `$FF` (stuff byte) | `$FF` | Card processed CMD12, stopped |

**`$FE` at byte [2] is the data token for the next sector.** The card's read-ahead pipeline queued it just 2 byte-times after the previous sector's CRC. By byte [3], sector data was streaming. CMD12 arrived on the input side and was processed by byte [6], stopping the data stream.

### This Race Is Not SP Elite-Specific

The Lexar 64GB shows the identical pattern:

```
CMD12 MISO during send: $FF $FF $FE $CC $CC $CC $FF
```

The timing race is endemic to modern fast SD cards with aggressive read-ahead pipelines. The difference: the Lexar always processes CMD12 fast enough that its R1=$00 comes through cleanly. The SP Elite sometimes doesn't — its output pipeline occasionally has enough residual data to push R1 out of alignment, producing the $E0 anomaly.

### The Anomalous Response ($E0)

When the race goes badly (observed on SP Elite, intermittent):

```
CMD12 stream (NCR=0): $E0 $1F $FF $FF $FF $FF $FF $FF
```

- `$E0` (`1110_0000`) — bit 7 set, invalid per SD spec. This is residual data from the aborted sector, not a genuine R1 response.
- `$1F` — second residual byte
- NCR=0 (no `$FF` gap before first byte) — abnormal for a genuine R1

When the race goes well (also observed on SP Elite and all other cards):

```
CMD12 stream (NCR=1): $00 $FF $FF $FF $FF $FF $FF $FF
```

- `$00` — genuine R1, success
- NCR=1 — first byte is the response, clean framing

---

## 3. Why In-Band Recovery Is Impossible

SPI has no framing markers. Every byte on MISO is just 8 bits — there is no encoding difference between a data byte and a response byte. The only way to distinguish them is positional knowledge: you know where the R1 should be because you know the protocol sequence.

When residual bytes from the aborted sector sit in the output pipeline ahead of the R1, positional knowledge is lost:

1. **Seven MISO bytes were discarded during CMD12 transmission.** The real R1 might have been among them.
2. **Data bytes and response bytes are indistinguishable.** `$00` (R1 success) looks identical to a sector data byte that happens to be zero.
3. **The pipeline depth is unknown.** Different cards, different runs, different depths.
4. **Scanning forward doesn't help.** We can't distinguish R1=$00 from idle `$FF` that follows, and we can't distinguish residual data from genuine responses.

The only recovery is an **out-of-band signal** — CS deassert.

---

## 4. The Fix: CMD12 Tolerance + CS Deassert Recovery

### How It Works

In `readSectors()`, when `sendStopTransmission()` returns an error:

```
CMD12 fail + all sectors received → recoverToIdle() → keep data (path 5)
CMD12 fail + sectors incomplete   → recoverToIdle() → discard data (path 3)
```

### recoverToIdle()

```spin2
pinh(cs)                    ' CS HIGH — card aborts everything, releases MISO
repeat 10
    sp_transfer_8($FF)      ' 80 clocks — card completes internal state transition
if pinr(miso) == 0          ' Verify card released the bus
    ' Extended recovery: 160 more clocks, check again
```

CS deassert is the SD specification's defined mechanism for aborting SPI operations (Section 7.2.2). When CS goes HIGH:
- The card aborts the current operation
- The card releases MISO (tri-states the pin)
- The card returns to standby state

This works regardless of pipeline state, framing alignment, or residual data. It is 80 clocks and a guaranteed clean state.

### Why This Is Correct, Not a Workaround

The tolerance recognizes that the CMD12 "error" is an artifact of reading residual pipeline data as if it were a command response. The card's actual status is fine — it successfully delivered all requested data with valid CRC-16. CS deassert is the spec-defined out-of-band reset that exists for exactly this situation: when in-band signaling is unreliable.

### Impact on Other Cards

Zero. On 19 of 20 tested cards, `sendStopTransmission()` returns R1=$00 (success). The tolerance code is unreachable:

```
sendStopTransmission() succeeds → takes normal path → tolerance code never reached
```

---

## 5. CMD23 Experiment: Not Available in SPI Mode

### What CMD23 Would Solve

CMD23 (SET_BLOCK_COUNT) tells the card the sector count before CMD18 starts. The card stops after N sectors on its own — no CMD12 needed, no timing race, no residual data. The ball is never thrown because the card knows there are no more balls to throw.

### Experiment Results

Both cards in our catalog that advertise CMD23 support reject it in SPI mode:

| Card | SCR CMD_SUPPORT | CMD23 R1 | Result |
|------|----------------|----------|--------|
| SP Elite 64GB | $03 (CMD23 advertised) | **$04** (Illegal Command) | Rejected |
| Lexar 64GB | $03 (CMD23 advertised) | **$04** (Illegal Command) | Rejected |

The SCR CMD_SUPPORT field applies to the SD 4-bit bus interface, not SPI mode. SPI mode has a reduced command set, and CMD23 is not in it on any card we've tested.

The remaining 18 cards in the catalog report CMD_SUPPORT=$00 or $01 (no CMD23 advertised).

### Driver Approach

The driver probes CMD23 at init time (`probeCmd23()`):
1. Read SCR CMD_SUPPORT — if bit 1 is clear, skip (no CMD23 advertised)
2. If advertised, send CMD23(1) to verify SPI mode support
3. If accepted (R1=$00), set `cmd23_supported := TRUE` and use CMD23+CMD18 for reads
4. If rejected, set `cmd23_supported := FALSE` and use CMD18+CMD12 with tolerance

This is future-proof: if a card ever supports CMD23 in SPI mode, the driver will use it automatically.

---

## 6. Init-Time Capability Probing

The driver probes two capabilities at init that cards may advertise but not implement in SPI mode:

| Probe | What It Detects | Flag | Exposed Via |
|-------|----------------|------|-------------|
| `probeCmd13()` | Broken CMD13 SPI implementation | `CW_CMD13_UNRELIABLE` | `cardWarnings()` |
| `probeCmd23()` | CMD23 rejected in SPI mode | `CW_CMD23_SUPPORTED` | `cardWarnings()` |

Both follow the same pattern: register says X, send the actual command to verify, set a DAT flag. Callers check `cardWarnings()` after mount for the complete picture.

---

## 7. Verified Test Results

### SP Elite — With Fix

- 20/20 regression suites PASS (407+ tests, 0 failures)
- Multi-block reads: count=1, 8, 64 all verified
- CMD12 tolerance triggered on anomalous runs (path=5), data preserved
- All subsequent operations succeed after `recoverToIdle()`

### Standard Cards — No Regression

- 20/20 regression suites PASS on standard test card
- Tolerance code unreachable (CMD12 returns R1=$00)

### Pre-Capture Evidence (Both Cards)

| Card | Pre-Capture Bytes | Timing Race Present |
|------|------------------|-------------------|
| SP Elite 64GB | `$FF $FF $FE $CC $CC $CC $FF` | Yes — `$FE` data token at byte [2] |
| Lexar 64GB | `$FF $FF $FE $CC $CC $CC $FF` | Yes — identical pattern |
| Standard cards | `$FF $FF $FF $FF $FF $FF $FF` | No — pipeline empty during CMD12 |

---

## 8. Card Identification

| Field | Value |
|-------|-------|
| Manufacturer | Silicon Power Computer Communications (SPCC) |
| MID | $9F (Shared OEM) |
| Product Name | "SPCC" |
| Firmware | PRV 0.7 |
| Manufacture Date | July 2025 |
| SD Spec | 6.x (newest in catalog) |
| Capacity | 57 GB (121,532,416 sectors) |
| Speed | 25 MHz SPI max |
| CMD_SUPPORT | $03 (CMD23 advertised, not functional in SPI) |

---

## Related Documents

- **[support/CMD12-SPCE-ANALYSIS-investigation.md](support/CMD12-SPCE-ANALYSIS-investigation.md)** — Original investigation log showing the systematic debugging process (three rounds of instrumentation, two competing theories)
- **[support/CMD12-SPI-FRAMING-DEEP-DIVE.md](support/CMD12-SPI-FRAMING-DEEP-DIVE.md)** — Working document with full Q&A history, engineering tradeoff discussions, and experimental details
- **[CMD13-COMPATIBILITY-ANALYSIS.md](superseded/CMD13-COMPATIBILITY-ANALYSIS.md)** — CMD13 anomaly on AData cards (superseded — see [CMD13-ROOT-CAUSE-ANALYSIS.md](CMD13-ROOT-CAUSE-ANALYSIS.md))
- **[../cards/siliconpower-spcc-64gb.md](../cards/siliconpower-spcc-64gb.md)** — Card data sheet with register dumps and test results

---

*Final analysis — Iron Sheep Productions, 2026-03-06*
