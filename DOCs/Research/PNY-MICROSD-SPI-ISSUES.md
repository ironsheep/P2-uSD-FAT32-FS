# PNY microSD Cards - SPI Mode Compatibility Research

**Date**: 2026-01-18
**Status**: Research for future driver hardening — partially adopted (see Decision below)
**Related**: Driver initialization sequence, response parsing

---

## Decision (audited 2026-05-18)

This document proposed, among other hardening measures, a **per-manufacturer SPI
speed cap** — detecting PNY/Phison cards via the CID MID byte and derating them
to ~20 MHz (see "Brand-specific workaround", the priority-1 fix, and the
"brand detection via CID" checklist item below).

That brand-based speed cap was **evaluated and deliberately NOT adopted.** Card
characterization showed every Phison/`$27` card in the catalog runs reliably at
the full 25 MHz SPI clock; no card needs derating. The shipping driver branches
on **no** manufacturer ID — SPI speed is `min(TRAN_SPEED, 25 MHz)` for every
card. `card_mfr_id` is recorded for identification only.

The **CS-handling and dummy-byte** hardening from this document *was* adopted.
Only the manufacturer-conditional speed cap was rejected. This note is kept so
the reasoning isn't re-litigated: the idea was considered, and the answer was no.

---

## Summary

PNY microSD cards are known to be more finicky in SPI mode. Marginal host implementations often expose issues that don't appear with other brands. Our P2 driver is likely correct but sits on timing/protocol edges that PNY cards stress.

**Key insight**: PNY cards work fine in phones and PCs (which use SD mode/SDIO), but expose SPI-mode edge cases.

---

## What Makes PNY Cards Different

### 1. Stricter Timing Around SPI Speed Changes

Microchip reported that PNY SD cards fail unless:
1. Card is **deselected** (CS HIGH)
2. SPI clock changed
3. Card **re-selected** (CS LOW)
4. Continue with operations

Leaving CS active while changing SPI speed causes init failures.

**Note**: SanDisk/Kingston tolerate this, but PNY exposes it.

### 2. Bit-Misaligned Responses in SPI Mode

An engineer on Microchip's forum noted that Kingston and PNY sometimes return responses that are **not aligned on byte boundaries**. The reply may be shifted by 1-3 bits, which breaks parsers that assume perfect byte alignment from the first non-0xFF byte.

**Solution**: More tolerant drivers re-synchronize by scanning bits until a valid start pattern is seen.

### 3. Slow/Marginal Initialization Behavior

Some controllers see cards that never set the busy bit in ACMD41 within their timeout window, causing endless retries or boot loops.

**PNY cards seem more likely to need**:
- "Insisting" on CMD55/ACMD41 (more retries)
- Longer waits before being ready

### 4. SPI Mode is Second-Class Citizen

The SD spec has de-emphasized SPI mode. Some vendors treat it as legacy.

Brands that optimize for phone/camera use (SDIO/4-bit) can be less robust in SPI. This matches what we see with PNY.

---

## Recommended Driver Hardening

### 1. Be Strict About Chip-Select and SPI Speed Changes

When switching from 400 kHz "init" clock up to higher transfer rate:

```
1. Drive CS HIGH
2. Change SPI clock divider
3. Re-assert CS LOW
4. Send at least one dummy 0xFF byte before next command
```

This matches the Microchip workaround that specifically fixed PNY failures.

### 2. Lengthen and Harden Initialization Sequence

**At power-up or card insert**:
- Provide at least 74 clock pulses with CS HIGH and MOSI HIGH before issuing CMD0

**CMD0**:
- Accept 0x01 (idle) as success
- Retry several times if 0xFF or 0x80 comes back

**CMD8**:
- Handle cards that don't support CMD8 (older SDSC) by falling back per standard

**ACMD41 loop**:
- Continue issuing CMD55 + ACMD41 until "ready" bit is set
- Timeout should be on the order of **1 second**, not just a few hundred ms
- Some problematic cards simply take longer to clear busy

### 3. Make Response Parser More Tolerant

**For R1/R3/R7 in SPI**:
- Clock in bytes until non-0xFF appears
- Allow a small number of extra bit clocks
- Check for expected start pattern
- Re-sync on the first 0 bit of the R1 response

