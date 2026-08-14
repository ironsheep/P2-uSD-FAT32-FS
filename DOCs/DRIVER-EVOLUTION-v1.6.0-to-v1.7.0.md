# Defect Analysis: v1.6.0 through v1.7.0

**Technical reference for the defects fixed across three releases — mechanism, evidence, fix, and verification for each.**

*P2-uSD-FAT32-FS · v1.7.0, 2026-08-12*

---

## Scope and method

This document covers defects fixed in v1.6.0, v1.6.1 and v1.7.0, in the driver and in the regression suite that certifies it. Each entry states: how the defect presented, the mechanism, why existing checks did not detect it, the fix, and how the fix was verified.

Locations are given by method name. Line numbers drift; method names have been stable across these releases. Source references are to `src/micro_sd_fat32_fs.spin2` unless stated.

Detection method is recorded per defect because the three methods used had substantially non-overlapping yields:

| Method | Defects attributed |
|---|---|
| Read-through audit of fallible operations | §3.1 (22 of 24 findings), §2.1, §2.2 |
| `tools/check_error_handling.sh` — mechanical scan for unconsumed status | §3.1 (`do_rename`, `do_movefile`) |
| Deliberate fault injection into error paths | §3.1 (5 later findings), §3.4 |
| Regression sweep failure + static attribution | §5.1, §5.2, §4 |

---

## 1. Write-path timing lineage

Relevant to §4. The write burst's timing has been modified four times.

**`RDFAST` sat between the SCK reset and `XINIT` in every release from v0.9.3 through v1.6.1** — verified by walking the tags. None of the changes below introduced that; they moved the phase within a window that already had the problem.

| Release | Change |
|---|---|
| v1.3.2 | Streamer write timing corrected for power-of-2 SPI half-periods (hp=4, hp=8) via NCO frequency adjustment |
| v1.5.1 | Read path: sampling mode adapts to sysclk-to-SCK ratio; bulk reads no longer begin sampling before the card drives data |
| v1.5.2 | Write path: removed the explicit `WAITX align_delay` from the write burst, relying on the incidental delay of surrounding instructions |
| v1.7.0 | `SETXFRQ`/`RDFAST` hoisted above the SCK reset; explicit `WAITX tx_align_delay` restored with a measured value (§4) |

The v1.5.2 change converted an explicit timing guarantee into an implicit one, and so moved the phase — but the window itself predates it by fourteen releases. §4 is the failure of that implicit guarantee, observed once.

---

## 2. v1.6.0 — write-path corruption

Both defects occur only when **rewriting an existing file**. Create-once, write-front-to-back workloads — including sector-aligned append logging — were never affected, which is why five releases shipped without either surfacing.

### 2.1 Cross-boundary overwrite truncated the FAT chain

**Presentation.** `openFileWrite()` + `seekHandle()` back into the file + `writeHandle()` spanning a cluster boundary. Write returns success. Data past the rewritten region is unreadable; free space is reduced.

**Mechanism.** At the cluster boundary the write path allocated a new cluster instead of following the file's existing chain. The remainder of the original chain was left allocated but unreferenced by any directory entry.

**Detection footprint.** Structural. The orphaned chain is a lost-cluster condition that `SD_FAT32_audit` reports and `SD_FAT32_fsck` reclaims. The space is recoverable; the file's tail content is not.

**Fix.** At a cluster boundary, follow the chain; allocate only at genuine end-of-chain. The invariant is stated in `DOCs/SD-CARD-DRIVER-THEORY.md` § *Write Path — Follow or Allocate*.

**Verification.** `SD_RT_fatchain_tests` group A. The suite is constructed to fail on the pre-fix driver and pass after.

### 2.2 Mid-sector append zero-filled existing bytes

**Presentation.** `openFileWrite()` + `writeHandle()` on a file whose length is not a multiple of 512. The bytes already occupying the final partial sector become zeros.

**Mechanism.** Appending into a partially-filled sector requires read-modify-write: load the existing sector, merge new bytes at the offset, write back. The load was skipped and a fresh buffer written.

**Detection footprint.** **None.** The directory entry, cluster chain and file length are all correct and mutually consistent; only data bytes are wrong. No filesystem-level tool can detect this, because there is no structural inconsistency to detect. Remedy is verification against a known-good copy.

**Fix.** Load the existing final sector before merging.

**Verification.** `SD_RT_fatchain_tests` group B.

### 2.3 Write failures returned success

**Presentation.** Writes to a full card, a failing card, or an unresponsive card could return success.

**Fix at v1.6.0.** Corrected at the observed sites only: writing, closing, syncing, unmounting, deleting.

