# Design Exploration: Multi-Filesystem Architecture

## The Goal

Create unified filesystem drivers that support multiple storage devices:

1. **Combo A**: Flash + microSD (2 devices)
2. **Combo B**: Flash + PSRAM + microSD (3 devices)

Each combo should be a single driver (one `.spin2` file) with a unified API.

---

## Current State: Three Independent Drivers

| Driver | Storage | Interface | Cog Model |
|--------|---------|-----------|-----------|
| P2-FLASH-FileSystem | SPI Flash chip | SPI (dedicated pins) | Dedicated worker cog |
| PSRAM-FileSystem | 32MB PSRAM (Edge EC-32MB) | HyperBus/xSPI | Dedicated worker cog |
| SD-FileSystem | microSD card | SPI (dedicated pins) | Dedicated worker cog (planned) |

---

## Key Observation: All Three Need Pin Ownership

Unlike hub RAM, **PSRAM is external memory** on the P2 Edge module (EC-32MB). It uses a HyperBus or similar high-speed parallel/serial interface with dedicated pins.

**All three storage devices require:**
- Dedicated pin ownership (per-cog DIR/OUT issue)
- Timing-sensitive transfers
- A worker cog to manage the interface

This means the "hybrid" approach where one device bypasses the worker doesn't apply here. All devices need cog-based management.

---

## Architecture Options

### Option 1: One Worker Cog Per SPI Device

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multi-FS Driver (Combo A)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DAT Block (shared singleton)                                    │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │  Flash Worker   │    │   SD Worker     │                     │
│  │  (Cog 2)        │    │   (Cog 3)       │                     │
│  │                 │    │                 │                     │
│  │  flash_pins     │    │   sd_pins       │                     │
│  │  flash_buf[512] │    │   sd_buf[512]   │                     │
│  │  flash_state    │    │   sd_state      │                     │
│  └────────┬────────┘    └────────┬────────┘                     │
│           │                      │                               │
│           └──────────┬───────────┘                               │
│                      │                                           │
│              ┌───────┴───────┐                                   │
│              │  API Layer    │                                   │
│              │  Routes by    │                                   │
│              │  mount point  │                                   │
│              └───────────────┘                                   │
│                                                                  │
│  PUB open("/flash/file.txt") → flash_cmd(CMD_OPEN, ...)         │
│  PUB open("/sd/file.txt")    → sd_cmd(CMD_OPEN, ...)            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Clean separation—each device has its own cog, buffer, state
- Parallel operations possible (Flash read while SD writes)
- Easy to add/remove devices

**Cons:**
- Uses 2 cogs for Combo A, 2 cogs for Combo B
- Duplicate command infrastructure
- More hub RAM (two 512-byte buffers, two stacks)

---

### Option 2: One Worker Cog, Multiple SPI Devices

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multi-FS Driver (Combo A)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DAT Block (shared singleton)                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Unified Worker (Cog 2)                    ││
│  │                                                              ││
│  │   flash_cs ────┐                    ┌──── sd_cs              ││
│  │                │    SHARED SPI BUS  │                        ││
│  │                └───► MOSI/MISO/SCK ◄┘                        ││
│  │                                                              ││
│  │   current_device: FLASH | SD                                 ││
│  │   buf[512]  (shared)                                         ││
│  │                                                              ││
│  │   Command dispatch:                                          ││
│  │     CMD_FLASH_READ  → select flash CS, do read               ││
│  │     CMD_SD_READ     → select SD CS, do read                  ││
│  │                                                              ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  PUB open("/flash/file.txt") → cmd(CMD_FLASH_OPEN, ...)         │
│  PUB open("/sd/file.txt")    → cmd(CMD_SD_OPEN, ...)            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Uses only 1 cog for all SPI devices
- Shared buffer saves RAM
- Single command infrastructure

**Cons:**
- No parallel SPI operations (serialized access)
- More complex worker (must track which device is active)
- Shared bus requires careful CS management
- Different SPI speeds (SD init at 400kHz, Flash at 20MHz)

**Feasibility Note:** This only works if Flash and SD share the same SPI bus (MOSI/MISO/SCK), with different CS pins. If they use completely separate SPI buses (different MOSI/MISO/SCK pins), this option doesn't apply.

---

### Option 3: One Worker Cog for All Three Devices (RECOMMENDED for Combo B)

