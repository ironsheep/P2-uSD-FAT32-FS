# External SD Header Regression Test Results

**Card**: Gigastone "High Endurance" 16GB SDHC (MID $00, SN:$0000_03FB)
**Interface**: External SD header (base pin 16: CS=20, MOSI=19, MISO=18, SCK=21)
**P2 Clock**: 270 MHz

---

## Run 1 — 2026-02-20

Pre-condition: FSCK run first, card already had data from prior tests.
Format was NOT run before this suite (format_tests reformatted during its own run).

## Run 2 — 2026-02-21

Pre-condition: Card freshly formatted with `SD_format_card`, then FSCK verified CLEAN.

---

## Results Comparison

| Test                 | Run 1 (02-20) | Run 2 (02-21) | Change       |
|----------------------|---------------|---------------|--------------|
| **FSCK**             | CLEAN         | CLEAN         | same         |
| card_info            | 16/0          | 16/0          | same         |
| register             | 10/0          | 10/0          | same         |
| mount                | 21/0          | 21/0          | same         |
| volume               | 19/2          | 19/2          | same         |
| file_ops             | 21/1          | 20/2          | **WORSE** +1 fail |
| read_write           | MOUNT FAIL    | MOUNT FAIL    | same         |
| directory            | MOUNT FAIL    | MOUNT FAIL    | same         |
| dirhandle            | 22/0          | 22/0          | same         |
| seek                 | MOUNT FAIL    | MOUNT FAIL    | same         |
| multihandle          | 19/0          | 19/0          | same         |
| multiblock           | 5/1           | 5/1           | same         |
| multicog             | 14/0          | 14/0          | same         |
| raw_sector           | 3/11          | 4/10          | **BETTER** -1 fail |
| error_handling       | MOUNT FAIL    | MOUNT FAIL    | same         |
| speed                | MOUNT FAIL    | MOUNT FAIL    | same         |
| crc_diag             | 12/2          | 12/2          | same         |
| format               | 46/0          | 46/0          | same         |
| **Mounted totals**   | **208/17**    | **207/17**    | -1 pass (file_ops worse) |
| **Mount failures**   | **5 tests**   | **5 tests**   | same 5 tests |

---

## Analysis

### Deterministic Mount Failures (100% reproducible, both runs)

These 5 test binaries ALWAYS fail to mount, regardless of card state:

1. `SD_RT_read_write_tests` (44,207 bytes)
2. `SD_RT_directory_tests` (35,769 bytes)
3. `SD_RT_seek_tests` (38,053 bytes)
4. `SD_RT_error_handling_tests` (33,952 bytes)
5. `SD_RT_speed_tests` (36,511 bytes)

- All fail within ~200ms of binary start
- Binary size does NOT correlate (smallest at 33KB fails, largest passing is 43KB)
- Fresh format, delays between tests, multiple retries make no difference
- The same 5 always fail, the other 12 always mount successfully
- This is binary-specific, NOT random contact/electrical

### Signal Integrity Issues (data corruption)

Tests that mount show SPI data corruption symptoms:

- **raw_sector**: 10-11 failures across runs, "readback mismatch" and "sector ID mismatch"
- **multiblock**: 1 failure both runs, "510 byte mismatches" on sector readback
- **crc_diag**: 2 failures both runs, CRC mismatch + retry counted
- **volume**: 2 failures both runs, volume label readback wrong

### Stable Tests (zero failures both runs)

- card_info, register, mount, dirhandle, multihandle, multicog, format (7 tests, 100% clean)

### Test-Level Failures (likely pre-existing bugs, not electrical)

- **file_ops #21**: `openFileRead(dir)` returns E_FILE_NOT_FOUND (-40) instead of E_NOT_A_FILE (-42)
- **volume #2**: Volume label readback shows stale label after `setVolumeLabel()`

---

## Conclusion

The external SD header shows two distinct issues:

1. **Deterministic mount failures**: 5 specific test binaries cannot mount. Since the same card mounts fine with 12 other binaries using identical pin definitions, this points to a binary-layout-dependent initialization issue — possibly related to P2 debug system setup or hub memory layout affecting initial SPI timing.

2. **SPI signal integrity**: Raw sector readback corruption (wrong bytes), CRC mismatches, and label readback errors all indicate marginal signal quality on the external header. The logic analyzer should reveal whether this is crosstalk, ringing, or inadequate drive strength on the longer traces.

Both issues are candidates for logic analyzer investigation.