**Residual.** The pattern was not audited systematically until v1.7.0, which found 24 further instances (§3).

---

## 3. v1.7.0 — error reporting

Source audit: `DOCs/Analysis/ERROR-REPORTING-AUDIT-2026-07-31.md`. 24 findings, 21 classified user-affecting.

### 3.1 Unchecked metadata writes

Nine findings sharing one shape: a method performs an ordered sequence of card writes that together change filesystem metadata, checks none of them, and assigns `status := SUCCESS` unconditionally. Because the writes are ordered and interdependent, a partial sequence leaves the volume inconsistent rather than merely unchanged.

| Method | Unchecked write | On-card state after a failed write |
|---|---|---|
| `allocateCluster()` | four FAT writes: FAT1/FAT2 for the new cluster, FAT1/FAT2 for the chain link | cluster reported allocated to the caller, FAT still marks it free → the next allocation scan returns the same cluster to a second file; two files share one chain |
| `do_delete()` | directory-entry write, followed unconditionally by `freeClusterChain()` | entry live, clusters free → file appears to exist; its clusters are reallocated; reads return another file's data. Return value was `freeClusterChain()`'s status, which succeeded |
| `do_movefile()` | source-entry delete write (destination entry already written) | one cluster chain owned by two live directory entries in two directories; deleting either frees clusters the other references |
| `do_newdir()` | parent-entry write and `.`/`..` cluster write | directory creation that wrote nothing returns SUCCESS |
| `do_rename()` | rewritten 8.3 entry — the entire product of the operation | rename returns SUCCESS, file retains its old name |

`do_newdir()` performed read-back verification of both writes and routed the results to `DEBUG` only. The driver ships `DEBUG_MASK = 0`, so the verification executed, established that the write had failed, and emitted the result to a disabled channel.

**Related — unvalidated cluster argument.** `allocateCluster()` returns `E_DISK_FULL` (-60) or `E_IO_ERROR` (-7) on failure. Two call sites in `do_newfile()` and `do_newdir()` passed the result to `clearCluster()` without a sign check, so `clearCluster(-60)` computed `clus2sec(-60)` and issued `sec_per_clus` sector writes at the resulting address. `do_create()` already carried the correct guard; it had not been applied to the directory-creation paths.

**Fix.** Every write site consumes its status. `do_delete()` sets `E_IO_ERROR` and leaves the chain intact rather than freeing clusters whose entry is still live — the recoverable ordering. `clearCluster()` and `readNextSector()` gained return values (`PRI clearCluster(cluster) : status`, `PRI readNextSector(buf_type) : status`), which is what made the guards expressible.

**Detection.** `do_rename()` and `do_movefile()` were not found by the read-through audit. They were found by `tools/check_error_handling.sh` on its first execution.

**Verification.** `SD_RT_error_injection_tests` group *Tier-1 Silent Corruption Paths*, using `setTestFailSector()` / `setTestFailWriteAfter()` to fail the specific write under test. `check_error_handling.sh` runs as a gate and reports clean across all 47 sources.

### 3.2 `searchDirectory()` conflated I/O failure with not-found

**Presentation.** Nine public APIs reported card read errors as `E_FILE_NOT_FOUND`.

**Mechanism.** `searchDirectory()` returned the same value for "no matching entry" and "directory sector could not be read". 14 call sites consumed that single value.

**The failing-open instance.** The three create paths (`do_create`, `do_newfile`, `do_newdir`) use the search as an existence check and read a negative result as "name is available". A read error during that check therefore caused a create to write a **second** directory entry and allocate a **second** cluster chain for a file that already existed: two entries, two chains, one name.

**Fix.** A separate `search_io_status` carries the I/O outcome. Call sites resolve it ahead of the not-found case:

```spin2
status := (search_io_status < 0) ? search_io_status : E_FILE_NOT_FOUND
```

The existence check now fails **closed**.

**Verification.** `SD_RT_error_injection_tests` group *Search Failure Is Not Not-Found*.

### 3.3 Short read indistinguishable from end of file

**Presentation.** `readHandle()` returned a byte count. A read that failed on its first sector returned 0, identical to end of file, so a file on a failing card was processed as a complete file.

**Fix (breaking).** `readHandle()` returns its error code when nothing at all was transferred; a partial transfer still returns the positive partial count. `0` therefore means end of file and nothing else. `handleError(handle)` returns the reason a read or write came up short. `writeHandle()` received the same treatment.

**Migration impact.** A loop terminating on `n =< 0` or `n > 0` is unaffected. A loop terminating only on `n == 0` will not terminate on a persistent failure. Documented in `DOCs/MIGRATION-GUIDE-v1.7.0.md` §9.

