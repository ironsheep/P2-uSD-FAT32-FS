# SPI Phase-Margin Diagnostic API

**Part of:** P2-uSD-FAT32-FS driver, v1.7.0
**Audience:** Driver maintainers and authors of diagnostic tools

> **All methods documented here are DIAGNOSTIC ONLY**, gated behind `#ifdef SD_INCLUDE_DEBUG`. Production applications must NOT call them. The driver internally computes the right phase-margin tuning based on hp; these knobs exist only to let diagnostic tools walk the parameter grid for marginal-card triage. The runtime knobs are subject to change without notice as the production driver bakes in the right defaults from empirical sweep data.

---

## Architectural background

The driver internally uses two distinct mechanisms to read MISO from the SD card:

- **Path A — smart-pin direct (`sp_transfer_8`):** every single-byte transfer (command responses, register reads, CRC bytes, start-token polling). Sample mode is controlled by the MISO smart pin's `WXPIN[5]` bit, computed inside `applySPISpeed` as a function of half-period.
- **Path B — streamer DMA (`STREAM_RX_BASE`):** every 512-byte sector transfer. Sample timing is controlled by `align_delay`, the cog `WAITX` between starting SCK and starting the streamer.

Cards with tight timing margins (notably old SDSC cards with long `t_OD`) may need the host-side sample point to be tuned away from the driver's defaults. The driver's *internal* logic adapts based on hp; the diagnostic API below lets diagnostic tooling probe the design space at runtime without recompiling.

**At default settings** the driver writes the same bytes to the smart pins as it did pre-Phase-2/3 at sysclk=350 MHz, so existing applications need no changes.

---

## How to use these methods

To call any of these methods from a consumer file, the consumer must export the diagnostic flag *before* the OBJ declaration:

```spin2
#pragma exportdef SD_INCLUDE_DEBUG          ' or #pragma exportdef SD_INCLUDE_ALL

OBJ
    sd : "micro_sd_fat32_fs"
```

Without that pragma, calling any `debug*` method here produces a compile error. This is intentional — it prevents accidental production use.

---

## Path A diagnostic APIs (smart-pin direct)

### `debugSetSampleMode(mode)`

Force MISO sample mode for the smart-pin direct path.

| Mode | Effect |
|---|---|
| `-1` | Auto-by-hp (default): pre-edge for hp ≤ `pre_edge_threshold`, on-edge otherwise |
| `0` | Force pre-edge (`%0_00111`): sample ~1 sysclk before SCK rising edge |
| `1` | Force on-edge (`%1_00111`): sample ~2 sysclks past SCK rising edge |

Out-of-range values are silently ignored. The change re-applies `WXPIN` to MISO immediately so subsequent transfers use the new value.

### `debugSetPreEdgeThreshold(hp_thresh)`

Set the half-period threshold for auto mode. When `debugSetSampleMode(-1)` is in effect (default), `hp ≤ hp_thresh` selects pre-edge and `hp > hp_thresh` selects on-edge. Default 5: only hp=4 and hp=5 use pre-edge, hp ≥ 6 uses on-edge. Range 4..32; out-of-range silently ignored.

### `debugGetEffectiveSampleMode() : mode`

Returns the actual `WXPIN[5]`-bit value currently in use on the MISO pin (`%1_00111` for on-edge, `%0_00111` for pre-edge).

### `debugGetCurrentHp() : hp`

Returns the current SPI half-period in sysclks (the value the SCK `P_TRANSITION` smart pin uses for its base period). Equals the driver's internal `spi_period`.

---

## Path B diagnostic APIs (streamer DMA)

### `debugSetAlignDelayOffset(offset)`

Set the signed integer offset added to `spi_period` (= hp) when computing the streamer's `align_delay` (the `WAITX` count before `XINIT`).

- **Default +5** (changed from 0 in v1.7.1). Chosen from measurement, not prediction: five independent passing-band sweeps — two card families, both sockets, three frequencies — **all centred on +5**. The narrowest measured band was `[+1..+9]` at 35 MHz. The old default of 0 sat on or outside the lower edge at elevated frequencies.
- **Corroborated by `p2kbArchIoPinTiming`:** the host-side I/O ring round trip is 5-6 sysclks (smart-pin output 1.5-3 + registered input 3-4), predicting an optimum at +5 to +7. The measurement landed inside the prediction.
- **The hp=4 floor cell is exempt** — positive offsets are withheld there and the historical `align_delay = hp` applies instead. See `debugGetEffectiveAlignDelay` below for why.
- **Floor:** `align_delay` is clamped to ≥ 2 (cog needs 2 sysclks to execute `WAITX` before `XINIT`).
- **Range:** caller may pass `[-8, +16]`; out-of-range silently ignored. The upper limit covers one full bit period (`2*hp` = 14 at the production hp=7) so a sweep can find the band's upper edge — the earlier `+8` limit left the band top unmeasured.

