# CRC Error Handling Study

**Status:** Plan proposed — awaiting review
**Date:** 2026-02-15
**Context:** Investigation of openFileRead -40 bug exposed gaps in our CRC error handling

---

## 1. What the SD Specification Says

Source: SD Physical Layer Simplified Specification Version 9.10 (Part 1 chunks)

### 1.1 Read CRC Errors

**The spec is essentially silent on host recovery for read CRC failures.**

- Data blocks use CRC-16-CCITT: polynomial x^16 + x^12 + x^5 + 1
- Every data block (CMD17/CMD18) is suffixed with a 16-bit CRC
- If a read fails, the card sends a **data error token** instead of a data block (Section 7.3.3.1, Figure 7-4)
- Data error token format: `[7:4]=0000, [3:0]=error bits` (same bits as R2 response)
- Error bits include: Card ECC Failed, Out of Range, CC Error, general Error

**What the spec does NOT specify for read CRC errors:**
- No retry count or recommendation
- No recovery procedure
- No explicit guidance on whether the host should retry at all
- No timing requirements between retries

**The only explicit CRC recovery action in the entire spec:**
> "If CRC error occurs on the status data [during CMD6], the host should issue a power cycle."

This applies only to CMD6 (SWITCH_FUNC), not to regular data reads.

**For multi-block reads (CMD18):**
- Each transferred block has its own 16-bit CRC suffix
- Host can use CMD12 (STOP_TRANSMISSION) to abort the read
- No guidance on whether to retry individual blocks or the entire sequence

### 1.2 Write CRC Errors

**The spec is explicit and detailed about write CRC handling.**

**Data Response Token (Section 7.3.3.1):**

After every write block, the card returns a 1-byte data response token:

| Token bits [3:1] | Meaning |
|-------------------|---------|
| `010` | Data accepted |
| `101` | Data rejected — CRC error |
| `110` | Data rejected — Write error |

**Key spec quotes:**

> "If the CRC fails, the card shall indicate the failure on the DAT line; the transferred data will be discarded and not be written, and all further transmitted blocks (in multiple block write mode) will be ignored."
> — Section 4.3.4

> "In case of any error (CRC or Write Error) during Write Multiple Block operation, the host shall stop the data transmission using CMD12."
> — Section 7.3.3.1

> "Once the programming operation is completed, the host should check the results of the programming using the SEND_STATUS command (CMD13). Some errors (e.g. address out of range, write protect violation etc.) are detected during programming only. The only validation check performed on the data block, and communicated to the host via the data-response token, is the CRC and general Write Error indication."
> — Section 7.2.4

**Write CRC error recovery tools provided by the spec:**
- **CMD12** — Stop transmission (required for CMD25 multi-block after error)
- **CMD13 (SEND_STATUS)** — Get detailed error status (R2 response with error bits)
- **ACMD22 (SEND_NUM_WR_BLOCKS)** — Count of well-written blocks before error

**Retry guidance:** The spec does NOT mandate a retry count. Host implementation determines retry policy.

### 1.3 CRC On/Off in SPI Mode

From Section 14 notes:
> "CRC is OFF by default after entering SPI mode (except CMD0 and CMD8 which always need valid CRC)."

CRC can be enabled with CMD59 (CRC_ON_OFF). When CRC is off:
- Command CRCs are not checked by the card (except CMD0, CMD8)
- Data CRCs are still transmitted by the card but not enforced

---

## 2. Current Driver Implementation

Source: `src/micro_sd_fat32_fs.spin2`

### 2.1 Read Path — `readSector()` (line 4920)

**CRC validation (lines 5056-5067):**
```
Read 2 CRC bytes from card (high byte first)
if diag_crc_enabled:
    Calculate CRC-16 of received 512-byte buffer
    if match: increment diag_crc_matches counter
    else: increment diag_crc_mismatches counter, log debug message
    (NO error return — function returns success regardless)
```

**Post-read verification (lines 5071-5076):**
```
CMD13 (checkCardStatus) — if card reports error, invalidate cache, return -1
Otherwise: return 0 (success)
```

**Bugs identified:**
1. CRC mismatch is diagnostic-only — returns success (0) with potentially corrupt data in buffer
2. Cache is NOT invalidated on CRC mismatch
3. No retry mechanism