Since all three devices use SPI, one worker cog can own both SPI buses:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multi-FS Driver (Combo B)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DAT Block (shared singleton)                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Unified Worker (Cog 2)                          ││
│  │                                                              ││
│  │   SPI BUS 1 (shared):     SPI BUS 2 (dedicated):             ││
│  │   ├── flash_cs            └── psram_cs                       ││
│  │   ├── sd_cs                   psram_mosi                     ││
│  │   ├── mosi1                   psram_miso                     ││
│  │   ├── miso1                   psram_sck                      ││
│  │   └── sck1                                                   ││
│  │                                                              ││
│  │   current_device: FLASH | SD | PSRAM                         ││
│  │   buf[512]  (shared)                                         ││
│  │                                                              ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  API Routing:                                                    │
│    "/psram/..." → worker command (SPI bus 2)                     │
│    "/flash/..." → worker command (SPI bus 1)                     │
│    "/sd/..."    → worker command (SPI bus 1)                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Uses only 1 cog for all three devices
- Single API, single command infrastructure
- Same SPI protocol for all devices—maximum code reuse
- Shared buffer saves RAM

**Cons:**
- All operations serialized (no parallel access across buses)
- More pins to manage in one cog

### Option 4: Two Worker Cogs (One Per SPI Bus)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multi-FS Driver (Combo B)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────┐    ┌────────────────────────┐       │
│  │  SPI Worker 1 (Cog 2)  │    │  SPI Worker 2 (Cog 3)  │       │
│  │  ──────────────────    │    │  ───────────────────   │       │
│  │  Owns SPI bus 1 pins   │    │  Owns SPI bus 2 pins   │       │
│  │  Handles Flash + SD    │    │  Handles PSRAM only    │       │
│  │  (shared bus)          │    │  (dedicated bus)       │       │
│  └───────────┬────────────┘    └───────────┬────────────┘       │
│              │                              │                    │
│              └──────────┬───────────────────┘                    │
│                         │                                        │
│                 ┌───────┴───────┐                                │
│                 │  API Layer    │                                │
│                 │  Routes by    │                                │
│                 │  path prefix  │                                │
│                 └───────────────┘                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Parallel operations possible (Flash/SD on bus 1 while PSRAM on bus 2)
- Each worker owns fewer pins
- Could use PSRAM as cache while SD operates

**Cons:**
- Uses 2 cogs
- Two command dispatch infrastructures (though same SPI code)

---

## Physical Wiring Considerations

### Scenario A: Shared SPI Bus (Common)

```
P2
├── Pin 40: MOSI  ────────┬─────────────── Flash MOSI
│                         └─────────────── SD MOSI
├── Pin 41: MISO  ────────┬─────────────── Flash MISO
│                         └─────────────── SD MISO
├── Pin 42: SCK   ────────┬─────────────── Flash SCK
│                         └─────────────── SD SCK
├── Pin 43: Flash_CS ─────────────────────  Flash CS
└── Pin 44: SD_CS    ─────────────────────  SD CS
```

With shared bus, **one worker cog can manage both** by toggling CS pins. Only one device is selected at a time.

### Scenario B: Separate SPI Buses (Less Common)

```
P2
├── Pins 40-43: Flash SPI (MOSI, MISO, SCK, CS)
└── Pins 44-47: SD SPI (MOSI, MISO, SCK, CS)
```

With separate buses, **each device needs its own cog** to own its pins—or you accept that all SPI operations are serialized in one cog that owns all pins.

---

## Recommended Architecture

### Combo A: Flash + microSD (Option 2 - One Worker)

Flash and SD are both SPI devices. They share a single worker cog with a shared SPI bus.

```spin2
' FlashSD_FileSystem.spin2

CON
  DEV_FLASH = 0
  DEV_SD    = 1

DAT
  ' Singleton control
  cog_id        LONG    -1
  api_lock      LONG    -1

  ' Pin configuration (shared SPI bus + separate CS)
  pin_mosi      LONG    0
  pin_miso      LONG    0
  pin_sck       LONG    0
  pin_flash_cs  LONG    0
  pin_sd_cs     LONG    0

  ' Per-device state
  flash_mounted BYTE    0
  sd_mounted    BYTE    0

  ' Shared buffer
  buf           BYTE    0[512]

  ' Handle table
  handle_device   BYTE    0[8]    ' Which device owns this handle
  handle_cluster  LONG    0[8]
  handle_position LONG    0[8]
  handle_size     LONG    0[8]

PUB start(mosi, miso, sck, flash_cs, sd_cs) : result
  '' Start unified filesystem driver (one worker cog)

PUB mount(device) : result
  '' Mount specified device
  '' device: DEV_FLASH or DEV_SD

PUB open(device, path) : handle
  '' Open file on specified device
  '' device: DEV_FLASH or DEV_SD
  '' path: File path relative to device root
  return cmd(device, CMD_OPEN, path)

PUB copy(device, src_path, dst_path) : bytes_copied
  '' Copy file within same device

PUB copy_to(src_dev, src_path, dst_dev, dst_path) : bytes_copied
  '' Copy file between devices
```

