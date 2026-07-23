# SDSC Driver Audit — Forensic Walk of Suspect Code Paths

**Driver under audit:** `src/micro_sd_fat32_fs.spin2` (7,939 lines, current HEAD)
**Scope:** the five focused areas (A–E) requested. Findings cite exact line numbers in the current file. Three previously-identified silent-error bugs (commits `a7dc362`, `dbe5cc9`, `bfeb20e`) are not re-listed here.

---

## A. `writeSector` post-PASM transition (single-block, CMD24 path)

### A.1 Step-by-step inventory, lines 6571–6660

| Line(s) | Step | MOSI smart-pin state | MOSI pin DIR/OUT | Notes |
|---|---|---|---|---|
| 6571–6572 | `_sck := sck; _mosi := mosi` | active `P_SYNC_TX \| P_OE` from initSPIPins | DIR=1, smart-pin owns OUT | — |
| 6591 | `cmd(CMD24, sector << hcs)` (line 6155–6181) | active | smart-pin drives | CMD24 keeps CS LOW (line 6181) |
| 6606 | `sp_transfer_8($FE)` data-start token | active | smart-pin drives | uses `WXPIN/WYPIN/DRVL _mosi` (sp_transfer_8 line 5786–5788) |
| 6621 | `pinclear(_mosi)` | **CLEARED** — `WRPIN=0, DIR=0` | floats (DIR=0) | smart-pin mode gone, pin floats for ~few-cycle window |
| 6622 | `pinl(_mosi)` | inactive | DIR=1, OUT=0 (manual drive low) | pin driven LOW by COG OUT register |
| 6637 | `DIRL _sck` (PASM) | inactive | (MOSI unchanged: LOW) | SCK only |
| 6638 | `DRVL _sck` (PASM) | inactive | (MOSI unchanged) | SCK ready |
| 6639–6642 | `SETXFRQ / RDFAST / XINIT stream_mode / WYPIN clk` | inactive | **streamer takes over OUT** — drives MOSI per bit-stream | streamer writes pin directly via STREAM_TX_BASE ($8081_0000); DIR still 1 from `pinl` |
| 6643 | `WAITXFI` | inactive | streamer drives | 512 bytes shipped |
| (post-WAITXFI) | (streamer done) | inactive | DIR=1, last bit on OUT (whatever the last data bit was — usually a 1 if data is text-ish, 0 if zero-padded) | **MOSI is left holding last bit value** — not necessarily HIGH (idle) |
| 6647 | `WRPIN(_mosi, spi_tx_mode)` | reconfigured `P_SYNC_TX \| P_OE` | DIR stays 1, smart-pin OE now active again | per p2kb canonical sequence WRPIN must follow DIRL; here DIR is *still 1*, so the smart-pin re-arms without an explicit reset |
| 6648 | `WXPIN(_mosi, %1_00111)` | active, X=8-bit start-stop | DIR=1 | bit-count param |
| 6649 | `pinh(_mosi)` | active | **DRVH (DIR=1, OUT=1)** — per p2kb "Overrides any smart pin mode on the pin" | Spin2 PINH = DRVH. But the established initSPIPins pattern (line 5634) also uses `pinh(mosi)` to "enable" the smart pin and works in steady state. With `P_OE` set, smart pin owns drive — OUT bit is overridden by smart pin OE in this mode. |
| 6659–6660 | `sp_transfer_8(crc_hi)` / `sp_transfer_8(crc_lo)` | active | smart-pin drives 8 bits each | uses standard smart-pin TX path |
| 6663 | `waitDataResponse()` | active | full-duplex polling | line 6845 |

### A.2 Findings on the transition window