**Where readSector return value is ignored:**
- `do_close_h()` line 1520 — reads dir sector for read-modify-write of file size
- `do_sync_h()` line 1799 — same pattern
- 36 other call sites throughout the driver (most are read-only paths)

### 2.2 Write Path — `writeSector()` (line 5226)

**Data response token check (lines 5314-5329):**
```
Wait for non-$FF response (100ms timeout)
if (resp & $1F) <> $05:    -> "Data rejected", return false
```

**Post-write verification (lines 5331-5348):**
```
Wait for busy (card programming complete) with CSD-based timeout
CMD13 (checkCardStatus) — if card reports error, return false
Otherwise: return true
```

**Assessment:** Write path is spec-compliant:
- Detects CRC rejection (`$0B`) and write error (`$0D`) via the `<> $05` check
- Waits for programming to complete
- Verifies with CMD13
- Returns false on any failure so caller can handle it

**Minor gap:** Does not distinguish between CRC error and write error (both return false with same debug message). Could be improved for diagnostics but not functionally wrong.

### 2.3 Multi-Block Write Path — `writeSectors()` (line 5352)

**Per-block CRC and response handling:** (needs verification)
**CMD12 stop on error:** (needs verification)
**ACMD22 for block count:** Not implemented

### 2.4 `diag_crc_enabled` State

- Declared as `BYTE 1` in VAR section (line 400) — this means 1 byte allocated, NOT initialized to 1
- VAR section variables are zero-initialized at startup in Spin2
- Therefore `diag_crc_enabled` defaults to 0 (DISABLED) unless explicitly set
- Public API: `setCRCEnabled(enabled)` at line 574
- When disabled, CRC bytes are still read from card but not validated

---

## 3. Gap Analysis: Read vs Write

| Aspect | Read (`readSector`) | Write (`writeSector`) |
|--------|--------------------|-----------------------|
| CRC sent/received? | Card sends CRC, we receive it | We calculate and send CRC |
| CRC validated? | Only if `diag_crc_enabled` (default OFF) | Card always validates |
| Error detected? | Diagnostic counter only | Data response token |
| Error reported to caller? | NO — returns success | YES — returns false |
| Cache invalidated on error? | NO (on CRC mismatch) | YES (line 5269) |
| Retry mechanism? | None | None (caller can retry) |
| CMD13 check? | Yes — returns -1 on card error | Yes — returns false on card error |
| Caller checks return? | Often NO (38 of 39 call sites) | Usually yes |

---

## 4. Industry Practice Research

Source: `DOCs/Research/CRC-INDUSTRY-PRACTICE.md` (Perplexity research)

### 4.1 Key Insight

The SD specs define mechanisms (status bits, error tokens, recovery commands), NOT policy. Host behavior — retry, reset, drop device — is an industry convention, not a hard standard. There is no normative section like "on CRC fail, retry N times with backoff X."

### 4.2 Critical Distinction for Read CRC Errors

> "The card always sends a correct CRC for what it transmits. A 'read CRC error' is detected on the HOST side (transmission corruption). From the card's perspective, the transaction completed normally. There is NO special 'retry that block' primitive at the protocol level. Recovery is entirely host-driven."

This means: if we detect a CRC mismatch on read, the data in our buffer is **definitely corrupt** — the card sent good data but the SPI bus corrupted it in transit. The buffer contents must be discarded.

### 4.3 Industry Standard Recovery Patterns

**Read CRC error (de facto standard from Linux MMC/SD stack, vendor drivers):**
1. Just reissue the read — the card has no special CRC-error state, it just sees "another read command"
2. Retry a small number of times (typically 2-3 retries)
3. If same block consistently fails but others succeed: treat as media error, report I/O error up-stack
4. If failures persist across many blocks: fall back to higher-level recovery (card reset or full re-init)

**Write CRC error (de facto standard):**
1. Abort multi-block transfers with CMD12
2. Retry the entire affected block or multi-block transfer
3. If repeated failures: mark card as failing or read-only, escalate

**General principle:** Treat CRC errors as transient unless proven otherwise.

---

## 5. Combined Analysis

### 5.1 What We're Doing Right

- **Write path is spec-compliant.** Data response token checked, busy-wait, CMD13 verification, error returned to caller. This matches both the spec and industry practice.
- **We already read the CRC bytes on every read.** The infrastructure is in place — we receive the 2 CRC bytes and can compute CRC-16-CCITT. The gap is only in what we DO with the result.
- **CMD13 verification after reads.** We check card status and return -1 if the card reports an error. This catches card-side failures.

