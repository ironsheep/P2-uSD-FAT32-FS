# Macca Diagnostic Test — Design Draft

**Date:** 2026-05-05
**Status:** DRAFT — for review before implementation
**Goal:** A single-binary diagnostic test for @macca that branches on outcome, gathers full information from his 1GB SDSC card in one session, and validates the new card-aware test infrastructure.

---

## 1. Driver-side additions

### 1.1 New production getter

```spin2
PUB eraseBlockSectors() : sectors
'' Get erase block size in sectors as reported by the card's CSD SECTOR_SIZE field.
'' Useful for application logic that wants to align writes to erase boundaries
'' for reduced wear and improved write throughput.
''
'' Typical values:
''   SDSC (CSD v1.0):           32 sectors (16 KB block)
''   SDHC/SDXC (CSD v2.0):     128 sectors (64 KB block)
''
'' @returns sectors - Number of 512-byte sectors per erase block
''                    Returns 128 (default) if CSD parse failed.

  sectors := card_erase_block_sectors
```

**Implementation:** add `card_erase_block_sectors LONG 128` to DAT (default 128 = SDHC convention). Populate in `parseTimeouts()` or `do_get_card_size()`: read CSD bits [45:39] (SECTOR_SIZE field), add 1, store. Same field for both CSD v1.0 and v2.0.

**Gating:** **Not gated** — production API. Reasoning: this is parallel to `cardSizeSectors()` (also production). Application code legitimately needs this for write batching and log rotation. Cost is one method, ~5 lines of parser code, one DAT long.

### 1.2 New debug-gated method

```spin2
#ifdef SD_INCLUDE_DEBUG

PUB debugEraseBlock(start_sector) : status
'' DIAGNOSTIC ONLY: Erase one erase-block region starting at start_sector.
''
'' Sends CMD32 (ERASE_WR_BLK_START_ADDR), CMD33 (ERASE_WR_BLK_END_ADDR),
'' CMD38 (ERASE), then waits for busy completion.
''
'' Used by Phase D3 of macca diagnostic (erase-then-write recovery test) to
'' distinguish "card flash is recoverable" from "card flash is failing."
''
'' Production code MUST NOT call this. The SD spec discourages explicit erase
'' for normal block writes — the card's controller handles erase internally
'' on RMW. Misuse can accelerate wear or corrupt the FAT32 filesystem.
''
'' @param start_sector - First sector of the erase block to erase. Must be
''                       erase-block-aligned (caller's responsibility); no
''                       alignment check is performed.
'' @returns status - 0 on success, E_TIMEOUT or E_IO_ERROR on failure
```

**Implementation:** ~30-40 lines. Worker-cog routed via new `CMD_DEBUG_ERASE_BLOCK`. Sequence: CMD32(start) → R1==0 → CMD33(start + eraseBlockSectors - 1) → R1==0 → CMD38(0) → R1==0 → wait MISO returns to $FF.

**Gating:** `#ifdef SD_INCLUDE_DEBUG`. Reasoning: production has no use case for explicit erase; spec discourages it; misuse risks filesystem corruption.

---

## 2. Test framework additions (`isp_rt_utilities.spin2`)

### 2.1 Card profile cache

```spin2
VAR
    LONG profile_cached_flag                    ' 0 = not cached
    LONG profile_eraseBlockSectors
    LONG profile_capacitySectors
    LONG profile_readTimeoutMs
    LONG profile_writeTimeoutMs
    LONG profile_cardClass                       ' 0 = SDSC, 1 = SDHC/SDXC
    LONG profile_maxSpiHz
    LONG profile_mfrId

PUB cacheCardProfile(p_sd)
'' Cache card characteristics from the driver. Call once after mount,
'' before using any card-aware helpers below.
''
'' @param p_sd - Pointer to mounted micro_sd_fat32_fs object

    profile_eraseBlockSectors := p_sd.eraseBlockSectors()
    profile_capacitySectors   := p_sd.cardSizeSectors()
    profile_readTimeoutMs     := p_sd.getReadTimeout()
    profile_writeTimeoutMs    := p_sd.getWriteTimeout()
    profile_maxSpiHz          := p_sd.getCardMaxSpeed()
    profile_mfrId             := p_sd.getManufacturerID()
    profile_cardClass         := (p_sd.getOCR() >> 30) & 1
    profile_cached_flag       := 1
```

### 2.2 Card-aware sector helpers

