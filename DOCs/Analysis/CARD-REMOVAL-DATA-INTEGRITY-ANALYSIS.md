# Card Removal Data Integrity Analysis

**Purpose**: Identify where the driver holds dirty state in RAM that has not yet been written to the SD card, and assess the data loss exposure if the card is physically removed at each point in the file lifecycle.
**Driver**: `src/micro_sd_fat32_fs.spin2`
**Date**: 2026-03-15

---

## Executive Summary

**Finding**: The driver's write-back strategy has a layered exposure profile. FAT sectors (cluster chains) are written immediately during allocation — this is the safest part of the design. However, two structures can linger in RAM with no time-based auto-flush:

1. **Per-handle data buffer** — the last partial sector of a write remains dirty in RAM until the handle is synced or closed
2. **Directory entry** — the file's size (and future timestamps) are updated only at `syncHandle()`, `closeFileHandle()`, or `unmount()`
3. **FSInfo sector** — free cluster count is tracked incrementally in RAM and only written at `unmount()`

If the user pulls the card after writing but before closing, they lose the last partial sector of data AND the directory entry still shows the old file size — the file appears truncated or zero-length even though the cluster chain and earlier full sectors are safely on card.

**Existing mitigations**: `syncHandle()` and `syncAllHandles()` are already in the public API and address exposures #1 and #2. Exposure #3 (FSInfo) is cosmetic — it only affects the "free space" display on the next mount. The real question is whether applications call sync frequently enough.

---

## The Five Dirty-State Locations

### 1. Per-Handle Data Buffer (HF_DIRTY)

**What**: Each open write handle has a private 512-byte sector buffer (`h_buf[handle]`). When the application writes data via `writeHandle()`, bytes are copied into this buffer. Full sectors are immediately flushed to card, but the **last partial sector** stays in RAM marked `HF_DIRTY`.

**When it's dirty**: From the moment the first byte of a new sector is written until either:
- The sector fills to 512 bytes (auto-flushed by `do_write_h`)
- `syncHandle(handle)` is called
- `closeFileHandle(handle)` is called
- `unmount()` is called (which calls `do_sync_all()`)

**Exposure window**: Indefinite. There is no timeout-based auto-flush. If an application writes 100 bytes and then goes idle, those 100 bytes stay in RAM forever until explicitly flushed.

**Data at risk**: Up to 511 bytes per open write handle (the last partial sector).

**Driver code**: `do_write_h()` (line ~3230) sets `h_flags[handle] |= HF_DIRTY` after copying data. `do_sync_h()` (line 3415) and `do_close_h()` (line 3089) clear it via `writeSector()`.

### 2. Directory Entry (File Size)

**What**: When a file grows, the driver updates `h_size[handle]` in RAM to reflect the new byte count. The actual directory entry on card (the 32-byte record in the directory sector) is NOT updated until the handle is synced or closed.

**When it's stale**: From the first `writeHandle()` that changes the file size until:
- `syncHandle(handle)` is called
- `closeFileHandle(handle)` is called
- `unmount()` is called

**Exposure window**: Indefinite, same as the data buffer.

**Data at risk**: The file's recorded size on card is wrong. On remount, the file will appear as whatever size it was when last synced. If never synced, a newly created file shows 0 bytes even though clusters were allocated and full sectors were written. The data is physically on card in allocated clusters, but the directory says the file is smaller — so the data beyond the recorded size is invisible to any reader.

**This is the most insidious exposure**: The cluster chain is intact (FAT was written immediately), the full sectors are on card, but the file size says they don't exist. A recovery tool could find them, but normal file access cannot.

**Driver code**: `h_size[handle]` updated in `do_write_h()`. Written to card in `do_sync_h()` (line 3442) and `do_close_h()` (line 3114).

### 3. FSInfo Sector (Free Cluster Count)

**What**: The FSInfo sector stores the volume's free cluster count and a "next free cluster" hint. The driver reads these at mount, tracks them incrementally in `fsi_free_count` and `fsi_nxt_free` as clusters are allocated/freed, and writes them back only at `unmount()` via `updateFSInfo()`.

**When it's stale**: From the first cluster allocation or deletion until `unmount()`.

**Exposure window**: The entire mounted session.