### 5.2 What We're Doing Wrong

1. **CRC validation is gated behind `diag_crc_enabled` (default OFF).** We're reading CRC bytes on every read but throwing them away. This is like having a smoke detector with the battery removed.

2. **CRC mismatch returns success.** Even when validation IS enabled, a mismatch increments a counter and returns success with corrupt data in the buffer. Per industry practice, the buffer contents are definitively corrupt and must be discarded.

3. **No retry on read CRC failure.** Industry practice is unanimous: retry the read. The card doesn't know anything went wrong — it just sees another CMD17. This is the simplest, most effective recovery.

4. **Critical callers ignore readSector return.** The read-modify-write paths in `do_close_h` and `do_sync_h` discard the return value. Even if readSector returned -1, these functions would patch and write back corrupt data.

### 5.3 Design Principle

Following industry practice: **CRC errors are transient until proven otherwise.** A single CRC mismatch on the SPI bus is not a card failure — it's a transmission error. Retry silently. Only escalate to the caller if retries are exhausted. This keeps the 39 existing call sites working without changes while making the driver robust against transient bus errors.

---

## 6. Systemic Issue: readSector Return Values Ignored Driver-Wide

### 6.1 The Problem

Of 43 `readSector()` call sites in the driver, only **1** checks the return value (line 708). The other 42 silently proceed with whatever is in the buffer — corrupt data, stale data, or partially-received data. This is not a 2-site bug; it is a driver-wide deficiency that will continue to cause problems as we encounter new cards with different timing characteristics.

**Every ignored error return is a potential data corruption or silent malfunction waiting to happen.**

### 6.2 Complete Call Site Audit

#### DESTRUCTIVE — Read-Modify-Write (9 sites) — CRITICAL

These read a sector, modify part of it, and write it back. A failed read means writing back corrupt data, **destroying valid data on disk.**

| Line | Function | What it modifies |
|------|----------|-----------------|
| 1297 | `do_close` (V2) | Directory entry (full 32-byte entry) |
| 1474 | `do_create` | Directory entry (new file entry) |
| 1520 | `do_close_h` | Directory entry (file size only) |
| 1799 | `do_sync_h` | Directory entry (file size only) |
| 2182 | `do_newdir` | Directory entry (new directory) |
| 2300 | `do_close` (V2 dir) | Directory entry (full 32-byte entry) |
| 2335 | `do_rename` | Directory entry (filename change) |
| 2381 | `do_setlabel` | VBR sector (volume label) |
| 2433 | `do_movefile` | Directory entry (move operation) |

#### DATA PATH — Returns Data to Application (10 sites) — HIGH

These read data into buffers that are returned to the application. A failed read means the application receives corrupt data silently.

| Line | Function | What it reads |
|------|----------|--------------|
| 1569 | `do_read_h` | Data sector → handle buffer |
| 1593 | `do_read_h` | FAT sector (chain following) |
| 1655 | `do_write_h` | Data sector (read within existing file) |
| 1751 | `do_write_h` | FAT sector (chain following for write) |
| 1904 | `do_seek_h` | FAT sector (chain following) |
| 1915 | `do_seek_h` | Data sector → handle buffer |
| 1979 | `do_read` (V2) | Data sector (partial read) |
| 2013 | `do_read` (V2) | Data sector (full sector) |
| 2023 | `do_read` (V2) | Data sector (tail read) |
| 2129 | `do_seek` (V2) | Data sector (seek position) |

#### FAT NAVIGATION — Chain Following (9 sites) — HIGH

These read FAT sectors to follow cluster chains. A failed read means following a corrupt chain — wrong clusters, infinite loops, or out-of-bounds access.

| Line | Function | What it reads |
|------|----------|--------------|
| 2287 | `do_freespace` | FAT sectors (counting free clusters) |
| 3852 | `followFatChainV2` | FAT sector (next cluster lookup) |
| 4309 | `getFATEntry` | FAT sector (cluster entry) |
| 4323 | `allocateCluster` | FAT sector (initial load) |
| 4327 | `allocateCluster` | FAT sector (next sector in scan) |
| 4337 | `allocateCluster` | FAT sector (link chain) |
| 4371 | `readNextSector` | FAT sector (cluster boundary) |
| 4385 | `readNextSector` | Next data/dir sector |
| 4398 | `followFatChain` | FAT sector (chain following) |

