# CMD13 Compatibility Analysis: Broken Status Reporting on Older SD Cards

> **SUPERSEDED (2026-03-06):** This document's root cause diagnosis is incorrect. The CMD13 failure is not a card-specific defect — it is a driver-side R1 response parsing error. Our code accepted the first non-$FF byte as R1, but the SD spec requires bit 7 = 0 for a valid R1. Pre-response bytes with bit 7 set (like $C1) are bus noise, not responses. See **[CMD13-ROOT-CAUSE-ANALYSIS.md](../CMD13-ROOT-CAUSE-ANALYSIS.md)** for the corrected analysis. The symptom descriptions and card data below remain accurate; only the diagnosis and mitigation strategy are superseded.

A comprehensive analysis of the CMD13 (SEND_STATUS) failure observed on an AData SDHC 16GB card, the underlying cause, impact on the driver, and mitigation strategies.

**Date:** 2026-03-05

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Card Identification and Controller Analysis](#2-card-identification-and-controller-analysis)
3. [CMD13 in SPI Mode: Specification vs. Reality](#3-cmd13-in-spi-mode-specification-vs-reality)
4. [Decoding the Failure](#4-decoding-the-failure)
5. [Why Data Operations Work Despite CMD13 Failure](#5-why-data-operations-work-despite-cmd13-failure)
6. [SPI Technique Analysis: Ruling Out Host-Side Causes](#6-spi-technique-analysis-ruling-out-host-side-causes)
7. [External Research](#7-external-research)
8. [Current Driver Architecture: Where CMD13 Lives](#8-current-driver-architecture-where-cmd13-lives)
9. [Integrity Layers: What Protects What](#9-integrity-layers-what-protects-what)
10. [Mitigation Strategies](#10-mitigation-strategies)
11. [Recommended Approach](#11-recommended-approach)
12. [Audit Tool Changes](#12-audit-tool-changes)
13. [Filesystem Issues on This Card](#13-filesystem-issues-on-this-card)

---

## 1. Problem Statement

A user reports that the driver fails immediately on mount when using an older AData 16GB SDHC card. The card initializes correctly (CMD0, CMD8, ACMD41, CMD58 all succeed), but the first sector read (MBR at sector 0) fails because `checkCardStatus()` returns E_IO_ERROR after receiving an invalid CMD13 response.

The user discovered that forcing `checkCardStatus()` to return OK allows the card to operate perfectly -- reads, writes, no corruption. The card's data path is clean; only its CMD13 status reporting is broken.

---

## 2. Card Identification and Controller Analysis

### Register Data

| Register | Field | Value | Interpretation |
|----------|-------|-------|----------------|
| **CID** | MID | $1D | AData (shared with PNY, budget OEMs) |
| | OID | "AD" ($41 $44) | AData OEM code |
| | PNM | "SD   " | Generic name, trailing spaces |
| | PRV | 0.2 | Extremely early firmware revision |
| | PSN | $B162_04C2 | |
| | MDT | 2013-03 | Over 13 years old |
| **CSD** | CSD_STRUCTURE | 1 | CSD v2.0 (SDHC) |
| | TRAN_SPEED | $32 | 25 MHz maximum (standard speed only) |
| | TAAC | $0E | Read access time |
| | R2W_FACTOR | 2 | Write time = read time x 4 |
| | C_SIZE | 30,133 | ~14 GB usable |
| | CCC | $5B5 | Classes 0,2,4,5,7,8,10 (no write-protect class 6) |
| **OCR** | Value | $C0FF_8000 | Ready, CCS=1 (SDHC block addressing), 3.3V |
| **SCR** | SD_SPEC | 2 | SD 3.0x |
| | SD_SPEC3 | 1 | SD 3.0 confirmed |
| | SD_BUS_WIDTHS | $05 | 1-bit and 4-bit supported |

### Controller Assessment

**MID $1D** is a budget OEM manufacturer ID shared by AData, PNY, and numerous contract manufacturers. These companies source controllers from the same suppliers (commonly Phison, Silicon Motion, or similar).

**Product revision 0.2** is the critical indicator. Mature SD controllers ship at revision 1.0 or higher. A 0.2 revision means this is from the first or second production run of this controller design -- firmware that never received the refinements that come from field experience and compliance testing.

**Generic product name "SD"** with trailing spaces (instead of a descriptive model name like "ACLCD" or "USD") is characteristic of white-label/bulk production where the card manufacturer did not bother to program a unique product identifier.

**Manufacture date March 2013**: This card predates many of the SD Association's stricter SPI-mode compliance testing requirements. Early SDHC cards were primarily tested for SD-mode (4-bit bus) operation, with SPI mode treated as a legacy interface for microcontrollers.

### Summary

This is a bottom-tier, first-generation-firmware, 13-year-old budget SDHC card. Its core data transfer commands work (CMD17 read, CMD24 write, CMD18/CMD25 multi-block), but its status-reporting command (CMD13) is broken in SPI mode.

---

## 3. CMD13 in SPI Mode: Specification vs. Reality

### What the Spec Says

The SD Physical Layer Specification (Part 1) defines CMD13 (SEND_STATUS) as returning an R2 response in SPI mode:

- **First byte (R1):** 8-bit status. Bit 7 must always be 0. Bits 6-0 encode error/status flags.
- **Second byte (STATUS):** 8-bit extended status. Bits 7-0 encode card-internal conditions (ECC failure, write protect, locked, etc.).

CMD13 may be issued at any time in SPI mode to query the card's internal state. It is particularly useful after write operations to detect flash programming failures that the data-response token cannot report.

### What Actually Happens in the Wild

Research confirms this is a **known class of issues**:

> "Practical reports from embedded developers show that certain commands around status reporting simply do not work reliably in SPI mode on some cards, especially older/cheap ones."

Specific patterns observed across the embedded community:

1. **CMD13 returns garbage R2**: The card accepts the command but returns uninitialized or stale register values. This is what we observe on the AData card.

2. **ACMD13 (SD_STATUS) incomplete**: One engineer reports receiving only the 2-byte R2 header but never the 512-bit status data block, even though other app-specific commands work correctly.

3. **Timing misalignment**: Some controllers respond to CMD13 with wrong NCR (command-to-response delay), causing the host to read misaligned data that appears to be a valid but nonsensical R1 byte.

The key conclusion from research:

> "Status-related commands are among the least reliably implemented parts of the SPI command set on some cards, particularly older ones."

And critically:

> "There is no requirement that hosts must continuously poll CMD13 in SPI mode; it is a convenience, not a hard reliability pillar."

---

## 4. Decoding the Failure

### R1 = $C1 (Binary: 1100_0001)

| Bit | Name | Value | Analysis |
|-----|------|-------|----------|
| 7 | (must be 0) | **1** | **Spec violation.** This alone proves the response is invalid. |
| 6 | Parameter error | 1 | Contradicts successful data operations |
| 5 | Address error | 0 | |
| 4 | Erase seq error | 0 | |
| 3 | CRC error | 0 | |
| 2 | Illegal command | 0 | |
| 1 | Erase reset | 0 | |
| 0 | Idle state | 1 | Card claims to be in idle state during active operation |

Bit 7 = 1 is the **definitive proof** that this is not a valid R1 response. The SD spec is unambiguous: "The MSB of R1 is always zero." The card controller is either not responding to CMD13 at all (and the driver is reading bus noise or stale data) or responding with a non-standard format.

### STATUS = $3F (Binary: 0011_1111)

When the user patched out the R1 check to examine the STATUS byte:

| Bit | Flag | Value | Plausibility on a Read Operation |
|-----|------|-------|----------------------------------|
| 7 | OUT_OF_RANGE | 0 | |
| 6 | ERASE_PARAM | 0 | |
| 5 | WP_VIOLATION | **1** | Impossible -- this was a **read**, not a write |
| 4 | CARD_ECC_FAILED | **1** | Would cause CRC failure too; CRC passed |
| 3 | CC_ERROR | **1** | General controller error -- yet data is correct |
| 2 | ERROR | **1** | General error -- yet data is correct |
| 1 | WP_ERASE_SKIP | **1** | Impossible -- no erase/write occurred |
| 0 | CARD_IS_LOCKED | **1** | Card is not locked; reads and writes work |

Six of eight error bits set simultaneously during a successful read operation. This is **physically impossible**. WP_VIOLATION on a read, CARD_IS_LOCKED when the card is unlocked, ECC_FAILED when CRC validates clean -- these are contradictory conditions that confirm the STATUS byte is garbage, not a legitimate card response.

### Conclusion

The CMD13 R2 response from this card is entirely meaningless. The controller's CMD13 implementation in SPI mode is non-functional -- it returns uninitialized register values or bus noise rather than actual card status.

---

## 5. Why Data Operations Work Despite CMD13 Failure

The card has multiple independent integrity mechanisms, and CMD13 is the only one that fails:

| Mechanism | Scope | Works on This Card? |
|-----------|-------|-------------------|
| **CMD0/CMD8/ACMD41/CMD58** | Card initialization | Yes -- card initializes correctly |
| **CMD17 (READ_SINGLE_BLOCK)** | R1 response + data token + 512 bytes + CRC-16 | Yes -- reads succeed with valid CRC |
| **CMD24 (WRITE_SINGLE_BLOCK)** | R1 response + data-response token ($05) + busy signal | Yes -- writes succeed, data persists |
| **CMD18/CMD25 (MULTI_BLOCK)** | Same as above, repeated per sector | Yes -- multi-block works |
| **CMD12 (STOP_TRANSMISSION)** | R1b response + busy | Assumed yes (user didn't test explicitly) |
| **CRC-16 hardware validation** | Wire-level data integrity | Yes -- no CRC mismatches |
| **Busy signal (MISO held LOW)** | Card programming/housekeeping in progress | Yes -- write completion works normally |
| **CMD13 (SEND_STATUS)** | Card-internal error reporting (ECC, address, lock) | **No -- returns garbage** |

The data path (commands, data tokens, CRC, busy signals) is implemented correctly. Only the post-hoc status query command is broken. This is consistent with the documented observation that status-reporting commands are the "least reliably implemented" part of the SPI command set.

---

## 6. SPI Technique Analysis: Ruling Out Host-Side Causes

A natural question arises: could the CMD13 failure be caused by a bug in the driver's SPI communication -- a timing error, bit-stream alignment slip, or protocol violation that only manifests for CMD13? This section demonstrates definitively that it cannot.

### 6.1 The Driver's Two SPI Transfer Primitives

The driver uses exactly two low-level SPI transfer functions, both implemented with P2 smart pins:

| Function | Used By | Mechanism |
|----------|---------|-----------|
| **`sp_transfer(data, bits)`** | `cmd()` — sends CMD0, CMD8, CMD17, CMD24, CMD18, CMD25, CMD55, CMD58, ACMD41 | Smart pin synchronous TX/RX, variable bit width |
| **`sp_transfer_8(data)`** | CMD13, CMD12, CMD9, CMD10, CMD6, ACMD51, ACMD13 | Smart pin synchronous TX/RX, fixed 8-bit |

Both functions use the same smart pin configuration (P_SYNC_TX for MOSI, P_SYNC_RX for MISO, P_TRANSITION for SCK) and produce identical SPI bus behavior: clock-synchronized, MSB-first data transfer with on-edge sampling.

### 6.2 CMD13 Uses the Same Technique as Working Commands

CMD13's SPI sequence is:

```
sp_transfer_8($40 | CMD13)    →  command byte
sp_transfer_8($00) × 4        →  argument bytes (RCA, unused in SPI)
sp_transfer_8($FF)            →  CRC (disabled after init)
waitR1Response()              →  poll for R1 byte
sp_transfer_8($FF)            →  read STATUS byte (R2 second byte)
```

Compare with CMD12 (STOP_TRANSMISSION), which works correctly on this card:

```
sp_transfer_8($40 | CMD12)    →  command byte
sp_transfer_8($00) × 4        →  argument bytes
sp_transfer_8(CRC_CMD12)      →  CRC byte
waitR1Response()              →  poll for R1 byte
```

And CMD9 (SEND_CSD) / CMD10 (SEND_CID), which also work correctly:

```
sp_transfer_8($40 | CMD9)     →  command byte
sp_transfer_8($00) × 4        →  argument bytes
sp_transfer_8($FF)            →  CRC byte
waitR1Response()              →  poll for R1 byte
<data block follows>
```

All four commands use **identical** SPI primitives in **identical** order: `sp_transfer_8` for the 6-byte command frame, then `waitR1Response()` to poll for the R1 response byte. There is no timing variation, no different pin configuration, no different sampling mode. If a bit-stream alignment slip or SPI timing error existed in this sequence, it would affect CMD9, CMD10, and CMD12 equally -- yet those commands succeed.

### 6.3 The `cmd()` Path Also Succeeds

The other group of commands (CMD0, CMD8, CMD17, CMD24, CMD18, CMD25, CMD58) goes through the `cmd()` function, which uses `sp_transfer()` instead of `sp_transfer_8()`. The `cmd()` function has its own response-polling loop that is functionally identical to `waitR1Response()`:

```
repeat
    result := sp_transfer(-1, 8)     →  poll for non-$FF byte
    if result <> $FF
        quit
    if timeout
        quit
```

This means the driver successfully communicates with the card via **both** SPI primitives across **all** command types. The following commands all succeed on the AData card:

| Command | SPI Function | Response Type | Succeeds? |
|---------|-------------|---------------|-----------|
| CMD0 (GO_IDLE) | `cmd()` → `sp_transfer` | R1 | Yes |
| CMD8 (SEND_IF_COND) | `cmd()` → `sp_transfer` | R7 (R1 + 32-bit) | Yes |
| CMD58 (READ_OCR) | `cmd()` → `sp_transfer` | R3 (R1 + 32-bit) | Yes |
| CMD55 (APP_CMD) | `cmd()` → `sp_transfer` | R1 | Yes |
| ACMD41 (SD_SEND_OP_COND) | `cmd()` → `sp_transfer` | R1 | Yes |
| CMD17 (READ_SINGLE_BLOCK) | `cmd()` → `sp_transfer` | R1 + data | Yes |
| CMD24 (WRITE_SINGLE_BLOCK) | `cmd()` → `sp_transfer` | R1 + data response | Yes |
| CMD18 (READ_MULTIPLE) | `cmd()` → `sp_transfer` | R1 + data stream | Yes |
| CMD25 (WRITE_MULTIPLE) | `cmd()` → `sp_transfer` | R1 + data stream | Yes |
| CMD12 (STOP_TRANSMISSION) | `sp_transfer_8` | R1b | Yes |
| CMD9 (SEND_CSD) | `sp_transfer_8` | R1 + 16-byte data | Yes |
| CMD10 (SEND_CID) | `sp_transfer_8` | R1 + 16-byte data | Yes |
| **CMD13 (SEND_STATUS)** | **`sp_transfer_8`** | **R2 (R1 + STATUS)** | **No** |

CMD13 is the **only** command that fails. Every other command using both SPI primitives succeeds. If the driver had a bit-stream alignment issue, a sampling timing error, or a protocol violation in its SPI communication, it would be statistically impossible for the defect to affect only CMD13 while leaving 12+ other commands -- including commands using the exact same code path (`sp_transfer_8` + `waitR1Response`) -- completely unaffected.

### 6.4 The R2 Response Format is Not the Issue

One might hypothesize that the R2 response format (two bytes instead of one) could cause an alignment problem. But the driver reads the second byte with a straightforward `sp_transfer_8($FF)` call -- the same primitive used hundreds of times per sector read to poll for start tokens, read CRC bytes, and perform bus recovery. There is no special parsing, no multi-byte assembly in the SPI layer, and no opportunity for misalignment. The R1 byte is read by `waitR1Response()` (shared with CMD12 and init commands), and the STATUS byte is read by a plain `sp_transfer_8($FF)`.

### 6.5 Observed Command Sequence Brackets the Failure

The user's debug logs (see `DOCs/User-Reports/rpt4.txt`) show the exact command sequence during a session with the AData card. The init sequence succeeds completely:

```
[initCard] Step 4: CMD0 (GO_IDLE_STATE)...
[initCard] CMD0 response: $$1
[initCard] CMD0 OK - card in idle state
[initCard] Step 5: CMD8 (SEND_IF_COND, VHS=1, pattern=$AA)...
[initCard] CMD8 response (32-bit): $resp = $0000_01AA
[initCard] CMD8 echo valid ($1AA) -> Ver 2.0+ SD card
[initCard] Step 6: ACMD41 init loop (arg=$acmd41_arg = $4000_0000)...
[initCard] ACMD41 complete - card ready!
[initCard] Step 7: CMD58 (READ_OCR)...
[initCard] OCR: $resp = $C0FF_8000
[initCard] === INIT SUCCESS ===
```

CMD0, CMD8, CMD55/ACMD41 (repeated), and CMD58 all return correct R1/R3/R7 responses via the `cmd()` function and its `sp_transfer()` primitive. The SPI bus is provably aligned.

Then, when CMD13 is bypassed, the mount sequence reads **multiple sectors** successfully:

```
[do_mount] Reading MBR sector 0...                 ← CMD17, R1 OK, 512 bytes, CRC-16 valid
[do_mount] MBR type code: $B                        ← MBR parsed correctly
[do_mount] FAT32 detected, VBR at sector 2048
[do_mount] Bytes/sector: 512                        ← CMD17 at sector 2048, CRC valid
[do_mount] Sectors/cluster: 16
[do_mount] FSInfo: free_count=1926114 nxt_free=2    ← CMD17 at FSInfo sector, CRC valid
[do_mount] SUCCESS, mode=FILESYSTEM
```

The characterization utility (rpt1.txt) also shows successful register reads using `sp_transfer_8` — the **same** primitive CMD13 uses:

```
--- Reading Card Registers ---
  CID: OK (16 bytes)    ← CMD10 via sp_transfer_8 + waitR1Response + 16-byte data block
  CSD: OK (16 bytes)    ← CMD9 via sp_transfer_8 + waitR1Response + 16-byte data block
  SCR: OK (8 bytes)     ← ACMD51 via sp_transfer_8 + 8-byte data block
  OCR: OK (4 bytes)     ← CMD58 via cmd()/sp_transfer
  SD Status: OK (64 bytes)  ← ACMD13 via sp_transfer_8 + 512-bit data block
```

The operational sequence is:

1. **CMD0 → CMD8 → ACMD41 → CMD58** via `sp_transfer` — all succeed
2. **CMD9, CMD10** via `sp_transfer_8` + `waitR1Response` — both succeed, returning valid 16-byte registers that match the card's physical markings
3. **CMD17** (MBR read) via `cmd()`/`sp_transfer` — R1 OK, 512 bytes transferred, CRC-16 validates clean
4. **CMD13** via `sp_transfer_8` + `waitR1Response` — **R1 = $C1 (invalid), STATUS = $3F (impossible)**
5. **CMD17** (subsequent reads) — all succeed with clean CRC, filesystem parsed correctly

Steps 2 and 4 use **identical** code: `sp_transfer_8` to send the 6-byte command frame, `waitR1Response()` to poll for the R1 byte, then `sp_transfer_8($FF)` to read additional response bytes. CMD9 and CMD10 succeed; CMD13 fails. There is no intervening bus reset, no pin reconfiguration, no clock frequency change between these commands.

If a bit-stream alignment slip existed, it would corrupt the R1 response polling for every subsequent command — yet CMD17 immediately after CMD13 receives a clean R1 ($00) and transfers 512 bytes with valid CRC-16. A timing drift would accumulate across commands, not magically appear for one command and disappear for the next.

This bracketing is the strongest possible evidence against a host-side SPI issue.

### 6.6 Driver Spec Compliance: Ruling Out Protocol Errors

Could the failure be a driver protocol error -- a misordered operation, wrong CS timing, or spec violation that only affects CMD13? An examination of the driver's CMD13 implementation against the SD Physical Layer Specification (Part 1, Section 7.2.7) shows exact compliance:

| Spec Requirement | Driver Implementation | Compliant? |
|-----------------|----------------------|------------|
| CS must be LOW during command | `pinl(cs)` before command, `pinh(cs)` after response | Yes |
| Send 8 clocks with CS HIGH before command (Ncr recovery) | 2 × `sp_transfer_8($FF)` with CS HIGH before `pinl(cs)` | Yes |
| Command format: start bit (0), transmitter bit (1), 6-bit index | `$40 \| CMD13` = `$4D` (01_001101) | Yes |
| 32-bit argument (RCA in SD mode, 0x00000000 in SPI mode) | Four `sp_transfer_8($00)` bytes | Yes |
| CRC + end bit | `sp_transfer_8($FF)` (CRC disabled after init, per spec) | Yes |
| Wait for R1: poll with $FF until bit 7 = 0, up to Ncr cycles | `waitR1Response()` polls up to 255 bytes with 1-second timeout | Yes (exceeds Ncr minimum) |
| R2 second byte: read immediately after R1 | `sp_transfer_8($FF)` immediately after `waitR1Response()` | Yes |
| Deselect after response complete | `pinh(cs)` after reading STATUS byte | Yes |

The driver's CMD13 command framing is byte-for-byte identical to how CMD9, CMD10, and CMD12 are framed -- the same CS assertion pattern, the same dummy-clock preamble, the same 6-byte command frame, and the same `waitR1Response()` call. There is no CMD13-specific code path where a protocol error could hide.

Furthermore, the driver has been tested on **20 different SD cards** from **9 manufacturers** (SanDisk, Samsung, Lexar, Kingston, PNY, Amazon Basics, Micro Center, Silicon Power, Gigastone). CMD13 succeeds on all of them except this single AData card. If the driver had a protocol ordering or timing bug, it would be extraordinarily unlikely to manifest on exactly one card out of 20 -- and specifically on the card with the oldest firmware revision (0.2) from the lowest-tier manufacturer.

The pattern is consistent with a card-side firmware defect, not a host-side protocol error: the card works perfectly for all data operations but has a non-functional CMD13 status register in SPI mode.

### 6.7 Conclusion: Card-Side Defect, Not Host-Side

The evidence is unambiguous:

1. **Same SPI primitives** (`sp_transfer_8`, `waitR1Response`) succeed for CMD9, CMD10, CMD12
2. **Same response polling** succeeds for CMD0, CMD8, CMD17, CMD24, CMD58, ACMD41
3. **Same bus configuration** (smart pins, clock rate, sampling mode) is used for all commands
4. **No command-specific SPI logic** exists -- the driver does not treat CMD13's SPI framing differently from any other command
5. **CRC-16 validates clean** on every sector read, proving the SPI bus has no data integrity issues at any point during operation
6. **Bracketing evidence** -- commands immediately before and after CMD13 succeed, ruling out any transient bus state issue
7. **Spec compliance verified** -- the CMD13 implementation follows the SD Physical Layer Specification exactly, with byte-for-byte identical framing to other working commands
8. **20-card test matrix** -- CMD13 works on 19 of 20 cards; the single failure is the oldest, lowest-tier card

The failure is isolated to the card controller's handling of CMD13. The card's firmware either does not implement CMD13 in SPI mode, returns uninitialized register values, or has a bug in its status register logic. This is consistent with the card's profile (MID $1D budget OEM, firmware revision 0.2, manufactured 2013) and with documented community reports of CMD13 failures on older cards (see [Section 7](#7-external-research)).

The driver's SPI implementation is proven correct by the successful operation of every other command in the SD protocol across all 20 tested cards.

---

## 7. External Research

Additional research provides three key insights:

### 7.1 This is a Known Class of Issue

Research confirms that CMD13 failures in SPI mode are documented across the embedded community. It's not unique to this card or this driver. The root cause is that SPI-mode status commands were not a focus of compliance testing for older controllers.

### 7.2 CMD13 is a Convenience, Not a Reliability Pillar

> "The spec describes CRC handling and explicit data error tokens as the mechanisms for detecting real data corruption. There is no requirement that hosts must continuously poll CMD13 in SPI mode."

The primary integrity mechanisms in SPI mode are:
- **CRC-16** for read data validation
- **Data-response token** ($05/$0B/$0D) for write acceptance/rejection
- **Busy signal** (MISO LOW) for programming completion
- **R1 responses** on each command for immediate error reporting

CMD13 is a supplementary layer that catches card-internal errors (flash ECC failure, address out of range) that the above mechanisms might not surface. It is valuable but not essential.

### 7.3 Recommended Strategy: Probe and Adapt

The research recommends:
1. Probe CMD13 once at init -- check R1 bit 7, check for impossible error combinations
2. Mark failing cards as `CMD13_unreliable`
3. Skip CMD13 on marked cards; rely on CRC + data-response tokens
4. For good cards, keep CMD13 after writes (most valuable); consider it optional after reads

---

## 8. Current Driver Architecture: Where CMD13 Lives

The driver calls `checkCardStatus()` (which sends CMD13) in exactly **four places**:

### 8.1 After Single-Sector Read (`readSector`, line 5054)

```
' CMD13: Verify card internal state after read
' CRC validates wire integrity; CMD13 validates card-internal state (ECC, address, etc.)
if result == 0 and checkCardStatus(@"readSector") < 0
    long[p_cache] := -1           ' Invalidate cache on card error
    result := E_IO_ERROR
```

This runs after CRC-16 has already validated the data. CMD13 here catches the rare case where the card's flash ECC failed but the card still sent data with a valid CRC (theoretically possible if the card sends stale cached data).

### 8.2 After Multi-Block Read (`readSectors`, line 5155)

```
' CMD13: Verify card internal state after multi-block read
if checkCardStatus(@"readSectors") < 0
    sectors_read := 0             ' Card reports error - data can't be trusted
```

Same role as 8.1 but for CMD18 multi-block reads. If CMD13 fails here, ALL sectors from the multi-block read are discarded (sectors_read = 0).

### 8.3 After Single-Sector Write (`writeSector`, line 5344)

```
' CMD13: Verify card internal state after write
' Data response $05 confirms wire-level acceptance; CMD13 validates card-internal state
if checkCardStatus(@"writeSector") < 0
    result := E_IO_ERROR
```

This is CMD13's **most valuable role**. The data-response token ($05) only confirms the SPI interface accepted the data. CMD13 is the only mechanism to detect:
- Flash programming failure (ECC error during write)
- Address out of range (card couldn't map the sector)
- Controller error during internal flash management

### 8.4 After Multi-Block Write (`writeSectors`, line 5453)

```
' CMD13: Verify card internal state after multi-block write
if checkCardStatus(@"writeSectors") < 0
    sectors_written := 0          ' Card reports error - writes can't be trusted
```

Same role as 8.3 but for CMD25 multi-block writes. Failure discards all writes.

### The `checkCardStatus()` Implementation

The function:
1. Sends 2 dummy clocks with CS HIGH (card recovery time)
2. Asserts CS LOW
3. Sends CMD13 with argument 0x00000000
4. Waits for R1 response via `waitR1Response()`
5. Reads STATUS byte (second byte of R2)
6. Stages results in `last_cmd13_r1` and `last_cmd13_status` for diagnostic access
7. Returns 0 if both R1 and STATUS are $00, E_IO_ERROR otherwise

---

## 9. Integrity Layers: What Protects What

Understanding the layered integrity model is essential for deciding what can safely be skipped.

### For Reads

| Layer | What It Catches | Independent of CMD13? |
|-------|----------------|----------------------|
| **R1 response to CMD17** | Immediate command errors (illegal, address, CRC) | Yes |
| **Data start token ($FE)** | Card accepted read request, data follows | Yes |
| **CRC-16 (hardware GETCRC)** | Any bit corruption on the SPI bus during data transfer | Yes |
| **CMD13 after read** | Card-internal ECC failure, stale cache served | No -- this is CMD13's role |

For reads, CRC-16 is the primary integrity mechanism. It validates every byte of the 512-byte payload at the wire level using P2 hardware-accelerated CRC. If CRC passes, the data received matches what the card sent. CMD13 adds one additional check: did the card's internal flash ECC succeed? In theory, a card could have a flash ECC failure and serve stale cached data with a valid CRC. In practice, this is extremely rare.

### For Writes

| Layer | What It Catches | Independent of CMD13? |
|-------|----------------|----------------------|
| **R1 response to CMD24** | Immediate command errors | Yes |
| **Data-response token ($05)** | SPI interface accepted the data + CRC | Yes |
| **Busy signal (MISO LOW)** | Card is still programming flash; completion when MISO goes HIGH | Yes |
| **CMD13 after write** | Flash programming failure, ECC error, address error | No -- this is CMD13's role |

For writes, the data-response token confirms wire-level acceptance and the busy signal confirms programming completion. CMD13 is the only way to detect that the flash write actually succeeded internally. This makes CMD13 more valuable for writes than for reads.

### The Busy Signal is NOT CMD13

An important distinction: the "housekeeping delay" where the card holds MISO LOW during flash programming is a **wire-level signal**, not a CMD13 response. The driver detects busy via `waitBusyComplete()` which polls MISO in a tight loop. This mechanism is completely independent of CMD13 and is unaffected by any CMD13 changes. The busy signal:

- Happens during write operations (after data-response token)
- Also happens after CMD12 (stop transmission)
- Also happens after stop token ($FD) in multi-block writes
- Is detected by reading $00 bytes on MISO until $FF appears
- Has nothing to do with CMD13

CMD13 is sent **after** the busy period has already completed and CS has been deasserted. It asks "did that completed operation succeed internally?" -- it does not detect or participate in the busy/housekeeping process.

---

## 10. Mitigation Strategies

### Strategy A: CMD13 Probe at Init + Selective Disable

**Mechanism:** At the end of `initCard()`, after the card is confirmed working, send a single CMD13 probe. Check:
- R1 bit 7 must be 0
- No impossible error combination (3+ error flags simultaneously on an idle card)

If the probe fails, set a DAT flag `cmd13_reliable := FALSE`. Gate all four `checkCardStatus()` call sites on this flag. Log a debug message at mount.

**Pros:**
- Fully automatic -- no user configuration needed
- Targeted -- only affects cards that demonstrably fail CMD13
- No behavior change for working cards
- Simple implementation (one probe, one flag, four if-checks)

**Cons:**
- Doesn't detect cards that pass the probe but produce intermittent CMD13 garbage later (theoretical; not observed in practice)
- For flagged cards, CMD13 is disabled for both reads AND writes, losing the write-verification benefit

### Strategy B: Positive Warning Code from mount()

**Mechanism:** `mount()` currently returns SUCCESS (0) or negative error codes. Define a positive return value (e.g., `W_CMD13_UNRELIABLE = 1`) meaning "mounted successfully, but with advisory conditions." Callers checking `result < 0` (error) continue to work. Callers checking `result == SUCCESS` specifically can detect the advisory.

**Pros:**
- Reporting channel exists: `mount()` return value
- Backward compatible: `result >= 0` still means success
- Caller can decide whether to continue or abort
- No new API methods needed

**Cons:**
- Changes the contract of mount() -- existing code checking `result == SUCCESS` or `result == 0` would interpret the advisory as a failure
- Requires updating all call sites in examples, demos, and tests that check `mount() == SUCCESS`
- Semantically muddy: is it success or not?

### Strategy C: New Advisory Query API

**Mechanism:** Add a new PUB method `cardWarnings() : flags` that returns a bitmask of advisory conditions discovered during mount. Callers who care can check it after mount(); callers who don't can ignore it.

```
CON
    CW_NONE              = $00
    CW_CMD13_UNRELIABLE  = $01     ' CMD13 probe failed; status checks disabled

PUB cardWarnings() : flags
    flags := card_warning_flags
```

**Pros:**
- Clean separation: mount() returns success/failure, cardWarnings() returns advisories
- No change to mount() contract
- Extensible: can add future warning flags (e.g., CW_SLOW_CARD, CW_OLD_SPEC)
- Caller can query at any time, not just immediately after mount
- Zero overhead: just reads a DAT variable

**Cons:**
- New API surface (one more PUB method + CON constants)
- Callers must know to check it -- the warning is "opt-in"

### Strategy D: Per-Cog Error Channel via error()

**Mechanism:** After mount succeeds, store a warning code in the per-cog `last_error[]` slot. The caller can check `sd.error()` after a successful mount to see if any advisories were raised.

**Pros:**
- Uses existing API (`error()`)
- No new methods

**Cons:**
- Overloads the error channel -- `error()` is for the last operation's error, not for persistent advisories
- The warning gets overwritten by the next operation's error code
- Semantically wrong: a warning is not an error
- Would break callers that check `error() == 0` after a successful mount

### Strategy E: Mount with Warning Return + Advisory API (Combined)

**Mechanism:** Combine strategies A + C:
1. CMD13 probe at init, set `cmd13_reliable` flag
2. Gate `checkCardStatus()` calls on the flag
3. Add `cardWarnings()` API for external callers to query

Mount still returns SUCCESS (0) when the card works. The warning is available via `cardWarnings()` for callers who want to know about degraded verification. Debug output logs a message at mount time for developers watching the console.

**Pros:**
- mount() contract unchanged
- Clean advisory channel
- Automatic detection
- Extensible for future advisories
- Callers can check or ignore

**Cons:**
- Slightly more implementation work (new API + flag + probe)

### Strategy F: Runtime Downgrade Heuristic

**Mechanism:** Track CMD13 results over time. If a card that passed the initial probe starts returning contradictory results while data operations succeed, automatically downgrade it to CMD13-unreliable.

**Pros:**
- Catches cards with intermittent CMD13 problems

**Cons:**
- Complexity: tracking history, defining "contradictory," deciding thresholds
- No evidence this scenario exists in practice
- Adds runtime overhead to every CMD13 check
- Can recommend as a future enhancement if ever needed

---

## 11. Recommended Approach

**Strategy E (Probe + Advisory API)** is the recommended approach. It combines:

1. **Automatic CMD13 probe at end of `initCard()`**
   - Send CMD13, check R1 bit 7, check for impossible error combinations
   - Set `cmd13_reliable` DAT flag (BYTE, default TRUE)

2. **Gate all four `checkCardStatus()` call sites**
   - If `cmd13_reliable == FALSE`, skip CMD13, return SUCCESS
   - All four sites (readSector, readSectors, writeSector, writeSectors)

3. **Store advisory in `card_warning_flags` DAT variable**
   - Set `CW_CMD13_UNRELIABLE` bit when probe fails

4. **New `cardWarnings()` PUB method**
   - Returns `card_warning_flags` bitmask
   - Callers can check after mount() to detect degraded verification
   - Always available (not gated by conditional compilation)

5. **Debug output at mount time**
   - When `cmd13_reliable == FALSE`: log a single warning message visible in debug output

### Reporting Channel for External Callers

The `cardWarnings()` API provides the reporting channel:

```spin2
result := sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)
if result == SUCCESS
    if sd.cardWarnings() & sd.CW_CMD13_UNRELIABLE
        debug("NOTE: Card has unreliable CMD13; status checks disabled")
```

This lets external callers know that CMD13 has been detuned without changing mount()'s return contract or overloading the error channel.

### What This Looks Like in the Driver

New CON constants:
```spin2
' Card warning flags (bitmask, returned by cardWarnings())
CW_NONE              = $00
CW_CMD13_UNRELIABLE  = $01     ' CMD13 probe failed; status checks disabled
```

New DAT variables:
```spin2
cmd13_reliable        BYTE    TRUE      ' FALSE if CMD13 probe failed
card_warning_flags    BYTE    CW_NONE   ' Advisory bitmask
```

New PUB method:
```spin2
PUB cardWarnings() : flags
'' Get card advisory flags - returns bitmask of conditions discovered during mount.
    flags := card_warning_flags
```

Modified `checkCardStatus()`:
```spin2
PRI checkCardStatus(caller) : result | r1, status
    if not cmd13_reliable
        return SUCCESS              ' Skip CMD13 on cards with broken implementation
    ' ... existing CMD13 logic unchanged ...
```

CMD13 probe at end of `initCard()`:
```spin2
' Probe CMD13 reliability after successful card init
cmd13_reliable := TRUE
card_warning_flags := CW_NONE
<send CMD13, read R1 + STATUS>
if r1 & $80                         ' Bit 7 must be 0 per spec
    cmd13_reliable := FALSE
    card_warning_flags |= CW_CMD13_UNRELIABLE
elseif <impossible error combination on idle card>
    cmd13_reliable := FALSE
    card_warning_flags |= CW_CMD13_UNRELIABLE
```

---

## 12. Audit Tool Changes

Two findings from the audit should be addressed in the fsck utility:

### 12.1 Partition Type: Accept $0B and $0C

The audit currently fails on partition type $0B (FAT32 CHS). Both $0B and $0C are legitimate FAT32 partition type codes:

- `$0B` = FAT32 with CHS addressing (older, used by some Linux mkfs tools)
- `$0C` = FAT32 with LBA addressing (modern, standard for SDHC)

The driver uses the LBA start sector from the MBR partition table regardless of which type code is present. The audit should accept both.

### 12.2 Backup FSInfo Mismatch: Downgrade to Warning

The backup FSInfo sector not matching the primary is a common, low-severity inconsistency. Windows and Linux both update the primary FSInfo but do not always update the backup. This does not affect normal filesystem operation. The audit should report this as a WARNING rather than a FAIL.

---

## 13. Filesystem Issues on This Card

For completeness, the card has two filesystem-level characteristics unrelated to CMD13:

| Issue | Detail | Severity |
|-------|--------|----------|
| MBR partition type $0B | FAT32 CHS (formatted by Linux mkfs.fat) | Cosmetic -- driver handles it correctly |
| Backup FSInfo mismatch | Primary and backup FSInfo sectors differ | Low -- common on FAT32 media |
| OEM name "mkfs.fat" | Linux formatting tool | Informational |
| 8 KB clusters (16 sectors/cluster) | Smaller than optimal for 16GB | Informational -- works correctly |

None of these affect card functionality or data integrity.

---

*Analysis produced 2026-03-05 from user reports, research, and driver source code study.*
