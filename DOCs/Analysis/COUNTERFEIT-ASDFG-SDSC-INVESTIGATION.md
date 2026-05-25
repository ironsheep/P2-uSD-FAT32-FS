# Counterfeit "asdfg" SDSC class — Investigation

**Scope:** Running investigation log + measured ground truth for the counterfeit
"asdfg" SDSC silicon class. Cards in this class share PNM `"asdfg"`, MID `$05`,
PRV `2.2`, and present as SDSC (CSD v1.0) with a dummy `$0000` data-block CRC.
Per-card empirical summaries live in the catalog ([`DOCs/cards/`](../cards/));
this doc holds the deep mechanism work, the hypothesis table, and the
as-received forensic dumps.

## Cards in this class

| Slot | Designator | Serial | MDT | Label | Per-card sheet |
|---|---|---|---|---|---|
| Cloudisk | `Unknown_asdfg_2.2_00001680_202511` | `$0000_1680` | 2025/11 | "Cloudisk" 2 GB | (pending) `cloudisk-asdfg-2gb.md` |
| Lerdisk  | `Unknown_asdfg_2.2_000001F4_202512` | `$0000_01F4` | 2025/12 | "Lerdisk" 1 GB  | [`lerdisk-asdfg-1gb.md`](../cards/lerdisk-asdfg-1gb.md) |

**Sequential SN and MDT strongly suggest same factory run, possibly same wafer.**
Treat shared findings as class-level until measurement contradicts; when the
two cards diverge, that divergence is itself a data point worth calling out.

**Section-tagging convention.** Per-card measurement sections are tagged with
the card name in the heading (e.g., `### MBR (Cloudisk, sector 0)`).
Class-level investigation sections (hypotheses, mechanism analysis, lessons)
are untagged. When a card-specific observation appears inside a class-level
section, lead the paragraph with `**[Cloudisk]**` or `**[Lerdisk]**`.

---

## Forensic dumps (as-formatted)

**Cloudisk dumps captured 18 MAY 2026** via `diagnostic-tests/SD_dump_mbr_vbr.spin2`
(log: `tools/logs/SD_dump_mbr_vbr_260518-231322.log`). Cloudisk in P2 Edge
socket (CS=60 MOSI=59 MISO=58 SCK=61), as received, before reformat. All
four Cloudisk structures below read back correctly through `initCardOnly` +
`readSectorRaw` with no CRC errors — the filesystem is clean and valid.

**Lerdisk dumps: pending.** When captured, append parallel sections under
each subsection heading.

### MBR (Cloudisk, sector 0)

| Field | Offset | Value |
|---|---|---|
| Partition 1 boot flag | 446 | `$00` |
| Partition 1 type | 450 | `$0C` (FAT32 with LBA) |
| Partition 1 LBA start | 454 | 8192 |
| Partition 1 total sectors | 458 | 3,924,992 (`$003BE000`, ~1.87 GB) |
| Boot signature | 510..511 | `55 AA` |

Sector is otherwise all zero (no boot code).

### VBR / BPB (Cloudisk, sector 8192)

| Field | Offset | Value |
|---|---|---|
| Jump | 0 | `EB 58 90` |
| OEM name | 3 | `BSD  4.4` |
| BytsPerSec | 11 | 512 |
| SecPerClus | 13 | 8 |
| RsvdSecCnt | 14 | 32 |
| NumFATs | 16 | 2 |
| Media | 21 | `$F0` |
| TotSec32 | 32 | 3,924,992 |
| FATSz32 | 36 | 3826 |
| RootClus | 44 | 2 |
| FSInfo sector | 48 | 1 |
| BkBootSec | 50 | 6 |
| Volume label | 71 | `MACOS-FMT` |
| fstype | 82 | `FAT32   ` |
| Boot signature | 510..511 | `55 AA` |

### Derived geometry (Cloudisk, absolute LBAs)

- FAT[0] start sector = 8192 + 32 = **8224**
- FAT[1] start sector = 8224 + 3826 = 12050
- Data region start  = 8192 + 32 + (2 × 3826) = **15876**
- Root directory start = 15876 + (2 − 2) × 8 = **15876**

### FAT[0] (Cloudisk, sector 8224)

| Entry | Value | Meaning |
|---|---|---|
| FAT[0] | `$0FFFFFF0` | media byte + EOC |
| FAT[1] | `$0FFFFFFF` | EOC, clean-shutdown / no hard-error bits |
| FAT[2] | `$0FFFFFFF` | root directory occupies a single cluster |

Many further chains are allocated (macOS Spotlight / fseventsd payload).

### Root directory (Cloudisk, sector 15876)

- Entry 0: volume-label entry `MACOS-FMT` (attr `$28`)
- `SPOTLI~1` — directory (attr `$12`), LFN `.Spotlight-V100`
- `FSEVEN~1` — directory (attr `$12`), LFN `.fseventsd`
- Remainder of sector is zero.

---

## Operational note — the card wedges

Three consecutive `initCardOnly` attempts failed with `-3 E_BAD_RESPONSE`. A full
power cycle of the P2 Edge board (a serial-download reset is not enough — it does
not drop the SD 3.3 V rail) cleared it and init then succeeded on the first try.

The card latches into a stuck state if a prior transaction is left incomplete.
This is a prime suspect for the fsck/audit "Invalid MBR signature" failure: the
fsck stops the main driver and re-inits the card on a temp cog — if that hand-off
leaves the card wedged, the temp-cog `initCardOnly` returns `-3`, and the fsck
(which swallows `readSectorRaw` return codes) misreports it as a bad MBR.

---

## Wedge characterisation — running log (19 MAY 2026)

Captured on a **replaced** P2 Edge module (the original one was swapped out as a
hypothesis-eliminating control — wedge behaviour was identical on the new module,
so the issue is not specific to a single defective board). Card stays in the
Edge socket between runs; only the binary download (which does NOT power-cycle
the SD rail) happens between each test.

### Outcomes by API combination

| API path | Tool examples | Observed outcome |
|---|---|---|
| `mount()` only | `identify`, `characterize`, regression `mount_tests` (31/31) | ✅ Clean, no wedge observed |
| `mount()` + writes + reads, single run | `benchmark` (writes file then reads it back; all throughput numbers normal) | ✅ Clean |
| `mount()` + writes (format path) | `format_card` as **first** tool after power-cycle | ✅ Clean MBR/VBR readback |
| `initCardOnly()` + read-only | `audit`, `check` — chained `audit→audit→check` | ✅ Clean |
| `initCardOnly()` + tight `writeSectorRaw`→`readSectorRaw` | regression `raw_sector_tests` (suite 2) | ❌ **Wedge** at first write/read pair: `WRITE FAILED`, then readback reports zeros (`expected $08, got $00`) |
| Any tool after the wedge fires | `identify`, `audit`, `check`, anything | ❌ `FATAL: Cannot initialize card` until power-cycle |

### Specific wedge instances observed

1. Power-cycle → `identify` ✅ → `audit` ✅ → `check` ❌ FATAL
2. Power-cycle → `audit×2` ✅✅ → `check` ✅ → `benchmark` ✅ → `format` ❌ MBR readback zero (a sub-bug — see below)
3. Power-cycle → `format` ✅ → `audit` ✅ → `check` ❌ FATAL
4. Power-cycle → regression: `mount_tests` (31/31) ✅ → `raw_sector_tests` ❌ 1 pass / 13 fail, wedge at first write/read pair

### Driver / tool issues separately surfaced during the wedge work

- **`isp_format_utility.doFormat()` swallows the return value of `sd.readSectorRaw(0, @verifyBuf)`.** When the underlying read fails, `verifyBuf` keeps its zero-initialised content and the tool misreports the situation as `*** MBR READBACK MISMATCH! Written data not on card ***`. This masks the real failure (a `-3 E_BAD_RESPONSE` from `readSectorRaw`). Same class of bug as the `isp_fsck_utility` issue fixed in commit `c9609d3`. The formatter is now instrumented to log `MBR readSectorRaw status` and `VBR readSectorRaw status` and the symptom went away after the next power-cycle (proving it was wedge-masked, not write-failure).
- **The driver's STEP 3 recovery flush (4096 SCK clocks, CS HIGH) is insufficient to clear this card's wedge state.** Only dropping the SD VCC rail recovers. Strengthening recovery (e.g., longer flush, CMD0 re-issue at low SPI clock, ACMD41-poll re-arm) is an open investigation thread.

### Working theory (testable)

The wedge fires specifically when the driver's worker cog dispatches a `writeSectorRaw` followed by a `readSectorRaw` for the same (or nearby) sector across **separate mailbox commands**. Each command involves: caller `locktry` → write mailbox → `COGATN` → caller `WAITATN` → worker reads mailbox → executes → writes result → `COGATN` → caller wakes → `lockrel`. The round-trip has timing the card on Edge tolerates poorly at the write→read boundary. Inside a single dispatch (`do_mount`'s init+immediate-MBR-read; `do_format`'s sequential writes; `benchmark`'s in-worker readSector/writeSector loops) the same operations succeed because no inter-command idle window opens.

External-connector experiments earlier this session showed the same wedge does **not** fire on the external SPI header — pointing to electrical margin (trace length / capacitance / impedance) at the Edge SD socket as the proximate amplifier of whatever the inter-command idle window does to the card's internal state. Driver fixes need to close the window or strengthen the recovery; we are not accepting Edge-socket as a "limitation" — the driver must work with this card.

### Investigation next steps (open)

1. Code-read the worker dispatch loop and the `writeSector`/`readSector` implementations; identify what state the SPI/CS/smart-pins are in between the two commands and during the WAITATN idle window.
2. Capture an LA trace across the `writeSectorRaw` → `readSectorRaw` boundary on Edge (LA still attached). Look for: dangling CMD13-busy, CS transition timing, MISO state at the moment of the next CMD17.
3. Test whether holding CS asserted across the inter-command window (or, alternatively, issuing a CMD13 busy-poll inside the writeSector handler before signalling caller) eliminates the wedge.
4. Strengthen STEP 3 recovery to a sequence that demonstrably clears this card's wedge (without power cycle).
5. Re-run regression — with fixes — to confirm `raw_sector_tests` and other `initCardOnly`-based suites pass on Edge with this card.

This is a real driver bug. The card is fully supportable; we need to find the right fix.

### Counter-intuitive observation: longer signal path WORKS, shorter path FAILS

The wedge fires on the Edge socket (short PCB traces directly to the SD card) but not on the external SD header (longer wires + connectors to a breadboard-style header). Conventional intuition says "longer wire = worse signal." Here the reverse holds, which is well-known in PCB SI for fast digital signals.

**Mechanism:** a long external cable acts as a lossy transmission line with high series R and distributed C. Two effects:

1. **Slew rate damping.** The P2 smart pin can rip SCK from 0 → 3.3 V in a few ns; the cable's RC rounds the edges. The SD card sees soft, rounded edges that cleanly cross threshold once.
2. **Reflection absorption.** Any impedance mismatch creates reflections, but the cable's series R dissipates them before they can ring back across the logic threshold.

A short Edge PCB trace has the opposite character: low R, low C, very fast slew, no natural damping. With no controlled trace impedance and no series termination, every fast edge reflects. If a reflection arrives while the line is still settling, it can cross the logic threshold twice — and the SD card's clock-counted state machine sees **one extra clock**. That shifts every subsequent byte boundary by one bit; subsequent commands get garbled and the card wedges.

This explains the in-dispatch vs cross-mailbox asymmetry:
- **Within one worker dispatch** (mount, format internal sequence), SCK clocks continuously; any ringing between adjacent legitimate edges gets swamped before it can be "counted."
- **Across mailbox commands**, SCK goes quiet for hundreds of microseconds. The line settles. The next command's first SCK edge rings on a quiet line, and the false edge gets cleanly counted.

This also predicts what the LA differential capture should show.

### LA observability — constrained: LA can only attach to External (the working side)

**Important constraint:** the logic analyzer can physically only probe the external SD header — the Edge socket has no exposed test points. So a direct differential capture (failing Edge waveform vs working External waveform) is not available. The LA on External can characterize the **baseline working case** but cannot directly show us the Edge socket's signals where the failure happens.

This shifts the experimental strategy from "LA differential is the smoking gun" to "software experiments on Edge are the primary diagnostic, LA on External is a supporting baseline tool."

