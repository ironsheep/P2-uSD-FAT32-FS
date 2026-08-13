# Layout-Sensitivity Root Cause — Analysis, Fix, and Bench Verification Plan

**Status:** FIX APPLIED container-side, awaiting bench verification.
**Answers:** `DOCs/Plans/LAYOUT-SENSITIVITY-ROOTCAUSE-REQUEST.md` (2026-08-11 bench session).
**Author:** container agent, 2026-08-12. All P2 facts cited to P2KB keys; all code
facts cited to `src/micro_sd_fat32_fs.spin2` at the pre-fix tree `a41c839`.

---

> **Three claims in this document are corrected — see Appendix: Corrections (2026-08-13) at the end.** The root cause and the fix are unaffected.


## 1. Executive summary

The defect is in the **write path**, not the read path. Both write-side streamer
blocks (`writeSector`, `writeSectors`) executed `RDFAST` — a hub-FIFO prime whose
blocking latency is **10–17 sysclks, variable with the hub egg-beater slot of the
buffer address** — *between* the SCK smart-pin counter reset and the
`XINIT`/`WYPIN` pair. The MOSI-bitstream-to-SCK-edge phase was therefore a
function of hub memory layout. `SD_INCLUDE_SPEED` is not the bug; adding its
compiled bytes moves the driver's DAT buffers (measured: **36 bytes = 4 hub
slots**), which moves `RDFAST`'s completion phase, which slides the transmitted
bitstream across the card's sampling edges. On losing layouts the card samples
every bit one SCK period late and **stores the sector shifted one bit** — and
nothing detects it, because SPI-mode write CRC is never enabled (no CMD59
anywhere in the driver), so `dresp=$05` certifies framing, not payload.

The readback then *faithfully* returns the shifted data the card stored: the
card's read CRC is computed over what it stored, so our read-side CRC check
matches, and the corruption is silent. Independent reads pass because their
on-card data was written correctly. This corrects two face-value claims in the
request doc: §2.4's "CRC valid at the card ⇒ transmitted stream self-consistent"
(false — CRC is not enforced in SPI mode by default, SD spec 7.2, and we never
send CMD59), and §1's framing of the defect as living in the *capture* path.

The fix (applied): hoist the hub ops (`RDFAST`/`SETXFRQ`, and `WRFAST` in
`readSectors`) **above** the SCK reset at all three unhardened streamer sites, so
every instruction from `DRVL` to `XINIT`/`WYPIN` is a fixed-2-clock cog op and the
data-vs-clock phase becomes a compile-time constant — the same Phase 1.5
discipline `readSector` already carries. A new `tx_align_delay` pad (DAT default
2, `debugSetTxAlignDelay()` shmoo knob under `SD_INCLUDE_DEBUG`) centers that
constant in the passing window on the bench.

## 2. Symptom inventory and its single cause

| Symptom (request doc) | Accounted for by |
|---|---|
| All ten ALL-suites fail, all seventeen non-ALL pass | SPEED bytes shift driver DAT +36 (§4.3) → losing phase for write bursts |
| Readback = written bitstream one bit late, carry across bytes | Card sampled MOSI one period late; first sampled bit = MOSI held LOW by `pinl` before the burst — matches head magic `7F→3F` (MSB 0) and pattern `0B→05` byte-exactly |
| Only just-written sectors corrupted; MBR/high-LBA reads pass | Corruption is *stored on the card*; independent sectors hold correct data |
| Write accepted: `dresp=$05`, R1 clean, CMD13 clean | SPI-mode CRC unenforced (no CMD59); CMD13 checks card-internal state, not payload |
| Read CRC never flags the corruption | Card computes read CRC over the (shifted) data it stored — tautological match |
| Deterministic per build, flips between builds | Both instruction-arrival and `RDFAST` completion are hub-rotation-locked; phase is constant per layout |
| Signature B: create-then-not-found, timestamps 0, recovery failures | Same shifted write applied to directory/FAT sectors via the same `writeSector` |
| multiblock failures | `writeSectors` (CMD25) carries the identical defect |
| Historical: never-executed 42-byte block flipped cogcwd↔subdir | Same lever: 42 ≡ 2 (mod 8) hub slots |
| Same suites passed on `8885fe3` | Different binary size → different (winning) alignment |
| async #8/10-13 `E_ASYNC_BUSY` cascades | Not explained by this cause — re-verify on bench after the fix (§6, step 6) |
| register #11, volume #9 | Independent, expectation-level (§7) |