**For data tokens (0xFE, 0xFC, etc.)**:
- Scan for the token across a window of bytes
- Don't assume it lands exactly where expected after command

**Key finding**: Current driver may assume perfectly aligned 8-bit responses. Relaxing that slightly can make PNY cards work.

### 4. Be Conservative with SPI Clock and Edges

- Keep initial clock at or **below 400 kHz** until ACMD41 completes
- Raise speed in steps, verify data CRCs are good at each step
- Stick to SPI mode 0 (CPOL=0, CPHA=0)
- Avoid edge-case timing (short CS setup/hold, sharp transitions with long stubs)

**Brand-specific workaround**: Detect brand via CID and cap PNY cards at lower SPI frequency.

### 5. Check Pull-ups and Bus Sharing

- Ensure MISO is tri-stated when CS is HIGH
- No other SPI device should drive MISO at the same time
- Conflicts are a known cause of "some cards work, some don't"
- All SD lines need appropriate pull-ups during reset/init per SD spec
- Some cards are more sensitive to pull-ups than others

### 6. Prefer "Better Behaved" Cards in Field

Even with a robust driver, some consumer SD cards remain flaky in SPI.

**Recommended brands for embedded**:
- SanDisk
- Transcend Industrial
- WD Industrial
- Kingston (generally good)

**For production systems**:
- Certify a short list of known-good brands/models
- Warn about PNY in documentation if can't fully tame them

---

## Implementation Checklist for P2 Driver

When hardening the driver for PNY compatibility:

**Initialization (completed 2026-01-20):**
- [x] Review SPI clock change sequence (CS handling) - Fixed: CS HIGH before speed change
- [x] Lower SPI clock to ≤20 MHz - Fixed: bit_delay = clkfreq / 40_000_000
- [x] Add dummy bytes after speed change - Fixed: 8 dummy bytes (64 clocks)

**Initialization (remaining):**
- [ ] Review CMD0/CMD8/ACMD41 sequence
- [ ] Review R1/data token parsing (bit alignment tolerance)
- [ ] Increase ACMD41 timeout to 1 second
- [✗] Consider brand detection via CID for speed limiting — *evaluated 2026-05-18, NOT adopted; all Phison/$27 cards run fine at 25 MHz (see Decision at top)*

**Write Operations (new - 2026-01-20):**
- [ ] Review writeSector() busy-wait implementation
- [ ] Verify data-response token (0x05) is read correctly
- [ ] Ensure CS stays LOW during entire busy-wait period
- [ ] Ensure continuous clocking during busy-wait (no SCK stops)
- [ ] Verify busy polling checks for 0xFF bytes (not just MISO high)
- [ ] Add reasonable per-block timeout (300-500ms, not 10+ seconds)
- [ ] Consider CMD13 (SEND_STATUS) on timeout for diagnostics

---

## Related Context

From `lesson_hardware_compat_pny` (context storage):
> PNY microSD card failed CMD0 init on P2 EC32 Mag (EX-32MB Edge module). CMD0 returned $00 instead of $01, MISO stuck at 0. Pins used: CS=60, MOSI=59, MISO=58, SCK=61.

This suggests our specific PNY failure may be related to:
1. Response bit-alignment issues (getting $00 instead of $01)
2. MISO not being released properly
3. Missing pull-ups on MISO line

---

---

## Agent Analysis of Our P2 Driver (2026-01-18)

After reviewing our driver's implementation details, an external analysis identified three main weak spots relative to "picky" cards like PNY:

1. **Changing SPI speed while CS is low with no resync**
2. **Assuming byte-aligned R1 responses**
3. **Running the data clock extremely fast (80 MHz) without brand-specific limiting**

### Analysis 1: Initialization Sequence

Our CMD0/CMD8/ACMD41/CMD58 flow and timeouts are generally solid and align well with common guidance. Given that most brands work already, the init sequence is probably not our primary problem.

**Changes worth considering (not strictly required):**
- Add a few more ACMD41 iterations and log the number of iterations; some borderline cards need many tries
- After CMD58, explicitly verify that the OCR voltage range bitmask is acceptable before moving to high-speed operation

