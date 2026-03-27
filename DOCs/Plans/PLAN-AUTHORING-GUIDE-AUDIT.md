# Spin2 Authoring Guide Compliance Audit

Full audit of all `.spin2` files against `DOCs/procedures/SPIN2-AUTHORING-GUIDE.md`. Excludes `jm_*.spin2` (third-party) and `.history/` files.

**Audit date:** 2026-03-27
**Files audited:** 44

---

## Summary

| Category | Violation Count | Files Affected |
|----------|:--------------:|:--------------:|
| Rule 4.4 — PRI methods missing doc comments | ~30 | 8 |
| Rule 4.3 — PUB methods missing/incorrect doc comments | ~6 | 5 |
| Rule 5.7 — Magic numbers | ~50+ | 15+ |
| Rule 5.2/5.3 — Early returns / return from loops | ~25 | 3 |
| Rule 2.2/2.3 — Generic container names (`result`, etc.) | 4+ | 4+ |
| Rule 5.0 — Unused/uninitialized return variables | 3+ | 2 |
| Rule 6.1 — Raw numeric literals in test assertions | ~5 | 3 |
| Rule 6.6 — Missing comments on expected error tests | ~8 | 4 |
| Rule 6.4 — Buffer sizes not named constants | ~6 | 4 |
| Rule 4.2 — File header format issues | ~3 | 3 |

---

## Part A — Main Driver (`src/micro_sd_fat32_fs.spin2`)

The driver is ~7100 lines and generally well-documented. PUB/PRI ordering is correct. All PUB and PRI methods have doc comments. The main issues are some magic numbers, early returns, and uninitialized return variables.

**Note:** The `' ---- Label ----` dash format on block declaration lines (CON, DAT, VAR, OBJ) is **correct and required** per Rule 4.5. These markers are gathered by the VS Code Outline panel for navigation. Only full-width decorative borders (`═══════`) are forbidden.

### A1. Rule 4.7 — Missing Enum Group Documentation

Handle flags (`HF_FREE`, `HF_READ`, `HF_WRITE`, `HF_DIR`, `HF_DIRTY`) around line 213 lack a preceding comment block listing all values and meanings.

**Fix:** Add a preceding comment block per Rule 4.7 pattern:
```spin2
  ' Handle state flags:
  '  HF_FREE   - Handle is available for allocation
  '  HF_READ   - Handle is open for reading
  '  HF_WRITE  - Handle is open for writing
  '  HF_DIR    - Handle is a directory handle
  '  HF_DIRTY  - Handle buffer has unwritten data
```

### A2. Rule 5.2/5.3 — Early Returns

Several methods use early `return` statements instead of single exit point:

| Line(s) | Method | Issue |
|---------|--------|-------|
| ~1109-1115 | `setDate()` | Multiple early returns in validation |
| ~4805-4851 | `do_create_contiguous()` | Multiple early returns in conditionals |

**Fix:** Restructure to assign return variable and fall through to a single exit point.

### A3. Rule 5.0/5.1 — Uninitialized Return Variables

| Line | Method | Issue |
|------|--------|-------|
| ~1006 | `readDirectoryHandle()` | `p_entry` not assigned on failure path |
| ~1025 | `readDirectory()` | `pEntry` not assigned on failure path |

**Fix:** Add `pEntry := 0` (or `p_entry := 0`) as the first line of the method.

### A4. Rule 5.7 — Magic Numbers

| Line(s) | Code | Fix |
|---------|------|-----|
| ~1331 | `idx == 9` | Use `SFN_NAME_LEN + 1` |
| ~7034 | `repeat idx from 0 TO 511` | Use `SECTOR_SIZE - 1` |
| ~6660 | `32` for bit count | Define `BITS_PER_LONG = 32` |

There are additional scattered magic numbers in timeout calculations and buffer offset arithmetic. A systematic search for bare numeric literals (excluding 0, 1, -1, 4) should be done during implementation.

---

## Part B — Regression Tests (`src/regression-tests/`)

### B1. Rule 4.4 — PRI Methods Missing Doc Comments

This is the most widespread issue across test files. Many PRI test runner methods lack the required `'` doc comment.

| File | Lines | Methods Missing Doc Comments |
|------|-------|------------------------------|
| `SD_RT_timestamp_tests.spin2` | 98, 140, 173, 219, 255, 273 | `runTest1_` through `runTest6_` |
| `SD_RT_async_tests.spin2` | 124, 177, 226, 266, 298, 354, 408 | `runTest1_` through `runTest6_`, `createTestFile` |
| `SD_RT_testcard_validation.spin2` | 114, 128, 152, 182, 215, 254, 278, 310, 353, 386, 410, 434, 467 | All 13 PRI test methods |
| `SD_RT_defrag_tests.spin2` | ~346 | `cleanupAllFiles()` |
| `SD_RT_dirhandle_tests.spin2` | ~481, ~528 | `createTestStructure()`, `cleanupTestItems()` |

