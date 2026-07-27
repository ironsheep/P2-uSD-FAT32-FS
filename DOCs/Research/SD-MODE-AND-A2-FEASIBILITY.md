# Research: SD 4-Bit Mode and A2 Application Performance Class Feasibility

**Date**: Feb 28, 2026
**Context**: The current P2 uSD driver uses SPI mode (4 wires: CLK, CS, MOSI, MISO). This document examines what performance and feature gains are available by adding native SD mode with the 4-bit data bus (6 wires: CLK, CMD, DAT0-DAT3), and whether A2 Application Performance Class features are accessible and beneficial.

**Source Material**: SD Physical Layer Simplified Specification Version 9.10 (local copy in DOCs/Specs/)

---

## 1. Current State: SPI Mode

### What We Have

SPI mode uses 4 wires with a single data line in each direction:

| Wire | SPI Function | Direction |
|------|-------------|-----------|
| CLK (SCK) | Clock | Host -> Card |
| CS | Chip Select (active low) | Host -> Card |
| MOSI (DI) | Data In to card | Host -> Card |
| MISO (DO) | Data Out from card | Card -> Host |

Data transfer is 1-bit serial in each direction. The maximum clock frequency in SPI mode is **25 MHz** at Default Speed (3.3V), or **50 MHz** if CMD6 High Speed switching succeeds. Our driver currently runs at 25 MHz.

### SPI Mode Limitations (per SD Spec Section 7.1)

The spec is explicit about SPI mode's second-class status:

> "The advantage of the SPI mode is the capability of using an off-the-shelf host, hence reducing the design-in effort to minimum. The disadvantage is the loss of performance of the SPI mode versus SD mode (e.g. Single data line and hardware CS signal per card)."

Key limitations:

1. **Commands defined after SD Spec v2.00 are not supported** (Section 7.1): "The commands and functions in SD mode defined after the Version 2.00 are not supported in SPI mode."
2. **UHS-I is not available** (Section 3.9): "UHS-I is provided in SD mode but not in SPI mode." This locks out SDR50 (100 MHz), SDR104 (208 MHz), and DDR50.
3. **Speed Class cannot be guaranteed** (Section 7.2.15): "The card cannot guarantee its Speed Class. In SPI mode, host shall treat the card as Class 0."
4. **Command classes 1, 3, and 9 are not supported** in SPI mode (Section 7.3.1.2).
5. **SDUC cards do not support SPI mode at all** (Section 7.1).
6. **1.8V signaling is not accessible** -- once a card enters 1.8V signaling, it cannot switch to SPI mode.

### Current Measured Performance (25 MHz SPI, 350 MHz sysclk)

From our benchmark data across 15 cards:

| Metric | Best Card | Throughput |
|--------|-----------|------------|
| Raw single-sector read | Samsung PRO Endurance | 1,283 KB/s |
| Raw multi-sector read (CMD18, 64 sectors) | Samsung PRO Endurance | 2,427 KB/s |
| Raw multi-sector write (CMD25, 64 sectors) | Samsung PRO Endurance | 2,319 KB/s |
| File-level read (handle API) | Lexar Blue 128GB | 1,444 KB/s |
| File-level write (handle API) | Amazon Basics 64GB | 774 KB/s |

**Theoretical SPI ceiling**: 25 MHz x 1 bit = 25 Mbit/s = 3,125 KB/s. Our best multi-sector reads reach 2,427 KB/s (78% of theoretical), meaning we are already extracting most of the bandwidth available in SPI mode.

---

## 2. What SD 4-Bit Mode Provides

### The 6-Wire Interface

SD native mode uses a different pin mapping from SPI. The microSD card has the same physical contacts, but the signals change:

| Pin | SD Mode | SPI Mode | Notes |
|-----|---------|----------|-------|
| 1 | DAT2 | CS | Repurposed |
| 2 | CMD | MOSI (DI) | Bidirectional command/response in SD mode |
| 3 | VSS | VSS | Ground |
| 4 | VDD | VDD | Power |
| 5 | CLK | CLK | Same function |
| 6 | VSS | VSS | Ground |
| 7 | DAT0 | MISO (DO) | Data line 0 (primary) |
| 8 | DAT1 | unused | Additional data line |
| 9 | DAT3 | unused | Additional data line (also card detect in SD mode) |

The active signal wires for SD 4-bit mode are: **CLK, CMD, DAT0, DAT1, DAT2, DAT3** -- 6 wires.

### Data Transfer Rates

In SD 4-bit mode, data travels on 4 parallel data lines (DAT0-DAT3) simultaneously:

| Bus Speed Mode | Clock | Data Lines | Max Throughput | Voltage |
|----------------|-------|------------|----------------|---------|
| **SPI mode** | 25 MHz | 1 | **3.1 MB/s** | 3.3V |
| SPI High Speed | 50 MHz | 1 | 6.3 MB/s | 3.3V |
| **SD Default Speed (DS)** | 25 MHz | 4 | **12.5 MB/s** | 3.3V |
| **SD High Speed (HS)** | 50 MHz | 4 | **25 MB/s** | 3.3V |
| SD SDR12 | 25 MHz | 4 | 12.5 MB/s | 1.8V |
| SD SDR25 | 50 MHz | 4 | 25 MB/s | 1.8V |
| SD SDR50 | 100 MHz | 4 | 50 MB/s | 1.8V |
| SD SDR104 | 208 MHz | 4 | 104 MB/s | 1.8V |
| SD DDR50 | 50 MHz | 4 | 50 MB/s | 1.8V |

**Key comparison**: At the same 25 MHz clock, SD 4-bit mode provides **4x the raw bandwidth** of SPI mode (12.5 MB/s vs 3.1 MB/s). At High Speed (50 MHz), the gap widens to **8x** (25 MB/s vs 3.1 MB/s).

### SD Mode Protocol Differences

The SD native protocol differs significantly from SPI:

**Command/Response**:
- SPI: Commands on MOSI, responses on MISO (byte-oriented, R1 is 1 byte)
- SD: Commands on CMD line, responses on CMD line (bit-oriented, R1 is 48 bits with CRC7)
- SD mode uses relative card addresses (RCA) assigned during initialization

**Data Transfer**:
- SPI: Data on MOSI (write) or MISO (read), 1 bit at a time
- SD: Data on DAT0-DAT3 in parallel (4-bit mode) or DAT0 only (1-bit mode)
- SD mode uses start/end bit framing on each data line, plus per-line CRC16

**Busy Signaling**:
- SPI: Card holds MISO low while busy
- SD: Card holds DAT0 low while busy

**Initialization Sequence**:
- SPI: CS low during CMD0 selects SPI mode (irreversible until power cycle)
- SD: CS high during CMD0 (or CMD0 not issued with CS asserted) keeps SD mode
- SD mode adds CMD2 (ALL_SEND_CID), CMD3 (SEND_RELATIVE_ADDR) for enumeration

### SD 1-Bit Mode

SD mode also supports a 1-bit variant (data on DAT0 only), selected by issuing ACMD6 with bus width = 1. This provides the SD protocol benefits (full command set, proper response format) without requiring all 4 data lines. However, throughput is the same as SPI mode (1 bit per clock). The primary use case would be as a stepping stone: implement the SD protocol first on 1 data line, then add 4-bit support.

---

## 3. A2 Application Performance Class

### A1 vs A2 (SD Spec Section 3.11)

| Parameter | A1 | A2 |
|-----------|----|----|
| Random Read | 1,500 IOPS (min) | 4,000 IOPS (min) |
| Random Write | 500 IOPS (min) | 2,000 IOPS (min) |
| Sequential Write | 10 MB/s (min) | 10 MB/s (min) |
| Command Queue required | No | Yes (mandatory for non-Express/non-SDUC) |
| Cache required | No | Yes |
| Introduced in | SD Spec 5.1 | SD Spec 6.0 |