**Data at risk**: Cosmetic only. The free cluster count is an optimization hint, not a structural requirement. FAT32 spec (Microsoft's FAT spec, section 4.1) explicitly says the FSInfo values may be incorrect and should be validated by scanning the FAT. On next mount, the driver reads FSInfo but the worst case is that the free space display is wrong until a full FAT scan corrects it. No data loss occurs.

**Driver code**: `fsi_free_count` decremented in `allocateCluster()` (line 4382), incremented in cluster deallocation (line 3752). Written to card only in `updateFSInfo()` (line 4434), called from `do_unmount()` (line 2859).

### 4. FAT Sectors (Cluster Chain) — NOT EXPOSED

**What**: When a file grows and needs a new cluster, `allocateCluster()` writes BOTH copies of the FAT (FAT1 and FAT2) **immediately and synchronously** before returning. The cluster chain on card is always up to date.

**Exposure**: None. This is the safest part of the design. Even if the card is pulled mid-session, the cluster chain reflects all allocations. The only transient risk is if the card is pulled during the actual `writeSector()` call for the FAT update (a sub-millisecond window), which could leave a partially written FAT sector — but this is an inherent physical limitation of any storage system and cannot be mitigated in software.

**Driver code**: `allocateCluster()` (line ~4339) calls `writeSector()` for both FAT copies immediately after modifying the in-buffer entry.

### 5. Global Caches (dir_buf, fat_buf, buf) — NOT INDEPENDENTLY EXPOSED

**What**: The three global 512-byte caches are used as staging areas for reads and writes. They are NOT independently dirty — they serve as the I/O buffer for `readSector()` and `writeSector()`. When data must be written, it's copied into the appropriate cache and then `writeSector()` is called immediately. The caches have no independent dirty flag.

**Exposure**: None as an independent concern. The global caches are transient — their contents are always either freshly read from card or about to be written. The risk is captured entirely by exposures #1-#3 above.

---

## Timeline of a File Write Session

This timeline shows exactly when each structure is safe vs. exposed:

```
Operation                  Handle Buffer    Dir Entry     FAT        FSInfo
─────────────────────────  ──────────────   ──────────    ─────────  ──────────
createFileNew()            clean            on card       on card    stale(*)
  (cluster allocated)                       (size=0)      (written)

writeHandle(256 bytes)     DIRTY (256B)     STALE         safe       stale
writeHandle(256 bytes)     → sector full    STALE         safe       stale
  (auto-flush to card)     clean            (size=0       safe       stale
                                            but 512B
                                            on card)

writeHandle(100 bytes)     DIRTY (100B)     STALE         safe       stale
                                            (size=0,
                                            612B actual)

── Card pulled here: lose 100 bytes of data.
   File shows 0 bytes on remount (dir entry never updated).
   But 1 full sector of data IS on card in allocated cluster. ──

syncHandle()               clean            ON CARD       safe       stale
                                            (size=612)

── Card pulled here: no data loss.
   File shows 612 bytes. All data recoverable. ──

writeHandle(400 bytes)     DIRTY (400B)     STALE         safe       stale
                                            (size=612,
                                            1012B actual)

closeFileHandle()          clean            ON CARD       safe       stale
                                            (size=1012)

unmount()                  (handle freed)   on card       safe       ON CARD
```

(*) FSInfo becomes stale as soon as the first cluster is allocated during `createFileNew()`.

---

## Risk Assessment by Scenario

### Scenario A: Pull card after writes, before close

**Impact**: HIGH — Loss of last partial sector (up to 511 bytes) AND directory entry is stale. File appears truncated or zero-length. Full sectors are on card but invisible because directory size is wrong.

**Frequency**: Common in embedded systems — power loss, user removal, watchdog reset.

### Scenario B: Pull card after close, before unmount

**Impact**: LOW — All file data and directory entries are safe. Only FSInfo is stale, which is cosmetic. Next mount may show incorrect free space until corrected.

**Frequency**: Common — many embedded applications never formally unmount.

### Scenario C: Pull card during a writeHandle() call

**Impact**: VARIABLE — If the card is pulled during a `writeSector()` for a full sector, that sector may be partially written (card-level corruption). The FAT chain is already on card from the prior `allocateCluster()`, so the chain is intact but the sector data may be garbled. This is a physical-layer risk that no software can fully prevent.

**Frequency**: Rare but possible during sustained high-throughput writing.

---

## Existing Mitigations

The driver already provides the tools to manage this exposure:

| API | What it flushes | What remains stale |
|-----|------------------|--------------------|
| `syncHandle(h)` | Handle data buffer + directory entry for handle h | FSInfo, other handles |
| `syncAllHandles()` | All write handles' data + directory entries | FSInfo |
| `closeFileHandle(h)` | Same as syncHandle + frees handle | FSInfo, other handles |
| `unmount()` | All handles + FSInfo | Nothing (fully flushed) |

The gap is not missing functionality — it's that **the application must explicitly call these methods**. There is no automatic periodic flush.

---

## The Embedded Reality: Data Is Hard-Won

In an embedded system, the data on the SD card is irreplaceable. A data logger deployed in the field, a sensor array collecting hours of readings, a control system recording operational history — this data cannot be re-created. It was hard-won through real-world operation, and losing it because a developer pulled the card to check the data on a PC (a completely natural action) is unacceptable.

The current driver design puts the burden of data safety on the application developer. The tools exist (`syncHandle()`, `syncAllHandles()`), but they require the developer to explicitly call them at the right times. This is the wrong default for an embedded system. **The safe behavior should be automatic.** A developer who writes data and then walks away for 30 seconds should be able to pull that card with confidence that everything they wrote is on it.

Relying on developers to "remember to sync" is the same class of error as relying on developers to "remember to free memory." It works in careful code, but the consequences of forgetting are disproportionate to the mistake. In our case, the consequence is silent data loss — the file appears truncated or zero-length with no error, no warning, and no recovery path.

**Design principle**: The driver should protect the data by default. If the worker cog is sitting idle anyway — burning cycles polling `pb_cmd` in a tight loop — it should use that idle time to ensure all dirty state reaches the card.

---

## Recommendations

### R1: Automatic idle-timeout flush in the worker cog (RECOMMENDED)

The worker cog's main loop (line 2115) currently spins on `repeat until pb_cmd <> CMD_NONE` — a tight poll consuming 100% of the cog doing nothing. This idle time should be used to auto-flush dirty handles once a quiet period has elapsed.

**Mechanism**: After completing a command (or on each idle loop iteration), the worker checks a free-running counter. If no command has arrived within the threshold period, it scans `h_flags[]` for any handle with `HF_DIRTY` set and performs the equivalent of `do_sync_h()` on each. After all dirty handles are flushed, it also writes the FSInfo sector if stale.

**The threshold must balance two concerns:**

1. **Too short** — The worker flushes while the application is still in the middle of a burst of writes. Each flush costs 5-50ms of SPI time during which the bus is unavailable. If the next `writeHandle()` arrives while the worker is mid-flush, the caller blocks on `api_lock` waiting for the flush to finish. This adds unexpected latency to the write path.

2. **Too long** — The exposure window stays open. A developer finishes a test, waits a few seconds, pulls the card, and loses data because the threshold hadn't elapsed yet.

#### Threshold Analysis

The key insight is: **what's the natural cadence of SD file I/O in embedded applications?**

| Application Pattern | Typical Write Interval | Notes |
|---------------------|----------------------|-------|
| High-rate data logger (1 kHz sensor) | 0.5-2ms between writes | Sustained burst, no gap until session ends |
| Medium-rate logger (10 Hz) | 100ms between writes | Regular cadence with short gaps |
| Event-driven logger | Seconds to minutes | Writes come in unpredictable bursts |
| Configuration save | One-shot, then idle | Write once, never again until next config change |
| Burst-then-idle | Sub-ms during burst, then seconds/minutes idle | Common: acquire data, write batch, go idle |

The "burst-then-idle" pattern is the most important case. The application writes rapidly for a period, then stops. The threshold must be long enough to avoid flushing mid-burst but short enough that the data is safe shortly after the burst ends.

#### Candidate Thresholds

**50ms — Too aggressive**

- A medium-rate logger writing at 10 Hz has 100ms between writes. A 50ms threshold would trigger a flush between every other write, adding 5-50ms of flush latency to the write path. At 25 MHz SPI, a sync of one dirty handle (1 sector write + 1 directory read + 1 directory write = 3 sector operations) takes roughly 3-5ms. This is tolerable but wasteful — the data is about to be overwritten by the next write anyway.
- Would catch a card-pull 50ms after the last write, but at the cost of constant unnecessary flushing during normal operation.

**200ms — Good balance (RECOMMENDED)**

- Long enough that a 10 Hz logger (100ms interval) never triggers a mid-burst flush — the counter resets on each command before reaching 200ms.
- Short enough that a developer who stops writing and reaches for the card (a 1-2 second human action) will find the data already flushed.
- The 200ms quiet period is a clear signal that the current burst is over. No embedded application writes data with exactly 200ms gaps as a sustained pattern — that's a dead zone between "regular periodic writes" (which are faster) and "occasional writes" (which are slower and don't mind the flush).
- At 350 MHz, 200ms = 70 million clock cycles. Using `getct()` and a simple comparison gives cycle-accurate timing with zero overhead.
- Flush cost (3-5ms for one handle) is invisible to the application since no commands are in flight.

