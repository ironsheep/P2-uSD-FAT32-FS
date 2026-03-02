# Card Presence Detection in SPI Mode

## What the SD Specification Says

**Source:** SD Physical Layer Simplified Specification Version 9.10 (December 2023)

### Section 6.2: "Card Detection (Insertion/Removal)"

> This section is a blank in the Simplified Specification.

The full card detection mechanism is **not published** in the publicly available spec. The details are in the non-public Mechanical Addendum.

### Prescribed Detection Methods (from other sections)

**1. Mechanical card-detect switch (primary method)**
The spec references a "card detection switch mechanism" in the Mechanical Addendum (section 6.2, also sections 3.7.3, 8.1.2). This is a physical switch built into the card socket that signals when a card is inserted or removed. It is the standard approach for SD host designs.

- The P2 Edge Module microSD socket does **not** expose a card-detect pin.
- This method is unavailable to our driver.

**2. DAT3/CS pull-up resistor (SD bus mode only)**
Per the pin assignment table footnote 3:

> At power up [DAT3] has a 50KOhm pull up enabled in the card. This resistor serves two functions: Card detection and Mode Selection. For Card detection, the host detects that the line is pulled high.

In SPI mode, DAT3 is repurposed as CS (chip select), which the host actively drives. The host cannot passively sense a pull-up on a line it is driving. **ACMD42** (SET_CLR_CARD_DETECT) can connect/disconnect this 50K pull-up, but it requires sending a command TO an already-present card.

- This method is **inapplicable to SPI mode**.

**3. No software-only detection method is defined**
The spec states (section 7.2):

> The selected card always responds to the command as opposed to the SD mode.

This is the only implicit guidance: if a card is selected (CS low) and does not respond to a command, there is no card. The spec does not codify this as a detection mechanism.

### Conclusion from Specification

For SPI mode without a card-detect switch, the SD spec provides **no prescribed card-presence detection method**. The only approach available is behavioral: attempt communication and interpret the result.

---

## Electrical Analysis: Card Present vs. No Card

### SPI Bus Behavior When Card is Present

| State | MISO behavior |
|-------|---------------|
| CS HIGH (deselected) | Card drives MISO HIGH (tri-state with internal pull-up) |
| CS LOW, idle | Card drives MISO HIGH ($FF) until it has data to send |
| CS LOW, responding | Card drives R1 response within NCR (0-8 bytes per spec) |
| CS LOW, busy | Card holds MISO LOW until operation completes |

Key: A present card **actively drives** MISO. It responds to CMD0 within NCR (typically 1-2 bytes).

### SPI Bus Behavior When No Card is Present

| Board design | MISO behavior |
|--------------|---------------|
| External pull-up on MISO | Reads steady $FF (HIGH) regardless of clocking or CS |
| No pull-up on MISO | MISO floats; reads noise or sticks at last driven value |

Key: With no card, **nothing drives** MISO in response to commands. The line is passive.

### The Distinguishing Signal

| Scenario | CMD0 response | Pattern |
|----------|--------------|---------|
| Card present, healthy | R1 = $01 within 1-2 bytes | Quick valid response |
| Card present, confused | R1 = non-$01 value | Non-$FF byte within timeout |
| Card present, bus stuck | MISO held LOW ($00) | cmd() returns $00 immediately |
| **No card, pull-up** | **All $FF, timeout** | **cmd() times out, returns 0** |
| **No card, floating** | **All $FF or noise** | **cmd() times out or returns random** |
| Wiring fault | Stuck LOW or garbage | Non-$FF but not valid R1 |

**The decisive signal**: A present card responds with a non-$FF byte within the NCR window. When there is no card (and MISO has a pull-up), **every byte read is $FF** and cmd() always times out.

---

## Detection Method: CMD0 Probe with Timeout Analysis

### Principle

Send CMD0 up to N times. Track whether any attempt received a non-timeout response. After the retry loop:

- **All attempts timed out** (every cmd() call saw only $FF): No card is driving MISO. This is a definitive "no card" signal on boards with MISO pull-up.
- **At least one non-$FF response was seen** but not the expected $01: A card (or something electrical) is present but not initializing correctly. This is a card/wiring problem, not "no card."

### Why This Works

1. The SD spec guarantees NCR = 0-8 bytes. A working card responds to CMD0 within microseconds.
2. Our cmd() function has a 1-second timeout per attempt. A card that doesn't respond in 1 second is not going to respond.
3. Five CMD0 retries with 10ms delays = ~5 seconds total. If nothing responds in 5 seconds, nothing is there.
4. The failure mode is **consistent $FF** (no driver on MISO), which is electrically distinct from "card present but broken" (card drives MISO to something).

### Prerequisite: MISO Pull-Up (Solved by P2 Hardware)

This method requires a pull-up resistor on the MISO line so that "no card" reads consistent $FF. Without a pull-up, a floating MISO reads noise that could look like card responses, producing false positives.

**P2 Solution: Built-in programmable pull-up resistors.** Every P2 I/O pin has configurable internal pull resistors:

| Constant | Resistance | Use case |
|----------|-----------|----------|
| `P_HIGH_1K5` | 1.5K | Strong pull-up |
| `P_HIGH_15K` | 15K | Medium pull-up (ideal for SD detection) |
| `P_HIGH_150K` | 150K | Weak pull-up |
| `P_HIGH_1MA` | ~3.3K equiv | 1mA constant current |