**A-1 (medium suspect):** Between `pinclear(_mosi)` (line 6621) and `pinl(_mosi)` (line 6622) there is a small window where MOSI is *floating* (DIR=0, WRPIN=0). At 350 MHz sysclk this is ~2 sysclks per Spin2 statement, plus interpreter overhead — easily microseconds. SCK is NOT clocking during this window (the streamer hasn't started yet, the smart pin is being torn down on the next operation). No clock means no sample by the card. **Risk:** none in normal operation; MOSI floating with no clock can't shift any bit into the card. Not a regression vector.

**A-2 (low suspect):** Between `WAITXFI` (line 6643) and `WRPIN(_mosi, spi_tx_mode)` (line 6647) MOSI sits at the **last data bit value** with DIR=1. SCK is idle LOW (last edge from streamer). With no SCK transitions the card cannot sample, so this is a benign rest state — but it is **not** the SPI idle high state. If the last data byte's LSB is 0, MOSI rests LOW during the ~10 sysclks of Spin2 overhead before WRPIN re-arms. Not a protocol violation.

**A-3 (low suspect):** Line 6647 `WRPIN` is executed with DIR=1 (not the canonical "DIRL → WRPIN → WXPIN → DIRH" smart-pin reset sequence). Per p2kb `p2kbArchSmartPin11100SyncSerialTransmit` "initialization: MUST reset (DIR=0) before configuration." The driver violates this *technical* requirement here. The smart pin may carry over internal Y-register state from the streamer-overridden period. **However**: the `pinclear(_mosi)` at line 6621 *did* reset both WRPIN AND DIR before the streamer ran, so the smart pin entered the streamer window already reset; the streamer then drove OUT directly without using the smart-pin shifter. So at line 6647 the smart pin's internal shifter is in a known-zero state. **The risk vector that remains:** the `pinh(_mosi)` at line 6649 = DRVH; that issues OUT=1, but with P_OE the smart pin's output overrides — and the smart pin's Y register has not been loaded yet (will be loaded by next `sp_transfer_8`'s `WYPIN`). Between line 6649 and the next `WYPIN` (inside `sp_transfer_8` line 5787), the smart pin is enabled with no Y data — it should idle HIGH per P_SYNC_TX spec but this is a brief window.

**A-4 (low suspect, ordering OK):** CRC bytes (lines 6659–6660) ARE sent after the smart pin is fully restored (WRPIN/WXPIN/pinh at 6647–6649). The ordering is correct: streamer → restore smart pin → send CRC. **No ordering bug found.**

**A-5 (NOTE — asymmetry with readSector):** Compare to readSector lines 6301–6302 which uses `pinclear(_miso); pinf(_miso)` (float for input). The write path uses `pinclear(_mosi); pinl(_mosi)` (drive low for output). Both teardown patterns are symmetric and appropriate for direction. **No asymmetry bug.**

### A.3 Conclusion on Area A

No *ordering* bug between streamer-end → smart-pin-restore → CRC. The most concerning items are:
- The non-canonical re-arm sequence (`WRPIN` while DIR=1) at line 6647 — *technically* violates p2kb's "DIR=0 before WRPIN" rule but the prior `pinclear` did do a full reset before the streamer ran.
- The lack of an explicit "idle MOSI HIGH for ≥ 1 byte time" gap between the last data bit and the first CRC bit, which on a marginal card with internal clock-stretching pretensions could be a concern. (See finding D-2 below.)

---

## B. NCO `xfrq` calculation symmetry

| Path | Line | xfrq formula | "subtract 1 if exact" guard |
|---|---|---|---|
| readSector (CMD17) | 6234–6236 | `xfrq := $4000_0000 / spi_period` | YES (line 6235) |
| readSectors (CMD18) | 6414–6416 | same | YES (line 6415) |
| writeSector (CMD24) | 6617–6619 | same | YES (line 6618) |
| writeSectors (CMD25) | 6735–6737 | same | YES (line 6736) |

**Finding B-1:** All four streamer-driven paths apply the identical "bilateral NCO fix." **No asymmetry.** The four call sites are byte-for-byte equivalent in the xfrq calculation. The comment on line 6236 in readSector explicitly references "Match write-path NCO fix," confirming intentional symmetry.

---

## C. CMD24 vs CMD25 protocol-path differences

### C.1 Byte-sequence comparison