**Fix:** Add a one-line `'` doc comment after each PRI method signature describing its purpose.

### B2. Rule 2.1 — Single-Letter Variable Names

| File | Line | Variables | Fix |
|------|------|-----------|-----|
| `SD_RT_recovery_tests.spin2` | 79 | `h0`, `h1`, `h2` | Rename to `handle0`, `handle1`, `handle2` |

### B3. Rule 5.0 — Unused Parameters

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `SD_RT_stress_tests.spin2` | 366 | `worker_id` param never used in `workerDispatch()` | Remove parameter or use it |

### B4. Rule 5.7 — Magic Numbers in Tests

| File | Line(s) | Issue |
|------|---------|-------|
| `SD_RT_read_write_tests.spin2` | ~78 | `vbrBuf BYTE 0[512]` — use `sd.SECTOR_SIZE` |
| `SD_RT_file_ops_tests.spin2` | ~121, 176, 189, 198 | `bytefill(@sectorBuffer, $EE, 512)` — use named constant |
| `SD_RT_mount_tests.spin2` | ~130-131 | Raw MBR offsets `$1C2`, `$1C6`, `$1C8`, `$1C9`, `$1FE` |
| `SD_RT_format_tests.spin2` | ~121-129 | Same MBR/VBR offsets as above |

**Fix:** Export FAT32 structure offsets as public constants from the driver in a `{Spin2_Doc_CON}` block. Test files then reference them via `sd.MBR_SIG_OFFSET`, `sd.MBR_PART_TYPE_OFFSET`, etc. Group all related offsets in a single public CON block — do not create separate blocks for each offset.

### B5. Rule 6.6 — Missing Comments on Expected Error Tests

| File | Line(s) | Issue |
|------|---------|-------|
| `SD_RT_seek_tests.spin2` | ~269, 273 | Seek beyond EOF / to exact EOF — missing explanation |
| `SD_RT_volume_tests.spin2` | ~419 | openFileRead() on directory — missing comment |
| `SD_RT_format_tests.spin2` | ~152 | VBR jump instruction check — missing comment |
| `SD_RT_crc_diag_tests.spin2` | ~155 | CRC non-zero check — missing explanation |

**Fix:** Add a comment before each expected-error assertion explaining why the error is expected.

### B6. Rule 6.4 — Buffer Sizes Not Named Constants

| File | Line(s) | Issue |
|------|---------|-------|
| `SD_RT_read_write_tests.spin2` | ~78 | `vbrBuf BYTE 0[512]` |
| `SD_RT_file_ops_tests.spin2` | Various | `512` used in `bytefill()` calls |
| `SD_RT_directory_tests.spin2` | ~65 | `genFileName BYTE 0[16]` without named size |

---

## Part C — Utility Files (`src/UTILS/`)

### C1. Rule 5.2 — Early Returns (`SD_card_identify.spin2`)

This file has the most early return violations in the project:

| Line(s) | Method | Issue |
|---------|--------|-------|
| ~172-183 | `getSDSpecVersion()` | 7 early returns in if chain |
| ~193-195 | `lookupMID()` | Return from inside repeat loop |
| ~206-209 | `getCardType()` | 3 early returns in conditionals |
| ~221-228 | `detectFilesystem()` | 8 early returns in case block |
| ~255-260 | `decodeSpeedClass()` | 6 early returns in case block |

**Fix:** Restructure each method to assign a result variable in each branch and return once at the end.

### C2. Rule 2.3 — Return Variable Named `result`

| File | Line | Fix |
|------|------|-----|
| `SD_card_identify.spin2` | ~96 | `go() \| result` -> rename to `status` |
| `SD_format_card.spin2` | ~41 | `go() \| result` -> rename to `status` |

### C3. Rule 4.5 — Decorative Borders (`SD_performance_benchmark.spin2`)

Lines ~158, 181, 220, 237, 382, 513, 571 use `' ════════` decorative borders as section separators inside the code.

**Fix:** Replace with plain `'` comments or remove entirely. The borders are acceptable inside `DAT` blocks but not as general section separators.

### C4. Rule 4.3 — PUB Methods Using `'` Instead of `''` (Examples)

| File | Line(s) | Issue |
|------|---------|-------|
| `SD_example_read_write.spin2` | ~45 | `go()` uses `'` instead of `''` for doc |
| `SD_example_directory_walk.spin2` | ~42 | Same |
| `SD_example_data_logger.spin2` | ~55 | Same |
| `SD_example_multicog.spin2` | ~58 | Same |

**Fix:** Change `'` to `''` on PUB method doc comments.

---

## Part D — Diagnostic Tests (`diagnostic-tests/`)

### D1. Rule 2.3 — Return Variable Named `result`

