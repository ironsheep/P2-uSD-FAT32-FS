# Cloudisk 2GB — Streamer-Read Failure Investigation

**Opened:** 2026-05-18
**Card under test:** Cloudisk 2GB microSD (counterfeit — CID product name `asdfg`, MID `$05`, CRC7 `$00`); register-confirmed 2 GB **SDSC** (CSD v1.0).
**Status:** Cause narrowed to the driver's streamer-DMA *read* path; soft logic analyzer built to capture the bus and resolve the final fork.

This card was bought new specifically to certify the driver against budget/marginal SDSC media. It is a legitimate certification target, not a card to discard.

---

## 1. Symptom

| Path | Result |
|------|--------|
| Card init (CMD0/CMD8/ACMD41), register reads | **Work** — all sysclks 200–350 MHz |
| Slow-path read (`readSectorSlow`, byte-by-byte smart-pin SPI) | **Works** — returns real, distinct data for every sector |
| Streamer-DMA read (`readSector`) | **Fails** — destination buffer left untouched; driver returns `-7` |
| Writes | Reach the full success handshake (data-response `$05`, CMD13 clean); persistence confirmed via slow-path readback of a prior run's pattern |

The streamer read does not "capture zeros" — with a distinct `$EE` sentinel in the destination buffer, the buffer is **completely unchanged** after the read. The streamer DMA transfers *nothing* into hub RAM.

This is the same failure class documented for the SanDisk SU01G SDSC card.

---

## 2. What we ruled out

### Sample phase — RULED OUT

The driver's streamer read samples MISO open-loop: the smart pin is disabled and floated, and the streamer NCO samples the raw pin at a phase set by `align_delay = spi_period + align_delay_offset` plus a hardcoded `init_phase`. `DOCs/SPI-PHASE-MARGIN-API.md` explicitly anticipates "old SDSC cards with long `t_OD`" needing this tuned.

`SD_phase_sweep_test.spin2` (reworked to be mount-free and to validate against a slow-path reference) swept `align_delay_offset` over [−3..+8] — more than a full bit cell — for both sample modes: **24/24 cells failed.** Shifting *when* the streamer samples does not help anywhere. Phase alignment is not the cause.

### SPI clock rate — RULED OUT

`SD_streamer_speed_test.spin2` swept the streamer read across SPI speeds 25 MHz → 400 kHz, comparing each to the slow-path reference: **fails at every speed.** The remaining structural difference between the working slow path (SCK in 8-bit bursts, idle gaps between bytes) and the failing streamer path (4096 bits clocked back-to-back, no gaps) is not rescued by lowering the rate either.

### "Cranky controller" CMD13 hypothesis — does not apply