The driver enables `P_HIGH_15K` on MISO **before** the CMD0 probe sequence. This guarantees MISO reads $FF when no card is present, regardless of board design. A present SD card easily overpowers a 15K pull-up (card output impedance is typically under 100 ohms).

**Activation sequence:**
```spin2
  ' Enable 15K pull-up on MISO for card-presence detection
  wrpin(miso, P_HIGH_15K)
  pinf(miso)                    ' Float pin (input with pull-up active)
  waitus(10)                    ' Let pull-up settle
```

**After detection**, the pull-up is cleared when smart pins are initialized for SPI communication (`initSPIPins()` calls `wrpin(miso, spi_rx_mode)` which overwrites the pull-up configuration).

This makes card-presence detection **completely self-contained** and independent of external board pull-up resistors.

### What About cmd() Returning 0 on Timeout?

The current `cmd()` function returns `result := false` (0) on timeout. This is also a valid R1 byte ($00 = no error flags, not in idle). However:

- CMD0 should always produce R1 = $01 (idle bit set). Getting $00 from CMD0 would be highly anomalous.
- In practice, $00 from CMD0 means the card's state machine is confused (it thinks it's already initialized). This is a card-present-but-broken scenario, not a no-card scenario.
- **For detection purposes, cmd() returning 0 can be treated as "timed out / no card" in the CMD0 context**, since a real card responding $00 to CMD0 is a card that needs recovery, not absence.

---

## Implementation Plan

### New Error Code

```spin2
CON ' error codes
  E_NO_CARD = -8      ' No card detected in slot (MISO idle during CMD0 probe)
```

This sits in the card-level tier (E_TIMEOUT=-1 through E_IO_ERROR=-7), adding the most fundamental failure: no hardware present.

### Changes to `initCard()`

**Step 2 (pin setup):** Enable P2 internal pull-up on MISO before SPI init:

```spin2
  ' STEP 2: Configure SPI pins and slow clock
  pinh(cs)                                      ' CS HIGH = deselected
  pinh(mosi)                                    ' MOSI HIGH
  pinl(sck)                                     ' SCK LOW (SPI mode 0)

  ' Enable 15K pull-up on MISO for card-presence detection
  ' If no card is present, MISO reads $FF (pulled high)
  ' If card is present, card drives MISO (overpowers 15K easily)
  wrpin(miso, P_HIGH_15K)
  pinf(miso)                                    ' Float pin (input with pull-up)
  waitus(10)                                    ' Let pull-up settle
```

**Step 4 (CMD0 loop):** Track whether ANY cmd() call returned a non-timeout response:

```spin2
  ' STEP 4: CMD0 - GO_IDLE_STATE
  got_response := false
  repeat CMD0_MAX_RETRIES
    resp := cmd(CMD0, 0)
    if resp <> 0                                ' cmd() returns 0 on timeout
      got_response := true
    if resp == R1_IN_IDLE
      quit
    waitms(CMD_RETRY_DELAY_MS)

  if resp <> R1_IN_IDLE
    if not got_response
      debug("    [initCard] No card detected (MISO idle across all CMD0 attempts)")
      result := false
      last_init_error := E_NO_CARD
    else
      debug("    [initCard] Card responded but CMD0 failed: $", uhex_(resp))
      result := false
      last_init_error := E_BAD_RESPONSE
```

The pull-up is automatically cleared when `initSPIPins()` overwrites MISO's WRPIN register with `spi_rx_mode` during Step 3.5.

### Changes to `do_mount()` / `do_init_card_only()`

These methods call `initCard()` and translate its boolean into error codes. They should propagate the specific error:

```spin2
  if not initCard()
    pb_status := last_init_error                ' Was: E_INIT_FAILED (generic)
```

This way `mount()` returns `E_NO_CARD` to the caller when no card is present, instead of the generic `E_INIT_FAILED`.

### New Local Variable

Add `got_response` as a local to `initCard()`:

```spin2
PRI initCard() : result | timeout, resp, card_version, acmd41_arg, got_response
```

### New DAT Variable

Add `last_init_error` to DAT section for initCard() to communicate the specific failure reason:

```spin2
last_init_error   LONG  0                       ' Specific error from last initCard() failure
```

### Error Flow

```
User calls mount()
  -> do_mount()
    -> initCard()
      -> CMD0 loop: all timeouts, no card
      -> result := false, last_init_error := E_NO_CARD
    -> do_mount sees initCard() failed
    -> pb_status := last_init_error  (= E_NO_CARD)
  -> mount() returns E_NO_CARD to caller
```

### User-Visible Behavior

```spin2
result := sd.mount(CS, MOSI, MISO, SCK)
if result == sd.E_NO_CARD
  debug("No SD card inserted")
elseif result < 0
  debug("Mount failed: ", sdec(result))
```

---

## Future Considerations

### Hot-Removal Detection

This same principle (MISO goes passive) could detect card removal during operation. If a readSector() suddenly gets all $FF where data was expected, the card may have been removed. This is out of scope for the initial implementation but uses the same electrical signal.

### Dedicated `isCardPresent()` PUB Method

A lightweight public method that just does the CMD0 probe without full initialization. Useful for applications that want to poll for card insertion before attempting mount. Would require the worker cog to be running (for SPI pin access).

### MISO Pull-Up Note

The P2 internal pull-up (`P_HIGH_15K`) eliminates the need for external pull-up resistors on MISO. The driver enables it automatically during the detection probe sequence. No board-level hardware changes are required.