| Step | CMD24 (writeSector, lines 6533–6702) | CMD25 (writeSectors, lines 6704–6811) |
|---|---|---|
| Command issue | `cmd(CMD24, sector << hcs)` line 6591; R1 timeout check (line 6593); fatal R1 check (line 6598) | `cmd(CMD25, start_sector << hcs)` line 6741; only checks `resp <> $00` line 6742 — **no R1-timeout-vs-clean-$00 disambiguation** |
| Data start token | `$FE` (line 6606) — single value | `$FC` (line 6752) inside per-block loop |
| Streamer 512 bytes | once (lines 6612–6644) | once per block (lines 6733–6768) |
| CRC bytes | once (6659–6660) | once per block (6777–6778) |
| Data response | `waitDataResponse()` line 6663; bit-decoded resp pattern check line 6672 | `waitDataResponse()` line 6781; checks `(resp & $0F) <> DATA_ACCEPTED` line 6785 |
| Busy after each block | `waitBusyComplete()` line 6690 | `waitBusyComplete()` line 6790 |
| Termination | none — single block | `$FD` stop token (line 6797) + stuff byte `$FF` (line 6798) — **NOT CMD12** |
| Final busy | (already done at 6690) | `waitBusyComplete()` line 6801 |
| Recovery on final-busy timeout | n/a | `recoverToIdle()` line 6803 (force CS HIGH + 80–240 clocks) |
| Post-write status check | `checkCardStatus()` (CMD13) line 6701 | `checkCardStatus()` (CMD13) line 6809 |
| CS deassert | always before return (lines 6596, 6601, 6667, 6685, 6692, 6696) | line 6744 (R1 reject), line 6806 (success path) — **no explicit `pinh(cs)` on inner-loop `quit`** (lines 6782–6792); the protocol relies on the post-loop $FD stop-token block to terminate cleanly |

### C.2 Findings

**C-1 (MEDIUM-HIGH SUSPECT):** **`writeSectors` does NOT do the R1-timeout disambiguation that `writeSector` does.** Line 6742 only checks `resp <> $00` — this means a `cmd()` R1 timeout (which since commit `bfeb20e` returns a distinguishable sentinel in `diag_cmd_r1_ms = -1` but, looking at the code, the actual return value path here…) — let me re-verify. Looking at `cmd()` lines 6166–6177: on timeout `response := false` (which is 0), and `diag_cmd_r1_ms := -1`. `writeSectors` line 6741 reads `resp := cmd(...)` then line 6742 `if resp <> $00`. **R1=$00 (clean) and R1=timeout both evaluate equal to $00** — so `writeSectors` proceeds INTO the CMD25 burst write loop on a CMD25 R1 timeout, sending the start token and 512 data bytes blind. This is the EXACT same class of silent-error bug as the one fixed in `bfeb20e` for `cmd()` callers in writeSector. **The fix exists in writeSector (line 6593: `if diag_cmd_r1_ms < 0`) but is MISSING in writeSectors.** This is a candidate Bug #4.

**C-2 (MEDIUM SUSPECT):** **Stop-token handling: the inner-loop `quit` paths in writeSectors (lines 6784, 6787, 6792) DO NOT call `pinh(cs)`** before falling through to send the `$FD` stop token. This is actually *correct* SD protocol — a multi-block write must be terminated by `$FD` (or CMD12), not by CS deassert mid-burst. However if `waitDataResponse()` *timed out* (no response from card at all), sending more bytes ($FD + $FF stuff) into a card that already isn't acknowledging is unlikely to recover; the eventual `waitBusyComplete()` at line 6801 will also time out, triggering `recoverToIdle()` at 6803. **Net effect:** a CMD25 with a per-block data-response timeout will still attempt to send the stop token, then recover via CS-high + dummy clocks. This sequence may leave a counterfeit SDSC card in an indeterminate internal state.

**C-3 (MEDIUM-HIGH SUSPECT, MATCHES STAGE 2 SIGNATURE):** **There is no busy-poll after the per-block `waitBusyComplete()` failure inside writeSectors.** If the per-block waitBusy times out (line 6790–6792), we `quit` the loop, but the card is *still programming a block*. We then immediately send the `$FD` stop token (line 6797) to a card that is still internally busy. Per SD Physical Spec 7.3.3.2, the stop token may be sent during a programming block, and the card should continue to busy-out until the program completes — but a card with a flaky write engine may interpret an early-stop differently. The Stage 2 failure ("after CMD25 multi-block + CMD24 single, the next CMD17 times out waiting for $FE") is consistent with **the card being left in an internal data-streaming or busy state from the prior CMD25 that the driver assumed had cleanly terminated**.