| File | Line | Fix |
|------|------|-----|
| `SD_stack_depth_test.spin2` | ~47 | Rename `result` to `status` |
| `SD_spi_limit_test.spin2` | ~72 | Rename `result` to `status` |

### D2. Rule 5.7 — Magic Numbers (Extensive)

Diagnostic tests are the heaviest offenders for magic numbers since they work directly with raw hardware values and buffer offsets.

| File | Issue |
|------|-------|
| `SD_card_info_tests.spin2` | Raw offsets `$1FE`, `$1C2`, `$1C6`; buffer sizes `512`, `64`; shift values `>> 30` |
| `SD_diag_fsck_window_test.spin2` | Raw VBR offsets `$0D`, `$0E`, `$10`, `$24`, `$20`; FAT entry masks `$7F` |
| `SD_frequency_characterize.spin2` | Raw `clkset()` binary literals; test pattern values |
| `SD_speed_characterize.spin2` | Raw `$DEADBEEF` seed; `MIN_HP = 4`; delta scale `1000` |
| `SD_freq_sweep_tests.spin2` | Raw modulo `50`; test patterns `37`, `53`; result bit patterns |
| `SD_spi_limit_test.spin2` | Raw `49_999_999`; test patterns `41`, `67`; minimum HP `4` |

**Fix:** Each file should define CON blocks for all semantic literals. Common FAT32 offsets should be shared (either from the driver's public constants or a shared test constants file).

### D3. Rule 4.3 — Missing Blank Line Before Code

Most diagnostic test files are missing the required blank line between doc comments and the first line of code in `go()` methods.

| File |
|------|
| `SD_stack_depth_test.spin2` |
| `SD_spi_limit_test.spin2` |
| `SD_frequency_characterize.spin2` |
| `SD_speed_characterize.spin2` |
| `SD_card_info_tests.spin2` |
| `SD_diag_cmd13_capture.spin2` |
| `SD_freq_sweep_tests.spin2` |

### D4. Rule 6.4 — Buffer Sizes Not Named Constants

| File | Issue |
|------|-------|
| `SD_speed_characterize.spin2` | `read_buf[512]`, `multi_buf[512 * 8]` |
| `SD_card_info_tests.spin2` | Buffer sizes `512`, `64`, `16` |
| `SD_diag_cmd13_capture.spin2` | Buffer sizes `512`, `7`, `8`, `64`, `16` |

---

## Implementation Order

Recommended order by impact and risk:

### Phase 1 — Safe, Mechanical Changes (no logic changes)
1. **Rule 4.4** — Add missing PRI method doc comments (test files)
2. **Rule 4.3** — Fix PUB doc comment style (`'` -> `''`) in examples
3. **Rule 4.3** — Add missing blank lines before code after doc blocks
4. **Rule 2.3** — Rename `result` return variables to meaningful names
5. **Rule 4.7** — Add enum group documentation (handle flags, etc.)
6. **Rule 4.5** — Remove full-width `═══` decorative borders in `SD_performance_benchmark.spin2` (these are inside method bodies, not on block declaration lines — the `---- Label ----` format on block declarations is correct)

### Phase 2 — Constant Extraction (low risk, high volume)
7. **Rule 5.7** — Define named constants for magic numbers across all files
8. **Rule 6.4** — Define buffer size constants in test CON blocks
9. **Rule 6.1** — Replace raw numeric literals in test assertions with named constants

### Phase 3 — Control Flow Refactoring (higher risk, requires testing)
10. **Rule 5.2/5.3** — Restructure early returns to single exit point (main driver)
11. **Rule 5.2/5.3** — Restructure early returns in `SD_card_identify.spin2`
12. **Rule 5.0/5.1** — Add default assignments for uninitialized return variables

### Phase 4 — Documentation Polish
13. **Rule 6.6** — Add comments on expected error tests
14. **Rule 2.1** — Rename single-letter variables (`h0`/`h1`/`h2` -> `handle0`/`handle1`/`handle2`)

---

## Notes

- `{Spin2_Doc_CON}` directives are **not violations** — they are pnut-ts metadata tags for API document extraction.
- `---- Label ----` format on block declarations is **correct and required** per Rule 4.5. These are gathered by VS Code Outline for navigation. Only full-width decorative borders (`═══════`) are forbidden.
- FAT32 structure offsets (`$1FE`, `$1C2`, `$1C6`, etc.) — **Decision: export as public constants from the driver** in a `{Spin2_Doc_CON}` block. Test and diagnostic files reference them via the `sd.` object prefix. Group related offsets in a single CON block per Rule 3.5.
- The `quit` keyword inside `repeat` loops is **correct** per Rule 5.3 — the guide says to use `quit` instead of `return` from loops. Some audit agents incorrectly flagged `quit` as a violation; it is the prescribed alternative.
- Decorative `' ════════` borders inside method bodies (not on block declaration lines) are not explicitly prohibited but clutter the code. Consider replacing with plain comments.