Affects ONLY streamer-driven 512-byte sector transfers (Path B). Does NOT affect single-byte transfers — for Path A see `debugSetSampleMode`.

### `debugGetEffectiveAlignDelay() : delay`

Returns the streamer-DMA `align_delay` value that will be used on the next streamer-driven sector transfer — the shared computation, including the floor-cell rule and the `WAITX` minimum of 2.

**The hp=4 floor-cell rule.** At `spi_period = 4`, positive offsets are *not* applied; that cell keeps the historical `align_delay = hp`. The passing bands were measured at hp 5..7 only, and at hp=4 the default +5 exceeds the whole bit period (`2*hp` = 8 sysclks) — it was measured breaking the CMD6 high-speed verify read. Negative (diagnostic) offsets still apply. hp=4 arises at the 50 MHz high-speed request and at low-sysclk 25 MHz configurations (e.g. 200 MHz sysclk); both keep their long-certified alignment until that cell is characterized.

> **The floor-cell rule is load-bearing, and measurement proved it (2026-08-19).**
> An earlier sweep found a band of `[+2..+8]` centred +5 at hp=4 and was read as
> evidence the rule could be dropped. That sweep reached 43.75 MHz by *setting* the
> clock, which leaves the card in default speed mode driven above spec — not the
> state hp=4 ships in. Measured **inside verified high-speed mode**, the band moves
> down by three:
>
> | Card | Band | Centre | offset 0 (the rule) | offset +5 (the default) |
> |---|---|---|---|---|
> | Samsung `$4AC8_5F42` | `[-3..+4]` | 0 | dead centre | **outside** |
> | Lexar `$3354_9024` | `[-3..+4]` | 0 | dead centre | **outside** |
> | PNY `$01CD_5CF5` | `[-1..+5]` | +2 | inside | upper edge |
>
> The rule keeps `align = hp`, i.e. offset 0 — inside the band on all three cards
> and dead centre on two, while the shipped +5 is excluded outright on two. It is
> **the correct value at hp=4, not a conservative placeholder**. An independent
> confirmation arrived by accident: an instrument that lifted the rule *before*
> negotiating put `align = hp + 5` on the CMD6 verify read, and that verify failed
> on the Lexar — the driver correctly refusing a mode it could not verify.

### `debugSetTxAlignDelay(pad)`

Set the `WAITX` phase pad used between the SCK counter reset and `XINIT` at both **write-path** streamer sites (`writeSector` and `writeSectors`). This is the shmoo knob for the layout-invariance fix: with `RDFAST` hoisted out of the phase-critical window, the MOSI-bitstream-to-SCK-edge phase is a build-independent constant, and this pad centers it in the passing window. The characterized default is baked into the driver's DAT (`tx_align_delay`).

- **Floor:** clamped to ≥ 2 at the use site (`WAITX` minimum).
- **Range:** `[2, 2 + 2*hp]` covers one full SCK period of phase; larger values wrap the same phases.

Affects ONLY write-path streamer bursts. The read path's phase pad remains `align_delay` (see `debugSetAlignDelayOffset`).

### `debugGetTxAlignDelay() : pad`

Returns the configured `tx_align_delay` value (before the use-site floor clamp).

---

## Guard-lifting APIs (v1.7.1)

Two production guards exist because measurement found real hazards behind them.
Both can be lifted — but only by a characterization tool that knows what it is
re-enabling. **Production applications must not call either.**

### `debugSetOverspeedAllowed(enabled)`

Allows `setSPISpeed()` targets above the production ceiling (the card's declared
`TRAN_SPEED`, capped at the SD SPI-mode 25 MHz; 50 MHz while verified high-speed
mode is active).

The bound exists because the socket-timing campaign measured **silent
whole-sector write corruption** above spec: the `tx_align_delay` losing phase
moves with hp, and the shipped default lands on it at hp=5 / 35 MHz. Nothing at
or below the ceiling can reach that configuration. Lifting the bound puts it back
in reach — which is the point when you are mapping it, and a defect the rest of
the time.