### 3.4 Background flush had no reporting channel

**Presentation.** No mechanism existed by which a caller could learn that an automatic flush had failed.

**Mechanism.** The driver flushes buffered writes after `IDLE_FLUSH_MS` (200 ms) of idle. `do_idle_flush()` is initiated by the worker cog itself — there is no mailbox transaction and no caller to return a status to. It discarded the results of both `do_sync_h()` and `updateFSInfo()`. For an application that writes without explicit syncs, this is the path its data takes to the card.

**Fix.** The failure is retained in driver state and exposed through new public accessors `lastFlushError()` and `clearFlushError()`. This is the one finding in the group whose fix required new API rather than a corrected return value, because the defect was structural.

**Verification.** `SD_RT_error_injection_tests` group *A Background Flush Failure Reaches Somebody*. These tests wait out real 200 ms idle windows and are correspondingly slow.

### 3.5 Return-value encoding collision

**Mechanism.** `eofHandle()` and `isFileContiguous()` returned `TRUE`, `FALSE`, or a negative error code. In Spin2 `TRUE` is `-1`; `E_TIMEOUT` is also `-1`. "At end of file" and "the card timed out" were the same 32-bit value.

No correct call form existed. `if sd.eofHandle(h)` treated every error as end-of-file; `if sd.eofHandle(h) < 0` treated the normal at-EOF case as an error.

**Fix (breaking).** Both return booleans only — `PUB eofHandle(handle) : is_eof`, `PUB isFileContiguous(p_path) : bContiguous`. On a failed query `eofHandle()` returns `TRUE` (a read-until-EOF loop terminates rather than spinning on an unresponsive card) and `isFileContiguous()` returns `FALSE` (a truthy error previously read as "yes, contiguous" and would let a caller skip a needed compaction). `error()` distinguishes.

### 3.6 Other findings in the block

| Finding | Mechanism | Fix |
|---|---|---|
| `error()` sticky since boot, documented as per-operation | only failures wrote the slot | every command-issuing method records its outcome on both exit paths; pure accessors exempt so a diagnostic call cannot erase the error being diagnosed |
| `sync()` could not report failure | dispatcher hardcoded `pb_status := SUCCESS`; `do_sync()` had no return value | `do_sync()` returns real status and runs the full unmount-grade flush (`do_sync_all()` + `updateFSInfo()`) |
| `stop()` discarded the unmount result | `do_unmount()`'s status computed then dropped, worker cog halted immediately after | `PUB stop() : status` |
| worker stack-guard violation discarded | guard checked after every command; result reached `DEBUG` only, `status` unaltered | violation surfaces as `E_STACK_OVERFLOW` (-26) through `error()`; `getResult()`/`cancelAsync()` report it too |
| `readFat()` returned stale data on failure | returned a valid pointer to the previous sector's contents | failure reported; callers consume it |
| `freeSpace()` returned partial count as fact | accumulated count returned when the FAT scan aborted | returns 0 with `error()` set |
| three capability queries conflated "no" with "couldn't ask" | `attemptHighSpeed()`, `checkCMD6Support()` and one other returned bare booleans | specific failure codes; a card lacking high-speed support is distinguished from a failed query |
| async result retrieval unowned | `getResult()`/`cancelAsync()` did not verify the calling cog, and released the API lock as their last act — so such a call released a lock it never held | cog ownership enforced |

### 3.7 Self-referential verification in `attemptHighSpeed()`

Listed separately because the mechanism recurs in §4.

`attemptHighSpeed()` verified a 50 MHz switch by writing a sector at the **unverified** speed and comparing the result against itself. The comparison could not detect the failure it existed to catch, and it wrote to the card at a speed not yet known good.

**Fix.** The switch is verified by re-reading a sector captured at the known-good speed and comparing against that capture. Nothing is written at an unverified speed.

---

## 4. v1.7.0 — write-path phase fault: sectors stored one bit late

### 4.1 Presentation

Failures appeared in suites that had been green, after commits that touched no timing code. **The failing set was not stable between sweeps**, which is the most diagnostic feature of the presentation and the reason it resisted attribution as long as it did.

Per-suite results, read directly from the sweep transcripts on card `$0000_0F14`:

| Sweep | `speed` | `crc_diag` | `subdir_ops` | `cogcwd` |
|---|---|---|---|---|
| `sweep_card2b_260806` | 15/0 | 14/0 | 18/0 | **0 pass / 5 fail** |
| `sweep_card2b_260807_cleaneach` | **13/2** | **11/3** | **6/12** | 5/0 |
| `sweep_card2b_260807_nogate` | 0/0 (no result) | **11/3** | 0/0 (no result) | 5/0 |

