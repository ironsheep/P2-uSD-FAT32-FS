# Boot-Time Bus Traffic Wedges Shared-Pin microSD Cards

Two microSD cards fail `mount()` with `E_NO_CARD` (`-8`) on every driver start after the first, until power is removed. The cause is boot-time traffic on pins the microSD socket shares with the boot flash, which leaves the card in a data-transfer state. Issuing CMD12 before CMD0 at card initialization resolves it. Fixed in v1.8.0.

**Investigation:** May–August 2026.

---

## 1. Applicability

You need all four of the following. If any one is absent, this document does not describe what you are seeing.

1. **The microSD socket shares pins with another function that drives them.** On the P2 Edge module, P58–P61 are shared between the boot flash and the microSD socket, and the two functions assign those pins different roles (§4.2).
2. **Something drives those pins before your code runs.** On a P2 Edge that is the boot ROM, on every reset, before a single user instruction executes — and it happens whichever of the two shared-pin devices the module is set to boot from. With flash boot selected the card sees the ROM's flash traffic on pins whose roles are exchanged; with microSD boot selected the ROM addresses the card directly, initialising it and reading a boot file. Both are boot-time traffic on the card's pins and both are covered by the fix.
3. **The card has been accessed since it last lost power.** A card not addressed since power-on does not exhibit the fault.
4. **The card latches on the resulting traffic.** Two of the twenty-six cards in our catalog do. No mainstream card in our catalog has.

**The symptom signature.** A card that is physically present and was readable moments earlier returns `E_NO_CARD` (`-8`) from `mount()` or `initCardOnly()`. Retry does not clear it. Elapsed time does not clear it. Additional clocking does not clear it (§2.4). Only removing power from the card clears it.

**Hardware:** a serial-download reset does not drop the card's 3.3 V rail and therefore does not clear the condition. Establishing the cold/warm split requires a full power cycle.

### 1.1 Terms used in this report

**Cold and warm.** A **cold** run is the first driver session after the board has been fully powered down and back up. A **warm** run is any driver session with an earlier one behind it and no power cycle between. The whole defect lives in that distinction.

**The quiesce.** The name used here for the fix: a CMD12 issued before CMD0 at the start of card initialization, which stops any transfer the card is still in the middle of. §6 is the implementation.

**SD commands.** Referred to by number throughout, as the specification does.

| | |
|---|---|
| **CMD0** | GO_IDLE_STATE — the reset that puts a card into SPI mode. Every initialization begins here |
| **CMD12** | STOP_TRANSMISSION — aborts a transfer in progress. §4.1 is why this one matters |
| **CMD13** | SEND_STATUS — reads the card's status register |
| **CMD24 / CMD25** | WRITE_BLOCK and WRITE_MULTIPLE_BLOCK — single-sector and multi-sector writes |

**Card identity fields.** Every SD card carries a CID register (who made it) and a CSD register (what it can do). The counterfeit evidence in §2.5 rests on four CID fields — **MID**, the manufacturer ID; **PNM**, the product name; **PRV**, the product revision; **PSN**, the serial number — plus **CRC7**, the checksum each register carries. Genuine silicon computes that checksum; both cards here return `$00`.

**SDSC.** The original SD capacity class, up to 2 GB, addressed by byte rather than by block. Both cards here are SDSC, which is unusual for parts manufactured in 2025 and is part of why they draw attention.

**DAT3.** One of the card's data lines. In SPI mode it is repurposed as chip select, which is what makes the pin-role table in §4.2 read the way it does.

**cog.** One of the P2's eight independent processors. The driver runs on one of them.

**Pad.** A deliberate stall, measured in system-clock ticks, inserted to shift one event's phase relative to another. It appears here only in §5.1.

**Cell.** One test condition — one combination of a sweep's swept parameters, scored as a unit. The write probe's cells are (frequency × pad) combinations, each scored by a write and a readback compare.

**The dummy-CRC card class.** A conforming card computes a CRC-16 over every data block it returns, and the host validates the read against it. Some cards return a fixed constant instead, so the check always passes and corruption is invisible to it. The driver flags these as `CW_NO_DATA_CRC`. Both cards in this report are in that class.

---

## 2. Findings

### 2.1 The trigger is boot-time bus activity, not driver behavior

**Finding:** with boot-time access to the shared pins disabled, four consecutive warm runs completed clean across two power cycles. Restoring the setting returned the fault immediately.