#### MOUNT / INIT — Structural Reads (4 sites) — MEDIUM

These read boot sectors and FSInfo during mount. A failed read means misconfigured filesystem parameters.

| Line | Function | What it reads |
|------|----------|--------------|
| 1061 | `do_mount` | MBR (sector 0) |
| 1067 | `do_mount` | VBR (volume boot record) |
| 1100 | `do_mount` | FSInfo sector |
| 1161 | `do_mount` | Warmup read (streamer init) |

#### DIRECTORY SEARCH / ENUMERATE (3 sites) — MEDIUM

These read directory sectors for search or enumeration. A failed read means files not found or wrong entries returned.

| Line | Function | What it reads |
|------|----------|--------------|
| 4074 | `searchDirectory` | Directory sector (file lookup) |
| 2390 | `do_setlabel` | Root directory (label search) |
| 2462 | `do_enumerate` | Directory sector (listing) |

#### FSINFO / VBR ACCESS (2 sites) — MEDIUM

| Line | Function | What it reads |
|------|----------|--------------|
| 2823 | `readVBRRaw` | VBR for raw access API |
| 3820 | `do_updateFSInfo` | FSInfo for free count update |

#### DEBUG / DIAGNOSTIC (6 sites) — LOW

These are verification reads or debug output. Failure is not operationally harmful.

| Line | Function | What it reads |
|------|----------|--------------|
| 2190 | `do_newdir` | Verify read (diagnostic) |
| 2217 | `do_newdir` | Verify read (diagnostic) |
| 3264 | `validateStreamer` | Root dir (streamer test) |
| 3270 | `validateStreamer` | Root dir (verify read) |
| 4163 | `debugDumpRootDir` | Root dir (debug dump) |
| 5734 | `displayFATSector` | FAT sector (debug display) |

#### ALREADY CHECKED (1 site)

| Line | Function | Notes |
|------|----------|-------|
| 708 | `fs_worker` (CMD_READ_SECTOR) | `if readSector(...) == 0` — the ONLY checked call site |

---

## 7. CRC Handling Plan

### 7.1 Change: Always Validate Read CRC (remove diagnostic gate)

**What:** Remove the `if diag_crc_enabled` conditional around CRC validation. Always compute and compare the CRC-16 on every `readSector` call.

**Why:** We already read the 2 CRC bytes from the card on every read. Computing and comparing the CRC adds negligible cost (~512-byte CRC16 calculation). There is no reason to NOT validate.

**Keep:** The `diag_crc_matches` and `diag_crc_mismatches` counters for telemetry. The `setCRCEnabled` / `getCRCMismatches` public API repurposed to report statistics (always-on validation means the API reports real data, not opt-in data).

**Impact:** No API change. No caller changes needed.

### 7.2 Change: CRC Mismatch → Retry Inside readSector

**What:** On CRC mismatch, invalidate cache, deselect card, and retry the read. Up to 3 total attempts (1 initial + 2 retries). If all attempts fail, return -1.

**Why:** Industry practice is unanimous — "just reissue the read." The card has no CRC-error state; it sees another CMD17. Retrying inside readSector is transparent to all call sites.

**Flow:**
```
readSector(sector, buf_type):
  repeat MAX_READ_CRC_RETRIES times:     ' 3 attempts total
    send CMD17
    wait for $FE token
    streamer receive 512 bytes
    read 2 CRC bytes
    compute CRC-16 of buffer
    if CRC matches:
      CMD13 check → return 0 or -1
    else:
      diag_crc_mismatches++
      diag_crc_retries++                  ' new telemetry counter
      invalidate cache
      deselect card (pinh(cs))
      debug("  [readSector] CRC mismatch, retry N of M")
      ' loop back to CMD17
  ' All retries exhausted
  debug("  [readSector] CRC FAILED after N retries")
  invalidate cache
  return -1
```

**New constant:** `MAX_READ_CRC_RETRIES = 3`

**New telemetry:** `diag_crc_retries` counter (how many times retry was needed and succeeded).

### 7.3 Change: Check readSector Return at ALL Call Sites

**Principle:** No readSector return value shall be ignored anywhere in the driver. Every call site must check for -1 and handle the error appropriately for its context.

**Error handling by category:**