## 3. Mechanism, step by step (P2KB-cited)

Numbers below use the standard operating point: sysclk 350 MHz, SPI 25 MHz,
half-period `hp = spi_period = 7` sysclks, full bit = 14 sysclks.

1. **SCK edge grid is anchored at the smart-pin reset.** The SCK pin runs
   P_TRANSITION (`%00101`): after `DIRL`/`DRVL` re-enable, the base-period
   counter cycles from DIR-rise; transitions begin at the next base-period
   boundary after Y is written (`p2kbArchSmartPin00101TransitionOutput`:
   "Starts at next base period after Y written"). Boundaries land at
   `T0 + hp·k` where `T0` = DRVL completion.
2. **The pre-fix block put a variable-latency hub op inside that window.**
   Old order: `DIRL, DRVL, SETXFRQ, RDFAST #0,p_buf, XINIT, WYPIN`
   (`micro_sd_fat32_fs.spin2:8160` pre-fix). `RDFAST` in waiting form takes
   **10–17 clocks** (`p2kbPasm2Rdfast` clocks field; `p2kbArchFifo` timing
   table) — the 8-clock spread is the egg-beater slot wait for the buffer's
   address slice (`p2kbArchHub`, hub_window_slot_wait 0–7 clocks).
3. **So XINIT/WYPIN timing was layout-dependent.** XINIT completed at
   `T0+14..21`, WYPIN at `T0+16..23`, both quantized by the hub phase of
   `p_buf`. The first SCK transition then fired at boundary `T0+21` or `T0+28`
   (an hp-quantum jump), while the streamer's first output bit landed at
   `XINIT + small fixed pipeline` and advanced every 14 clocks
   (`SETXFRQ $4000_0000/hp` → NCO rollover every 2·hp;
   `p2kbPasm2StreamerSmartpinControl` bit_edge_lockstep, GOLDEN). The
   data-transition train vs. the rising-edge sample train could therefore sit
   anywhere across the bit period, chosen by layout, fixed per build.
4. **Losing phases quantize to exactly one bit late.** SCK and MOSI derive from
   the same sysclk, so there is no jitter band — each build's phase is exact.
   If data transitions land after the rising edges, the card clocks in the
   *previous* bit value at every edge: the first captured bit is the LOW that
   `pinl(_mosi)` parked on the pin (`:8146`), and every subsequent bit is the
   preceding data bit. That is precisely `expected >> 1` with carry — the
   observed signature, byte-exact against all three captures in the request
   doc (§2.4).
5. **Nothing catches it.** The 2 CRC bytes are sent *after* the burst via the
   re-built MOSI smart pin (`:8199-8200`) — correct bytes, correctly framed
   (P_SYNC_TX is hardware-synchronized to SCK via B-input, immune to this
   defect). The card doesn't verify them: SPI mode disables CRC checking by
   default and the driver never issues CMD59 (grep: zero hits). For
   CW_NO_DATA_CRC cards we deliberately send `$FF $FF` filler. Either way,
   `dresp=$05` is a framing acknowledgment only. CMD13 validates card-internal
   state, not payload. On readback, the card's CRC describes the stored
   (shifted) data, so the read-side check matches. The corruption has no
   detector anywhere in the chain — which is why it presents as clean tests
   with wrong data rather than as CRC retries.
6. **Why `readSector` (single-block read) was immune:** its block was hardened
   by the Phase 1.5 reorder (`:7770`, per @evanh, KB-verified) — `WRFAST` and
   `SETXFRQ` execute *before* DIR-rise, and everything after is fixed-cycle.
   That is exactly the discipline the write path lacked. (`readSectors` had
   `WRFAST` inside the window, but `WRFAST` is near-fixed latency —
   `p2kbArchFifo`: ~2–3 clocks — because it has nothing to prefetch; it is
   hoisted anyway for uniformity.) The canonical flash_loader patterns keep
   `XINIT`→`WYPIN` adjacent with the FIFO primed earlier (`p2kbPasm2Xinit`
   examples; `p2kbPasm2Rdfast` streamer_pairing).

