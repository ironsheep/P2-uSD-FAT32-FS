# Symptom Investigation: moveFile Intermittent Failures

**Date:** 2026-01-27
**Methodology:** Following DEBUGGING-METHODOLOGY.md - systematic symptom collection without filtering

---

## Logs Analyzed

| Log File | Result | Failures |
|----------|--------|----------|
| 260126-211543 | FAIL | 1 (Test #22) |
| 260126-213402 | PASS | 0 |
| 260126-213518 | PASS | 0 |
| 260126-213535 | PASS | 0 |
| 260126-213549 | FAIL | 2 (Tests #20, #22) |
| 260126-213607 | PASS | 0 |
| 260126-213625 | PASS | 0 |

Note: The passing run (213402) occurred BETWEEN the two failing runs chronologically.

---

## Symptoms Collected (No Filtering)

### Symptom 1: Different directory entry indices across runs
**Source:** All logs, Test #1-3 creation output

| Run | RTDIR1 index | RTDIR2 index | MOVEME.TXT index |
|-----|--------------|--------------|------------------|
| Failing #1 (211543) | i=6_240 (offset 96) | i=6_272 (offset 128) | i=6_304 (offset 160) |
| Passing (213402) | i=6_336 (offset 192) | i=6_368 (offset 224) | i=6_400 (offset 256) |
| Failing #2 (213549) | i=6_336 (offset 192) | i=6_368 (offset 224) | i=6_400 (offset 256) |

Failing run #1 uses lower indices (earlier positions). Failing run #2 uses same indices as passing run.

### Symptom 2: Stale data visible in buffer before do_close copy
**Source:** do_close debug output in all logs

| Run | Before copy, buf at offset |
|-----|---------------------------|
| Failing #1 (211543) | `[ïOVEME  TXT]` (corrupted first byte) |
| Passing (213402) | `[           ]` (empty/spaces) |
| Failing #2 (213549) | `[ïOVEME  TXT]` (corrupted first byte) |

Both failing runs show stale MOVEME-like data in buffer before copy. Passing run shows clean buffer.

### Symptom 3: Created file not found immediately after creation (Failing #2)
**Source:** 213549 log, Tests #19-20

- Test #19 creates MOVEME.TXT at i=6_400 (sector 38_688 offset 256)
- do_close confirms: "Syncing dir entry at sector 38_688 offset 256"
- Test #20 searches for MOVEME.TXT
- Search reports: "Free slot at n_sec=38_688 i=6_432" (offset 288)
- **The entry at i=6_400 was skipped over and not recognized**

### Symptom 4: RTDIR2 not found after successful moveFile (Failing #1)
**Source:** 211543 log, Tests #20-22

- Test #20 moveFile completes successfully (returns $FFFF_FFFF)
- Test #22 tries to changeDirectory to RTDIR2
- Search reports: "Free slot at n_sec=38_688 i=6_336"
- "searchDirectory FAILED for: name_ptr = 'RTDIR2' dir_sec=38_676"
- **RTDIR2 was at i=6_272 but search found free slot at i=6_336**

### Symptom 5: Different debug output between passing and failing runs
**Source:** do_movefile debug output

Passing run (213402) shows:
```
[do_movefile] Reading sector 38_688 (sec_in_buf=63_572)
[do_movefile] After read: buf[128]=[{~fm...] buf[160]=[MOVEME  TXT]
[do_movefile] Copied entry: [MOVEME  TXT]
[do_movefile] After $E5: buf[128]=[{~fm...]
[do_movefile] Calling do_close, flags=$B
```

Failing run #1 (211543) shows:
```
[do_movefile] Copied entry: [MOVEME  TXT]
[do_movefile] Calling do_close, flags=$B
```

**Missing lines:** "Reading sector", "After read", "After $E5"

### Symptom 6: Passing run sees data from previous failing run
**Source:** 213402 log, do_movefile debug

The passing run's do_movefile shows:
```
buf[160]=[MOVEME  TXT]
```

But in this passing run, MOVEME.TXT was created at offset 256, not 160. The data at offset 160 is from the PREVIOUS failing run #1 where MOVEME.TXT was at i=6_304 (offset 160).

**The card retains stale data from previous failed test runs.**

### Symptom 7: Cleanup phase fails to find directories
**Source:** Both failing runs, cleanup section

Failing #1 (211543) cleanup:
```
[do_chdir] searchDirectory FAILED for: name_ptr = "RTDIR1" dir_sec=38_676
[do_chdir] searchDirectory FAILED for: name_ptr = "SUBDIR1" dir_sec=38_676
[do_chdir] searchDirectory FAILED for: name_ptr = "RTDIR2" dir_sec=38_676
```

Failing #2 (213549) cleanup:
```
[do_chdir] searchDirectory FAILED for: name_ptr = "RTDIR1" dir_sec=38_676
[do_chdir] searchDirectory FAILED for: name_ptr = "SUBDIR1" dir_sec=38_676
[do_chdir] searchDirectory FAILED for: name_ptr = "RTDIR2" dir_sec=38_676
```

Directories that were successfully created and used earlier cannot be found during cleanup.

### Symptom 8: Search always finds "Free slot" at higher index than expected
**Source:** All failing runs

- Failing #1: RTDIR2 at i=6_272, but search finds free slot at i=6_336
- Failing #2: MOVEME.TXT at i=6_400, but search finds free slot at i=6_432

**Pattern: Search skips past valid entries and finds free slot 32-96 bytes later**

### Symptom 9: sec_in_buf shows different sector before read
**Source:** Passing run do_movefile debug

```
[do_movefile] Reading sector 38_688 (sec_in_buf=63_572)
```

sec_in_buf=63_572 is RTDIR2's first sector (cluster 391 = sector 63_572).
The code is about to read directory sector 38_688, but the buffer currently contains RTDIR2's sector.

This is expected behavior (cache mismatch triggers read), but documents the buffer state.

### Symptom 10: First byte corruption pattern
**Source:** Both failing runs, do_close Before copy output

The stale data shows `[ïOVEME  TXT]` - the first byte is corrupted (showing as ï or $E5 or similar) but bytes 2-11 look correct.

If first byte = $E5, that's the "deleted entry" marker in FAT. The entry would be skipped during search.

---

## Symptom Trace Analysis

### Trace for Symptom 3 (File not found after create)

**Question:** Why does searchDirectory not find an entry that was just written?

**Code path for Test #19 (create file):**
1. newFile() -> do_newfile()
2. searchDirectory() finds free slot at i=6_400
3. Creates entry_buffer with filename
4. Calls writeFile() or equivalent
5. do_close() syncs entry:
   - Reads sector 38_688 into buf (or uses cached)
   - bytemove(@buf + 256, @entry_buffer, 32)
   - writeSector(38_688)
   - sec_in_buf = -1 (invalidated)

**Code path for Test #20 (search for file):**
1. moveFile() -> do_movefile()
2. searchDirectory() for "MOVEME.TXT"
3. Starts at n_sec=38_676, i=0
4. Reads sectors, checks each 32-byte entry
5. At sector 38_688, offset 256 (i=6_400):
   - Should find MOVEME.TXT entry
   - But instead continues to i=6_432 (free slot)

**Possible failure points:**
- writeSector() in do_close didn't actually write
- readSector() in searchDirectory returned wrong/stale data
- Entry at offset 256 has first byte = $00 or $E5
- Name comparison failed for unknown reason

### Trace for Symptom 4 (RTDIR2 not found after moveFile)

**Question:** Why does RTDIR2 disappear after moveFile completes?

**During moveFile (Test #20):**
1. searchDirectory() finds MOVEME.TXT at i=6_304
2. searchDirectory() finds RTDIR2 at i=6_272 - **FOUND OK**
3. Creates new entry in RTDIR2
4. Marks source entry as deleted ($E5)
5. do_close() writes changes

**After moveFile (Test #22):**
1. changeDirectory("RTDIR2")
2. searchDirectory() for "RTDIR2"
3. Search fails - "Free slot at n_sec=38_688 i=6_336"

**Key observation:** RTDIR2 was at i=6_272, but search found free slot at i=6_336. The search skipped past RTDIR2's location.

**Possible failure points:**
- moveFile modified sector 38_688 and corrupted RTDIR2's entry
- do_close wrote wrong data to sector 38_688
- Something marked RTDIR2's entry as deleted ($E5)
- Cache returned stale/wrong sector data

### Trace for Symptom 2 (Stale data in buffer)

**Question:** Why does buffer show MOVEME-like data before do_close copies fresh data?

**In do_close():**
1. Need to read sector containing entry
2. readSector() loads sector 38_688 into buf
3. buf now contains whatever is on the card
4. Debug shows: "Before copy, buf at offset: [ïOVEME  TXT]"

**This reveals:** The CARD already has a partial/corrupted MOVEME entry at that location from a previous run. The test isn't starting with a clean card.

**But this alone shouldn't cause failure** because do_close overwrites with fresh data.

---

## Convergence Analysis

Multiple symptoms point to **searchDirectory() skipping valid entries**:
- Symptom 3: MOVEME.TXT not found at i=6_400
- Symptom 4: RTDIR2 not found at i=6_272
- Symptom 7: Multiple directories not found during cleanup
- Symptom 8: Search always finds free slot at higher index

**If entries are being skipped, possible causes:**
1. First byte of entry = $00 (end marker) - stops search
2. First byte of entry = $E5 (deleted) - skips entry
3. Sector not read correctly (cache issue)
4. Wrong sector read (sector number confusion)

**Symptom 2 (stale ïOVEME data) suggests:** First byte might be $E5 from previous partial delete.

**Symptom 5 (missing debug lines) suggests:** Different code paths executing between passing and failing runs, OR something preventing the debug output.

---

## Hypotheses

### Hypothesis A: Entry first byte is $E5 (deleted marker)
**Explains symptoms:** 3, 4, 7, 8 (search skipping entries)
**Evidence for:** Symptom 2 shows corrupted first byte that could be $E5
**Would be proven by:** Adding debug to show actual first byte of entries during search
**Would be disproven by:** If first byte is actually a valid character (A-Z)

### Hypothesis B: writeSector() not completing or writing to wrong sector
**Explains symptoms:** 3, 4, 7 (created entries don't persist)
**Evidence for:** Symptom 5 shows different debug output
**Would be proven by:** Adding debug to confirm writeSector parameters and completion
**Would be disproven by:** If writeSector logging shows correct sector written

### Hypothesis C: sec_in_buf cache returning wrong data
**Explains symptoms:** 3, 4, 7, 8 (reading stale sector data)
**Evidence for:** Symptom 9 shows buffer contains different sector before read
**Would be proven by:** If sec_in_buf incorrectly matches when it shouldn't
**Would be disproven by:** If readSector always reads when sec_in_buf mismatches

### Hypothesis D: moveFile corrupts nearby directory entries
**Explains symptoms:** 4, 7 (RTDIR2 disappears after moveFile)
**Evidence for:** RTDIR2 and source entry are in same sector 38_688
**Would be proven by:** If do_movefile's buffer operations overwrite wrong offsets
**Would be disproven by:** If buffer operations are correctly bounded

### Hypothesis E: Test cleanup leaves entries with first byte = $E5
**Explains symptoms:** 2, 6 (stale MOVEME data on card)
**Evidence for:** Tests run multiple times, failing runs show stale data
**Would be proven by:** If cleanup deleteFile sets $E5 but new create reuses same slot
**Would be disproven by:** If new entries always go to truly free slots ($00)

---

## Priority Investigation Order

1. **Hypothesis A** - Most directly explains the "search skips entry" pattern
2. **Hypothesis D** - Explains why RTDIR2 disappears only after moveFile
3. **Hypothesis C** - Could explain intermittent nature (cache state varies)
4. **Hypothesis B** - Would explain persistent failures
5. **Hypothesis E** - Explains card state but not why fresh writes fail

---

## Next Steps

1. Add debug to searchDirectory() to print first byte of each entry examined
2. Add debug to do_movefile to trace all buffer operations with offsets
3. Add debug to writeSector() to confirm sector number and completion
4. Verify sec_in_buf handling in all sector read/write operations
5. Check if $E5 from cleanup is being confused with new entries

---

## Key Code Locations to Examine

| Function | Purpose | File Location |
|----------|---------|---------------|
| searchDirectory() | Find entry by name | SD_card_driver_v2.spin2 |
| do_movefile() | Move file between directories | SD_card_driver_v2.spin2 |
| do_close() | Sync entry to card | SD_card_driver_v2.spin2 |
| readSector() | Read sector with cache | SD_card_driver_v2.spin2 |
| writeSector() | Write sector, invalidate cache | SD_card_driver_v2.spin2 |
