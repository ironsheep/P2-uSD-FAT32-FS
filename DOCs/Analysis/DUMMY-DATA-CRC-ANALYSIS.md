# SD Cards That Send a Dummy Data-Block CRC (SPI Mode)

**Discovered:** 2026-05-18
**Trigger card:** Cloudisk 2 GB microSD (counterfeit; CID product name `asdfg`, MID `$05`, CRC7 `$00`; register-confirmed 2 GB **SDSC**, CSD v1.0)
**Status:** Root cause **confirmed on the wire** with a hardware logic analyzer. Driver fix designed (per-card CRC probe); implementation pending.
**Supersedes the conclusion of:** [`CLOUDISK-STREAMER-READ-INVESTIGATION.md`](CLOUDISK-STREAMER-READ-INVESTIGATION.md) — that investigation blamed the streamer; the streamer was never at fault.

---

## TL;DR

A class of SD cards — observed so far on older **SDSC** (CSD v1.0) media — does **not** compute a real CRC-16 for the data blocks it returns on a read. The card transmits a fixed placeholder in the CRC field (`$0000` on the trigger card; `$FFFF` is the other value seen in the wild). **The card's 512 data bytes are correct** — only the trailing 16-bit CRC field is a dummy.

The P2 driver's streamer read path (`readSector`) treated a data-CRC mismatch as a **fatal** error. Against a dummy-CRC card it therefore failed *every* read: `readSector` returned `E_CRC_ERROR`, the worker dispatch flattened that to `-7`, and skipped the copy-out — so the caller's buffer came back untouched. For most of the investigation this looked like a **streamer-DMA defect**. It was not. The streamer captures the data flawlessly; the failure was CRC *validation* against a card that never sends a real CRC.

The fix: **recognise** such a card at init (a one-sector CRC probe) and stop treating its data CRC as authoritative — while keeping full, strict CRC validation for every card that *does* send a real one.

---

## 1. The card

| Property | Value |
|---|---|
| Brand / product | "Cloudisk" 2 GB microSD — counterfeit (CID product name reads `asdfg`) |
| MID | `$05`  ·  CID CRC7 `$00` |
| Capacity class | **SDSC** — CSD v1.0, byte addressing (`CCS = 0`) |
| Init, register reads | Work (sysclk 200–350 MHz) |
| Writes | **Not reliable.** A single write completes; write #2 of a single-block-write pair always wedges this silicon class. See the correction below. |
| Slow byte-by-byte read | Works — returns correct, distinct data per sector |
| Streamer-DMA read | **Failed** (`-7`, buffer untouched) — until this fix |
| Data-block CRC on reads | **`$0000` — a dummy.** The real CRC of the data is non-zero. |

Bought new to certify the driver against budget/marginal SDSC media. It is a legitimate certification target.

> **Correction, 2026-08-12.** This table previously read "Init, register reads,
> writes | All work," which was wrong about writes and had been wrong since the
> document was written. The 2026-05-27 wedge investigation established that on this
> `asdfg` silicon class — Cloudisk 2 GB and Lerdisk 1 GB alike, both
> `CW_NO_DATA_CRC` — **write #2 of a single-block-write pair always wedges the
> card**, with the failure mode varying by LBA (`busyTO` with `dresp=$05` and a
> ~4 s stuck-busy at LBA 1,001 / 50,001 / 100,000; `drespTO` with `dresp=$FF`
> never arriving at LBA 100,001). No tested LBA escapes the wedge. What this
> document establishes is the **read** path: the dummy-CRC detection and the
> streamer-read fix. Its write claim was never in evidence.
>
> The scope of this analysis is unaffected — the fix it describes gates read
> *validation* only, and `writeSector()` still always sends a real CRC (§ below).
> The wedge is a separate, unresolved card defect tracked as "Counterfeit
> asdfg-class" on `DOCs/Plans/PUNCH-LIST.md`, classed as a card-specific
> investigation.

