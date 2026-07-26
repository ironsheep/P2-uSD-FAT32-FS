# SPI Clock Divisor & Margin — Analysis and Action Plan

**Date:** 2026-05-04 (last revised after reasoning consolidation)
**Author:** Stephen M Moraco
**Status:** Action plan agreed; test driver to be built next
**Related:** `DOCs/User-Reports/2026-05-04-macca-1GB-card-clock-sensitivity.md`

---

## Executive summary

A user (@macca) has a 1GB SDSC card that **works at sysclk=350 MHz and fails at sysclk=250 MHz**, both at the same target SPI rate (25 MHz). Both points produce *identical* SCK frequency (25.000 MHz exactly), so the failure isn't about clock rate. It's about **where in each bit cell the driver samples MISO, and how that sample point relates to the card's valid-data window** — both of which depend on the sysclk-to-SCK divisor (`hp`) rather than on SCK alone.

This document analyzes the design space, identifies which controls in the P2 smart-pin and streamer hardware can affect sample positioning, and proposes a four-step margin-improvement plan that can be implemented entirely in driver code with no impact on customer pin budget. A test driver embodying these changes will be sent to @macca for validation; we'll independently test on our reference hardware.

The four steps are:

1. **Audit and harden pin-setup ordering** in the driver (DIRL → WRPIN → WXPIN → DIRH, with correct ordering across the SCK / MOSI / MISO trio).
2. **Make the smart-pin RX sample mode (`WXPIN[5]`) adaptive** — flip from on-edge to pre-edge when `hp` is small, keeping the receiver near the geometric center of the bit cell across all sysclk values.
3. **Make the streamer `align_delay` adaptive** — set `align_delay = hp − 2` (or a tunable per-card offset) to cancel the streamer-pipeline equivalent of the on-edge sampling bias on bulk transfers.
4. **Settle drive-strength on the reference Edge module** — characterize SCK and MOSI edge cleanliness once on a logic analyzer, hardcode the values that give clean edges with low ringing, never adapt at runtime.

None of these consume pins. Steps 1–3 are driver-only changes. Step 4 is a one-time engineering exercise yielding a constant in the driver.

---

## Section 1 — The system, in one picture

When the SD driver reads a byte from the card, MISO data flows from the card's pin through one of **two distinct mechanisms** in the P2:

| Path | Used for | Sample mechanism | Phase knob today |
|---|---|---|---|
| **A — Smart-pin direct** (`sp_transfer_8`) | All single-byte traffic: command responses, R1 / R2 / start-token polls, CRC bytes, register reads, recovery flushes | `P_SYNC_RX` smart pin on MISO. B-input routed to SCK pin. Smart pin samples MISO on each SCK rising edge with X[5]=1 ("on-edge") sampling, which has a ~2-sysclk pipeline before the latched value is stable. | `WXPIN[5]`, fixed at on-edge |
| **B — Streamer DMA** (`STREAM_RX_BASE` / `STREAM_TX_BASE`) | Only the 512-byte sector body inside `readSector` / `writeSector`. The MISO smart pin is *temporarily disabled* during this window — the streamer reads the pin directly. | Streamer NCO. `align_delay` cog instructions delay between starting SCK and starting `XINIT`. `init_phase` positions the first sample within the NCO accumulator. | `align_delay`, fixed at `hp` |

Both paths transmit data through the *same* SCK and MOSI smart pins (in `P_TRANSITION` and `P_SYNC_TX` modes respectively), but they read MISO through different hardware. **The two paths do not share their phase-tuning controls.** Adjusting one does not affect the other. This distinction is essential to the analysis that follows; failing to keep them separate produces wrong conclusions.

---

## Section 2 — Why the failure exists at all

In SPI mode 0 the SD card launches each MISO bit on an SCK falling edge and holds it valid until the next falling edge. The host should sample at the *center* of the bit, which is the SCK rising edge. In sysclks, with half-period `hp`:

```
  bit launch (falling)                     next bit launch (falling)
        |                                          |
        |←─── SCK low half: hp sysclks ───→|←─── SCK high half: hp sysclks ───→|
        |                                          |
        ─────┐                                   ┌──
              │                                   │   SCK
              └───────────────────────────────────┘
                                |
                                ↑
                                SCK rising edge = geometric center of bit cell
                                = ideal sample point
```

The smart pin in on-edge mode samples ~2 sysclks past the rising edge. That `+2 sysclks` constant is independent of `hp`, but the bit cell width (`2·hp`) shrinks with `hp`. So as sysclk decreases (and `hp` shrinks), the same +2 offset becomes a larger fraction of the cell, biasing our sample increasingly toward the *trailing* edge of the bit — toward the next falling edge, where the card may begin transitioning to the next bit.

The card's valid-data window inside the bit cell is bounded by:

- **`t_OD`** (output delay): how long after the prior falling edge before MISO is valid. Determines the leading edge of the valid window.
- **Output hold** after the *next* falling edge: how long the card keeps the prior bit valid before changing. Determines the trailing edge.

Both are properties of the card silicon. Old SDSC cards typically have larger `t_OD` and shorter post-edge hold. The narrower the card's valid window, the less tolerant it is of sample-point bias.

@macca's 1GB SDSC card is exactly this case: `t_OD` long enough that at sysclk=250 MHz / hp=5 our +2 sample offset (combined with whatever the card's leading-edge delay is) leaves no margin. At sysclk=350 MHz / hp=7 the same sample offset still has 5 sysclks of trailing margin — comfortably inside the valid window.

