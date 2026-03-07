# CMD13 Root Cause Analysis: R1 Response Byte Alignment

**Date:** 2026-03-06
**Status:** Implemented and validated on two cards (SP Elite 64GB, Transcend 32GB). Awaiting user validation on AData 16GB.

---

## 1. The Bug

The driver's R1 response detection accepts the **first non-$FF byte** as the R1 response. The SD Physical Layer Specification (Section 7.3.2.1) requires that a valid R1 always has bit 7 = 0:

> *"This response token is sent by the card after every command with the exception of SEND_STATUS commands. It is one byte long, and the **MSB is always set to zero**. The other bits are error indications, an error being signaled by a 1."*

After a completed operation, the MISO line may still carry residual bytes — data tokens ($FE), CRC residue, bus settling artifacts. These bytes frequently have bit 7 set. Our driver treated them as R1 responses, producing false errors.

### The wrong code

```spin2
repeat
    resp := sp_transfer_8($FF)
    if resp <> $FF          ' WRONG: first non-$FF byte treated as R1
        r1 := resp
        quit
```

### The fix

```spin2
repeat
    resp := sp_transfer_8($FF)
    if (resp & $80) == 0    ' CORRECT: bit 7 must be 0 for valid R1
        r1 := resp
        quit
```

This is the same pattern used by FatFs/ChaN's canonical `sdmm.c`:

```c
do
    rcvr_mmc(buf+6, 1);
while ((buf[6] & 0x80) && --n);    /* Skip bytes with bit 7 set */
```

---

## 2. The Symptom

An external user reported that their AData 16GB card (MID $1D, SD 3.x, manufactured 2013) failed to mount. The driver's `checkCardStatus()` — which sends CMD13 after every sector read/write — returned R1=$C1 and STATUS=$3F, causing `E_IO_ERROR` on the very first MBR read.

When `checkCardStatus()` was forced to return success, the card worked perfectly — reads, writes, full audit, no corruption.

### Why $C1 is not an R1 response

$C1 = `1100_0001` — bit 7 is set. This is a residual byte on the bus, not a valid R1. Our driver treated it as R1 and saw "parameter error + idle" — a nonsensical combination. The actual R1 ($00) was the next byte, which we then misinterpreted as the STATUS byte. The STATUS byte that followed ($3F, with 6/8 error bits set) was equally meaningless — it was the real STATUS being read at the wrong position.

With the bit-7 check, the driver skips $C1 and finds the real R1.

---

## 3. Scope — CMD13 vs CMD12

The bit-7 check is the correct fix for **CMD13 and all general command R1 parsing** (idle bus). It does **not** replace the CS deassert recovery for **CMD12 during multi-block reads** (active bus). These are different problems.

### Why bit-7 works for CMD13

CMD13 is sent after a completed operation. The bus is nominally idle. Pre-response artifacts (data tokens, CRC residue, settling noise) have bit 7 set. The bit-7 check correctly skips all of them.

### Why bit-7 does NOT work for CMD12

CMD12 is sent while the card is actively streaming file data. File data can be **any byte value** — including $00, $05, or any value with bit 7 = 0. The bit-7 check would stop on random file data and misidentify it as R1. CS deassert recovery (80 clocks with CS HIGH, per SD spec Section 7.2.2) is the correct mechanism for CMD12.

| Situation | Pre-response bytes | Bit-7 check sufficient? |
|---|---|---|
| CMD13 after completed I/O | Bus artifacts (bit 7 set) | **Yes** |
| CMD12 mid-stream | Arbitrary file data | **No** — use CS deassert |

These two mechanisms are complementary:
- **Bit-7 check**: Finds R1 on an idle or settling bus
- **CS deassert recovery**: Terminates an active data stream so the bus returns to idle

---

## 4. What Was Changed

11 R1 detection loops updated from `resp <> $FF` to `(resp & $80) == 0`:

| Method | Context |
|--------|---------|
| `cmd()` | Central command dispatch |
| `waitR1Response()` | Shared R1 wait helper |
| `checkCardStatus()` | CMD13 after I/O |
| `probeCmd13()` | CMD13 probe at init |
| `readCSD()` | CMD9 register read |
| `readCID()` | CMD10 register read |
| `sendCMD6()` | High-speed mode switch |
| `readSCR()` | CMD55 + ACMD51 (2 loops) |
| `readSDStatus()` | CMD55 + ACMD13 (2 loops) |

**Not changed:** `sendStopTransmission()` (CMD12 mid-stream — file data has arbitrary bit patterns).

---

## 5. Validation

| Card | Suites | Pass | Fail |
|------|--------|------|------|
| Silicon Power Elite 64GB | 19/19 | 381 | 0 |
| Transcend 32GB | 19/19 | 381 | 0 |

Awaiting user validation on the AData 16GB card that originally triggered the investigation.

---

## 6. CMD13 Bypass Infrastructure — Status

The driver has CMD13 bypass infrastructure (`cmd13_reliable` flag, `probeCmd13()`, `CW_CMD13_UNRELIABLE` warning) built before the root cause was understood. This infrastructure remains in place as a safety net until the bit-7 fix is validated on the user's AData card. If validation confirms CMD13 works on all cards, this infrastructure can be removed.

CS deassert recovery in `recoverToIdle()` is unrelated and stays — it handles CMD12.

---

## 7. Prior Understanding

We initially diagnosed this as a card-specific CMD13 implementation defect — that older/budget controllers don't correctly implement CMD13 in SPI mode. The symptoms supported this reading: R1 bit 7 set (spec violation), impossible STATUS byte, consistently broken on every call. We built probe + bypass infrastructure to detect and work around these "broken" cards.

The card was never broken. Our R1 parsing was. The sdmm.c reference from the user's testing confirmed this: after adopting the bit-7 skip pattern, CMD13 returned valid responses on all their cards. See [CMD13-COMPATIBILITY-ANALYSIS.md](superseded/CMD13-COMPATIBILITY-ANALYSIS.md) and [USER-REPORT-ADATA-CMD13-ANALYSIS.md](superseded/USER-REPORT-ADATA-CMD13-ANALYSIS.md) for the original (incorrect) analysis — both contain superseded notices.

---

*Analysis produced 2026-03-06 — Iron Sheep Productions*