| Switch setting | Flash banner | Cold run | Warm run |
|---|---|---|---|
| P59 pulled up (no flash or microSD boot) | absent | 43/43 | **43/43 clean, 4 warm runs, 2 power cycles** |
| Boot-time access enabled | present | 43/43 | **19/24, `-7` then `-8`** |

Every prior warm run in the campaign had wedged on the first attempt.

**Method:** the toggle was exercised in both directions, in one session, on one card. A single-direction result cannot separate a fix from a quiet day, and this campaign had already produced two conclusions that inverted under re-measurement (§5.3).

**Method:** switch state was verified empirically rather than assumed, using a banner this board happens to print.

This Edge module has a program resident in its flash, loaded there deliberately, which announces itself at boot with the line `* Hi! from FLASH *`. It has nothing to do with the tests. It appears in the transcripts because of how downloading works: pnut-ts opens the serial port and starts listening, *then* resets the P2. The P2 boots from flash, the resident program runs and prints its banner, and only after that does pnut-ts download the test binary and let it run. The banner is caught in the window between the reset and the download — which is why a test transcript opens with a line from an unrelated program, at line 15, before the test says anything.

That makes it a free check on the switches. P2KB (`p2kbArchBootPatternSelection`, Hardware Manual 2022-11-01) documents `P59 = up` as *"Program from serial within 60 s window; no flash or microSD card boot"*. With boot-time access disabled the flash program never runs and the banner is simply absent. Its presence or absence was read from every transcript rather than inferred from switch positions.

**Hardware:** the P2 Edge module carries a four-position DIP switch, numbered 1-4 left to right, identical on the Edge Standard and Edge 32MB modules.

| Switch | Controls | Pin |
|---|---|---|
| 1 | LED | no boot effect |
| 2 | **FLASH** | **P61** up when on |
| 3 | **up arrow** | **P59** up to 3.3 V |
| 4 | **down arrow** | **P59** down to ground |

Switches 3 and 4 must never both be on; they drive P59 in opposite directions.

**Switch 2 selects which of the two shared-pin devices the ROM boots from** — on, the SPI flash; off, the microSD card. That is the point worth holding onto: the flash and the card are on the same four pins, and this switch decides which one the boot ROM talks to. Switch 4 then sets what happens when that source fails.

| Switches | Boot procedure | What the card sees at boot | Banner |
|---|---|---|---|
| 2 on, 4 off | boot from SPI flash, with a 100 ms serial window first | the ROM's flash traffic, on pins whose roles are exchanged (§4.2) | present |
| 2 on, 4 on | boot from SPI flash, no serial window | same | present |
| 2 off, 4 off | boot from microSD; fall back to serial if absent | the ROM initialising the card, mounting FAT32 and reading a boot file | — |
| 2 off, 4 on | boot from microSD only, no serial window | same as above | — |
| 3 on | serial only; neither flash nor microSD boot | nothing | absent |

**The two configurations used throughout this report are a flash-boot row and the last row.** Every wedging run had switch 2 on, which is why the banner is present in every wedging transcript and why the ROM never read the card in any run recorded here.

**Which flash-boot row makes no difference.** The fault appears with the serial window and without it — switch 4 either way — observed at the bench. That is consistent with the cause being the flash read itself rather than anything about the boot window: the ROM reads the flash in both variants, and that is the traffic the card sees.

The microSD-boot rows require `P60 = up`, and nothing on this DIP drives P60 — so the Edge asserts it by some other means. P2KB records that mechanism as unverified (`p2kbArchBootPatternSelection`, `p2kbArchSdCardBoot`); that these rows work on the bench establishes that it is asserted, not how.

### 2.2 A driver session is required to arm the condition; the filesystem layer is not involved

**Finding:** `initCardOnly()` alone arms it. A size-matched control that touches no pin does not.

| Arm | Predecessor performs | Size | Warm `mount_tests` |
|---|---|---|---|
| `P_NOTHING` | nothing; no pin touched | 47,369 | **43/43 clean**, `0` / `0` |
| `P_INIT` | `initCardOnly()` only, worker cog left running | 47,334 | **19/24 wedged**, `-7` / `-8` |

The two arms differ by 35 bytes, so they differ in what they do rather than in how long they take to download.

