# Driver V3 Regression Analysis

**Date**: 2026-02-15
**Status**: In Progress — Root cause analysis phase
**Backup**: `src/micro_sd_fat32_fs.spin2.backup-20260215-*` (pre-investigation snapshot)

---

## 1. Problem Statement

After making changes to `micro_sd_fat32_fs.spin2`, a subset of SD cards that previously passed all regression tests now fail. Passing cards are budget/older spec (SD 3.x), failing cards are name-brand/newer spec (SD 5.x/6.x).

## 2. Cards Tested

| Card | Identity | SD Spec | Pass Rate | Result |
|------|----------|---------|-----------|--------|
| Card 2 | Gigastone ASTC 8GB | SD 3.x | 256/256 (100%) | PASS |
| Card 6 | Budget OEM SD16G 16GB | SD 3.x | 236/236 (100%) | PASS |
| Card 3 | SanDisk SA16G 16GB industrial | SD 5.x | 192/236 (81%) | **FAIL** |
| Card 4 | Lexar MSSD0 64GB | SD 6.x | 178/236 (75%) | **FAIL** |

## 3. Changes Made to Driver (uncommitted diff vs last commit)

~700 lines changed across 5 categories:

### 3a. CRC Retry Loop in readSector (MAJOR)
- Wraps entire read (CMD17 + token wait + streamer + CRC check) in `repeat attempt from 1 to 3`
- CRC validation now ALWAYS performed (was gated by `diag_crc_enabled`)
- CRC mismatch triggers retry (deselect card, re-send CMD17, re-read)
- After 3 failed attempts, returns -1 (hard error)
- Pre-computed streamer constants moved outside loop

### 3b. CMD13 Demoted to Warning — BUG (4 locations)
All four CMD13 call sites demoted from fatal to informational:

| Location | Line | Should Be | Currently Is |
|----------|------|-----------|-------------|
| `readSector` | 5209 | Fatal → return -1 | Warning → continues |
| `writeSector` | 5515 | Fatal → return false | Warning → continues |
| `readSectors` | 5358 | Fatal → return 0 | Warning → returns sectors_read |
| `writeSectors` | 5636 | Fatal → return 0 | Warning → returns sectors_written |

CMD12 (stop transmission) failure in readSectors also silently swallowed (line 5352).

**Why this is wrong**: CRC validates wire transfer integrity. CMD13 validates card internal state (ECC errors, programming failures, address errors). They check different things. Ignoring CMD13 means the card can accumulate unacknowledged errors. Some cards clear error bits when CMD13 reads them — skipping this means errors pile up.

### 3c. Error Checking at ~30 readSector Call Sites (CORRECT)
All callers now check `if readSector(...) < 0` and handle errors. This is the RIGHT change — callers should always check return codes. Errors now properly propagate through:
- `do_mount`, `do_close`, `do_create`, `do_read_h`, `do_write_h`
- `do_seek_h`, `do_sync_h`, `do_read_dir_h`, `do_read`, `do_seek`
- `do_newdir`, `do_delete`, `do_freespace`, `do_sync`, `do_rename`
- `do_set_vol_label`, `do_movefile`, `do_readdir`, `readVBRRaw`
- `attemptHighSpeed`, `updateFSInfo`, `countFreeClusters`
- `searchDirectory`, `debugDumpRootDir`, `readFat`, `allocateCluster`
- `readNextSector`, `followFatChain`, `displayFAT`

### 3d. CMD24 R1 Response Validation (NEW)
- Checks fatal R1 bits ($64): illegal cmd, address err, parameter err → return false
- Logs stale R1 bits ($1B): idle, erase reset, CRC, erase seq → proceed with warning

### 3e. Write Diagnostics Infrastructure (NON-BEHAVIORAL)
- New DAT variables: `diag_write_result`, `diag_write_r1`, `diag_write_dresp`, `diag_write_sector`
- New PUB: `getWriteDiag()`, `getCRCRetryCount()`
- Write timeout increased from 250ms to 500ms for SDHC/SDXC
- Data-response token decoded: CRC error ($0B), write error ($0D), etc.
- Debug output in writeSector showing buffer state before streamer TX

## 4. Failure Patterns Observed

### 4a. Failure Mode A — CRC False Positives (single-sector reads)

Evidence from `file_ops_tests` on Card 4 (Lexar MSSD0):
```
DIAG: readSectorRaw(0) returned -1     ← readSector failed (CRC mismatch after 3 retries)
DIAG: MBR bytes 510-511: $55 $AA       ← But buffer data is CORRECT!
DIAG: MBR signature OK!
```

Data is correct in the buffer, but `readSector` returned -1 because CRC didn't match. This cascades:
- `searchDirectory` → fails (readSector returns -1)
- `openFileRead` → returns E_FILE_NOT_FOUND
- Test fails

