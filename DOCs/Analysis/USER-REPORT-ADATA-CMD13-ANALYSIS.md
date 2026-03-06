# User Report Analysis: AData 16GB Card Blocking on CMD13

**Date:** 2026-03-05
**Source:** DOCs/User-Reports/rpt1.txt through rpt4.txt
**Card:** AData SDHC 16GB, manufactured March 2013

---

## 1. Card Identity

| Field | Value | Notes |
|-------|-------|-------|
| **Manufacturer ID (MID)** | $1D | AData (also used by PNY, some OEM cards) |
| **OEM/Application ID** | "AD" ($41 $44) | AData OEM code |
| **Product Name** | "SD   " | Generic name with trailing spaces -- budget/OEM controller |
| **Product Revision** | 0.2 | Very early firmware revision |
| **Serial Number** | $B162_04C2 | |
| **Manufacturing Date** | 2013-03 | **Over 13 years old** |
| **Card Type** | SDHC (CCS=1) | Block addressing, CSD v2.0 |
| **Capacity** | ~14 GB (30,857,216 sectors) | |
| **SD Spec Version** | 3.0x (SD_SPEC=2, SD_SPEC3=1) | |
| **TRAN_SPEED** | $32 = 25 MHz max | Standard speed only |
| **Timeouts** | Read: 100 ms, Write: 250 ms | SDHC standard fixed values |
| **CCC (Command Classes)** | $5B5 | Classes 0,2,4,5,7,8,10 -- no class 6 (write protect) |
| **Formatted by** | `mkfs.fat` (Linux) | OEM name in VBR |
| **Partition Type** | $0B (FAT32 CHS) | Older format; audit expects $0C (FAT32 LBA) |
| **Cluster Size** | 16 sectors (8 KB) | |

### Controller Assessment

The combination of MID $1D + generic product name "SD" + revision 0.2 + 2013 manufacture date strongly suggests a **budget Phison-family or similar OEM controller**. Key indicators:

- **Revision 0.2**: Extremely early firmware. Most mature SD controllers are at revision 1.0+ or higher. A 0.2 revision suggests this is from the first or second production run of this controller design.
- **Generic product name**: Legitimate high-quality cards have descriptive product names (e.g., "ACLCD", "USD", "SE16G"). A bare "SD" with trailing spaces is typical of white-label/budget controllers.
- **MID $1D**: Shared across AData, PNY, and numerous OEM/contract manufacturers, all sourcing from the same controller suppliers.

---

## 2. The Symptom

The card **blocks on every CMD13 (SEND_STATUS) call** after sector reads and writes. The driver calls CMD13 after each read/write operation to verify the card's internal state (ECC errors, address errors, etc.). This card returns garbage, causing E_IO_ERROR.

From the user's log (rpt4.txt):

```
[checkCardStatus] readSector: R1 error=$$C1
[do_mount] FAIL: MBR read error
[mount] Mount failed with error -7
```

---

## 3. Decoding the CMD13 Response

### R1 Byte: $C1

Binary: `1100_0001`

| Bit | Name | Value | Valid? |
|-----|------|-------|--------|
| 7 | (must be 0) | **1** | **INVALID** -- SD spec mandates bit 7 = 0 in all R1 responses |
| 6 | Parameter error | 1 | |
| 5 | Address error | 0 | |
| 4 | Erase sequence error | 0 | |
| 3 | CRC error | 0 | |
| 2 | Illegal command | 0 | |
| 1 | Erase reset | 0 | |
| 0 | Idle state | 1 | |

**Bit 7 = 1 is the smoking gun.** Per the SD Physical Layer Specification (Part 1, Section 7.3.2.1), the R1 response format requires bit 7 to always be 0. A value of 1 means the byte being read is **not a valid R1 response at all**. The card controller is either:
- Not responding to CMD13 (the $C1 is bus noise / stale data)
- Responding with a non-standard format
- Sending the response with wrong timing (the driver reads it shifted)

### STATUS Byte: $3F

When the user patched out the R1 check to see the status byte:

Binary: `0011_1111`

| Bit | Name | Value |
|-----|------|-------|
| 7 | OUT_OF_RANGE | 0 |
| 6 | ERASE_PARAM | 0 |
| 5 | WP_VIOLATION | 1 |
| 4 | CARD_ECC_FAILED | 1 |
| 3 | CC_ERROR | 1 |
| 2 | ERROR | 1 |
| 1 | WP_ERASE_SKIP | 1 |
| 0 | CARD_IS_LOCKED | 1 |

**Six of eight status error bits set simultaneously.** This is physically impossible in a normally-operating card:
- `WP_VIOLATION` requires a write to a protected area (but the operation was a **read**)
- `CARD_IS_LOCKED` requires a password lock (the card is not locked)
- `CARD_ECC_FAILED` + `CC_ERROR` + `ERROR` all at once is not a realistic failure mode

This confirms the STATUS byte is also **garbage**, not a legitimate card response.

---

## 4. Root Cause: Broken CMD13 Implementation

### Diagnosis

The card's controller **does not properly implement CMD13 (SEND_STATUS) in SPI mode**. The R2 response (R1 + STATUS) is garbage data, not a meaningful error report.

Evidence:
1. R1 bit 7 = 1 (spec violation, not a valid response)
2. STATUS has 6/8 error bits set simultaneously (physically impossible)
3. The errors appear on every single CMD13 call (not intermittent)
4. **All actual data operations work perfectly** -- the user confirms: "If I force checkCardStatus() to okay then everything is fine. I can read and write the SD card without problems. No corruption."