**DESTRUCTIVE (read-modify-write) — 9 sites:**
- On readSector failure: do NOT modify buffer, do NOT write back
- Return E_IO_ERROR to caller
- Free any allocated handles
- This prevents the exact corruption pattern that caused the -40 bug

**DATA PATH (returns data to application) — 10 sites:**
- On readSector failure: return E_IO_ERROR or negative byte count
- Do NOT copy buffer to caller's memory
- Application sees an error, not silent corruption

**FAT NAVIGATION (chain following) — 9 sites:**
- On readSector failure: stop following the chain, return error
- Do NOT interpret buffer contents as cluster numbers
- Prevents following corrupt chains into wrong sectors

**MOUNT / INIT — 4 sites:**
- On readSector failure: fail the mount
- Return E_NOT_FAT32 or E_IO_ERROR
- Driver stays in unmounted state — safe

**DIRECTORY SEARCH / ENUMERATE — 3 sites:**
- On readSector failure: return false (not found) or error
- Better to report "file not found" than to search through corrupt data

**FSINFO / VBR ACCESS — 2 sites:**
- On readSector failure: return error, don't update FSInfo with corrupt values

**DEBUG / DIAGNOSTIC — 6 sites:**
- On readSector failure: log the failure, skip the diagnostic
- Non-critical — these can be addressed last

### 7.4 Change: Distinguish Write CRC Error from Write Error (diagnostic improvement)

**What:** In `writeSector`, when `(resp & $1F) <> $05`, decode the actual status bits to log whether it was a CRC rejection ($0B) or a write error ($0D).

**Why:** Pure diagnostics. Helps distinguish bus-level issues (CRC) from card-level issues (write error) in logs. No functional change.

### 7.5 No Change Needed: Write Path

The write path is already spec-compliant. The card validates write CRC and returns a clear accept/reject response. Our driver checks it and returns false on rejection. No changes needed.

### 7.6 Verify: Multi-Block Write CRC Handling

**Action:** Audit `writeSectors()` to confirm it checks the data response token for each block and issues CMD12 on error. Document findings.

---

## 8. Implementation Priority

| Priority | Change | Sites | Risk | Effort |
|----------|--------|-------|------|--------|
| **1** | **7.3 — DESTRUCTIVE paths: check return, abort on error** | **9** | **Prevents data destruction** | **Medium** |
| **2** | **7.1 — Always validate read CRC** | **1 (readSector)** | **Low** | **Small** |
| **3** | **7.2 — Retry inside readSector on CRC mismatch** | **1 (readSector)** | **Medium** | **Medium** |
| **4** | **7.3 — DATA PATH: check return, return error** | **10** | **Prevents silent corruption** | **Medium** |
| **5** | **7.3 — FAT NAVIGATION: check return, stop chain** | **9** | **Prevents wrong-cluster access** | **Medium** |
| **6** | **7.3 — MOUNT/INIT: check return, fail mount** | **4** | **Low** | **Small** |
| **7** | **7.3 — DIR SEARCH/ENUM: check return** | **3** | **Low** | **Small** |
| **8** | **7.3 — FSINFO/VBR: check return** | **2** | **Low** | **Small** |
| **9** | 7.4 — Distinguish write CRC vs write error | 1 | None | Tiny |
| **10** | 7.6 — Audit writeSectors CRC handling | 1 | None | Read-only |
| **11** | **7.3 — DEBUG/DIAGNOSTIC: check return** | **6** | **None** | **Small** |

**Priorities 1-3** are the immediate fix: protect destructive paths, enable CRC validation, add retry. This directly addresses the openFileRead -40 bug.

**Priorities 4-8** are the systemic fix: no ignored return values anywhere. This hardens the driver against every card we'll encounter in the future.

**Total: 43 call sites to audit and fix.** One (line 708) is already correct.

---

## 8. References

- `DOCs/Research/CRC-INDUSTRY-PRACTICE.md` — Industry conventions from Perplexity research
- `DOCs/Specs/Part1_chunks/chunk_ao` — Section 7.3.3 (SPI Data Response Token)
- `DOCs/Specs/Part1_chunks/chunk_ad` — Section 4.3.4 (Data Write Protocol)
- `DOCs/Specs/Part1_chunks/chunk_an` — Section 7.2.4 (SPI Write Operations)
- SD Physical Layer Simplified Specification Version 9.10

---
