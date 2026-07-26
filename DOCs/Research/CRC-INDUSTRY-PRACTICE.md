# CRC Error Handling — Industry Practice and Host Policy

**Source:** Perplexity research, 2026-02-15
**Context:** SD specs define mechanisms, not policy. This document captures de facto industry conventions.

---

## 1. Key Insight: Specs Define Mechanisms, Not Policy

The SD specs describe status bits, error tokens, and recovery commands. Host behavior (retry, reset, drop device, etc.) is an industry convention, not a hard standard. There is no normative section like "on CRC fail, retry N times with backoff X" in the SD physical spec.

**Relevant spec documents:**
- **SD Physical Layer Simplified Specification (Part 1):** CRC on CMD/DAT lines, error indications in R1/R2 responses, data response tokens, when to send CMD12
- **SD Host Controller Simplified Specification (Part A2):** Controller status bits like "Command CRC Error" and "Response CRC Error" — but leaves actual policy to the host driver

---

## 2. Card-Side Behavior on CRC Errors

### Command CRC error (host -> card)
- Card treats the command as illegal/ignored
- Does NOT execute the command, does NOT change state
- Host can safely resend the command

### Data write CRC error (host -> card)
- Each data block has its own CRC
- Card detects CRC error in data block:
  - Signals error in data response token
  - Does NOT program the corrupted block into flash
  - For multi-block: ignores further incoming blocks, may not send CRC status for them
  - Host expected to terminate with STOP_TRANSMISSION and re-send the data

### Data read CRC error (card -> host)
- The card always sends a correct CRC for what it transmits
- A "read CRC error" is detected on the HOST side (transmission corruption)
- From the card's perspective, the transaction completed normally
- There is NO special "retry that block" primitive at the protocol level
- Recovery is entirely host-driven

### Programming/erase errors
- If flash programming error occurs, card may ignore further data blocks and not send CRC responses
- Host should notice timeout / missing CRC
- Host should issue STOP_TRANSMISSION and recover

---

## 3. What the SD Spec Expects the Host to Do

### Write CRC error:
> "The host shall issue the respective WRITE command again and transfer all blocks again"

- For multi-block: send STOP_TRANSMISSION (CMD12) to abort, then redo the write
- Use ACMD22 to determine how many blocks were actually written

### Command/response CRC error:
- Physical Layer spec: "Host should issue CMD12 to recover" after certain error conditions
- Stop any ongoing data transfer, re-sync the bus, retry

### Host controller CRC errors:
- Host Controller spec exposes "Response CRC Error" and "Command CRC Error" bits
- Does NOT dictate exact retry counts or timeouts — up to the OS or firmware

---

## 4. De Facto Industry Practice

Based on Linux MMC/SD stack, vendor controller docs, and major OS implementations:

### Command CRC error or response CRC error:
1. Reissue the command a small number of times
2. If failures persist, reset the card or bus (power-cycle, re-init sequence)

### Data write CRC error (error in data response token):
1. Abort multi-block transfers with CMD12
2. Retry the entire affected block or multi-block transfer
3. If repeated failures: mark card as failing or read-only, escalate to OS

### Data read CRC error (detected by host):
1. Retry the read (possibly multiple times)
2. If same block consistently fails: report I/O error up-stack
3. Let the filesystem or application decide what to do

---

## 5. Practical Guidance for MCU Host Code

### Treat CRC errors as transient unless proven otherwise:
- Implement small retry loops for commands and for single-block read/write operations
- On repeated failure of the same operation: fall back to higher-level recovery (CMD12, card reset, or full re-init)

### For multi-block writes:
- Watch data response status for each block
- If any block reports CRC/program error: send CMD12, then re-send the full multi-block sequence
- Don't assume intermediate blocks were written correctly

### For read CRC errors (host-side detection):
- Just reissue the read — the card has no special CRC-error state, it just sees "another read command"
- If a sector repeatedly fails but others succeed: treat as media error (I/O error, bad block)

### Use host-controller status bits:
- Wire up "Command CRC Error", "Data CRC Error", and related status bits
- Implement policy in your driver rather than relying only on timeouts

---

## 6. Citeable Reference

> The SD Specifications Part 1 (Physical Layer Simplified Spec) is the key reference; it describes CRC use, error tokens, CMD12 recovery, and how cards behave when CRC or programming errors occur, while intentionally leaving retry/timeout policy to the host design.

---