## 4. Container-side evidence

### 4.1 The a41c839 diff is exonerated (request §3 confirmed)
`git diff 8885fe3..a41c839 -- src/micro_sd_fat32_fs.spin2` (524 changed lines)
contains zero hits for `xinit|xfrq|STREAM_|P_SYNC|wxpin|wypin|waitxfi|
sp_transfer|getcrc`. The diff moved bytes; it did not touch the transfer paths.

### 4.2 CMD59 is absent
`grep -n "CMD59" src/micro_sd_fat32_fs.spin2` → no hits. Card-side write CRC
enforcement is at its SPI-mode default: **off**. This falsifies the request
doc's "CRC valid at the card" inference and unblocks the write-side reading of
the evidence.

### 4.3 The placement lever, measured
Two compiles of the §4 reproducer (`SD_RT_raw_sector_tests` with the explicit
flag list, ± `SD_INCLUDE_SPEED`, pnut-ts 1.55.0, same include paths as
`run_test.sh`): the driver DAT anchor `days_table` sits at binary offset
`$4A1F` without SPEED and `$4A43` with SPEED — **+36 bytes, ≡ 4 (mod 8) hub
slots** — and no conditional DAT lies between it and the three sector buffers,
so `@dir_buf/@fat_buf/@buf` shift identically. Four slots of egg-beater phase
is 4 sysclks of `RDFAST` completion shift — 57 % of the 7-sysclk half-period.
Binary sizes: 48213 vs 48805 bytes.

### 4.4 SPEED regions are code-only
All five `#ifdef SD_INCLUDE_SPEED` regions (`:63`, `:163`, `:2211`, `:3363`,
`:5926`, `:9263` pre-fix numbering) contain the CMD6 API, wrappers, and worker
dispatch cases — no CON value changes, no smart-pin/streamer configuration, no
initialization-path side effects. Presence changes layout only, consistent with
the flag-bisection table (request §2.2) where SPEED is the unique flip lever.

## 5. The fix (applied 2026-08-12)

Three edits in `src/micro_sd_fat32_fs.spin2`, one discipline:

- **`writeSector`** and **`writeSectors`**: `SETXFRQ` + `RDFAST` hoisted above
  `DIRL/DRVL`; a `WAITX tx_pad` inserted between `DRVL` and `XINIT`;
  `XINIT`→`WYPIN` remain adjacent. Every op after `DRVL` is fixed-2-clock, so
  the phase is a build-independent constant.
- **`readSectors`**: `SETXFRQ` + `WRFAST` hoisted above the reset, matching
  `readSector`'s proven Phase 1.5 ordering exactly (`WYPIN` at DRVL+2,
  `WAITX align_delay`, `XINIT init_phase`).
- **`tx_align_delay`** (DAT, default 2 = the WAITX floor) with
  `debugSetTxAlignDelay()`/`debugGetTxAlignDelay()` under `SD_INCLUDE_DEBUG`
  (documented in `DOCs/SPI-PHASE-MARGIN-API.md`). This is the write-path
  analogue of the read path's `align_delay` — an engineered, characterized
  phase constant, not a per-build workaround. `[2, 2+2·hp]` sweeps one full
  bit period.

Why minimal: no sampling-mode changes, no byte loops, no delays-as-workarounds —
the streamer and smart pins keep doing exactly what they did, with the variable
component moved outside the phase-critical window. The default `tx_pad = 2`
reproduces a *fixed* instance of the timing the old code produced variably;
whether it is the *centered* instance is a bench question (§6 step 3).

Container gates on the fixed tree: `check_style` exit 0, `check_error_handling`
clean, `run_regression.sh --compile-only --include-format` 27/27 + format
vehicle + 15 consumers, all three doc instruments clean.

## 6. Bench verification plan (host side, in order)

Card: shakedown card SN `$0000_0F14` unless stated. Transcripts named by card
serial per `DOCs/Agent-Reports/README.md`. HARD-STOP rule from «#64» applies:
any anomaly → confirm the measurement before any conclusion.