```spin2
PUB safeTestRegionStart() : sector
'' Returns first erase-block-aligned sector that is reasonably past FAT32
'' metadata (root dir, FAT tables typically reside in first 1024-40000
'' sectors). Picks sector 100,000 rounded up to next erase block boundary,
'' clamped to never exceed half of card capacity.
''
'' Requires cacheCardProfile() called first.

PUB nonAdjacentSectors(count, p_dest) : returnedCount
'' Fill p_dest (LONG array of size count) with sector numbers, each in a
'' different erase block. First sector is safeTestRegionStart(); subsequent
'' sectors stride by profile_eraseBlockSectors.
''
'' If count exceeds the available number of strides before card capacity,
'' returns fewer entries (returnedCount < count).
''
'' Requires cacheCardProfile() called first.

PUB blockAlignedRange(count) : startSector
'' Return start of an erase-block-aligned range that contains exactly `count`
'' sectors and fits within one or more whole erase blocks.
'' For tests that want to write a complete erase block (whole-block-erase
'' fast path on the card).
''
'' Requires cacheCardProfile() called first.

PUB cardAdjustedTimeoutMs(base_ms) : adjusted_ms
'' Scale a base timeout (suitable for typical SDHC) up if the card profile
'' indicates slower behavior (SDSC with high R2W_FACTOR or TAAC).
'' Returns max(base_ms, profile_readTimeoutMs * scale_factor).
'' Scale factor: 2 for SDHC, 4 for SDSC.

PUB profileReport(p_dest)
'' Format-print the cached profile to debug output. Used by tests to log
'' what they actually ran against, for reproducibility in failure analysis.
```

**Test-side, no driver-API impact.** Tests `OBJ utils : "isp_rt_utilities"` and call these directly.

---

## 3. Macca diagnostic test program (`SD_macca_diagnostic.spin2`)

Lives in `diagnostic-tests/`. Sets `_CLKFREQ = 350_000_000` and `#pragma exportdef SD_INCLUDE_ALL`.

### 3.1 Top-level structure

```
mount → cacheCardProfile → reportProfile
↓
PHASE A: disambiguation (always runs)
↓
case phase_a_outcome:
    DRIVER_SIDE:    PHASE B → PHASE C1 → PHASE C2
    CARD_SIDE:      PHASE D
    CANNOT_REPRODUCE: retry-loop, then report
    INVERSE:        PHASE D (forensic)
↓
unmount → emit final report
```

Total runtime worst case: ~4 minutes. Best case (CARD_SIDE): ~2 minutes.

### 3.2 Phase A — Disambiguation

```spin2
PRI runPhaseA() : outcome | a1_status, a2_status, a1_signature, a2_signature
' A1: streamer read of sector 0 (default settings)
    bytefill(@streamer_buf, $00, 512)
    a1_status := sd.readSectorRaw(0, @streamer_buf)
    a1_signature := (BYTE[@streamer_buf][510] << 8) | BYTE[@streamer_buf][511]

' A2: slow-path read of sector 0 (default settings)
    bytefill(@slowpath_buf, $00, 512)
    a2_status := sd.debugReadSectorSlow(0, @slowpath_buf)
    a2_signature := (BYTE[@slowpath_buf][510] << 8) | BYTE[@slowpath_buf][511]

' Compare: $55AA boot-signature presence and overall buffer state
    case (a1_signature == $55AA), (a2_signature == $55AA):
        false, false:  outcome := BRANCH_CARD_SIDE         ' both zero/garbage
        false, true:   outcome := BRANCH_DRIVER_SIDE       ' streamer-specific
        true, true:    outcome := BRANCH_CANNOT_REPRODUCE  ' both worked
        true, false:   outcome := BRANCH_INVERSE           ' improbable
```

**Output format:**
```
PHASE A: DISAMBIGUATION
  A1: streamer    sector=0 status=0 sig=$0000 hash=$00000000  (no MBR signature)
  A2: slowpath    sector=0 status=0 sig=$55AA hash=$A3F2B891  (valid MBR signature)
  → BRANCH: DRIVER_SIDE (streamer-specific failure)
```

### 3.3 Phase B — Phase tuning matrix (driver-side branch)

```spin2
PRI runPhaseB() | mode, offset, errors
    debug("PHASE B: PHASE TUNING (3 modes x 5 offsets, errors per cell out of 512)")
    debug("                offset=-3  offset=0  offset=+3  offset=+5  offset=+7")

    repeat mode from 0 to 2  ' 0=PRE-edge, 1=ON-edge, -1=AUTO (we'll iterate -1, 0, 1)
        repeat offset from -3 to 7 step ...  ' -3, 0, 3, 5, 7
            sd.debugSetSampleMode(mode)
            sd.debugSetAlignDelayOffset(offset)
            errors := readSector0AndCountByteMismatches(@streamer_buf, @slowpath_buf)
            ' record cell, format-print
```

15 cells, ~30s wall-clock. Compares each cell's streamer read against Phase A's slow-path reference (the known-good buffer).