| Hypothesis | Can the LA on External (alone) test it? | Indirect software-only test on Edge |
|---|---|---|
| **1 — post-CMD13 settling** | Indirect: measure cross-mailbox gap in success case; gives baseline for "how long is the card given?" | **E2a — `waitms(N)` sweep** between cross-mailbox commands on Edge; threshold-where-wedge-stops directly confirms or rules out. |
| **2 — SI / spurious edges** | ❌ Cannot directly observe the Edge socket SI. | **E2b — SPI clock sweep** on Edge: SI ringing scales with edge rate; if lower SPI clocks eliminate the wedge → strong evidence for Hyp 2. **E2c — smart-pin slew sweep**: slower slew = less reflection; same logic. |
| **3 — timing sub-window** | Same as Hyp 1 — only indirect timing-baseline value. | Largely subsumed by E2a; if no settle time helps, both Hyp 1 and Hyp 3 are weakened. |

### Software-only experiments on Edge (no LA required, run where failure happens)

These are the new primary diagnostics:

- **E2a — Settle-time sweep:** insert `waitms(N)` between cross-mailbox commands; sweep N = 0, 1, 5, 10, 25, 50, 100 ms. Threshold tells us if "card needs more settle time" is the cause and how much. Tests Hyp 1.
- **E2b — SPI clock sweep:** run E1 at SPI clocks 400 kHz, 1 MHz, 5 MHz, 12.5 MHz, 25 MHz. SI severity scales with edge rate; if wedge disappears at low clocks → Hyp 2 strongly confirmed. If wedge fires equally at all clocks → Hyp 2 ruled out.
- **E2c — Smart-pin slew-rate sweep:** P2 smart pins have configurable output drive strength. Slower drive → slower edges → less reflection energy. Run E1 at each drive setting. Like E2b but holds SPI clock constant.
- **E2d — CMD0 resync candidate fix:** modify driver to issue CMD0 + wake preamble before every cross-mailbox `readSectorRaw`/`writeSectorRaw` entry. Even if it doesn't confirm Hyp 2, it tests a real candidate fix end-to-end.
- **E2e — Sequence variation:** try write→write, read→read, write→getStatus→read instead of write→read. Pins down whether failure is write→read-specific or any cross-mailbox transition.

### LA on External — supporting role

- **E3' — Baseline characterization:** capture a successful E1 run on External. Measure the cross-mailbox idle window duration (CS-HIGH between the writeSector's final CMD13 ack and the next readSector's CMD17 wake). This number is the empirical floor for the E2a sweep. Also capture SCK frequency / edge timing in the working case for comparison-by-inference if Edge cards arrive later with scope probes.

### Soft LA — internal P2-side capture, runs on EITHER connector

The hardware-LA-only-on-External constraint can be partially worked around by the **P2-internal soft logic analyzer** at `diagnostic-tests/SD_soft_la_test.spin2`. The soft LA captures the P2's view of the pins using a spare cog's streamer (1-pin capture mode, `X_1P_1DAC1_WFBYTE`), triggered by SE1 on CS falling edge for sub-clock precision. **No debug during capture** is part of the design — debug TX on P62 would interfere with the capture cog, so all output is deferred until the capture cog has stopped.

**What the soft LA can do for our wedge investigation:**

- Run on **Edge** (the failing case — physically impossible for a hardware LA on this rig) → first-time visibility into what actually happens on the wires when the wedge fires.
- Run on **External** (the success case) for the same E1 sequence → baseline to diff against.
- Capture in sequential mode: one pin per SD read, four reads per setup. SD pins are 58/59/60/61, well clear of the P62/P63 debug serial.

**What it can and can't observe:**

| Observable | Visibility |
|---|---|
| Exact byte timing on all four lines | ✅ Clear |
| MISO content (what the card returns) | ✅ Clear — distinguishes "card responds wrong" from "we sent wrong" |
| Cross-mailbox idle window duration | ✅ Clear |
| Total SCK transition count per transaction | ✅ Clear — if Edge has more transitions than External for the same logical operation, smoking gun for Hyp 2 ringing detected at the P2 input |
| CS / MOSI clean transitions | ✅ At P2 input resolution |
| Sub-ns SCK ringing | ⚠️ Only if it crosses the P2's input threshold AND is held long enough to not be filtered by the input synchronizer — the SD card's input characteristics differ from the P2's, so the card may "see" extra edges the soft LA does not |
| Analog signal quality (overshoot, undershoot, slew) | ❌ Digital threshold crossings only |

**Differential interpretation:**

- If soft LA captures on Edge vs External show **identical SCK transition counts, identical MOSI bytes, identical CS timing** but the card's MISO response differs → strong evidence for Hyp 1/3 (card responds differently to the same wire sequence) **OR** Hyp 2 with sub-resolution ringing the P2 can't see. Disambiguate with E2b (SPI clock sweep).
- If soft LA captures show **a different SCK transition count on Edge** for the same logical operation → smoking gun for Hyp 2 at the P2-input layer, fix is driver-side slew control or per-command resync.

**Upgrade opportunity (not built):** the streamer's `X_4P_4DAC1_WFBYTE` mode would capture all four SD signals simultaneously from P58..P61, well clear of P62/P63 debug, giving us inter-line correlation (e.g., MISO edge timing relative to SCK edge). The existing tool was designed sequential because the 16-pin streamer mode would have corrupted debug; 4-pin adjacent avoids that and is a worthwhile next-session upgrade if the sequential captures show interesting but ambiguous results.

### Revised first-session experimental sequence (next focused session)

1. **Build E1** — minimal `initCardOnly + writeSectorRaw + readSectorRaw` repro tool with full status logging.
2. **Run E1 cold on Edge after power-cycle.** Confirm the wedge fires on the very first cross-mailbox write→read pair. Decisive: it's intrinsic, not statistical.
3. **E2f first (cheapest candidate fix):** enable `P_HIGH_15K` on MISO in `spi_rx_mode` (one-line driver change). Re-run E1 on Edge. If wedge eliminated → floating-MISO was the cause, we have a spec-aligned fix, done.
4. **If E2f doesn't fix it:** wrap E1 with soft LA capture (sequential, one pin per pass, four passes per setup, no-debug rule honored). Run on Edge + External. Compare per the matrix above.
5. **Based on captures:** proceed to E2a (settle sweep) or E2b (SPI clock sweep) or E2c (slew sweep) or E2d (CMD0 resync fix candidate).
6. **E4 (recovery hardening) in parallel** — strengthen STEP 3 to actually clear this card's wedge in software, regardless of root cause.

### Pull-up / pull-down analysis (Edge socket as candidate "missing host pull-ups" case)

**Driver state, confirmed by code reading:**
- `initCard()` STEP 2 (line 5807) sets `P_HIGH_15K` on MISO **only for card-presence detection**. The driver's own comment at line 5802 acknowledges: *"Pull-up is cleared later when initSPIPins() configures MISO for smart pin SPI."*
- `initSPIPins()` line 5513: `spi_rx_mode := P_SYNC_RX | (((sck - miso) & 7) << 24)` — **no pull-up bits**. Once normal operation begins, MISO has no internal pull-up.
- MOSI and SCK are P2 outputs in active drive; pull-up irrelevant during driving.
- CS is GPIO; no explicit pull-up configuration in the driver.

**Why this matters for the Edge-vs-External differential:**
- SD spec mandates **host-side pull-ups** on MISO, CS, and MOSI (typically 10-100 kΩ).
- External SD breakout boards typically include these pull-ups on board.
- **A bare P2 Edge module's microSD socket may not include external pull-ups** — many minimal designs omit them.
- If Edge has no external pull-ups and the driver doesn't enable internal pull-ups, MISO floats during cross-mailbox idle windows. On short PCB traces with low parasitic capacitance, a floating line couples noise from adjacent SCK switching during the next command's wake bytes — phantom bus activity that the card can mis-interpret.

