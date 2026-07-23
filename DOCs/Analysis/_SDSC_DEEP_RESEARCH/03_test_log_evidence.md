# 03 — Test Log Evidence (counterfeit asdfg SDSC wedge)

This document extracts the hard empirical evidence from the May 18–26 test logs
captured against the two counterfeit "asdfg" SDSC cards. Logs live in
`/workspaces/P2-uSD-FAT32-FS/tools/logs/`.

> **Diag dump format (since commit `bfeb20e`)**
> `code=N` — see legend in test output:
>   1=CMD24fatalR1, 2=drespTO, 3=CRCrej, 4=writeErr, 5=unkRej, 6=busyTO, 7=success, **8=R1neverArrived (new sentinel)**
> `R1=$XX` — value of the last R1 byte the worker saw (post-`bfeb20e`: only set when a real R1 was seen)
> `dresp=$XX` — last data-response token nibble from CMD24 path
> `cmd13_pre=[7 bytes]` — bus snapshot just before issuing CMD13 in dumpWriteFailDiag/dumpReadFailDiag
> `cmd(CMDxx) R1 latency=N ms after P byte polls` — instrumented from `bfeb20e`; -1 = no R1 ever received

---

## Card identification (which physical card was in the socket?)

| Date / time (P2 clk)     | SN              | Card                              | Notes |
|--------------------------|-----------------|-----------------------------------|-------|
| 5/19 – 5/24 ~12:00       | `$0000_1680`    | "asdfg" Cloudisk SDSC **1 GB**    | older format, 3_923_944 sectors (~1915 MB) free, 489_533 free clusters |
| 5/24 12:19 – 5/24 15:46  | `$0000_01C9`    | Transcend SDHC **29 GB**          | reference card; baseline pass |
| 5/24 16:00 onward        | `$0000_1680`    | Cloudisk back in socket           | unmount/mount cycle starts to fail |
| 5/25 12:50 onward        | `$0000_01F4`    | "asdfg" **Lerdisk** SDSC **960 MB** | 1_957_864 free sectors (~955 MB), 245_233 free clusters (per mount diag) |

The cardWarnings field is `$$04` (NO_DATA_CRC) on **both** counterfeits — they
return zeros in the CRC-16 trailer rather than valid CRCs.

---

## Decisive evidence: May 25–26 raw_sector_tests (Lerdisk, SN `$0000_01F4`)

Four nearly-identical runs of `SD_RT_raw_sector_tests.bin` against the Lerdisk
card on May 25 evening (build with `bfeb20e` R1-latency diag).

### Per-write outcome table (the 5 PHASE-1 writes)

Logs: `260525-225750` (most recent), `260525-224009`, `260525-212503`,
`260525-194043` (the latter uses pre-bfeb20e code=2 reporting).

| Run / write | Sector  | Result          | code | R1   | dresp | CMD17/CMD24 R1 latency        | byte polls   |
|-------------|---------|-----------------|------|------|-------|-------------------------------|--------------|
| 22:57 #1    | 100_000 | write OK; read fail | 7  | $00  | $05   | CMD17 0 ms after 2 polls    | 2            |
| 22:57 #2    | 100_001 | WRITE FAIL      | **2**  | $00  | $FF   | CMD24 0 ms after 2 polls    | 2            |
| 22:57 #3    | 100_002 | WRITE FAIL      | **8**  | $00  | $FF   | CMD24 **-1 ms** (no R1)     | **138_045**  |
| 22:57 #4    | 100_003 | WRITE FAIL      | **8**  | $00  | $FF   | CMD24 -1 ms                 | 138_040      |
| 22:57 #5    | 100_004 | WRITE FAIL      | **8**  | $00  | $FF   | CMD24 -1 ms                 | 138_123      |
| 22:40 #1–5  | same    | identical       | 7→2→8→8→8 | $00 | $05/$FF | identical latencies      | 2 / 2 / 138_045 / 138_041 / 138_122 |
| 21:24 #1–5  | same    | identical       | 7→2→8→8→8 | $00 | $05/$FF | identical                  | 2 / 2 / 138_046 / 138_040 / 138_123 |
| 19:40 #1–5  | same    | 7→2→**2**→2→2 (pre-bfeb20e) | reports code=2 even when no R1 arrived | $00 | $05/$FF | (no R1 instrumentation in this build) | 2 / 2 / 137_624 / 137_620 / 137_702 |