The four suites never failed together in one run. `cogcwd` failed on 08-06 while the other three passed; the other three failed on 08-07 while `cogcwd` passed. Each sweep is a different build.

Symptom signatures where the transcripts record detail: `subdir_ops` — file created and handle valid, then `openFileRead` and `deleteFile` both return -40; `speed` and `crc_diag` — `Pattern mismatch at 0: got $0`; `cogcwd` — written data reads back 0. The shared signature is **data written does not read back, or the file cannot be found afterward**.

**Bounding fact holding across all three sweeps.** Not a general write failure: `read_write` 49/0, `file_ops` 26/0, `directory` 30/0, `seek` 37/0, `volume` 31/0 throughout.

A failing set that migrates between builds is evidence for a marginal phase that some configurations lose. It is *weaker* support for a phase deterministically fixed by a build's layout than a stable per-build failing set would have been — see the unresolved attribution in §4.3.

### 4.2 Hypotheses refuted

**Stack overflow corrupting SPI pin configuration.** The memory map made this plausible — 20 bytes separate the end of the worker stack from `cs`. *(Addresses below are quoted from `POST-V161-ROOT-CAUSE-ANALYSIS.md`, which read them from a build map. They have not been re-derived for the v1.7.0 tree, where `cog_stack_end_mark` now sits between the stack and the guard; treat them as the layout at the time of that investigation.)*

| Symbol | Address | Offset past stack end |
|---|---|---|
| `COG_STACK` (160 longs) | `$00F1E` | ends `$0119E` |
| `COG_STACK_END_MARK` | `$0119E` | +0 |
| `COG_STACK_GUARD` (16 B) | `$011A2` | +4 |
| `CS` | `$011B2` | +20 |
| `MISO` | `$011BA` | +28 |
| `SPI_RX_MODE` | `$011CA` | +44 |
| `SPI_PERIOD` | `$011CE` | +48 |

Corrupting `miso`/`spi_rx_mode` produces zero reads; corrupting `spi_period` produces -7. The symptoms match.

**Refuted:** `send_command()` checks the 16-byte `$CC` guard after every command and overrides the status with `E_STACK_OVERFLOW`. An overflow reaching `cs` must first traverse all 16 guard bytes and so cannot arrive unreported. No `-26` appears in any failing run. The guard was intact while the data was corrupt.

**`entry_buffer` resolving to a wild pointer.** `entry_buffer dir_entry_t` does not appear in the map's DAT symbol list; it appears under PASM labels at the object base + 8, roughly 30 KB from its actual anonymous storage between `buf` and `vol_label`. Investigated and not the cause of these symptoms.

### 4.3 Mechanism

`DIRL`/`DRVL` on SCK resets the `P_TRANSITION` smart pin's base-period counter. Every subsequent SCK edge lands on a grid anchored at that DIR-rise (`p2kbArchSmartPin00101TransitionOutput`). `XINIT` starts the streamer, whose NCO ramps from zero at the instant it executes.

The phase between the outgoing MOSI bitstream and the clock edges latching it is therefore set entirely by the **sysclk count between `DRVL` and `XINIT`**.

`WAITX`, `XINIT` and `WYPIN` are fixed 2-clock cog operations. `RDFAST` is not: `p2kbPasm2Rdfast` documents it as `WRFAST finish + 10...17` sysclks.

Pre-fix, `RDFAST` executed between `DRVL` and `XINIT`. The data-to-clock phase was therefore **not a compile-time constant**. That is the whole of the established mechanism, and it is sufficient: a variable-latency instruction inside a phase-critical window breaks the timing contract regardless of what drives the variability.

**What drives the variability is not established.** `p2kbArchP2ArchitectureMentalModel` states a hub operation completes "in 2-9 clocks depending on when the COG's slot arrives" — a property of issue time. `p2kbArchHub`'s slicing section can be read as making it a property of the address requested. The two are unreconciled and neither was measured. The fix does not depend on resolving it.

**Measurement.** `pnut-ts -l` on both reproducer variants: `SD_INCLUDE_SPEED` shifts the driver's DAT symbol from `$4A1F` to `$4A43`, **+36 bytes**. That the flag correlates with failure is established. The causal path from a DAT shift to a phase change is not.

**Competing explanation, unresolved.** The shipped `tx_align_delay` at the time was **2**, the bare `WAITX` floor. §4.6's sweep later showed the failing phase is `pad ≡ 1 (mod 7)` — one phase step below 2. A nominal phase sitting one step from the cliff would flip on any small systematic offset, which would make the DAT shift a trigger without requiring address-determined latency. This is consistent with the observed instability in §4.1 and has not been discriminated from the address hypothesis by measurement.