### Why This Happens

CMD13 was not widely used in early SPI-mode SD implementations. Many early SD controllers focused on the essential command set (CMD0, CMD8, CMD17, CMD24, ACMD41, CMD58) and treated CMD13 as low priority. Some controllers:

1. **Don't implement CMD13 at all** -- they return "illegal command" ($04 in R1 bit 2). This is actually the clean failure mode.
2. **Implement CMD13 partially** -- they accept the command but return stale/uninitialized register values. This appears to be what this card does.
3. **Return a response with wrong timing** -- the controller delays too long or too short, and the host reads misaligned data.

Given that bit 7 of R1 is 1, option (2) or (3) is most likely. The controller may be returning the R2 response at the wrong NCR (command-response delay) timing, causing the driver's `waitR1Response()` to read a byte that isn't actually the R1 byte.

### Supporting Evidence: 2013 Vintage

In 2013, SDHC cards were relatively mature, but SPI-mode CMD13 compliance was not universally tested. The SD Association's compliance testing programs focused heavily on SD-mode (4-bit bus) operation. SPI mode was considered a legacy interface primarily for microcontrollers, and CMD13 in SPI mode specifically was a corner of the spec that many controllers handled poorly.

---

## 5. Filesystem Issues (Minor, Unrelated)

The audit (rpt2.txt) found two additional issues when CMD13 is bypassed:

### 5.1 Partition Type $0B (not $0C)

The MBR partition type is `$0B` (FAT32 with CHS addressing) instead of the expected `$0C` (FAT32 with LBA addressing). This is because the card was formatted with Linux `mkfs.fat`, which can use either partition type depending on how it was invoked.

- `$0B` = FAT32, CHS addressing
- `$0C` = FAT32, LBA addressing (standard for SDHC)

Both work identically for our driver since we use the LBA start sector from the MBR partition table regardless of the type code. The audit check is overly strict here.

### 5.2 Backup FSInfo Mismatch

The backup FSInfo sector (at VBR sector + 12) does not match the primary FSInfo sector (at VBR sector + 1). This is a common low-severity inconsistency -- Windows and Linux both update the primary FSInfo but may not always update the backup. It does not affect normal operation.

---

## 6. Recommendations

### 6.1 Driver Change: Make CMD13 Failure Non-Fatal for Reads

CMD13 serves as a secondary validation layer. For **reads**, the primary integrity check is the CRC-16 that the card sends with every sector. If the CRC validates, the data is correct regardless of what CMD13 says. The driver could:

**Option A: Downgrade CMD13 read failures to warnings**
After a successful CRC-validated read, treat CMD13 failure as a diagnostic warning rather than E_IO_ERROR. Log the failure but return the data. This preserves the CRC-based integrity guarantee while tolerating broken CMD13 implementations.

**Option B: Make CMD13 checking configurable**
Add a flag (e.g., `SD_CMD13_CHECK_ENABLED`) that defaults to true but can be disabled by the user. This allows workaround without code changes.

**Option C: Detect broken CMD13 at init time**
After card initialization but before mounting, send a single CMD13 probe. If the R1 response has bit 7 set (spec violation), mark the card as "CMD13-unreliable" and skip all subsequent CMD13 checks. Log a warning at mount time.

### 6.2 For Writes, CMD13 Matters More

For **writes**, CMD13 is more important because the data-response token ($05) only confirms the card's SPI interface accepted the data -- it does not confirm the flash write succeeded. CMD13 is the only way to detect post-write ECC failure or flash programming errors.

However, for cards with broken CMD13, skipping it is still better than refusing to write at all. A pragmatic approach:
- Skip CMD13 for reads (CRC is sufficient)
- Skip CMD13 for writes on cards flagged as CMD13-unreliable, but log a warning at mount time that write integrity cannot be verified beyond the data-response token

### 6.3 Audit: Relax Partition Type Check

The audit's check for partition type $0C should accept both $0B and $0C as valid FAT32 partition types. Both are legitimate FAT32 indicators per the MBR specification.

### 6.4 For the User

The immediate workaround (forcing `checkCardStatus()` to return OK) is functionally safe for this card because:
- Read integrity is guaranteed by CRC-16 validation (hardware-accelerated, checked on every sector read)
- The card shows no actual data corruption
- Write integrity is covered by the data-response token ($05 = accepted)

The risk is that a genuine flash failure during a write would not be detected. For a 13-year-old budget card, this is an acceptable risk given the alternative is the card being unusable.

---

## 7. Summary

| Item | Finding |
|------|---------|
| **Card** | AData SDHC 16GB, MID $1D, revision 0.2, manufactured March 2013 |
| **Controller** | Budget OEM (likely Phison-family), extremely early firmware |
| **Root Cause** | CMD13 (SEND_STATUS) not properly implemented in SPI mode |
| **Evidence** | R1 bit 7 = 1 (spec violation); STATUS = $3F (6/8 error bits, impossible) |
| **Data Integrity** | Not affected -- all reads/writes work correctly; CRC validates clean |
| **Recommended Fix** | Auto-detect broken CMD13 at init; skip checks for flagged cards |
| **Partition Type** | $0B (CHS) instead of $0C (LBA) -- cosmetic, both work correctly |
| **Backup FSInfo** | Mismatched -- common low-severity inconsistency |

---

*Analysis produced 2026-03-05 from user reports rpt1.txt through rpt4.txt.*