Affected tests (Card 4): file_ops (14/22 pass), read_write (15/29), seek (36/37), directory (25/28), multihandle (8/19)

### 4b. Failure Mode B — 1-Bit Right Shift (data corruption)

From `raw_sector_tests` on Card 4:
```
Expected DEADBEEF → got $EF $56 $DF $77   (every byte right-shifted by 1 bit)
Expected $55 $AA  → got $2A $D5            (same 1-bit shift)
```

From `multiblock_tests` on Card 4:
```
Expected $01 $02 $03 $04 $05
Got      $00 $81 $01 $82 $02   (1-bit right shift with bit carry across bytes)
```

Bit-level verification: $55 (01010101) → $2A (00101010) = right-shift by 1, carry-in 0.
$AA (10101010) → $D5 (11010101) = right-shift by 1, carry-in 1 (from $55 LSB).

### 4c. Multi-Block Corruption Differs by Card

**Card 4** (Lexar 64GB):
- Test 1 (CMD25 write + CMD18 read): FAIL, 1533 mismatches from byte 1
- Test 2 (CMD25 write + CMD17 reads): FAIL, 1022 mismatches from sector 3
- Test 3 (CMD24 writes + CMD18 read): **PASS**
- → CMD25 (multi-write) introduces corruption

**Card 3** (SanDisk SA16G):
- Test 1 (CMD25 write + CMD18 read): FAIL, 1488 mismatches from byte 512
- Test 2 (CMD25 write + CMD17 reads): FAIL, 992 mismatches from sector 2
- Test 3 (CMD24 writes + CMD18 read): **FAIL**, 3472 mismatches from sector 1
- Test 4a (count=1): **FAIL**, 496 errors
- → Both multi-block write AND read paths corrupted

### 4d. Mount Always Passes

Mount tests pass on all cards (21/21). This means MBR, VBR, FSInfo sector reads succeed during mount. Failures occur in subsequent operations.

## 5. Root Cause Analysis

### Bug 1 (CONFIRMED): CMD13 Demoted to Warning

**This is incomplete implementation.** The project goal was to make the driver properly check all return codes. CMD13 was demoted in all 4 locations instead.

**Impact**: Card internal errors (ECC failures, programming errors, address errors) go undetected. Error state accumulates. Subsequent operations (especially multi-block CMD18/CMD25) encounter a card in an error state, producing corrupt data.

**Fix**: Restore CMD13 as fatal in all 4 locations:
- `readSector`: `if checkCardStatus() < 0 → return -1`
- `writeSector`: `if checkCardStatus() < 0 → return false`
- `readSectors`: `if checkCardStatus() < 0 → return 0` (or negative error code)
- `writeSectors`: `if checkCardStatus() < 0 → return 0` (or negative error code)

Also restore CMD12 failure handling in readSectors.

### Bug 2 (HYPOTHESIS): CRC False Positives — WRFAST FIFO Race

After `waitxfi`, the streamer has finished reading SPI data, but the WRFAST FIFO may not have fully drained to hub RAM. CRC computation `calcDataCRC(p_buf, 512)` runs immediately after and reads from hub RAM — potentially before the last bytes are flushed.

- **Old code**: CRC mismatch was just logged, data accepted → tests passed (data actually correct)
- **New code**: CRC mismatch triggers retry → 3 retries all hit same race → returns -1 → caller error

**Why card-dependent**: Faster card controllers (SanDisk SD 5.x, Lexar SD 6.x) complete SPI transfers earlier, leaving less time between `waitxfi` and WRFAST FIFO flush. Budget cards (Gigastone SD 3.x) have slower response latency, providing natural flush time.

**Evidence**: file_ops_tests shows readSectorRaw(0) returning -1 (CRC fail) but buffer having correct data ($55 $AA).

**NOTE**: Any fix for this must be CLOCK-SPEED INDEPENDENT. The P2 runs at 350 MHz and 250 MHz (and potentially lower). A fixed `waitx` delay would scale wrong at different clock speeds. The fix must use P2 architectural mechanisms (hub synchronization, FIFO status, etc.) rather than timed delays.

**Investigation needed**: Look up P2 WRFAST FIFO drain behavior in P2KB. Is there a way to ensure WRFAST completion without a timed delay?

### Bug 3 (HYPOTHESIS): Streamer Bit Alignment — Card Timing Dependent

The 1-bit right shift pattern suggests the streamer's sampling point (`init_phase := $4000_0000`) doesn't work for all cards. Cards with different CLK-to-MISO propagation delays may need different phase alignment.

**This is a deeper hardware-level issue** that may be exposed more frequently when CMD13 errors aren't caught (Bug 1), allowing the driver to continue operating with a card in an error state.