1. **Decisive fork experiment — is the corruption on the card?** (pre-fix
   binary, ~5 min). Build the §4 reproducer FAIL variant **at `a41c839`**
   (stash the fix or use the pre-fix binary if still on disk). Run raw_sector
   to write `TEST_SECTOR_A..E`; let it fail. Power-cycle. Run the PASS-variant
   (no-SPEED) build and raw-read sector 100_000
   (`SD_dump_sector` works too). **Prediction: the stored data is the
   one-bit-shifted pattern.** This proves write-side displacement with no new
   code. If the data reads back CORRECT, the mechanism analysis is wrong —
   STOP, report, do not proceed to step 2.
2. **Fix confirmation, both former polarities.** Fixed tree: run the §4
   reproducer in BOTH variants (ALL build and no-SPEED explicit build).
   Expected: 14/14 both. Then `SD_RT_stress_tests` (ALL) → 4/4 and
   `SD_RT_multiblock_tests` (ALL) → 7/7.
3. **`tx_align_delay` shmoo (characterization, one card, ~20 min).** With the
   ALL build + `debugSetTxAlignDelay(pad)` walked over `[2 .. 2+2*hp]` (at
   hp=7: 2..16), run a raw write+readback per point (the raw_sector suite's
   pattern tests, or `SD_phase_sweep_test`-style loop). Record pass/fail per
   pad. Expected: a contiguous passing band ≥ half a bit period wide. Set the
   DAT default to the band's center, rebuild, re-run step 2. If the band is
   narrower than 4 sysclks or split, STOP — the margin model is wrong.
4. **Alignment-invariance proof (the actual acceptance test).** With the final
   pad value: compile the reproducer with deliberate layout perturbations — a
   never-executed `BYTE 0[N]` DAT block in the test top file for
   N ∈ {1, 2, 4, 8, 12, 36, 60} — and run each (~3 min each). **All must
   pass.** This sweeps buffer alignment across hub slots including both former
   polarities; any failure = fix incomplete, STOP.
5. **Optional logic-analyzer confirmation:** capture SCK vs MOSI at burst start
   on (a) the pre-fix FAIL build and (b) the fixed build: (a) shows data
   transitions on the wrong side of the rising edges; (b) shows them fixed and
   safely away. Evidence for the record; not gating.