### Combo B: Flash + PSRAM + microSD (Option 3 - One Worker)

All three devices use SPI. One worker cog can manage both SPI buses.

```spin2
' FlashPsramSD_FileSystem.spin2

CON
  DEV_FLASH = 0
  DEV_PSRAM = 1
  DEV_SD    = 2

DAT
  ' Singleton control
  cog_id        LONG    -1        ' Single worker cog
  api_lock      LONG    -1

  ' SPI bus 1 pins (Flash + SD share this bus)
  pin_mosi1     LONG    0
  pin_miso1     LONG    0
  pin_sck1      LONG    0
  pin_flash_cs  LONG    0
  pin_sd_cs     LONG    0

  ' SPI bus 2 pins (PSRAM dedicated bus)
  pin_mosi2     LONG    0
  pin_miso2     LONG    0
  pin_sck2      LONG    0
  pin_psram_cs  LONG    0

  ' Per-device state
  flash_mounted BYTE    0
  psram_mounted BYTE    0
  sd_mounted    BYTE    0

  ' Shared buffer
  buf           BYTE    0[512]

  ' Handle table
  handle_device   BYTE    0[8]    ' Which device owns this handle
  handle_cluster  LONG    0[8]    ' Current cluster
  handle_position LONG    0[8]    ' Byte position
  handle_size     LONG    0[8]    ' File size

PUB open(device, path) : handle
  '' Open file on specified device
  '' device: DEV_FLASH, DEV_PSRAM, or DEV_SD
  '' path: File path relative to device root
  return cmd(device, CMD_OPEN, path)

PUB copy_to(src_dev, src_path, dst_dev, dst_path) : bytes_copied
  '' Copy file between devices
  '' Example: fs.copy_to(DEV_SD, "data.log", DEV_FLASH, "backup.log")
  return cmd_copy(src_dev, src_path, dst_dev, dst_path)
```

---

## Handle Table Design

With multiple devices, the handle must encode which device owns it:

```spin2
CON
  MAX_OPEN_FILES = 8

  ' Handle encoding: bits 7:6 = device, bits 5:0 = slot index
  HANDLE_DEVICE_MASK = %1100_0000
  HANDLE_INDEX_MASK  = %0011_1111

DAT
  ' Per-slot tracking
  handle_device   BYTE    0[MAX_OPEN_FILES]   ' Which device
  handle_cluster  LONG    0[MAX_OPEN_FILES]   ' Current cluster
  handle_position LONG    0[MAX_OPEN_FILES]   ' Byte position
  handle_size     LONG    0[MAX_OPEN_FILES]   ' File size
  handle_flags    BYTE    0[MAX_OPEN_FILES]   ' Open mode flags

PRI decode_handle(handle) : device, slot
  device := (handle & HANDLE_DEVICE_MASK) >> 6
  slot := handle & HANDLE_INDEX_MASK
```

---

## Worker Cog Command Routing

```spin2
PRI fs_worker() | cmd, device
  ' Initialize all SPI pins (this cog owns them all)
  pinh(pin_flash_cs)              ' Flash deselected
  pinh(pin_sd_cs)                 ' SD deselected
  pinh(pin_mosi)
  pinl(pin_sck)

  repeat
    repeat until (cmd := pb_cmd) <> CMD_NONE
    device := pb_device           ' Which device this command targets

    ' Select appropriate CS
    case device
      DEV_FLASH: pinl(pin_flash_cs)
      DEV_SD:    pinl(pin_sd_cs)

    ' Execute command
    case cmd
      CMD_READ:  pb_status := do_read(device, ...)
      CMD_WRITE: pb_status := do_write(device, ...)
      ' ... etc ...

    ' Deselect device
    case device
      DEV_FLASH: pinh(pin_flash_cs)
      DEV_SD:    pinh(pin_sd_cs)

    ' Signal completion
    pb_cmd := CMD_NONE
    COGATN(1 << pb_caller)
```