`cmd13_pre` is `[$FF $FF $FF $FF $FF $FF $FF]` in **every** dump — the bus is **idle high, not stuck LOW**. That excludes the obvious "wedge holds DAT line low" hypothesis.
`lastCMD13err = $0000` in every dump — the worker never issued a CMD13 because no operation got far enough to require it.

### Reads in PHASE 2-4 all fail with `warnings=$04`

All 8 reads (reverse-order verify, full-byte verify, MBR readback) fail with
`status=-1`. `cmd13_pre = [$FF*]` always. The card no longer responds to CMD17
after the first write storm — every subsequent CMD17 R1 is presumably timing
out the same way CMD24 did (the read path does not yet emit a per-op latency
counter, so we can't see the poll count, but the per-test elapsed time of
~1086 ms == one full CMD17 R1 timeout corroborates this).

### Determinism is decisive

The byte-poll counts across three independent 5/25 runs of the **same binary**:

| Run     | #3 polls | #4 polls | #5 polls |
|---------|----------|----------|----------|
| 22:57   | 138_045  | 138_040  | 138_123  |
| 22:40   | 138_045  | 138_041  | 138_122  |
| 21:24   | 138_046  | 138_040  | 138_123  |

Variance is ≤1 poll out of ~138_000. This is **fully deterministic** behavior —
not racing, not noise. Whatever the card is doing on writes #3–#5, it does it
exactly the same way every time.

### Stage-transition timing (the 75-ms window after first write)

Timestamps from `260525-225750`:

| Event                                     | Time           | Δ from previous |
|-------------------------------------------|----------------|-----------------|
| Test #1 starts                            | 22:57:36.695   | —               |
| Test #1 diag emitted (write OK, read fail)| 22:57:37.683   | 988 ms (the 1-second CMD17 read timeout) |
| Test #2 starts                            | 22:57:37.701   | 18 ms           |
| Test #2 diag (CMD24 R1=$00 after 2 polls) | 22:57:37.787   | **86 ms** |
| Test #3 starts                            | 22:57:37.806   | 19 ms           |
| Test #3 diag (CMD24 R1 timeout)           | 22:57:38.791   | 985 ms (R1 timeout itself) |

The **gap between write #1 success and the failed CMD24 R1 of write #2 is
~85 ms** — long enough that any 5–50 ms "wait for the busy line" delay would
not change anything; the card is *already* not responding to CMD24 by the time
we send it 85 ms later.

### Counter-intuitive transition between writes #2 and #3

- Write **#2** gets `R1=$00` after just 2 byte polls — the card *did* answer
  CMD24 promptly with success-R1, **but then never sent a data-response token**
  (`dresp=$FF`, code=2 = drespTO). After streaming 512 + 2 CRC bytes the host
  expected the XXX0XXX nibble; it got $FF for the full 250-ms watcher window.
- Writes **#3–#5** never get R1 at all — 138_000 byte polls × ~7.2 µs each
  ≈ ~1 second timeout, then code=8 sentinel.

So write #2 establishes that the card *can* still see CMD24 (it responds with
R1=$00) but cannot complete the data phase. Writes #3–#5 escalate: CMD24
itself is now silently dropped at SPI layer. **The wedge is progressive**:
data-phase first, then command-phase.

### Predicted-outcome check for commit `bfeb20e`

`bfeb20e` distinguishes "cmd() returned -1 (R1 timeout)" from "cmd() returned
$00 valid R1." Before `bfeb20e`, all silent failures looked the same.
**Prediction: write #2 should now report a meaningful code, and writes #3–#5
should report code=8 (new sentinel).** Confirmed:

- Pre-`bfeb20e` 19:40 log: writes #3–#5 reported `code=2` (drespTO) with no R1
  instrumentation — driver was lying about what stage failed.
- Post-`bfeb20e` 21:24 / 22:40 / 22:57 logs: writes #3–#5 report `code=8`
  (R1neverArrived) with poll-count proof. The new code path correctly
  distinguishes the two failure modes. **`bfeb20e` works as designed.**

The mechanism the fix surfaced: **CMD24 R1 is silently dropped** by the card
after the first failed data-phase, not "CMD24 sent OK but data-response timed
out" as the old code reported.

---

## Mount tests (Lerdisk, 5/25 22:57)

Log: `SD_RT_mount_tests_260525-225715.log`

All 31 mount/unmount/freeSpace tests pass. The card mounts, reports
`P2-BENCH`, 1_957_864 free sectors. **The wedge is exclusively triggered by
sequential CMD24 writes, not by initCard, mount, or freeSpace reads.**

Important DIAG observation: `error()` returns `-9` (E_BAD_PIN_LIMIT) *after* a
successful mount. This is a stale per-cog last_error from the
pin-validation Tests #8/#9 above. Not a real failure — but worth noting for
anyone reading the log out of context.

---

## Mount tests (Cloudisk, 5/24 16:06 — the original wedge-on-unmount capture)

Log: `SD_RT_mount_tests_260524-160658.log`

A different and stronger failure shape — happens during **unmount**, not
during writes:

| Test | Op                | Result           | Notes |
|------|-------------------|------------------|-------|
| #10  | mount()           | **0** (success)  | freeSpace=3_923_944 (1915 MB) |
| #11  | volumeLabel       | OK ("P2-BENCH ") | |
| #12  | freeSpace         | OK 3_923_944     | took ~743 ms (large FAT walk) |
| **#13** | **unmount()**  | **-7 (E_IO_ERROR)** after **~3987 ms** | takes the worst-case write timeout — likely the FSInfo write back to disk failing |
| #15  | mount()           | -8 (E_CARD_NOT_PRESENT) | |
| #17+ | every subsequent op | all fail        | -7 or -8 chain |

Notice **once unmount fails, the card never recovers** until power-cycle. This
matches the wedge shape but is triggered by the **FSInfo write** that unmount
performs, not the raw_sector_tests CMD24. Same underlying mechanism: **the
first write succeeds but a subsequent write wedges the card**.

The 5/24 16:50 DEBUG_MASK-on rerun of the same binary against the same card
(`SD_RT_mount_tests_260524-165058.log`) passes all 31 tests including unmount.
This is the strongest hint that **the wedge depends on observable timing**
(serial-debug printing slows the bus enough between operations to avoid the
race). This is the "DEBUG=on hides the bug" capture mentioned in the running
log.

---

## tempcog / audit reproductions

Logs: `SD_tempcog_repro_260519-140852.log`, `SD_audit_repro_260519-001724.log`

Both run **reads only** on Cloudisk. Both get 4–6 consecutive `status=0` reads
with `sig=$55 $AA`. CRC always `recvCRC=$$0000  calcCRC=$$2302` — confirming
NO_DATA_CRC (the card sends `$00 $00` instead of a real CRC).

`cardWarnings=$$04` ($04=NO_DATA_CRC) for both cards. No writes attempted, no
wedge. **These reads confirm read-only operation is solid on the Cloudisk;
the wedge is write-specific.**

---

## Hard answers to the six specific questions

1. **Failure mode under `bfeb20e`:** writes #3–#5 fail at the **CMD24 R1 step**
   with the new code=8 sentinel. The fix correctly distinguished R1-timeout
   from R1=$00 — previously these failures were misreported as `code=2`
   (drespTO). The card silently drops CMD24 after one bad data phase.