---

## 2. Background — the SPI-mode data-block CRC

On an SD card read in SPI mode, the card returns, per block: a `$FE` start token, 512 data bytes, then a **16-bit CRC** (CRC-16-CCITT, poly `$1021`). A spec-compliant card computes that CRC over the data it just sent.

Empirically, a class of cards — older/cheap/counterfeit **SDSC** controllers in particular — **skip the computation and emit a constant** (`$0000` or `$FFFF`) in the CRC field. The data itself is still valid; the card's firmware simply never bothered with the read-path CRC.

In SPI mode, CRC handling is relaxed by default (command-CRC checking is off after reset; `CMD59` governs it). A host is free to validate the data CRC or ignore it. The practical consequence is unavoidable: **a host that hard-fails on a data-CRC mismatch cannot use any card in this class.** Robust SD stacks must tolerate a card that does not provide a real read CRC.

---

## 3. The symptom — and why it misled the investigation for so long

`readSectorRaw(sector, buf)` returned `-7` (`E_IO_ERROR`) with the caller's buffer **completely unchanged** (a distinct `$EE` sentinel survived the call).

Two facts hid the real cause:

1. **`readSector` reads into the driver's *internal* `buf`**, validates CRC, and only then copies out. The worker dispatch (`CMD_READ_SECTOR_RAW`) does:
   ```
   if readSector(...) == 0
       bytemove(caller_buf, @buf, 512)   ' copy out ONLY on success
   else
       pb_status := E_IO_ERROR           ' ANY failure -> -7, no copy
   ```
   So **"buffer untouched" never meant "the streamer captured nothing."** It only ever meant "`readSector` returned non-zero." The investigation read it as a streamer-DMA failure; it was an error-handling artifact.

2. **The dispatch flattens every error code to `-7`.** `readSector` can return `E_CRC_ERROR (-4)`, `E_TIMEOUT (-1)`, `E_BAD_RESPONSE`, or `E_IO_ERROR (-7)` — the dispatch collapses all of them to `-7`. The visible `-7` carried no information about *which* failure occurred.

The prior investigation correctly ruled out streamer sample-phase and SPI clock rate, then concluded the remaining fault was in the streamer-RX capture path or a card limitation under gapless clocking. **Both were wrong.** The instrumentation needed was not "watch the streamer" — it was "ask the driver which error code it actually produced, and compare the streamer capture against a known-good reference."

---

## 4. The investigation that resolved it

### 4.1 Wire evidence (hardware logic analyzer)

A hardware LA on the eval-board SD pins (`CS=P20 SCK=P21 MOSI=P19 MISO=P18`), triggered on CS falling, captured a full single-sector read. Decoded MISO at the end of the data block:

```
… 00 00 55 AA | 00 00
   ^^^^^^^^^^^   ^^^^^
   data[508..511]  data-block CRC
```

`55 AA` is the MBR boot signature — the data is valid. **The two CRC bytes on the wire are `00 00`.** The card transmits a dummy CRC. The driver was reading exactly what the card sent.

### 4.2 The instrumented diagnostic — the decisive data

`diagnostic-tests/SD_la_streamer_diag.spin2` reads sector 0 two ways and dumps the driver's internal CRC diagnostics (`getLastReceivedCRC`, `getLastCalculatedCRC`, `debugGetReadSectorDiag`):

| | Slow read (no streamer) | Streamer read |
|---|---|---|
| status | `0` (success) | `-7` |
| captured `buf[0..3]` | `00 00 00 00` | `00 00 00 00` — **identical** |
| `calc_crc` (CRC of captured 512 bytes) | `$2302` | `$2302` — **identical** |
| `buf[508..511]` | `00 00 55 AA` (valid MBR sig) | — |
| `recv_crc` (CRC read from card) | `$0000` | `$0000` |