---

## SPI Speed Management

Different devices may need different SPI speeds:

| Device | Init Speed | Operating Speed |
|--------|------------|-----------------|
| SD Card | 400 kHz (required by spec) | 10-25 MHz |
| SPI Flash | N/A | 20-50 MHz |

The worker must adjust `bit_delay` when switching devices:

```spin2
PRI select_device(device)
  case device
    DEV_FLASH:
      bit_delay := flash_bit_delay    ' Fast
      pinl(pin_flash_cs)
    DEV_SD:
      bit_delay := sd_bit_delay       ' May be slower
      pinl(pin_sd_cs)
```

---

## PSRAM Considerations (P2 Edge EC-32MB)

The 32MB PSRAM on the P2 Edge module uses **SPI** (same protocol family as Flash and SD), but on its **own dedicated SPI bus**.

| Characteristic | PSRAM | SPI Flash | SD Card |
|----------------|-------|-----------|---------|
| Interface | SPI (own bus) | SPI (shared bus) | SPI (shared bus) |
| Bus | Dedicated | Shared with SD | Shared with Flash |
| Typical speed | High (dedicated bus) | 10-50 MB/s | 10-25 MB/s |

**Key implications:**
1. All three devices use the same SPI protocol—code reuse possible
2. Flash + SD share one SPI bus (different CS pins)
3. PSRAM has its own SPI bus (separate MOSI/MISO/SCK/CS pins)
4. One worker cog could own ALL pins (both buses), or two workers (one per bus)

### Single Cog vs Two Cogs for Combo B

**Option A: One worker cog owns both SPI buses**
```
Worker Cog owns:
  SPI Bus 1: Flash_CS, SD_CS, MOSI1, MISO1, SCK1
  SPI Bus 2: PSRAM_CS, MOSI2, MISO2, SCK2

All operations serialized through one cog
```
- Pro: Uses only 1 cog
- Con: No parallel operations between buses

**Option B: Two worker cogs (one per bus)**
```
SPI Worker 1: Flash + SD (shared bus)
SPI Worker 2: PSRAM (dedicated bus)

Operations on different buses can run in parallel
```
- Pro: Parallel access possible (read SD while writing PSRAM)
- Con: Uses 2 cogs

**Recommendation**: Start with Option A (one cog). If performance requires parallel access, refactor to Option B.

### PSRAM as Cache Layer (Future Enhancement)

An interesting optimization: use PSRAM as a read cache for SD card data:

```
SD Card (slow, removable)
    ↓
  PSRAM Cache (fast, 32MB)
    ↓
  Application
```

This would allow:
- Fast repeated reads of recently-accessed SD data
- Write buffering for SD operations
- Large directory caches

This is a future enhancement, not part of the initial implementation.

---

## Implementation Complexity

| Combo | Cogs Used | Buffer RAM | Complexity |
|-------|-----------|------------|------------|
| Flash-only | 1 | 512 bytes | Low |
| SD-only | 1 | 512 bytes | Low |
| Flash + SD | 1 | 512 bytes (shared) | Medium |
| Flash + PSRAM + SD | 2 | 1024 bytes (512 each) | Medium-High |

The unified driver complexity scales with the number of protocols:
- **Combo A (Flash + SD)**: One protocol (SPI), one worker, CS pin routing
- **Combo B (Flash + PSRAM + SD)**: Two protocols (SPI + HyperBus), two workers, separate command paths

---

## Device Selection: Enumeration (Not Path Parsing)

**Design Decision**: Use explicit device parameter instead of path prefixes.

### Why Not Path Prefixes?

```spin2
' Path prefix approach (REJECTED):
handle := fs.open("/flash/subdir/file.txt")   ' Must parse "/flash/" prefix
handle := fs.open("/sd/data.bin")              ' String parsing overhead
```

Problems:
- String parsing overhead on every call
- Ambiguity with paths like "/flashdata/file.txt" (is "flashdata" a directory?)
- More complex implementation

### Device Enumeration Approach (ADOPTED)

```spin2
CON
  DEV_FLASH = 0
  DEV_PSRAM = 1
  DEV_SD    = 2

' Clean, explicit device selection:
handle := fs.open(DEV_FLASH, "subdir/file.txt")
handle := fs.open(DEV_SD, "data.bin")
handle := fs.open(DEV_PSRAM, "cache.tmp")
```

