# Post-v1.6.1 regression failures: attribution and root causes

**Date:** 2026-08-08
**Method:** static analysis of source, git history, and `tools/logs/`. No hardware.
**Supersedes:** the working premises of `DOCs/Plans/POST-V161-CHANGE-ATTRIBUTION-REQUEST.md`

---

## 0. Two premises from the request document are false

**"No reference point was ever established."** It was. `tools/logs/SD_RT_*_260727-13*.log`
is the v1.6.1 certification: 26 suites, 471 tests, every totals line present and intact.
It is not truncation-masked. The request's §2.1 plan — re-measure v1.6.1, then step back to
v1.6.0, then v1.5.3 — spends bench time re-deriving a number already on disk.

**"Only two commits touch the driver; that is a three-step bisection, and it was never
run."** The bisection was already run. The 08-03 sweep IS the committed HEAD tree. It is
the measurement that separates the eight commits from the working-tree experiments, and it
is decisive.

---

## 1. Root cause #1 — two stack detectors sharing one address

**Explains 7 of 7 failing/blank suites on 08-03. FIXED (commit `569f898`).**

`isp_stack_check.prepStackForCheck()` writes its sentinel to `LONG[@cog_stack][STACK_SIZE]`
— one long past the stack. With no gap long declared, that address *is*
`cog_stack_guard[0]`. Two detectors demanded different values at one address ($addee5e5 vs
$CC). `start()` writes the guard first and the sentinel second, so the guard always lost,
and `checkStackGuard()` became a stuck-at-FAIL detector.

Latent and invisible while the violation only reached DEBUG (the driver ships
`DEBUG_MASK = 0`). `f34610f` escalated the check to the caller in `send_command`, and a
stuck-at-FAIL detector became **-26 on every command**.

Evidence, 08-03, committed HEAD: `mount(): -26 (expected 0)`, then free space 0, unmount
fails, remount fails — 15 pass / 16 fail.

The correlation is exact. Suites failing or producing no totals line on 08-03:

    mount, directory, multiblock, raw_sector, read_write, format, file_ops

Suites defining `SD_INCLUDE_STACK_CHECK`:

    directory, multiblock, raw_sector, read_write, mount, format, file_ops

**Identical sets. No other suite affected.** After the fix, `mount_tests` went 15/16 -> 31/0.

---

## 2. Root cause #2 — stale assertions for the retired `eofHandle` contract

**Explains 3 more. FIXED (commit `be6169a`).** Test defects, not driver defects.

`eofHandle` is boolean-only by design: it cannot return a code, because TRUE and
`E_TIMEOUT` are both -1. The code moved to `ERROR()`. Three checks still compared the
answer itself:

| Site | Asserted | Actual |
|---|---|---|
| `error_handling` #12 | `E_NOT_A_DIR_HANDLE` (-93) | -1 (TRUE) |
| `multihandle` #19 | `E_INVALID_HANDLE` (-91) | -1 (TRUE) |
| `multihandle` use-after-close | `E_INVALID_HANDLE` (-91) | -1 (TRUE) |

The request's §4.3 predicted more of these existed. It was right.

---

## 3. Root cause #3 — OPEN. One defect, four detectors

**Not layout roulette, and the failing-suite identity is not the phenomenon.** Every
instance shares one signature: **data written comes back as zeros, or the file is not
found**.

| Suite | Symptom |
|---|---|
| `subdir_ops` #2/#3 | file created, handle valid -> `openFileRead` **-40**, `deleteFile` **-40** |
| `speed` #12 | `Pattern mismatch at 0: got $0`; `openFileRead after restore failed: -40` |
| `crc_diag` #12 | `Pattern mismatch at 0: got $0 expected $30` |
| `cogcwd` | `worker read BBBB` -> 0; `main still sees FILE_A` -> 0 |

Two facts bound it hard:

- **Not in the committed tree.** 08-03, same 58GB card: `subdir_ops` 18/0, `speed` 15/0,
  `crc_diag` 14/0, `cogcwd` 5/0. All green.
- **Not general write failure.** Same 08-07 sweep: `read_write` 49/0, `file_ops` 26/0,
  `directory` 30/0, `seek` 37/0, `volume` 31/0.

It appears only with the uncommitted worker stack-integrity gate, which is why that gate
was removed from the tree rather than committed.

### 3.1 Correction to the "42 bytes that never execute" framing