### Analysis 2: SPI Clock Change and CS Handling (RED FLAG)

**This is the first big red flag for PNY.**

Other developers have seen PNY SD cards fail unless the SD card is deselected before changing SPI speed, then re-selected afterwards. The documented workaround is: CS HIGH → change SPI clock → CS LOW → send dummy clocks.

Glitches or abrupt changes on SCK while CS is low are known to cause persistent protocol desync on some controllers.

**Concrete fixes:**

After ACMD41/CMD58 completes at 50 kHz:
1. Drive CS HIGH
2. Change the bit_delay to "fast" value
3. With CS HIGH, clock out at least 8-16 dummy 0xFF bytes to stabilize SCK/MOSI
4. Assert CS LOW again for the next command
5. Send one more dummy 0xFF before that command
6. Consider adding a small delay (a few microseconds) after changing the clock divider before re-asserting CS

**On frequency:**

80 MHz on the wire is way beyond what most SD cards in SPI mode are characterized for. Practical SPI-mode ceilings are usually around 20-25 MHz.

**Diagnostic step**: Cap "fast" speed at 10-20 MHz and see if PNY cards suddenly behave. If they do:
- Keep a global cap (simplest), OR
- Read the CID and apply a lower per-brand cap when "PNY" is detected

### Analysis 3: R1 Parsing and Byte Alignment (RED FLAG)

**This is the second big place where picky cards/hosts diverge.**

Our R1 parsing assumes responses are perfectly byte-aligned. There are real reports of SD cards producing byte-misaligned responses in SPI mode; the symptom is R1 bits appearing shifted in captured bytes.

Robust drivers treat the first non-0xFF byte as only a "candidate" and may re-sync by scanning bits for a valid pattern.

**Recommended changes:**

When waiting for R1, keep existing "skip 0xFF bytes" logic, but once a non-0xFF byte appears, do not assume that entire byte is the R1.

**Option A (simple):** Accept only values where upper bits match R1 format (bit7 = 0, no impossible combinations like 0xFF/0xFE). If candidate is invalid, continue clocking bytes until a plausible R1 appears or timeout expires.

**Option B (more robust):** After first non-0xFF, clock an extra 8-16 bits while keeping a rolling 8-bit window in a shift register. Check each shift for a valid R1 pattern, effectively doing bit-level resync similar to what we do for the 0xFE token.

**Instrument**: Log or scope both raw byte stream and decoded R1 during failing PNY sessions to confirm misalignment.

### Analysis 4: Data Token Handling

Our bit-level polling for the 0xFE token start is already more forgiving than R1 parsing, but it trusts the first low bit as beginning of a valid token.

**Adjustments:**
- After bit-level wait for MISO going low, read the next full byte and verify it is exactly 0xFE; if not, treat as spurious and continue scanning or fail
- Include a maximum bit/byte count from end of command to when valid 0xFE must appear; if exceeded, abort as timeout

This guards against treating noise or mis-clocked bits as a data token, which can be more likely at very high SPI rates.

---

## Write Operation Analysis (2026-01-20)

**Key finding**: PNY cards are almost certainly not "really" taking 10–11 seconds to program a 512-byte sector; that symptom almost always indicates the host's write-busy handling is off and the card is stuck waiting for something, or you are stuck waiting on the wrong condition.

For SPI-mode writes, the two fragile parts are:
1. The **busy-wait on MISO**
2. The exact handling of **CS and clocks after the data-response token**

### How SPI-Mode Write Busy Should Behave

For a single-block write (CMD24) in SPI mode, the sequence is:

1. Send CMD24, get R1 = 0x00
2. Send a few 0xFF "gap" bytes
3. Send data token 0xFE, then 512 data bytes, then 2 CRC bytes
4. Card replies with a **data response**:
   - Lower 5 bits are meaningful: `0b00101` = "data accepted", others are errors
   - You typically see `0x05` as the token value
5. Immediately after that, the card:
   - Drives **MISO low** and stays low while it internally programs the flash ("busy" state)
   - When done, it releases MISO, which then idles high (you read 0xFF bytes)