A2's higher random IOPS numbers are achieved through two card-internal features that the host must explicitly enable:

### 3.1 Cache (SD Spec Section 4.17)

Cache allows the card to acknowledge writes faster by initially storing data in volatile fast memory (likely SRAM or SLC NAND) before committing to the main TLC/QLC NAND:

- **Transparent to host** -- card decides which data goes into cache
- **Host must enable** -- via Performance Enhancement Function Register Byte[4]
- **Host must flush before power-off** -- `Flush Cache` via Performance Enhancement Function Register Byte[261] bit[0]='1', or data loss occurs
- **Flush takes up to 1 second** -- card signals busy on DAT0 during flush
- **Power Off Notification required** -- card must support it when cache is enabled

Cache is controlled through **CMD6 (SWITCH)** using Function Group 1 to write the Performance Enhancement Function Register. CMD6 IS available in SPI mode (Section 7.2.13 confirms "Same as for SD mode with two exceptions" -- both exceptions are about timing, not availability). However, the flush operation signals busy on DAT0, which in SPI mode would be the MISO line held low.

### 3.2 Command Queuing (SD Spec Section 4.19)

Command Queuing (CQ) allows multiple read/write tasks to be submitted to the card before execution, letting the card's internal controller reorder operations for optimal flash access:

- **CMD44** -- Define block count and direction (read/write) for a task
- **CMD45** -- Define start address for a task
- **CMD46** -- Execute a read task (card selects which queued task is ready)
- **CMD47** -- Execute a write task

CQ separates the *submission* phase (telling the card what to do) from the *execution* phase (actually transferring data). The card can reorder tasks internally to minimize flash seek time.

**CQ commands (CMD43-CMD47) are post-v2.00 SD commands.** Per Section 7.1, these are **not available in SPI mode**. This is the fundamental barrier.

Two CQ modes exist:
- **Voluntary CQ Mode**: Card can reorder tasks. A2 performance is guaranteed only in this mode.
- **Sequential CQ Mode**: Tasks execute in submission order. Used for sequential pre-conditioning.

### 3.3 Can A2 Features Be Used Over SPI?

| Feature | Available in SPI Mode? | Why / Why Not |
|---------|:---------------------:|---------------|
| Cache enable | Possibly | CMD6 works in SPI mode; register writes may succeed |
| Cache flush | Possibly | CMD6 works in SPI mode; busy signaling differs (MISO held low) |
| Command Queuing (CMD43-47) | **No** | Post-v2.00 commands; explicitly excluded from SPI mode |
| Power Off Notification | **No** | CMD48/CMD49 extension commands; post-v2.00 |
| UHS-I speed modes | **No** | Requires 1.8V signaling and SD mode |

**Bottom line**: The marquee A2 feature -- Command Queuing -- is **not accessible in SPI mode**. Cache *might* be partially accessible via CMD6, but without proper Power Off Notification (which is required when cache is enabled), using it risks data loss. Even if cache could be enabled, A2 performance numbers are specified with CQ enabled. Without CQ, the card falls back to A1-level performance.

### 3.4 Passive A2 Benefits Over SPI

Even without explicit A2 host support, an A2-rated card may provide some passive benefits:

1. **Better flash controller**: A2 cards have faster internal controllers to meet the IOPS requirements. This can reduce card-internal latency for any operation, including SPI transfers.
2. **Faster random access**: The card's internal flash management is optimized for random I/O patterns regardless of the bus protocol.
3. **Better wear leveling**: Higher-end controllers tend to have more sophisticated garbage collection and wear leveling.

Our benchmark data provides anecdotal evidence: several A2-rated cards (Lexar Blue 128GB, Amazon Basics 64GB) are among our top performers even over SPI. However, this likely reflects overall controller quality rather than A2-specific features.

