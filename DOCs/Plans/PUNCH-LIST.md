# Punch List

Items to investigate when time permits.

**Every entry carries a `**Class:**` line.** `user-affecting` means someone using
the shipped driver or utilities could hit it in normal use — wrong data, a wrong
result, a silent failure, or docs/output that misdescribe real behaviour. Per the
release gate in `CLAUDE.md`, every `user-affecting` item must be **fixed or
explicitly accepted in writing** before a release ships; the acceptance and its
reason are recorded on the item. Everything else — card-specific investigations,
features, harness work — is ordinary backlog.

Check before tagging: `grep -n "Class:" DOCs/Plans/PUNCH-LIST.md`

---

### ~~`debugClearRootDir()` leaks FAT clusters and clears only one root sector~~ RESOLVED 2026-07-25

**Class:** user-affecting — RESOLVED 2026-07-25 (public method, docs asserted the opposite of the code).

**Where:** `src/micro_sd_fat32_fs.spin2` — public wrapper `:2449`, worker case
`CMD_DEBUG_CLEAR_ROOT` `:2736-2743`.

**What's wrong:** the implementation is

```
bytefill(@buf, 0, SECTOR_SIZE)
if writeSector(root_sec, BUF_DATA) == SUCCESS
  dir_sec_in_buf := -1
  pb_status := SUCCESS
```

so it (a) zeroes **only `root_sec`**, the first sector of the root directory —
entries in the second and later root sectors survive untouched — and (b) frees
**no FAT clusters**, so every entry it erases leaks its whole cluster chain
permanently. The docstring's claim, *"Clears the root directory… This DELETES all
files and folders!"*, is wrong on both counts.

**Why it matters:** two regression suites called it unconditionally at start-up
(`SD_RT_file_ops_tests:109`, `SD_RT_subdir_ops_tests:97`) — both call sites
removed during the v1.5.4 harness precondition audit. Until then every regression
run silently lost free space that no `deleteFile()` would ever return, which is a
sufficient standalone explanation for the regression card progressively filling up
and needing a manual reformat — independent of the Bug A write-path corruption.

**Options when picked up:**
- Fix it: walk every root-directory sector and release each live entry's cluster
  chain, so it means what the docstring says; or
- Narrow it: rename to reflect the actual behaviour (clears the first root sector,
  leaks chains, diagnostic only) and correct the docstring.

Do **not** leave the current behaviour behind the current name. No regression
suite should call it either way.

**Resolved 2026-07-25 by the second option — narrowed to the truth.** A correct
"delete all files and folders" is a recursive tree delete (freeing a subdirectory's
own chain still leaks everything inside it): 100+ lines in the worker cog with a
512-long stack, duplicating what `SD_format_card` and `SD_FAT32_fsck` already do.
The real use for this method is the diagnostic sledgehammer — zero an unreadable
root so the card will mount — so it was renamed to say that.

- `debugClearRootDir()` -> `debugZeroRootSector()`; `CMD_DEBUG_CLEAR_ROOT` ->
  `CMD_DEBUG_ZERO_ROOT_SEC`. Behaviour and opcode unchanged.
- Docstring now states all three facts it hid: first sector only, later root
  sectors survive, chains are not freed. Points at fsck/format for the real jobs.
- Corrected in `CONDITIONAL-COMPILATION-GUIDE.md`, `SD-CARD-DRIVER-THEORY.md`
  (x2), `SD-CARD-DRIVER-TUTORIAL.md`, `regression-tests/THEORY-OF-OPERATIONS.md`.
- `diagnostic-tests/SD_zero_root_sector_probe.spin2` asserts the three facts on
  hardware; the operator steps in its header (audit -> fsck -> audit) certify the
  documented recovery path. **Not yet run on hardware.**

*Noted: 2026-07-23 (v1.5.4 sprint, §4 harness precondition audit)*

---

### Deliver the dual-driver convergence advice doc

**Class:** coordination — not user-affecting. Stephen owns delivery (agreed 2026-07-25).

**Where:** `DOCs/Agent-Reports/ADVICE-TO-DUAL-DRIVER-AGENT-CONVERGENCE.md` (7 divergences).

The doc was written as a v1.5.4 §8c deliverable and is complete, but neither the
plan nor its task said **how it reaches the dual-driver agent**. Written, not
delivered — so it is not yet doing its job. Divergence 7 (utility output voicing)
was added 2026-07-25 and is the freshest item they do not have.

Decide the channel (paste into that agent's session, drop it in their repo, or a
shared handoff location) and hand it over. Until then the two drivers keep
diverging on exactly the points the doc enumerates.

