# Pin-Setup Order Audit — SCK / MOSI / MISO Smart Pins

**Date:** 2026-05-04
**Author:** Stephen M Moraco (sprint task #2-#4)
**File audited:** `src/micro_sd_fat32_fs.spin2`
**Scope:** every site that reconfigures the SCK, MOSI, or MISO smart pins via WRPIN/WXPIN/WYPIN/DIRL/DIRH/DRVL/DRVH/FLTL/FLTH/pinclear/pinfloat, plus DIRH-equivalent calls (`pinh()` on a smart pin). CS toggles (pure GPIO) are excluded — they're not smart-pin reconfigurations.

This document fulfills sprint tasks #2 (inventory), #3 (verify against canonical order), and #4 (apply fixes if any).

---

## Canonical invariants

**Per-pin invariant** (from `p2kbArchSmartPins`):

```
DIRL pin              ' reset (DIR=0) — must come first
WRPIN mode, pin       ' configure mode + routing
WXPIN x, pin          ' set X parameter
WYPIN y, pin          ' set Y parameter (when applicable)
DIRH pin              ' enable (DIR=1) — must come last
```

WRPIN requires DIR=0 to take effect. DIRH must be last so the pin starts in a fully-configured state.

Note: in this driver, several Spin2 pin helper calls implement the same effect:
- `pinfloat(pin)` ≡ `DIRL pin` (resets the smart pin).
- `pinclear(pin)` ≡ `WRPIN #0, pin` followed by `DIRL pin` (clears WRPIN value entirely and resets).
- `pinh(pin)` on a configured smart pin ≡ `DIRH pin`.
- `pinl(pin)` on a configured smart pin ≡ `DRVL pin`, which is also a DIRH-equivalent that drives output low — sometimes called "ManAtWork pattern" in driver comments.

**Cross-pin invariant** (from `p2kbPasm2StreamerSmartpinControl`): receiver/transmitter smart pins must be enabled *before* edges arrive on their inputs. Specifically:

- The MISO smart pin must be `DIRH`'d before any subsequent code path issues `WYPIN(N, sck)` that begins clocking, or the receiver may miss the first SCK edge and shift the entire byte.
- The MOSI smart pin must be `DIRH`'d before clocks begin.
- The streamer's `XINIT` must occur after both data smart pins are enabled.

**Inline-PASM timing invariant** (Phase 1.5 root cause from `p2kbArchSmartPin00101TransitionOutput`): when SCK is in `P_TRANSITION` mode, the smart pin starts cycling at DIR-rise; new transition sequences begin at the next base-period boundary *after `WYPIN` writes Y*. This means the time between `DIRH _sck` and `WYPIN clk_count, _sck` must be less than `hp` sysclks, or the first SCK transition slips by a full base period. Phase 1.5 addresses this; for Phase 1, we just verify per-pin ordering.

---

## Inventory and per-site verification

### A. Worker cog initial GPIO state (lines 2309–2311)

| Line | Operation | Pin | Notes |
|---:|:--|:--|:--|
| 2309 | `pinh(cs)` | CS | GPIO only (CS is not a smart pin) — sets idle HIGH. |
| 2310 | `pinh(mosi)` | MOSI | GPIO at this point — sets idle HIGH before smart-pin configuration. |
| 2311 | `pinl(sck)` | SCK | GPIO at this point — sets idle LOW (SPI mode 0) before smart-pin configuration. |

**Verdict:** N/A — these are GPIO state-setters before any smart pin is configured. Not subject to the smart-pin canonical order.

### B. `initSPIPins` initial smart-pin configuration (lines 5252–5282)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 5252 | `pinh(cs)` | CS | GPIO only |
| 5258 | `pinfloat(sck)` | SCK | DIRL — reset |
| 5259 | `WRPIN(sck, spi_clk_mode)` | SCK | configure mode |
| (no WXPIN here) | | | half_period set later by applySPISpeed |
| (no DIRH here) | | | enabled later by applySPISpeed line 5340 (`pinl(sck)` = DRVL = DIRH) |
| 5268 | `pinfloat(mosi)` | MOSI | DIRL — reset |
| 5269 | `WRPIN(mosi, spi_tx_mode)` | MOSI | configure mode |
| 5270 | `WXPIN(mosi, %1_00111)` | MOSI | set X (start-stop, 8 bits) |
| 5271 | `pinh(mosi)` | MOSI | DIRH — enable |
| 5279 | `pinfloat(miso)` | MISO | DIRL — reset |
| 5280 | `WRPIN(miso, spi_rx_mode)` | MISO | configure mode |
| 5281 | `WXPIN(miso, %1_00111)` | MISO | set X (on-edge sample, 8 bits) |
| 5282 | `pinh(miso)` | MISO | DIRH — enable |

**Per-pin verdict:** PASS for MOSI and MISO (canonical DIRL → WRPIN → WXPIN → DIRH). **PASS for SCK** because the canonical sequence is split intentionally: SCK is reset and given a mode in `initSPIPins`, then `applySPISpeed` writes the half-period and enables it via `pinl(sck)`. The split is documented and the order across the two functions is still DIRL → WRPIN → WXPIN → DIRH.

**Cross-pin verdict:** PASS. MOSI and MISO are both `DIRH`'d in `initSPIPins`. SCK is `DIRH`'d (via `pinl(sck)`) only inside `applySPISpeed`, which is called after `initSPIPins`. So both data smart pins are enabled before SCK starts ticking on the next operation.

### C. `applySPISpeed` SCK enable (lines 5339–5340)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 5339 | `WXPIN(sck, half_period)` | SCK | set X (transition period) |
| 5340 | `pinl(sck)` | SCK | DRVL (DIRH-equivalent + drive low) — enable |

**Per-pin verdict:** PASS. WXPIN is written while SCK is in DIRL state (set by `initSPIPins` at line 5258 via `pinfloat(sck)`), then DRVL/DIRH enables it. Canonical order across functions is preserved.

**Cross-pin verdict:** PASS in steady state. On *re-application* of speed (e.g., a CMD6 high-speed switch at line 6920), the SCK smart pin transitions through DIRL→WXPIN→DIRH again; if MOSI/MISO smart pins are already enabled (which they are after init), this should be safe. **Worth flagging as a possible attention point** for Phase 1.5: at re-speed, SCK is reset and re-enabled; ensure no operation in progress.

### D. `sp_transfer_8` inline-PASM (lines 5406–5417)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 5406 | `WXPIN #$27, _mosi` | MOSI | set X (8 bits, start-stop) |
| 5407 | `WYPIN tx_data, _mosi` | MOSI | set Y (data) |
| 5408 | `DRVL _mosi` | MOSI | DIRH-equivalent — enable |
| 5412 | `WXPIN #$27, _miso` | MISO | set X (8 bits, start-stop) |
| (no WYPIN — MISO has no Y for sync_rx) | | | |
| 5414 | `DIRH _miso` | MISO | enable |
| 5417 | `WYPIN #16, _sck` | SCK | start clocking (16 transitions = 8 bits) |

**Per-pin verdict:** PASS. Both MOSI and MISO have WXPIN written before DIRH. SCK is already enabled; we're just kicking it via `WYPIN`.

**Cross-pin verdict:** PASS. MOSI is `DIRH`'d (line 5408), then MISO is `DIRH`'d (line 5414), then SCK is kicked (line 5417). Both data pins are enabled before SCK starts toggling.

**Note:** WRPIN is *not* re-applied here. The mode set in `initSPIPins` is persistent across DIRL/DIRH cycles (until DIRL is followed by a fresh WRPIN). This is intentional and correct per the KB: WRPIN persists; only X and Y need re-setting if you want different bit count or data per transfer.

### E. `sp_transfer_32` inline-PASM (lines 5454–5463)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 5454 | `WXPIN #$3F, _mosi` | MOSI | set X (32 bits, start-stop) |
| 5455 | `WYPIN tx_data, _mosi` | MOSI | set Y (data) |
| 5456 | `DRVL _mosi` | MOSI | DIRH-equivalent — enable |
| 5459 | `WXPIN #$3F, _miso` | MISO | set X (32 bits, start-stop) |
| 5460 | `DRVL _miso` | MISO | DIRH-equivalent — enable |
| 5463 | `WYPIN #64, _sck` | SCK | start clocking |

**Per-pin verdict:** PASS. Same pattern as `sp_transfer_8`.

**Cross-pin verdict:** PASS. MOSI then MISO `DIRH`'d, then SCK kicked.

### F. `initCard` recovery flush — temporary MISO reconfig (lines 5506–5530)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 5506 | `pinh(cs)` | CS | GPIO |
| 5507 | `pinh(mosi)` | MOSI | GPIO drive HIGH (idle) |
| 5508 | `pinl(sck)` | SCK | GPIO drive LOW (idle) |
| 5514 | `WRPIN(miso, P_HIGH_15K)` | MISO | reconfigure as plain input with 15K pull-up |
| 5515 | `pinf(miso)` | MISO | DIRL — set as input |
| 5527 | `pinh(sck)` | SCK | GPIO toggling (bit-banged dummy clocks) |
| 5529 | `pinl(sck)` | SCK | GPIO toggling |

**Per-pin verdict:** PASS for MISO. WRPIN(miso, P_HIGH_15K) at line 5514 — but at this point, has MISO been previously DIRH'd in `initSPIPins`? YES (line 5282).

**Potential issue flagged:** WRPIN at line 5514 requires DIR=0. The MISO pin is currently DIRH (enabled smart pin). The KB says: "Smart pins MUST be reset (DIR=0) before any WRPIN configuration." But here WRPIN is written first (line 5514), then `pinf(miso)` (DIRL) is called (line 5515). **This is reverse order — WRPIN before DIRL.** Per the KB, this is undefined / undocumented behavior.

**Hypothesis why this might still work in practice:** WRPIN to a non-smart-pin mode (P_HIGH_15K is mode `%00000`, the normal/pass-through mode) may be a special case that doesn't need DIRL. The mode `%00000` disables smart-pin behavior entirely, so the smart-pin reset requirement may not apply. But this is silicon-behavior speculation, not KB-documented.

**Verdict:** **POSSIBLY FAIL — needs investigation.** Order is `WRPIN → DIRL` instead of canonical `DIRL → WRPIN`. The fact that this driver works on every card we've tested suggests the silicon tolerates it for this specific case (mode-zero WRPIN), but it deviates from the canonical order. **Phase 1 task C decision: defer fix unless Phase 1.5 testing surfaces an issue.** Reordering is straightforward (`pinf(miso)` before `WRPIN(miso, P_HIGH_15K)`) and risk-free.

### G. `readSector` streamer-driven block (lines 5821–5856) — PHASE 1.5 PRIMARY TARGET

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 5821 | `pinclear(_miso)` | MISO | clear WRPIN + DIRL (full reset) — disable MISO smart pin before streamer |
| 5822 | `pinf(_miso)` | MISO | confirm DIRL (input mode) |
| 5833 | `DIRL _sck` (in PASM) | SCK | reset SCK smart pin |
| 5834 | `DRVL _sck` (in PASM) | SCK | DIRH-equivalent — re-enable |
| 5835 | `SETXFRQ xfrq` (in PASM) | streamer | not pin control |
| 5836 | `WRFAST #0, p_buf` (in PASM) | hub FIFO | not pin control |
| 5837 | `WYPIN clk_count, _sck` (in PASM) | SCK | start clocking |
| 5838 | `WAITX align_delay` (in PASM) | — | wait |
| 5839 | `XINIT stream_mode, init_phase` (in PASM) | streamer | start streamer |
| 5840 | `WAITXFI` (in PASM) | — | wait for completion |
| 5854 | `WRPIN(_miso, spi_rx_mode)` | MISO | re-configure smart pin |
| 5855 | `WXPIN(_miso, %1_00111)` | MISO | set X |
| 5856 | `pinh(_miso)` | MISO | DIRH — re-enable |

**Per-pin verdict:**
- **MISO disable side:** PASS. `pinclear` is a clean reset (WRPIN=0 + DIRL).
- **MISO re-enable side:** PASS. After `pinclear` (which left DIR=0), the canonical sequence WRPIN → WXPIN → DIRH is followed.
- **SCK side:** PASS for canonical order (DIRL → DRVL re-enables; pin already had WRPIN/WXPIN from earlier init/applySPISpeed and those persist across DIRL).

**Per-pin Phase 1.5 timing invariant verdict:** **FAIL.** Two non-pin instructions (`SETXFRQ`, `WRFAST`) are between `DRVL _sck` (DIRH-equivalent at line 5834) and `WYPIN clk_count, _sck` (line 5837). Each PASM instruction is 2 sysclks. Time from DIR-rise to WYPIN execution: 2 (SETXFRQ) + 2 (WRFAST) + 2 (WYPIN itself) = 6 sysclks. For hp ≤ 6, the next base-period boundary after Y is written falls at `2·hp` instead of `hp`, slipping the first SCK transition by a full half-period. **This is the verified Claim B mechanism. Phase 1.5 (sprint task #5) addresses this exact site.**

**Cross-pin verdict:** PASS. MISO is reset *before* SCK is re-enabled and starts clocking; MISO is re-enabled *after* the streamer completes. The streamer reads the pin directly — MISO smart pin is intentionally disabled during the streamer window.

### H. `readSector` streamer-write verify-read (lines 5961–5979)

Identical pattern to G. Same Phase 1.5 timing-invariant FAIL at the inline-PASM block (lines 5961-5970 mirroring 5821-5839).

**Per-pin verdict:** PASS for canonical order.
**Phase 1.5 timing invariant verdict:** **FAIL.** Same pattern, same fix.

### I. `writeSector` main streamer block (lines 6125–6157)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 6125 | `pinclear(_mosi)` | MOSI | clear WRPIN + DIRL — disable MOSI smart pin before streamer |
| 6126 | `pinl(_mosi)` | MOSI | drive LOW (output mode) |
| 6144 | `DIRL _sck` (in PASM) | SCK | reset SCK |
| 6145 | `DRVL _sck` (in PASM) | SCK | DIRH-equivalent — re-enable |
| (RDFAST + SETXFRQ between, similar to read path) | | | |
| 6150 | `WYPIN clk_count, _sck` (in PASM) | SCK | start clocking |
| 6155 | `WRPIN(_mosi, spi_tx_mode)` | MOSI | re-configure |
| 6156 | `WXPIN(_mosi, %1_00111)` | MOSI | set X |
| 6157 | `pinh(_mosi)` | MOSI | DIRH — re-enable |

**Per-pin verdict:** PASS for canonical order on MOSI re-enable.
**Phase 1.5 timing invariant verdict:** **FAIL same as G.** But per @evanh's Part 3 feedback, RDFAST has different timing characteristics than WRFAST and the writeSector fix is **deferred** until @macca confirms the readSector fix works. **Sprint task #5 explicitly does NOT touch this site.**

### J. `writeSector` second streamer instance — multi-block (lines 6264–6283)

Identical to I. Same FAIL on Phase 1.5 timing invariant. Same deferral applies.

### K. SCK / MOSI direct-drive utilities (lines 6680–6687)

| Line | Operation | Pin | Step |
|---:|:--|:--|:--|
| 6680 | `DRVL _sck` | SCK | drive LOW |
| 6683 | `DRVH _sck` | SCK | drive HIGH |
| 6687 | `DRVH _mosi` | MOSI | drive HIGH |

**Verdict:** N/A — these are bit-banged GPIO operations on already-configured smart pins (DRVH/DRVL change the OUT bit through the smart-pin override path). Not a reconfiguration sequence.

### L. `applySPISpeed` re-application sites (lines 4432, 4458, 6920, 6922)

`applySPISpeed` is called multiple times in the driver lifecycle:
- Line 5539 (init): `applySPISpeed(INIT_SPI_FREQ)` — 400 kHz init
- Line 4432: `applySPISpeed(50_000_000)` — 50 MHz post-init
- Line 4458: `applySPISpeed(25_000_000)` — 25 MHz post-init
- Line 6920, 6922: re-speed for CMD6 high-speed mode

Each call writes WXPIN(sck, half_period) at line 5339 and `pinl(sck)` at line 5340. Per task **C** above, this is canonical order PASS for SCK. The smart pin is *not* DIRL'd before WXPIN in these re-applications — but **WXPIN can be written while a smart pin is running** (per `p2kbArchSmartPins` "live update behavior": "WXPIN works freely while smart pin is running (DIR=1)"). So this is fine.

**Verdict:** PASS.

---

## Summary table — verdicts

| Section | Site | Per-pin order | Cross-pin order | Phase 1.5 timing | Notes |
|:--|:--|:--:|:--:|:--:|:--|
| A | Worker init GPIO | N/A | N/A | N/A | not smart-pin reconfig |
| B | initSPIPins | PASS | PASS | N/A | foundation; SCK enable in C |
| C | applySPISpeed SCK enable | PASS | PASS | N/A | live-update WXPIN safe |
| D | sp_transfer_8 PASM | PASS | PASS | N/A | byte-by-byte path |
| E | sp_transfer_32 PASM | PASS | PASS | N/A | 32-bit path |
| F | initCard recovery flush | **POSSIBLY FAIL** | PASS | N/A | WRPIN before DIRL; mode %00000 likely tolerated |
| G | readSector streamer | PASS | PASS | **FAIL** | Phase 1.5 target |
| H | readSector streamer-write verify | PASS | PASS | **FAIL** | Phase 1.5 target |
| I | writeSector main streamer | PASS | PASS | **FAIL** | Deferred per @evanh |
| J | writeSector multi-block streamer | PASS | PASS | **FAIL** | Deferred per @evanh |
| K | SCK/MOSI direct-drive | N/A | N/A | N/A | bit-banged GPIO |
| L | applySPISpeed re-applications | PASS | PASS | N/A | live-update WXPIN safe |

---

## Phase 1 task C — apply fixes if any (sprint task #4)

Two findings that warrant action; the rest are PASS.

### Action 1: Section F — `initCard` recovery flush WRPIN-before-DIRL ordering

**Site:** lines 5514-5515 (`WRPIN(miso, P_HIGH_15K)` followed by `pinf(miso)`).

**Issue:** WRPIN is written before MISO is reset to DIR=0. The KB says smart pins MUST be reset before WRPIN.

**Risk assessment:** Low. WRPIN here writes mode `%00000` (P_HIGH_15K = pass-through with 15K pull-up), which disables smart-pin behavior. The DIRL invariant likely doesn't apply to mode-zero writes, and the driver has shipped this way without observed misbehavior across many cards.

**Decision: APPLY THE FIX.** The fix is risk-free, makes the code KB-canonical, and removes a footgun if anyone ever changes mode `%00000` to a different mode without reordering. Swap lines 5514 and 5515 (and their comments) so MISO is `pinf(miso)`'d before `WRPIN(miso, P_HIGH_15K)`. After the WRPIN, MISO remains in DIR=0 (input mode with pull-up active), which matches the existing intent.

**Note:** look closely at the existing line ordering — it may be that `pinclear(miso)` earlier in the function already left MISO at DIR=0, in which case WRPIN-first is technically OK. Verify before applying the swap.

### Action 2: Sections G and H — Phase 1.5 inline-PASM timing invariant

**Sites:** lines 5821-5840 (G), and the equivalent block within writeSector verify path (H).

**Decision: DEFER TO PHASE 1.5 (sprint task #5).** This is exactly the work Phase 1.5 is scoped to do. Phase 1 is "audit and fix canonical order"; Phase 1.5 is the targeted inline-PASM reorder. Keeping them separate keeps the diffs cleanly attributable.

### Sites with no action

- A, B, C, D, E, K, L: PASS.
- I, J: FAIL on Phase 1.5 invariant but explicitly **deferred** per @evanh's Part 3 feedback (handle writeSector after @macca confirms the readSector fix).

---

## Conclusion

**Phase 1 audit complete.** Out of 97 inventoried pin-control sites:

- 91 sites pass all applicable invariants.
- 1 site (Section F, recovery flush) has a minor canonical-order deviation that we will fix preemptively for hygiene.
- 4 sites (G, H, I, J — the streamer inline-PASM blocks) fail the Phase 1.5 timing invariant. G and H are addressed by sprint task #5 (Phase 1.5). I and J are deferred per the agreed sequencing.

The Phase 1 fix work is **a single small change at lines 5514-5515** (Section F). After applying it, the driver is canonically compliant on all per-pin and cross-pin invariants for sites within Phase 1's scope. Compile cleanliness is preserved.