**Output format:**
```
PHASE B: PHASE TUNING (3 modes x 5 offsets, errors out of 512 bytes)
                offset=-3  offset=0  offset=+3  offset=+5  offset=+7
  PRE-edge:        512        512       143         0          0
  ON-edge:         512        512       512        287         12
  AUTO:            512        512       512        287         12
  → BEST CELL: PRE-edge / offset=+5 (0 errors)
  → SECOND BEST: PRE-edge / offset=+7 (0 errors)
```

After Phase B, restore default sample_mode (`-1` auto) and align_delay_offset (`0`).

### 3.4 Phase C1 — SPI speed sweep

7 cells: 25, 22, 20, 18.75, 15, 12.5, 8 MHz. Default phase tuning. sysclk=350.

For each: call `sd.setSPISpeed(rate)`, read sector 0 via streamer, count byte mismatches against slow-path reference.

**Output:**
```
PHASE C1: SPI SPEED SWEEP at sysclk=350MHz
  25.00 MHz → FAIL  (512 byte errors)
  22.00 MHz → FAIL  (412 byte errors)
  20.00 MHz → MARGINAL (38 byte errors)
  18.75 MHz → PASS
  15.00 MHz → PASS
  12.50 MHz → PASS
   8.00 MHz → PASS
  → SPEED THRESHOLD: passes at 18.75 MHz and below
```

### 3.5 Phase C2 — sysclk sweep at SPI=20 MHz

6 cells: 200, 250, 270, 300, 320, 350 MHz. SPI fixed at 20 MHz (proposed derate value).

Uses `clkset()` + `sd.debugOnClockChange()` (Phase 2 already validated this pattern in `SD_frequency_characterize`).

**Output:**
```
PHASE C2: SYSCLK SWEEP at SPI=20MHz
  200 MHz hp=4 → PASS
  250 MHz hp=5 → PASS
  270 MHz hp=6 → PASS
  300 MHz hp=6 → PASS
  320 MHz hp=8 → PASS
  350 MHz hp=9 → MARGINAL (12 byte errors)
  → SYSCLK CEILING (at SPI=20MHz): 320 MHz
```

### 3.6 Phase D — Card-side diagnostics (card-side branch only)

**D1. CMD13 polling (10 reads, no other commands between):**
```
PHASE D1: CMD13 STATUS POLL (10 successive reads)
  poll  1: R1=$00 ST=$08 (CC_ERROR)
  poll  2: R1=$00 ST=$08 (CC_ERROR)
  ...
  → STICKY: CC_ERROR persists across all 10 polls
  (or → CLEARS after N polls, or → INTERMITTENT)
```

**D2. Sector wear-pattern (slow-path reads, 6 sectors across address space):**
```
PHASE D2: SECTOR WEAR PATTERN (slow-path reads to isolate streamer)
  sector       0 → status=0  sig=$55AA  hash=$A3F2B891  (valid MBR)
  sector  100000 → status=0  sig=$0000  hash=$00000000  (zero readback)
  sector  500000 → status=0  sig=$0000  hash=$00000000  (zero readback)
  sector 1000000 → status=0  sig=$0000  hash=$00000000  (zero readback)
  sector 1500000 → status=-1                              (read failure)
  sector 1980000 → status=0  sig=$0000  hash=$00000000  (zero readback)
  → PATTERN: Only sector 0 returns real data; data sectors return zeros
```

**D3. Erase + write + read cycle:**
```
PHASE D3: ERASE-RECOVER CYCLE
  Target: erase block at sector 100,000 (32-sector block on this SDSC)
  Step 1: erase block → status=0
  Step 2: write known pattern (random fill, deterministic seed) → status=0
  Step 3: read back via slow-path → matches written data? YES/NO
  Step 4: read back via streamer → matches written data? YES/NO
  → CONCLUSION: erase recovers the block / erase does not recover the block
```

**Aggregate output for Phase D:** D1 + D2 + D3 combined.

### 3.7 CANNOT_REPRODUCE branch (Phase A's both-real outcome)

Run a 10-iteration retry loop at default settings:
```
RETRY LOOP: 10 successive sector-0 reads at default settings
  iter  1: streamer=PASS slowpath=PASS
  iter  2: streamer=PASS slowpath=PASS
  ...
  → STABLE: 10/10 iterations passed; original failure not reproduced
```

If any iteration fails, escalate to Phase B + C as in DRIVER_SIDE branch.

### 3.8 Final report block

After all phases run, emit a final summary block for easy scanning:

```
=== MACCA DIAGNOSTIC v1 SUMMARY ===
CARD: SanDisk_SU01G_8.0_006CD5B2_200706 (SDSC, June 2007)
PROFILE: eraseBlock=32 capacity=1982464 readTO=1500ms writeTO=24000ms maxSpi=25MHz
SETTINGS at start: sysclk=350MHz spi=25MHz hp=7

OUTCOME: DRIVER_SIDE (streamer-specific failure at default settings)

KEY FINDINGS:
  - Slow-path reads succeed; streamer reads return all zeros at default settings
  - Phase tuning: PRE-edge / align_delay_offset=+5 produces clean reads
  - Speed margin: streamer reads succeed at 18.75 MHz and below
  - sysclk margin (at 20MHz SPI): all sysclks 200-320 MHz pass

RECOMMENDATIONS:
  - Workaround: setSPISpeed(18_750_000) after mount
  - Or: debugSetSampleMode(0) + debugSetAlignDelayOffset(5)

=== END ===
END_SESSION
```

---

## 4. File layout

```
src/micro_sd_fat32_fs.spin2
  + eraseBlockSectors()           [production API, ~5 lines + DAT field]
  + debugEraseBlock(start_sector) [SD_INCLUDE_DEBUG, ~40 lines + worker dispatch]
  + parser update for csd_sector_size [~3 lines in parseTimeouts]

src/regression-tests/isp_rt_utilities.spin2
  + cacheCardProfile(p_sd)        [~15 lines + VAR fields]
  + safeTestRegionStart()         [~10 lines]
  + nonAdjacentSectors(count, p_dest) [~15 lines]
  + blockAlignedRange(count)      [~10 lines]
  + cardAdjustedTimeoutMs(base_ms) [~5 lines]
  + profileReport()               [~10 lines]

diagnostic-tests/SD_macca_diagnostic.spin2
  NEW FILE, ~400-500 lines
  - go() entry point
  - runPhaseA() / runPhaseB() / runPhaseC1() / runPhaseC2() / runPhaseD()
  - reporting helpers
  - branch dispatcher
```

Total new code:
- Driver: ~50 lines (mostly debugEraseBlock + getter)
- Test utilities: ~70 lines
- Test program: ~450 lines

---

## 5. Open design questions

1. **Output format — interleaved or end-block?** I went with interleaved per-phase output above (each phase emits its results as it runs). Alternative is a single structured block at the end. **Interleaved is safer if a phase hangs** (we still see the prior phases' output); the final summary block is a digest of what already streamed.

2. **Phase B matrix: 3×5 = 15 or 2×5 = 10?** Skipping AUTO and just running PRE/ON gives 10 cells; AUTO is what default is so we'd already know AUTO from Phase A. **I lean to 2×5=10** — saves ~10s and AUTO is redundant with Phase A's failure result.

3. **Phase C1 speeds:** 25, 22, 20, 18.75, 15, 12.5, 8 MHz — is 7 cells right, or do we want more granularity around the suspected threshold (say, 19, 20, 21 MHz)? **I'd add 19 and 21 MHz** if the boundary turns out to be in that region; can be a follow-up if the first run shows a sharp transition.

4. **Should we add a baseline assertion at start?** E.g., "verify CID/CSD reads work" before assuming smart-pin SPI is healthy. Adds ~5s for safety. **I lean yes** — cheap insurance against a bench setup issue masquerading as a streamer problem.

5. **Erase block alignment for `safeTestRegionStart()`** — picking sector 100,000 then rounding up to next block boundary feels arbitrary. Should we instead pick `cardSizeSectors() / 4` rounded to a block? **I lean toward keeping 100,000 as base** — well past FAT32 metadata on any reasonable card, and block-rounded keeps it predictable.

6. **For macca's specific test, do we want to also probe pre-v1.5.1 behavior?** That would require him to compile a separate pre-Phase-1.5 binary. **I lean no** — this diagnostic is about characterizing his card under v1.5.1; comparing to pre-v1.5.1 is a separate question.

---

## 6. Implementation order

1. Add `eraseBlockSectors()` to driver (production)
2. Add `debugEraseBlock()` to driver (SD_INCLUDE_DEBUG, worker-routed)
3. Add card-aware helpers to `isp_rt_utilities.spin2`
4. Build `SD_macca_diagnostic.spin2`
5. Compile-test (no hardware needed for compile-validation)
6. Confirm with a freshly-mounted SDHC card on dev hardware (negative control: should produce CANNOT_REPRODUCE outcome)
7. Ship to macca

Steps 1-5 can all happen on dev machine with no hardware required. Step 6 is the smoke test before we send to macca.

---

## 7. What this validates beyond macca

- The card-aware test infrastructure works end-to-end on a real failing case.
- Failure attribution (driver vs card) becomes clean and automatic.
- The structured-output convention is exercised (we'll see if it's actually parseable when we look at his result log).
- The branching-test pattern proves out — if it works here, retrofit-to-existing-tests gets a working template.
