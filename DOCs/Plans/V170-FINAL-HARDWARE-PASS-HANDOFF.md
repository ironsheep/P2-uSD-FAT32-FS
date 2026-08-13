# v1.7.0 final hardware pass — handoff to the host-native agent

**Written:** 2026-08-13, container agent (no hardware)
**For:** the macOS host agent with the P2 Edge rig
**Status:** container work COMPLETE. Everything below is bench execution.

---

## 0. What this closes

Two gaps stand between the tree and the v1.7.0 tag. Neither is a suspected defect;
both are missing measurements.

**Gap 1 — the shipping tree has never run.** Both certifying sweeps of 2026-08-12
(574/574 on two cards) ran the *measurement* build at `STACK_SIZE = 512`. The release
build is 160. That is a 1408-byte DAT difference — a material layout change — so no
sweep has yet run the binary that ships.

**Gap 2 — the layout fix's own acceptance test was never run.** The layout-sensitivity
fix claims data-to-clock phase is independent of where the streamer's hub buffer sits.
`DOCs/Analysis/LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` section 6 step 4 specifies the
acceptance test for that claim. No transcript of it exists. It had been *reported* as
passed in three user-facing documents; that claim was withdrawn on 2026-08-13 (see
`DOCs/Plans/2026-08-13-EVOLUTION-DOC-PROVENANCE-AUDIT.md`).

---

## 1. Card

**Put the Gigastone 64GB in the rig.** (Catalog `DOCs/cards/gigastone-astc-64gb.md`;
serial `$0000_0F14`; reports as 58GB formatted — the label says 64GB.)

The **Gigastone 8GB** (`$0001_B9D5`) is not needed. It buys *geometry* coverage, and
geometry is unaffected by a `STACK_SIZE` edit — that dimension was certified on both
cards on 08-12. What changed is layout, which is card-independent.

Both runs below are destructive to card contents and authorized as such. Leave the card
**operational** (mountable) at the end.

Name transcripts by serial per `DOCs/Agent-Reports/README.md` — `..._SN0000-0F14_...` —
even though the card is identified by label above.

---

## 2. Run order

### Step 1 — buffer-alignment sweep (new tool, ~2 min)

```
cd tools
./run_test.sh ../diagnostic-tests/SD_buffer_alignment_sweep.spin2
```

**This tool is new and has never run on hardware.** It compiles clean in the container
(41857 bytes) but has no bench history — treat a surprising result as possibly the
tool's fault before concluding anything about the driver.

**What it does.** `writeSectorsRaw()`/`readSectorsRaw()` pass the caller's buffer pointer
straight through to `RDFAST #0, p_buf` / `WRFAST #0, p_buf`, so sweeping the pointer
sweeps the streamer's hub address with no recompile. It walks byte offsets 0,4,8..28 —
eight long-aligned positions, one full 32-byte period — in two phases: phase 1 varies
the write buffer (isolating `RDFAST`), phase 2 varies the read buffer (isolating
`WRFAST`). Two patterns each, classified by the same bit-shift classifier
`SD_tx_phase_shmoo` uses. Writes go only to LBA 100,000–100,001, the sanctioned scratch
sectors.

**PASS:** all 32 points report `CORRECT`, and the closing line reads
`ALL 32 POINTS CORRECT - layout invariance HOLDS`.

**HARD STOP conditions:**

- Any `SHIFTED-LATE` or `SHIFTED-EARLY` verdict — the fix is incomplete. **Do not tag.**
  Record which offsets failed and in which phase. A phase-1-only failure implicates the
  write path; phase-2-only implicates the read path.
- `GUARD VIOLATED` — results are invalid, the tool overran its buffer. Tool defect, not
  a driver finding.
- `WRITE-FAIL` / `READ-FAIL` verdicts — the transfer itself failed. Check the card is
  seated and initialized before reading anything into it.

### Step 2 — full sweep at the release configuration (~35–45 min)

```
cd tools
./run_regression.sh --include-format
```

**No `--stack-report`.** That is the entire point of this run: it must be the release
configuration, `STACK_SIZE = 160`, which is what ships.

**No `--clean-each`.**

**PASS:** 574/574 across 27 suites, 0 fail, closing audit 23/23 — matching the 08-12
result on this card exactly.

**HARD STOP:** any red. Zero tolerance stands. A failure here is more interesting than
usual because the *only* delta from the green 08-12 run is the stack size and its layout
consequence — so a red is a layout-sensitivity signal, not a routine regression. Capture
it and stop rather than re-running.

---

## 3. Scope discipline

**The source tree is frozen.** `diagnostic-tests/` does not ship and is not compiled by
`run_regression.sh`, so adding the probe did not touch the certified tree. Do not edit
anything under `src/` during this session — a source change reopens the sequence at
style conformance and requires a fresh sweep. If step 1 or 2 finds something requiring a
code change, **stop and hand back**; do not fix and re-run in the same session.

---

## 4. Known gap this pass does NOT close

The **single-sector** write path's buffer alignment is not swept, and cannot be.
`writeSectorRaw()` bytemoves the caller's data into the driver's internal `buf` and
writes from there, so its streamer source address is fixed by the DAT layout. Only the
multi-block path plumbs the caller pointer through.

Covering it literally means the original approach — a never-executed `BYTE 0[N]` DAT
block in a diagnostic top file, N in {4,8,12,16,20,24,28}, seven build/download cycles,
roughly ten minutes.

**Stephen's call, and the container agent's recommendation was to skip it:** the two
08-12 sweeps ran 27 distinct top-level binaries per card — 27 different link layouts,
each placing the driver's `buf` somewhere different — all green. That is incidental but
real coverage using real workloads. What it lacks is knowing *which* positions were hit.
If skipped, the documents already describe this path's coverage as incidental rather
than designed.

---

## 5. On return

Report back:

1. Step 1 verdict lines and the closing summary line, verbatim.
2. Step 2 per-suite totals and the closing audit.
3. Transcript filenames (by serial).

Then remaining before the tag, all container-side:

- Set the `## [1.7.0] - YYYY-MM-DD` heading in `CHANGELOG.md` to the actual tag date.
  It currently reads `2026-08-12` as a placeholder. This must be the **last** edit.
- Stephen's accept-or-fix on the one open release-gate item: **S6** —
  `deleteFile()` reports read-only/hidden/system files as `E_FILE_NOT_FOUND`. Plus the
  carried items: Maxwell NCard re-decision, Samsung 8GB (blocked), todo #3240, #3348.
- Then tag and push.

---

## 6. Context the running agent should load first

| Key / file | Why |
|---|---|
| `sprint_v170_release_prep_state` (todo-mcp context) | full state of the release prep |
| `DOCs/Plans/2026-08-13-EVOLUTION-DOC-PROVENANCE-AUDIT.md` | what was withdrawn and why — read before citing any layout-fix mechanism |
| `DOCs/Analysis/LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` | the root cause; **see its end appendix for three corrections** |
| `DOCs/Plans/V170-RELEASE-PREP-REQUEST.md` | Stephen's original scope for this phase |

**One standing caution carried from the provenance audit:** the mechanism behind the
layout defect is *not* settled. The attribution of `RDFAST`'s 10–17 sysclk spread to the
buffer's hub address was withdrawn; what is established is only that a variable-latency
instruction sat inside a phase-critical window. Step 1 above is the first measurement
that bears directly on the question. Do not re-narrate the withdrawn mechanism in any
finding.