## 6. Fix Priority

1. **P0 — Restore CMD13 as fatal** (Bug 1): This is definitely wrong and may fix multi-block corruption by catching card errors before they accumulate.

2. **P1 — Investigate WRFAST race** (Bug 2): Research P2 WRFAST FIFO behavior. If confirmed, find a clock-independent synchronization mechanism.

3. **P2 — Investigate bit alignment** (Bug 3): May resolve itself once CMD13 is restored. If not, investigate with logic analyzer.

## 7. What NOT to Change

- **Keep error checking at call sites (3c)**: This is correct. All callers should check readSector/writeSector return codes.
- **Keep CRC retry concept**: CRC validation and retry on mismatch is good practice — IF the CRC computation is reliable (depends on Bug 2 resolution).
- **Keep write diagnostics (3e)**: These are valuable for debugging.
- **Keep CMD24 R1 validation (3d)**: Needs review but the concept is sound.

## 8. Fix Round 1: CMD13/CMD12 Error Handling + recoverToIdle

**Date**: 2026-02-15
**Goal**: Restore proper error handling at all 6 error-swallowing sites. Add recovery helper for dangerous desync cases.

### Design Principle: Lockstep State Machine

The SD card has its own SPI state machine. Our driver is the other half. They must stay in lockstep. Every command, response, and token — both sides must agree on what state they're in. If they lose sync, nothing works until we re-establish it.

**Returning an error is necessary but not sufficient.** Before returning to the caller, we must ensure the card's state machine is back in idle. Otherwise the caller's next operation (retry or different command) hits a card that's still in a previous state.

### Card State at Each Error Site

| # | Site | Card State | Recovery Needed |
|---|------|-----------|-----------------|
| 1 | readSector CMD13 | Idle (read done, CMD13 exchanged) | No — bus clean |
| 2 | writeSector CMD13 | Idle (write done, busy cleared, CMD13 exchanged) | No — bus clean |
| 3 | readSectors CMD12 fail | **DATA_OUT** — still transmitting blocks | **YES — recoverToIdle** |
| 4 | readSectors CMD13 | Idle (CMD12 succeeded, CMD13 exchanged) | No — bus clean |
| 5 | writeSectors busy timeout | **PROGRAMMING** — MISO held low | **YES — recoverToIdle** |
| 6 | writeSectors CMD13 | Idle (stop sent, busy cleared, CMD13 exchanged) | No — bus clean |

### recoverToIdle() Design

For sites 3 and 5, the card is actively out of sync. Recovery uses the SPI escape hatch: CS deassert aborts any pending operation.

```
PRI recoverToIdle() : result
  pinh(cs)                        ' CS HIGH — abort any pending operation
  repeat 10
    sp_transfer_8($FF)            ' 80 clocks with CS high — let card release bus

  ' VERIFY: card must have released MISO (pulled high when CS deasserted)
  if pinr(miso) == 0              ' Card still holding MISO low
    repeat 20
      sp_transfer_8($FF)          ' 160 more clocks — extended recovery
    if pinr(miso) == 0
      debug("recoverToIdle FAILED: card holding MISO after 240 clocks")
      return -1                   ' Card stuck — caller must handle

  return 0                        ' Card released bus — back to idle
```

Key design points:
- **CS deassert** is the SD spec mechanism for aborting any SPI operation
- **80 clocks** gives the card time to finish any partial byte and release MISO
- **Verify MISO high** confirms the card actually released the bus (not just hoping)
- **Extended clocking** if first attempt fails — some cards need more time
- **Returns status** — caller knows if recovery succeeded or card is stuck
- **Clock-speed independent** — no `waitx` delays, uses SPI clock cycles instead

### Changes Made

| # | File:Line | Change | Recovery |
|---|-----------|--------|----------|
| 1 | readSector:5209 | Warning → `return -1` | None (bus clean) |
| 2 | writeSector:5515 | Warning → `return false` | None (bus clean) |
| 3 | readSectors:5351 | Warning → `recoverToIdle()` + `return 0` | **recoverToIdle** |
| 4 | readSectors:5358 | Warning → `sectors_read := 0` + return | None (bus clean) |
| 5 | writeSectors:5629 | Warning → `recoverToIdle()` + `return 0` | **recoverToIdle** |
| 6 | writeSectors:5636 | Warning → `sectors_written := 0` + return | None (bus clean) |
| 7 | New helper | `recoverToIdle()` with MISO verification | — |

### Verification Result — Card 6 (Budget OEM SD16G 16GB)

**236/236 (100%) — No regressions.** All 10 test suites pass identically to before the fix.