**500ms — Safe but slow**

- Guarantees no interference with any write pattern, including slow 2 Hz loggers.
- But the exposure window is half a second. A quick developer could pull the card 300ms after the last write and still lose data. In practice, the human action of reaching for the card takes 1-2 seconds, so 500ms is probably safe for the "developer pull" scenario. But it provides less margin.

**1000ms (1 second) — Too conservative**

- A full second of exposure after the last write. This is safe against mid-burst interference but provides little advantage over requiring the developer to call `syncHandle()` manually. If they have to wait a full second anyway, they might as well call sync.
- The whole point of auto-flush is that the developer shouldn't have to think about it. A 1-second threshold still requires awareness of the timing.

#### Recommended Design: 200ms Idle Threshold

```
Worker Loop (modified):
  1. If pb_cmd != CMD_NONE:
       dispatch command
       reset idle_timer := getct()
       reset flush_done := false
  2. If pb_cmd == CMD_NONE and not flush_done:
       if (getct() - idle_timer) >= IDLE_FLUSH_CLOCKS:
         scan h_flags[] for HF_DIRTY handles
         for each dirty handle:
           do_sync_h(handle)
           if pb_cmd != CMD_NONE: abort flush, handle command first
         if fsi_free_count stale:
           updateFSInfo()
         flush_done := true
  3. Repeat
```