**Effect on the losing side.** The card stores every sector one bit late, and reports success. The shmoo transcripts label this failure mode `SHIFTED-LATE`.

### 4.4 Why existing checks did not detect it

**Data-response token.** `dresp = $05` ("data accepted") establishes only that the packet framing was well-formed. SPI-mode write-CRC checking is disabled unless the host enables it with CMD59, which this driver has never sent. The token was never evidence about payload content. A card with CRC enforcement enabled would have rejected these writes.

**Read-back comparison.** The shifted bytes were what the card had stored. The read path was hardened in the v1.5.1/Phase-1.5 work and was never affected, so a read returned the stored bytes faithfully and any written-vs-read-back comparison agreed with itself. The comparison was tautological — the same structural error as §3.7.

The initial analysis read the accepted-data token as evidence of correct data at the card and consequently looked for the fault on the capture side. The fault was on the write side.

### 4.5 Fix

`SETXFRQ` and `RDFAST` are hoisted above the SCK reset at both write sites (`writeSector()`, `writeSectors()`); `WRFAST` likewise on `readSectors()`. The variable latency is spent before the phase-critical window opens.

Current write sequence, both sites:

```
SETXFRQ   xfrq                ' streamer bit rate, before SCK reset
RDFAST    #0, p_buf           ' prime FIFO -- variable-latency op lands here
DIRL      _sck                ' reset SCK: counter stops, output LOW, Y=0
DRVL      _sck                ' DIR=1 restarts base-period counter fresh
WAITX     tx_pad              ' phase pad (tx_align_delay, floor 2)
XINIT     stream_mode, #0     ' start streamer; NCO from zero, fixed offset from DRVL
WYPIN     clk_count, _sck     ' start clock, fixed offset from DRVL
WAITXFI
```

From `DRVL` onward every instruction is a fixed 2-clock cog operation, so `XINIT` sits at a compile-time-constant offset from the reset and the phase is build-independent.

**The read path's constraint differs and is not symmetric.** `readSector()` uses `FLTL`+`DIRH` rather than `DIRL`+`DRVL`, and `WYPIN` must execute before the first base-period boundary after DIR-rise or the first SCK transition slips a full half-period when hp <= 6. `WYPIN` therefore immediately follows `DIRH`, with the phase pad applied after it and `XINIT` last:

```
WRFAST    #0, p_buf
SETXFRQ   xfrq
FLTL      _sck
DIRH      _sck
WYPIN     clk_count, _sck     ' Y written 2 sysclks after DIRH, inside the first hp
WAITX     align_delay
XINIT     stream_mode, init_phase
WAITXFI
```

`readSectors()` uses `DIRL`+`DRVL` but keeps this `WYPIN`-then-`WAITX`-then-`XINIT` order.

### 4.6 Pad characterization

Tuning is only meaningful once phase is build-independent; a pad chosen while phase still moved with layout would be tuned to one binary.

Measured on SN `$0000_0F14`, P2 Edge slot, 350 MHz sysclk / 25 MHz SPI (hp=7), three runs of `SD_tx_phase_shmoo`. Transcript data, longest run (`SD_tx_phase_shmoo_260811-213419.log`, pads 2–30):

| Pad | Result |
|---|---|
| 2–7 | CORRECT |
| **8** | **SHIFTED-LATE** |
| 9–14 | CORRECT |
| **15** | **SHIFTED-LATE** |
| 16–21 | CORRECT |
| **22** | **SHIFTED-LATE** |
| 23–28 | CORRECT |
| **29** | **SHIFTED-LATE** |
| 30 | CORRECT |

Four failures at 8, 15, 22, 29; 25 passing points. All three runs agree on the failing pads. Both test patterns (A and B) fail together at every failing pad.

- Pad-to-phase is a **sawtooth of period hp**: only hp distinct phases exist regardless of pad magnitude. The proposed reason — SCK starts on the next base-period boundary after `WYPIN` while streamer start moves continuously — is an interpretation of the periodicity, not an independent measurement.
- Exactly one phase fails: **pad ≡ 1 (mod 7)**. `8, 15, 22, 29` are all ≡ 1 (mod 7); every other measured pad passes.
- Shipped default `tx_align_delay = 4`. The tool's own recommendation line reads `SUGGESTED DAT DEFAULT: 4 (band center)`, the centre of the measured contiguous passing band `2..7`. Phase 4 sits 3 steps from the failing phase going down and 4 going up; 3 is the maximum achievable minimum distance with one bad phase in seven (phase 5 ties).
- The prior default of **2** is one phase step above the failing phase. Pad 1 itself is below the `WAITX` floor and was never measured, so 2 was the lowest reachable pad — but in *phase* terms it sat adjacent to the cliff, which is the sense in which it was marginal.