Zero restores the bound. The socket shmoo, write probe and phase sweep all call
this.

### `debugSetAlignFloorRuleEnabled(enabled)`

Enables (default) or disables the hp=4 floor-cell rule described under
`debugGetEffectiveAlignDelay`.

The rule makes the floor cell **unmeasurable** as a side effect of making it
safe: with positive offsets withheld, every positive offset collapses to the same
effective `align_delay`, so a sweep there returns a flat, meaningless grid. Pass
zero to lift the rule and actually measure the band.

Disabling it re-enables the configuration that broke the CMD6 high-speed verify
read during v1.7.1 certification. That is the intent — a sweep is looking for
where the edges are — but nothing outside a characterization run belongs here.

---

## Runtime sysclk recompute

### `debugOnClockChange() : status`

Recomputes host-side sysclk-dependent state after a caller-initiated `clkset()` without re-initializing the card:

- `spi_period` (smart-pin half-period, derived from new `clkfreq`)
- `WXPIN(sck, spi_period)` so the smart pin uses the new period
- `miso_wxpin` (sample mode reflects new hp)
- `WXPIN(miso, miso_wxpin)` so MISO uses the new sample mode
- `idle_flush_clocks` (auto-flush threshold in new sysclks)
- `ct_tick_clocks` (clock-tick threshold in new sysclks)

Does NOT re-initialize the card. The card's internal state and register caches are preserved.

The worker cog must be idle (`pb_cmd == CMD_NONE`) when this is called. If the worker is busy, returns `E_BAD_RESPONSE` without modifying state.

Used by `diagnostic-tests/SD_frequency_characterize.spin2` Mode C to isolate host-side runtime timing from card-init state for marginal-card triage.

**Production guidance after a `clkset()`:** call `unmount()` then `mount()` again. Do not call `debugOnClockChange()` in production.

---

## Diagnostic workflow — sweep tuning a card

```spin2
#pragma exportdef SD_INCLUDE_ALL                ' enables the debug* APIs

OBJ
    sd : "micro_sd_fat32_fs"

PUB go() | result
    sd.mount(SD_CS, SD_MOSI, SD_MISO, SD_SCK)

    ' Try the failing combination at sysclk=250 MHz first
    sd.debugSetSampleMode(1)                    ' on-edge
    sd.debugSetAlignDelayOffset(0)              ' default
    result := test_path_b()                     ' read sector 0, check signature

    ' Walk to the predicted optimum
    sd.debugSetAlignDelayOffset(5)              ' predicted host-side latency
    result := test_path_b()
```

For full per-cell + margin-summary output, see `diagnostic-tests/SD_phase_sweep_test.spin2`, which walks the 2 × 12 grid (mode × offset) and reports the largest contiguous passing-band per mode.

---

## Default behavior summary

At default settings (consumer does NOT export `SD_INCLUDE_DEBUG`, or does export it but does not call any `debug*` setters):

- Path A: MISO `WXPIN[5]` auto-by-hp with threshold=5 → on-edge for hp ≥ 6, pre-edge for hp ≤ 5
- Path B reads: `align_delay = spi_period + 5` (offset=+5, the measured band centre) — **except at hp=4**, where the floor-cell rule keeps `align_delay = spi_period`
- Path B writes: `tx_align_delay = 4` — **characterized, not a floor value.** See below.

These defaults are validated against the regression suite (530/530 at 350 MHz sysclk on the certification card, and 532/532 on a second 119GB / 64-sectors-per-cluster geometry). Note that the read offset default changed in v1.7.1 from 0 to +5, so byte-on-the-wire output is **no longer identical** to pre-Phase-2/3 behaviour — that equivalence was a v1.7.0 property, deliberately given up in exchange for centring the read alignment on its measured band. The production driver does not expose any tunable surface for these — the right values are hardcoded internally.

### The write-path pad was characterized on the bench (v1.7.0, 2026-08-11)

`tx_align_delay` shipped at 2 — the bare `WAITX` floor — while the layout-sensitivity fix was being proven. It is now **4**, chosen from a measured sweep rather than inherited from the floor.

Measured on Card 2b (SN `$0000_0F14`) in the P2 Edge slot at 350 MHz sysclk / 25 MHz SPI (hp=7), across three `SD_tx_phase_shmoo` runs: pad-to-phase is a **sawtooth of period hp**, because SCK starts on the next base-period boundary after `WYPIN` while the streamer start moves continuously — so only hp distinct phases exist no matter how far the pad is swept. Exactly one of them loses: **pad ≡ 1 (mod 7)**, which failed at pads 8, 15, 22 and 29. All 24 other measured points passed.