6. The host is supposed to:
   - Keep **CS asserted low** while waiting for the busy period to end
   - Clock dummy 0xFF bytes and watch for the first 0xFF response, which means "ready"
   - Only then deassert CS or issue the next command

**Critical**: If CS is deasserted too early, or you change the SPI clock or mode during busy, some cards will get confused and you can end up in situations that look like multi-second "hangs."

### Likely Failure Modes for 10-11 Second Write Delays

Given our earlier init design and that PNY is more timing-sensitive than other brands, these are the most probable causes:

#### 1. Busy Polling on the Wrong Condition

- If your code checks only for "MISO goes high once" instead of "start seeing stable 0xFF bytes," noise or bit-misalignment could fool it, and then a later part of your stack might time out at 10–11 seconds
- If you accidentally **stop clocking SCK while "waiting,"** the card can remain busy indefinitely from the host's perspective, because it only communicates via returned bits when you clock it

#### 2. Releasing CS or Changing SPI Clock While Busy

- Some controllers (PNY is notorious) expect CS to remain low and clocking to continue until they release busy
- If your driver deasserts CS right after the 0x05 token and then changes SPI speed or mode, the card may abort or repeat internal housekeeping, making subsequent commands appear extremely slow or require re-init

#### 3. Not Consuming All Response Bits or Misaligning After Data-Response Token

- If the response is read with a bit-level routine that doesn't end exactly on a byte boundary, the next "busy" polling may be bit-shifted and never see 0xFF, so you spin until a long upper-level timeout

### Concrete Fixes for Write Operations

#### During the Write Sequence

1. After sending CRC, clock exactly 8 bits and read the data-response byte
2. Verify `(resp & 0x1F) == 0x05` (data accepted); if not, flag an error immediately
3. **Do not** change SPI speed, mode, or CS state at this point

#### Busy Wait Loop

1. Keep CS low
2. In a tight loop, send 0xFF and read a byte; repeat until the byte equals 0xFF or a reasonable timeout (tens to hundreds of ms per block, **not seconds**)
3. Only when you see 0xFF, consider the card ready and then you may:
   - Either deassert CS, or
   - Proceed to the next command directly

#### Timeouts

- Use a per-block busy timeout on the order of **300–500 ms**; if exceeded:
  - Deassert CS
  - Maybe send CMD13 (SEND_STATUS) to see if the card is in an error state
- **Do not** just keep clocking for 10+ seconds, or you hide the underlying failure

#### Multi-Block Writes (CMD25)

If using multi-block writes:
- The same pattern applies, but each data block has its own data-response and busy period
- After the STOP_TRAN token, there is also a final busy period; you must wait for 0xFF again before issuing any other command

### Why This Affects PNY Specifically

PNY (or, more accurately, the Phison and other controllers they often use) tend to be less tolerant of:
- Changing clock or CS at arbitrary points
- Slightly off-spec busy handling (e.g., letting CS float, or not clocking enough during busy)

Many other brands "just happen to work" even if the driver's write-busy handling is sloppy, which is why you are only noticing this with PNY.

### What to Examine in the Driver

To diagnose and fix the write delays, examine:
1. How the data-response token (0x05) is read
2. How busy/ready is polled (what value is checked, how long, what happens with CS and clock)
3. Whether CS or clock changes occur between write and busy-wait completion

Fixing these should collapse 10–11 second delays down to the expected few-tens-of-milliseconds level even on PNY cards.

---

### Prioritized Fix Plan

In order of impact vs. effort:

| Priority | Fix | Effort |
|----------|-----|--------|
| 1 | Lower "fast" SPI clock to ≤20 MHz and re-test PNY | Low |
| 2 | Add CS-high/clock-change/CS-low + dummy-bytes sequence after ACMD41/CMD58 | Medium |
| 3 | Harden R1 parsing with multi-candidate or bit-resync approach | Medium |
| 4 | Validate 0xFE token byte after bit-level start-bit detection | Low |

---

## Sources

- Microchip forum reports on PNY SPI failures
- SD Physical Layer Simplified Specification
- Embedded developer community experience reports
- External agent analysis of P2 driver implementation (2026-01-18)

---

*Research compiled: 2026-01-18*
*Updated: 2026-01-20 with write operation analysis*
*For use in: Future driver hardening sprint*