`debugSetTxAlignDelay()` / `debugGetTxAlignDelay()` expose the knob under `SD_INCLUDE_DEBUG` for characterizing an unfamiliar board or socket. See `DOCs/SPI-PHASE-MARGIN-API.md`.

### 4.7 Invariance verification

**Measured 2026-08-13 on the Gigastone 64GB (`$0000_0F14`), release configuration. All 32 points CORRECT — layout invariance holds.**

`writeSectorsRaw()`/`readSectorsRaw()` pass the caller's buffer pointer through to `RDFAST #0, p_buf` / `WRFAST #0, p_buf`, so the streamer's hub address can be swept at runtime. `diagnostic-tests/SD_buffer_alignment_sweep.spin2` walks byte offsets 0,4,8..28 — eight long-aligned positions, one full 32-byte period, addresses `$0000_93F4` through `$0000_9410` — in two phases: write buffer swept to isolate `RDFAST`, read buffer swept to isolate `WRFAST`. Two patterns at each point, classified by the same bit-shift classifier `SD_tx_phase_shmoo` uses.

Every one of the 32 points returned `CORRECT`. Transcript: `tools/logs/SD_buffer_alignment_sweep_260813-155251.log`.

**What this does and does not establish.** It establishes that, post-fix, the streamer's data-to-clock phase is independent of the buffer's hub address across every long-aligned position — which is exactly what the fix claims. It does **not** retroactively confirm the withdrawn pre-fix attribution in §4.3: with `RDFAST` now outside the phase window, buffer address would not matter under either competing hypothesis, so this result cannot discriminate between them. That question stays open and unmeasured.

**Coverage this does not reach.** The single-sector path. `writeSectorRaw()` bytemoves the caller's data into the driver's internal `buf` and writes from there, so its streamer source address is fixed by the DAT layout and cannot be varied at runtime. Its layout coverage remains incidental — the regression suites' 27 top-level binaries place `buf` at 27 different addresses, all green — rather than designed.

The original acceptance test in `LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` §6 step 4 specified N ∈ {1, 2, 4, 8, 12, 36, 60} bytes of DAT displacement. That set reaches four distinct slice positions with one duplicate; the runtime sweep above reaches all eight, once each, without recompiling.

**Also confirmed, run first as the decisive fork:** a sector written by a failing build, read back by a passing build. Shifted data was present **on the card**, not introduced by the capture path — which located the defect on the write side.

## 5. Regression suite defects

The suite is the driver's certification mechanism; defects in it are recorded here on the same footing.

### 5.1 Two stack detectors sharing one address

**Presentation.** Post-v1.6.1 sweep: seven suites failing or producing no totals line. `mount(): -26 (expected 0)`, then free space 0, unmount fails, remount fails — `mount_tests` 15 pass / 16 fail.

**Mechanism.** `isp_stack_check.prepStackForCheck()` writes sentinel `$addee5e5` to `LONG[@cog_stack][STACK_SIZE]` — one long past the stack. With no gap long declared, that address *is* `cog_stack_guard[0]`, which the driver's own guard requires to be `$CC`. Two detectors demanded different values at one address. `start()` writes the guard first and the sentinel second, so the guard always lost and `checkStackGuard()` became a stuck-at-FAIL detector.

**Why it was latent.** While the violation reached `DEBUG` only, a stuck-at-FAIL detector is indistinguishable from a working one at `DEBUG_MASK = 0`. The §3.6 fix escalating the check to the caller's return status converted it into `-26` on every command.

**Attribution.** Suites failing or blank: mount, directory, multiblock, raw_sector, read_write, format, file_ops. Suites defining `SD_INCLUDE_STACK_CHECK`: directory, multiblock, raw_sector, read_write, mount, format, file_ops. Identical sets; no other suite affected.

**Fix.** Commit `569f898`. `mount_tests` 15/16 → 31/0.

### 5.2 Stale assertions against a retired contract

Three tests compared `eofHandle()`'s return value against error codes after §3.5 moved the error to `error()`. Driver correct, tests wrong.

| Site | Asserted | Actual |
|---|---|---|
| `error_handling` #12 | `E_NOT_A_DIR_HANDLE` (-93) | -1 (TRUE) |
| `multihandle` #19 | `E_INVALID_HANDLE` (-91) | -1 (TRUE) |
| `multihandle` use-after-close | `E_INVALID_HANDLE` (-91) | -1 (TRUE) |