CMD13 polling on this card returns clean (`$00`). The card does not flag spurious status bits. (This distinguishes it from the SU01G's documented CC_ERROR behaviour.)

---

## 3. The remaining question

Only one fork is left, and it cannot be answered from software running the transfer:

1. During the streamer's continuous clocking, **does SCK actually toggle?**
2. **Does the card drive MISO with the sector data** in response?

- SCK toggles + MISO carries data, yet the driver's buffer is empty → the bug is in the driver's **streamer-RX capture path**.
- SCK toggles + MISO flat → the card will not drive MISO under gapless streamer clocking → **card limitation**.
- SCK does not toggle → the driver's streamer **clock generation** is broken.

---

## 4. The soft logic analyzer

Rather than reach for an external instrument, the P2 instruments itself.

### Why not the smart-pin "nearest neighbor" feature

P2 smart pins can route their A/B input from a neighbor at ±1/±2/±3 pins (WRPIN `%AAAA`/`%BBBB`, internal — no wire needed). This is real and usable for single-signal *measurement* (e.g. an unused pin counting SCK edges). But a full **parallel decode** would need one free pin within ±3 of *both* MISO (P58) and SCK (P61); they are 3 pins apart and every position within ±3 of both is occupied. So neighbor routing alone cannot do byte-level capture here.

### The mechanism actually used

The P2 streamer has capture modes (Pins → Hub). A **spare cog runs its own streamer** in 16-pin capture mode (`X_16P_2DAC8_WFWORD`), recording pins P48–P63 — which contain all four SD pins — into a 256 KB hub buffer, while the SD worker cog performs the read. Each cog has an independent streamer; the two run in parallel.

(16-pin, not 4-pin: streamer multi-pin capture is block-aligned, and P58–P61 straddle a 4-pin boundary. 16-pin P48–P63 is the smallest aligned block containing all four.)

Sample bit mapping: MISO→bit10, MOSI→bit11, CS→bit12, SCK→bit13.

### Sampling / Nyquist

Sample clock = sysclk/2 = **175 MS/s** at 350 MHz. The fastest signal, SCK at 25 MHz, is then sampled at **7 samples per period — 3.5× Nyquist**. Every half-cycle is resolved; edges are placed within one sample (5.7 ns). This comfortably exceeds the Nyquist requirement; full sysclk sampling is not cleanly available (the streamer NCO tops out near sysclk/2) and is not needed.

Window: the streamer sample-count field is 16 bits (≤65535/XINIT); two back-to-back XINITs against one WRFAST give 131070 samples = a **749 µs window**, which contains a full 25 MHz single-sector read.

### Limitation

The capture records the *digital logic level* the P2 input registers latch — timing, edges, whether the card drives data. It does **not** reveal analog signal quality (slow slew, marginal levels, ringing). If the streamer fails because MISO slews too slowly to latch cleanly, this capture may itself sample it ambiguously; that residual question still belongs to a scope.

---

## 5. Tools produced

| Tool | Role |
|------|------|
| `diagnostic-tests/SD_phase_sweep_test.spin2` | Streamer `align_delay` × sample-mode sweep (reworked: mount-free, slow-path-referenced). Ruled out phase. |
| `diagnostic-tests/SD_streamer_speed_test.spin2` | Streamer read vs slow read across SPI speeds. Ruled out clock rate. |
| `diagnostic-tests/SD_soft_la_test.spin2` | Soft logic analyzer — spare-cog streamer capture of the SD bus during a read. Resolves the final fork. |

`SD_macca_diagnostic_v2.spin2` was also fixed (Phase 0 no longer gates the sweep; matrix reordered gentlest-first) and `DEBUG_BAUD` was added to `SD_card_characterize`/`SD_format_card`.

---

## 6. Soft-LA build status (2026-05-18)

`SD_soft_la_test.spin2` is built and compiles. It went through several iterations:

- **16-pin one-pass capture** (MISO+MOSI+CS+SCK at once) — abandoned: the only
  block-aligned 16-pin window containing MISO(P58) and SCK(P61) is P48–P63,
  which also spans P62/P63 (the debug-serial pins). The capture corrupted the
  debug channel → garbage + hang.
- **Sequential 1-pin captures** — SCK then MISO, one per SD read, using the
  streamer's `X_1P` mode (driver-proven, no debug-pin overlap). Plus a hard
  rule: **no `debug()` while a capture runs**. This compiles and runs cleanly
  (no hang, no garbage).
- **First run mis-synced**: a `waitus()`-timed capture window did not reliably
  overlap the read — capture showed only ~50 SCK transitions (impossible for a
  real transaction). Fixed by a **CS-falling-edge hardware trigger**: the
  capture cog sets up the streamer, then spins on CS (P60) and issues `XINIT`
  only when CS falls — syncing the capture to the actual bus transaction.
- Streamer NCO rate verified against P2KB (`p2kbPasm2Setxfrq`):
  `D = target_freq × 2^32 / clkfreq`; sysclk/2 → `$8000_0000`.

**Current state:** CS-edge-triggered version compiles; **not yet run on
hardware.** That hardware run is the immediate next step.

## 7. Next steps

1. Run the CS-edge-triggered `SD_soft_la_test.spin2`. Expect each capture to
   start exactly at CS-low and show a real transaction.
2. **SCK capture** — thousands of transitions = SCK clocks; near-zero = the
   driver's streamer clock-gen (WYPIN) is not running.
   **MISO capture** — a sustained dense burst = the card drives the data;
   flat = the card does not drive MISO under streamer clocking.
3. If SCK clocks + MISO carries data but the driver's streamer buffer is empty
   → the bug is in the streamer-RX block of `readSector()` (the
   `FLTL/DIRH/WYPIN/WAITX/XINIT/WAITXFI` sequence and `pinclear`/`pinf` MISO
   handling).
4. If the soft-LA cannot distinguish an analog-signal-quality cause, escalate
   to a scope/LA capture.