6. **Re-enter the «#64» sweep.** Full `run_regression.sh --include-format` per
   the task body (sweep-start fsck, no `--clean-each`), scored against the
   574-count pack. Expected deltas vs the 2026-08-11 shakedown: the ten ALL
   suites go green; error_injection now scores **36/36 with T36 running** (the
   geometry guard redesign, §7.1 — the designed-red is retired); async
   #8/10-13 re-checked — if `E_ASYNC_BUSY` cascades persist on a green write
   path, they are a separate defect: collect, do not chase mid-sweep. The two
   expectation-level items (register #11, volume #9) remain red until §7.2/§7.3
   decisions land.
7. **Stack watermarks:** unaffected by this work (request §7); the «#65»
   formula inputs stand.

## 7. Companion items

### 7.1 error_injection T36 geometry guard — FIXED
The last-slot boundary is now built by `rawFillExtDir()`: raw sector writes of
synthetic occupied entries (empty 8.3 files, first-cluster 0 — the driver's own
lazy-create shape) across the subdirectory's first cluster, leaving exactly the
final slot free. O(sec/clus) card writes instead of O(entries²) create-scans:
practical at 8 through 128 sec/clus, so the setup guard passes on every
supported card and the witness runs everywhere. Cleanup wipes the slots raw and
deletes the emptied directory (also clears pre-redesign `EXTnnn.TMP` leftovers).
The requireSetup guard still exists and still scores RED, but now only on a
geometry FAT32 itself forbids (mount lied). **Scoring-pack impact:** T36's
designed-red on 64-sec/clus cards is retired; error_injection expects 36/36 on
`$0000_0F14`.

### 7.2 register #11 CID PNM printability — PROPOSAL (decision: Stephen)
SD Physical Layer spec defines PNM as a 5-character ASCII product name, so the
assertion is spec-faithful — but the failing observation is about the *card*,
not the driver, and the driver's contract is faithful register transport.
**Recommendation:** score structural validity (CID delivered, CRC7 already
validated by the register path) and demote printability to an informational
line that prints PNM with non-printables hex-escaped. Keeps the suite
card-independent — same principle as the T36 redesign. Alternative (rejected):
a per-serial waiver table, which grows forever and re-reds on every new OEM
card.

### 7.3 volume #9 chdir-onto-label error code — PROPOSAL (decision: Stephen)
Driver returns `E_NOT_A_DIR` (-43); the isolation test expects
`E_FILE_NOT_FOUND` (-40). **Recommendation: -40, align the driver.** The S1
doctrine (a41c839) makes the volume label invisible to file operations —
`E_NOT_A_DIR` leaks its existence and contradicts that doctrine. Likely a
one-line fix in the chdir lookup path (exclude ATTR_VOLUME_ID matches in the
search, as the S1 label filter already does for file ops), plus an
ERROR-HANDLING-GUIDE line. Not implemented pending the decision.

## 8. Residuals and interactions

- **async `E_ASYNC_BUSY` cascades** (#8/10-13): unexplained by this root cause;
  bench step 6 disposition.
- **Socket-timing plan** (`DOCs/Plans/SOCKET-TIMING-CHARACTERIZATION-PLAN.md`):
  this fix makes the digital phase deterministic, which is exactly what that
  plan's δ-measurement needs as a stable baseline. Run it only after step 3
  locks the pad.
- **Other cards:** on spec-CRC-enforcing cards this same defect would have
  presented as write rejections or read-CRC retries rather than silent
  corruption — worth remembering when reading historical marginal-card logs.
- **`tx_align_delay` default (2) ships only after step 3 characterizes it.**
  Until the bench runs, the fix guarantees *invariance*, not *correct phase* —
  do not certify from container state.

---

## Appendix: Corrections (2026-08-13)

Two claims in this document are **withdrawn**; a third is a plan that has been cited
elsewhere as a result. The root cause and the fix are unaffected.

**1. "36 bytes = 4 hub slots" (§4.3, and "42 ≡ 2 (mod 8)" at §2) is wrong arithmetic.**
`36 mod 8` was computed on a *byte* count. Hub slices are long-granular — P2KB's own
block-transfer figures ("1 long per clock", "4 bytes per clock") require it — so 36
bytes is 9 longs ≡ **1** slice. The measured part, DAT symbol `$4A1F` → `$4A43` under
`SD_INCLUDE_SPEED`, stands.

**2. Attributing RDFAST's 10–17 sysclk spread to "the egg-beater slot wait for the
buffer's address slice" is not established.**
`p2kbArchP2ArchitectureMentalModel` states a hub operation completes "in 2-9 clocks
depending on when the COG's slot arrives" — a property of issue time, not of the
address requested. `p2kbArchHub`'s slicing section reads the other way; the two are
unreconciled and neither was measured here. The fix's correctness does not depend on
resolving it: a variable-latency instruction must not sit inside the phase window,
whatever drives the variability.

An alternative that fits the evidence at least as well: the shipped `tx_align_delay`
was **2**, and §6 step 3's sweep later found the failing phase to be `pad ≡ 1 (mod 7)`
— one step away. A phase sitting next to the cliff flips on any small systematic
offset. Note also that the failing-suite set *migrated* between sweeps (08-06 `cogcwd`
failed while `speed`/`crc_diag`/`subdir_ops` passed; 08-07 the reverse), which fits a
marginal phase better than a phase deterministically fixed by layout.

**3. §6 step 4 — the alignment-invariance proof — has no recorded result.**
It is written here as the plan ("the actual acceptance test … All must pass"). No
transcript exists in `tools/logs/` and no displacement vehicle exists in
`diagnostic-tests/`. It was subsequently cited in three user-facing documents as though
it had been performed; those have been corrected. As specified the N set is also weaker
than intended — N ∈ {1,2,4,8,12,36,60} reaches four distinct slice positions with one
duplicate; N ∈ {4,8,12,16,20,24,28} walks all eight.

Full account: `DOCs/Plans/2026-08-13-EVOLUTION-DOC-PROVENANCE-AUDIT.md`.