Benefits:
- No string parsing for device selection
- Explicit and unambiguous
- Faster (single byte comparison vs string prefix scan)
- Paths are always relative to device root

---

## File Copy Operations

Cross-device file copy is a key use case. The API should support both:

### Same-Device Copy
```spin2
PUB copy(device, src_path, dst_path) : result
  '' Copy file within same device
  '' Example: fs.copy(DEV_SD, "original.txt", "backup.txt")
```

### Cross-Device Copy
```spin2
PUB copy_to(src_device, src_path, dst_device, dst_path) : result
  '' Copy file between devices
  '' Example: fs.copy_to(DEV_SD, "data.log", DEV_FLASH, "archive.log")
  ''          fs.copy_to(DEV_SD, "bigfile.bin", DEV_PSRAM, "cached.bin")
```

### Implementation: No Staging Required

**Key insight**: Even with a single worker cog, we can have files open on multiple devices simultaneously. The worker interleaves operations naturally:

```
Cross-device copy flow (single worker cog):
─────────────────────────────────────────────
1. Open source file on device A      → handle_src (state in memory)
2. Open destination file on device B → handle_dst (state in memory)
3. Loop:
   a. Select device A's CS pin
   b. SPI: Read 512 bytes from source → hub buffer
   c. Deselect device A
   d. Select device B's CS pin
   e. SPI: Write 512 bytes to destination
   f. Deselect device B
4. Close both files
```

**Why no staging is needed:**
- "Open" files are just **software state** (current position, cluster, etc.)
- Switching devices is just asserting a different CS pin
- The SPI bus is available immediately after each transfer
- Both files remain "open" throughout—we're just alternating which device is selected

**Handle table supports multiple devices:**
```spin2
DAT
  ' Handle table - each slot tracks device + file state
  handle_device   BYTE    0[MAX_HANDLES]   ' Which device owns this handle
  handle_cluster  LONG    0[MAX_HANDLES]   ' Current cluster
  handle_position LONG    0[MAX_HANDLES]   ' Byte position in file
  handle_size     LONG    0[MAX_HANDLES]   ' File size
```

With this design, `open(DEV_SD, "a.txt")` and `open(DEV_FLASH, "b.txt")` can coexist—they're just different slots in the same handle table.

**Two-cog architecture bonus**: If using separate cogs per bus, read and write could overlap (read next chunk while writing current chunk). This is an advanced optimization, not required for correctness.

### Buffer Strategy for Copy

```spin2
' Option A: Use driver's internal buffer (512 bytes)
' - Simple, no caller allocation
' - Slower for large files (many round trips)

' Option B: Caller provides buffer
PUB copy_to(src_dev, src, dst_dev, dst, p_buf, buf_size) : bytes_copied
' - Caller controls buffer size (e.g., 4KB for faster copies)
' - More flexible
```

**Recommendation**: Support both—default to internal buffer, optional caller buffer for performance.

---

## Feasibility Assessment

| Question | Answer |
|----------|--------|
| Can one cog manage Flash + SD? | **Yes**, with shared SPI bus and separate CS pins |
| Can one cog manage all three? | **Possible but not recommended** - PSRAM uses different protocol |
| Is two cogs acceptable for Combo B? | **Yes**, still leaves 6 cogs for application |
| Is this more efficient than separate drivers? | **Yes**, reduces cog count and simplifies app code |

---

## Recommendation

1. **Create two unified drivers:**
   - `FlashSD_FileSystem.spin2` — Flash + microSD (1 cog)
   - `FlashPsramSD_FileSystem.spin2` — Flash + PSRAM + microSD (2 cogs)

2. **Architecture:**
   - **Combo A**: One worker cog owns SPI pins (Flash + SD on shared bus)
   - **Combo B**: SPI worker (Flash + SD) + PSRAM worker (HyperBus)
   - Path prefix routing: `/flash/`, `/sd/`, `/psram/`
   - Handle encodes device + slot index

3. **Build incrementally:**
   - First: Get single-device SD driver working with new architecture
   - Second: Add Flash support to same driver (Combo A complete)
   - Third: Add PSRAM worker as second cog (Combo B complete)

---

## Implementation Strategy: Transform First, Then Merge

**Decision**: Transform each driver to the unified multi-cog architecture independently, THEN merge them into combo drivers.

### Why Transform First?

#### 1. The Shared Bus Problem Becomes Simpler

