# Layout-Sensitivity Root-Cause Request — Container Agent Handoff

**Status:** ANSWERED 2026-08-12 — root cause found (write-path RDFAST inside the
SCK phase window; layout moves its hub-slot latency), fix applied container-side.
See `DOCs/Analysis/LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` for the mechanism,
the corrected read of §2.4 (write-side, not capture-side; dresp=$05 proves
framing only), and the bench verification plan. Originally drafted 2026-08-11
from the bench session that cornered the defect.
**Requester:** Stephen (bench session, Card 2b, P2 Edge onboard slot).
**Assignee:** container agent (no hardware access — see §6 for the deliverable split).
**Gate:** this defect is release-gating for v1.7.0. Consumers compile the driver into
programs whose sizes we do not control; a layout-dependent data-corruption defect is
a field lottery.

---

## 1. One-paragraph statement

With driver `a41c839`, the compiled **presence** of `SD_INCLUDE_SPEED` — code proven
never executed in the failing programs — deterministically flips the write→readback
path from fully passing to corrupting: sector data reads back as the written
bitstream **delayed by exactly one bit**. The same suites, same flags, same card,
same socket passed on 2026-08-10 against driver `8885fe3`. Therefore SPEED is a
*layout lever*, not the bug: some structure in the driver whose hub placement moves
with total binary content sits on a timing cliff in the streamer/SPI capture path.
The task is to find that structure and make the driver **alignment-invariant**.

## 2. Evidence chain (all measured 2026-08-11, Card 2b = Gigastone OEM ASTC SDXC
58GB, SN `$0000_0F14`, P2 Edge onboard slot, sysclk 350 MHz, SPI 25 MHz)

### 2.1 Sweep-level correlation (27 programs)

Full-suite sweep on `a41c839`: 449 pass / 57 fail. **Every one of the ten suites
built with `SD_INCLUDE_ALL` failed; every one of the seventeen suites built without
it passed** (the two non-ALL blemishes — register #11 CID-printability and volume #9
label-error-code — are expectation-level, not corruption). Transcript:
`tools/logs/shakedown_SN0000-0F14_260811.txt` (not in git; summary preserved here).

| ALL suites (all FAILED) | non-ALL suites (all PASSED) |
|---|---|
| raw_sector 2/5, multiblock 5/2, format (aborted on MBR verify), stress 0/4, cogcwd 0/1, timestamp 4/4, error_injection 21/15, crc_validation 1/5, recovery 0/7, async 1/12 | mount 43/0, file_ops 35/0, read_write 49/0, seek 38/0, directory 33/0, dirhandle 25/0, multihandle 22/0, fifo 21/0, error_handling 19/0, subdir 18/0, multicog 15/0, crc_diag 14/0, fatchain 2/0, defrag 12/0 (was 13/0 line—12 pass), speed 15/0, register 16/1*, volume 37/1* |

### 2.2 Flag bisection on SD_RT_raw_sector_tests (same driver a41c839, minutes apart)

| Build (pnut-ts `#else` branch pragmas) | Result |
|---|---|
| ALL (= ASYNC+DEFRAG+RAW+REGISTERS+SPEED+DEBUG+TEST_HOOKS) | 2/5 FAIL |
| ALL minus ASYNC | 2/5 FAIL (ASYNC exonerated) |
| RAW+DEBUG | **14/14 PASS** |
| RAW+DEBUG+TEST_HOOKS+DEFRAG+REGISTERS | **14/14 PASS** |
| RAW+DEBUG+TEST_HOOKS+DEFRAG+REGISTERS+SPEED | **2/5 FAIL** |

(SPEED cannot be tested without REGISTERS — driver guard
`SD_INCLUDE_SPEED requires SD_INCLUDE_REGISTERS`, micro_sd_fat32_fs.spin2:165.)