---

## 4. What SD 4-Bit Mode Would Enable

Switching from SPI to SD 4-bit mode unlocks multiple tiers of improvement:

### 4.1 Immediate Throughput Gain: 4x Data Bus Width

At our current 25 MHz clock, SD 4-bit mode provides 4 bits per clock vs 1 bit:

| Metric | SPI (current) | SD 4-bit (projected) | Gain |
|--------|:-------------:|:--------------------:|:----:|
| Theoretical max | 3,125 KB/s | 12,500 KB/s | **4x** |
| Projected multi-sector read | ~2,400 KB/s | ~9,600 KB/s | **~4x** |
| Projected file-level read | ~1,400 KB/s | ~4,000-5,000 KB/s | **~3-4x** |

File-level gains will be less than 4x because filesystem overhead (FAT lookups, directory traversal) becomes a larger fraction of total time when raw transfer is 4x faster.

### 4.2 High Speed Mode: 50 MHz Clock

CMD6 switching to High Speed mode provides 50 MHz clock in SD mode (vs 25 MHz default):

| Metric | SPI 25 MHz | SD 4-bit 25 MHz | SD 4-bit 50 MHz | Gain vs SPI |
|--------|:----------:|:---------------:|:---------------:|:-----------:|
| Theoretical max | 3,125 KB/s | 12,500 KB/s | 25,000 KB/s | **8x** |

Our driver already supports CMD6 for high-speed switching. In SD mode, the same CMD6 call activates 50 MHz clocking with 4 data lines.

### 4.3 Full Command Set Access

SD mode unlocks the complete command set, including all post-v2.00 commands:

- **Command Queuing** (CMD43-47): Enables A2 performance levels
- **Cache control**: Safe cache enable/flush with proper Power Off Notification
- **ACMD6**: Bus width selection (1-bit to 4-bit)
- **Speed Class**: Card can guarantee its rated speed class
- **SDUC support**: Cards >2TB would become accessible (future-proofing)

### 4.4 A2 Feature Availability

With SD 4-bit mode, the full A2 feature set becomes available. **Yes, A2 is fully accessible over SD 4-bit mode.** All A2-related commands (CMD43-47 for Command Queuing, CMD6 for Cache and Power Off Notification) are native SD mode commands with no restrictions in 4-bit operation.

---

## 5. SD 4-Bit Mode: With A2 vs Without A2

This is the key comparison. Once we have SD 4-bit mode, what does enabling A2 features actually change?

### 5.1 SD 4-Bit Mode WITHOUT A2 Features

This is vanilla SD 4-bit mode -- the same command set we use today in SPI (CMD17, CMD18, CMD24, CMD25, etc.) but running on 4 data lines instead of 1. The host issues one command at a time, waits for the card to complete it, then issues the next.

**Sequential file read (e.g., reading a 256 KB file):**
```
CMD18 (READ_MULTIPLE) -> card streams sectors on DAT0-DAT3 -> CMD12 (STOP)
```
Each sector: host waits for start bit, receives 512 bytes on 4 lines (~41 us at 25 MHz), verifies CRC16 on each line. Card controls pacing -- if it needs time to fetch the next sector from flash, it delays the start bit.

**Sequential file write (e.g., writing a 32 KB file):**
```
CMD25 (WRITE_MULTIPLE) -> host streams sectors on DAT0-DAT3 -> stop token
```
Each sector: host sends 512 bytes on 4 lines (~41 us), card responds with CRC status on DAT0, then holds DAT0 low (busy) while programming flash. Host waits for busy to clear before sending next sector.

**Random access (e.g., reading 100 scattered 4 KB blocks):**
```
For each block:
  CMD18 -> receive 8 sectors -> CMD12
  (wait for card to locate next block in flash)
  CMD18 -> receive 8 sectors -> CMD12
  ...repeat 100 times
```
Each command round-trip includes: command transmission, card internal seek time (flash page lookup, possible garbage collection), data transfer, stop. The card processes these strictly one at a time.