Fixed in commit `be6169a`.

### 5.3 Unreachable-premise injection tests

`SD_RT_error_injection_tests` shipped tests that armed a failure at a point the driver never reaches. These failed on every run they had been part of. One had an unreachable premise and was rebuilt: the T36 directory boundary is now constructed by `rawFillExtDir` raw writes, which is O(sectors per cluster) and holds at every geometry.

### 5.4 Injection-suite structure

The suite's first four groups test the injector, not the driver:

| Group | Establishes |
|---|---|
| Disarmed Behavior | nothing fails when nothing is armed — no injector residue crosses groups |
| Targeted Read Failure | a named LBA fails on read, and only that LBA |
| Targeted Write Failure | a named LBA fails on write, and only that LBA |
| Arming Precision | `setTestFailWriteAfter(n)` fires on the nth write and not n±1; one-shot arms stay one-shot; `clearTestErrors()` disarms |

A failure in this suite is otherwise ambiguous between "the driver stopped reporting an error" and "the injector never armed the failure". With the first four groups green, a later red is attributable to the driver.

Fault-injection hooks are gated behind `SD_INCLUDE_TEST_HOOKS`, enabled by `SD_INCLUDE_ALL` and deliberately **not** by `SD_INCLUDE_DEBUG`, so enabling diagnostics cannot compile fault injection into a shipping binary.

---

## 6. Verification basis for v1.7.0

**Suite:** 27 suites, 574 tests, as certified at v1.7.0. <!-- doc-count: historical -->

**Certification:** two full sweeps, `tools/run_regression.sh --include-format`, each preceded by a sweep-start `fsck` and closed by a structural audit. Zero infrastructure retries.

| Card | Serial | Sectors/cluster selected by our formatter | Result |
|---|---|---|---|
| SharedOEM/Gigastone SDHC 7 GB | `$0001_B9D5` | 8 (4 KB) | 574/574, audit 23/23 |
| Gigastone ASTC SDXC 58 GB | `$0000_0F14` | 64 (32 KB) | 574/574, audit 23/23 |

**Geometry selection rationale.** A card catalog records the *factory* format, which a regression run destroys at its first reformat. What runs is whatever `isp_format_utility.spin2`'s capacity table selects: ≤8 GB → 8 sectors, ≤16 GB → 16, ≤32 GB → 32, >32 GB → 64. An earlier 7 GB + 14 GB pairing therefore ran at 8 and 16 — adjacent buckets, 2x spread. This pairing spans 8 and 64: 8x cluster-size spread, ~4x cluster count, crossing the SDHC/SDXC boundary. It is selected against the code this release changed — `writeAdvanceCluster`, `readNextSector`'s boundary advance, `allocateCluster`'s FAT sector math, `freeClusterChain`, and the fsck chain walk. Large clusters cross boundaries 8x less often against a 4x smaller FAT.

A failure appearing on one card and not the other is treated as geometry-dependent and diagnosed as such, not retried.

**Worker stack:** peak watermark 122 of 512 longs, in `SD_RT_defrag_tests`, identical on both cards. Shipped `STACK_SIZE` = 122 + 32 rounded up to a multiple of 16 = **160**.

**Static gates, all clean at the certified tree:** `check_style.sh`, `check_error_handling.sh`, `check_doc_counts.sh`, `check_doc_claims.sh`, `check_doc_api.sh`, and `run_regression.sh --compile-only --include-format` (27 suites plus 15 consumer programs).

---

## 7. Open items

| Item | State |
|---|---|
| CMD59 write-CRC enforcement | Not implemented. A conforming card with enforcement enabled would have rejected the §4 writes rather than accepting them silently. Whether the driver should optionally enable it is an open design question |
| S10 — FAT-chain reserved high bits | Mask landed at all ten read sites in v1.7.0; the deliberate-poke witness probe is deferred post-release |
| S12 — filename validation | Matching half landed (`$E5`-first-byte slots skipped when matching); input validation and the `$05`-for-`$E5` escape remain unimplemented |
| S6 — `deleteFile()` on protected files | `do_delete`'s `attributes() & ATTR_LFN` mask ($0F) shields the volume label but also catches read-only, hidden and system files, reporting an enumerable file as `E_FILE_NOT_FOUND` |
| Terminator-less full directory | Phantom-slot minting suppressed (fails closed); the error code is `E_FILE_NOT_FOUND`, which misdescribes "directory full". Directory growth on the past-EOC path is not implemented |

---

## References