**C-4 (LOW SUSPECT):** CMD25 → next-command sequence: After the CMD25 stop sequence and successful `waitBusyComplete()`, the driver does `pinh(cs)` (line 6806) and then issues CMD13 via `checkCardStatus()`. The CMD13 path goes through `sendCmd13Transaction()` which already deasserts then re-asserts CS (lines 6996, 7001). So there IS a CS handoff. **No CS-handoff bug found.**

**C-5 (NOTE):** No CMD12 is ever sent after a CMD25 — the driver correctly uses the `$FD` stop token. This matches SD spec; CMD12 is for multi-block READ (CMD18), not multi-block WRITE (CMD25).

---

## D. `waitBusyComplete` / `waitDataResponse` audit

### D.1 `waitBusyComplete` (lines 6869–6889)

- Exit condition: `resp == $FF` (single byte, line 6884). Polling timeout from `card_write_timeout_ms` (line 6881).
- **Callers (all 4):**
  - `writeSector` line 6690 — success path, after `waitDataResponse` accepted
  - `writeSectors` line 6790 — per-block, inside repeat
  - `writeSectors` line 6801 — after `$FD` stop token
  - `sendStopTransmission` line 6948 — after CMD12 R1 in multi-block READ termination

**Finding D-1 (low):** All callers proceed to the next phase via either a `quit` (loop exit), a fall-through to send another byte, or in `sendStopTransmission` to set `last_cmd12_busy := 0` and return. **No caller proceeds *immediately* (no inter-byte gap) into a new command without CS handoff** — in every case there is at least one `pinh(cs)` between busy-complete and the next command, OR at minimum the protocol-mandated stop-token/stuff-byte gap. **No gap bug found.**

### D.2 `waitDataResponse` (lines 6845–6867)

- Polls for `(resp & $11) == $01` (line 6861) — i.e. bit 0 set, bit 4 clear. Lower 5 bits returned as response.
- 100 ms timeout (line 6856).
- Loop is tight: a `sp_transfer_8($FF)` per iteration. Each iteration takes ~ (16 SCK transitions at smart-pin rate + Spin2 loop overhead). At hp=4 (40 MHz SCK on 320 MHz sysclk) this is ~200 ns of SCK + ~few μs of Spin2 — well-spaced.

**Finding D-2 (HIGH SUSPECT — MATCHES STAGE 2 "code=2 drespTO"):** **Counting SCK clocks between "last CRC bit out" and "first MISO poll."**

In writeSector line 6660 → 6663:
1. `sp_transfer_8(diag_sent_crc & $FF)` — finishes 8 SCK cycles, returns when the smart pin TX completes; line 5800–5802 waits on MISO IN flag.
2. Spin2 interpreter overhead (interpreter dispatch + method call) — a few tens of sysclks, **with NO SCK clocks** because no transfer is in flight.
3. `waitDataResponse()` enters, line 6855–6856 sets timeout, line 6858 polls `sp_transfer_8($FF)` — this triggers another 8 SCK cycles.

**The window between "CRC LSB last bit" and "first MISO poll byte" contains ZERO SCK clocks but several μs of wall time.** Per SD Physical Spec 7.3.3.2, the data-response token "is sent by the card right after each data block has been written" — the card needs *clocks* to shift the response out. Most cards take 1–3 byte-times (8–24 clocks) after CRC to emit the response. So the first `sp_transfer_8($FF)` poll provides the clocks for the card to emit the data-response token. **This is by design and normal.**

**However**, with a counterfeit / marginal SDSC card whose internal state machine is unstable (especially after a prior CMD25 burst that left residual state), the card may need more than one byte-time to emit the response — but the driver polls at byte-granularity, which should still catch it within the 100 ms timeout. Unless the card never emits anything (MISO stays $FF), which is exactly the Stage 2 symptom.