### 5.2 SD 4-Bit Mode WITH A2 Features (Cache + Command Queuing)

**Cache** changes write behavior. When enabled, the card can acknowledge a write immediately after receiving the data into fast volatile memory (SRAM or SLC buffer), *before* committing to main NAND. This dramatically reduces the per-write busy time:

| Write Scenario | Without Cache | With Cache |
|----------------|:------------:|:----------:|
| Single sector write busy time | 2-15 ms (flash program) | ~0.1-1 ms (SRAM accept) |
| Burst of small writes | Each waits for flash commit | Card pipelines to SRAM, commits in background |
| Power-off safety | Data safe immediately | **Must flush before power-off or data is lost** |

**Command Queuing** changes the entire I/O model. Instead of one-command-at-a-time, the host submits a batch of tasks, then lets the card execute them in whatever order its flash controller prefers:

**Random access WITH CQ (same 100 scattered 4 KB blocks):**
```
Submit phase:
  CMD44+CMD45: task 0 = read 8 sectors at address A
  CMD44+CMD45: task 1 = read 8 sectors at address B
  CMD44+CMD45: task 2 = read 8 sectors at address C
  ... (up to card's queue depth, typically 2-32 tasks)

Execute phase:
  CMD46: card picks whichever queued task is ready first
  -> receive 8 sectors
  CMD46: card picks next ready task
  -> receive 8 sectors
  ...
```

The card's flash controller can reorder the queued reads to minimize internal seek time. If tasks 0, 5, and 12 happen to be in the same flash erase block, the card executes them consecutively rather than in submission order.

### 5.3 Direct Behavioral Comparison

