# Sprint Plan: SPI Phase-Margin Improvement (steps 1–3)

**Date created:** 2026-05-04
**Last revised:** 2026-05-04 (Phase 1.5 added after KB-verified community feedback)
**Author:** Stephen + Claude
**Goal:** Build a test driver implementing steps 1–3 of the four-step plan from `DOCs/Analysis/2026-05-04-spi-clock-divisor-margin-table.md`, ship it to @macca for validation against his failing 1GB SDSC card at sysclk=250 MHz, and run independent verification on our reference Edge module.
**Status:** Plan draft, revised. No code changes yet.

Step 4 (drive-strength characterization) is a parallel hardware exercise, tracked separately — not in this sprint.

**Major revision 2026-05-04:** community feedback from @evanh (verified against `p2kbArchSmartPin00101TransitionOutput`) identified a likely root-cause bug in the inline-PASM ordering: the `P_TRANSITION` smart pin's first SCK transition lands at `2·hp` instead of `hp` when `hp ≤ 6`, because intervening setup instructions push WYPIN past the first base-period boundary. This is a precise mechanism that explains @macca's hp-dependent failure pattern and is now prioritized as Phase 1.5, executed **before** Phases 2 and 3. See `DOCs/User-Reports/2026-05-04-evanh-streamer-stability-feedback.md` for the verification.

---

## Overview of the deliverable

A **test build of `micro_sd_fat32_fs.spin2`** that:

1. **Has DIRL/DIRH/WRPIN/WXPIN ordering audited and corrected** at every call site that touches SCK / MOSI / MISO smart pins. No behavior change in the steady-state path; correctness fixes only where audit finds issues.
2. **Computes `miso_wxpin` adaptively** as a function of `hp` (effective half-period) inside `applySPISpeed`, replacing the literal `%1_00111` constant at every WXPIN site for the MISO pin.
3. **Computes `align_delay` adaptively** as `spi_period + align_delay_offset` at the streamer-burst sites, with `align_delay_offset` defaulting to `0` (preserves current `align_delay = hp` behavior) and overridable at runtime. Default of `0` rather than `−2` reasoning is in §3.5.
4. **Exposes three runtime tuning knobs** plus a built-in sweep test that exercises both Path A (byte-by-byte) and Path B (streamer bulk) over a configurable parameter grid and reports per-cell pass/fail with measured margin.

The runtime knobs:

```spin2
PUB setSampleMode(mode)              ' 0=pre-edge, 1=on-edge, -1=auto-by-hp
PUB setAlignDelayOffset(offset)      ' signed integer, sysclks
PUB setPreEdgeThreshold(hp_thresh)   ' hp value at/below which auto switches to pre-edge
```

Plus diagnostic getters so a test program can query the current effective settings:

```spin2
PUB getEffectiveSampleMode() : mode  ' returns the actual %X_00111 value used
PUB getEffectiveAlignDelay() : delay ' returns the actual sysclk count
PUB getCurrentHp() : hp              ' returns the current half-period
```

---

## Sweep prediction model