| Document | Contents |
|---|---|
| `DOCs/Analysis/ERROR-REPORTING-AUDIT-2026-07-31.md` | The 24 findings, per-finding, with call sites |
| `DOCs/Analysis/LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` | §4 in full: measurements, refuted hypotheses, fix ordering |
| `DOCs/Analysis/POST-V161-ROOT-CAUSE-ANALYSIS.md` | §5.1/§5.2 attribution |
| `DOCs/Analysis/REGRESSION-COVERAGE-ANALYSIS-2026-08-10.md` | The 12-finding coverage audit |
| `DOCs/SD-CARD-DRIVER-THEORY.md` | Architecture; current streamer sequences and the phase invariant |
| `DOCs/SPI-PHASE-MARGIN-API.md` | Phase-margin diagnostic surface; sawtooth measurement |
| `DOCs/MIGRATION-GUIDE-v1.7.0.md` | Consumer-visible changes; §0 data-recovery note |
| `src/regression-tests/THEORY-OF-OPERATIONS.md` | Per-suite purpose; certification record |

---

## Appendix A — Corrections register

Claims this document previously made and has withdrawn. Kept so a reader who saw an
earlier revision, or who finds the same claim still repeated elsewhere, can tell what
changed. **Nothing here describes current driver behaviour** — the body does that.

Full working: `DOCs/Plans/2026-08-13-EVOLUTION-DOC-PROVENANCE-AUDIT.md`.

### A.1 — RDFAST's latency attributed to the buffer's hub address (2026-08-13)

**Was:** "the spread is the hub egg-beater slot wait for the buffer address's hub slice,
and slot assignment is a function of hub address"; therefore "data-to-clock phase was a
function of the driver's hub address."

**Withdrawn because:** `p2kbArchP2ArchitectureMentalModel` states the wait as "depending
on when the COG's slot arrives" — issue time, not requested address. We measured neither.
The same attribution appeared in `SD-CARD-DRIVER-THEORY.md` and in the driver's DAT
comment at `writeSector()`; both corrected, and the DAT comment now carries an explicit
instruction not to re-narrow it.

**Why it survived review:** the claim appeared in three of our own artifacts, but the DAT
comment and the sprint context note were both written *from*
`LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md`. Agreement was propagation, not corroboration.

**Retained and sufficient:** `RDFAST` has documented variable latency; it sat inside the
phase window; phase was therefore not a compile-time constant.

### A.2 — "36 bytes = 4 hub slots" (2026-08-13)

**Was:** `SD_INCLUDE_SPEED` shifts the DAT by "36 bytes = 4 hub slots."

**Withdrawn because:** `36 mod 8` was computed on a byte count. Slices are long-granular
(P2KB's "1 long per clock" / "4 bytes per clock" block-transfer rate requires it), so 36
bytes is 9 longs ≡ 1 slice. Dropped rather than corrected — the quantity was never
load-bearing. Origin `LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md:130`, which carries the
same error at line 53 (`42 ≡ 2 (mod 8)`).

**Retained:** the measurement itself — DAT symbol `$4A1F` → `$4A43`, +36 bytes.

### A.3 — Invariance sweep reported as performed (2026-08-13)

**Was:** "The driver's DAT was deliberately displaced by 1, 2, 4, 8, 12, 36 and 60 bytes
and the suites re-run at each: all pass."

**Withdrawn because:** that is the *plan* at `LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md`
§6 step 4 ("the actual acceptance test … All must pass"), not a result. No transcript
exists. The same claim had propagated to `SD-CARD-DRIVER-THEORY.md` and
`SPI-PHASE-MARGIN-API.md`; both corrected. See §4.7 for current status.

### A.4 — Symptom set presented as one observation (2026-08-13)

**Was:** four suites failing together, all four "green on the committed tree, same card,
days earlier."

**Withdrawn because:** the transcripts show they never failed together. `cogcwd` failed on
`sweep_card2b_260806` while `speed`/`crc_diag`/`subdir_ops` passed; on
`sweep_card2b_260807_cleaneach` the reverse. The "all green days earlier" claim is false
for `cogcwd`. §4.1 now quotes the per-sweep results directly.

**Consequence for A.1:** a failing set that migrates between builds fits a marginal phase
some configurations lose better than a phase deterministically fixed by layout — which is
independent reason to have withdrawn A.1.

### A.5 — Pad measurement understated (2026-08-13)

**Was:** "all 24 other measured points pass."

**Corrected to:** the longest run measures pads 2–30 — four failures, **25** passes. §4.6
now quotes the transcript table and the tool's own
`SUGGESTED DAT DEFAULT: 4 (band center)` line.