`P_INIT`'s own `initCardOnly()` returned `0`. It succeeded, then armed the fault.

This eliminates in one run: the mount, directory reads, the FAT scan, the unmount, and the FSInfo update. It also eliminates the cog-shutdown hypothesis without a separate arm — `P_INIT` left the worker cog running, so no `COGSTOP` pin release occurred.

### 2.3 The condition is latched in the card and survives everything short of power removal

| Arm | Result | Eliminated |
|---|---|---|
| Null binary, 49,691 bytes, no driver object, no pin touched | 2/2 clean | The reset itself, the pin-float window, download traffic. The null binary is *larger*, so its high-impedance window is longer |
| Driver session followed by 120 s powered idle | wedged | Time-based recovery; the housekeeping-completes model |
| Read-only predecessor, FSInfo update suppressed | wedged | Writes, FSInfo, filesystem state. Nothing on the card was modified, so what persists is controller state, not data |
| All four pins floated to high-Z for 1,200 ms after a driver session | 8/8 clean | Pin float in the order in which it actually occurs |

**Method:** every arm was size-matched against the reproducer binary, so the arms differ in what they do rather than in how long they take to download.

### 2.4 A wedged card is not recoverable in software

**Finding:** five rungs, no power cycle, all returned `-8`.

| Rung | Action | Result |
|---|---|---|
| 1.1 | `initCardOnly()` | `-8` |
| 1.2 | `initCardOnly()` again | `-8` |
| 2→3 | 102,400 clocks, CS high (25× our driver's own 4,096-clock flush), then init | `-8` |
| 4→5 | 102,400 clocks, CS low (card selected), then init | `-8` |

The fault can be **detected** — `-8` from init — and cannot be **repaired**. Detect-and-recover was therefore closed as a release path, and the investigation had to reach a root cause.

The reasoning behind rungs 2–5: an SD card advances its state machine on SCK, so a card waiting for clocks it will never receive is indistinguishable from a dead one. Supplying 25× the recovery flush in both CS polarities was intended to exhaust that explanation. The *manner* of its failure is the campaign's most confirming single result — see §4.3.

### 2.5 The two cards are indistinguishable under the reproducer

| | Lerdisk 1 GB `$0000_01F4` | Cloudisk 2 GB `$0000_1680` |
|---|---|---|
| `mount_tests` | 19 pass / 24 fail | 19 pass / 24 fail |
| `unmount()` | `-7` | `-7` |
| `mount()` #2 | `-8` | `-8` |
| Diagnostics | `error()=-8, lastCMD13=$0, CRC match=0 mismatch=0 retry=0` | identical |

Both are counterfeit SDSC cards bought as separate products: PNM `"asdfg"`, MID `$05`, PRV 2.2, sequential serials, adjacent manufacture dates (2025/11 and 2025/12). CID and CSD CRC7 fields are `$00`, which conforming silicon does not produce; the data-block CRC is a dummy `$0000`.

---

## 3. The reproducer

Two regression suites run back to back in the onboard socket, with no power cycle between them:

```
SD_RT_mount_tests        ->  SD_RT_raw_sector_tests
```

| Step | Result on a wedging card |
|---|---|
| Tests #1–12 (first mount, directory and file operations) | pass |
| #13 `unmount()` | `-7` `E_IO_ERROR` after a ~4 s stall when warm, `0` when cold (§5.0) |
| #15 `mount()` #2 | `-8` `E_NO_CARD` — invariant |
| `SD_RT_raw_sector_tests` afterwards | 0/1, `ERROR: Card init failed!` |

**Finding:** the reproducer is deterministic once that variable is controlled.

| Condition | Runs | `mount_tests` | `unmount()` | `mount()` #2 |
|---|---|---|---|---|
| **Cold** — first binary after power-on | 4 | **43/43 pass** | `0` | `0` |
| **Warm** — any prior driver session, no power cycle | 2 | **19/24 fail** | `-7` | `-8` |

**Finding:** the predecessor need not be a different program. One wedging run's predecessor was the identical `mount_tests` binary.

**Method:** no `identify` run precedes a cold arm. An identify is itself a driver session and destroys the cold condition. Card identity is confirmed after the first run.

**Pitfall:** a formatter or fsck utility that discards the return value of a sector read reports the resulting zero-filled buffer as a data mismatch. `isp_format_utility`'s internal `doFormat()` discarded the return of `sd.readSectorRaw(0, @verifyBuf)` and reported `*** MBR READBACK MISMATCH! Written data not on card ***` — a write failure that had not occurred, masking a `-3` from a wedged card. The fsck utility carried the same defect. Both are fixed, and the class was swept for across our driver. A discarded status code does not merely fail to help; it manufactures false symptoms.

---

## 4. Mechanism

### 4.1 The specification designates one command for this state

**SD Physical Layer Simplified Specification v9.10, spec §4.3 (Data Transfer Mode):**

> All data read commands can be aborted any time by the stop command (CMD12). The data transfer will terminate and the card will return to the Transfer State.

**Spec §7.2.3 (SPI mode, Data Read)** confirms the behavior is not SD-mode-only:

> Stop transmission command (CMD12) will actually stop the data transfer operation (the same as in SD Memory Card operation mode).

**Spec §7.2.8 (SPI mode, Error Conditions)** states the decisive constraint:

> A command may be rejected in any one of the following cases:
> - It is sent while the card is in read operation (**except CMD12 which is legal**).

A card left mid-read rejects CMD0, which accounts for five silent retries, and accepts CMD12, which accounts for one command restoring it. The specification also documents the failure from the other direction: *"in case the host sends command while the card sends data in read operation then the response with an illegal command indication may disturb the data transfer."*

CMD12 is listed **Mandatory** in SPI mode and is therefore available on any card our driver will encounter.

### 4.2 Pin roles are swapped between the two functions

**Hardware:** on the P2 Edge module the microSD socket and the boot flash share P58–P61, and the two functions assign those pins different roles. Per P2KB the boot ROM's flash interface is `P61 = CS, P60 = CK, P59 = DI, P58 = DO`. Our driver's default microSD pinout is `CS = P60, MOSI = P59, MISO = P58, SCK = P61`.

| Pin | Boot flash role | microSD role |
|---|---|---|
| **P60** | **CK** (clock) | **DAT3 / CS** (chip select) |
| **P61** | **CS** (chip select) | **CLK** (clock) |
| P59 | DI (host → flash) | MOSI (host → card) |
| P58 | DO (flash → host) | MISO (card → host) |

Clock and chip select are exchanged. While the boot ROM reads flash, the card sees its own chip select toggling at flash clock rate with traffic on its data lines — at every reset, at RCFAST (20–30 MHz), before user code executes.

A card left in a data-transfer state by that activity is streaming rather than listening. CMD0 sent into a stream is data, not a command.

This is the surviving explanation rather than a preferred one: the only other thing that executes before user code is excluded by inspection (§4.3), and the ROM's SD-boot path is excluded by the boot pattern. What remains demonstrated is the input-output pair — remove the boot-time traffic and the fault stops; send the specification's transfer-abort command and the fault stops. How a card walks from this traffic into a transfer state it will not leave is not shown step by step, and §7 says so.

### 4.3 The actor, by elimination

**The actor is the boot ROM, established by elimination.** Two things execute on this board before any user code: the boot ROM, and the program resident in the flash image it loads. The resident program is excluded by inspection — it starts the serial port, prints one line, and then loops in place, so nothing else can happen. It never addresses P58–P61 in their card roles at all. That leaves the ROM's own flash-interface traffic as the only candidate, which is the mechanism described in §4.2.

The ROM's *SD-boot* path is excluded **for the runs recorded here**, and only for those. Every run had switch 2 on, which puts `P61` up and selects a flash-boot pattern; the documented fallback on flash failure is the serial window, not the card (P2KB `p2kbArchBootPatternSelection`, `p2kbArchSdCardBoot`). The banner confirms it in every transcript. So in this campaign the ROM never went looking for a boot file on the card.

**That is a statement about our switch settings, not about the board.** With switch 2 off the same ROM boots *from* the card — initialising it, mounting FAT32, locating and reading a boot file (`p2kbArchSdCardBoot`). Such a board also meets condition 2 of §1: there is boot-time traffic on the card's pins, by a more direct route, since the ROM is addressing the card rather than the flash.

What that traffic does to a susceptible card is **not** established, and the reasoning below argues against the obvious guess: an abandoned ROM read is unlikely for the same reason it is unlikely on the flash side — it would require the boot ROM to mishandle a card transaction. We never ran that configuration and measured nothing in it. The fix covers it regardless, and a reader in SD-boot mode should not read our flash-boot findings as excluding them.

**Which makes the §2.1 toggle a single-variable experiment, retroactively.** Disabling boot-time access removes flash boot, and flash boot on this board does exactly two things: the ROM reads the flash, and the image it loads prints one line and loops. The second cannot reach the card. So the toggle that turned the fault off and on was only ever changing one thing that touches P58–P61 — the ROM's flash reads. That was true when the experiment ran; it could not be *known* until the contents of the flash image were established, which is why this was recorded as an open question for as long as it was.

**Why the surviving mechanism is also the plausible one.** Elimination says the ROM's flash traffic is what remains; three further arguments say it is what one would expect. They are reasoning, not measurement, and are offered as such.

*No ROM defect is required.* The ROM is not addressing the card. It is driving an SPI flash correctly, and the card is an unwitting bystander on the same four pins, mis-parsing traffic never sent to it. There is no unterminated command from the ROM's point of view.

*The alternative would require one.* For an abandoned SD read to be the cause, the boot ROM would have to leave a card transaction open. On the SD-boot success path it cannot: the ROM boots from the card and then hands control to user code that will want to use it, so a ROM that left the card wedged would break every SD-boot application. That path must terminate cleanly, or SD boot would not work at all.

*The incidence fits.* Two of twenty-six cards. The flash-traffic mechanism predicts that shape — the traffic reaches every card, and only silicon that mishandles a chip select it ought to be ignoring is caught, which is why it is the two counterfeit parts and no mainstream one. A ROM mishandling card transactions would predict the opposite: broad failure across cards on SD-boot boards, which is not reported anywhere.

**This widens the exposure rather than narrowing it.** Had the resident program been the actor, the condition would have been an artifact of one board's flash contents. It is not. The traffic comes from the ROM doing what it does on every reset, which means **every P2 Edge board booting from flash meets condition 2 of §1**, regardless of what its flash contains — and, by the paragraph above, so does every Edge board booting from the card.

### 4.4 The mechanism accounts for the results that resisted every earlier explanation

| Observation | Accounted for by |
|---|---|
| A reset is necessary, but pin float and download duration are both eliminated | The third effect of a reset is running the boot sequence |
| A driver session is required; a null binary is clean | The card must have been left in a transfer-capable state for boot traffic to catch it mid-stream |
| `initCardOnly()` alone arms it | Nothing above card initialization is involved |
| 120 s of powered idle changes nothing | The state is a protocol state, not a housekeeping backlog |
| In-binary cycles stay clean; reset-separated sessions wedge | No reset means no boot sequence between them |
| **102,400 clocks in either CS polarity recovered nothing** | **A multiple-block read continues until it is told to stop. Additional clocking fed the stream.** The recovery ladder never sent the one command that reaches a card in that state |
| **The onboard socket fails and the external socket never does** | **The external header is on P18–P21, ordinary GPIO with no boot-ROM role. The onboard socket is on P58–P61, which are the boot pins** |

The socket asymmetry is a pin-assignment property, not an electrical-margin property.

---

## 5. Superseded conclusions

Each of these was recorded in the repository and is now known wrong. They are listed because a reader may hold one, or may be about to reach it independently.

| # | Conclusion | Prediction it made | What refuted it |
|---|---|---|---|
| T1 | Reflections / signal integrity on short onboard traces | Slower SCK or slower slew should help | ~336 write cells across four cards and three frequencies spanning the operating range: no wedge (rounds 5–6) |
| T2 | The idle window between mailbox commands lets the card drift | Inserting settle time should help | Suite-level reproduction persisted regardless; refuted outright by 13b |
| T3 | Single-block write packaging; the card mishandles CMD24 | Routing writes through CMD25 should fix it | Raw single-sector writes never wedge; the trigger is not in the write path (round 5, Finding 1) |
| T4 | Card garbage collection; the driver's busy-poll gives up too early | Waiting longer should help | 120 s of powered idle changes nothing (13b) |
| T5 | Pin float at reset; a card latched in SPI mode misreads floating CS | Floating the pins should reproduce it | 8/8 clean floating all four pins for 1,200 ms after a driver session (14c); 2/2 clean floating before one (13a) |
| T6 | The two deliberately-wrong-pin `mount()` calls in the test suite | Removing that prefix should fix it | Those calls execute identically in four clean cold runs (12a) |
| T7 | Crossing a binary boundary | A single looping binary should be clean | True but not causal — the fault fires at test #13 inside one binary (12a) |

### 5.0 The `-7` that was read as intermittent

**Correction:** the `-7` at step #13 of the reproducer was recorded as intermittent for three months. It is not intermittent. Split by condition it is exact — every warm run returns `-7`, every cold run returns `0`. The uncontrolled variable was whether the board had been power-cycled before the run, and nobody was tracking it.

### 5.1 T1 — and the instrument that had never failed

The socket asymmetry was real and required an explanation. The one recorded in May was that a long external cable is a lossy transmission line whose series resistance and distributed capacitance round the edges and absorb reflections, while a short unterminated PCB trace reflects every edge, and a reflection that recrosses the logic threshold is counted by the card's clock-driven state machine as one extra clock.

**Correction:** the explanation was wrong. A write probe swept SPI clock and write pad across the wedging card, in the wedging socket, at three frequencies covering its range, including the second write where the fault was believed to bite. Result: 165 cells, all pass, no wedge.

**Pitfall:** across round 5 the probe ran roughly 336 write cells on four cards of two families and produced zero `WRITE_ERR`, zero `READBACK_ERR`, zero `DATA_MISMATCH` and zero wedges. Every defined failure mode was unreached. **An instrument that has never failed is not yet known to be capable of failing**, and its green results are not yet evidence. Two deliberately-broken cells were run to establish that the detection paths fire:

```
1) wrong-expectation compare reports mismatch:   INSTRUMENT PASS
2) absurd-LBA write returns error (status=-7):   INSTRUMENT PASS
SELFTEST VERDICT: detection paths PROVEN -- green grids are evidence
```

Only after that did the 336 cells become evidence, and T1 and T3 fall together.

### 5.2 T4 — the cheapest hypothesis

These cards are documented as re-busying themselves after CS deassert for internal housekeeping, and the driver's init busy-poll gives up after approximately two seconds. The hypothesis was plausible and would have been fixable in an afternoon.

It was tested with a P2-timed 120-second hold, verified in its own transcript (`ARM: HOLD_120S -- idling 120 s before exit`, ticking `idle 10 s of 120`). The card still wedged.

**Pitfall:** the hypothesis that would be cheapest to fix warrants the earliest and hardest test, because the cost of the fix is not evidence for the diagnosis.

### 5.3 T3 — a workaround that would have shipped

In late May an experiment sequence concluded that consecutive single-block writes wedged the card while a multi-block CMD25 pair with count=2 succeeded, and that the fault was specific to single-block packaging. A workaround was designed: route single-block writes through CMD25 for cards in the dummy-CRC class. Both card records were amended to say so and both cards were marked *supported on the External SD header only*, pending that workaround.

**Correction:** raw single-block writes do not wedge these cards at all (round 5). The workaround was never implemented. Had it shipped, it would have added a permanent card-class special case to the write path, would have appeared to work — the reproducer that motivated it always began with a mount and a reset, which is where the trigger lives — and would have left the fault in place.

**Pitfall:** a workaround not tied to a proven mechanism will frequently pass its own test, because the test was constructed from the same misunderstanding.

---

## 6. The fix

`initCard()` issues CMD12 before CMD0, unconditionally, on every driver start, on every card. In `src/micro_sd_fat32_fs.spin2` as step 3.9 — after the recovery flush and smart-pin setup, immediately ahead of CMD0:

```spin2
  cmd(CMD12, 0)
  pinh(cs)                              ' deselect
  sp_transfer_8($FF)                    ' NCS recovery clocks (SD spec)
  waitms(CMD_RETRY_DELAY_MS)
```

**Cost:** one command at 400 kHz plus a 10 ms settle, once per driver start. Steady-state operation is unchanged.

### 6.1 Why the command is unconditional

Three gating strategies were considered and rejected.

- **Gating on detection of the fault** is impossible. A wedged card cannot be identified because it answers nothing; the condition is visible only after init has already failed.
- **Gating on the card** is wrong-targeted. The trigger is the board, not the card. A card that has never wedged on our bench may wedge on a board whose boot behavior differs.
- **Gating on a build switch** does not reach the affected user. A user who needs it is by definition a user whose card will not mount. This was made an explicit release condition for v1.8.0.

Sending CMD12 to an idle card is harmless: there is no transfer to stop, the card returns a status with an error bit set, and our driver ignores it. There is no state to get wrong, which is what qualifies the command to precede CMD0 on every card on every start.

### 6.2 Certification

**Controlled demonstration.** Boot-time access remained enabled throughout — switches in the wedging configuration, flash banner present in every transcript. The fix build and the unmodified build were interleaved on the same card with no power cycle between them.

| | Pair 1 | Pair 2 |
|---|---|---|
| With CMD12, cold | 43/43 | 43/43 |
| With CMD12, warm | **43/43 clean** | **43/43 clean** |
| With CMD12, warm again | — | **43/43 clean** |
| **Unmodified, warm (control)** | **19/24 wedged**, `-7`/`-8` | **19/24 wedged**, `-7`/`-8` |

Five clean warm runs across two power cycles. In both pairs the unmodified build ran warm immediately afterwards on the same card without a power cycle, and wedged. The card demonstrably retained the capacity to wedge during the same session, minutes after each clean run; the only variable was the presence of one command.

**Limitation:** the two builds were not distinguishable from the captured logs. They differed by 20 bytes, and the transcript recorded neither the size nor any marker separating them — the debug line that would have done so uses a channel the test suite compiles out. The result rests entirely on the interleaved controls above, which is strong, but it should not have had to. The step now prints unconditionally while it remains under observation. Recorded because a reader auditing this evidence would otherwise have to establish it independently.

**Whole-suite certification.** 27 suites, 534/534, closing filesystem audit 23/23 clean, on a mainstream card in the onboard socket. Since the command is unconditional, every mount in that run exercised it. The purpose of the run is not the fault but the absence of collateral effect on cards that never had it.

**The wedging card, full suite, in the socket where it wedges.** Lerdisk `$0000_01F4` ran `SD_RT_mount_tests` 45/45 and `SD_RT_raw_sector_tests` 14/14 in the onboard socket — the two-suite sequence that had been the reproducer since May.

**Both twins on the fixed build.** Cloudisk `$0000_1680` returned 45/45 and 14/14 across four warm runs and two power cycles; the uncatalogued second Cloudisk `$0001_9B39` was clean on the same protocol. Boot configuration remained in the wedging state, with the flash banner verified present in all twelve transcripts.

---

## 7. Limitations

**Limitation:** the strength of the evidence differs by card, and the difference is worth stating rather than averaging.

| Card | What establishes it would have wedged | |
|---|---|---|
| Lerdisk `$0000_01F4` | the interleaved controls of §6.2 — the unfixed build run on the same card, minutes later, in the same session | strongest |
| Cloudisk `$0000_1680` | wedged 19/24 under the reproducer before the fix, clean 45/45 across four warm runs and two power cycles after it, with the boot configuration verified armed on both occasions | strong |
| Cloudisk `$0001_9B39` | silicon identity with the two above: same PNM, MID and PRV, same `$00` CRC7 anomaly, same `CW_NO_DATA_CRC` flag, manufactured the same month | weakest |

The third card was never put through the reproducer before the fix. Its earlier appearances were a read-only frequency sweep and a write probe, and round 5 established that the write probe does not reproduce this fault on any card, including the proven wedger. So the missing "before" is a gap in what was run, not an observation that the card behaves differently.

One residual applies to `$0000_1680`: the driver gained more than the quiesce between its pre-fix and post-fix runs, so its before/after establishes that *this build* does not wedge it. Attributing that to the quiesce specifically rests on the Lerdisk's same-session control and on the mechanism in §4.3.

A same-session control arm remains buildable at any time — the quiesce is one call at `initCard()` step 3.9, and a scratch build with it commented out gives a true single-variable comparison. It is not recorded here as owed work, because a third instance of one controller design would test the mechanism no further than the first two did. What is missing from this report is not another card of this class; it is a wedging card of a *different* class, and that is the limitation below.

**Limitation:** the boot-time traffic has not been captured. The mechanism in §4.2 is inferred from the pin-role table and the behavioral evidence, not observed on a wire. The Edge module's socket has no exposed test points, and a logic analyzer can attach only to the external header, which is the side that does not fail. The card controller's actual state — mid-read, mid-write, or a state a conforming card would not enter — is unknown; what is known is that CMD12 is what leaves it.

**Limitation:** the clock-line arithmetic is not demonstrated step by step. Because the roles are exchanged, the card's clock line is the flash's chip select, which toggles once per flash transaction rather than once per flash bit. The card therefore sees approximately one clock edge per flash SPI transaction while its own chip select is driven at flash bit rate with flash command and address bits on its data-in line. Over a full boot that is a large number of edges accompanied by arbitrary data, which is why it is considered sufficient. How a card walks from that into a transfer state it will not leave has not been demonstrated. What is demonstrated is the input-output pair: removing the boot-time traffic stops the fault, and sending the specification's transfer-abort command stops the fault. If the intermediate state proves to be other than an unterminated read, the fix is unaffected and §4.2 requires amendment.

**Limitation:** incidence is not characterized. Two of twenty-six cards. Whether a conforming card can be driven into this state by the same traffic is unknown. The claim is the mechanism and the fix, not the incidence.

---

## 8. Procedure — diagnosing this on other hardware

You need neither our cards nor our suites.

**Step 1. Establish the cold/warm split.** Power the board down completely; a serial-download reset does not drop the card's supply rail. Power up, run one program that mounts the card and exits. Then, without removing power, run it again. If run 1 is clean and run 2 returns `E_NO_CARD` on a card that is physically present, you have this condition. If both are clean or both fail, you have something else.

**Step 2. Determine whether the card's pins are shared.** Inspect your board's schematic for other functions on the card's four SPI pins; boot flash is the common case. On the P2 Edge that is P58–P61, with CK and CS exchanged between the flash and microSD roles. A socket on ordinary GPIO — the external header on P18–P21 — is not exposed.

**Step 3. Confirm by removing boot-time access.** If your board can disable flash and SD boot — on a P2 Edge, pulling P59 up, which is switch 3 on the four-position DIP with switch 2 off — the warm run should become clean, and should wedge again when you restore the setting. **Run it in both directions.** One direction cannot distinguish a fix from a quiet day.

**Step 4. Do not pursue software recovery.** Additional clocking does not help in either CS polarity at any count (§2.4). Elapsed time does not help. For a card in a transfer state, CMD12 is the only command that reaches it.

If you are writing your own driver: send CMD12 before CMD0 in your init sequence and ignore its response. That is the entire fix.

---

## 9. Method notes

Recorded because they governed which results were admissible.

**Measure in the state that ships.** This campaign produced two conclusions that inverted when re-measured in the shipping state. A measurement that reaches its target by a shortcut states which state it was taken in, or it does not count.

**Establish that an instrument can fail before trusting that it passed.** §5.1.

**Interleave controls.** For an intermittent fault, a fix followed by clean runs establishes nothing. A fix followed by clean runs *and* a same-session unmodified build that still fails establishes that the card could have failed and did not.

**"Always observed" is not "tested."** For three months, *only a power cycle clears it* described the two actions anyone had happened to try. Tested as a claim, the manner of its failure became the most confirming single result available (§4.3).

**Record contradictions unresolved.** After round 14 the condition required a reset while both known card-visible effects of a reset were eliminated. Recording that as an open contradiction, rather than resolving it in prose, is what identified the boot ROM as the remaining variable.

---

## 10. Sources

| Document | Where |
|---|---|
| `src/micro_sd_fat32_fs.spin2`, `initCard()` step 3.9 | The driver. The fix, with the mechanism recorded in a comment at the call site |
| `DOCs/cards/lerdisk-asdfg-1gb.md`, `DOCs/cards/cloudisk-asdfg-2gb.md` | In the repository. Per-card register dumps and test history for the two twins |
| SD Physical Layer Simplified Specification v9.10 | Spec sections 4.3, 7.2.3 and 7.2.8. Published by the SD Association |
| P2 Hardware Manual, boot pattern selection | `P59 = up` — the switch setting used in §2.1 |

The blow-by-blow record — the May–June forensic log, the August round-by-round bench notes, and the transcripts each result came from — is retained in the project repository. It is unedited working material, carrying bench shorthand and superseded conclusions left standing as history, so this report treats it as provenance rather than as reading. What is worth taking from it is here.

If you have questions about what I have written here, file an issue and I will respond with edits to this document to make it clearer. Corrections are welcome too — particularly if you can attribute the boot-time traffic to the ROM or to a resident program on your own hardware, or if you have seen a conforming card enter this state.

Thanks for Reading, following along.
