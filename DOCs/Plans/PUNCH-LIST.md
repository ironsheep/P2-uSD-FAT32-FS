# Punch List

Items to investigate when time permits.

---

### Silicon Power SPCC 64GB -- CMD18 multi-block read times out

**Card:** siliconpower-spcc-64gb
**Unique ID:** `SharedOEM_SPCC_0.7_00940105_202507`
**Card File:** [siliconpower-spcc-64gb.md](../cards/siliconpower-spcc-64gb.md)

**Symptom:** CMD18 (READ_MULTIPLE_BLOCK) times out 100% -- the card never sends the $FE data token after CMD18 is accepted. Single-sector CMD17 reads work perfectly (11,000 consecutive reads, 0 CRC errors). CMD18 fails in both the speed characterizer (no-mount mode) and the driver mount process (warmup read at `do_mount()` line 1173).

**Register contradiction:** CCC=$DB5 includes Class 2 (CMD18 supported). SCR CMD_SUPPORT=$03 includes CMD23 (SET_BLOCK_COUNT). The card explicitly advertises multi-block support. The timeout is NOT a documented card limitation.

**Investigation leads:**
1. Does this card require CMD23 before CMD18? Some cards that support CMD23 may expect a pre-defined block count rather than CMD12 termination.
2. Check whether CMD18 R1 response is $00 (accepted) -- confirm the command is reaching the card.
3. Test CMD25 (multi-block write) separately -- is it CMD18-specific or all multi-block?
4. Check if other Shared OEM ($9F) cards exhibit the same behavior.
5. This is the first SD 6.x spec card in the catalog -- could be a spec-version-specific behavior.

**Impact:** Mount fails because `do_mount()` has a CMD18 warmup read. Benchmark and regression testing blocked. Card cannot be fully characterized.

*Noted: 2026-02-17*

---

### Samsung 00000 8GB -- FAT32 format writes but doesn't persist

**Card:** samsung-00000-8gb
**Unique ID:** `Samsung_00000_1.0_D9FB539C_201408`
**Label:** Unlabeled 8GB microSD (Chinese text/no brand) - Card #2

```
Samsung 00000 SDHC 7GB [FAT16] SD 3.x rev1.0 SN:D9FB539C 2014/08
Class 6, SPI 25 MHz
```

**Raw Registers:**
```
CID: $1B $53 $4D $30 $30 $30 $30 $30 $10 $D9 $FB $53 $9C $00 $E8 $B1
CSD: $40 $0E $00 $32 $5B $59 $00 $00 $3A $CD $7F $80 $0A $40 $00 $97
OCR: $C0FF_8000
SCR: $02 $35 $80 $03 $00 $00 $00 $00
```

**ACMD13 SD Status (verified 2026-02-15):**
```
[00-0F]: $00 $00 $00 $00 $03 $00 $00 $00 $03 $03 $90 $00 $08 $11 $09 $00
[10-3F]: all $00
```
- SPEED_CLASS (byte 8): $03 = Class 6
- UHS_SPEED_GRADE (byte 14): $00 = U0 (not defined)
- VIDEO_SPEED_CLASS (byte 15): $00 = V0 (not defined)

**CSD write-protect bits:** PERM_WRITE_PROTECT=0, TMP_WRITE_PROTECT=0

**The Problem:**

Format utility (`SD_RT_format_tests.spin2`) reports FORMAT COMPLETE -- it writes MBR (partition type $0C/FAT32 LBA), VBR (OEM "P2FMTER"), FSInfo, backup boot sector, both FATs (15,046 sectors each), and root directory cluster. All write operations appear to succeed (no errors returned). Format test result: 35/46 pass, 11 fail.

However, immediately re-reading the card shows the **original factory values are still present**:
- MBR partition type: `$0E` (FAT16 LBA) -- should be `$0C` (FAT32 LBA)
- VBR OEM name: `MSWIN4.1` -- should be `P2FMTER`
- mount() fails with error -22 (not FAT32)

**Reproduction (2026-02-15):**