`calc_crc` is computed over the captured buffer. It is **bit-identical** for the streamer read and the no-streamer slow read. Had the streamer corrupted even one of the 512 bytes, `calc_crc` would differ. It does not. **The streamer captures all 512 data bytes perfectly.**

The only mismatch is `recv_crc $0000` vs `calc_crc $2302` — the card's dummy CRC vs the real CRC of the (correct) data.

### 4.3 Proof chain

| Stage | Evidence | Verdict |
|---|---|---|
| Command (CMD17) on the wire | MOSI = `51 00 00 00 00` | ✅ correct |
| CS framing | held low for one clean transaction | ✅ correct |
| Data-phase clock | continuous SCK burst fires | ✅ correct |
| Card delivers the sector | MISO carries real data, ends `55 AA` | ✅ card data is valid |
| Streamer capture | `calc_crc` identical to the no-streamer slow read | ✅ **streamer is correct** |
| Data-block CRC | `00 00` on the wire; `recv_crc = $0000` | ⚠️ **card sends a dummy CRC** |
| Driver result | `readSector` → `E_CRC_ERROR` → dispatch `-7`, no copy-out | ❌ **fatal-on-mismatch is the bug** |

Why the slow path "worked" while the streamer path failed: pure error-handling asymmetry. `readSectorSlow` *logs* a CRC mismatch and returns success anyway; `readSector` treats it as fatal, retries `MAX_READ_CRC_RETRIES` times, then returns `E_CRC_ERROR`.

---

## 5. How to recognise this class of card

**Signature of a dummy-data-CRC card:**

1. The card returns otherwise-valid data (a slow/tolerant read yields correct, structured content — e.g. sector 0 ends in the `55 AA` MBR signature).
2. The CRC field read from the card (`recv_crc`) is a **fixed placeholder** — `$0000` or `$FFFF` — and **does not match** the CRC computed over the (correct) data (`calc_crc`).
3. The placeholder is **constant across sectors**. A real CRC varies with the data; reading two different sectors and seeing the *same* `recv_crc` while `calc_crc` differs is the confirming tell.

This distinguishes a dummy-CRC card from genuine data corruption: real corruption produces a *varying*, real-looking `recv_crc` and *wrong data*; a dummy-CRC card produces a *constant* `recv_crc` and *correct data*.

**Recommended init-time probe procedure:**

- After card bring-up, before any filesystem read, read one (ideally two) sectors via the **tolerant** path (`readSectorSlow`, which never hard-fails on CRC and populates both `diag_recv_crc` and `diag_calc_crc`).
- If `recv_crc == calc_crc` → the card provides a real CRC → keep strict validation.
- If `recv_crc != calc_crc` **and** `recv_crc ∈ {$0000, $FFFF}` (and, with a two-sector probe, identical across both) → **dummy-CRC card** → disable read-CRC *validation* for the session.
- If `recv_crc != calc_crc` and `recv_crc` is some *other* value → treat as a genuine fault; **do not** disable validation.

---

## 6. Driver handling — the per-card CRC probe (design; not yet implemented)

**Per-card, not per-read.** A per-read "accept any `$0000` CRC" rule was rejected: it would let a corrupted read whose CRC bytes happened to land on `$0000` pass on a *real-CRC* card. The per-card probe keeps real-CRC cards under strict validation and relaxes **only** a card proven to send a dummy.

Design:

- A **dedicated flag** `card_provides_crc` (default `TRUE`), set by the init-time probe — *not* a reuse of the debug toggle `diag_crc_enabled` (overloading the debug flag would let `debugSetCrcEnabled` fight the auto-detection).
- `readSector` performs the fatal data-CRC check only when `diag_crc_enabled AND card_provides_crc`.
- The probe runs in the **shared card bring-up**, *before* `mount` reads the MBR — `mount` is otherwise also broken on these cards.
- Bring-up resets `card_provides_crc := TRUE` before probing, so a previous card's result cannot leak into the next mount.

**Boundaries — what the flag must NOT affect (artifact guards, to be verified in the code audit):**

