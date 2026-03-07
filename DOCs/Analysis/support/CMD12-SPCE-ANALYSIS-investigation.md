# CMD12 Response Anomaly on Silicon Power Elite 64GB: Root Cause Analysis

An investigation of the CMD12 (STOP_TRANSMISSION) response failure observed on the Silicon Power Elite 64GB SDXC card during multi-block reads, and its relationship to the CMD13 anomaly documented in [CMD13-COMPATIBILITY-ANALYSIS.md](../superseded/CMD13-COMPATIBILITY-ANALYSIS.md).

**Date:** 2026-03-05

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Card Identification](#2-card-identification)
3. [Systematic Failure Path Tracing](#3-systematic-failure-path-tracing)
4. [The Raw Byte Stream Evidence](#4-the-raw-byte-stream-evidence)
5. [Root Cause Analysis](#5-root-cause-analysis)
6. [External Research](#6-external-research)
7. [The Fix: CMD12 Tolerance](#7-the-fix-cmd12-tolerance)
8. [Relationship to CMD13 Anomaly](#8-relationship-to-cmd13-anomaly)
9. [Verification](#9-verification)
10. [Impact on Other Cards](#10-impact-on-other-cards)

---

## 1. Problem Statement

The Silicon Power Elite 64GB SDXC card passes 19 of 20 regression test suites but fails all multi-block read tests. The card mounts successfully, single-sector reads and writes work perfectly (11,000+ consecutive CMD17 reads with 0 CRC errors), and multi-block writes (CMD25) succeed. Only multi-block reads (CMD18) fail — and they fail 100% of the time, even with count=1.

The previous characterization (2026-02-17) noted that CMD18 "times out waiting for data token ($FE)" during mount warmup reads. After removing the warmup code, mount succeeds but `readSectorsRaw()` still returns 0 sectors for every CMD18 attempt.

---

## 2. Card Identification

| Register | Field | Value | Significance |
|----------|-------|-------|-------------|
| **CID** | MID | $9F | Shared OEM (not assigned to a specific manufacturer) |
| | OID | "TI" | Contract manufacturer |
| | PNM | "SPCC" | Silicon Power Computer Communications |
| | PRV | 0.7 | Recent firmware (not early/buggy revision) |
| | MDT | 2025-07 | Less than 1 year old |
| **CSD** | TRAN_SPEED | $32 | 25 MHz SPI maximum |
| | CCC | $DB5 | **Class 2 present** — CMD18 advertised as supported |
| **SCR** | SD_SPEC | 6.x | SD_SPEC4=1, SD_SPECX=2 — newest spec version in our catalog |
| | CMD_SUPPORT | $03 | **CMD23 (SET_BLOCK_COUNT) supported** |

### Key Contrast with CMD13 Card

| Property | AData (CMD13 issue) | SP Elite (CMD12 issue) |
|----------|---------------------|------------------------|
| Age | 2013 (13 years old) | 2025 (< 1 year old) |
| PRV | 0.2 (earliest firmware) | 0.7 (recent firmware) |
| SD Spec | 3.0 | 6.x (newest) |
| MID | $1D (budget OEM) | $9F (shared OEM) |
| CMD13 probe | FAILS (garbled R2) | PASSES (clean $00/$00) |

The CMD13 card is old with immature firmware. The SP Elite is new with current firmware. These are different failure classes.

---

## 3. Systematic Failure Path Tracing

### Methodology

The driver's `readSectors()` function has four failure paths. Rather than speculate, we instrumented the driver with diagnostic DAT variables and PUB getters (gated by `#IFDEF SD_INCLUDE_DEBUG`) to capture exactly which path was taken on every call.

### Instrumentation Added

| DAT Variable | Type | Purpose |
|-------------|------|---------|
| `last_cmd18_r1` | BYTE | R1 response from CMD18 command |
| `last_cmd18_token` | BYTE | Data token from waitDataToken() |
| `last_cmd18_result` | BYTE | waitDataToken outcome: 0=ok, 1=timeout, 2=error |
| `last_cmd18_fail` | BYTE | Failure path: 0=none, 1=R1, 2=token, 3=CMD12, 4=CMD13, 5=CMD12 tolerated |
| `last_cmd18_sread` | BYTE | Sectors actually read before CMD12/CMD13 |
| `last_cmd12_r1` | BYTE | R1 from CMD12 (sendStopTransmission) |
| `last_cmd12_busy` | BYTE | CMD12 outcome: 0=ok, 1=R1 timeout, 2=R1 error, 3=busy timeout |
| `cmd12_capture` | BYTE[16] | Raw byte stream after CMD12 stuff byte |
| `cmd12_capture_len` | BYTE | NCR gap length (position of first non-$FF byte) |

### Results: Three Rounds of Instrumented Testing

**Round 1 — R1 response check:**

| Test | CMD18 R1 |
|------|----------|
| Test 1 (8 sectors) | **$00** (accepted) |
| Test 3 (8 sectors) | **$00** (accepted) |
| Test 4a (1 sector) | **$00** (accepted) |
| Test 5 (64 sectors) | **$00** (accepted) |

**Finding:** CMD18 is accepted by the card. R1=$00 on every attempt.

**Round 2 — Data token and failure path:**

| Test | Token | Path | sread |
|------|-------|------|-------|
| Test 1 (8 sectors) | **$FE** | 3 | 0 |
| Test 3 (8 sectors) | **$FE** | 3 | 0 |
| Test 4a (1 sector) | **$FE** | 3 | 0 |
| Test 5 (64 sectors) | **$FE** | 3 | 0 |

**Finding:** The $FE data start token IS received. Data transfer proceeds. Failure is Path 3: `sendStopTransmission()` (CMD12). `sread=0` was misleading — this was captured AFTER the CMD12 failure zeroed the count.

**Round 3 — CMD12 details and sector count before zeroing:**

| Test | sread (actual) | CMD12 R1 | CMD12 result |
|------|---------------|----------|-------------|
| Test 1 (8 sectors) | **8** | **$E0** | 2 (R1 error) |
| Test 3 (8 sectors) | **8** | **$E0** | 2 (R1 error) |
| Test 4a (1 sector) | **1** | **$E0** | 2 (R1 error) |
| Test 5 (64 sectors) | **64** | **$E0** | 2 (R1 error) |

**Critical finding:** ALL requested sectors are read successfully. The data transfer is 100% complete. CMD12's R1 response has bit 7 set ($E0 = `1110_0000`), which is invalid per the SD specification.

---

## 4. The Raw Byte Stream Evidence

After identifying CMD12 as the failure point, we added a 16-byte capture buffer to record every byte received after the CMD12 stuff byte. This answers the question the external analyst asked: "how many $FF bytes you see before it on the wire?"

### Capture from Test 1 (8-sector read):

```
CMD12 stream (NCR=1): $E0 $1F $FF $FF $FF $FF $FF $FF
                       $FF $FF $FF $FF $FF $FF $FF $FF
```

### Analysis

| Byte | Value | Interpretation |
|------|-------|---------------|
| [0] | **$E0** | First byte after stuff byte — treated as R1. **NCR=1** (no $FF gap) |
| [1] | **$1F** | Non-$FF byte immediately after alleged R1 |
| [2-15] | $FF | Bus idle |

### What This Tells Us

**NCR=1 is abnormal.** The SD specification defines NCR (command-to-response delay) as 0 to 8 bytes of $FF padding before the card sends its R1. On all 19 other tested cards, CMD12 shows several $FF bytes before R1=$00. Getting a non-$FF byte on the very first clock after the stuff byte means either:

1. The card responded instantaneously with an invalid R1, OR
2. The byte $E0 is **residual data** from the multi-block read stream, not an actual R1 response

**$E0 followed by $1F is suspicious.** These two bytes together form the 16-bit value $E01F. In a multi-block read, the card streams: `$FE` (data token) + 512 bytes (sector data) + 2 bytes (CRC-16). After reading the last sector's CRC, if the card was already preparing the next data token, the next bytes on the bus could be residual from this preparation.

$E0 = `1110_0000` — bit 7 is set, making this an invalid R1 per spec. Valid R1 always has bit 7 = 0.

**The byte stream pattern is consistent with a framing/alignment issue** where CMD12 was sent while the card's output pipeline still had uncleared data, and `waitR1Response()` grabbed the first non-$FF byte as R1 without any NCR gap.

---

## 5. Root Cause Analysis

### Confirmed Facts

1. CMD18 is accepted (R1=$00)
2. All requested data tokens ($FE) arrive correctly
3. All sector data is received via streamer DMA
4. CRC-16 validation passes on all sectors
5. The sector count matches the request (8/8, 1/1, 64/64)
6. CMD12's response has bit 7 set ($E0) — invalid per spec
7. NCR gap is zero — no $FF padding before the alleged R1
8. CMD25 (multi-block write) works perfectly — it uses $FD stop token, NOT CMD12

### Two Competing Theories

**Theory A: Card Firmware Bug**
The SP Elite card has a broken CMD12 SPI-mode response. It returns $E0 instead of $00. This would be the same class of issue as the AData CMD13 bug — correct data operations with broken status reporting.

**Theory B: Response Framing Misalignment**
The card's SPI output pipeline still contains residual bytes from the multi-block data stream when CMD12 arrives. The `waitR1Response()` function grabs the first non-$FF byte, which happens to be leftover data ($E0) rather than the actual CMD12 R1 response.

### Evidence Favoring Theory B

- **NCR=1**: No $FF padding before $E0, which is abnormal for a genuine R1 response
- **$1F follows $E0**: A second non-$FF byte immediately after suggests multiple residual bytes on the bus, not a clean R1+busy sequence
- **CMD13 passes on this card**: The card's SPI command processing works for other commands (CMD13 probe returns clean $00/$00). Only CMD12 — sent mid-stream during an active data transfer — fails
- **This is a fast, modern card**: SD 6.x with U3/V30 rating. Its internal pipeline may output data faster than CMD12 can interrupt

### Evidence Favoring Theory A

- **Consistent across all test sizes**: $E0 appears for count=1, 8, and 64. If it were alignment-dependent, we might expect variation
- **Other budget OEM cards**: MID $9F (shared OEM) controllers have shown various SPI-mode quirks

### Verdict

Both theories lead to the same practical conclusion: **the data is valid and should not be discarded.** The distinction matters for understanding, but the fix is identical. Logic analyzer capture could resolve which theory is correct by showing the exact bit-level framing around CMD12.

---

## 6. External Research

An external analysis (see `DOCs/User-Reports/rpt6-cmd12-external-analysis.txt`) confirmed:

1. **Bit 7 set in CMD12 R1 is not supposed to happen per spec** — reserved bit, must be 0
2. **Historical precedent**: "Some host drivers get no response or timeouts for CMD12 even though the card continues working fine"
3. **Most likely causes**: Byte alignment issues where the host reads a data byte or status byte as R1, extra clocks from DMA shifting the framing, or one-byte-off latching
4. **Recommended diagnostic**: "Capture the raw bit stream around CMD12 on your logic analyzer and compare against the spec's 48-bit command and response framing" — consistent with our byte stream capture approach

---

## 7. The Fix: CMD12 Tolerance

### Implementation

In `readSectors()`, when `sendStopTransmission()` returns an error but all requested sectors were received:

```
Before (all cards):
  CMD12 fail → recoverToIdle() → sectors_read := 0 → data discarded

After:
  CMD12 fail + sectors_read == count → recoverToIdle() → keep data (path 5)
  CMD12 fail + sectors_read < count  → recoverToIdle() → discard data (path 3)
```

The tolerance is conservative:
- Only applies when **every requested sector** was received
- `recoverToIdle()` is still called to reset the bus (CS HIGH + 80 clocks)
- Diagnostic variables capture the anomaly for inspection
- Incomplete reads are still discarded (path 3)

### Why recoverToIdle() Is Sufficient

`recoverToIdle()` deasserts CS and clocks 80 dummy cycles. Per the SD specification, CS HIGH aborts any pending SPI operation and the dummy clocks allow the card to release MISO. After this sequence, the next command starts with a clean bus state. This is proven by the fact that subsequent operations (including CMD25 writes and CMD17 reads) work correctly after the recovery.

---

## 8. Relationship to CMD13 Anomaly

### Similarities

| Property | CMD13 (AData) | CMD12 (SP Elite) |
|----------|---------------|------------------|
| Invalid R1 (bit 7 set) | $C1 (`1100_0001`) | $E0 (`1110_0000`) |
| Data operations work | Yes | Yes |
| CRC integrity verified | Yes | Yes |
| Fix: tolerate and recover | Yes (probeCmd13 + skip) | Yes (keep data if complete) |

### Differences

| Property | CMD13 (AData) | CMD12 (SP Elite) |
|----------|---------------|------------------|
| Card age | 13 years (2013) | < 1 year (2025) |
| Firmware maturity | PRV 0.2 (early) | PRV 0.7 (recent) |
| Bus state at command | Idle (CS cycled before CMD13) | Active data transfer (CS asserted) |
| NCR gap | Not captured | **0 $FF bytes** (abnormal) |
| Failure consistency | 100% of CMD13 calls | 100% of CMD12 after CMD18 |
| Second byte | $3F (also invalid) | $1F (also non-$FF) |

### Are They Related?

**No — these are different failure mechanisms.**

The CMD13 failure on the AData card is a **card firmware bug**. CMD13 is sent after CS cycling (clean bus state), and the card's response ($C1/$3F) is consistent garbage on every call. The `probeCmd13()` function detects this at init and marks the card as CMD13-unreliable. This is a known class of issue with old budget SPI controllers.

The CMD12 failure on the SP Elite is most likely a **response framing issue**. CMD12 is sent while the card is still in data-output mode during a multi-block read. The zero NCR gap and the two-byte non-$FF sequence ($E0 $1F) suggest the host is reading residual data from the output pipeline rather than a genuine R1 response. The SP Elite's CMD13 works perfectly (probe passes), confirming its SPI command processing is functional for commands sent in idle state.

The common thread is that **both produce invalid R1 responses (bit 7 set)**, but for different reasons:
- AData: Card firmware doesn't implement CMD13 correctly in SPI mode
- SP Elite: CMD12's R1 is lost in or obscured by the data stream framing

### Could CMD13's AData Failure Also Be Framing?

Unlikely. `checkCardStatus()` deasserts CS, sends two $FF clocks for recovery, then reasserts CS before sending CMD13. This CS cycling creates a clean break in the SPI state machine — there is no active data stream to create residual bytes. The AData card's CMD13 failure occurs even on an idle card at init time (`probeCmd13()` runs after `initCard()`), confirming it is not a framing issue.

---

## 9. Verification

### SP Elite — Before Fix

- 19/20 regression suites: **PASS** (407 tests, 0 failures)
- multiblock suite: **FAIL** (2 pass, 4 fail)

### SP Elite — After Fix

- 20/20 regression suites: **PASS** (all tests pass including multiblock 6/6)
- Total: 407+ tests, 0 failures
- CMD12 tolerance triggered on every multi-block read (path=5)
- All data integrity verified via CRC-16 and byte-by-byte comparison

### Standard Card — Regression Verification

Pending: Full 20-suite regression on standard card to confirm no behavioral change. The tolerance code is unreachable on cards where CMD12 returns R1=$00.

---

## 10. Impact on Other Cards

The tolerance has **zero impact** on cards with working CMD12 implementations. The code path is:

```
sendStopTransmission() succeeds (R1=$00)
  → takes 'else' branch → pinh(cs) → checkCardStatus()
  → tolerance code is never reached
```

On 19 of 20 tested cards, `sendStopTransmission()` returns 0 (success). The tolerance code at path 5 is only reached when:
1. CMD12 returns a non-zero R1 (error), AND
2. All requested sectors were received before CMD12

This combination has only been observed on the SP Elite card.

---

*Analysis by Iron Sheep Productions. See also: [CMD13-COMPATIBILITY-ANALYSIS.md](../superseded/CMD13-COMPATIBILITY-ANALYSIS.md) for the CMD13 anomaly on AData cards (superseded).*
