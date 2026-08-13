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

- **Default 0:** preserves historical `align_delay = hp` behavior.
- **Per `p2kbArchIoPinTiming`** the host-side I/O ring round trip is 5-6 sysclks (smart-pin output 1.5-3 + registered input 3-4), so the optimal offset post-Phase-1.5 is **in the +5 to +7 range**, not negative.
- **Floor:** `align_delay` is clamped to ≥ 2 (cog needs 2 sysclks to execute `WAITX` before `XINIT`).
- **Range:** caller may pass `[-8, +8]`; out-of-range silently ignored.

Affects ONLY streamer-driven 512-byte sector transfers (Path B). Does NOT affect single-byte transfers — for Path A see `debugSetSampleMode`.

### `debugGetEffectiveAlignDelay() : delay`

Returns the streamer-DMA `align_delay` value that will be used on the next streamer-driven sector transfer. Computed as `spi_period + align_delay_offset`, clamped to a minimum of 2.

### `debugSetTxAlignDelay(pad)`

Set the `WAITX` phase pad used between the SCK counter reset and `XINIT` at both **write-path** streamer sites (`writeSector` and `writeSectors`). This is the shmoo knob for the layout-invariance fix: with `RDFAST` hoisted out of the phase-critical window, the MOSI-bitstream-to-SCK-edge phase is a build-independent constant, and this pad centers it in the passing window. The characterized default is baked into the driver's DAT (`tx_align_delay`).

- **Floor:** clamped to ≥ 2 at the use site (`WAITX` minimum).
- **Range:** `[2, 2 + 2*hp]` covers one full SCK period of phase; larger values wrap the same phases.

Affects ONLY write-path streamer bursts. The read path's phase pad remains `align_delay` (see `debugSetAlignDelayOffset`).

### `debugGetTxAlignDelay() : pad`

Returns the configured `tx_align_delay` value (before the use-site floor clamp).

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
- Path B reads: `align_delay = spi_period` (offset=0)
- Path B writes: `tx_align_delay = 4` — **characterized, not a floor value.** See below.

These defaults reproduce pre-Phase-2/3 byte-on-the-wire behavior at sysclk=350 MHz and are validated against the regression suite. The production driver does not expose any tunable surface for these — the right values are hardcoded internally.

### The write-path pad was characterized on the bench (v1.7.0, 2026-08-11)

`tx_align_delay` shipped at 2 — the bare `WAITX` floor — while the layout-sensitivity fix was being proven. It is now **4**, chosen from a measured sweep rather than inherited from the floor.

Measured on Card 2b (SN `$0000_0F14`) in the P2 Edge slot at 350 MHz sysclk / 25 MHz SPI (hp=7), across three `SD_tx_phase_shmoo` runs: pad-to-phase is a **sawtooth of period hp**, because SCK starts on the next base-period boundary after `WYPIN` while the streamer start moves continuously — so only hp distinct phases exist no matter how far the pad is swept. Exactly one of them loses: **pad ≡ 1 (mod 7)**, which failed at pads 8, 15, 22 and 29. All 24 other measured points passed.

4 is the maximal mod-7 distance (3) from the losing phase on both sides. The old floor value of 2 sat one sysclk from the cliff.

**Why the fix matters more than the pad.** With `RDFAST` hoisted out of the phase-critical window, every instruction between the SCK reset and `XINIT` is a fixed 2-clock cog operation, so `XINIT` sits at a compile-time-constant offset from the reset. That is what makes a *single* correct default possible; before the fix, the offset included a variable-latency instruction and no pad value could have been correct for every build.

> **Verification status.** Invariance is **measured**, not only argued. On 2026-08-13
> the streamer's hub buffer was swept through all eight long-aligned positions on both
> the write (`RDFAST`) and read (`WRFAST`) paths: 32 of 32 points correct. Three full
> 574-test sweeps at the shipped configuration support it further. See
> `DOCs/DRIVER-EVOLUTION-v1.6.0-to-v1.7.0.md` §4.7. The single-sector path cannot be
> swept this way — its source address is fixed by the DAT layout — and its coverage
> remains incidental.

The read-path pad (`align_delay = spi_period`) remains as characterized previously. If a future sweep identifies a better production default for either path, the new value is baked into the driver's DAT and this section is updated with its measurement. The diagnostic surface exists for investigating marginal cards and sockets; it is never the production tuning mechanism.