*Noted: 2026-07-25 (v1.6.0 sprint closeout, carryover)*

---

### Delete the runner's dual success-marker workaround for the format vehicle

**Class:** harness — not user-affecting. Blocked on evidence from the next sweep.

**Where:** `tools/run_regression.sh` `_reformat_card()` — the ~12-line comment
block plus `FORMAT COMPLETE || FORMAT SUCCESSFUL` acceptance.

`SD_format_card.spin2` now drains the terminal backlog (`waitms(500)`) before
`END_SESSION`, so its own `FORMAT SUCCESSFUL!` line should stop being truncated
out of the log. The runner still accepts either marker, deliberately: the
workaround stays until a hardware run proves the line lands intact.

**When picked up:** after the next full sweep, grep a `SD_format_card_*.log` for
an intact `FORMAT SUCCESSFUL`. If present, tighten `_reformat_card()` to that one
marker and delete the explanatory comment. If absent, the drain is insufficient —
investigate rather than lengthening the wait.

*Noted: 2026-07-25 (v1.6.0 sprint closeout, carryover)*

---

### Re-run the Card 1 recert sweep for a clean certification record

**Class:** record-keeping — not user-affecting. Cosmetic; the certification holds on the evidence.

**Where:** `DOCs/Agent-Reports/sweep_card1_recert_260724.txt`.

Card 1's transcript ends in `CLOSING AUDIT FAILED` with a hand-written annotation
explaining it is a false negative — caused by the runner grepping for
`AUDIT COMPLETE` while the consolidated engine emitted `FSCK COMPLETE`, since
fixed. The suites were 471/0 and the audit log itself is 23/0 clean, so the
certification holds on the evidence.

Cosmetic but worth ~10 minutes: re-run the sweep on the 4 KB card with the fixed
tooling so the cert record needs no annotation — particularly for a release whose
headline is that the audit now tells the truth. Card 2 already has a clean
end-to-end run with the fixed gate.

*Noted: 2026-07-25 (v1.6.0 sprint closeout, carryover)*

---

### Counterfeit asdfg-class — characterize LBA-failure-mode boundary

**Class:** investigation — not user-affecting. Characterization of known-counterfeit cards; behaviour already documented in the card catalog.

**Cards:** Lerdisk (`Unknown_asdfg_2.2_000001F4_202512`), Cloudisk (`Unknown_asdfg_2.2_00001680_202511`) — same `asdfg` silicon class, both CW_NO_DATA_CRC.

**Context:** From the 2026-05-27 wedge investigation, write #2 of a single-block-write pair always wedges these cards, but the *failure mode* varies by LBA:

| LBA #2 | Failure mode |
|---|---|
| 1,001 | busyTO (dresp=$05, then busy stuck ~4 s) |
| 50,001 | busyTO |
| 100,000 (same as #1) | busyTO |
| 100,001 | drespTO (dresp=$FF, never arrived) |

The mode-boundary is bracketed between LBA 50,001 and LBA 100,001 — only one drespTO data point so far. The transition probably corresponds to a wear-leveling zone or FTL region boundary in the counterfeit silicon (it's NOT an erase block boundary; all the tested pairs sit inside a single 128-sector erase block).

**Why this is on the punch list, not the active investigation:** Mapping the boundary characterizes the card's FTL internals but does not move us toward a fix. Both failure modes are wedges; no LBA we've tested escapes the wedge. The boundary location is an academic curiosity for the card-catalog data sheet, not a fix path. Deferred until the active wedge-mechanism investigation is concluded or a separate "card-characterization" cycle picks it up.

**Suggested scan if/when picked up:**
- LBA 75,000 (binary search between 50K and 100K)
- LBA 500,000 (does drespTO persist at much higher LBAs, or is there an upper boundary too?)
- LBA 10 (very low — does busyTO persist all the way down?)
- LBA `cardSize - 10` (near-end of card)

Requires one power-cycle per scan point. Approach: extend `diagnostic-tests/SD_lba_scan_50K.spin2` (already created and reusable) with a #define-able LBA, or copy-and-edit per test.

**Doc:** [`COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md`](../Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md) — see 2026-05-26/27 sections.

*Noted: 2026-05-27*

---

### ~~Silicon Power SPCC 64GB -- CMD18 multi-block read times out~~ RESOLVED v1.2.9

**Class:** user-affecting — RESOLVED v1.2.9.

**Card:** siliconpower-spcc-64gb
**Unique ID:** `SharedOEM_SPCC_0.7_00940105_202507`
**Card File:** [siliconpower-spcc-64gb.md](../cards/siliconpower-spcc-64gb.md)

**Symptom:** CMD18 (READ_MULTIPLE_BLOCK) times out 100% -- the card never sends the $FE data token after CMD18 is accepted. Single-sector CMD17 reads work perfectly (11,000 consecutive reads, 0 CRC errors). CMD18 fails in both the speed characterizer (no-mount mode) and the driver mount process (warmup read at `do_mount()` line 1173).

**Register contradiction:** CCC=$DB5 includes Class 2 (CMD18 supported). SCR CMD_SUPPORT=$03 includes CMD23 (SET_BLOCK_COUNT). The card explicitly advertises multi-block support. The timeout is NOT a documented card limitation.

**Resolution:** CMD12 tolerance fix in v1.2.9 — card has aggressive read-ahead pipeline that streams next sector's data token ($FE) before CMD12 arrives. CS deassert recovery (80 clocks per SD spec Section 7.2.2) is the definitive fix. Card now benchmarks at 967 KB/s single-sector, 2,334 KB/s multi-sector (350 MHz).

*Noted: 2026-02-17 — Resolved: 2026-03-06*

---

### Samsung 00000 8GB -- FAT32 format writes but doesn't persist — PAUSED (card not located)

**Class:** user-affecting, BLOCKED — the card cannot be located, so the defect cannot be reproduced or fixed. Release-gate disposition: accepted-blocked; card-specific, documented in the card catalog. Revisit if the card resurfaces or another card shows the same symptom.

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
*Paused: 2026-03-17 — unable to locate card for retesting*

---

### ~~Remove card_is_slow manufacturer override (PNY 20 MHz cap)~~ RESOLVED v1.3.2

**Class:** user-affecting — RESOLVED v1.3.2.

**Code:** `identifyCard()` and `setOptimalSpeed()` in `src/micro_sd_fat32_fs.spin2`

The driver flagged PNY/AData cards (manufacturer ID $1D) as `card_is_slow := true`, capping SPI at 20 MHz. Investigation revealed: (1) the flag checked the wrong MID ($1D instead of the PNY card's actual $27), so it never applied; (2) the real issue was an NCO write alignment bug at power-of-2 half-period values, not card speed sensitivity.

**Resolution:** Removed `card_is_slow` DAT variable and all 4 references (identifyCard, setOptimalSpeed, do_attempt_high_speed, stale comment in initCard). Fixed the actual bug with `xfrq -= 1` for exact NCO division. No driver logic now branches on manufacturer ID. See [NCO-WRITE-ALIGNMENT-ANALYSIS](../Analysis/NCO-WRITE-ALIGNMENT-ANALYSIS.md) and [NCO-WRITE-FIX-ENGINEERING-GUIDE](ext-agents/NCO-WRITE-FIX-ENGINEERING-GUIDE.md).

*Noted: 2026-03-02 — Resolved: 2026-03-09*

---

### Maxwell NCard 4GB -- Format fails with busyTimeout on sector 0

**Class:** user-affecting, card-specific — a user with this card cannot format it. Release-gate disposition: needs Stephen's explicit accept-or-fix at the next tag. Documented in the card catalog.

**Card:** Maxwell microSD HC 4GB (label), Silicon Motion NCard (controller)
**Unique ID:** `SiliconMotion_NCard_1.0_0000058F_201008`

```
Silicon Motion NCard SDHC 3GB [Empty] SD 3.x rev1.0 SN:$0000_058F 2010/08
Class 4, U0, V0, SPI 25 MHz
```

**Symptom:** Card initializes and reads successfully. Format utility writes MBR to sector 0 — card accepts CMD24, data response `$05` (accepted), but then stays busy indefinitely (busyTimeout, result=6). No valid MBR or filesystem on card (sector 0 is mostly zeros with "SMI" signature at offset $19).

**Diagnostic output:**
```
ERROR: Failed to write MBR!
  DIAG: result=6 R1=$00 dresp=$05 sector=0
  (1=CMD24fatal 2=drespTimeout 3=CRCreject 4=writeErr 5=unknownReject 6=busyTimeout 7=OK)
```

**Possible Causes:**
- Worn-out flash — controller accepts write command but can't complete erase/program cycle
- Similar to Samsung 00000 write-persist issue (different symptom, same class of problem)
- Card manufactured August 2010 — over 15 years old
- Unknown if only sector 0 fails or all writes fail (not yet tested)

**To Investigate:**
- Try raw write to non-zero sector (e.g., sector 1000) to determine if all writes fail or just sector 0
- Check if card has internal write-protect mechanism not visible in CSD bits

*Noted: 2026-03-17*

---

### Feature: SD 4-bit native mode backend (QSPI adapter support)

**Class:** feature — not a defect.

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