**Critical detail**: The flush loop checks `pb_cmd` between each handle sync. If a new command arrives mid-flush, the worker abandons the flush and services the command immediately. The remaining dirty handles will be caught on the next idle period. This ensures that auto-flush **never** adds latency to a real operation.

**Constants**:
```spin2
CON
  IDLE_FLUSH_MS    = 200                          ' Auto-flush after 200ms idle
  IDLE_FLUSH_CLOCKS = (clkfreq / 1000) * IDLE_FLUSH_MS
```

**Note**: `IDLE_FLUSH_CLOCKS` must be computed at runtime (in the worker's init) since `clkfreq` is a runtime value. The CON definition above is conceptual — the actual implementation would use a DAT variable set during worker startup.

#### What Each Threshold Costs on a False Trigger

If the threshold fires mid-burst (application was just slow this one time), the cost is:

| Dirty Handles | Sectors Written | Time at 25 MHz SPI | Caller Impact |
|---------------|----------------|---------------------|---------------|
| 1 handle | 3 (data + dir read + dir write) | ~3-5ms | Caller blocks 3-5ms on next command |
| 3 handles | 9 | ~10-15ms | Caller blocks 10-15ms |
| 6 handles (max) | 18 | ~20-30ms | Caller blocks 20-30ms |

At 200ms, false triggers are rare (requires a >200ms gap in an otherwise active write stream). When they do occur, the cost is bounded and recoverable — the caller just sees slightly higher latency on the next command, comparable to a slow SD card write.

### R2: Document the exposure clearly in the API reference

Even with auto-flush, applications should understand the write-back model. The API documentation should state:
- `writeHandle()` buffers data in RAM; it may not be on card immediately
- The worker cog auto-flushes dirty handles after 200ms of inactivity
- `syncHandle()` forces an immediate flush if the application needs stronger guarantees
- `closeFileHandle()` always flushes before freeing the handle

### R3: FSInfo — include in auto-flush cycle

With auto-flush in place, the FSInfo sector should be written as part of the idle flush cycle (after all dirty handles are synced). This eliminates the "pull card before unmount" cosmetic issue at zero additional cost — the worker is already doing I/O during the flush, and one more sector write is negligible. This means a cleanly auto-flushed card can be moved to a PC and show correct free space without requiring `unmount()`.

### R4: Guard against partial close failure

If `closeFileHandle()` fails mid-way (data buffer writes but directory write fails), the handle is freed anyway (line 3126, `freeHandle()` runs unconditionally). This means a partial close could leave the directory entry stale AND the handle freed — the application has no way to retry. This is low probability (requires an I/O error during close) but worth hardening: `freeHandle()` should only run if both writes succeeded, or at minimum the failure should be reported so the application knows the directory entry may be stale.

### R5: Application-level sync remains available

Auto-flush is a safety net, not a replacement for explicit sync in applications that need deterministic guarantees. A control system that must ensure data is on card before taking an action (e.g., "log the command, then actuate the valve") should still call `syncHandle()` explicitly. The 200ms auto-flush threshold is designed for the common case — protecting against card removal after activity stops — not for the real-time case where data must be durable before the next line of code executes.