| Behavior | SD 4-bit (no A2) | SD 4-bit (with A2) |
|----------|:----------------:|:------------------:|
| **Sequential read throughput** | ~10-12 MB/s (25 MHz) | ~10-12 MB/s (same -- CQ doesn't help here) |
| **Sequential write throughput** | ~5-10 MB/s (card-limited) | ~8-12 MB/s (cache absorbs, fewer busy stalls) |
| **Random read IOPS (4 KB)** | ~200-500 IOPS | **~4,000 IOPS** (card reorders flash accesses) |
| **Random write IOPS (4 KB)** | ~50-200 IOPS | **~2,000 IOPS** (cache + reorder) |
| **Write burst tolerance** | Each write blocks until flash commits | Card buffers writes, commits in background |
| **Power-off behavior** | Data safe after busy clears | **Must flush cache first** or risk data loss |
| **Host complexity** | Same as current (one command at a time) | Task queue management, ready-task polling, flush logic |
| **Card compatibility** | All SD cards | Only A2-rated cards (mandatory CQ support) |

### 5.4 Where A2 Matters and Where It Doesn't

**A2 matters for:**
- Applications doing many small random reads/writes (database-style access patterns)
- Workloads with bursty writes (sensor data arriving in irregular patterns)
- Applications where write latency variation is problematic (real-time logging with tight deadlines)

**A2 does NOT matter for:**
- Sequential file reads (streaming data from a file) -- already bus-limited, not seek-limited
- Sequential file writes (data logging in append mode) -- CMD25 multi-block is already efficient
- Any workload that is sequential in nature -- the 4-bit bus width is the dominant improvement

For our typical embedded use cases (data logging, configuration file reading, firmware updates), **the 4-bit bus width alone delivers most of the gain**. A2 features would be a second-phase enhancement for applications with random access patterns.

---

## 6. P2 Implementation Considerations

### 6.1 Pin Requirements

SD 4-bit mode needs 6 signal wires vs SPI's 4:

| Signal | P2 Pin | Smart Pin Mode (projected) |
|--------|--------|---------------------------|
| CLK | P61 (current SCK) | `P_TRANSITION | P_OE` (same as now) |
| CMD | P59 (current MOSI) | Bidirectional -- TX for commands, RX for responses |
| DAT0 | P58 (current MISO) | Bidirectional data line |
| DAT1 | new pin | Bidirectional data line |
| DAT2 | P60 (current CS) | Bidirectional data line (also card detect at init) |
| DAT3 | new pin | Bidirectional data line (active-low CS function at init) |

Note: The pin assignments above are illustrative. The actual mapping depends on P2 Edge Module routing and which pins are adjacent for smart pin B-input relationships. The current SPI pin assignment (CS=P60, MOSI=P59, MISO=P58, SCK=P61) would need to be reconsidered since SD mode repurposes CS (pin 1) as DAT3 and MOSI (pin 2) as the bidirectional CMD line.

### 6.2 Streamer Adaptation

The current streamer configuration reads/writes 1 pin at a time (`$C081_0000` for RX, `$8081_0000` for TX -- the `$01` encodes 1-pin width). For 4-bit mode, the streamer would need to transfer 4 pins simultaneously. The P2 streamer supports multi-pin modes -- the pin-count field in the streamer mode word would change from 1 to 4. This is a significant change to the streamer setup but the P2 hardware natively supports it.

### 6.3 CMD Line Protocol

The SD mode CMD line is the most complex change. Unlike SPI where commands go on MOSI and responses come on MISO (separate wires), SD mode uses a single bidirectional CMD line:

1. Host drives CMD line to send a 48-bit command (start bit + transmission bit + 6-bit index + 32-bit argument + CRC7 + end bit)
2. Host releases CMD line
3. Card drives CMD line to send response (48-bit for R1/R3/R6/R7, 136-bit for R2)
4. CRC7 is mandatory in SD mode (in SPI mode, CRC is optional after init)

This requires the P2 to rapidly switch the CMD pin between output and input modes, and to compute CRC7 on every command/response.

### 6.4 CRC Requirements

SD mode has stricter CRC requirements than SPI:

- **Commands**: CRC7 is mandatory (our driver already computes CRC7 for commands)
- **Responses**: CRC7 must be verified (currently optional in SPI mode)
- **Data**: CRC16 on **each** data line independently (4 simultaneous CRC16 calculations for 4-bit mode)

The P2's `GETCRC` instruction can compute one CRC at a time. For 4-bit mode, we would need to either:
- Compute 4 CRC16 values sequentially after the transfer
- Use 4 separate CRC accumulators during the transfer
- Post-process the received data to de-interleave and CRC-check each line

### 6.5 Dual-Mode Driver Architecture

The driver could support both SPI and SD modes, selected at `mount()` time based on which pin configuration the user provides. This preserves backward compatibility:

<!-- api-audit: proposed — mountSD() is a design sketch, not a shipped method -->
```spin2
' SPI mode (4-wire, existing)
sd.mount(CS, MOSI, MISO, SCK)

' SD 4-bit mode (6-wire, new)
sd.mountSD(CLK, CMD, DAT0, DAT1, DAT2, DAT3)
```

Alternatively, a single `mount()` could accept a mode parameter. The internal worker cog would branch on the mode for card initialization and data transfer, sharing all filesystem logic.

---

## 7. Performance Analysis: Where Does the Gain Come From?

### 7.1 Breakdown of Performance Bottlenecks

Our current file-level read of ~1,400 KB/s on the best cards breaks down roughly as:

| Phase | Time Budget (estimated) |
|-------|------------------------|
| SPI data transfer (512 bytes x 8 bits / 25 MHz) | ~164 us per sector |
| Card internal latency (flash read) | ~50-200 us per sector |
| Spin2 overhead (FAT lookup, handle management) | ~50-100 us per sector |
| Multi-sector command setup / inter-sector gaps | ~10-30 us per sector |

With SD 4-bit mode at 25 MHz:

| Phase | Time Budget (estimated) |
|-------|------------------------|
| SD data transfer (512 bytes x 2 bits / 25 MHz) | **~41 us per sector** |
| Card internal latency (flash read) | ~50-200 us per sector (unchanged) |
| Spin2 overhead | ~50-100 us per sector (unchanged) |
| Multi-sector command setup | ~10-30 us per sector (similar) |

The **data transfer time drops by 4x**, but **card latency and Spin2 overhead remain constant**. This means the actual end-to-end improvement depends heavily on the card's internal speed:

- **Fast cards** (low internal latency): closer to 3-4x improvement
- **Slow cards** (high internal latency): closer to 1.5-2x improvement

### 7.2 Feature Tiers and Their Value

| Tier | Feature | Effort | Performance Gain | Complexity |
|------|---------|--------|-----------------|------------|
| 1 | SD 4-bit mode at 25 MHz | High | **~3-4x throughput** | New protocol, new streamer config, 4-line CRC |
| 2 | SD High Speed (50 MHz) | Low (incremental) | **~2x over Tier 1** (~6-8x vs SPI) | CMD6 already implemented, just clock change |
| 3 | Cache enable | Medium | **Faster random writes** | CMD6 register writes, flush-before-power-off logic |
| 4 | Command Queuing | Very High | **2-4x random IOPS** | New command protocol, task management, queue depth tracking |
| 5 | UHS-I (1.8V signaling) | Impractical | **Up to ~33x vs SPI** | Requires 1.8V I/O, voltage switching circuitry on P2 Edge |

### 7.3 Recommendation

**Tier 1 + Tier 2 (SD 4-bit mode with High Speed) delivers the highest return on investment.** This provides 6-8x throughput improvement over current SPI mode with no changes to the filesystem logic -- only the card initialization and sector transfer layers need modification.

**Tier 3 (Cache) is a nice-to-have** for applications doing many small writes. The implementation is moderate (CMD6 register writes) but requires careful power-off handling to prevent data loss.

**Tier 4 (Command Queuing) is high effort and niche benefit.** CQ primarily improves random I/O, which is uncommon in embedded data logging applications. For sequential file reads/writes, the 4-bit data bus is the dominant improvement.

**Tier 5 (UHS-I) is impractical** without hardware modifications to the P2 Edge Module. The P2's I/O pins operate at 3.3V; UHS-I requires 1.8V signaling with a voltage switching sequence.

---

## 8. Summary

| Question | Answer |
|----------|--------|
| Does SPI mode benefit from A2 cards? | Minimally -- better internal controller helps, but A2 features (CQ, Cache) are inaccessible or risky |
| **Is A2 available over SD 4-bit mode?** | **Yes -- fully.** All A2 commands (CMD43-47 for CQ, CMD6 for Cache/Power Off Notification) are native SD mode commands |
| What does SD 4-bit mode gain (without A2)? | **4x raw bandwidth** at same clock speed, full command set, Speed Class guarantees |
| What does A2 add on top of SD 4-bit mode? | **Cache**: faster write acknowledgment (SRAM absorb vs flash commit). **CQ**: 2-4x random IOPS (card reorders flash accesses). Neither helps sequential throughput |
| When does A2 matter over 4-bit mode? | Random access patterns, bursty small writes, latency-sensitive real-time logging. Does NOT matter for sequential file reads/writes |
| What does adding High Speed gain? | Another **2x** over 25 MHz (total ~8x vs current SPI) |
| Is SD 4-bit mode feasible on P2? | Yes -- P2 streamer supports multi-pin modes, smart pins can handle bidirectional CMD line |
| What pins are needed? | 6 signal wires: CLK, CMD, DAT0-DAT3 (vs current 4: CLK, CS, MOSI, MISO) |
| Biggest single performance lever? | **SD 4-bit mode at High Speed (50 MHz)** -- projected ~20+ MB/s raw throughput vs current ~2.4 MB/s |