---

## Section 3 — Boundary conditions: what's variable, what isn't

The driver's primary deployment is the **P2 Edge module's built-in microSD socket**. SD lines on that module are short, direct, and timed deterministically. Manufacturing variation on the module is far below our timing margin needs. So:

- **The electrical channel is fixed.** Trace length, impedance, ringing profile, capacitive loading from the SD socket: all known constants per Edge module revision.
- **Drive strength becomes a one-time engineering decision**, not an adaptive runtime knob. Pick the setting on the reference hardware that gives the cleanest edges; hardcode it forever.
- **The only material variability is the card itself.** TAAC, NSAC, output-delay, output-hold, internal clock-domain latencies — all card-side properties, all reported (in part) by the card's own CSD register.

This narrows the algorithm: we are designing for **card variability on a known-good electrical channel.** Failure-mode candidates that depend on board-level variability (ringing, reflections, channel-induced glitches) drop in priority. Failure-mode candidates that depend on driver setup-order errors or card-internal timing rise in priority.

---

## Section 4 — The four real failure modes, on a fixed channel

With the channel deterministic, the failure modes that matter are:

### 4.1 Sample lands inside `t_OD` (leading edge of valid window)

The card hasn't finished driving the new bit by the time we sample. Reads return whatever was on MISO before the bit became valid — often the previous bit's value, sometimes a transitional level interpreted by chance. Most commonly affects the *first* bit of a byte (where the card has had less time to update than for subsequent bits, or where the prior bus state was idle-high and any "0" bit is misread as "1").

**Cause:** sample point biased too early. With on-edge sampling, our sample is at `+2 sysclks` past the SCK rising edge, which is mid-cell — usually safe — but for old cards with large `t_OD`, even mid-cell may be inside the leading edge.

### 4.2 Sample lands too close to the trailing edge

The card may begin transitioning to the next bit slightly before the next SCK falling edge. With on-edge sampling our sample is `+2 sysclks` past the rising edge, leaving `hp − 2` sysclks of trailing margin. At hp=4 that's 2 sysclks — exactly the on-edge mode's documented hold requirement, with zero design margin.

**Cause:** sample point biased too late, *or* bit cell is narrow because hp is small. Same +2 offset, increasingly squeezed cell.

### 4.3 First-bit setup glitch

The very first bit of a transfer can read wrong if the receiving smart pin's edge counter is in an indeterminate state when the first SCK edge arrives. Subsequent bits in the same burst are fine — the receiver is now locked.

**Cause:** pin-setup ordering. If MISO smart pin is enabled *after* SCK has begun toggling, or if an SCK glitch occurs in the window between MISO smart-pin enable and the first real SCK edge, the receiver may miss or double-count an edge.

This is *not* a margin issue — it's a setup-order bug. With correct ordering and clean edges, it does not occur.

### 4.4 Write-side bit corruption

Symmetric to 4.1/4.2 but on the MOSI / TX side. Driver shifts MOSI on SCK rising edges with a ~2-sysclk pipeline. The card sets up its own MOSI sample at its rising edge with its own setup time. If the card's setup window is tighter than our pipeline allows, the card sees the *previous* bit at the moment of its sample.

**Cause:** TX smart pin has no `WXPIN[5]`-equivalent. We have less direct control over MOSI timing than over MISO timing.

---

## Section 5 — Knobs available, by path

