# Punch List

Items to investigate when time permits.

---

### ~~Formatter: Switch FAT initialization to multi-sector writes (CMD25)~~ RESOLVED

**Status:** DONE — implemented in `isp_format_utility.spin2` with 64-sector CMD25 batches (`MULTI_BATCH_SIZE = 64`, 32 KB zero buffer). Both `initFAT()` and `initRootDirectory()` use `writeSectorsRaw()`. Verified working across multiple cards during onboarding.

*Noted: 2026-02-15 | Resolved: 2026-02-17*

---

### ~~BUG: openFileRead -40 errors on Samsung GD4QT benchmark~~ RESOLVED

**Status:** DONE — root cause was TX streamer 1-bit shift bug and CMD25 stuff byte bug, fixed in commits `07fc806` and `58f6347`. Post-fix Samsung GD4QT benchmarks at 350 MHz show all file reads succeeding (1,369-1,455 KB/s, zero -40 errors). Verified at both 350 and 250 MHz (commit `beb0646`).

*Noted: 2026-02-15 | Resolved: 2026-02-16*

---

### Silicon Power SPCC 64GB — CMD18 multi-block read times out

**Priority:** HIGH — blocks characterization of this card

**Card:** siliconpower-spcc-64gb
**Unique ID:** `SharedOEM_SPCC_0.7_00940105_202507`
**Card File:** [DOCs/cards/siliconpower-spcc-64gb.md](cards/siliconpower-spcc-64gb.md)

**Symptom:** CMD18 (READ_MULTIPLE_BLOCK) times out 100% — the card never sends the $FE data token after CMD18 is accepted. Single-sector CMD17 reads work perfectly (11,000 consecutive reads, 0 CRC errors). CMD18 fails in both the speed characterizer (no-mount mode) and the driver mount process (warmup read at `do_mount()` line 1173).

**Register contradiction:** CCC=$DB5 includes Class 2 (CMD18 supported). SCR CMD_SUPPORT=$03 includes CMD23 (SET_BLOCK_COUNT). The card explicitly advertises multi-block support. The timeout is NOT a documented card limitation.

**Investigation leads:**
1. Does this card require CMD23 before CMD18? Some cards that support CMD23 may expect a pre-defined block count rather than CMD12 termination.
2. Check whether CMD18 R1 response is $00 (accepted) — confirm the command is reaching the card.
3. Test CMD25 (multi-block write) separately — is it CMD18-specific or all multi-block?
4. Check if other Shared OEM ($9F) cards exhibit the same behavior.
5. This is the first SD 6.x spec card in the catalog — could be a spec-version-specific behavior.

**Impact:** Mount fails because `do_mount()` has a CMD18 warmup read. Benchmark and regression testing blocked. Card cannot be fully characterized.

*Noted: 2026-02-17*

---

### ~~Investigate whether CMD18 warmup in do_mount() is still needed~~ RESOLVED

**Status:** DONE — warmup confirmed vestigial and removed from both `do_mount()` and `do_init_card_only()`. The warmup was masking the TX streamer bit-shift bug (fixed in `07fc806`). Proven by running `SD_RT_multiblock_tests` (CMD25 write → CMD18 read → verify) on 4 cards across 4 manufacturers and 3 SD spec versions — all 6/6 PASS without warmup:
- Gigastone SD16G 16GB (SD 3.x)
- SanDisk Industrial SA16G 16GB (SD 5.x)
- Lexar Red MSSD0 64GB (SD 6.x)
- Samsung EVO Select 128GB (SD 6.x)

*Noted: 2026-02-17 | Resolved: 2026-02-17*

---

### Samsung 00000 8GB — FAT32 format writes but doesn't persist

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

Format utility (`SD_RT_format_tests.spin2`) reports FORMAT COMPLETE — it writes MBR (partition type $0C/FAT32 LBA), VBR (OEM "P2FMTER"), FSInfo, backup boot sector, both FATs (15,046 sectors each), and root directory cluster. All write operations appear to succeed (no errors returned). Format test result: 35/46 pass, 11 fail.

However, immediately re-reading the card shows the **original factory values are still present**:
- MBR partition type: `$0E` (FAT16 LBA) — should be `$0C` (FAT32 LBA)
- VBR OEM name: `MSWIN4.1` — should be `P2FMTER`
- mount() fails with error -22 (not FAT32)

**Reproduction (2026-02-15):**

1. First format attempt: download corrupted (`P2 checksum verification FAILED`), format output appeared but was running stale code. Card unchanged.
2. Second format attempt: download successful, FORMAT COMPLETE reported, 1,922,122 clusters, 15,046 sectors/FAT written. Card unchanged — still shows FAT16/$0E/MSWIN4.1.
3. Card info test after format: 8/16 pass (Phase 1 passes, Phase 2 mount fails).

**Possible Causes:**
- Card controller silently discarding writes to sector 0 (bad block remapping or internal write-protect)
- Card-level write protection not visible in CSD bits
- Old Samsung OEM controller firmware with SPI write quirks
- Card may accept writes to FAT area but not MBR area

**Card Background:**
- Manufactured August 2014 — over 11 years old
- Unlabeled Chinese-market card, no brand markings
- Samsung MID $1B + OID "SM" — genuine Samsung flash
- Product name "00000" — OEM/internal variant, not retail
- Factory formatted FAT16 with partition type $0E (FAT16 LBA)
- All other 16 cards in the collection format successfully

**Priority:** Low — old unlabeled card, no practical impact. All branded cards format fine.

*Noted: 2026-02-15*

---
