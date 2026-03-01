# Postmortem: Why Regression Tests Didn't Catch SPI-from-Caller-Cog Bugs

**Date:** 2026-03-01
**Fixed in commit:** 98342d4

---

## The Problem

Six PUB methods performed SPI bus operations directly from the caller's cog instead of routing through the worker cog via `send_command()`. The worker cog exclusively owns the SPI pins in this architecture. All 6 passed regression testing despite being architecturally incorrect.

---

## The 6 Broken Methods and Their Test Coverage

| Method | Test File | Calls in Tests | Test Assertion |
|--------|-----------|----------------|----------------|
| `testCMD13()` | *none* | 0 | **No coverage** |
| `debugDumpRootDir()` | *none* | 0 | **No coverage** |
| `displayFAT()` | *none* | 0 | **No coverage** |
| `setSPISpeed()` | `SD_RT_speed_tests.spin2` | 9 calls | Checks `getSPIFrequency()` range |
| `checkHighSpeedCapability()` | `SD_RT_speed_tests.spin2` | 1 call | Checks result is boolean |
| `attemptHighSpeed()` | `SD_RT_speed_tests.spin2` | 1 call | Checks consistency with `isHighSpeedActive()` |

---

## Root Cause Analysis

### Reason 1: Three methods had zero test coverage

`testCMD13()`, `debugDumpRootDir()`, and `displayFAT()` are never called by any regression test, example, utility, or demo file anywhere in the project. They were invisible to the entire suite.

The `THEORY-OF-OPERATIONS.md` test coverage matrix even documents this explicitly:

> `debugDumpRootDir()` — "Debug utility — not testable"

These methods were categorized as "debug/diagnostic" and excluded from testing by design.

### Reason 2: P2 smart pins are globally shared — bugs work by accident

This is the most important finding. On the Propeller 2:

- **Smart pin configuration is per-pin, not per-cog.** When the worker cog configures SCK with `P_TRANSITION | P_OE` via `WRPIN`/`WXPIN`/`DRVL`, that configuration is visible to ALL cogs.
- **Any cog can interact with a configured smart pin.** `WYPIN`, `RDPIN`, `WXPIN`, `DRVL` are not restricted to the cog that performed the initial `WRPIN`.
- **The worker cog was idle during these calls.** After `mount()` completes, the worker sits in `WAITATN()` waiting for the next command. There is no contention on the SPI pins.

This means when the test cog called `setSPISpeed()` (which does `wxpin(sck, half_period)` and `pinl(sck)`), it **actually worked** — the SPI clock speed changed, the DAT variable `spi_freq` was updated, and subsequent worker-cog operations used the new speed.

Similarly, when `attemptHighSpeed()` called `readSector()`/`writeSector()` directly from the test cog, the streamer DMA and smart pin operations **succeeded** because the pin configuration was already in place and no other cog was contending for the bus.

**The bugs were latent, not symptomatic.** They would only manifest under concurrent access — e.g., if another cog sent a command to the worker while a direct-SPI PUB method was in progress. The regression tests are single-cog callers, so this race never occurred.

### Reason 3: Speed test assertions are deliberately weak

The speed tests verify API contract compliance, not functional correctness:

```spin2
' checkHighSpeedCapability: only checks it returns a boolean
utils.evaluateSubBool(hsCap == true or hsCap == false, @"HS cap is boolean", true)

' attemptHighSpeed: only checks self-consistency
utils.evaluateSubBool(hsResult == hsActive, @"HS state consistent", true)
```

A broken `checkHighSpeedCapability()` that returns `false` (due to SPI garbage from the wrong cog) would still pass "result is boolean." A broken `attemptHighSpeed()` that fails and returns `false` would be consistent with `isHighSpeedActive()` also returning `false` (since the speed was never changed). Both assertions pass with broken implementations.

### Reason 4: setSPISpeed data integrity test validates the WORKER, not the caller

The "Data integrity at 20 MHz" test (lines 134-151) does:

1. `sd.setSPISpeed(20_000_000)` — caller cog directly reconfigures SPI clock (broken, but works due to Reason 2)
2. `sd.createFileNew(...)` — routes through `send_command()` to worker cog
3. `sd.writeHandle(...)` — routes through `send_command()` to worker cog
4. `sd.readHandle(...)` — routes through `send_command()` to worker cog

The data integrity check validates that the WORKER can read/write at the new speed. It doesn't validate that `setSPISpeed()` should be callable from the test cog — it validates that the globally-shared pin config change took effect, which it did.

---

## Why These Bugs Are Still Dangerous

Even though they "work" in testing, they are architecturally wrong:

1. **Race condition under multi-cog access.** If cog 0 calls `setSPISpeed()` while cog 1 has a pending `send_command()`, the worker cog could be mid-SPI-transaction when the clock speed changes — causing data corruption.

2. **Lock protocol violation.** `send_command()` acquires `api_lock` to serialize access. Direct SPI calls bypass the lock entirely. Under multi-cog use, this is a data race.

3. **Maintenance trap.** Any future change to the worker's SPI initialization, teardown, or bus-switching logic could cause the caller-cog path to silently break. The "works by accident" behavior depends on implementation details that could change.

4. **Streamer state coupling.** The streamer DMA reads/writes are configured per-cog. If the caller cog's streamer state differs from the worker's expectations (e.g., different `SETQ`/`XINIT` history), sector reads could silently return wrong data.

---

## Lessons Learned

### For test design

1. **Add negative architecture tests.** A test that verifies "this PUB method routes through `send_command()`" could catch this class of bug. For example: check that `pb_cmd` transitions during a PUB call (indicates worker dispatch), or check the executing cog ID inside critical methods.

2. **Test under multi-cog load.** A test that calls PUB methods from one cog while another cog is doing file I/O would expose the race conditions that single-cog testing misses.

3. **Don't skip "debug" method coverage.** Debug methods are still part of the public API. If they can't be tested automatically (no P2 connected), at minimum verify they compile and route through `send_command()`.

4. **Assert success, not just type.** `evaluateSubBool(result == true or result == false, ...)` is a tautology for any boolean-returning method. Better: test with a known-capable card and assert `result == true`, or test with a known-incapable card and assert `result == false`.

### For driver design

5. **setSPISpeed was PUB "for speed characterization testing."** This is the classic "made public for convenience" anti-pattern. If external callers need speed control, add a `CMD_SET_SPI_SPEED` worker command instead of exposing the pin-level operation.

6. **The worker-cog pattern needs enforcement.** A code review checklist item: "Does this PUB method call any PRI method that touches SPI pins?" Or better: naming convention (`do_*` for worker-only methods) that makes violations obvious at a glance.

---

## Changes Made

See commit 98342d4 for the full fix. Summary:

- 3 new CMD constants (82, 83, 84) and worker dispatch cases
- 3 new `do_*` PRI methods (worker-cog implementations)
- 3 PUB wrappers rewritten to use `send_command()`
- `setSPISpeed` changed from PUB to PRI
- 2 debug methods rewritten to use `CMD_READ_SECTOR_RAW` with local buffers
- `readVBRRaw` moved from `SD_INCLUDE_REGISTERS` to `SD_INCLUDE_RAW`
- Compile-time guard for `SD_INCLUDE_SPEED` → `SD_INCLUDE_REGISTERS` dependency
- All 35 compilable files verified clean
