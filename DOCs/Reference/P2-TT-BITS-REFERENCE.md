# P2 TT Bits — Complete Reference

**Source:** Chip designer (Chip Gracey), relayed 2026-02-16

## Overview

The TT field is bits [7:6] of the WRPIN register. The silicon documents describe TT as **two independent bit functions**, not four discrete modes:

| Bit | Name | Function |
|-----|------|----------|
| Bit 7 (high) | Output SOURCE selector | 0 = OUT (or SMART/OUT), 1 = OTHER (or SMART/OTHER) |
| Bit 6 (low)  | Output ENABLE control  | 0 = disabled regardless of DIR, 1 = enabled regardless of DIR |

**Note:** The enable control (bit 6) only applies when a smart pin mode is active (SSSSS != 0). When no smart pin mode is configured, DIR controls output enable as normal.

## What is "OTHER"?

- **Odd pins:** OTHER = the even pin's NOT output state (differential source)
- **Even pins:** OTHER = a unique pseudo-random bit (noise source)
- **All pins with smart pin active:** SMART = smart pin output, which overrides OUT/OTHER

The "/" in "SMART/OUT" and "SMART/OTHER" means **priority** — SMART takes priority when actively driving. The fallback source differs.

## Full Matrix: Smart Pin Mode OFF (SSSSS = %00000)

DIR controls output enable normally.

| TT | Non-DAC_MODE | DAC_MODE |
|----|-------------|----------|
| %00 | OUT drives output | OUT enables ADC, M[7:0] sets DAC level |
| %01 | OUT drives output | OUT enables ADC, M[3:0] selects cog DAC channel |
| %10 | OTHER drives output | OUT drives BIT_DAC |
| %11 | OTHER drives output | OTHER drives BIT_DAC |

## Full Matrix: Non-DAC Smart Pin Modes (SSSSS = %00100..%11111)

**This is the table relevant to SPI — P_SYNC_TX and P_SYNC_RX are non-DAC modes.**

| TT | Output Enable | Output Source |
|----|---------------|---------------|
| %00 | **Disabled** regardless of DIR | SMART/OUT (irrelevant since disabled) |
| %01 | **Enabled** regardless of DIR | SMART/OUT drives output (or BIT_DAC if DAC_MODE) |
| %10 | **Disabled** regardless of DIR | SMART/OTHER (irrelevant since disabled) |
| %11 | **Enabled** regardless of DIR | SMART/OTHER drives output (or BIT_DAC if DAC_MODE) |

## Full Matrix: DAC Smart Pin Modes (SSSSS = %00001..%00011)

| TT | Output Enable | ADC Control |
|----|---------------|-------------|
| %00 | Disabled | OUT enables ADC in DAC_MODE, M[7:0] overridden |
| %01 | Enabled  | OUT enables ADC in DAC_MODE, M[7:0] overridden |
| %10 | Disabled | OTHER enables ADC in DAC_MODE, M[7:0] overridden |
| %11 | Enabled  | OTHER enables ADC in DAC_MODE, M[7:0] overridden |

## Differential Signaling Example (TT=%11)

USB differential pairs use this. For pin pair P0/P1:
- Even pin (P0): P_OE (TT=%01) — SMART drives the main signal
- Odd pin (P1): TT=%11 — SMART from this pin's own smart pin, OTHER provides complement of even pin's output

Creates hardware-level differential signaling without software intervention.

## SMART vs OUT Priority — Key Nuance

With TT=%01 (SMART/OUT): when the smart pin is **NOT actively driving**, the OUT bit (which includes streamer data) is the fallback. But every active mode document says:

> "This mode overrides OUT to control the pin output state"

So SMART is always in control once the mode is running. The OUT fallback would only matter during reset or in an edge-case idle state.

**Open question for our SPI driver:** When P_SYNC_TX is in start-stop mode and has finished shifting its last byte (idle between transfers), does SMART still hold the output? Or does it revert to OUT? This determines the idle-HIGH behavior we observe.

## Relevance to SPI Driver (micro_sd_fat32_fs.spin2)

Our current MOSI configuration:
```
spi_tx_mode := P_SYNC_TX | P_OE | P_PLUS2_B
```

P_OE sets TT bit 6 = 1. With bit 7 = 0 (from P_SYNC_TX base), our TT = %01:
- Output **enabled** regardless of DIR
- Source = **SMART/OUT** (SMART priority, OUT fallback)

This means:
- When smart pin is actively shifting: SMART drives MOSI
- When smart pin is idle: Either SMART holds last state, or OUT (streamer) is fallback
- Experimentally confirmed: idle state is HIGH (not zero), which is why removing pinclear produces all-$FE data