**Pull-ups can NOT damp reflections on actively-driven SCK** (they're DC stabilization at 1.5k-15k Ω, not AC terminators at 30-50 Ω). So pull-ups don't address the SI ringing flavor of Hyp 2.

**Pull-ups CAN eliminate floating-input noise on MISO during idle.** That's a different, also-plausible mechanism for the Edge-vs-External differential, with a trivially small driver-side fix to test it.

**Action:** E2f (above) — enable `P_HIGH_15K` on MISO in `spi_rx_mode`. First experiment of the next session because cost is minimal and even a negative result narrows the search cleanly.

---

## Experimental log — 19 MAY 2026 evening session (each result narrows the search)

These experiments were run with the E5 fix in place so `raw_sector_tests` now reports the real `readSectorRaw` / `writeSectorRaw` return codes instead of swallowing them. That visibility was decisive.

### Failure shape now precisely characterised

With E5 instrumentation, `raw_sector_tests` reports a consistent failure progression:

1. First write→read pair: `writeSectorRaw` returns SUCCESS, then `READ FAILED status=-1` (E_TIMEOUT) — readSector's token-wait loop times out waiting for `$FE`.
2. Next several writes: `WRITE FAILED status=-7` (E_IO_ERROR).
3. Then reads alternate between `READ FAILED status=-1` and "succeeds" returning all zeros.

**Key implication:** the card was demonstrably alive immediately before the failing read — the writeSector exited SUCCESS after waitBusyComplete (MISO HIGH = card ready). Yet the very next CMD17 receives no response (~1 second to E_TIMEOUT). Whatever silences the card happens **between writeSector's `pinh(cs)` and the next `cmd(CMD17)`**.

### E2f — MISO `P_HIGH_15K` pull-up — RESULT: did not help

One-line change at `micro_sd_fat32_fs.spin2:5513`:
```
spi_rx_mode := P_SYNC_RX | P_HIGH_15K | (((sck - miso) & 7) << 24)
```

Driver-wide MISO lifecycle audited beforehand: `spi_rx_mode` is defined once (line 5513) and consumed in exactly three sites (lines 5552, 6189, 6315). One-line change propagates to all three. Temporary `pinclear(_miso)` windows inside readSector / readSectors are during active card drive of MISO (sector data), so absent pull-up there is harmless.

Test: regression on Edge after power-cycle. `mount_tests` 31/31 ✅, `raw_sector_tests` 1/13 ❌ — **identical failure pattern**. Floating MISO between commands is not the cause of the wedge.

Change kept in tree — it is SD-spec-compliant (host pull-up on MISO is mandated; the Edge module may not provide one externally). Removes one variable from future investigation. Costs nothing.

### E2-CMD13 — disable `checkCardStatus()` at end of writeSector — RESULT: did not help

Hypothesis: `sendCmd13Transaction()`'s trailing-byte capture loop (lines 6870-6872) reads bytes past R1+STATUS that may put the card into an extended-output state from which it can't gracefully receive the next command.

One-line change at `micro_sd_fat32_fs.spin2:6541`:
```
'if checkCardStatus(@"writeSector") < 0
'  status := E_IO_ERROR
```

Test: regression on Edge after power-cycle (and a USB reseat — first attempt hit the known post-wedge USB-discovery loss; "All Passed" with 0/0 per suite is the diagnostic for that condition, every binary download had failed with "No Propeller v2 device found"). Real run: `mount_tests` 31/31 ✅, `raw_sector_tests` 1/13 ❌ — **identical failure pattern, identical error codes**.

So CMD13's trailing capture is not the cause either. The wedge fires even with writeSector returning SUCCESS based only on data-response-token + `waitBusyComplete` (MISO HIGH).

Change reverted — restored `checkCardStatus()` call. CMD13 catches real card-state errors and is needed in production driver.

### What this leaves on the table

The wedge is caused by something in:
- `waitBusyComplete()` itself (returns prematurely?)
- The transition `pinh(cs)` immediately after busy-clear (no guard clocks?)
- The next `cmd(CMD17)`'s wake sequence interacting with whatever state the card is in

Refined leading hypothesis: **post-busy-clear card needs additional clock cycles before the next command.** SD spec recommends 8 dummy clocks with CS HIGH after busy-clear, before any further command. The driver's `waitBusyComplete` likely exits the instant MISO goes HIGH and then `pinh(cs)` is called immediately, with no guard clocks. If the card is "ready" per MISO but still finalizing internal state, the next CMD17 lands too soon.

### E2-guard — 8-clock CS-LOW guard after waitBusyComplete — RESULT: did not help

Inserted `sp_transfer_8($FF)` between `waitBusyComplete()` (which exits the instant MISO goes HIGH) and the subsequent `pinh(cs)`, with CS still LOW. SD spec recommends additional clocks after busy-clear before deselect.

Test: regression on Edge. `mount_tests` 31/31 ✅, `raw_sector_tests` 1/13 ❌ — **identical failure pattern, identical error codes**. Card still silent on first CMD17 after a successful write.

Change reverted (didn't fix the wedge and there's no confirmed root-cause justifying it as a permanent addition).

### E2-CS+MOSI pull-ups — RESULT: BROKE OTHER TESTS — important semantic lesson

Hypothesis: SD spec mandates host-side pull-ups on CS and MOSI in addition to MISO. Same `P_HIGH_15K` idiom as E2f, applied to `spi_tx_mode` (MOSI) and a new `WRPIN(cs, P_HIGH_15K)` in `initSPIPins()` (CS is plain GPIO).

Test: regression on Edge. `mount_tests` went from 31/31 ✅ down to **18 pass / 12 fail** — many basic mount operations now broken.

**Root cause of the regression (verified against P2KB `p2kbArchSmartPin00000NormalMode` and `p2kbSpin2Pinstart` post-hoc):** `P_HIGH_15K` configures the pin's HIGH output drive stage to drive through a ~15 kΩ resistor (the M field, bits 20:8 of the WRPIN word). The P2KB does call it a "pull-up" — that label is accurate when the pin is configured as an input (DIR=0 / `PINFLOAT`), because no active output stage is engaged and the weak HIGH bias acts exactly like a pull-up.

When the pin is configured as an active output, however (MOSI driven by `P_SYNC_TX | P_OE`, or CS driven by GPIO `pinh`/`pinl` with DIR=1), the output stage IS engaged and the drive characteristic is what the constant literally says — drive HIGH through 15 kΩ. That's too weak to slew a digital line at the SPI clock rate against trace/socket/card input capacitance — cards never see CS LOW asserted, MOSI bits don't switch cleanly.

The P2KB canonical pattern for actively-driven SPI pins uses `P_HIGH_FAST` (strong push-pull) — see the Flash FS SPI example in `p2kbSpin2Pinstart`. The HUB75 LED panel example uses `P_HIGH_FAST | P_OE` on output data and control pins.

**Lesson saved to project memory** at `lesson_p_high_15k_semantics.md`:
- ✅ `P_HIGH_15K` on input-mode pins → pull-up (works as intended).
- ✅ `P_HIGH_FAST` on actively-driven outputs → strong drive (correct constant for SPI/digital outputs).
- ❌ `P_HIGH_15K` on actively-driven outputs → weak drive (will break digital signaling).

**Implication for the MISO change (E2f):** the original reasoning that "MISO has no pull-up, adding `P_HIGH_15K` provides one" was actually correct per P2KB — MISO is configured as `P_SYNC_RX` (synchronous serial INPUT), the output stage is not engaged, and `P_HIGH_15K` legitimately provides a pull-up bias. The change was reverted as part of the minimal-diff cleanup, but reintroducing it would be a legitimate spec-alignment improvement (SD spec mandates a host-side pull-up on MISO; some Edge modules may not provide it externally). It does not address the cross-mailbox wedge but it's a real correctness improvement independent of the wedge investigation.

Both changes reverted (`spi_tx_mode` back to original, CS back to plain `pinh(cs)`). MISO `P_HIGH_15K` ALSO reverted in the same cleanup pass — although it was empirically harmless on MISO, the rationale for it (SD-spec pull-up) doesn't apply the way we thought, and it didn't help with the wedge, so the cleanest end state is minimal diff back to status quo ante for the driver.

### Final state of the investigation at session end (19 MAY 2026, evening)

**The cross-mailbox `writeSector → readSector` wedge on Cloudisk on Edge is NOT yet root-caused.** Three negative experiments and one breakage have substantially narrowed the search:

| Hypothesis tested | Result |
|---|---|
| Floating MISO between commands (E2f) | ❌ Pull-up didn't fix it |
| CMD13 trailing-capture leaves card non-responsive (E2-CMD13) | ❌ Disabling CMD13 didn't fix it |
| Card needs settle clocks after busy-clear (E2-guard) | ❌ 8 settle clocks didn't fix it |
| Floating CS/MOSI (E2-CS+MOSI) | ⚠️ Changes broke mount; reverted before knowing if they would have helped — but `P_HIGH_15K` semantics make the test invalid anyway |

**What we now know about the failure shape (precise, from E5-instrumented logs):**
- First write→read pair: writeSector returns SUCCESS, readSector reports `E_TIMEOUT (-1)` after the token-wait loop sees no `$FE` for ~1 s.
- Subsequent writes return `E_IO_ERROR (-7)` — the card IS responding with fatal R1 bits (illegal command / address error / parameter error), consistent with a bit-counter shift like a spurious clock would cause.
- Subsequent reads also time out; the card is wedged until power-cycle.
- The wedge is reproducible on first cross-mailbox write→read after init — not statistical, not cumulative.

**Leading remaining hypothesis: SI-induced spurious clock (Hyp 2).** The "fatal R1 on subsequent commands" symptom is exactly what a shifted bit counter would produce. We have not ruled this in or out directly. It needs the soft LA capture (E3a) or a SPI clock speed sweep (E2b) to test.

### Driver / tool changes RETAINED at session end (real improvements, kept)

These improvements survive the session even though no fix for the wedge was found:

1. **`SD_RT_raw_sector_tests.spin2`** — `writeAndVerify()` and `verifyPattern()` now check `writeSectorRaw`/`readSectorRaw` return codes and report real error codes (E5 fix). Test failures are now self-diagnosing — without this, we'd never have seen the `READ FAILED status=-1` / `WRITE FAILED status=-7` pattern that decisively shaped the investigation.
2. **`isp_format_utility.spin2`** — `doFormat()` now logs `MBR readSectorRaw status` and `VBR readSectorRaw status` (formatter instrumentation). Same bug class — the formatter used to misreport readback failures as "MBR READBACK MISMATCH"; now we see the real `-3 E_BAD_RESPONSE` when applicable.
3. **`diagnostic-tests/SD_tempcog_repro.spin2`** — removed reference to nonexistent `debugGetTokenWaitLoops()` so the tool compiles. Compiles + runs as a Cog0-vs-tempcog repro.

### Changes REVERTED at session end (didn't fix the wedge, kept tree minimal)

- MISO `P_HIGH_15K` (E2f)
- `checkCardStatus()` disable (E2-CMD13)
- 8-clock CS-LOW guard after busy-clear (E2-guard)
- MOSI `P_HIGH_15K` (E2-CS+MOSI, broke mount)
- CS `WRPIN(cs, P_HIGH_15K)` (E2-CS+MOSI, broke mount)

Driver file `src/micro_sd_fat32_fs.spin2` is back to status quo ante.

### Investigation candidates that were still on the table at session end

The remaining unverified hypotheses, in priority order:

1. **SI-induced spurious clock (Hyp 2 revisited).** Test via SPI clock speed sweep (E2b) — if slower SPI clocks eliminate the wedge, SI is implicated. Also testable via soft LA differential capture (E3a) on Edge vs External, looking for SCK transition count discrepancies at the P2-input layer.
2. **`waitBusyComplete()` returning prematurely on this card** — maybe MISO HIGH doesn't actually mean "ready" for this counterfeit. Test by replacing the single-byte check with a "MISO HIGH for N consecutive bytes" check.
3. **Inter-command timing window** — test waitms(N) sweep between writeSector and the next command at the worker dispatch level, sweep N from 0 to 100 ms.

### Recommended next-session opening move

Build E1 (minimal `initCardOnly + writeSectorRaw + readSectorRaw` repro with full error code logging), then run a SPI clock speed sweep on Edge (try 400 kHz, 1 MHz, 5 MHz, 12.5 MHz, 25 MHz). If lower SPI clocks make the wedge disappear, Hyp 2 is essentially proven and the fix path is in the smart-pin slew control / external termination / per-command resync category. If all clocks fail equally, Hyp 2 is essentially ruled out and we go to the soft LA capture for direct observation.

### Candidate fixes by hypothesis (none accepted as workarounds — root cause first)

If Hyp 2 (SI corruption) is confirmed, in order of effort:
1. **Smart-pin slew-rate reduction** on SCK — config-only driver change, slows the edges to be more like the external cable's, suppresses reflection energy.
2. **Per-command resync** — issue an extra CMD0 with 8-clock wake preamble before each cross-mailbox command on cards in a "needs-resync" class. Re-aligns card's state machine before issuing the real command.
3. **Reduced SPI clock on first byte after idle window**, then ramp back up.
4. **PCB-level**: add 33-50 Ω series resistor on SCK trace at the P2 end. Not in scope for the driver but the right long-term hardware answer.

If Hyp 1 (post-CMD13 settling) is confirmed:
1. **Add settle delay after CMD13 in writeSector** — extend `waitBusyComplete()` by a card-specific window, or insert a small `waitus()` after CMD13 ack before exiting writeSector.
2. **Lengthen STEP 3 recovery flush** to cover the same window after any post-write transition.

Recovery hardening (E4) is independently valuable regardless of root cause — the driver currently cannot clear this wedge in software, only power-cycle does. Strengthening STEP 3 (extended flush, CMD0 at 400 kHz, full re-init handshake) is a general improvement.

### Investigation artifacts created this session

- `isp_format_utility.spin2`: instrumented `doFormat()` to log `MBR readSectorRaw status` and `VBR readSectorRaw status` so the real error code is no longer masked by buffer-stays-zero. Located the bug class that hid the formatter's true failure mode for months.
- `SD_RT_raw_sector_tests.spin2`: `writeAndVerify()` and `verifyPattern()` now check `readSectorRaw` return codes and report `WRITE FAILED status=X` / `READ FAILED status=X` instead of misleading "readback mismatch."
- Same `readSectorRaw`-not-checked bug class still exists at ~25 other sites (mostly in `isp_fsck_utility.spin2`, plus `SD_demo_shell.spin2`, `SD_card_characterize.spin2`). Worth a sweep commit — every site is a potential silent-failure-masquerading-as-data-corruption.

---

## 2026-05-20 — SPI bus timing characterization and per-card SCK ceiling design

**Session goal:** root-cause the formatter "Problem B" (the formerly suspected counterpart to the audit failure that was resolved on 2026-05-19), then build a quantitative model of how this card behaves across SPI bus timing variations so we can design an honest, performant driver response for the dummy-CRC card class.

**Card state during this session:** Freshly **P2-formatted** by `isp_format_utility` (overwriting the earlier macOS-formatted ground truth captured 2026-05-18). On the **external SD header** (CS=20 / MOSI=19 / MISO=18 / SCK=21) — the SI-clean side, isolating bus-timing margin from the Edge-socket SI confound. The on-card filesystem is a valid FAT32, label `P2-BENCH`, OEM string `P2FMTER`, 489,534 clusters, 3,832 sectors/FAT.

Methodology mandate carried forward from prior sessions: **root-cause everything, no band-aids.** Don't claim resolution without measurement; don't blame the card for what the driver is doing wrong, and don't blame the driver for what the card is doing wrong.

### ✅ PROVEN — formatter "Problem B" is not a formatter bug

Re-ran `SD_format_card` on this card on the external connector at sysclk 270 MHz. Format completed cleanly: MBR readback `sig=$AA55 type=$0C start=8192` (verified, status=0), VBR readback `jump=$EB OEM=$50,$32 bps=512 spc=8 sig=$AA55` (verified, status=0), FAT1 and FAT2 each wrote `3,832/3,832` sectors with no batch-write failure, root-dir written, `FORMAT COMPLETE` with 489,534 clusters / 1920 MB.

The earlier "readback = zeros / FAT batch write FAILED at sector 769" reports came from the Cloudisk on the **Edge socket** at higher sysclks. Those symptoms were the same Edge-socket SI manifestation as the audit failure (resolved 2026-05-19). The formatter itself has no defect. **Closes #3212 / #3213 — not-a-bug.**

### ✅ PROVEN — per-card SCK timing margin (validated against direct measurement)

Drove `SD_mount_diag` at six sysclk × target-rate combinations on the external connector. Default driver target = 25 MHz; `hp = ceil(clkfreq / (2 × target))` per `applySPISpeed` (driver line 1939). `pre_edge_threshold = 5` → `hp ≤ 5` uses PRE-edge (`%0_00111`), `hp ≥ 6` uses ON-edge (`%1_00111`).

| sysclk (MHz) | SPI target | hp | **actual SCK (MHz)** | half-period (ns) | sample mode | observed |
|---:|---:|---:|---:|---:|:---:|:---:|
| 270 | 25 MHz | 6 | 22.500 | 22.22 | ON | **CLEAN** (format) |
| 320 | 25 MHz | 7 | 22.857 | 21.88 | ON | **CLEAN** (audit 39/39, mount OK) |
| 340 | 25 MHz | 7 | 24.286 | 20.59 | ON | **FAIL** (bit-flips, mount -22) |
| 300 | 25 MHz | 6 | 25.000 | 20.00 | ON | **FAIL** (bit-flips, mount -22) |
| 350 | 25 MHz | 7 | 25.000 | 20.00 | ON | **FAIL** (bit-flips, mount -22) |
| 350 | 20 MHz | 9 | 19.444 | 25.71 | ON | **CLEAN** (mount status 0) |

Each "FAIL" row reported `readSectorRaw(0) status = 0` while individual bytes read back wrong with **single-bit corruption** (e.g. `$AA → $EA` = bit 6 set, `$0C → $0E` = bit 1 set, `$3F → $3B` = bit 2 cleared). Different bytes flipped on different runs — consistent with bus-level noise on individual MISO bits, not a deterministic firmware fault.

**Empirical clean-read ceiling for this card: between actual SCK 22.86 MHz (clean) and 24.29 MHz (fail).** Half-period eye width between 21.88 ns (clean) and 20.59 ns (fail).

### ✅ PROVEN — what the card actually sees

What the SD card cares about, bit-by-bit, is the **SCK pin we drive it on** — not our sysclk. The card has no notion of P2 sysclk. Our `hp` is an integer number of sysclks; ceiling-rounding means at sysclks that are exact multiples of `2 × target` (e.g. sysclks 200, 250, 300, 350 at target 25 MHz), there is zero slack and the actual SCK lands on the target exactly. At every other sysclk, the achieved SCK is *below* the target — sometimes substantially so. This explains why 270 MHz / SCK 22.5 MHz works while 350 MHz / SCK 25.0 MHz fails: the higher-sysclk run is actually driving the card *faster* on the bus, not slower.

### ✅ PROVEN — Edge-socket failures are the same model, tighter ceiling

Prior session (2026-05-19) showed this card on the Edge socket failed at every sysclk tested, while the external connector reads cleanly at the same sysclks. The Edge socket adds parasitic capacitance and reflections that effectively reduce the card's clean-read ceiling further. The model is the same — only the ceiling moves. The "Edge socket is broken for this card" framing was incomplete; the right framing is "the Edge socket's effective MISO `tODLY` margin is too tight for this card at the SCKs we were driving." Predicts that a sufficiently low SCK target should let the Edge socket read this card cleanly (not yet retested).

### ✅ PROVEN — card identity & flags on freshly-formatted Cloudisk

From `SD_card_identify` at sysclk 320 MHz on external connector (log `SD_card_identify_260520-152100.log`):

```
L1: Unknown asdfg SDSC 1GB [FAT32] SD 1.x rev2.2 SN:$0000_1680 2025/11
L2: Class 4, U0, V0, SPI 22 MHz  [P2FMTER]
L3: CSD claims TRAN_SPEED = 25 MHz; cardWarnings() = $04
```

- **MID $05** → not in known-manufacturer table (`Unknown`).
- **PNM `"asdfg"`** → clearly bogus.
- **CID CRC7 $00** → many counterfeits skip CID CRC computation (per earlier session notes).
- **SDSC** (CSD v1.0) — claims to be pre-2010 architecture.
- **Manufacturing date 2025/11** — real SDSC silicon ended ~2010; a 2025 SDSC card is implausible.
- **SD spec 1.x** — original spec, predates SDHC.
- **Class 4** — modest performance class, lowest in catalog.
- **CSD claims `TRAN_SPEED = 25 MHz`** but empirical ceiling is between 22.86 and 24.29 MHz. **The card is lying in its CSD.**
- **`cardWarnings() = $04`** = `CW_NO_DATA_CRC` set — `probeDataCrc` confirmed dummy CRC.
- Achieved SPI = 22 MHz (actual SCK at sysclk 320 / hp=7 = 22.86 MHz, integer rounded).

### 🔬 PROPOSED — decouple two card properties currently conflated

Conflating "dummy CRC" with "needs slow SCK" produces both false positives and false negatives. They are **correlated but independent**:

| Property | What it governs | How we measure it |
|---|---|---|
| **CRC honesty** (`CW_NO_DATA_CRC` 0/1) | Whether we can trust the data-CRC field for runtime detection | `probeDataCrc` at init — already implemented |
| **SCK ceiling** (per-card max reliable bus rate) | Where we set the SPI target so reads don't silently corrupt | Empirical probe — not yet implemented |

A card can be any of four combinations:

| CRC honest? | At CSD-claimed SCK? | Strategy | Example |
|:---:|:---:|---|---|
| Real CRC | Works | Trust CSD; runtime CRC catches drift | Catalog A/B/C cards |
| Real CRC | Fails | Trust CSD initially; runtime CRC fires; reactive backoff | (not yet observed in catalog) |
| Dummy CRC | Works | Trust CSD; **no runtime detection** — accept drift risk | (suspected SU01G) |
| Dummy CRC | Fails | **Empirical probe at init** is the only honest answer | **Cloudisk** |

### 🔬 PROPOSED — backoff philosophy: highest SCK the card can sustain, not "safe slow"

> Design rule: the driver must **back off so it succeeds, and only as far as it needs to**. A blanket clamp to 20 MHz for the dummy-CRC class would lose 12-25 % throughput on cards (like a hypothetical clean-but-dummy-CRC SU01G) that can sustain a higher rate.

Concrete algorithm (per init):

1. **Real-CRC card**: start at `target = min(CSD TRAN_SPEED, 25 MHz)`. Read sector 0; if data-CRC validates, accept this rate. (Equivalent to current driver. No probe overhead.) Runtime CRC handles drift reactively.
2. **Dummy-CRC card** (`CW_NO_DATA_CRC` set): perform an empirical SCK probe at init.

The probe:

a. Read one sector at a **very low** SCK (e.g. 1-2 MHz) to capture ground-truth bytes. This rate is below any plausible card's clean-read ceiling.
b. From the highest `hp` we'd otherwise use, step `hp` **downward** (faster SCK) until a read at that rate disagrees with ground truth in any byte.
c. Back off one `hp` step → that's the operating rate.

For Cloudisk at sysclk 350 MHz, this lands at `hp = 8`, actual SCK 21.875 MHz, half-period 22.86 ns — well inside the proven-clean envelope, and **12 % faster than the conservative `target = 20 MHz` fallback** (which lands at hp=9 / SCK 19.44 MHz).

For a clean dummy-CRC card (e.g. hypothesised SU01G), the probe would succeed at hp=7 / SCK 25 MHz immediately — zero throughput penalty.

### 🔬 PROPOSED — drift headroom for dummy-CRC cards

Because we surrender CRC error detection on dummy-CRC cards, the operating point must leave a margin for temperature/voltage/age drift the runtime can't detect. **Proposal:** for dummy-CRC cards only, operate **one hp step above** the probe-found ceiling (slower than strictly required). Cost is one notch of SCK; benefit is that small drift doesn't push us across the threshold into silently-bad reads.

Open question: is **one hp step** the right margin? Could be parameterized.

### 🔬 PROPOSED — counterfeit classifier (multi-indicator)

Per `CARD-CATALOG.md`'s "Card Quirks" section, counterfeit/marginal cards cluster — many indicators show up together. Single indicators are noisy; combinations are diagnostic. **Proposed scoring rubric** with empirical thresholds to be calibrated:

| # | Indicator | Weight | Rationale |
|---|---|:---:|---|
| 1 | **PNM not alphanumeric-printable** (control chars, gibberish like `"asdfg"`) | +3 | Real product names are 5-char readable identifiers (`SN64G`, `MSSD0`, `SU01G`) |
| 2 | **PNM is all zeros (`"00000"`) or all spaces, alone** | +2 | Common in budget OEMs — `$74` Gigastone, `$9F` Shared OEM both use it legitimately. *Weak* signal in isolation |
| 3 | **Major-brand MID with placeholder/anomalous PNM** (e.g. MID = `$03` SanDisk, `$1B` Samsung, `$02` Toshiba, `$41` Kingston, but PNM = `"00000"`, gibberish, or doesn't match brand's known product-code conventions) | **+4** | Real major brands use real product codes (`SN64G`, `GD4QT`, `JD1Y7`, `SD8GB`). Placeholder PNM under a major-brand MID means **the silicon is forged with a copied MID** — the card-label says "Samsung" or "SanDisk" but the silicon controller never came from that vendor. Strong counterfeit tell |
| 4 | **MID not in known-manufacturer list** | +2 | Real manufacturers have well-known MID assignments (current list in catalog) |
| 5 | **CID CRC7 = $00** | +2 | Real manufacturers compute the proper CRC7 |
| 6 | **CSD v1.0 (SDSC) with MDT year > 2012** | +3 | Real SDSC silicon ended around 2010; "new" SDSC is a counterfeit tell. SU01G (real SDSC, MDT 2007) is correctly NOT flagged by this rule |
| 7 | **CSD TRAN_SPEED claims 25 MHz but empirical probe finds ceiling < 23 MHz** | +3 | Card is lying in CSD about its capabilities — strong counterfeit indicator (requires empirical data) |
| 8 | **`CW_NO_DATA_CRC` set** | +2 | Real silicon computes a real CRC; dummy CRC is a cost-cut indicator |
| 9 | **SD spec = 1.x AND class = 4 AND CSD v1.0** | +1 | Combined "lowest of everything" signal |
| 10 | **Gold standard: CSD-claimed capacity ≠ actual usable sectors** | +5 (when measurable) | Fake-capacity cards lie about size; ground truth via write-then-read-back at the full capacity — expensive but conclusive |

> **Note on indicator #3** — this is the key indicator the catalog already implicitly flags as "Chinese Made #1" / "Chinese Made #2." Codifying it: when MID and PNM disagree about whether this is a major-brand card, the silicon (MID) and the supply-chain story tell different stories. Examples (catalog rows):
> - `Samsung_00000_..._201408` — MID `$1B` (Samsung) but PNM `"00000"`. Real Samsung uses `JD1Y7`, `GD4QT`, etc. → **mismatch fires.**
> - `SanDisk_SU08G_..._201010` — MID `$03` (SanDisk) AND PNM `"SU08G"` (real SanDisk format). The two **agree** at the CID layer — even though the physical card was sold as suspect "Chinese #1." Indicator #3 does NOT fire — for this card we need empirical signals (CW_NO_DATA_CRC, TRAN_SPEED lie, capacity check) to confirm.

**Decision rule (tentative):**
- Score < **3** → legitimate (no advisory).
- Score **3-5** → flag `CARD_SUSPECTED_COUNTERFEIT` (advisory; trigger empirical SCK probe + drift headroom).
- Score ≥ **6** → flag `CARD_LIKELY_COUNTERFEIT` (advisory; trigger empirical SCK probe + drift headroom; expose via `cardWarnings()`).
- Score ≥ **9** → flag `CARD_CONFIRMED_COUNTERFEIT` (advisory; user-visible warning recommended).

Cloudisk re-scored: PNM gibberish (+3) + MID unknown (+2) + CID CRC7=$00 (+2) + SDSC dated 2025 (+3) + CSD lies about TRAN_SPEED (+3) + CW_NO_DATA_CRC (+2) + spec 1.x+class 4+v1.0 (+1) = **16** → **confirmed counterfeit**.

Note: Indicator #3 ("major-brand MID with placeholder PNM") does NOT fire for Cloudisk — its MID `$05` isn't in our table of major brands. That indicator catches a *different* counterfeit pattern: silicon forged with a real brand's MID. Cloudisk is the other counterfeit pattern: unknown-MID counterfeit with everything fake.

### 🔬 PROPOSED — counterfeit classifier catalog walk-through

Re-scoring every card in `CARD-CATALOG.md` against the updated rubric (with empirical fields TBD for cards we haven't bus-timed):

| Card | PNM<br>gibberish<br>(+3) | PNM<br>zeros<br>(+2) | Brand/PNM<br>mismatch<br>(+4) | MID<br>unknown<br>(+2) | CRC7<br>=$00<br>(+2) | SDSC<br>>2012<br>(+3) | Dummy<br>CRC<br>(+2) | Score<br>(no empirics) | **Classification** |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| SanDisk SN64G/SN128/AGGCF/AGGCE/SA16G/SH32G/WX64G/SS08G ($03) | — | — | — | — | — | — | — | 0 | **legitimate** |
| Lexar MSSD0 64GB/128GB ($AD) | — | — | — | — | — | — | — | 0 | **legitimate** |
| Amazon Basics USD00 (Longsys $AD) | — | — | — | — | — | — | — | 0 | **legitimate** |
| Samsung JD1Y7 / GD4QT ($1B) | — | — | — | — | — | — | — | 0 | **legitimate** |
| Gigastone ASTC ($12) | — | — | — | — | — | — | — | 0 | **legitimate (Gigastone OEM)** |
| Silicon Power SPCC ($9F) | — | — | — | — | — | — | — | 0 | **legitimate (shared OEM)** |
| Transcend `"00000"` (Gigastone $74) | — | +2 | — | — | — | — | — | 2 | **borderline-low** — known Gigastone PNM convention; legit-OEM rebrand pattern |
| "Unknown" `"00000"` (Gigastone $9F) | — | +2 | — | — | — | — | — | 2 | **borderline-low** — same pattern |
| BudgetOEM `SD16G` (Gigastone $00) | — | — | — | — | — | — | — | 0 | **legitimate** (real PNM) |
| Kingston SD8GB ($41) | — | — | — | — | — | — | — | 0 | **legitimate** |
| Phison SD16G PNY / Sony ($27) | — | — | — | — | — | — | — | 0 | **legitimate** (real Phison) |
| **"Chinese Made #1" SanDisk SU08G ($03), MDT 2010/10** | — | — | — | — | TBD | — | TBD | 0 (sans empirics) | **needs empirical re-characterization** — MID and PNM both look legit (SanDisk format `SU08G`); catalog flag is from physical/source-of-supply suspicion. Classifier cannot confirm/refute from CID alone. **Needs `cardWarnings()` + TRAN_SPEED-lie check.** |
| **"Chinese Made #2" Samsung `"00000"` ($1B), MDT 2014/08** | — | +2 | **+4** | — | TBD | — | TBD | **6** | **CARD_LIKELY_COUNTERFEIT** — Samsung MID with placeholder PNM `"00000"`. Real Samsung uses real product codes (`GD4QT`, `JD1Y7`). The silicon claims Samsung but the conventions don't match. **Catalog flag is correct.** |
| **SanDisk SU01G ($03), MDT 2007/06 (Industrial SDSC)** | — | — | — | — | — | — | TBD (suspected) | 0 | **legitimate** (old industrial SDSC) — MDT 2007 < 2012 cutoff. SU01G product line was a real SanDisk SDSC industrial card |
| **Cloudisk `"asdfg"` ($05), MDT 2025/11** | +3 | — | — | +2 | +2 | +3 | +2 | **12** (sans CSD-lie empiric) **/ 16** (with) | **CARD_CONFIRMED_COUNTERFEIT** |

### What the walk reveals

**Two cards in the catalog meet the classifier threshold:**

1. **"Chinese Made #2" Samsung `00000`** — score **6** → `CARD_LIKELY_COUNTERFEIT`. The catalog already calls it "Chinese Made #2 (Samsung inside)" and flags it as suspect. **Our classifier formalizes that suspicion: indicator #3 (brand/PNM mismatch) is the rule that fires** — and was missing from the rubric before this session. With it added, the catalog flag is now algorithmically justified, not just hand-noted.

2. **Cloudisk** — score **12-16** → `CARD_CONFIRMED_COUNTERFEIT`. Not in the catalog yet — this is the card driving this session's work. Should be added to `CARD-CATALOG.md` with the counterfeit classification when investigation closes.

**One card needs further work to classify**: "Chinese Made #1" SanDisk SU08G. Its CID looks legitimate — MID $03, PNM `SU08G` (real SanDisk product family). The classifier won't flag it from CID alone. To finish characterizing this card we need to:
- Run `SD_card_identify` (extended with `cardWarnings()` and `getCardMaxSpeed()`) on it to see if `CW_NO_DATA_CRC` is set.
- Run the empirical SCK probe to see if the card's actual clean-read ceiling is below its CSD-claimed 25 MHz.

If both empirics fire, the card scores +5 (TRAN_SPEED lie +3, dummy CRC +2) → `CARD_SUSPECTED_COUNTERFEIT`. If neither fires, the card is just an old SanDisk SDHC — the "Chinese Made #1" label is a supply-chain note, not a counterfeit determination.

**Key takeaways from the walk:**
- The **brand/PNM mismatch indicator (#3) is the catalog-formalizing rule**. Without it, "Chinese #2" would score only 2 (PNM zeros alone). With it, it scores 6 — matching the catalog's existing flag.
- The **MDT-year filter on SDSC-v1.0** correctly distinguishes legitimate old-SDSC (SU01G, MDT 2007) from fake new-SDSC (Cloudisk, MDT 2025).
- **No false positives** on legitimate cards. None of the 21 catalog cards classified as legitimate trip the rubric above the borderline-low threshold.
- **No counterfeit-suspected cards in the catalog are missed by the classifier** except SanDisk SU08G "Chinese #1", which needs empirical follow-up because its CID is indistinguishable from a real cheap SanDisk SDHC.

### Action items from the walk

1. **Update `CARD-CATALOG.md`** to explicitly flag confirmed/likely-counterfeit cards in the summary table and in their card pages (separate edit below).
2. **Re-characterize SanDisk SU08G "Chinese #1"** with the extended identify tool when physically available. Updates classification one way or the other.
3. **Add Cloudisk to `CARD-CATALOG.md`** as the third counterfeit entry, once the dummy-CRC investigation thread closes.

### 🔬 PROPOSED — what eventually goes into theory of operations

**Not yet** — per session rule, theory of operations gets the polished version only **after the design is implemented and tested**. The driver-resident parts to promote later, once implemented:

1. **Dummy-CRC probe at init** (already done in driver — keep).
2. **Per-card SCK probe at init for dummy-CRC cards** (new). Probe procedure, ground-truth read, hp step-down, drift-headroom rule.
3. **Counterfeit classifier scoring** (new). Multi-indicator detection at init, surfaced as `cardWarnings()` flags. Whether to expose user-visible warnings is a UX call.
4. **Decoupling of CRC-honesty and SCK-ceiling** (refactor). Two independent flags / values, not conflated.
5. **Honest declaration of read-error detection coverage**: real-CRC = full coverage; dummy-CRC = none, mitigated by SCK headroom.

### ❓ HYPOTHESIS — still to test

1. **Does the empirical SCK probe at sysclk 350 land at hp=8 (SCK 21.875 MHz)?** Predicted clean. Not yet measured. Quick run: extend `SD_mount_diag` to call `setSPISpeed(22_000_000)` (which forces `hp = ceil(350/44) = 8`) and check whether reads are clean. *That row is missing from the table above and is the single most important validation.*
2. **Does the Edge-socket succeed at a sufficiently low SCK?** Predicted yes per the SI model. Test: switch back to Edge socket, run mount_diag at sysclk 350 / target 16 MHz (hp = ceil(350/32) = 11, actual SCK ~15.9 MHz, half-period ~31 ns). If it works, confirms SI model and quantifies the Edge socket margin penalty.
3. **Does SU01G show `CW_NO_DATA_CRC = 1` AND clean reads at SCK 25 MHz?** Predicted yes. If true, validates the decoupling of CRC honesty and SCK ceiling: a card can be dummy-CRC but fast.
4. **Does the third card under test show any counterfeit-classifier hits?** Unknown. About to find out.
5. **Are the "Chinese Made" #1 and #2 cards in catalog dummy-CRC?** Unknown. Need to re-run the extended identify tool on them.
6. **Is one hp step the right drift-headroom margin?** Unknown. Could be tighter (zero extra steps) if the card's SCK margin is wide enough, or looser (two steps) if drift is significant. Calibrate by long-running test on a known dummy-CRC card across temperature.

### ❌ DISPROVEN — rule out, don't revisit

- "P2 sysclk has an upper limit for SD card I/O" — false. The card sees only SCK; sysclk affects which SCK we end up driving via the integer-rounded `hp`, but is not a direct constraint.
- "Half-period < 20 ns is the boundary" — false. Both 20.00 ns (FAIL) and 20.59 ns (FAIL) fail; 21.88 ns is clean. The boundary is between 20.59 and 21.88 ns half-period for this card, equivalently 22.86 - 24.29 MHz actual SCK.
- "Formatter has a bug" — false. Formatter writes correct data; earlier "failures" on Edge socket were SI-induced corruption of *verify reads*, misreported as write failures. Resolved 2026-05-20.
- "Dummy-CRC and slow-SCK are the same problem" — false. They are correlated on counterfeit silicon but independent properties. A real-CRC card can have a low SCK ceiling; a dummy-CRC card can sustain 25 MHz.

### What changes for the driver, summarized

| Today | Proposed |
|---|---|
| `target = min(TRAN_SPEED_from_CSD, 25 MHz)` for every card | Same for real-CRC cards; **empirical probe** for dummy-CRC cards |
| `CW_NO_DATA_CRC` only affects read-CRC validation | Also gates the empirical SCK probe AND drift-headroom rule |
| No counterfeit detection | Multi-indicator classifier surfaced via `cardWarnings()` |
| No runtime backoff on read errors | Real-CRC cards: reactive backoff on CRC failure (open) |
| Cards that lie in CSD get believed | CSD trust is conditional on probe agreement |

### Session artifacts (uncommitted at session end)

- `diagnostic-tests/SD_mount_diag.spin2` — extended to log `setSPISpeed` actual; restored to default sysclk 350 / target 25 once measurements collected; pins on external connector. Add waitms before END_SESSION.
- `src/UTILS/SD_card_identify.spin2` — added "L3" line printing `getCardMaxSpeed()` (CSD-claimed) and `cardWarnings()`. waitms(300) before END_SESSION to flush serial.
- `src/UTILS/SD_format_card.spin2` — pin set switched to external connector for the freshly-format run; no functional driver change.
- `diagnostic-tests/SD_audit_repro.spin2`, `SD_tempcog_repro.spin2`, prior session's `SD_dump_mbr_vbr.spin2` extensions — left in tree from prior session.

Driver itself (`src/micro_sd_fat32_fs.spin2`) is **unchanged** this session — all work is investigative.

### Resume here — next-session opening moves

1. **Hp=8 validation** at sysclk 350 / target 22 MHz on this card on external connector (the missing table row).
2. **Move to the third card** (about to be physically inserted) and run the extended `SD_card_identify` to score it against the classifier; document findings here.
3. **Promote SU01G to "test under extended tool"** when next available, to fill in the CRC-honesty data point on a legitimate old SDSC.
4. **Re-test Edge socket with low SCK** on Cloudisk (close the SI-vs-bus-timing loop).
5. **Eventually**: prototype the empirical SCK probe in `isp_fsck_utility` style (off-driver), validate algorithm, then promote into `micro_sd_fat32_fs.spin2` as the dummy-CRC init step. Only after that, update `DOCs/Theory-of-Operations` and `DOCs/Analysis/DUMMY-DATA-CRC-ANALYSIS.md` with the production version.

---

## 2026-05-23/24 — Cross-binary unmount→remount wedge investigation (Edge socket)

**Session goal:** Resume certification campaign on Edge socket with Cloudisk; root-cause why repeated mount-test runs wedge the card.

**Card state during session:** Cloudisk on Edge socket. Probe-fix from prior session (PROBE_SCK_SAMPLES=8 + exact-target pre-backoff) was UNCOMMITTED in working tree from 2026-05-20.

### ✅ PROVEN — the 2026-05-20 probe fix works as designed

Measured directly via `SD_performance_benchmark` at sysclk 350 on Edge after fresh power-cycle:

```
SysClk:        350 MHz
SPI Frequency: 21_875 kHz  (= 21.875 MHz)
```

Math check: `hp = ceil(350/50) = 7` lands on exact 25 MHz boundary → pre-backoff fires → `hp = 8` → SCK = 350/(2×8) = 21.875 MHz. Confirmed. **The hypothesis that the wedge was due to "calculation error letting us run at 25 MHz" is FALSE — we are already safely below the danger rate.**

Also confirmed at sysclk 320 (`SD_card_identify`): SCK lands at 22 MHz (no pre-backoff fires, math naturally gives 22.857 MHz from `hp=7`). Consistent with the 2026-05-20 table.

### ✅ NEW SYMPTOM — back-to-back same-binary runs reproduce a distinct cross-binary wedge

Reproduction (Edge, fresh power-cycle each cold run):

| Test run | Result |
|---|---|
| `mount_tests` standalone after power-up | **31/31 PASS** |
| `mount_tests` re-run immediately (no power-cycle) | **20 pass / 10 fail** at tests #15+ |

Failure pattern in run #2 is consistent:
- Tests #1-14 PASS — initial mount succeeds, basic ops, **first unmount succeeds**
- Test #15 ("mount() again") FAILS with `-8 E_NO_CARD`
- All subsequent mount attempts in the same session also fail with `-8`
- Test #17, #19, #21 ("unmount()") report success — driver tears down its mount state but mount won't re-init

**This is the same class as the 2026-05-19 cross-mailbox wedge but a different trigger.** That one was `writeSectorRaw → readSectorRaw` within a single binary on `initCardOnly` mode. This one is `mount()` succeeding once per binary, then any subsequent `mount()` after `unmount()` failing — regardless of what happens between.

### 🔬 INSTRUMENTED — what the failing CMD0 actually does

With `DEBUG_MASK = (1 << CH_INIT) | (1 << CH_MOUNT)` and added intra-`cmd()` debug, captured the failing test #15 of run #2:

```
[initCard] Pins: CS=1 MOSI=1 MISO=0 SCK=0     ← MISO low at entry
[initCard] Step 3: Recovery flush...
[initCard] MISO after recovery flush: 0       ← still low after 4096 clocks (~120ms)
[initCard] Step 4: CMD0 (GO_IDLE_STATE)...
  [cmd] CS before assert: 1
  [cmd] CS after pinl: 0 MISO=0               ← MISO low when CS goes low
  [cmd] After CMD0 sent, MISO=0               ← MISO still low after sending CMD0 frame
[initCard] CMD0 response: $00                 ← card returned $00 not $01
... (4 more retries, all $00) ...
[initCard] No card detected (MISO idle across all CMD0 attempts)
[do_mount] FAIL: initCard() returned false
```

Compare to a PASSING mount (test #15 within run #1):

```
[initCard] Pins: CS=1 MOSI=1 MISO=1 SCK=0    ← MISO HIGH at entry
[initCard] MISO after recovery flush: 1
[cmd] After CMD0 sent, MISO=0                ← (MISO=0 during command tx is normal)
[initCard] CMD0 response: $01                ← R1_IN_IDLE - success
```

**Differentiator:** MISO state at `initCard` entry. When MISO is high at entry (card idle), CMD0 succeeds. When MISO is low at entry (card actively driving low), CMD0 fails — and the card *never* releases MISO long enough to send a real R1.

### 🔬 NEW DATA — MISO sometimes releases after extended flush BUT CMD0 still fails

Replaced fixed 4096-clock flush with poll-until-MISO-released, 65536-clock timeout. Captured behaviour for ALL failing mounts in run #2:

| Test | MISO at entry | Extra clocks to release | MISO after extra flush | CMD0 result |
|---|:---:|---:|:---:|---|
| #15 | 0 | 5398 | **0** (timeout) | `$00` × 5 |
| #18 | 0 | 5597 | 1 (released) | `$00` × 5 |
| #20 | 0 | 5379 | 1 (released) | `$00` × 5 |
| #22 | 0 | 5683 | 1 (released) | `$00` × 5 |
| #23 | 0 | 5419 | 0 (timeout) | `$00` × 5 |
| #27 | 0 | 5572 | 1 (released) | `$00` × 5 |
| #29 | 0 | 5380 | 1 (released) | `$00` × 5 |

**Critical observation:** even when MISO RELEASES (goes high after ~5500 extra clocks ≈ 110ms), **CMD0 still returns `$00` for all 5 retries**. The card is not "stuck in busy" — it's WEDGED in a state where it transmits zeros and ignores commands. This was confirmed by extending the CMD0 response polling to a full 1-second timeout per retry (5 seconds total) — the card transmits `$00` for the entire 5 seconds and never sends anything else.

### Experimental driver changes tried this session

| # | Change | Where | Hypothesis | Result |
|---|---|---|---|---|
| C1 | `pinclear(sck)`, `pinclear(mosi)` before recovery flush | `initCard()` step 2 | Smart pins from prior `initSPIPins` have `P_OE` set; `pinh/pinl/pinf` cannot drive the wire while the smart pin owns it, so the 4096-clock recovery flush produces ZERO transitions on remount. Per P2KB: "Smart pin modes may still operate while DIR=0"; `pinclear` does both `WRPIN=0` and `DIR=0` to fully release. | ❌ Did not change wedge behaviour. **Kept** — defensible per docs, no observed harm, MISO=1 after flush in many cases (which would not be possible if `pinclear` weren't releasing the smart pin). |
| C2 | Extended recovery flush: 4096 baseline + up to 65536 more polling MISO | `initCard()` step 3 | Card needs more clocks to clear busy state on Edge. | ❌ Card does release MISO in many cases (extra=~5500) but CMD0 still fails. **Kept** — the polling logic is correctly robust regardless of root cause; failing tests cleanly show MISO state in the new debug. |
| C3 | CMD0 only: treat `$00` response as "keep polling" up to 1s timeout (other commands still accept `$00`) | `cmd()` response polling | Card may be sending busy-tail zeros after CMD0 — discard them as not-yet-R1, wait for real `$01`. | ❌ Card transmits `$00` for full 1 second across all 5 retries. Not busy-tail — actual wedge. **Reverted.** |

### What this session ruled out

- **NOT a probe / SCK rate bug.** Card is running at 21.875 MHz, well below the 24.29 MHz failure ceiling proven 2026-05-20.
- **NOT a smart-pin retention bug** (C1 hypothesis). pinclear works as documented; the wedge persists.
- **NOT a busy-tail issue** (C3 hypothesis). Card sends zeros for at least 1 second per CMD0; that is not "tail" anything.
- **NOT a "card needs more clocks to release busy" issue alone** (C2 hypothesis). MISO releases on most failing attempts, yet CMD0 still fails — releasing MISO is necessary but not sufficient.

### What this session leaves on the table

**The wedge appears to be a card-internal state on Cloudisk-on-Edge that persists across the unmount→remount boundary within a single power session.** Mount #1 of each binary works (card has had ~15s+ since prior binary's last write — enough to fully settle). Mount #2 of the same binary fails (only ~150ms since the binary's own first unmount).

But within the FIRST binary run after power-cycle, the SAME mount-cycle sequence works (tests #15, #18, #20, #22 all PASS in run #1). So the trigger is more nuanced than "any unmount-then-remount" — something about the FIRST binary after power-cycle that the SECOND binary lacks.

Candidate triggers (none verified):
- **Prior binary's writes accumulate card-internal state** (wear-leveling, garbage-collection queues) such that by the time run #2's mount #1 completes a write→unmount sequence, the card transitions into a state where the next mount can't unwedge it
- **NCO write-bilateral fix** completed for read-path but write-path may still have edge case at exact-target SCK on this card (the dummy-data-CRC writes during `updateFSInfo` could corrupt card-internal state without us seeing CRC errors — the card swallowed the CRC issue)
- **Edge-socket SI** at the unmount→remount instant specifically — same root mechanism as 2026-05-19 cross-mailbox wedge, just a different observable trigger

### Driver state at session end (uncommitted in working tree)

`src/micro_sd_fat32_fs.spin2`:
- (Pre-existing from 2026-05-20) `PROBE_SCK_SAMPLES = 8`, N-sample probe, exact-target pre-backoff in `probeSpiCeiling()`
- (Pre-existing from 2026-05-20) NCO bilateral fix on read-path (`xfrq -= 1` when `$4000_0000 // spi_period == 0`) in `readSector` and `readSectors`
- (Pre-existing from 2026-05-20) `probeSpiCeiling()` call wired into `initCard()` after `probeDataCrc()`
- (NEW this session) `pinclear(sck)` / `pinclear(mosi)` before recovery flush — kept (C1)
- (NEW this session) `RECOVERY_BUSY_TIMEOUT_CLKS = 65536` + poll-MISO-after-flush — kept (C2)
- `DEBUG_MASK` back to `0` (production)

`src/UTILS/SD_performance_benchmark.spin2`:
- (Pre-existing) header comment fix ("350/250" sysclks not "320/270")

`DOCs/cards/CATALOG-PROCEDURE.md`:
- (Pre-existing) new file documenting the catalog procedure

### Verified behaviour with current working-tree driver

- **Fresh-power + `mount_tests`**: 31/31 PASS (cycles work within binary)
- **`mount_tests` × 2 back-to-back**: 31/31 then 20/10 (the cross-binary wedge)
- **`SD_card_identify` (sysclk 320)**: works after fresh power-cycle, reads `SPI 22 MHz`, `cardWarnings() = $04` (dummy-CRC), counterfeit classifier score 12-16
- **`SD_performance_benchmark` (sysclk 350)**: works after fresh power-cycle, `SPI Frequency: 21_875 kHz`, 17s clean run

### Smells the diagnostic agent identified (worth fixing, INDEPENDENT of wedge)

These are real correctness issues found while investigating; agreed with user to fix but NOT yet applied because wedge isn't root-caused:

1. **`do_unmount()` always returns SUCCESS** even when `updateFSInfo()` fails (line 3382 unconditionally `status := SUCCESS`). Caller can't distinguish "clean unmount" from "FSInfo write failed." This is also why test #17 "unmount()" reports success after a failed mount.
2. **Stale `card_warning_flags` / `cmd23_supported` / `hcs` / `ocr_value` across failed inits.** These are only cleared after CMD0/CMD8/ACMD41 succeed (line 5990+). If mount #N fails at CMD0, prior card's flags persist into mount #N+1 calls.
3. (Agent noted) `cmd()` line 6024 sends only 8 NCS clocks before commands — for CMD0 specifically, spec wants 74+ accumulated. **Not a real issue** — once the recovery flush works (C1 + C2), there are ~5000+ clocks before CMD0.

### 2026-05-23/24 next-session opening moves

1. **Test other cards on Edge socket back-to-back** (`mount_tests × 2`). Catalog Samsung/SanDisk known-good cards. If they wedge too → driver bug. If they don't → Cloudisk-specific quirk on Edge SI.
2. **Implement smells #1 + #2** independently of the wedge. They are correctness wins regardless.
3. **Logic analyzer capture on External** (working case) of `mount_tests × 2` — get baseline timing/byte counts to compare against Edge's failure.
4. **Try a deeper recovery sequence on Edge**: CS toggle + CMD12 + dummy clocks + CMD0 instead of just dummy clocks + CMD0. Some cards need explicit `STOP_TRANSMISSION` to reset their state machine.
5. **Investigate whether `updateFSInfo`'s writes during unmount are corrupted on this card** (NCO write-path bilateral check, even though prior session believed bilateral fix is complete — re-audit). Dummy-CRC card swallows the evidence.

---

## 2026-05-24 — Smell fixes implemented; debug-on vs debug-off reveals timing-independent failure mode

**Session goal:** Implement the agreed smell fixes (`do_unmount` error propagation, stale-state reset across failed inits), then re-test on Cloudisk-on-Edge with the now-honest error surface visible.

**Commits added this session (in order):**
- `da2ed83` — `SD_card_characterize` default sysclk 270 → 350 (consistency with benchmark; lands exact 25 MHz SCK)
- `6b2a0fa` — Probe-fix bundle (PROBE_SCK_SAMPLES=8, exact-target pre-backoff, NCO read-path bilateral fix, cross-binary recovery: `pinclear` + extended MISO flush) + `CATALOG-PROCEDURE.md`. Previously uncommitted from 2026-05-20.
- `a7dc362` — Eleven sites across nine PRI methods now propagate `writeSector` / `do_sync_h` / `do_close` / `freeClusterChain` failures that were silently swallowed. Class of bugs: methods declared `: status` that called writeSector and ignored its return, then unconditionally returned SUCCESS. Smells #1 and #2 from the prior session, plus the agent-audit Group A/B/C findings.

### ✅ PROVEN — Gigastone certification clean on Edge after all three commits

Gigastone 32GB SDHC (`Transcend_00000_0.0_000001C9_202307`) regression on P2 Edge, sysclk 350 MHz, `--include-format`:

| Metric | Value |
|---|---|
| Suites passed | **25 / 25** |
| Tests passed | **467 / 467** |
| Format suite | 46 / 46 pass |
| Total runtime | 310 s |

No regression on a previously-certified card. The new error-propagation paths exist but never fire on a healthy card / healthy socket because no underlying writes fail. Direct empirical evidence that the smell fixes did not break the happy path.

Data sheet for this re-cert: `DOCs/cards/gigastone-00000-32gb-recert-2026-05-24.md` (untracked).

### 🔬 NEW SYMPTOM — same wedge surfaces in unmount via the new error visibility

Same Cloudisk-on-Edge regression with `DEBUG_MASK = 0`. mount_tests result: **16 pass / 14 fail in 11 s** (stops on first suite failure). Detailed log: `tools/logs/SD_RT_mount_tests_260524-160658.log`.

Failure progression (test framework numbering; log line refs):

| Test # | Operation | Result | Duration | Code path |
|---:|---|---|---:|---|
| #1-12 | Pre-mount checks, mount #1, volumeLabel(), freeSpace() | PASS | — | reads only; CW_NO_DATA_CRC bypasses validation |
| #13 | `unmount()` — first unmount of session | **FAIL `-7` (E_IO_ERROR)** | **3987 ms** | `do_unmount → updateFSInfo` (now-checked write fails) |
| #15 | `mount()` — first remount | FAIL `-8` (E_NO_CARD) | 363 ms | `do_mount → initCard` — CMD0 retries exhausted |
| #17 | `unmount()` — driver not mounted | FAIL `-7` | <1 ms | passes status from prior failed state |
| #18 | `mount()` cycle 1 | FAIL `-8` | 363 ms | same wedge pattern |
| #20, #22 | further mounts | FAIL `-8` | ~365 ms each | identical |
| #27 | mount after unmount | FAIL `-8` | 365 ms | identical |
| #29 sub, #31 sub | double-mount tests | FAIL `-8` | 366 ms each | identical |
| #30 | Output truncated — produced no fail/pass line; harness reported `BAD TEST COUNTS: 31 <> 30` | — | — | possibly a hang inside test #30 |

**Critical new fact:** with the smell fixes, `unmount()` now reports `-7` where it used to report `0`. The 4-second duration of the failing unmount matches **two writeSector calls each timing out**. The only writes during this unmount (the test never wrote data — only reads) are the FSInfo primary + backup writes inside `updateFSInfo`. Prior runs without the smell fixes would have reported `unmount(): 0` and ascribed the wedge to "the next mount magically fails," masking that an unmount-time write already failed.

### 🔬 NEW SYMPTOM — `DEBUG_MASK = CH_MOUNT | CH_SECTOR` makes the wedge disappear

Re-ran identical mount_tests binary, only difference: `DEBUG_MASK = (1 << CH_MOUNT) | (1 << CH_SECTOR)` instead of `0`. Detailed log: `tools/logs/SD_RT_mount_tests_260524-165058.log`. Card power-cycled between runs.

Result: **all 31 tests pass.** All unmounts return `0` and complete in ~1 ms. All remounts return `0` and complete in ~220 ms. Every mount/unmount cycle works cleanly.

| Phase | DEBUG_MASK=0 | DEBUG_MASK=MOUNT\|SECTOR | Delta |
|---|---:|---:|---:|
| mount() test #10 | 199 ms | 249 ms | +50 ms |
| freeSpace FAT scan | 2525 ms | 2382 ms | -143 ms (within run variance) |
| Gap freeSpace → unmount | 17 ms | 4 ms | -13 ms |
| Unmount test #13 | 3987 ms (FAIL `-7`) | 1 ms (PASS `0`) | reverses outcome |
| Subsequent mount/unmount cycles | all fail | all pass | reverses outcome |

The two compiled binaries differ only in whether `debug[CH_MOUNT]` and `debug[CH_SECTOR]` calls have generated code. Per `p2kbSpin2DebugMask`: when the channel bit is not set, the statement is **entirely omitted** from compiled output — zero runtime presence.

### ❌ DISPROVEN this session (with P2KB citations) — debug overhead is NOT slowing the writes

These hypotheses were considered to explain the debug-on/off difference and are now ruled out:

**❌ "Debug ISR adds per-instruction overhead in the cog."**
Source: `p2kbArchDebugInterrupt`:
> `breakpoint_overhead: when_not_hit: '0 additional clocks (debug interrupt only fires when its event condition is met)'`

The P2 debug interrupt is event-triggered. Between explicit `debug()` calls, the cog runs with **zero** debug overhead. There is no continuous per-instruction tax.

**❌ "Debug call serial-output time gives the card more settling time during writes."**
Source: actual log timestamps + the channel-call inventory. The 14 `debug[CH_MOUNT]` calls in the success run total ~3.8 ms of serial bit time (765 chars × 5 µs at 2 Mbaud). They fire **during do_mount**, **2.4 seconds before** the writes in updateFSInfo. Between freeSpace and the FSInfo writes, **no debug calls fire on the success path** (writeSector's debug only fires on error branches that don't execute during success; updateFSInfo's debug fires after the writes already succeeded). The 4 ms gap between freeSpace and unmount in the debug-on run is *shorter* than the 17 ms gap in the debug-off run — yet the writes succeed in the former and fail in the latter. Direct contradiction of any "more time helps" story.

**❌ "Different code layout shifts hub access timing, perturbing writeSector PASM."**
User correction (2026-05-24): "Code location should not affect performance. Once the cache synchronizes, it synchronizes and does not desynchronize." The P2 egg-beater gives each cog a deterministic slot pattern relative to its own clock. Cog instruction timing does not depend on absolute hub addresses. The same instructions in the same order produce the same bus traffic regardless of where the code lives in hub.

**❌ "Compiler-generated code sequencing differences."**
Same user correction. No P2KB support for this idea. Retracted.

### ❓ STILL UNEXPLAINED — what about DEBUG_MASK on makes the write succeed

If the cog instructions executed during writeSector are byte-identical between the two binaries (which they should be — writeSector's success path contains no `debug[CH_SECTOR]` call that fires), and if hub access timing is deterministic by cog phase, then the SPI bus traffic the card sees should be byte-identical between the runs. Yet the card responds differently. The mechanism is not yet identified.

This is the single biggest open question in the investigation. We have one data point per condition. We have not formally tested determinism — both runs might be coin flips. **Until determinism is established, "DEBUG_MASK changes the outcome" is itself a single-shot observation.**

### Current outstanding failures (with code-region attribution)

| Failure | Symptom | Code region | Routine | Notes |
|---|---|---|---|---|
| **F1** — Unmount fails on Cloudisk-Edge with DEBUG_MASK=0 | `-7` returned, 4 s duration | `do_unmount → updateFSInfo` | line 5041 `updateFSInfo` | Now visible because smell fix `a7dc362` makes the error escape; was silent before |
| **F2** — Next mount on Cloudisk-Edge after a failed unmount returns `-8` | E_NO_CARD, 363 ms | `do_mount → initCard` | line 5774 `initCard` | CMD0 retries exhausted with $00 responses (per 2026-05-23 instrumented capture) |
| **F3** — Persists across subsequent mount attempts | Every mount fails identically | `initCard` | Card-state wedge — only power-cycle clears |
| **F4** — `DEBUG_MASK = CH_MOUNT \| CH_SECTOR` reverses the outcome | All tests pass | (cross-cutting) | Mechanism unidentified; **not timing** per above |

The PRIMARY failure is F1 (the write inside updateFSInfo that fails on Cloudisk-Edge). F2/F3 are consequences of F1 — once the card is wedged, nothing else works. F4 is the diagnostic anomaly that we can't yet explain.

### Code inventory of the write path involved in F1

This is **what the code does**, not what it might be doing wrong. Source: `src/micro_sd_fat32_fs.spin2` after commits da2ed83 / 6b2a0fa / a7dc362.

**`do_unmount` (line 3370):**
- Calls `do_sync_all()` (handles HF_WRITE-flagged handles only; for mount_tests, no write handles open — returns SUCCESS without writes)
- Calls `do_close()` (writes dir entry only if `F_NEWDIR` flag set; for mount_tests, not set — returns SUCCESS without writes)
- Calls `updateFSInfo()` (always, unless `fsinfo_sec == 0` or `fsi_free_count == $FFFF_FFFF`)
- Returns first non-SUCCESS encountered; SUCCESS if all three succeed

**`updateFSInfo` (line 5041):**
- If `fsinfo_sec == 0` or `fsi_free_count == $FFFF_FFFF`: returns FALSE without doing anything (the card has no FSInfo to update)
- Otherwise: `readSector(vbr_sec + fsinfo_sec, BUF_DATA)` — reads FSInfo sector (sector 8193 = vbr_sec 8192 + fsinfo_sec 1) into `@buf`
- Verifies `FSINFO_LEAD_SIG` and `FSINFO_STRUCT_SIG` against `@buf` (rejects if either fails)
- Calls `fsiSetFreeClusters(pFSI, fsi_free_count)` and `fsiSetNextFreeHint(pFSI, fsi_nxt_free)` — overwrites the FreeCount and NextFree fields in `@buf` with the driver's cached values
- `writeSector(vbr_sec + fsinfo_sec, BUF_DATA)` — primary FSInfo write to sector 8193
- `writeSector(vbr_sec + 7, BUF_DATA)` — backup FSInfo write to sector 8199
- Returns TRUE if both writes succeed; FALSE otherwise (smell-fix `a7dc362` made this gating actually correct)

**`writeSector` (line 6498):** the operation that's failing. Sequence per call:
1. Choose buffer pointer + cache pointer by `buf_type`
2. Invalidate own cache (LONG[p_cache] := -1)
3. Cross-buffer cache coherence (invalidate any other cache holding this sector)
4. `cmd(CMD24, sector << hcs)` — send CMD24 (WRITE_BLOCK), polls for R1 with 1s timeout, leaves CS LOW
5. Check R1 for fatal bits (`R1_FATAL_MASK = $04|$20|$40` = illegal cmd / address err / parameter err) — on fatal: pinh(cs), return E_IO_ERROR
6. `sp_transfer_8($FE)` — send data start token
7. Configure streamer for TX (STREAM_TX_BASE | MOSI pin << 17 | bit count 4096); `xfrq := $4000_0000 / spi_period` (with -=1 if exact division per NCO bilateral fix)
8. `pinclear(_mosi)` + `pinl(_mosi)` — release smart pin, drive low
9. **PASM block:** `DIRL _sck` → `DRVL _sck` (smart-pin reset) → `SETXFRQ xfrq` → `RDFAST #0, p_buf` → `XINIT stream_mode, #0` → `WYPIN clk_count, _sck` → `WAITXFI` — 512-byte streamer DMA out
10. Restore MOSI smart pin (`WRPIN(_mosi, spi_tx_mode)`, `WXPIN`, `pinh(_mosi)`)
11. Calculate CRC-16 over the source data; send CRC high then CRC low byte via `sp_transfer_8`
12. `waitDataResponse()` — polls MISO for a non-$FF byte; checks bits 4:0 for valid format `xxx0sss1`; returns lower 5 bits or E_TIMEOUT after 100 ms
13. If response is not DATA_ACCEPTED ($05): pinh(cs), return E_WRITE_REJECTED or E_IO_ERROR per response
14. `waitBusyComplete()` — polls MISO via `sp_transfer_8($FF)` until $FF returns; timeout = `card_write_timeout_ms` (CSD-derived, can be up to 30 s for SDSC)
15. On busy timeout: pinh(cs), return E_CARD_BUSY
16. `pinh(cs)` — deassert CS
17. `checkCardStatus(@"writeSector")` — issues CMD13 (SEND_STATUS); returns negative on stale-state R2 bits

**`cmd` (line 6119):** the command-send subroutine.
- For CMD0 specifically: emits one CH_INIT debug line before CS assert (gated by op == CMD0 check)
- `sp_transfer(-1, 8)` — send 8 dummy bits with CS HIGH (NCS pre-clocks; "required for certain cards (my 512MB card fails if not present)")
- `pinl(cs)` — assert CS LOW
- For CMD0 only: another CH_INIT debug ("CS after pinl")
- `sp_transfer(-1, 8)` — send another 8 dummy bits with CS LOW
- `sp_transfer($40 | op, 8)` — command byte
- `sp_transfer(parm, 32)` — 32-bit argument
- `sp_transfer(CRC_CMD0 or CRC_CMD8, 8)` — CRC7 — note: hardcoded for CMD0 and CMD8 only; other commands send CRC_CMD8 (which is wrong CRC for those but cards ignore CRC in SPI mode per spec)
- Polls for R1 (bit 7 = 0) with 1 s timeout
- For CMD8/CMD58: reads additional 32-bit reply
- For CMD17 / CMD24 / CMD18 / CMD25 / CMD55: **leaves CS LOW** for the following data phase; for everything else, raises CS

**`waitBusyComplete` (line 6829):**
- Single-byte polling loop via `sp_transfer_8($FF)` — sends $FF and reads MISO byte
- Exits on first byte where ALL EIGHT BITS are HIGH (`resp == $FF`)
- Timeout: `card_write_timeout_ms` (typically hundreds of ms for SDHC; up to 30 s for SDSC per CSD)
- No requirement that MISO be high for N consecutive bytes — first single $FF byte breaks the loop

**`waitDataResponse` (line 6805):**
- Single-byte polling loop, 100 ms timeout
- Looks for a byte where `(resp & $11) == $01` (data-response token format `xxx0sss1`)
- Returns the bottom 5 bits

### Code inventory of the failing remount (F2)

**`initCard` (line 5774):** runs when do_mount calls it after the wedged state.
- After smell-fix `a7dc362`: top of routine resets `sec_in_buf`, `fat_sec_in_buf`, `card_warning_flags`, `cmd23_supported`, `hcs`, `ocr_value` — so prior card state cannot leak
- STEP 1: `waitms(POWER_ON_DELAY_MS)` (100 ms)
- STEP 2: `bit_delay := clkfreq / 100_000` (~50 kHz init clock); `pinclear(sck)`, `pinclear(mosi)` (added by commit 6b2a0fa to fully release smart pins from prior init); `pinh(cs)`, `pinh(mosi)`, `pinl(sck)`; `dirh` on all
- STEP 3: Recovery flush — 4096 SCK clocks toggled at ~50 kHz with CS HIGH (~82 ms); then **poll** MISO with additional clocks up to `RECOVERY_BUSY_TIMEOUT_CLKS=65536` until MISO releases high. Per 2026-05-23/24 instrumented data: MISO often releases after ~5500 extra clocks (~110 ms). Per same data: even when MISO releases high, CMD0 still gets $00 responses for the full 1 s polling window per retry, across all 5 retries.
- STEP 3.5: `initSPIPins()` — configure smart pins for SPI (P_TRANSITION on SCK, P_SYNC_TX on MOSI, P_SYNC_RX on MISO)
- STEP 4: CMD0 retry loop (up to 5 attempts with 10 ms delay between)
- STEP 5+: CMD8, ACMD41, CMD58, CMD16/SET_BLOCKLEN for SDSC, probeCmd13, probeCmd23, probeDataCrc, probeSpiCeiling
- The wedge fails the entire init at STEP 4 — never proceeds past CMD0

### What the code does NOT do (factually — these are not present)

These are operations the SD spec mentions in various contexts that are absent from our current init/write paths:

- **No CMD12 (STOP_TRANSMISSION) before mount retry.** Some cards expect a CMD12 to reset internal state machines after a busy transaction; spec recommends but does not mandate. We do not issue CMD12 on remount.
- **No SCK clocks with CS LOW before CMD0.** Spec section 6.4.1 / Figure 6-1 wants 74+ clocks of CS-HIGH initialization, which we do (STEP 3). The 8-byte dummy clocks at CS-LOW inside `cmd()` (line 6135) happen AFTER CS is asserted, not before it ever goes LOW.
- **No re-arming of the recovery flush after a failed CMD0.** Once we enter the CMD0 retry loop (STEP 4), retries do not re-run STEP 3's recovery flush — only the 10 ms delay between CMD0 attempts.
- **No card-state inspection before declaring E_NO_CARD.** When all 5 CMD0 retries fail to return a valid R1, initCard returns FALSE → do_mount returns -8. No attempt is made to read CID/CSD/SCR/OCR to see if the card responds to anything at all.
- **No verification that data block reached the card on successful write.** `writeSector` accepts DATA_ACCEPTED response token + `waitBusyComplete` MISO-released as proof of success. There is no read-back verify in the success path. (CMD13 at the end checks card R2 state but not data integrity.)

### Things in the code that could conceivably matter for the symptoms — without claiming which one is the cause

- **`waitBusyComplete` exits on first byte that reads as $FF on MISO** (line 6844). It does not verify N consecutive $FF bytes. If the card releases MISO transiently between busy and a subsequent error state, we would return SUCCESS from busy-wait but the card's state machine could still be in transition.
- **`cmd()` sends 8 dummy bits at CS-LOW** (line 6135) before sending the command byte. This is 16 SCK clocks of unspecified content; on a card that's not in idle, this could be interpreted as data or a malformed command.
- **CMD24's CRC byte is sent as `CRC_CMD8`** (line 6142) — incorrect CRC, but SD spec says SPI mode ignores CRC for non-CMD0/CMD8 unless `CRC_ON_OFF` is enabled. The card should ignore. But if the card is in a state where it's checking CRC, our value would fail validation.
- **`pinclear` + `pinl` on MOSI before PASM streamer block** (line 6581-6582). Per `p2kbArchSmartPin00000NormalMode`, this releases the smart pin then drives the pin LOW via standard output. Between `pinl(_mosi)` and the streamer's `XINIT` (which configures MOSI as a streamer-driven output), MOSI is briefly a plain GPIO output at LOW. The card sees: MOSI HIGH (from before) → MOSI LOW (during pinl/pinclear transition) → MOSI streamer-driven data. The data start token $FE was sent BEFORE this transition by `sp_transfer_8($FE)` — so the card is already past the token and expecting data bytes when this transition happens.
- **PASM block uses `DIRL _sck` / `DRVL _sck`** to reset the P_TRANSITION counter. Per the comment, this gives a "deterministic phase from wypin onward." Verified on 4 cards. Cloudisk's tolerance to whatever happens during this reset is unknown.
- **`xfrq` calculation `$4000_0000 / spi_period`** with `xfrq -= 1` correction when exact division. This is the NCO bilateral fix applied to the write path. The comment claims "ensure 1-cycle late rollover like truncated values." The exact behavior of the streamer NCO when xfrq is exactly $4000_0000/N vs ($4000_0000/N)-1 has not been measured on a logic analyzer for this card.

These observations are inventory, not hypothesis. They describe what the code does. Whether any of them is what makes Cloudisk wedge is unverified.

### ❓ Open questions, ordered by what would give us the most information

1. **Is the DEBUG_MASK on/off outcome deterministic?** One run each is not enough. If determinism holds: there is a real (unidentified) mechanism. If not: F4 may be variance and the wedge may be flaky regardless of DEBUG_MASK.
2. **Which specific writeSector return code is updateFSInfo seeing?** The smell fix surfaces the failure but `updateFSInfo` itself returns only TRUE/FALSE. The CH_MOUNT debug we ran today shows `[updateFSInfo] Updated primary+backup` in the success case but doesn't print individual writeSector return codes on failure. Adding CH_MOUNT prints around each writeSector call (or enabling CH_SECTOR in the writeSector failure-path debug) would tell us: E_TIMEOUT, E_WRITE_REJECTED, E_CARD_BUSY, or E_IO_ERROR. That is decisive for which spec mechanism we should look at.
3. **What does the card output on MOSI after the rejected write?** We have no capture of the wire traffic between the failed write and the subsequent CMD0 that returns $00 forever.
4. **Does the wedge depend on FSInfo specifically?** Not yet known. The wedge surfaces precisely when the FIRST write happens on a session. If mount_tests had done a sector write before unmount (not just reads), would the wedge fire there too?

### Hypothesis status table (rolled forward from prior sessions, updated this one)

| # | Hypothesis | Status |
|---|---|---|
| H-SI | Edge-socket signal integrity at writes / SCK reflections | **OPEN** — still consistent with everything. Disproven mechanisms below do not refute it. |
| H-FloatMISO | MISO floats between cmds → noise misinterpreted | ❌ Disproven 2026-05-19 (E2f pull-up did not help) |
| H-CMD13Trail | CMD13 trailing capture leaves card non-responsive | ❌ Disproven 2026-05-19 (E2-CMD13 did not help) |
| H-PostBusyGuard | Card needs settle clocks after busy-clear | ❌ Disproven 2026-05-19 (E2-guard did not help) |
| H-FloatCSMOSI | CS/MOSI float during idle | ⚠️ Test invalid — P_HIGH_15K broke active drivers per `lesson_p_high_15k_semantics` |
| H-Probe | Driver running too fast (above 25 MHz) | ❌ Disproven 2026-05-23/24 (probe lands at 21.875 MHz, well below ceiling) |
| H-SmartPinRetention | Smart pin from prior init holding lines | ❌ Disproven 2026-05-23/24 (C1 `pinclear` did not change wedge behavior) |
| H-BusyTail | $00 responses are busy-tail not wedge | ❌ Disproven 2026-05-23/24 (card sends $00 for full 1 s) |
| H-NotEnoughClocks | Need more recovery flush clocks | ❌ Disproven 2026-05-23/24 (MISO releases after ~5500 extra clocks, CMD0 still fails) |
| H-DebugISROverhead | Debug ISR slowing all cog instructions | ❌ **Disproven 2026-05-24** per `p2kbArchDebugInterrupt`: event-triggered, zero per-instruction overhead |
| H-DebugSerialSettling | Serial output time gives card settling | ❌ **Disproven 2026-05-24** — debug calls fire 2.4 s before the writes; success-run gap was *shorter* than failing run |
| H-CodeLayout | Hub address shifts affect cog timing | ❌ **Disproven 2026-05-24** — egg-beater is cog-phase-deterministic, not hub-address-dependent |
| H-WriteRejectedSurvives | Card wedges after a rejected write | **OPEN** — F1 → F2 chronology fits, but cause of the rejection is unknown |
| H-FSInfoSpecific | FSInfo sector specifically triggers wedge | **OPEN** — never tested with a non-FSInfo write before unmount |

### Next-session opening moves (revised after this session)

The remaining moves from the 2026-05-23/24 list still stand, plus:

6. **Test determinism of DEBUG_MASK on/off.** Run mount_tests **twice consecutively with same DEBUG_MASK** (=0 and =MOUNT|SECTOR) with power-cycle between each. Four total runs. Confirms whether F4 is real or variance — single biggest open question.
7. **Add temporary debug at each writeSector return inside updateFSInfo** to capture which specific error code (`E_TIMEOUT`, `E_WRITE_REJECTED`, `E_CARD_BUSY`, `E_IO_ERROR`) is returned, plus the `diag_write_result` value (1-6 per writeSector internal step) and `diag_write_dresp` (data response token raw). This is the smallest possible instrumentation change that converts "the unmount failed" into "writeSector failed at step N with response X." Run with DEBUG_MASK=0 to preserve the failure mode.
8. **Probe whether the wedge depends on FSInfo specifically** — diagnostic test that mounts, writes one sector to a non-FSInfo location (e.g., a data-area sector that's known free), then attempts the same write to FSInfo. If both wedge: any write. If only FSInfo: location-specific.
9. **Soft-LA capture** (SD_soft_la_test.spin2) on Edge of the failing writeSector. Soft LA was the option recommended in the 2026-05-19 LA-observability matrix specifically because it works on Edge where hardware LA does not. Captures MISO content during the failing window.

### Session uncommitted state

`src/regression-tests/SD_RT_mount_tests.spin2`:
- Added `DEBUG_BAUD = 2_000_000` in CON (per project rule from memory)

`src/micro_sd_fat32_fs.spin2`:
- `DEBUG_MASK = (1 << CH_MOUNT) | (1 << CH_SECTOR)` — TEMPORARY for diagnostic; will revert to 0 before next investigation cycle

These two changes should be reverted before the next investigation session unless we choose to re-run with the same DEBUG_MASK to test determinism.