Only the gate *body* is unexecuted. `checkStackGuard()` itself runs on **every** command
completion, and the gate sat between end-of-dispatch and the `COGATN` that wakes the
caller. "Never executed" is not an accurate description of the change under test.

### 3.2 Hypotheses tested and REFUTED — do not re-adopt

**(a) Stack overflow corrupting the SPI pin configuration.** The layout makes this
attractive: only 20 bytes separate the end of the worker stack from `cs`.

| Symbol | Address | Past stack end |
|---|---|---|
| `COG_STACK` (160 longs) | `$00F1E` | ends `$0119E` |
| `COG_STACK_END_MARK` | `$0119E` | +0 |
| `COG_STACK_GUARD` (16 B) | `$011A2` | +4 |
| `CS` | `$011B2` | **+20** |
| `MISO` | `$011BA` | **+28** |
| `SPI_RX_MODE` | `$011CA` | **+44** |
| `SPI_PERIOD` | `$011CE` | **+48** |

Corrupt `miso`/`spi_rx_mode` and reads return zeros; corrupt `spi_period` and you get -7.
The symptoms fit exactly.

**REFUTED:** `send_command` checks the guard after every command and overrides the status
with `E_STACK_OVERFLOW`. A stack overflow deep enough to reach `cs` must first pass
through all 16 guard bytes, so it cannot arrive unreported. The 08-07 failing runs show no
-26. The guard was intact while the data was corrupt.

*(Still worth doing on its own merits: `STACK_SIZE = 160` is annotated "measured peak: 113
longs", a measurement predating `f34610f`'s +1237 lines. `diagnostic-tests/SD_worker_stack_depth_probe.spin2`
re-measures it. That is prudence, not this root cause.)*

**(b) `entry_buffer` resolving to a wild pointer.** `entry_buffer dir_entry_t` (line ~805)
does not appear in the map's DAT symbol list at all. It appears under **`PASM Labels:
ENTRY_BUFFER  COG $002  HUB $00AF8`** — the driver object base + 8, ~30 KB from the 32
bytes of storage, which are allocated *anonymously* between `BUF` and `VOL_LABEL`.
Rewriting the declaration as a plain `BYTE 0[14]` produces a proper DAT symbol and changes
the binary by **52 bytes**.

**REFUTED as root cause #3:** `readDirectoryHandle()` hands `@entry_buffer` to callers as a
public pointer, and `SD_RT_dirhandle_tests` passes **25/0 on every run including 08-07**.
If that pointer aimed into the object image, those tests would read bytecode instead of
filenames. The map entry is a **pnut-ts map-reporting artifact**, not the resolved address.

*Worth reporting to Parallax alongside the `#error` finding: a struct-typed DAT label is
misreported in the map, and the declaration form costs 52 bytes over the plain form.*

---

## 4. Card confound — never noted in the request document

The instrument was not frozen, in a way §9 does not mention.

| Session | Card |
|---|---|
| 07-27 (v1.6.1 certification) | **SDHC 7GB** |
| 08-03, first sweep | SDHC 7GB |
| 08-03, second sweep onward | **SDXC 58GB** `SN:$0000_0F14` 2023/06 |
| 08-06, 08-07 | SDXC 58GB `SN:$0000_0F14` |

That serial is **neither** of the two cards designated for the two-card certification
($0001_B9D5, $3584_1E2E) — it is an uncatalogued third card. **The 58GB card has no green
baseline at any version.** Root cause #1 appeared identically on both cards, so the
attribution above stands; but no future comparison should cross this boundary silently.

---

## 5. State of the tree, and what is NOT yet known

Commits `569f898`, `be6169a`, `5960286` land the two proven fixes and the instrument
repair, and remove the gate. All 27 suites plus 15 consumer programs compile clean;
`check_style.sh` and `check_error_handling.sh` are clean.

**This configuration has never been run on hardware.** It is not the 08-03 tree (it has the
DAT fix) and it is neither A/B variant from 08-07 (the gate, `worker_stack_fault`, and the
`send_command` branch are all gone). Its expected result is the 08-03 result minus root
cause #1's seven suites and minus root cause #2's three assertions — but that is a
prediction, not a measurement.

Specifically: **removing the gate did not fix `subdir_ops`.** On 08-07 the gate-absent
configuration scored 6/12. Root cause #3 is isolated, not resolved.