Flash and SD share the same SPI bus. When merged, **one worker cog must own that bus**.

If both drivers already use the same architecture (parameter block + COGATN + command dispatch), merging them is essentially:
- One worker cog
- Two sets of device state
- CS pin selection determines which device gets the command
- Same command protocol for both

If they have *different* architectures, the merge becomes reconciling two incompatible patterns into one cog—much messier.

#### 2. Flash's "Different Style" is a Liability

The existing Flash driver has a different multi-cog style than the planned SD architecture. Merging incompatible architectures creates a Frankenstein driver. Aligning architectures first means the merge is just "routing"—the internal machinery already speaks the same language.

#### 3. Testing is Isolated

```
Transform SD    → run regression tests → know SD works
Transform Flash → run regression tests → know Flash works
Merge           → test the merge
```

vs.

```
Merge → transform → where did the bug come from?
```

#### 4. PSRAM is a Clean Validation

PSRAM has an independent bus—no sharing complications. Transforming it validates the architecture pattern without bus-sharing complexity.

---

### Transformation Order

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: Transform Individual Drivers to Unified Architecture          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Step 1: SD Driver                                                       │
│  ─────────────────                                                       │
│  • Transform to new architecture (see SPRINT-PLAN-MULTICOG.md)           │
│  • DAT block singleton, dedicated worker cog, COGATN signaling           │
│  • Run regression tests → validates architecture pattern                 │
│  • Deliverable: micro_sd_fat32_fs.spin2 (multi-cog safe)                 │
│                                                                          │
│  Step 2: Flash Driver                                                    │
│  ────────────────────                                                    │
│  • Transform to MATCH SD pattern (same command protocol)                 │
│  • Align: DAT singleton, worker cog, parameter block, COGATN             │
│  • Run regression tests                                                  │
│  • Deliverable: FLASH_driver.spin2 (architecture-aligned)                │
│                                                                          │
│  Step 3: PSRAM Driver (can parallel with Step 2)                         │
│  ───────────────────────────────────────────────────────────             │
│  • Transform to MATCH SD pattern                                         │
│  • Independent bus = clean validation of architecture                    │
│  • Run regression tests                                                  │
│  • Deliverable: PSRAM_driver.spin2 (architecture-aligned)                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: Merge Aligned Drivers into Combo Drivers                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Step 4: Flash + SD (Combo A)                                            │
│  ────────────────────────────                                            │
│  • Merge two aligned drivers into one worker cog                         │
│  • Shared SPI bus, CS pin routing                                        │
│  • Command dispatch routes to Flash or SD operations                     │
│  • Test cross-device operations                                          │
│  • Deliverable: FlashSD_FileSystem.spin2 (1 cog)                         │
│                                                                          │
│  Step 5: Flash + PSRAM + SD (Combo B)                                    │
│  ────────────────────────────────────                                    │
│  • Add PSRAM worker as second cog (separate bus)                         │
│  • OR: Single cog owns all pins (serialized, simpler)                    │
│  • Test three-device operations                                          │
│  • Deliverable: FlashPsramSD_FileSystem.spin2 (1-2 cogs)                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### What "Merge" Looks Like After Transformation

Once all drivers use the same architecture pattern, the merged worker is straightforward:

```spin2
PRI fs_worker() | cmd, device
  ' Initialize all SPI pins (this cog owns them all)
  pinh(pin_flash_cs)              ' Flash deselected
  pinh(pin_sd_cs)                 ' SD deselected
  pinh(pin_mosi)
  pinl(pin_sck)

  repeat
    repeat until (cmd := pb_cmd) <> CMD_NONE
    device := pb_device           ' Which device this command targets

    ' Dispatch by device - same command protocol for both!
    case cmd
      CMD_OPEN:
        case device
          DEV_FLASH: pb_status := do_flash_open(pb_param0)
          DEV_SD:    pb_status := do_sd_open(pb_param0)

      CMD_READ:
        case device
          DEV_FLASH:
            pinl(pin_flash_cs)
            pb_status := do_flash_read(...)
            pinh(pin_flash_cs)
          DEV_SD:
            pinl(pin_sd_cs)
            pb_status := do_sd_read(...)
            pinh(pin_sd_cs)

      ' ... etc ...

    ' Signal completion - same for all devices
    COGATN(1 << pb_caller)
```

The public API routes by device, the worker dispatches by command—clean and uniform.

---

### Architecture Alignment Checklist