1. First format attempt: download corrupted (`P2 checksum verification FAILED`), format output appeared but was running stale code. Card unchanged.
2. Second format attempt: download successful, FORMAT COMPLETE reported, 1,922,122 clusters, 15,046 sectors/FAT written. Card unchanged -- still shows FAT16/$0E/MSWIN4.1.
3. Card info test after format: 8/16 pass (Phase 1 passes, Phase 2 mount fails).

**Possible Causes:**
- Card controller silently discarding writes to sector 0 (bad block remapping or internal write-protect)
- Card-level write protection not visible in CSD bits
- Old Samsung OEM controller firmware with SPI write quirks
- Card may accept writes to FAT area but not MBR area

**Card Background:**
- Manufactured August 2014 -- over 11 years old
- Unlabeled Chinese-market card, no brand markings
- Samsung MID $1B + OID "SM" -- genuine Samsung flash
- Product name "00000" -- OEM/internal variant, not retail
- Factory formatted FAT16 with partition type $0E (FAT16 LBA)
- All other 16 cards in the collection format successfully

*Noted: 2026-02-15*

---

### API: File/directory operations should return error codes, not true/false

**Goal:** File and directory operation methods that currently return `true`/`false` should return `SUCCESS` (0) on success or a negative error code on failure. Callers should not need to call `sd.error()` separately to find out what went wrong.

**Affected methods** (return `true`/`false` today):
- `deleteFile(pFilename)` -- returns `true`/`false`
- `rename(pOldName, pNewName)` -- returns `true`/`false`
- `moveFile(pFilename, pDestFolder)` -- returns `true`/`false`
- `newDirectory(pDirname)` -- returns `true`/`false`
- `changeDirectory(pDirname)` -- returns `true`/`false`

**Target pattern:**
```spin2
result := sd.deleteFile(@"OLD.TXT")
if result < 0
    debug("Delete failed: ", sdec_(result))    ' e.g., E_FILE_NOT_FOUND (-40)
```

**Notes:**
- The handle-based API already returns error codes (e.g., `openFileRead()` returns handle >= 0 or negative error)
- This change makes file/directory operations consistent with the handle API
- Update tutorial and all test files after changing

*Noted: 2026-02-28*

---

### Feature: SD 4-bit native mode backend (QSPI adapter support)

**Goal:** Support a second SD card adapter that wires out D0-D3/CLK/CMD for 4-bit parallel transfers, selectable via compile define (e.g., `SD_BUS_4BIT`). Same FAT32 filesystem layer on top, different transport underneath. Theoretical 4x throughput gain at the same clock speed.

**P2 streamer modes confirmed:**
- **Read (card->hub):** `X_4P_4DAC1_WFBYTE` ($E081_0000) -- 4 contiguous pins -> WFBYTE
- **Write (hub->card):** `X_RFBYTE_4P_4DAC1` ($A081_0000) -- RFBYTE -> 4 contiguous pins
- MSB-first via `X_ALT_ON` -- matches SD bus bit ordering

**What stays identical** (top ~90% of driver):
- Handle system, FAT32 parsing, directory traversal, file operations
- Worker cog mailbox, lock arbitration, buffer cache
- All public API methods, entire test suite

**What switches per backend** (bottom ~10%):
- Card init sequence (SPI mode -> SD native mode)
- Command send/receive framing (SPI R1 -> native 48-bit with CRC)
- `readSector()` / `writeSector()` streamer constants and clock counts
- CRC handling (single CRC-16 -> per-line CRC-16 on D0-D3)
- Pin setup (D0-D3 must be 4 contiguous P2 pins)
- Busy detection (polling byte -> DAT0 line level)

**Pin requirement:** D0-D3 on 4 contiguous P2 pins for streamer 4-pin modes. CLK and CMD on separate pins. Adapter hardware determines assignment.

**Key consideration:** SD 4-bit mode uses the SD native protocol, not SPI. The command framing, response formats, CRC, and busy signaling are fundamentally different from SPI mode. This is not just "SPI with more data lines" -- it requires implementing the SD native command layer.

*Noted: 2026-02-26*