**Finding D-3 (MEDIUM SUSPECT):** Loop body at line 6858–6864 — when `resp == $FF` (idle, no response yet) the code does NOT continue; it falls through to the time check (line 6865) and loops. **Correct.** When `resp <> $FF` but `(resp & $11) <> $01` (line 6861 false branch), the code falls to the comment "Not a valid response format, keep polling (might be noise)" (line 6864) and then to the timeout check. **This means**: if the card emits any non-$FF byte that doesn't match the data-response pattern, the loop CONSUMES it and polls another byte. With a card stuck in some weird state emitting (say) $00, the driver would chew through 100 ms of byte polls without recognizing the situation. **However** this is conservative and unlikely to cause the observed lockup.

### D.3 `sendStopTransmission` (lines 6891–6952) — for completeness

CMD12 path: send command bytes (full-duplex captured into `cmd12_pre_capture`), 100 ms timeout poll for non-$FF (= R1 arrived), capture 16 more bytes for framing, then `waitBusyComplete()`. No issues spotted.

---

## E. SDSC-specific branches

### E.1 Address conversion (`<< hcs`)

`hcs` is set to 9 for SDSC (line 6075), 0 for SDHC (line 6072). Branching is uniform across:
- CMD17 readSector — line 6247 (`sector << hcs`)
- CMD18 readSectors — line 6435 (`start_sector << hcs`)
- CMD24 writeSector — line 6591 (`sector << hcs`)
- CMD25 writeSectors — line 6741 (`start_sector << hcs`)
- CMD17 readSectorSlow (debug path) — line 7760
- CMD32 erase block start — line 7814
- CMD33 erase block end — line 7821

**Finding E-1:** Address conversion is **applied uniformly across all sector-addressable commands.** No SDSC addressing bug found.

### E.2 CMD16 SET_BLOCKLEN

Line 6087: `if hcs <> 0` (SDSC) → issue `cmd(CMD16, SECTOR_SIZE)` (line 6089). On non-zero R1 only a warning is logged (line 6091); no failure return. CMD16 is issued **after** CMD58 / before identifyCard / before setOptimalSpeed.

**Finding E-2:** CMD16 IS issued for SDSC during init. **However:** a warning-only response is not promoted to an init failure. If the counterfeit card's CMD16 returns non-zero R1 the driver continues init with possibly-wrong block length. Worth tracing in actual logs for the `asdfg` card to confirm R1=$00 on CMD16.

### E.3 Other SDSC branches

`grep "hcs"` returns only the 8 sites above. Beyond addressing and CMD16, **there is no other SDSC-specific code path** — no separate timeout policy, no separate retry logic, no separate CRC handling. (`probeDataCrc` flags the dummy-CRC behavior based on observed response, not based on hcs.)

### E.4 `card_warning_flags` lifecycle

- Cleared **unconditionally at entry of `initCard()`**, line 5875. **The "extra credit" smell from the running investigation log is FIXED** — flags do not leak from a failed prior init into the next attempt, because the clear happens before any CMD0 attempt.
- Set sites: line 7067 / 7072 / 7077 (CW_CMD13_UNRELIABLE in `probeCmd13`), 7104 (CW_CMD23_SUPPORTED in `probeCmd23`), 7168 (CW_NO_DATA_CRC in `probeDataCrc`).

### E.5 CMD59 (CRC ON/OFF)

`grep CMD59` returns zero hits in the entire driver. **CMD59 is never issued.** The driver sends `CRC_CMD8 ($87)` as a fixed CRC for all non-CMD0 / non-CMD8 commands (line 6161). Per SD Physical Spec 7.2.2, in SPI mode CRC checking is OFF by default and remains OFF unless CMD59 enables it. **Sending an invalid CRC byte on every command (CRC_CMD8 = correct only for CMD8) is therefore harmless** — cards ignore it. **No CRC-related bug here.** This is an inefficiency / code smell, not a correctness issue. Documenting CRC_CMD8 reuse would help future maintainers.

---

## F. Timing-related notes

- `waitms` / `waitus` used as documented spec waits, not as workarounds:
  - line 5885: `waitms(POWER_ON_DELAY_MS)` — spec ≥1 ms
  - line 5920: `waitus(10)` — pull-up settle, hardware physical settling time
  - lines 5935–5945: `waitus(10)` inside the CS-HIGH recovery loop (bit-bang clocking before smart pins are configured) — pre-smart-pin necessity
  - line 5956: `waitus(SMARTPIN_SETTLE_US)` — smart-pin settling, documented in p2kb
  - lines 5978, 6038, 6055: `waitms(ACMD41_POLL_DELAY_MS)` — spec-mandated polling cadence