Before describing what each phase does, we commit to a **falsifiable prediction** of what the empirical sweep should find. This serves two purposes: it tightens our understanding (forces us to compute, not handwave), and it makes failure modes detectable (if the sweep doesn't match the prediction, we know the model is missing something).

### The model

After Phase 1.5 corrects the first-SCK-edge timing, the streamer's optimal sample point on the wire — for any given card and sysclk — is governed by:

```
optimal_align_delay = hp + Δ_host(sysclk) + Δ_card(card_t_OD, sysclk)
```

Where `Δ_host` is the round-trip delay through the P2 I/O ring, and `Δ_card` is the card's response time converted to sysclks at the operating sysclk.

### Component delays — sources and grounding

| Component | KB / spec source | Value | Notes on uncertainty |
|---|---|---|---|
| Smart-pin output staging (smart pin → SCK pad) | `p2kbArchIoPinTiming` | "6-9 ns typical" | **Range exists in the silicon spec.** Single chip is fixed but unknown without measurement. To pin: capture SCK transition vs. cog instruction with logic analyzer. |
| Card SCK input → MISO drive (card's `t_OD`) | SD spec; per-card via CSD `TAAC` + `NSAC` | card-specific | **Unknown until CSD is read.** For @macca's 1GB SDSC: ask for the CSD register dump from `SD_card_identify.spin2`. Modern cards: typically <4 ns. |
| Registered input (MISO pad → smart pin / streamer) | `p2kbArchIoPinTiming` | "3-4 clock cycles" | **KB-cited as a sysclk count, with a 1-clock range.** The range may reflect synchronizer metastability uncertainty (worst-case 4, best-case 3). Treat as 3.5 ± 0.5. |

The first and third components are P2-side (deterministic for a given chip and sysclk), the second is card-side (deterministic for a given card).

### Per-sysclk computation (no card-specific data yet)

For the smart-pin output path, the silicon spec gives nanoseconds; we convert to sysclks by dividing by the sysclk period:

| sysclk (MHz) | sysclk period (ns) | Smart-pin output (sysclks)| Registered input (sysclks) | Host-side total (sysclks) |
|---:|---:|:---|:---|:---|
| 350 | 2.857 | 2.10 to 3.15 (avg 2.6) | 3.0 to 4.0 (avg 3.5) | **5.10 to 7.15 (avg ~6.1)** |
| 290 | 3.448 | 1.74 to 2.61 (avg 2.2) | 3.0 to 4.0 (avg 3.5) | **4.74 to 6.61 (avg ~5.7)** |
| 250 | 4.000 | 1.50 to 2.25 (avg 1.9) | 3.0 to 4.0 (avg 3.5) | **4.50 to 6.25 (avg ~5.4)** |

So: **before** adding the card's `t_OD`, the predicted host-side compensation alone should be in the **5-6 sysclk range** at our test sysclks, with the exact value pinning down once we measure on hardware. The "+5 to +8" range I was citing was that 5-6 host-side baseline plus 0-2 sysclks of card-side allowance — but with no per-card grounding.

### Per-card computation (with CSD)

The card's CSD register encodes its declared timing in two fields:

- **TAAC** (1 byte): time-unit + multiplier giving the access time portion.
- **NSAC** (1 byte): number of clocks contribution.

Card-declared maximum read access time is computed as:

```
t_AC = TAAC_value + (NSAC_value × 100 × SCK_period)
```

This isn't quite the same as `t_OD` (it's the post-CMD17 time-to-first-data-byte, not a per-bit launch delay), but it bounds it from above. For a card declaring TAAC=1.5 ms with NSAC=0, the per-bit `t_OD` is much smaller — measured in nanoseconds. For a card declaring TAAC=10 ms with NSAC=10, you're seeing a much slower part.

**Action item — gather CSD before sweep is most useful:** request the CSD register dump from @macca's 1GB SDSC card and from at least one modern card on our reference hardware. We can then compute predicted `Δ_card` per card and refine the per-card prediction.

Until the CSD is in hand, our **predicted optimal `align_delay_offset`** at the test sysclks is just the host-side host-side baseline, with card variation as known unknown:

| sysclk (MHz) | Predicted optimal `align_delay_offset` | Sweep target band | Rationale |
|---:|---:|---:|---:|
| 350 | +5 to +7 | sweep `[+3, +9]`, expect plateau center near +6 | Host-side avg ~6, card adds 0-2 |
| 290 | +5 to +6 | sweep `[+3, +8]`, expect plateau center near +5.5 | Host-side avg ~5.5 |
| 250 | +4 to +6 | sweep `[+2, +8]`, expect plateau center near +5 | Host-side avg ~5 |

For the *unified* sweep (running all sysclks against the same offset range), the union is `[−3, +8]` — covering both the predicted optimum and a margin band on either side.

### What we expect the sweep to look like

For each `(sample_mode, align_delay_offset)` cell on a given card and sysclk:

- We expect to see a **bathtub curve** when sweeping `align_delay_offset` at fixed `sample_mode`: a band of passing offsets, flanked by failing offsets on both sides.
- The **center of the passing band** for a given (card, sysclk) is our predicted optimum.
- The **width of the passing band** measures the card's valid-data window margin.

Cross-card and cross-sysclk:

- The passing band's center should shift left as sysclk drops (because `Δ_host` in sysclks decreases).
- The passing band's width should be roughly constant across sysclks for the same card (because the bit cell and card timing both scale similarly with sysclk).
- Different cards should show *different* passing-band centers if `t_OD` varies card-to-card; if all cards' centers are within ±1 sysclk, a single fixed default suffices for the production driver.

### Falsification — what would tell us the model is wrong

- If the passing-band center is **far from** our predicted +5 to +7 (e.g., at +0 or +12), our `Δ_host + Δ_card` decomposition is missing something or has a sign error.
- If the passing band has **two separate plateaus** instead of one, there's a phenomenon we're not modeling (likely: bit-cell interactions across the streamer NCO that re-align at certain offsets).
- If the passing band has **no clear center** (all offsets pass or all fail), the failure isn't at this knob — it's somewhere else (likely Path A, drive strength, or a bug we haven't identified).
- If the band is **much narrower** than ~5 sysclks, the card's valid window is very narrow and we have less margin than expected; consider reducing SCK rate.

These are concrete things to look for in the sweep output. They should be flagged automatically by the test program (Phase 4) as anomalies if they occur.

---

## Sprint phases

The work splits into four phases that should mostly run sequentially. Phase 1 (audit) gates phases 2–3; phases 2 and 3 can be implemented in parallel once phase 1 completes and is reviewed.

### Phase 1 — DIRL/DIRH/WRPIN/WXPIN ordering audit

**Goal:** Confirm or fix the canonical pin-setup order at every call site that touches the SCK / MOSI / MISO smart pins.

**Canonical per-pin order** (from `p2kbArchSmartPins`):

```
DIRL  pin                ' reset (DIR=0)
WRPIN mode, pin          ' configure mode + routing
WXPIN x, pin             ' set X parameter
WYPIN y, pin             ' set Y parameter (when applicable)
DIRH  pin                ' enable (DIR=1) — must be LAST
```

**Cross-pin invariant** (from `p2kbPasm2StreamerSmartpinControl`): smart pins must be enabled before edges arrive on their inputs. Specifically:

- The MISO smart pin's `DIRH` must complete **before** the next `WYPIN(N, sck)` that begins clocking.
- The MOSI smart pin's `DIRH` must complete **before** the next `WYPIN(N, sck)` that begins clocking.
- Streamer `XINIT` must occur **after** all relevant smart pins are enabled.

#### Phase 1 tasks

**1.1 Inventory every site that writes WRPIN / WXPIN / WYPIN / DIRL / DIRH / pinclear / pinf / pinh on the SPI pins.**

Search targets:
```
grep -nE 'WRPIN|WXPIN|WYPIN|DIRL|DIRH|pinclear|pinf\(|pinh\(|pinl\(' src/micro_sd_fat32_fs.spin2 \
  | grep -E '_sck|_miso|_mosi|sck,|miso,|mosi,|sck\)|miso\)|mosi\)|cs,|cs\)'
```

Build a table of (line number, function, operation, pin, surrounding context). Expected hot spots:

| Function (approximate) | Purpose | Likely sites |
|---|---|---|
| `initSPIPins` (~5230) | First-time pin configuration | Initial setup |
| `applySPISpeed` (~5306) | Speed-change reconfiguration of SCK | Period change, possibly MOSI/MISO restart |
| `readSector` (~5760+) | Streamer-driven sector read | MISO disable before streamer, re-enable after |
| `writeSector` (~6080+) | Streamer-driven sector write | MOSI disable before streamer, re-enable after |
| `sp_transfer_8` | Per-byte SCK toggle, MISO read | Inner loop — should not be reconfiguring smart pins |

**1.2 Verify each site against the canonical order.**

For each entry in the inventory:
- Does the per-pin sequence match `DIRL → WRPIN → WXPIN → [WYPIN] → DIRH`?
- For sequences spanning the trio, is MISO enabled before SCK starts toggling? Is MOSI enabled before MOSI is shifted? Is the streamer started last?
- Are there sites that write `WRPIN` while the pin is `DIRH`'d? (Per the KB this requires DIR=0; if found, this is a bug.)

**1.3 Audit the streamer-end re-enable points.**

Specifically focus on:
- `readSector` after `WAITXFI` — when MISO smart pin is re-enabled (`WRPIN(_miso, ...)` then `WXPIN(_miso, ...)` then `pinh(_miso)`).
- `writeSector` analog for MOSI.

Verify that:
- The pin is `DIRL`'d (or `pinclear`'d) before the new `WRPIN`.
- SCK is genuinely idle in the window between streamer completion and the next byte-by-byte transfer that will toggle SCK.
- No spurious SCK transition can occur during smart-pin re-enable.

**1.4 Document findings.**

Create `DOCs/Analysis/2026-05-04-spi-pin-setup-order-audit.md` with:
- The complete site inventory.
- Per-site pass/fail against canonical order.
- For any failing sites, the proposed fix.

**1.5 Implement any required ordering fixes.**

Per-site, in the smallest possible diff:
- Insert missing `DIRL`/`pinclear` before reconfiguration.
- Reorder operations so `DIRH` is last.
- Add `WAITX` separators where needed for cross-pin ordering.

**1.6 Verify on hardware.**

Run the existing regression test suite at sysclk=350 MHz (the known-good condition) against a working card. **All 464 tests must continue to pass.** If any test fails, the ordering change introduced a regression and must be fixed before continuing.

#### Phase 1 deliverables

- `DOCs/Analysis/2026-05-04-spi-pin-setup-order-audit.md` (audit findings)
- Driver patch (if any sites need fixing)
- Regression-test pass log at sysclk=350 confirming no behavior regression

#### Phase 1 exit criteria

- All call sites audited.
- All ordering violations (if any) fixed.
- Regression suite green at sysclk=350 MHz.

---

### Phase 1.5 — Inline-PASM block reordering (KB-verified root-cause hypothesis)

**Goal:** Fix the WYPIN-after-DIRH timing bug in the inline-PASM streamer block. This is a **correctness fix**, not an optimization, with a KB-verified mechanism that explains @macca's hp-dependent failure.

**Root cause (verified against `p2kbArchSmartPin00101TransitionOutput`):**

The `P_TRANSITION` smart pin starts its base-period counter as soon as DIR rises. New transitions begin only at the next base-period boundary *after Y is written* via WYPIN. In the current driver, setup instructions between DIRH and WYPIN push the WYPIN-execute time past the first base-period boundary when `hp ≤ 6`, so the first SCK edge arrives at `2·hp` ticks instead of the assumed `hp` ticks. The streamer (started at `align_delay = hp` after DIR-rise) then samples MISO before SCK has even started toggling.

| hp | First SCK transition under current driver | Expected | Phase error |
|---:|:---|:---|:---|
| 4 | tick 8 (boundary after WYPIN at tick 6) | tick 4 | +4 ticks (+1 full cycle late) |
| 5 | tick 10 | tick 5 | +5 ticks (+1 full cycle late) |
| 6 | tick 6 or 12 (race) | tick 6 | unstable |
| 7 | tick 7 | tick 7 | 0 (correct) |
| 8 | tick 8 | tick 8 | 0 (correct) |

This precisely matches the empirical pattern: @macca passes at hp=7 (sysclk=350) and fails at hp=5 (sysclk=250).

#### Phase 1.5 tasks

**1.5.1 Re-read the existing inline-PASM block**

`src/micro_sd_fat32_fs.spin2:5832-5841` (read path) and the analogous block in the write path (`writeSector` near `:6155`).

**1.5.2 Apply the fix to readSector**

Move setup instructions to *before* DIR-rise so DIRH and WYPIN are adjacent:

```spin2
ORG
        WRFAST    #0, p_buf                       ' Setup hub write FIFO (before DIR-rise; safe per @wuerfel_21 KB-verified)
        SETXFRQ   xfrq                            ' Set streamer NCO rate (before DIR-rise)
        FLTL      _sck                            ' Reset SCK smart pin (replaces DIRL+DRVL pair)
        DIRH      _sck                            ' DIR rises — internal counter starts cycling
        WYPIN     clk_count, _sck                 ' WYPIN immediately after DIRH (executes in 2 ticks)
        WAITX     align_delay                     ' Wait for first SCK rising edge
        XINIT     stream_mode, init_phase         ' Start streamer
        WAITXFI                                   ' Wait for completion
END
```

The substantive changes:
- `WRFAST` and `SETXFRQ` moved before `FLTL`/`DIRH`.
- `DIRL`+`DRVL` replaced with `FLTL`+`DIRH`.
- `WYPIN` is now immediately after `DIRH` — no instructions in between.

After this fix:
- DIR rises at tick 0; smart pin's base-period counter starts.
- WYPIN executes at tick 2 (2-tick instruction).
- For all hp ≥ 4, tick 2 < tick `hp`, so Y is written before the first base-period boundary.
- First SCK transition at tick `hp` for **every** hp value. Phase deviation = 0 sysclks.

**1.5.3 DEFERRED: writeSector analogous fix**

@evanh explicitly recommends *not* fixing the write-path RDFAST issue until the read-path fix is verified working. RDFAST has different (larger) timing variability than WRFAST and may need a different approach. **Don't touch the write path in Phase 1.5.** It will be a separate sprint after we have @macca's read-path verification.

**1.5.4 Test that the reordered block produces correct behavior on known-passing hardware**

At sysclk=350 MHz with the working 32GB card:
- The reordered block should produce identical good behavior (since hp=7 was already in the "correct" range under the old code).
- Run the regression suite. **All 464 tests must pass.**

**1.5.5 Test at sysclk=250 MHz with @macca's failing case (or our equivalent)**

If we have a card showing similar symptoms on our reference hardware, run mount + sector read. If the readSector fix alone resolves the failure, **we may not need Phases 2 and 3 to fix @macca's bug** — they become margin-improvement enhancements rather than required fixes.

This is exactly what we want to learn before deciding what test driver to ship to @macca.

#### Phase 1.5 deliverables

- Reordered inline-PASM block in `readSector`.
- No change to writeSector (deferred).
- Regression-suite pass log at sysclk=350.
- Empirical evidence at sysclk=250 (whether the fix alone resolves the failure or not).

#### Phase 1.5 exit criteria

- Build clean.
- Regression suite green at sysclk=350 MHz.
- Empirical result captured at sysclk=250 MHz: did the reorder alone fix the read failure?

#### What this changes for downstream phases

If Phase 1.5 alone resolves @macca's failure on our hardware:

- Phase 2 (adaptive `WXPIN[5]`) and Phase 3 (adaptive `align_delay`) become *margin-improvement* features, not bug fixes.
- The test driver shipped to @macca should still include all three so we can verify against his hardware and explore the design space.
- The default for `align_delay_offset` should be `0` (not `−2`), because the +hp phase shift was being absorbed by the `align_delay = hp` setting; with the reorder, geometric center is correctly placed at `align_delay = hp`.
- The default `WXPIN[5]` stays at on-edge for now; pre-edge becomes a sweep option rather than a default.

If Phase 1.5 *does not* resolve @macca's failure on our hardware:

- We still proceed with Phases 2 and 3 — they're independent margin improvements.
- The default `align_delay_offset` recommendation stays `−2` (provisional), with the sweep telling us the right value.

---

### Phase 2 — Adaptive `WXPIN[5]` for Path A (smart-pin direct)

**Goal:** Make MISO sample mode track `hp` so that as the bit cell narrows, we shift sampling earlier (toward leading edge) to maintain trailing-edge margin.

**Mechanism:** replace literal `%1_00111` (on-edge) at every WXPIN-on-MISO site with a computed value `miso_wxpin` that is derived from `hp` and runtime tuning state.

#### Phase 2 tasks

**2.1 Add driver state for the sample-mode computation.**

In the DAT section near `spi_period`:

```spin2
        miso_wxpin              LONG    %1_00111            ' Computed in applySPISpeed
        sample_mode_override    LONG    -1                  ' -1 = auto, 0 = pre-edge, 1 = on-edge
        pre_edge_threshold      LONG    6                   ' hp <= this -> pre-edge in auto mode
```

**2.2 Add the computation in `applySPISpeed`.**

After `spi_period := half_period` (~line 5335), add:

```spin2
  ' Compute MISO sample mode based on half-period
  CASE sample_mode_override
    0:        miso_wxpin := %0_00111                       ' pre-edge, forced
    1:        miso_wxpin := %1_00111                       ' on-edge, forced
    OTHER:                                                  ' -1 = auto
      IF half_period <= pre_edge_threshold
        miso_wxpin := %0_00111                             ' pre-edge for narrow cells
      ELSE
        miso_wxpin := %1_00111                             ' on-edge for wide cells
```

**2.3 Replace literal `%1_00111` at every MISO-WXPIN call site with `miso_wxpin`.**

Search:
```
grep -n 'WXPIN.*_miso.*%1_00111\|WXPIN.*miso.*%1_00111' src/micro_sd_fat32_fs.spin2
```

Expected sites (approximate line numbers from current source):
- `initSPIPins` (~5281): `WXPIN(miso, %1_00111)`
- `readSector` re-enable (~5855): `WXPIN(_miso, %1_00111)`
- Streamer-write MISO restore (~5978): `WXPIN(_miso, %1_00111)`

Each becomes `WXPIN(_miso, miso_wxpin)`.

**Important:** the literal `%1_00111` also appears on **MOSI** (e.g., `WXPIN(mosi, %1_00111)` at ~5270) — but this is the start-stop bit, not the sample-mode bit. Do NOT replace MOSI literals with `miso_wxpin`. Verify each site is the MISO pin before substituting.

**2.4 Add the public API methods.**

In the public-API section:

```spin2
PUB setSampleMode(mode)
  ' mode: -1 = auto-by-hp (default), 0 = pre-edge force, 1 = on-edge force
  IF mode < -1 OR mode > 1
    RETURN
  sample_mode_override := mode
  ' Force re-computation on next applySPISpeed; current pin keeps existing setting
  ' until next speed change. Document this behavior.

PUB setPreEdgeThreshold(hp_thresh)
  ' hp at or below which auto-mode chooses pre-edge.
  IF hp_thresh < 4 OR hp_thresh > 32
    RETURN
  pre_edge_threshold := hp_thresh

PUB getEffectiveSampleMode() : mode
  RETURN miso_wxpin    ' the actual value the smart pin is using

PUB getCurrentHp() : hp
  RETURN spi_period
```

**2.5 Optional: re-apply the MISO smart-pin configuration on `setSampleMode` change.**

Behavior decision: should `setSampleMode` take effect immediately (re-WRPIN the MISO pin) or on the next `applySPISpeed` call?

**Recommended:** re-apply immediately, so the test driver can sweep without an extra `applySPISpeed` between settings. Implementation:

```spin2
PUB setSampleMode(mode)
  IF mode < -1 OR mode > 1
    RETURN
  sample_mode_override := mode
  recompute_miso_wxpin()     ' helper that re-derives miso_wxpin from current hp
  WXPIN(miso_pin, miso_wxpin) ' apply immediately
```

#### Phase 2 deliverables

- DAT additions for `miso_wxpin`, `sample_mode_override`, `pre_edge_threshold`.
- Computation block in `applySPISpeed`.
- Replacements at every MISO-WXPIN site.
- Public API: `setSampleMode`, `setPreEdgeThreshold`, `getEffectiveSampleMode`, `getCurrentHp`.

#### Phase 2 exit criteria

- Build clean.
- At sysclk=350 MHz with default settings, regression suite passes (default behavior matches current driver).
- At sysclk=350 MHz with `setSampleMode(0)` (force pre-edge), basic mount + read test passes (pre-edge mode is functional, even if not the eventual default).

#### Phase 2 coverage caveat — Path A range limit

`WXPIN[5]` is a binary knob with two preset positions ~3 sysclks apart (pre-edge ≈ −1 sysclk, on-edge ≈ +2 sysclks). The host-side I/O ring round trip on Path A is comparable to Path B's: ~5-7 sysclks (`p2kbArchIoPinTiming`).

**Implication:** if the optimal sample position for Path A on a given card is more than ~3 sysclks away from either preset, **Phase 2 cannot fully compensate.** We can only choose the closer of two presets, leaving a residual offset.

If empirical results show:
- Path A passes for our card matrix with the binary knob → Phase 2 is sufficient. Done.
- Path A still fails on @macca's card after Phase 2 + Phase 1.5 + Phase 3 → the binary range is insufficient, and we have evidence-justifying the auxiliary phase-shifted clock pin (knob #21 in the inventory). That becomes a separate sprint with the pin cost justified by data.

This caveat is here so we don't over-promise. The sprint as currently scoped does **not** guarantee Path A coverage for all possible cards; it guarantees what `WXPIN[5]` can buy us, which is significant but bounded.

---

### Phase 3 — Adaptive `align_delay` for Path B (streamer DMA)

**Goal:** Make `align_delay` parameterizable so we can shift the streamer's first-sample position within the bit cell.

**Mechanism:** replace `align_delay := spi_period` (literal) with `align_delay := spi_period + align_delay_offset` at the streamer-burst sites, where `align_delay_offset` is a signed driver-state variable.

#### Phase 3 tasks

**3.1 Add driver state.**

In the DAT section:

```spin2
        align_delay_offset      LONG    0                   ' Default 0 (current align_delay = hp behavior)
                                                             ' Predicted optimum after Phase 1.5: +5 to +7
                                                             ' (host-side I/O ring round trip from
                                                             ' p2kbArchIoPinTiming: smart-pin output 1.5-3 sc
                                                             ' + registered input 3-4 sc)
                                                             ' Default of 0 chosen to preserve current behavior
                                                             ' until empirical sweep data confirms optimum.
                                                             ' Sweep test sets this via setAlignDelayOffset().
```

**Default reasoning:** the test driver ships with `align_delay_offset = 0` (preserves current `align_delay = hp` behavior pre-Phase-1.5) so that:

- (a) Existing regression tests at sysclk=350 MHz still pass byte-identically with default settings, providing a clean regression guard.
- (b) The sweep test starts with a known reference point and walks outward to find the actual optimum.
- (c) We do *not* commit to a guessed default that turns out to be wrong; the production default is set after empirical evidence.

The earlier sprint-plan-draft default of `−2` was based on the (since-superseded) hypothesis that the streamer path needed only the Path A on-edge pipeline canceled. After Claim C verification (`p2kbArchIoPinTiming`), we know `−2` would in fact land us *further* from the optimum (which is at positive offset), so it's been retracted as a default. See §3 ("Sweep prediction model") for the updated prediction.

**3.2 Replace `align_delay` computation at streamer sites.**

Search:
```
grep -n 'align_delay\s*:=\s*spi_period' src/micro_sd_fat32_fs.spin2
```

Expected sites:
- `readSector` (~5781): streamer-driven sector read.
- `writeSector` (~5927): streamer-driven sector write.

Each becomes:

```spin2
align_delay := spi_period + align_delay_offset             ' Steerable streamer phase
IF align_delay < 2                                          ' WAITX floor (cog needs 2 sc)
  align_delay := 2
```

The floor enforcement is critical at hp=4 with `align_delay_offset = −2`, which lands exactly at 2.

**3.3 Add public API.**

```spin2
PUB setAlignDelayOffset(offset)
  ' Signed integer. Default 0 (current behavior). -2 cancels the +2 bias.
  ' Range checked at use site (floor of 2 enforced).
  IF offset < -8 OR offset > 8
    RETURN                                                  ' Out of plausible range
  align_delay_offset := offset

PUB getEffectiveAlignDelay() : delay
  ' The value that will be used on the NEXT streamer transfer.
  delay := spi_period + align_delay_offset
  IF delay < 2
    delay := 2
```

**3.4 Document the path-B-only nature in the API doc.**

Add a comment block at `setAlignDelayOffset` explaining:
- This affects only streamer-driven 512-byte sector transfers (Path B).
- It does NOT affect single-byte transfers (commands, register reads, CRC bytes, etc.).
- For Path A, see `setSampleMode`.

#### Phase 3 deliverables

- DAT addition for `align_delay_offset`.
- Replacement at streamer-burst sites.
- Public API: `setAlignDelayOffset`, `getEffectiveAlignDelay`.
- Floor enforcement logic.

#### Phase 3 exit criteria

- Build clean.
- At sysclk=350 MHz with default `align_delay_offset = 0`, regression suite passes (default behavior matches current driver).
- At sysclk=350 MHz with `setAlignDelayOffset(-2)`, basic mount + sector read/write test passes (alternate align is functional).
- At sysclk=200 MHz with `setAlignDelayOffset(-2)`, floor logic engages cleanly (no underflow / no hang).

---

### Phase 4 — Sweep test driver

**Goal:** A test program that exercises both paths across a configurable knob grid and reports pass/fail with margin metrics.

This is a *test program* (in `diagnostic-tests/` or `src/EXAMPLES/`), not a change to the production driver. It uses the public API added in phases 2 and 3.

#### Phase 4 tasks

**4.1 Test program: `SD_phase_sweep_test.spin2`**

Located at `diagnostic-tests/SD_phase_sweep_test.spin2`. Outline:

```spin2
CON
    _CLKFREQ = 250_000_000                                   ' Configurable; default to failing case
    SD_CS = 60, SD_MOSI = 59, SD_MISO = 58, SD_SCK = 61

OBJ
    sd : "micro_sd_fat32_fs"

PUB go() | hp, mode, offset, total_pass, total_fail
    ' Init: mount card at default settings (the working ones, in case they're needed for setup)
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)

    debug("=== Phase Sweep Test ===")
    debug("sysclk=", udec(clkfreq), " hp=", udec(sd.getCurrentHp()))

    ' Sweep grid: every combination of sample_mode × align_delay_offset
    REPEAT mode FROM 0 TO 1                                   ' 0=pre-edge, 1=on-edge
      sd.setSampleMode(mode)
      REPEAT offset FROM -3 TO +8                             ' -3..+8 sysclks
                                                              ' Range justified by p2kbArchIoPinTiming:
                                                              ' host-side round-trip is ~5-6 sysclks
                                                              ' (smart-pin out 2-3 + registered input 3-4)
                                                              ' so optimum may live at +5 to +8
        sd.setAlignDelayOffset(offset)
        run_one_combination(mode, offset, @total_pass, @total_fail)

    debug("=== Final: ", udec_(total_pass), " pass, ", udec_(total_fail), " fail ===")
    debug("END_SESSION")

PRI run_one_combination(mode, offset, p_pass, p_fail) | result_a, result_b
    debug("--- mode=", udec_(mode), " offset=", sdec_(offset), " ---")

    result_a := test_path_a()                                 ' Single-byte path
    result_b := test_path_b()                                 ' Bulk streamer path

    debug("  Path A (sp_transfer_8): ", result_a == 0 ? @"PASS" : @"FAIL")
    debug("  Path B (streamer):      ", result_b == 0 ? @"PASS" : @"FAIL")

    IF result_a == 0 AND result_b == 0
      LONG[p_pass]++
    ELSE
      LONG[p_fail]++

PRI test_path_a() : status
    ' Exercise byte-by-byte path: read CSD, verify a known value
    ' Returns 0 on success, error code otherwise
    ...

PRI test_path_b() : status
    ' Exercise streamer path: read sector 0, verify known signature byte
    ' Or: write known pattern to scratch sector, read back, verify
    ' Returns 0 on success, error code otherwise
    ...
```

**4.2 What "test_path_a" exercises.**

Path A is used for command responses, register reads, CRC bytes — single-byte traffic. A clean test:
- Read CSD (known structure, known fields, can be validated against expected values without writing to the card).
- Read CID (same).
- For each register: dump bytes, verify checksum / expected fields.
- Failure modes: stuck bits, off-by-one byte shifts, total garbage.

**4.3 What "test_path_b" exercises.**

Path B is the streamer-DMA bulk path. A clean test:
- Read sector 0 (MBR) — verify `$55 $AA` signature at offset 510-511.
- Optionally: write a known pattern to a scratch sector outside the filesystem, read it back, verify CRC.
- Failure modes: sector signature missing, partial data, CRC mismatch.

**4.4 Output format**

Single-line-per-combination output for easy parsing:

```
sysclk=250_000_000 hp=5 mode=0 offset=-2 path_a=PASS path_b=PASS
sysclk=250_000_000 hp=5 mode=0 offset=-1 path_a=PASS path_b=FAIL
sysclk=250_000_000 hp=5 mode=1 offset=+0 path_a=FAIL path_b=PASS
```

This gives a 2 × 12 = 24-cell grid per sysclk (sample mode × align_delay_offset over `[−3, +8]`). Easy to plot, easy to diff between his hardware and ours.

**4.5 Margin measurement — passing-band width**

After the per-cell sweep, the test program post-processes the result table to compute, for each (card, sysclk, sample_mode), the **passing-band width**: the contiguous run of `align_delay_offset` values that all pass.

Algorithm:

```
For each row of fixed (sysclk, sample_mode):
    Find all offsets where path_b=PASS.
    Identify contiguous runs of passing offsets.
    For each run:
        record run_start, run_end, run_width = run_end - run_start + 1
        record run_center = (run_start + run_end) / 2
    The largest run is "the passing band."
```

Output:

```
=== Margin summary ===
sysclk=250 mode=0 (pre-edge): passing band [+3..+7], width=5, center=+5.0
sysclk=250 mode=1 (on-edge):  passing band [+4..+8], width=5, center=+6.0
sysclk=350 mode=1 (on-edge):  passing band [+4..+9], width=6, center=+6.5
```

Why band width matters:

- **Width = card valid-data window.** A wide band means the card's MISO is solidly valid for many sysclks; a narrow band means the card's window barely overlaps any single sample point.
- **Center = optimal align_delay_offset** for that card+sysclk+sample-mode combination.
- **Comparing widths between BEFORE-Phase-1.5 and AFTER:** a Phase 1.5 fix that increases the band width is improving margin in the truest sense (wider window, more tolerant to card variation).
- **Detecting model violations:** if the band has gaps (multiple plateaus), or the center is far from our prediction, the §3 falsification triggers fire and we know to investigate.

Implementation cost: ~30 lines of Spin2 post-processing on the result table. Negligible. **Required for the going-to-production decision** because we need to compare margin, not just pass/fail.

For Path A, the same band-width concept applies but the offset axis is just the binary `WXPIN[5]` choice, so the "band" is degenerate: it's either {0}, {1}, or {0, 1}. Still informative — if a card fails on both pre-edge and on-edge, that flags the binary range as insufficient (Phase 2 coverage caveat).

**4.6 Optional: also sweep sysclk**

A second variant (`SD_phase_sweep_sysclk.spin2`) that walks sysclk through the relevant boundary range (320, 310, 300, 295, 290, 280, 270, 260, 250 MHz) using `clkset()`, running the same knob grid at each sysclk. This is a bigger test (would take ~10s of seconds) but pinpoints the @macca threshold cleanly.

#### Phase 4 deliverables

- `diagnostic-tests/SD_phase_sweep_test.spin2` with the per-cell sweep and the margin-summary post-processing
- Optionally: `diagnostic-tests/SD_phase_sweep_sysclk.spin2`
- Documented expected output format with worked examples for matching against §3's predictions

---

## Cross-cutting concerns

### Default behavior preservation

Phases 2 and 3 must preserve current behavior when their knobs are at defaults. Concretely:

- `sample_mode_override = -1` (auto) AND `pre_edge_threshold = 6` AND `hp >= 7` → `miso_wxpin = %1_00111` (today's literal).
- `align_delay_offset = 0` → `align_delay = spi_period` (today's literal).

At sysclk=350 (hp=7), this means **both knobs at default produce identical bytes-on-the-wire to current driver.** This is the critical regression guard. The full regression suite must pass at sysclk=350 with default settings.

### Decision: pre-edge threshold at hp=6 vs hp=5

The default `pre_edge_threshold = 6` means hp=4, 5, 6 use pre-edge; hp=7+ uses on-edge. This *changes* behavior at sysclk=300 (hp=6), which currently works on most cards. Two options:

- **Option A: threshold = 5.** Only hp=4 and hp=5 use pre-edge in auto mode. sysclk=300 (hp=6) keeps current on-edge behavior. Smaller change, lower risk.
- **Option B: threshold = 6.** As above. More aggressive, may give better margin at sysclk=255–300 range.

**Default for the test driver: threshold = 5.** Conservative initial setting; the sweep test will tell us if 6 is justified.

### What "pass" means in the sweep test

For Path A (CSD read): all 16 bytes match the expected pattern derived from the CID/CSD register specification, including the CRC field. CRC validates the entire byte stream — any single-bit shift fails CRC.

For Path B (sector 0 read): sector signature `$55 $AA` at offsets 510-511. Optional: also CRC-validate the entire sector if the driver's CRC validation is enabled.

For sweep purposes, **"pass" means the read returned the expected data with no error code**. This is the same standard the driver uses internally; using it in the test ensures the test detects exactly the failures the driver detects.

### What we do NOT do in this sprint

- **No streamer NCO `init_phase` adjustment.** That's a second knob on Path B with the same effect as `align_delay`. Sticking to one knob per path keeps the sweep grid tractable.
- **No drive-strength adjustment in code.** Step 4 is a separate hardware exercise.
- **No `P_INVERT_B` exploration.** Mode-incompatible alone, no value here.
- **No auxiliary phase-shifted clock pin.** Excluded by customer pin budget.
- **No CSD-driven adaptive logic.** Out of scope until we have empirical evidence that knobs #15 + #20 are sufficient or insufficient.

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Phase 1 audit reveals a long-standing setup-order bug that affected previous tests | medium | might invalidate some past test results | document carefully; re-run regression suite after fix |
| `setSampleMode(0)` on hp=7 breaks something we hadn't anticipated | low-medium | regression at sysclk=350 | test pre-edge at sysclk=350 explicitly before shipping to @macca |
| `align_delay = 2` (floor at hp=4) causes streamer to mis-align | low | sysclk≤200 MHz tests fail | floor handling tested explicitly at sysclk=200 |
| Sweep test takes too long to run interactively | medium | @macca's testing experience suffers | keep grid small (2 × 7 = 14 cells); single sysclk variant is fast |
| `setSampleMode` immediate re-WRPIN at runtime corrupts an in-progress transfer | medium | sweep test produces noise | only call `setSampleMode` between transfers; document the constraint |
| @macca's hardware doesn't reproduce the failing case in our test rig | low | can't validate fix on his card | request CSD dump from him so we can model the card timing predictively |

---

## Sequencing and time estimates

This is a quality-driven plan, not a deadline-driven one (per CLAUDE.md: "WE ARE NOT TIME CONSTRAINED"). Estimates are for sequencing only.

| Phase | Approximate effort | Gating dependencies |
|---|---|---|
| S.1 — `_CLKFREQ` typo fix | trivial | none (independent commit) |
| S.3 — `debugOnClockChange()` API | 1 sitting | none |
| S.4 — Update freq-sweep test to use S.3 | trivial | S.3 done |
| 1 — Audit | 1 sitting | none |
| 1.5 — Inline-PASM reorder | 1 sitting | phase 1 done |
| 2 — Adaptive WXPIN[5] | 1 sitting | phase 1 done |
| 3 — Adaptive align_delay | 1 sitting | phase 1 done; phase 2 not strictly required but co-ordinated |
| 4 — Sweep test program | 1 sitting | phases 2 and 3 done |

After all phases land we have: updated driver + new freq-sweep test + Phase-4 sweep test program, all compiled clean, ready for hardware verification.

---

## Top-level testing methodology (Steps 1–4)

This is the full end-to-end verification arc, executed in order:

### Step 1 — Frequency-sweep test certification (pre-driver-fix)

**Purpose:** prove the freq-sweep diagnostic tool works correctly on healthy hardware before we use it to evaluate the driver fix.

**What runs:** the corrected freq-sweep test program (S.4) using the new `debugOnClockChange()` API (S.3). Driver compiled with `SD_INCLUDE_DEBUG` defined. Phase 1.5 / 2 / 3 fixes **not yet applied**.

**Success criterion:** **on a working card, all three modes produce identical pass/fail signal at every tested frequency.** Specifically: Mode A 17/17 PASS, Mode B 17/17 PASS, Mode C 17/17 PASS. If any mode diverges from the others on a working card, the diagnostic infrastructure has a flaw and Step 1 is not complete.

This step is **independent of the driver phase-margin fixes**. It validates the test *tool*, not the driver behavior we plan to change.

**Failure handling:** if Mode C fails where Mode A/B passed, investigate whether `debugOnClockChange()` is recomputing the right state. Likely candidates: missed a recompute, wrong target SPI rate cache, missed a smart-pin re-apply.

### Step 2 — Apply driver phase-margin fixes (Phases 1, 1.5, 2, 3)

**Purpose:** apply all four phases of the phase-margin work to the driver.

**What runs:** Phase 1 audit + fixes if any, Phase 1.5 inline-PASM reorder, Phase 2 adaptive `WXPIN[5]`, Phase 3 adaptive `align_delay`. Plus Phase 4 sweep test program built.

**Success criterion:** clean compile of driver + examples + regression test files + Phase 4 sweep test + S.3/S.4 freq-sweep updates. No regressions in the build.

### Step 3 — Full regression test suite on hardware

**Purpose:** validate that the driver fixes don't regress any of the existing 464 regression tests at sysclk=350 MHz.

**What runs:** `tools/run_test.sh` against every `src/regression-tests/SD_RT_*.spin2` file. Run on Stephen's reference hardware externally (container cannot execute hardware tests).

**Success criterion:** all 464 tests pass. **Zero tolerance** per CLAUDE.md ("Every test suite must pass 100% at all times.")

**Failure handling:** if any test regresses, do not proceed to Step 4. Diagnose and fix; the regression points at something in the four phases that broke an established invariant.

### Step 4 — Package and release to @macca

**Purpose:** get @macca's specific 1GB SDSC failure case validated against the new driver.

**What runs:**
- Test driver binary (or source).
- Phase 4 sweep test program (`SD_phase_sweep_test.spin2`) — exercises the new runtime knobs across the parameter grid.
- Updated freq-sweep test (`SD_frequency_characterize.spin2`) — three modes A/B/C across the freq range.
- Brief README explaining how to run each, what output to capture.
- Request: run `SD_card_characterize.spin2` on his 1GB SDSC and send us the full output (raw CSD bytes + decoded TAAC/NSAC).

**Success criterion (for @macca's specific failure):** at sysclk=250 MHz, the 1GB SDSC mounts and reads sectors correctly with at least one combination of (sample mode, align_delay_offset) in the sweep grid.

**Decision branches** (driven by Phase 4 sweep results across his cards and ours): see "Going-to-production criteria" below.

---

## Going-to-production criteria (post-sweep)

After @macca and we both run the sweep, we have data on which `(mode, offset)` combinations pass on which cards on which sysclks, plus margin-band widths from the §4.5 post-processing. Decision tree:

### Branch 1 — Phase 1.5 alone resolves @macca's failure

Detection: at sysclk=250 with `align_delay_offset = 0` (driver's default behavior post-Phase-1.5 reorder), Path B passes on the 1GB card.

Action: Phase 2 and Phase 3 are no-cost margin enhancements; we still ship them but with the knobs at their conservative defaults (`align_delay_offset = 0`, `sample_mode = auto-by-hp` with `pre_edge_threshold = 5`). The test driver remains useful for future card-margin investigations.

### Branch 2 — Phase 1.5 + Phase 3 (positive `align_delay_offset`) needed for @macca

Detection: sysclk=250 with `align_delay_offset = 0` still fails on the 1GB card, but a positive offset (within the predicted +5 to +7 band, modulo card t_OD) passes.

Action:
- Set the production default `align_delay_offset` to the **best single value that passes all tested cards at all tested sysclks**. The §4.5 margin summary points at the right number: pick the offset that maximizes the *minimum* band-width across all tested (card, sysclk) pairs.
- If that single value gives a wide passing band on every card, we're done with a fixed default — no card-adaptive logic needed.
- If different cards converge on subtly different optima but all still pass at a single compromise value, ship the compromise value with a note that adaptive tuning is a future option.

### Branch 3 — Phase 1.5 helps but doesn't fully resolve @macca

Detection: at sysclk=250 with **any** `align_delay_offset` in the swept range, Path B still fails on the 1GB card. The reorder fixed something but exposed a deeper issue.

Action:
- Examine the §3 falsification triggers: did the bathtub curve come out as predicted, or did it look anomalous (no plateau, multiple plateaus, etc.)?
- If the prediction was right but no offset works, the card's valid-data window is genuinely narrower than our sample-point precision allows. Possible next steps:
  - Try a slower SCK target (e.g., 12.5 MHz instead of 25 MHz at sysclk=250). This widens the bit cell, possibly enough to fit the card's timing.
  - Read the card's CSD and confirm whether its declared timing is exceptional. If yes, this card is a legitimate edge case and a slower-SCK fallback may be warranted (`setMaxSPISpeed` API tweak).
- If the prediction was wrong, our model is missing something. Stop and investigate — don't ship until we understand what.

### Branch 4 — Different cards prefer noticeably different `(mode, offset)`

Detection: each card has a clear passing band, but the band centers differ by more than ~2 sysclks across cards.

Action: this is the trigger for **CSD-driven adaptive defaults**. Read CSD on every mount, compute predicted optimum from TAAC/NSAC, set `align_delay_offset` accordingly. The mechanism is straightforward; the justification is now empirical, not speculative.

### Branch 5 — No combination passes the failing case

Detection: even with margin-summary post-processing, the 1GB card has no passing offset at sysclk=250 in any sample mode.

Action: the binary `WXPIN[5]` knob and the continuous `align_delay_offset` knob together aren't enough for this card. This is the trigger for revisiting **knob #21 (auxiliary phase-shifted clock pin)** with empirical justification for the pin cost. Separate sprint.

### Cross-branch: Path A coverage

For each branch, separately evaluate Path A's pass/fail on the 1GB card:

- If Path A passes at the production default after Phase 1.5 + Phase 2 → Path A is covered.
- If Path A still fails → Phase 2's binary range is insufficient; same Branch 5 trigger applies for Path A specifically. Knob #21 becomes the candidate fix, isolated to the read-side smart pin's clock input.

---

## Side-fix items (bundled with this sprint's commits)

These are small items uncovered during the analysis, not part of the four-phase margin work but small enough to commit alongside.

### S.1 — Fix `SD_frequency_characterize.spin2` `_CLKFREQ` typo

**Issue:** the test source ships with `_CLKFREQ = 270_000_000` while its header strings reference 320 MHz (mismatch noticed by @macca, recorded in his user-report Part 6.1).

**Fix:** change `_CLKFREQ = 270_000_000` to `_CLKFREQ = 320_000_000` to match the test's stated baseline.

**Verification:** rebuild; the header should still say "Initial mount at 320 MHz..." and now actually run at 320 MHz.

**Bundling:** include in the same commit set as the driver changes — small enough not to warrant a separate commit, large enough that we shouldn't lose it.

### S.2 — Card-register dump tool — use existing `SD_card_characterize.spin2`

**Audit finding:** the existing `src/UTILS/SD_card_characterize.spin2` (1225 lines) already prints:
- Raw CSD bytes (16-byte hex dump, line 818)
- Decoded TAAC + NSAC ([USED] markers, lines 573-574)
- Decoded TRAN_SPEED, CCC, READ_BL_LEN, all CSD fields with their bit positions
- Raw CID, SCR, SDStatus registers and their decoded fields

**No new code needed.** The smaller `SD_card_identify.spin2` (which @macca ran) was the wrong tool — it produces only the short summary `L1`/`L2`.

**Action:** update test-driver release packaging instructions (next section) to ask @macca to run `SD_card_characterize.spin2` for the full register dump, not `SD_card_identify.spin2`.

### S.3 — Diagnostic-only `debugOnClockChange()` API for marginal-card triage

**Motivation:** the freq-sweep test (corrected by remote agent) revealed that running three test modes — Mode A (boot at sysclk, fresh mount), Mode B (clkset + unmount + remount), Mode C (clkset without remount) — produces **diagnostically different signals** when investigating marginal cards:

- All three FAIL → card-side issue (intrinsic timing of that card at that sysclk).
- Mode A FAIL, Mode B PASS → init sequence at this sysclk corrupts state; re-init from a different sysclk fixes it (host init-side).
- Mode A PASS, Mode B PASS, Mode C FAIL → card+host init are fine; host-side runtime timing (steady-state SCK/streamer phase) is the bug.
- All three PASS → card and host work cleanly at this sysclk; failure must be elsewhere.

Without an `onClockChange()` API, Mode C cannot be tested cleanly — the driver's `spi_period`, `idle_flush_clocks`, and `ct_tick_clocks` are stale after a runtime `clkset()`, and the test is forced into "stale-state" behavior that's indistinguishable from a host-runtime-timing bug. Mode C with a proper `onClockChange()` call recomputes those host-side state values without re-initializing the card, isolating the host-side runtime timing as a clean test variable.

**Production scope:** this API is **not** for production use. Production applications pick a sysclk at design time and stay there. The constraint "after `clkset()`, unmount and re-mount" remains the documented production guidance.

**Conditional compile flag:** `SD_INCLUDE_DEBUG`. This is the same flag that already gates other diagnostic methods (`debugGetRootSec`, `debugReadSectorSlow`, `debugClearRootDir`, CRC getters, etc.) per the section comment "---- Debug / Diagnostics [SD_INCLUDE_DEBUG] ----" at line 1835 of the driver. We reuse this flag rather than adding a new one — it matches existing conventions and keeps the public API surface unchanged.

**API signature:**

```spin2
#ifdef SD_INCLUDE_DEBUG

PUB debugOnClockChange() : status
'' DIAGNOSTIC ONLY: Recompute host-side sysclk-dependent state after a
'' caller-initiated clkset(). Use only when investigating sysclk-dependent
'' card behavior (e.g., the three-mode test pattern in
'' diagnostic-tests/SD_frequency_characterize.spin2).
''
'' Production applications must NOT call this. Production guidance after
'' a clkset() is to unmount() and mount() again. Calling this method in
'' production constitutes undefined behavior.
''
'' Caller is responsible for ensuring no SD operation is in flight at the
'' time of the call. The worker cog's command mailbox is checked; if a
'' command is mid-dispatch, this method returns E_BAD_RESPONSE without
'' modifying state.
''
'' Recomputes:
''   - spi_period (smart-pin half-period, derived from new clkfreq)
''   - WXPIN(sck, spi_period) so the smart pin uses the new period
''   - idle_flush_clocks (auto-flush threshold in new sysclks)
''   - ct_tick_clocks (clock-tick threshold in new sysclks)
''
'' Does NOT re-initialize the card. The card's internal state (CMD0/CMD8/
'' ACMD41/CMD58 results) is preserved across the call. Card register
'' caches (CID/CSD/SCR) are also preserved.
''
'' @returns status - 0 on success, E_BAD_RESPONSE if a command is in flight

#endif
```

**Implementation requirements:**

- Lives in the `#ifdef SD_INCLUDE_DEBUG` section near the existing `debug*` methods.
- Validates `pb_cmd == CMD_NONE` before modifying state; returns `E_BAD_RESPONSE` if the worker is busy.
- Does not require the worker cog's participation (it's a host-state recompute, not a card operation), so it does not go through the mailbox.
- Calls a new private helper `recompute_clock_dependent_state()` that:
  - Computes `spi_period := (clkfreq + (target_speed * 2) - 1) / (target_speed * 2)` (same formula as `applySPISpeed`).
  - Calls `WXPIN(sck, spi_period)`.
  - Recomputes `idle_flush_clocks := (clkfreq / 1000) * IDLE_FLUSH_MS`.
  - Recomputes `ct_tick_clocks := clkfreq * CT_TICK_SECONDS`.
- Caches the most recently applied target SPI speed in a new DAT variable (`current_spi_target_hz`) so we know what target to recompute against. Set this in `applySPISpeed` whenever called.

**Validation:**

- Verify the existing regression suite passes with `SD_INCLUDE_DEBUG` defined and undefined.
- Add a small diagnostic test that boots at one sysclk, calls `clkset()` to a different sysclk, calls `debugOnClockChange()`, and verifies a sector read passes against the expected pattern. Place under `diagnostic-tests/` (not regression).

### S.4 — Update `SD_frequency_characterize.spin2` to use `debugOnClockChange()` in Mode C

**Motivation:** the corrected three-mode freq-sweep test (per remote agent results recorded in user reports) currently has Mode C running with stale driver state. Once `debugOnClockChange()` is in the driver, update the test to call it in Mode C so that Mode C tests *only* host-side runtime timing in isolation.

**Required changes to `SD_frequency_characterize.spin2`:**

- After `clkset(target_freq)` in the Mode C path, immediately call `sd.debugOnClockChange()` and check the return status. If non-zero, abort that frequency's Mode C test and log a diagnostic message.
- Update the Mode C banner / documentation comment in the test source to note that the test now exercises host-side runtime timing in isolation, and that `debugOnClockChange()` is required for the test to be meaningful.
- Verify (post-driver-fix) that all three modes produce the *same* per-frequency pass/fail signal on a working card — divergence between modes A/B/C is what we want for marginal-card triage, but on healthy cards they should all be identical.

**Bundle with:** the same commit that adds the `debugOnClockChange()` API.

**Expected post-fix outcome (working cards):** Mode A 17/17 PASS, Mode B 17/17 PASS, Mode C 17/17 PASS. Any divergence in Mode C after this becomes a real diagnostic signal, not test artifact.

---

## Auxiliary post-implementation track — frequency-sweep tool investigation

**Tracked separately from the main four phases but executed after they pass regression.**

### Background

@macca reported that `diagnostic-tests/SD_frequency_characterize.spin2`, which uses runtime `clkset()` to walk through sysclk values, **hangs inside `clkset()`** after the first sweep step. Recorded in his user-report Part 6.2. Confirmed with both Spin Tools and pnut-ts compilers.

This is a regression — the frequency-sweep tool worked in the past. Some change to either the driver or the test program has broken the runtime sysclk-change mechanism. We do not currently know which.

### Hypotheses

- **H1 (most likely if Phase 1.5 fixes it):** the inline-PASM phase-shift bug (Claim B in `2026-05-04-evanh-streamer-stability-feedback.md`) puts the driver's worker cog in a degenerate timing state during `applySPISpeed`, and the subsequent `clkset()` hangs because of that. If true, Phase 1.5 incidentally resolves the frequency-sweep tool too.
- **H2:** some other clock-dependent state in the driver's worker cog (mailbox `WAITATN` timing, smart-pin period state, streamer NCO state) doesn't survive a `clkset()` from underneath it. Independent of Phase 1.5; would need a separate fix.
- **H3:** the regression is in the test program itself, not the driver — perhaps a Spin2 language-version or compiler-evolution issue.

### Investigation sequencing (option B per Stephen's choice)

After the four-phase driver work passes regression on hardware, run the frequency-sweep tool with the new driver. Three outcomes:

1. **Tool works** → Phase 1.5 incidentally fixed it (H1 confirmed). Document and close the auxiliary investigation.
2. **Tool still hangs at the same point** → it's not the inline-PASM bug. H2 or H3. Investigate further. Likely steps:
   - Add debug output around `clkset()` to identify exactly where the hang occurs (before clkset / inside clkset / after clkset).
   - Check whether the driver's worker cog needs an explicit `reInit()` API that re-derives smart-pin period from the new sysclk.
   - Check git history for changes to either the driver's clock-dependent state or `clkset()` usage in the sweep tool.
3. **Tool partially works (some sysclks succeed, others hang)** → mixed outcome; pin down which sysclks fail and look for a pattern (is it the same hp-threshold pattern as the inline-PASM bug, or a different one?).

### Why this lives outside the main sprint

- Doing investigation **before** the driver fix gives ambiguous data (we'd be debugging on top of a known bug).
- Doing it **after** gives clean data on whether the runtime sysclk-change machinery is independently broken.
- We deliver value to @macca first (working driver against his fixed sysclk), then improve our own test infrastructure separately.

### Deliverable

A short investigation document (likely `DOCs/Analysis/<date>-frequency-sweep-clkset-investigation.md`) summarizing what we found and any fix applied, plus a regression test that exercises `clkset()` on the SD driver's worker cog if we find a fix worth permanizing.

---

## Test driver release packaging

What we send @macca:

1. The test driver `.binary` (or `.spin2` source if he prefers to build).
2. A short README explaining:
   - How to run the sweep test
   - What each combination is testing
   - What output to capture
   - How to report results (preferred format: pasted log + brief description of any anomalies)
3. The current analysis document (`2026-05-04-spi-clock-divisor-margin-table.md`) for context, in case he wants to dig in.
4. A request for the CSD register dump from `SD_card_identify.spin2` if he hasn't already provided it — this lets us model the card's declared timing predictively.

---

## Open questions for Stephen

1. **Pre-edge threshold default.** Threshold=5 (conservative) or threshold=6 (aggressive)? My recommendation is 5 for the test driver, with the sweep telling us if 6 is justified.
2. **Sweep test sysclk.** Single sysclk (250 MHz, the failing case) or multi-sysclk (sweep through the boundary)? Multi gives more data but takes longer to run and analyze.
3. **Path B sweep test data.** Read sector 0 only (safe, read-only) or write-then-read a scratch sector (more complete coverage but writes to the card)? Recommend read-only to minimize risk to @macca's card.
4. **Phase 1 audit format.** Standalone audit document, or fold findings into the main analysis doc as another appendix? Recommend standalone — it's a code-level audit document, distinct from the algorithm analysis.
5. **Public API stability.** The runtime knobs (`setSampleMode`, etc.) — are these test-only (to be removed before production) or are we comfortable with them being permanent public API even if we ship a single tested default? Recommend test-only for now; revisit after sweep results.