2. **Stage-transition timing #1→#2:** writes #1 success at 22:57:37.683,
   write #2 R1 received at 22:57:37.787 (CMD24 R1 came back in <86 ms wall —
   most of which is test framework overhead; actual R1 latency = 0 ms after 2
   byte polls). **A `waitms(N)` between writes will NOT help** — write #2 R1
   already comes back fast and correct; it's the data-response phase that
   fails. The card "knows" the previous write failed and is now in some
   internal recovery state.

3. **Determinism:** Decisive. Poll counts ≤1-byte variance across three runs.
   This is not a timing race in the host; it's a deterministic card state
   machine.

4. **Sector range:** 100_000 – 100_004 (5 consecutive sectors). All in the
   data area of a FAT32-formatted card. No alignment to cluster boundary
   tested. The behavior is identical for all 5 LBAs — sector number is
   irrelevant.

5. **Recovery:** None. Once write #1 misbehaves, **every** subsequent
   operation (writes #2-#5, reads in PHASE 2, MBR read in PHASE 4) fails.
   Only unmount + remount + power-cycle restores function (mount tests pass
   from a clean boot).

6. **Lerdisk vs Cloudisk:** Both wedge. The triggers differ slightly:
   - **Cloudisk** (SN `$0000_1680`) wedges on the **first write inside
     unmount** (the FSInfo writeback). Raw sector tests against it weren't
     captured post-bfeb20e (last tested 5/24).
   - **Lerdisk** (SN `$0000_01F4`) wedges on the **second write of
     raw_sector_tests** (CMD24 to LBA 100_001).
   Both share `cardWarnings=$$04` (NO_DATA_CRC, dummy `$00 $00` CRC trailer).
   Both are SD 1.x rev2.2. Both date-stamp `2_025/11` or `2_025/12`. The
   failure mode is structurally identical: **first write succeeds, subsequent
   write wedges the card.**

---

## What the logs prove (≤300 words)

1. **The wedge is real, deterministic, and write-only.** Three identical binary
   runs against the Lerdisk produced byte-identical failure shapes (poll counts
   match within ≤1 out of 138_000). Reads-only workloads (tempcog/audit) never
   wedge. Mount/freeSpace works perfectly.

2. **The wedge is a card-side state failure, not a host bus problem.** Every
   `cmd13_pre` snapshot is `[$FF $FF $FF $FF $FF $FF $FF]` — the SPI bus is
   high-idle, not stuck low. The host can still drive CMD frames; the card
   just stops issuing R1 responses to CMD24 after the first failed
   data-phase. Writes #3–#5 see CS toggled, MOSI driven, but MISO stays at
   $FF for ~138_000 byte-polls (~1 s).

3. **The fix in `bfeb20e` works as designed.** It distinguishes
   "CMD24 sent, R1=$00 received, data-response stuck" (write #2, code=2)
   from "CMD24 sent, R1 never arrived" (writes #3–#5, code=8). Pre-fix all
   three appeared as `code=2`, mis-suggesting that the problem was in the
   data-response phase. The actual mechanism is: **write #2 reaches data-
   phase but the card never emits a valid data-response token; the next CMD24
   is then silently dropped at the command layer.**

4. **A `waitms()` workaround between writes will not fix this.** Write #2's
   R1 latency is 0 ms after 2 byte polls — the card answers CMD24 promptly
   and correctly; the failure is downstream of R1 reception. Adding wait
   time before sending CMD24 will not help because CMD24 itself is fine.

5. **DEBUG_MASK timing changes the outcome.** The 5/24 16:50 DEBUG_MASK-on
   rerun of the unmount-failing build passed cleanly — a strong hint that
   the wedge has a narrow timing window the card cannot tolerate at full
   SPI speed.

6. **Both counterfeits share the failure mode.** Cloudisk wedges on FSInfo
   writeback; Lerdisk wedges on the 2nd CMD24. Both report
   `cardWarnings=$$04` (dummy zero CRC). The class — not the individual
   card — is the bug.