Cross-confirmation on two signature-B suites:
- SD_RT_stress_tests: ALL → 0/4; ALL-minus-SPEED → **4/4 PASS**
- SD_RT_error_injection_tests: ALL → 21/15; ALL-minus-SPEED → **35/36**
  (sole residual is test #36's geometry setup guard — §5.1, unrelated)

### 2.3 SPEED code is never executed in the failing programs

- `do_attempt_high_speed` is reachable ONLY from the worker dispatch case
  (micro_sd_fat32_fs.spin2:3365, `CMD` from public `attemptHighSpeed()`).
- `do_mount` (≈:3919–4100) contains no speed/CMD6 reference — mount does NOT
  auto-negotiate high speed.
- SD_RT_raw_sector_tests contains no reference to any speed API (verified by grep).

Presence-without-execution flipping behavior ⇒ the mechanism is **placement**, not
function. This confirms, with a minimal reproducer, the previously documented
unexplained finding (post-v1.6.1 investigation): a never-executed 42-byte block
flipped cogcwd↔subdir_ops outcomes.

### 2.4 The corruption signature (byte-exact)

Readback = written bitstream shifted one bit late, carry propagating across bytes
(observed byte = expected>>1, MSB = previous expected byte's LSB):

- Pattern bytes: expected `0B 0C 0D 0E 0F` → read `05 86 06 87 07`
- Head magic: expected `7F 0C 1F 4E` (DEADBEEF^nonce) → read `3F 86 0F A7`
- format_tests MBR verify: wrote sig `$AA55` type `$0C` start `8_192` →
  read back sig `$D52A` type `$06` start `4_224` (same arithmetic)

Scope facts from the standalone failing run
(`SD_RT_raw_sector_tests_260811-172126.log`):

- Write is accepted by the card: `write diag: code=7 R1=$00 dresp=$05` (data
  accepted, CRC valid at the card), `lastCMD13err=$0000`, CMD13 pre-capture all
  `$FF`, R1 latency 0 ms. SD SPI data framing is start-token-relative, so the
  card accepting the block means the transmitted token+512+CRC was self-consistent.
- **Only read-back-of-just-written sectors is corrupted.** In the same failing
  program run: test "Read sector 0 (MBR signature)" PASSES (`$55 $AA` verified) and
  "Read high LBA 1,000,000" PASSES. mount_tests (43/0) parses boot sectors fine in
  its own ALL build — n.b. mount_tests is NOT an ALL build (RAW+DEBUG+STACK_CHECK),
  do not over-generalize from it.
- One sysclk at 350 MHz ≈ 2.86 ns; one bit at 25 MHz SCK = 40 ns = 14 sysclks.
  A one-BIT shift is therefore NOT a one-sysclk slip of a counter — characterize
  precisely what start-condition error produces exactly one extra/missing bit
  period at capture start.

### 2.5 Signature B is the same defect landing on metadata

The "created file not findable" family (stress/async #1-7/cogcwd/timestamp/
crc_validation/recovery/error_injection) is the same corruption applied to
directory/FAT sector round-trips: create writes the entry, the corrupted
readback path can't find it (`E_FILE_NOT_FOUND` -40 immediately after successful
create; timestamps read 0; `newDirectory()` setup failures). All of these
cleared when SPEED was removed from the build. Separately, async tests 8/10-13
showed `E_ASYNC_BUSY` (-91) cascades — re-verify these on the bench after the
layout fix before treating any of it as an independent defect.

## 3. What is already ruled out (verified by code reading of the a41c839 diff)

- `a41c839` touched ZERO streamer/smart-pin/SPI-transfer lines in the driver
  (`grep` over the diff for xinit/xfrq/STREAM_/P_SYNC/wxpin/wypin/waitxfi/
  sp_transfer/GETCRC: no hits). Its 365+/157− lines are logic-layer.
- Command-code collision (`CMD_TEST_INVAL_CACHES=51`): ruled out, dispatch table
  verified.
- The 14-wrapper mailbox-consumption refactor: verified correct against the worker
  dispatch table.
- `searchDirectory` volume-label filter: no attribute-bit overlap with normal files.
- Cluster-0/lazy-allocation changes, FAT reserved-bit mask: verified correct.

## 4. The reproducer recipe (3 min/run, bench-side)

In `src/regression-tests/SD_RT_raw_sector_tests.spin2`, pnut-ts branch (`#else` at
:84-88), replace `#pragma exportdef SD_INCLUDE_ALL` with the explicit flag list;
toggle `SD_INCLUDE_SPEED` (+REGISTERS). Run
`cd tools && ./run_test.sh ../src/regression-tests/SD_RT_raw_sector_tests.spin2`.
PASS build: 14/14. FAIL build: 2/5 with the §2.4 signature, deterministic.

## 5. Companion items (small, independent)

### 5.1 error_injection test #36 geometry guard
"SETUP: dir-extend fill practical at this geometry (<=16 sec/clus)" fails on
big-cluster cards (58GB card formats larger). Redesign so the check adapts or
skips scored-and-explained on large geometries; a setup guard must be able to
pass on every supported card in the rig.

### 5.2 register test #11 (CID PNM printable-ASCII) — decision needed
Card 2b returns non-printable PNM bytes. Either relax the assertion to what the
SD spec actually mandates, or classify as card-quirk with a documented waiver.
Check the spec before choosing.

### 5.3 volume test #9 error-code semantics — decision needed
`changeDirectory()` onto the volume label's name: driver returns `E_NOT_A_DIR`
(-43); the new isolation test expects `E_FILE_NOT_FOUND` (-40). Full invisibility
argues for -40. Decide, then align driver or test and document in the error guide.

## 6. Deliverables (container agent — no hardware)

1. **Mechanism analysis, P2KB-backed** (per the no-speculation rule: every step
   cited to P2KB or a factual code reading). Identify every point in the driver's
   read-capture and write-transmit paths where hub placement of code or DAT could
   alter timing relative to the free-running SCK smart pin: inline-PASM load/FIFO
   behavior around `xinit`, hub egg-beater phase at streamer start, smart-pin
   disable→streamer-enable handoff ordering, `waitxfi` semantics. Explain how a
   placement change produces exactly one bit period of displacement — and why only
   on the write→readback sequence while independent reads pass.
2. **Candidate fix** that makes capture/transmit phase deterministic regardless of
   placement (e.g., phase-anchoring the streamer start to an SCK edge event rather
   than code arrival time — validate feasibility against P2KB, do not invent
   instruction behavior). Must not violate the CLAUDE.md prohibitions: no byte
   loops, no bit-banging, no waitus band-aids, no sampling-mode changes without
   evidence.
3. **Instrumented verification plan for the bench**: exact builds to run (reuse §4
   reproducer plus deliberate layout perturbations — e.g., padded never-executed
   blocks of varying sizes), expected outcomes, and what constitutes proof of
   alignment-invariance. The bench session executes it and returns transcripts.
4. Fixes for §5.1 and proposals for §5.2/§5.3 (decisions stay with Stephen).

## 7. Constraints

- Nothing ships until the full regression sweep is green on the bench; changes
  enter through the normal sequence (style conformance → compile → regression →
  hardware).
- `DOCs/Plans/SOCKET-TIMING-CHARACTERIZATION-PLAN.md` (deferred) is related
  context: its measurand δ is the analog half of this margin; the fix here should
  make the digital phase deterministic so that plan's socket comparison stays clean.
- The worker-stack watermark data from both sweeps (max 122/512 measurement build)
  and suggested release STACK_SIZE 160 are unaffected by this work; do not fold
  stack changes into the fix commit.