| Test Suite | Result |
|-----------|--------|
| mount_tests | 21/21 |
| format_tests | 46/46 |
| file_ops_tests | 22/22 |
| read_write_tests | 29/29 |
| directory_tests | 28/28 |
| seek_tests | 37/37 |
| multicog_tests | 14/14 |
| multihandle_tests | 19/19 |
| multiblock_tests | 6/6 |
| raw_sector_tests | 14/14 |

**Conclusion**: The working card never triggered CMD13 errors, confirming these code paths are exercised only by cards with genuine internal issues. The fixes don't affect cards that are operating normally.

**Next step**: Test against a failing card to see if CMD13 restoration changes the failure pattern.

### Fix Round 1 Results on Failing Card — Card 3 (SanDisk SA16G 16GB Industrial)

**Date**: 2026-02-16
**Card formatted**: Yes, using SD_format_card utility before testing

| Test Suite | Result |
|-----------|--------|
| format_tests | SUCCESS |
| mount_tests | 13/21 (all mount attempts FAIL) |
| file_ops_tests | FAIL (cannot mount) |
| read_write_tests | FAIL (cannot mount) |
| directory_tests | FAIL (cannot mount) |
| seek_tests | FAIL (cannot mount) |
| multicog_tests | FAIL (cannot mount) |
| multihandle_tests | FAIL (cannot mount) |
| multiblock_tests | FAIL (cannot mount) |
| raw_sector_tests | 13/14 (1 fail — MBR signature bit-shifted) |

## 9. Root Cause: Mount Failure is NOT CMD13 or CRC

### Instrumented Diagnostics (mount test with SD_INCLUDE_DEBUG)

```
DIAG: error()=-22                        ← E_NOT_FAT32 (not E_IO_ERROR!)
DIAG: lastCMD13=$0 lastCMD13Error=$0     ← CMD13 is CLEAN — no card error
DIAG: CRC match=1 mismatch=0 retry=0    ← CRC passed first time, zero retries
DIAG: recvCRC=$7E22 calcCRC=$7E22        ← Perfect CRC match
DIAG MBR: sig=$2A $D5                    ← Should be $55 $AA (bit-shifted!)
DIAG MBR: part1 type=$06                 ← Should be $0C (bit-shifted!)
DIAG MBR: lba=$00,$00,$10,$80            ← Should be $00,$00,$20,$00
```

### What Happened

1. **Format wrote bit-shifted MBR**: The format utility's `writeSector(0, MBR)` call shifted all data right by 1 bit. The format utility detected this: `MBR readback: sig=$D52A type=$06 start=4_224 *** MBR READBACK MISMATCH!`
2. **Format continued anyway**: Despite detecting the mismatch, the format utility continued writing VBR, FSInfo, FATs, and root directory.
3. **VBR was written correctly**: Format readback showed `jump=$EB OEM=$50 bps=512 spc=16 sig=$AA55` — all correct. So the bit shift is **intermittent** (first write after init?).
4. **readSector reads shifted data correctly**: CRC matches perfectly because the card CRC'd the shifted data it received. CRC validates wire integrity — it confirms the data matches what's on the card, but doesn't know the on-card data is wrong.
5. **do_mount parses shifted MBR**: Partition type is $06 (shifted $0C), doesn't match $0B or $0C → returns E_NOT_FAT32.

### Why This is NOT a CMD13 Issue

- CMD13 returns $0000 (R1=0, STATUS=0) — card has no internal errors
- CRC match count increases with each read — all reads succeed
- The error is in the DATA itself (on-card corruption from a write), not in the communication protocol

### Bug Classification Update

| Bug | Status | Impact |
|-----|--------|--------|
| Bug 1: CMD13 demotion | **FIXED** (Round 1) | Was masking errors, now properly fatal |
| Bug 2: CRC false positives | **NOT CONFIRMED** | Zero CRC mismatches observed; WRFAST race may not exist |
| Bug 3: Bit alignment | **CONFIRMED — in writeSector TX path** | First write after init shifts data right 1 bit |

### Bug 3 Details: writeSector TX Streamer Bit Shift

**Pattern**: The FIRST writeSector call after card initialization writes data shifted right by 1 bit. Subsequent writes are correct (VBR written after MBR was correct).

**Evidence**:
- Format MBR write (1st write): shifted
- Format VBR write (2nd write): correct
- Raw sector writes to sectors 100,000-100,004: all correct

**Card-dependent**: Budget cards (SD 3.x) may have enough timing margin to tolerate the shift. Higher-spec cards (SD 5.x/6.x) with tighter timing show the corruption.

**Next investigation**: Examine the writeSector TX streamer configuration. The initCardOnly warmup reads sector 0 (settles RX streamer), but does NOT exercise the TX streamer. The first TX streamer operation may have an unsettled phase.

---

*Analysis will be updated as investigation progresses.*