4 is the maximal mod-7 distance (3) from the losing phase on both sides. The old floor value of 2 sat one sysclk from the cliff.

### What the five-card survey added (2026-08-18)

The v1.7.0 characterization above was measured on **one card**. A survey across
five cards revised it in three ways that matter:

- **The losing phase is DRIVER-side, not card-side.** Every affected card fails
  at identical pads. But **only three of five cards express it** — the other two
  tolerate the marginal phase. So the tooth is a property of our timing that some
  cards are sensitive to, not a property of any one card.
- **The losing residue MOVES with hp.** Measured: pads `8, 22` at hp=14; `8, 15`
  at hp=7; **`4, 9` at hp=5**. The spacing is hp, but three points do not
  determine the residue as a function of hp, and it should not be extrapolated.
- **Consequently the shipped default of 4 lands ON the losing phase at hp=5**
  (35 MHz). Distance-from-cliff computed at one frequency does not transfer to
  another.

**Why that is not a shipped defect:** hp=5 is above the SD SPI-mode ceiling, and
since v1.7.1 the production speed bound makes it unreachable — a user cannot
arrive there without `debugSetOverspeedAllowed()`. Any future change that raises
production SPI speed **must re-derive this pad for its hp** before shipping.

### hp=4, measured inside high-speed mode (2026-08-19)

The pad was finally characterized at hp=4 — the cell verified CMD6 high-speed
mode runs in — with the card actually in that mode. Failures land at pads **2, 6,
10**: period 4 again, residue **≡ 2 (mod 4)**. Repeated four times, byte-identical
including the exact corrupted values.

**The shipped default of 4 passes**, two pads clear of the nearest tooth on either
side. An independent check agrees: a benchmark that verifies every write found
24 of 24 clean at high speed on three cards. So the write slowdown measured at
43.75 MHz is **not** caused by the pad.

The residue offset now has four data points — hp=4 → 2, hp=5 → 4, hp=7 → 1,
hp=14 → 8 — and no formula fits them that is worth trusting. Treat each hp as
requiring its own measurement.

**Confirmed across three cards (2026-08-19).** Two controllers share the residue
`≡ 2 (mod 4)`; the third expresses no tooth at all, consistent with the earlier
finding that only some cards are sensitive to it. **Pad 4 passes on all three**, so
the shipped default is established safe at hp=4 rather than resting on one card.

**The corruption here is bit-SMEARING, not a bit-shift.** At every failing pad the
corrupted byte is exactly `exp | (exp >> 1)` — every `1` also appears in the
next-lower bit position, which is the preceding transmitted bit bleeding into the
following one on MOSI. That is a settling/edge-rate signature, not the stream
sliding by a position.

This is **the opposite of the read-path failure**, and the two must not be
conflated: a read taken with too small an `align_delay` produces a true one-bit
right shift with carry-in (`$C1` stored → `$E0` received; a smear would have given
`$E1`). Different path, different mechanism, different arithmetic. The smear
reproduces on a second controller at lower severity, so it is a property of the
write path rather than of one card.

**Why the fix matters more than the pad.** With `RDFAST` hoisted out of the phase-critical window, every instruction between the SCK reset and `XINIT` is a fixed 2-clock cog operation, so `XINIT` sits at a compile-time-constant offset from the reset. That is what makes a *single* correct default possible; before the fix, the offset included a variable-latency instruction and no pad value could have been correct for every build.

> **Verification status.** Invariance is **measured**, not only argued. On 2026-08-13
> the streamer's hub buffer was swept through all eight long-aligned positions on both
> the write (`RDFAST`) and read (`WRFAST`) paths: 32 of 32 points correct. Three full
> 574-test sweeps at the shipped configuration support it further. See
> `DOCs/DRIVER-EVOLUTION-v1.6.0-to-v1.7.0.md` §4.7. The single-sector path cannot be
> swept this way — its source address is fixed by the DAT layout — and its coverage
> remains incidental.

The read-path pad (`align_delay = spi_period`) remains as characterized previously. If a future sweep identifies a better production default for either path, the new value is baked into the driver's DAT and this section is updated with its measurement. The diagnostic surface exists for investigating marginal cards and sockets; it is never the production tuning mechanism.