The complete inventory of smart-pin and streamer controls is in [Appendix B](#appendix-b--exhaustive-knob-inventory). Here, the subset that matters for our four steps:

### Path A (smart-pin direct) — the controls

| Knob | What it does | Range | Cost |
|---|---|---|---|
| `WXPIN[5]` on MISO | `0` = pre-edge sample (~−1 sysclk before SCK edge); `1` = on-edge sample (~+2 sysclks after) | binary, ~3 sysclks repositioning total | free |
| DIRH ordering | Order in which we enable the SCK / MOSI / MISO smart pins relative to one another and to the cog issuing clock pulses | first-bit only | free |
| OUT-bit pre-position | Set the pin's idle state cleanly before enabling the smart pin | first-bit only | free |
| Drive strength on SCK | Slew rate of SCK as the card sees it; affects edge cleanliness | small effect | free |

### Path B (streamer DMA) — the controls

| Knob | What it does | Range | Cost |
|---|---|---|---|
| `align_delay` | `WAITX` between starting SCK and starting the streamer; positions the first streamer sample within the bit cell | continuous, 1-sysclk steps, full cell | free |
| `init_phase` | Initial value of streamer NCO accumulator; co-determines first-sample position | continuous (alternate to `align_delay`) | free |
| Drive strength on MOSI | Slew rate of MOSI on writes | small effect | free |

Knob #15 (`WXPIN[5]`) and `align_delay` are the primary phase-tuning levers. Drive strength is a one-time fixed-default engineering decision. Setup ordering must be correct in every code path; it's not a continuous knob, it's a correctness invariant.

We deliberately exclude any knob that consumes a physical pin (e.g., an auxiliary phase-shifted clock pin). Customer pin budget is preserved as a default; if the four-step plan proves insufficient on real cards, we revisit pin-consuming options at that point.

---

## Section 6 — Quantifying the divisor and sample-point geometry

Two foundational tables. The first shows what divisor (`hp`) the driver computes per sysclk and the resulting SCK frequency. The second shows the deviation from geometric center for each row, in both today's configuration and the proposed configuration.

### 6.1 Table — Divisor and actual SCK by sysclk

The driver computes `hp = ceil(clkfreq / 50_000_000)`, clamped to `hp ≥ 4`, then `actual_SCK = clkfreq / (2·hp)`.

| sysclk (MHz) | hp | SCK period (sysclks) | Actual SCK (MHz) | Off target |
|---:|---:|---:|---:|---:|
| 400 |  8 | 16 | 25.0000 | 0.00% |
| 395 |  8 | 16 | 24.6875 | -1.25% |
| 390 |  8 | 16 | 24.3750 | -2.50% |
| 385 |  8 | 16 | 24.0625 | -3.75% |
| 380 |  8 | 16 | 23.7500 | -5.00% |
| 375 |  8 | 16 | 23.4375 | -6.25% |
| 370 |  8 | 16 | 23.1250 | -7.50% |
| 365 |  8 | 16 | 22.8125 | -8.75% |
| 360 |  8 | 16 | 22.5000 | -10.00% |
| 355 |  8 | 16 | 22.1875 | -11.25% |
| **350** |  **7** | **14** | **25.0000** | **0.00%**  ←  WORKS (1GB) |
| 345 |  7 | 14 | 24.6429 | -1.43% |
| 340 |  7 | 14 | 24.2857 | -2.86% |
| 335 |  7 | 14 | 23.9286 | -4.29% |
| 330 |  7 | 14 | 23.5714 | -5.71% |
| 325 |  7 | 14 | 23.2143 | -7.14% |
| 320 |  7 | 14 | 22.8571 | -8.57% |
| 315 |  7 | 14 | 22.5000 | -10.00% |
| 310 |  7 | 14 | 22.1429 | -11.43% |
| 305 |  7 | 14 | 21.7857 | -12.86% |
| 300 |  6 | 12 | 25.0000 | 0.00% |
| 295 |  6 | 12 | 24.5833 | -1.67% |
| **290** |  **6** | **12** | **24.1667** | **-3.33%**  ←  @macca empirical boundary |
| 285 |  6 | 12 | 23.7500 | -5.00% |
| 280 |  6 | 12 | 23.3333 | -6.67% |
| 275 |  6 | 12 | 22.9167 | -8.33% |
| 270 |  6 | 12 | 22.5000 | -10.00% |
| 265 |  6 | 12 | 22.0833 | -11.67% |
| 260 |  6 | 12 | 21.6667 | -13.33% |
| 255 |  6 | 12 | 21.2500 | -15.00% |
| **250** |  **5** | **10** | **25.0000** | **0.00%**  ←  FAILS (1GB) |
| 245 |  5 | 10 | 24.5000 | -2.00% |
| 240 |  5 | 10 | 24.0000 | -4.00% |
| 235 |  5 | 10 | 23.5000 | -6.00% |
| 230 |  5 | 10 | 23.0000 | -8.00% |
| 225 |  5 | 10 | 22.5000 | -10.00% |
| 220 |  5 | 10 | 22.0000 | -12.00% |
| 215 |  5 | 10 | 21.5000 | -14.00% |
| 210 |  5 | 10 | 21.0000 | -16.00% |
| 205 |  5 | 10 | 20.5000 | -18.00% |
| 200 |  4 |  8 | 25.0000 | 0.00% |
| 195 |  4 |  8 | 24.3750 | -2.50% |
| 190 |  4 |  8 | 23.7500 | -5.00% |
| 185 |  4 |  8 | 23.1250 | -7.50% |
| 180 |  4 |  8 | 22.5000 | -10.00% |
| 175 |  4 |  8 | 21.8750 | -12.50% |
| 170 |  4 |  8 | 21.2500 | -15.00% |
| 165 |  4 |  8 | 20.6250 | -17.50% |
| 160 |  4 |  8 | 20.0000 | -20.00% |
| 155 |  4 |  8 | 19.3750 | -22.50% |
| 150 |  4* |  8 | 18.7500 | -25.00% (clamp engaged below this) |

The shelves are clear: every multiple of 50 MHz drops `hp` by one and snaps actual SCK back to 25 MHz exactly. **Both known data points (350 and 250) sit on shelf tops and produce identical 25.000 MHz SCK** — confirming that frequency is not the discriminator.

### 6.2 Table — Sample-point deviation: today vs. corrected

The bit cell is `2·hp` sysclks wide, with the geometric center at `hp` sysclks from the cell's leading falling edge. Today, the on-edge smart-pin samples at `hp + 2` sysclks (Path A), and the streamer's first sample is intentionally aligned to `hp` sysclks (Path B's design intent). The Path A `+2 sysclks` deviation is what we want to cancel.

For each row, three column groups:

- **TODAY**: sample point in sysclks from cell leading edge, deviation in sysclks/ns/% of cell.
- **CORRECTED**: assuming we apply the matching phase fix (Path A: `WXPIN[5]=0`; Path B: `align_delay = hp − 2`), the new sample point and its deviation.
- **IMPROVEMENT**: trailing-margin recovered (in sysclks, ns, and percentage points).

| sysclk | hp | Cell ns | TODAY: sample / dev sc / dev ns / dev % | CORRECTED: sample / dev sc | IMPROVE: sc / ns / pp of cell |
|---:|---:|---:|:---|:---|:---|
| 400 | 8 | 40.00 | 10sc / +2sc / +5.00ns / +12.50% | 8sc / 0 | 2sc / 5.00ns / 12.50pp |
| 350 | 7 | 40.00 |  9sc / +2sc / +5.71ns / +14.29% | 7sc / 0 | 2sc / 5.71ns / 14.29pp |
| **300** | **6** | **40.00** |  **8sc / +2sc / +6.67ns / +16.67%** | **6sc / 0** | **2sc / 6.67ns / 16.67pp** |
| **290** | **6** | **41.38** |  **8sc / +2sc / +6.90ns / +16.67%** | **6sc / 0** | **2sc / 6.90ns / 16.67pp**  ← @macca boundary |
| **250** | **5** | **40.00** |  **7sc / +2sc / +8.00ns / +20.00%** | **5sc / 0** | **2sc / 8.00ns / 20.00pp**  ← FAILS today |
| 200 | 4 | 40.00 |  6sc / +2sc / +10.00ns / +25.00% | 4sc / 0 | 2sc / 10.00ns / 25.00pp |

(Full table at all 5 MHz steps in [Appendix A](#appendix-a--full-deviation-and-correction-tables).)

**Key observations:**

- The deviation correction is constant in sysclk units (always `−2`), but its absolute size in nanoseconds grows as sysclk drops. Same fix, more meaningful effect at lower sysclk.
- After correction, **every row hits 50% trailing margin** — perfect symmetry around geometric center, regardless of hp. This is the algorithmic property that makes the fix robust across the full sysclk range.
- The biggest improvement is at the worst case (hp=4): trailing margin goes from 25% of cell to 50% of cell, a 100% relative increase exactly where today's headroom is thinnest.

---

## Section 7 — The four-step action plan

### Step 1 — Audit DIRL/WRPIN/WXPIN/DIRH ordering

**Goal:** verify that every pin-configuration sequence in the driver follows the canonical order and that pin enable across the SCK/MOSI/MISO trio happens in the right sequence.

**Canonical sequence per pin** (from `p2kbArchSmartPins`):

```
DIRL pin              ' reset (DIR=0)
WRPIN mode, pin       ' set mode and routing
WXPIN x, pin          ' set X
WYPIN y, pin          ' set Y (when applicable)
DIRH pin              ' enable LAST
```

**Cross-pin order** (per `p2kbPasm2StreamerSmartpinControl`): smart pins must be enabled before any code path that drives clock edges through them. Specifically:

- Receivers (`P_SYNC_RX` MISO smart pin) must be `DIRH`'d **before** `WYPIN` to the SCK pin starts the clock.
- The streamer must be started after both data smart pins are enabled.

**Audit points in the driver:**

- `initSPIPins` (first-time pin configuration)
- `applySPISpeed` (every speed change)
- After streamer reads — re-enabling MISO smart pin (line ~5854)
- After streamer writes — re-enabling MOSI smart pin (line ~6155)
- Every `pinclear()` followed by reconfiguration

For each, verify (a) the canonical per-pin order and (b) the cross-pin order. Confirm with logic-analyzer trace on the reference Edge module that SCK is genuinely idle and clean during the windows where receivers transition between enabled and disabled states.

This step can produce no driver code change at all (if everything is already correct), or it can produce small ordering fixes. **Either outcome is informative.**

### Step 2 — Adaptive `WXPIN[5]` for Path A

**Goal:** make MISO sample mode track `hp`, so the receiver stays near the geometric center of the bit cell across the full sysclk range.

**Mechanism:** `WXPIN[5]` is a one-bit knob inside the WXPIN value passed to the MISO smart pin. Today it is fixed at `1` (on-edge, +2 sysclks late). When `hp` is small, flipping to `0` (pre-edge, −1 sysclk early) repositions the sample by ~3 sysclks, recovering trailing-edge margin at the cost of leading-edge margin.

**Decision:** the cleanest implementation is to compute the WXPIN value as a function of `hp` inside `applySPISpeed`, alongside the existing half-period calculation. A reasonable initial threshold:

```spin2
' In applySPISpeed, after computing half_period:
miso_wxpin := (half_period >= 6) ? %1_00111 : %0_00111
'                                  on-edge   pre-edge
'                                  (+2 sc)   (-1 sc)
```

The threshold value (6 here) is itself tunable; the test driver should allow @macca and us to override it for sweep testing.

**Where the value is used:** every site that writes WXPIN to the MISO pin. Today these are constants (`%1_00111`); they become references to the computed `miso_wxpin`. Search the driver for `WXPIN(_miso, %1_00111)` and `WXPIN(miso, %1_00111)` — there are several call sites.

### Step 3 — Adaptive `align_delay` for Path B

**Goal:** make the streamer's first-sample position track `hp` minus the equivalent on-edge bias, so bulk sector reads are centered the same way Path A is.

**Mechanism:** `align_delay := spi_period` becomes `align_delay := spi_period + align_delay_offset`, where `align_delay_offset` is a signed integer. Default `0` for current behavior; setting it to `−2` cancels the equivalent pipeline.

**Implementation site:** `src/micro_sd_fat32_fs.spin2:5781` (read path) and the equivalent line in the write path (~5927). Lift `align_delay_offset` to a driver-level state variable that can be set by the test driver for sweep testing.

**Floor:** `align_delay` must be ≥ 2 sysclks (cog needs at least that long to execute WAITX before XINIT). At hp=4 with `align_delay_offset = −2`, we land on the floor exactly. Below that, we'd need a different mechanism (e.g., `init_phase` instead of `align_delay`); for now we cap at the floor.

### Step 4 — Settle drive strength on the reference Edge module

**Goal:** pick fixed drive-strength values for SCK and MOSI on the P2 Edge module that produce clean edges with low ringing at the SD socket pins. Hardcode them.

**Method:** with @macca's working 32GB card and the failing 1GB card on the reference Edge module, capture SCK and MOSI traces on a logic analyzer at the SD socket pins. Vary the drive-strength bits in WRPIN's M[12:0] field. Find the setting where edges are crispest with minimal post-edge ringing. Confirm this same setting works for both cards (it should, since the channel is determined by the module, not the card).

**Output:** two constants in the driver (one for SCK, one for MOSI). No runtime adaptation. No CSD-driven adjustment. This is a one-time engineering decision based on hardware that we own.

This step is independent of steps 1–3 and can run in parallel. It may turn out the current default is already optimal; in that case, step 4 produces a verification log and no code change.

---

## Section 8 — Test plan

### What we ship to @macca

A test driver based on the production driver with steps 1–3 implemented and all three knobs exposed as runtime parameters:

- `set_align_delay_offset(offset)` — signed integer, sets the streamer-path phase offset.
- `set_miso_sample_mode(mode)` — 0 for pre-edge, 1 for on-edge.
- `set_pre_edge_threshold(hp_threshold)` — `hp` value at and below which the driver auto-switches to pre-edge.

Plus a built-in sweep test that runs a known sector through both byte-by-byte and streamer paths at each candidate setting and reports pass/fail with margin metrics.

### What @macca runs

1. Confirm the failing case still fails with all settings at defaults (validates the test rig).
2. Run the sweep at sysclk=250 MHz against the 1GB card. Report which combinations pass.
3. Run the same sweep at sysclk=350 MHz against both cards. Confirm all settings still pass at the known-good sysclk.
4. If we have logic-analyzer-time and inclination: capture SCK and MOSI traces at the SD socket pins for the drive-strength characterization (step 4).

### What we run independently

Same sweep against our card matrix on our reference Edge module. Compare the bathtub-curve shapes between his hardware and ours. Differences pinpoint either card-specific timing or any residual electrical variation between modules (which should be small).

### Decision criteria

- **If the sweep finds a settled `align_delay_offset` and `WXPIN[5]` combination that passes @macca's 250 MHz case while still passing every other card we test:** ship steps 1–3 in the production driver with sensible defaults from the sweep. Step 4 confirmed independently.
- **If the sweep finds a setting that helps but doesn't fully recover:** we have evidence that knob #15's range is insufficient and need to revisit pin-consuming options. This is the threshold that justifies considering an auxiliary phase-shifted clock pin in a future revision.
- **If the sweep finds no setting that helps:** we've ruled out the sample-position hypothesis. The failure has a different root cause and we restart the analysis.

---

## Appendix A — Full deviation and correction tables

(Per-row computations at 5 MHz steps from 400 MHz down to 100 MHz. Generated by the script in §A.2; correctness verifiable from the source formulas.)

### A.1 — Full Path A deviation table, today vs. corrected (every row)

`hp` is the divisor with the `hp ≥ 4` clamp applied; `*` indicates the clamp engaged.

| sysclk | hp | Cell ns | TODAY: sample / dev sc / dev ns / dev % | CORRECTED: sample / dev sc | IMPROVE sc / ns / pp |
|---:|---:|---:|:---|:---|:---|
| 400 | 8 | 40.00 | 10sc / +2sc / +5.00ns / +12.50% | 8sc / 0 | 2 / 5.00 / 12.50 |
| 395 | 8 | 40.51 | 10sc / +2sc / +5.06ns / +12.50% | 8sc / 0 | 2 / 5.06 / 12.50 |
| 390 | 8 | 41.03 | 10sc / +2sc / +5.13ns / +12.50% | 8sc / 0 | 2 / 5.13 / 12.50 |
| 385 | 8 | 41.56 | 10sc / +2sc / +5.19ns / +12.50% | 8sc / 0 | 2 / 5.19 / 12.50 |
| 380 | 8 | 42.11 | 10sc / +2sc / +5.26ns / +12.50% | 8sc / 0 | 2 / 5.26 / 12.50 |
| 375 | 8 | 42.67 | 10sc / +2sc / +5.33ns / +12.50% | 8sc / 0 | 2 / 5.33 / 12.50 |
| 370 | 8 | 43.24 | 10sc / +2sc / +5.41ns / +12.50% | 8sc / 0 | 2 / 5.41 / 12.50 |
| 365 | 8 | 43.84 | 10sc / +2sc / +5.48ns / +12.50% | 8sc / 0 | 2 / 5.48 / 12.50 |
| 360 | 8 | 44.44 | 10sc / +2sc / +5.56ns / +12.50% | 8sc / 0 | 2 / 5.56 / 12.50 |
| 355 | 8 | 45.07 | 10sc / +2sc / +5.63ns / +12.50% | 8sc / 0 | 2 / 5.63 / 12.50 |
| 350 | 7 | 40.00 |  9sc / +2sc / +5.71ns / +14.29% | 7sc / 0 | 2 / 5.71 / 14.29  ← WORKS |
| 345 | 7 | 40.58 |  9sc / +2sc / +5.80ns / +14.29% | 7sc / 0 | 2 / 5.80 / 14.29 |
| 340 | 7 | 41.18 |  9sc / +2sc / +5.88ns / +14.29% | 7sc / 0 | 2 / 5.88 / 14.29 |
| 335 | 7 | 41.79 |  9sc / +2sc / +5.97ns / +14.29% | 7sc / 0 | 2 / 5.97 / 14.29 |
| 330 | 7 | 42.42 |  9sc / +2sc / +6.06ns / +14.29% | 7sc / 0 | 2 / 6.06 / 14.29 |
| 325 | 7 | 43.08 |  9sc / +2sc / +6.15ns / +14.29% | 7sc / 0 | 2 / 6.15 / 14.29 |
| 320 | 7 | 43.75 |  9sc / +2sc / +6.25ns / +14.29% | 7sc / 0 | 2 / 6.25 / 14.29 |
| 315 | 7 | 44.44 |  9sc / +2sc / +6.35ns / +14.29% | 7sc / 0 | 2 / 6.35 / 14.29 |
| 310 | 7 | 45.16 |  9sc / +2sc / +6.45ns / +14.29% | 7sc / 0 | 2 / 6.45 / 14.29 |
| 305 | 7 | 45.90 |  9sc / +2sc / +6.56ns / +14.29% | 7sc / 0 | 2 / 6.56 / 14.29 |
| 300 | 6 | 40.00 |  8sc / +2sc / +6.67ns / +16.67% | 6sc / 0 | 2 / 6.67 / 16.67 |
| 295 | 6 | 40.68 |  8sc / +2sc / +6.78ns / +16.67% | 6sc / 0 | 2 / 6.78 / 16.67 |
| 290 | 6 | 41.38 |  8sc / +2sc / +6.90ns / +16.67% | 6sc / 0 | 2 / 6.90 / 16.67  ← @macca boundary |
| 285 | 6 | 42.11 |  8sc / +2sc / +7.02ns / +16.67% | 6sc / 0 | 2 / 7.02 / 16.67 |
| 280 | 6 | 42.86 |  8sc / +2sc / +7.14ns / +16.67% | 6sc / 0 | 2 / 7.14 / 16.67 |
| 275 | 6 | 43.64 |  8sc / +2sc / +7.27ns / +16.67% | 6sc / 0 | 2 / 7.27 / 16.67 |
| 270 | 6 | 44.44 |  8sc / +2sc / +7.41ns / +16.67% | 6sc / 0 | 2 / 7.41 / 16.67 |
| 265 | 6 | 45.28 |  8sc / +2sc / +7.55ns / +16.67% | 6sc / 0 | 2 / 7.55 / 16.67 |
| 260 | 6 | 46.15 |  8sc / +2sc / +7.69ns / +16.67% | 6sc / 0 | 2 / 7.69 / 16.67 |
| 255 | 6 | 47.06 |  8sc / +2sc / +7.84ns / +16.67% | 6sc / 0 | 2 / 7.84 / 16.67 |
| 250 | 5 | 40.00 |  7sc / +2sc / +8.00ns / +20.00% | 5sc / 0 | 2 / 8.00 / 20.00  ← FAILS |
| 245 | 5 | 40.82 |  7sc / +2sc / +8.16ns / +20.00% | 5sc / 0 | 2 / 8.16 / 20.00 |
| 240 | 5 | 41.67 |  7sc / +2sc / +8.33ns / +20.00% | 5sc / 0 | 2 / 8.33 / 20.00 |
| 235 | 5 | 42.55 |  7sc / +2sc / +8.51ns / +20.00% | 5sc / 0 | 2 / 8.51 / 20.00 |
| 230 | 5 | 43.48 |  7sc / +2sc / +8.70ns / +20.00% | 5sc / 0 | 2 / 8.70 / 20.00 |
| 225 | 5 | 44.44 |  7sc / +2sc / +8.89ns / +20.00% | 5sc / 0 | 2 / 8.89 / 20.00 |
| 220 | 5 | 45.45 |  7sc / +2sc / +9.09ns / +20.00% | 5sc / 0 | 2 / 9.09 / 20.00 |
| 215 | 5 | 46.51 |  7sc / +2sc / +9.30ns / +20.00% | 5sc / 0 | 2 / 9.30 / 20.00 |
| 210 | 5 | 47.62 |  7sc / +2sc / +9.52ns / +20.00% | 5sc / 0 | 2 / 9.52 / 20.00 |
| 205 | 5 | 48.78 |  7sc / +2sc / +9.76ns / +20.00% | 5sc / 0 | 2 / 9.76 / 20.00 |
| 200 | 4 | 40.00 |  6sc / +2sc / +10.00ns / +25.00% | 4sc / 0 | 2 / 10.00 / 25.00  ← hits WAITX floor |
| 195 | 4 | 41.03 |  6sc / +2sc / +10.26ns / +25.00% | 4sc / 0 | 2 / 10.26 / 25.00 |
| 190 | 4 | 42.11 |  6sc / +2sc / +10.53ns / +25.00% | 4sc / 0 | 2 / 10.53 / 25.00 |
| 185 | 4 | 43.24 |  6sc / +2sc / +10.81ns / +25.00% | 4sc / 0 | 2 / 10.81 / 25.00 |
| 180 | 4 | 44.44 |  6sc / +2sc / +11.11ns / +25.00% | 4sc / 0 | 2 / 11.11 / 25.00 |
| 175 | 4 | 45.71 |  6sc / +2sc / +11.43ns / +25.00% | 4sc / 0 | 2 / 11.43 / 25.00 |
| 170 | 4 | 47.06 |  6sc / +2sc / +11.76ns / +25.00% | 4sc / 0 | 2 / 11.76 / 25.00 |
| 165 | 4 | 48.48 |  6sc / +2sc / +12.12ns / +25.00% | 4sc / 0 | 2 / 12.12 / 25.00 |
| 160 | 4 | 50.00 |  6sc / +2sc / +12.50ns / +25.00% | 4sc / 0 | 2 / 12.50 / 25.00 |
| 155 | 4 | 51.61 |  6sc / +2sc / +12.90ns / +25.00% | 4sc / 0 | 2 / 12.90 / 25.00 |
| 150 | 4* | 53.33 |  6sc / +2sc / +13.33ns / +25.00% | 4sc / 0 | 2 / 13.33 / 25.00  ← clamp engaged |

(Below 150 MHz the clamp dominates and the SCK frequency drops linearly with sysclk; the +2 deviation pattern continues identically because hp stays at 4. Rows truncated for brevity; same shape applies.)

### A.2 — Reproduction script

```python
target = 25_000_000
OFFSET = 2  # smart-pin on-edge mode samples +2 sysclks past SCK rising edge
for mhz in range(400, 99, -5):
    sysclk = mhz * 1_000_000
    natural_hp = -(-sysclk // (target * 2))   # ceiling division
    hp = max(4, natural_hp)
    cell = 2 * hp
    sysclk_ns = 1_000 / mhz
    cell_ns = cell * sysclk_ns
    sample_today = hp + OFFSET
    dev_today_pct = OFFSET / cell * 100
    sample_corrected = hp
    improve_sc = OFFSET
    improve_pct = OFFSET / cell * 100
```

Driver source of truth: `src/micro_sd_fat32_fs.spin2:5306-5343` (`applySPISpeed`).

---

## Appendix B — Exhaustive knob inventory

The complete control surface of the smart-pin and streamer hardware as it relates to our SPI signaling. Sources: P2KB entries `p2kbArchSmartPins`, `p2kbArchSmartPin11101SyncSerialReceive`, `p2kbArchSmartPin11100SyncSerialTransmit`, `p2kbArchSmartPin00101TransitionOutput`, `p2kbPasm2StreamerSmartpinControl`, `p2kbPasm2Wrpin`.

### B.1 — Where the configuration lives

A smart pin's complete configuration is held in four places:

1. **WRPIN value** — 32-bit, written by `WRPIN`. Format: `%AAAA_BBBB_FFF_MMMMMMMMMMMMM_TT_SSSSS_0`. Requires DIR=0 before write.
2. **X register** — 32-bit, mode-specific. Set by `WXPIN`. May be changed at runtime, but the KB warns that mid-transfer changes corrupt sync-serial in-progress data.
3. **Y register** — 32-bit, mode-specific. Set by `WYPIN`. Always-runtime-safe.
4. **DIR / OUT bits and timing** — when the pin is enabled and what its OUT bit was at the moment of enable.

External mechanisms (streamer, cog `WAITX`) influence timing without writing to the smart pin.

### B.2 — WRPIN field-by-field

#### AAAA (bits 31:28) — A-input selector

The data-side input. Eight source routings (this pin / ±1 / ±2 / ±3 / OUT bit) plus per-source invert; total 16 settings. **Routing only — not a phase delay.** Inversion is signal flip, not phase shift.

#### BBBB (bits 27:24) — B-input selector

The clock-side input. Same 16 settings. Routing only. **`P_INVERT_B` produces a 180° phase flip = `hp` sysclks** (since SCK is 50% duty), but this places the smart pin's "rising edge" on real SCK's falling edge — wrong location for SPI mode 0 alone.

#### FFF (bits 23:21) — A and B logic / filter

Eight values: four logic-combine modes (A, A AND B, A OR B, A XOR B) and four debounce filters (filt0=12.5 ns, filt1=600 ns, filt2=16.4 ms, filt3=210 ms). **Filters are debounce, not precise delays.** Filt0 is in the same magnitude as our SCK half-period at high speeds but is signal-slew-dependent — not usable as a phase-tuning knob.

#### M[12:0] (bits 20:8) — Pin-level analog and drive

Drive strength, pull-up/pull-down, DAC mode, ADC selection. **Drive strength affects edge slew rate**, which has a small but real effect on edge cleanliness as the card sees it. With a known electrical channel (Edge module), this is a one-time fixed-default decision, not adaptive.

#### TT (bits 7:6) — Output enable / source

Four settings for DIR-gated vs always-enabled output and OUT vs OTHER source. Driver uses `P_OE` (`%01`) on SCK and MOSI. Not a phase knob.

#### SSSSS (bits 5:1) — Smart-pin mode

5-bit mode selector, 32 modes. Driver uses `P_TRANSITION` (SCK), `P_SYNC_TX` (MOSI), `P_SYNC_RX` (MISO). Mode choice is architectural, not tuning.

### B.3 — WXPIN per mode (the relevant ones)

#### `P_TRANSITION` (SCK)

`X[15:0]` = transition period in sysclks (= our `hp`). Sets bit cell width.

#### `P_SYNC_TX` (MOSI)

`X[4:0]` = bit count − 1. `X[5]` = continuous (0) vs. start-stop (1). **`X[5]` on TX is buffering mode, not phase.** No equivalent of RX's pre-edge / on-edge knob.

#### `P_SYNC_RX` (MISO)

`X[4:0]` = bit count − 1. **`X[5]` = sample mode**: 0 = pre-edge (~−1 sysclk before edge), 1 = on-edge (~+2 sysclks after edge). **The only direct sample-phase knob in the smart pin.**

### B.4 — External mechanisms

- **Streamer `align_delay`**: cog `WAITX` between starting SCK and starting `XINIT`. Continuous, sysclk-resolution. Currently fixed at `hp`. Steers Path B sample point.
- **Streamer `init_phase`**: NCO accumulator initial value. Co-determines first-sample position. Alternative or composable with `align_delay`.
- **Pin layout**: BBBB selector range constrains where SCK can sit relative to MOSI / MISO. Not phase delay; constraint on routing.
- **DIRH ordering**: order in which smart pins are enabled. Affects first-bit alignment, not steady state.
- **Cog OUT pre-position**: idle state of the wire before smart pin takes over. Affects start-of-burst.
- **Auxiliary phase-shifted clock pin**: a second `P_TRANSITION` smart pin, period-matched to SCK, enabled at a sysclk-precise offset, routed to MISO smart pin's B-input. Continuous, sysclk-resolution sample-point control on Path A. **Costs one physical pin** — excluded from the four-step plan to preserve customer pin budget.

### B.5 — Master classification table

| # | Knob | Path | Type | Range | In four-step plan? |
|---:|---|:---:|---|---|:---:|
| 1 | RX A-input source | A | route | 8×invert | no (routing only) |
| 2 | RX A-input invert | A | logic | 2 | no (signal flip) |
| 3 | RX/TX B-input source | both | route | 8×invert | no (routing only) |
| 4 | P_INVERT_B | both | logic | 2 (=hp) | no (mode-incompatible alone) |
| 5 | A/B logic combine | both | logic | 4 | no |
| 6 | A/B filter | both | filter | 4 | no (debounce, not delay) |
| 7 | Drive strength | both | electrical | many | **step 4** (settled, not adaptive) |
| 8 | Pull-up/pull-down | both | electrical | on/off | no |
| 9 | TT (DIR override) | both | mode | 4 | no |
| 10 | Smart-pin mode | both | mode | 32 | no (architectural) |
| 11 | SCK half-period | both | timing | 1–65535 | sets cell width, not tuned |
| 12 | TX bit count | B-tx | mode | 1–32 | no |
| 13 | TX X[5] (continuous/start-stop) | B-tx | mode | 2 | no (not a phase knob) |
| 14 | RX bit count | A | mode | 1–32 | no |
| 15 | **RX X[5] (pre/on edge)** | **A** | **timing** | **2 (≈−1 / +2 sc)** | **step 2** |
| 16 | TX data | B-tx | data | 32-bit | no |
| 17 | SCK transition count | both | mode | 0/1+ | no |
| 18 | DIRH ordering | both | timing | sysclk steps | **step 1** (correctness) |
| 19 | OUT pre-position | both | timing | per-pin | step 1 (correctness) |
| 20 | **Streamer `align_delay`** | **B** | **timing** | **continuous, full cell** | **step 3** |
| 21 | Aux phase-shifted clock pin | A | timing | continuous, full cell | **excluded** (pin cost) |
| 22 | Streamer NCO mode for SCK | both | timing | fractional rates | no (architecture change) |

---

## Appendix C — Reasoning history and corrections

This appendix records reasoning that was superseded as the analysis progressed. It is preserved for traceability; the main body reflects current understanding.

### C.1 — Initial conflation of paths

The first version of this analysis treated the smart-pin direct path and the streamer-DMA path as a single sample mechanism with one phase knob. This was wrong: they use entirely different hardware (smart pin's autonomous edge-counting receiver vs. the streamer's NCO-driven direct pin read), and their phase controls are independent (`WXPIN[5]` vs. `align_delay`). A correction applied to one path does *not* affect the other. The path distinction is now a top-level structural element of the document (Section 1).

### C.2 — Overclaim on smart-pin tuning capability

An intermediate version of the document described `align_delay` as a continuous phase knob over the smart-pin sample point. It is not — it only steers the streamer path. The smart-pin path's only direct phase knob is the binary `WXPIN[5]`. Section 5 and Appendix B now state this correctly.

### C.3 — Spurious-edge "failure mode 4"

An earlier version proposed that whole-byte misalignment symptoms (e.g., `$FD` instead of `$FE`, write data-response of `$07`) might arise from the smart pin's edge counter miscounting. This was implausible — the silicon has been exhaustively tested, and given a clean input waveform the edge counter is deterministic. The credible cause for those symptoms is **pin-setup ordering errors** (smart pin enabled while SCK is already toggling, or smart pin enabled before configuration completes). Step 1 of the action plan addresses this directly.

### C.4 — Adaptive drive strength

An earlier version raised "adapt drive strength per card" as a possible algorithm. With the deterministic Edge-module channel, this is unnecessary: drive strength is a one-time engineering decision, validated on reference hardware, hardcoded in the driver. CSD timing fields characterize card-internal timing for sample-point logic, not channel-loading for drive strength.

### C.5 — Auxiliary phase-shifted clock pin

The pin-consuming knob (#21 in Appendix B) was initially proposed as a second-line option. After clarification on customer pin budget — and noting that it gives Path A what `align_delay` already gives Path B for free — it has been **excluded from the four-step plan** and is preserved only as a fallback to be reconsidered if steps 1–4 prove insufficient against real cards.