Each driver must implement these patterns to enable clean merging:

| Component | Required Pattern |
|-----------|-----------------|
| State storage | DAT block (singleton) |
| Cog control | `cog_id` initialized to -1 |
| API serialization | Hardware lock (`api_lock`) |
| Command communication | Parameter block in DAT |
| Completion signaling | COGATN to caller |
| Caller waiting | WAITATN (efficient sleep) |
| Error codes | Negative values, per-cog storage |
| Worker startup | COGSPIN (Spin2 worker) |

When all three drivers follow this checklist, merging them is mechanical rather than architectural.

---

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Transformation breaks existing functionality | Regression tests after each driver transformation |
| Flash driver changes are extensive | May require phased approach within Flash transformation |
| Merge reveals incompatibilities | Aligned architecture minimizes this; protocol is identical |
| Testing complexity with combos | Test individual drivers first; combo tests layer on top |

---

## Future Optimization: LUT RAM

Each P2 cog has **512 longs (2KB) of LUT RAM** in addition to its 512 longs of cog RAM. This is a valuable resource for driver optimization.

### LUT RAM Instructions

| Instruction | Cycles | Description |
|-------------|--------|-------------|
| `RDLUT D, S` | 3 | Read from LUT address S into register D |
| `WRLUT D, S` | 2 | Write D to LUT address S |
| `SETLUTS D` | 2 | If D[0]=1, enable LUT sharing with adjacent cog |

### LUT Sharing Between Cogs

**SETLUTS** enables a powerful feature: odd/even cog pairs (0-1, 2-3, 4-5, 6-7) can share their LUT RAM. When enabled, writes to one cog's LUT are **automatically copied** to the companion cog's LUT—zero overhead, hardware-level synchronization.

### Potential Uses for Filesystem Drivers

#### 1. FAT Cluster Cache (HIGH VALUE)
```
LUT Usage: 512 longs = 512 FAT entries = 256KB of cluster chain coverage

Benefits:
- Eliminates hub RAM reads for hot FAT entries
- Dramatically speeds sequential file access
- Cluster chain traversal becomes LUT lookup instead of hub read
```

#### 2. CRC Lookup Tables
```
LUT Usage: 256 bytes for CRC-16 table (SD card data CRC)

Benefits:
- Replace bit-by-bit CRC with table lookup
- 8x speedup for CRC calculation
- Critical for high-speed data verification
```

#### 3. Double-Buffering SPI Transfers
```
LUT Usage: 128 longs = 512 bytes (one sector)

Benefits:
- Overlap SPI read with hub write via streamer
- One sector in LUT while previous sector moves to hub
- Potential 2x throughput for sequential reads
```

#### 4. LUT Sharing for Combo Drivers
```
Architecture: Worker cog (even) + Helper cog (odd) share LUT

Benefits:
- Worker writes status/results to LUT
- Helper reads immediately—no hub contention
- Zero-copy fast path for inter-cog communication
- Could enable parallel Flash+SD operations
```

### Recommended Priority

1. **FAT Cache** - Biggest impact for typical file operations
2. **CRC Tables** - Speeds all data transfers
3. **Double-buffering** - Benefits large sequential transfers
4. **LUT Sharing** - Valuable for combo drivers with parallel operations

### Implementation Notes

- LUT RAM is per-cog, so only the worker cog can use it
- LUT sharing only works between adjacent odd/even pairs
- LUT contents are lost on cog restart
- Consider preloading FAT cache during mount()

---

## Open Questions

1. ~~**SPI Bus Topology**: Are Flash and SD on shared bus or separate?~~ **ANSWERED**: Shared bus (same MOSI/MISO/SCK, different CS)

2. **PSRAM Interface Details**: What is the exact protocol for the EC-32MB PSRAM? (HyperRAM, xSPI, or other?)

3. **PSRAM Filesystem Structure**: Simple flat allocation, or full FAT-like structure?

4. ~~**Cross-Device Operations**: Should we support copying between devices?~~ **ANSWERED**: Yes, `copy_to()` API

5. **Default Device**: Should bare paths (`file.txt`) default to a specific device?

6. **PSRAM as Cache**: Worth implementing PSRAM as a transparent cache for SD reads? (Future enhancement)

---

*Document created: 2026-01-17*
*Updated: 2026-01-17 - Added Implementation Strategy (Transform First, Then Merge)*
*Status: DECIDED - Ready for implementation*