- **Write-CRC generation is untouched.** `writeSector` must always send a *real* CRC; a card with write-CRC checking enabled would reject writes otherwise. The flag gates read *validation* only.
- The **multi-block** read path (`readSectors`, CMD18) must honour the same flag, or multi-block reads still fail on these cards.
- The probe read must not poison the sector caches (`sec_in_buf` etc.).
- `readSectorSlow` behaviour is left unchanged (it is a debug path).

**Mitigating factor:** even with read-CRC validation off, `readSector` still runs the post-read **CMD13** card-status check. Card-internal errors (ECC, address faults) are still caught. Relaxing the data CRC removes one of two integrity layers, not both.

---

## 7. The class this opens up

This is not a one-card curiosity. Recognising and handling dummy-CRC cards unlocks a whole category of media the driver currently rejects:

- **Old SDSC (CSD v1.0) cards** generally — pre-2010 controller architectures are the most likely to skip the read-path CRC.
- **The SanDisk SU01G 1 GB SDSC** — currently cataloged **FAIL**. Its streamer-read symptom is described as "the same failure class" as the Cloudisk card. It is a **strong suspect** for the same dummy-CRC behaviour and should be **re-tested with `SD_la_streamer_diag.spin2`** now that we know what to measure. (Its separate CMD13 `CC_ERROR` quirk is a distinct issue and does not contradict this.)
- **Budget / counterfeit cards** in general — minimal-effort firmware skipping the read CRC is exactly the kind of corner such cards cut.

Every future card brought into the catalog should be checked with the recognition procedure in §5. A card that fails streamer reads while passing slow reads is now a *known, handled pattern*, not a fresh investigation.

---

## 8. Verification — how we prove correctness

- **No regression:** the 25-suite regression run on the real-CRC catalog cards proves the fix did not weaken anything — those cards still validate strictly, and the CRC error-injection hooks (`test_force_read_crc_error`) still fire.
- **Fix proof:** the raw-sector and read/write suites must be run **against the Cloudisk card** on the eval board. Streamer reads (and `mount`) succeeding there proves the fix.
- **Caveat:** the CRC-validation / CRC-injection suites implicitly assume a real-CRC card. On a dummy-CRC card those specific tests are *inapplicable* and must not be read as failures. This belongs in the card's catalog note.

---

## 9. Lessons / methodology

- **Instrument both ends early.** The decisive data came from dumping the driver's *internal* CRC values (`recv` vs `calc`) and comparing the streamer capture against a *tolerant reference path*. That A/B — available from day one via existing getters — would have ended the investigation immediately.
- **A flattened error code hides the diagnosis.** The dispatch collapsing every `readSector` error to `-7` meant a CRC failure was indistinguishable from a timeout. Consider surfacing the real `readSector` return through the raw-read API.
- **Do not over-read a symptom.** "Destination buffer untouched" was taken as "streamer transferred nothing." It actually meant "`readSector` returned non-zero and the copy-out was skipped." The buffer was never the streamer's to fill on a failed read.
- **Keep a known-good reference path.** `readSectorSlow` being tolerant-by-design made it the perfect oracle. Preserve that property.

---

## 10. Diagnostic tools produced

| Tool | Role |
|---|---|
| `diagnostic-tests/SD_soft_la_test.spin2` | P2-internal soft logic analyzer — spare-cog streamer capture of one SD pin; SE1 CS-falling-edge hardware trigger. |
| `diagnostic-tests/SD_la_streamer_read.spin2` | Streamer-read bus stimulus for a hardware LA (repeated reads, arming window). |
| `diagnostic-tests/SD_la_pin_ident.spin2` | 4-bit counter on the SD pins — LA probe-channel identification. |
| `diagnostic-tests/SD_la_streamer_diag.spin2` | **The decisive tool** — slow vs streamer read of the same sector with full CRC/capture diagnostics dumped. |