- No "just in case" delays inserted around the write CRC or busy paths. **No workaround-delays found.**

---

## G. Suspect ranking (most → least)

| Rank | Finding | Loc | Why |
|---|---|---|---|
| 1 | **C-1: writeSectors does NOT disambiguate `cmd(CMD25)` R1 timeout from clean R1=$00** | 6741–6742 | Same class as bug #3 (`bfeb20e`). If CMD25 R1 times out, the driver issues a full multi-block write blind into a card that did not acknowledge the command. After mount_tests this could leave the card mid-state for the next single-block, EXACTLY matching the Stage 2 progression. **Candidate Bug #4.** |
| 2 | **C-3: per-block waitBusyComplete failure inside writeSectors falls through to $FD without ensuring card is at a clean stopping point** | 6790–6797 | If the per-block busy-poll times out, the card is still programming — sending $FD on top of an unfinished block is spec-tolerated but on a marginal SDSC may corrupt internal state. Matches the Stage 2/3 hand-off (CMD25 followed by failing CMD17/CMD24). |
| 3 | **D-2: zero-SCK-clock gap between CRC LSB and first MISO poll** | 6660 → 6663 | Spec-permitted but tight; on a stressed counterfeit card the data-response may be unreliable. Direct match to the Stage 2 "code=2 drespTO" symptom. |
| 4 | **E-2: CMD16 SET_BLOCKLEN R1 error is warning-only, not a failure** | 6087–6091 | If the asdfg card silently rejects CMD16, the driver continues with the card's power-up default block length (potentially 1024) — every subsequent CMD17/CMD24 will desync the streamer mid-block. **Worth checking the asdfg log for CMD16 R1 value.** |
| 5 | **C-2: writeSectors inner-loop `quit` paths terminate via $FD even on data-response timeout** | 6782–6797 | Spec-acceptable but recovery-fragile on the bad card. Lower rank than C-1 because the post-loop `recoverToIdle()` does eventually clean up. |
| 6 | **A-3: WRPIN(_mosi) after streamer without explicit DIR=0 reset** | 6647 | Violates p2kb's "DIR=0 before WRPIN" canonical sequence; in practice the prior `pinclear` cleared the smart pin before the streamer ran, so internal state should be safe. Low probability of being load-bearing. |
| 7 | **D-3: waitDataResponse silently consumes non-$FF / non-data-response bytes** | 6858–6864 | Conservative loop; would cause 100 ms hang on a card emitting garbage, but not the observed lockup. |
| 8 | **A-2: MOSI rests at last-data-bit value (potentially LOW) between WAITXFI and WRPIN restore** | 6643–6647 | SCK is idle so no card-side sampling occurs; benign rest state. |
| 9 | **A-1: MOSI floats briefly between `pinclear` and `pinl`** | 6621–6622 | SCK is idle; no card-side sampling. Benign. |
| 10 | **E-5: CMD59 never issued; CRC_CMD8 byte reused as filler on all commands** | 6161 | Harmless per spec (CRC checking off by default). Code smell only. |

### Ranking rationale

The top three findings (C-1, C-3, D-2) directly match the empirical Stage 2 symptom: a CMD25 multi-block burst (mount_tests) leaves the card in a state where the next CMD17/CMD24 fails on the data-token path, not on R1. C-1 is the most precise match because it would let the driver execute a 512-byte streamer blast into a card that never even acknowledged CMD25 — depositing arbitrary bytes on whatever sector the previous CMD25 last started, with no error reported to the caller. This is exactly the class of bug that the bfeb20e fix addressed for the single-block path; it is mechanically duplicable to writeSectors and the audit log already hints that the multi-block path is where the wedge originates.

E-2 (CMD16 not enforced for SDSC) is a sleeper candidate — if the `asdfg` card silently rejects CMD16 and the driver assumes 512-byte blocks while the card defaults to 1024, every write would over- or under-stream. Easy to confirm or rule out from existing init logs.
