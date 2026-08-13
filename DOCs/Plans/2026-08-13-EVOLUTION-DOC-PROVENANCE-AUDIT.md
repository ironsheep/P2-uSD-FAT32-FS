# Provenance audit — `DOCs/DRIVER-EVOLUTION-v1.6.0-to-v1.7.0.md`

**Date:** 2026-08-13
**Trigger:** Stephen challenged the buffer-address-to-hub-slot association in §4.3. The
claim did not survive scrutiny, so every substantive claim in the document was
re-classified by how it was established.

**Classification:**

| Tag | Meaning |
|---|---|
| **V** | Verified directly this session against source, tool output, or a transcript |
| **I** | Inherited from a prior analysis document and restated — not independently checked |
| **W** | **Withdrawn** — asserted, then found unsupported or wrong |

The failure mode being audited for: an inference from a prior investigation, restated in
my own words, becomes indistinguishable from a measured fact. Three of our own artifacts
carried the §4.3 attribution — the driver DAT comment, the sprint context note, and the
root-cause analysis — but the first two were written *from* the third. Agreement was
propagation, not corroboration.

---

## Findings requiring action

### F1 — §4.7 invariance acceptance test was never run **[W — CLOSED 2026-08-13]**

> **RESOLVED.** The acceptance test ran on 2026-08-13 and passed: all 32 points
> correct, `tools/logs/SD_buffer_alignment_sweep_260813-155251.log`. It was executed
> by a runtime buffer sweep reaching all eight slice positions rather than the
> seven-build DAT-displacement approach originally specified. The withdrawal below
> stands as the record of what was wrongly claimed before the measurement existed.

The document stated: *"The driver's DAT was deliberately displaced by 1, 2, 4, 8, 12, 36
and 60 bytes and the suites re-run at each: all pass."*

`LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md` §6 step 4 defines that sweep as **the plan** —
*"Alignment-invariance proof (the actual acceptance test) … **All must pass** … any
failure = fix incomplete, STOP."* Imperative, not a result.

Evidence searched: no transcript in `tools/logs/` matching pad/align/displacement; no
displacement vehicle in `diagnostic-tests/` (only `SD_tx_phase_shmoo`). **No record that
it ran.**

The same unsupported claim appeared in `SD-CARD-DRIVER-THEORY.md` and
`SPI-PHASE-MARGIN-API.md`. All three corrected.

**This is the one finding with release-gate weight.** The layout fix's own designated
acceptance test has no result. What *was* run — the pad shmoo and two 574/574 sweeps —
supports the shipped configuration but does not measure invariance across layouts.

**Note on the N set.** Even as specified it is weaker than it reads: hub slices are
long-granular, so N ∈ {1,2,4,8,12,36,60} covers four distinct slice positions with one
duplicate. N ∈ {4, 8, 12, 16, 20, 24, 28} walks all eight once each.

### F2 — §4.3 hub-address attribution **[W]**

Stated: the 10–17 sysclk `RDFAST` spread "is the hub egg-beater slot wait for the buffer
address's hub slice," and phase was therefore "a function of the driver's hub address."

`p2kbArchP2ArchitectureMentalModel` states a hub operation completes "in 2-9 clocks
**depending on when the COG's slot arrives**" — issue time, not requested address.
`p2kbArchHub`'s slicing section reads the other way. The two are unreconciled and we
measured neither.

Withdrawn from the evolution doc, `SD-CARD-DRIVER-THEORY.md`, and the driver's DAT
comment at `writeSector()`, which now carries an explicit *do not re-narrow this*
instruction so the attribution is not reintroduced.

Retained and sufficient: `RDFAST` has documented variable latency; it sat inside the
phase window; therefore phase was not a compile-time constant.

### F3 — "36 bytes = 4 hub slots" **[W]**

`36 mod 8 = 4` computed on a **byte** count. Slices are long-granular — P2KB's own
block-transfer figures ("1 long per clock", "4 bytes per clock") require it — so 36 bytes
is 9 longs ≡ 1 slice. Dropped rather than corrected; the quantity was never load-bearing.
Origin: `LAYOUT-SENSITIVITY-ROOTCAUSE-ANALYSIS.md:130`, which also carries `42 ≡ 2 (mod 8)`
at line 53 with the same error.

The measured part — DAT symbol `$4A1F` → `$4A43`, +36 bytes under `SD_INCLUDE_SPEED` —
stands.

### F4 — §4.1 symptom table aggregated across different sweeps **[W]**

The document presented four suites failing together, and claimed all four "were green on
the committed tree, same card, days earlier."

Read directly from the transcripts:

| Sweep | speed | crc_diag | subdir_ops | cogcwd |
|---|---|---|---|---|
| `sweep_card2b_260806` | 15/0 | 14/0 | 18/0 | **0/5** |
| `sweep_card2b_260807_cleaneach` | **13/2** | **11/3** | **6/12** | 5/0 |
| `sweep_card2b_260807_nogate` | 0/0 (no result) | **11/3** | 0/0 (no result) | 5/0 |

They never failed together. `cogcwd` failed on 08-06 while the other three passed; the
reverse on 08-07. The "all green days earlier" claim is false for `cogcwd`.

**This finding cuts against F2's withdrawn hypothesis and is worth keeping in view.** A
failing set that migrates between builds fits a marginal phase that some configurations
lose. A phase deterministically fixed by layout predicts a *stable* per-build failing set.
Combined with the fact that the shipped pad was 2 — one phase step from the failing
residue — the "sitting next to the cliff" explanation fits the observations better than
the address hypothesis did. Neither is measured.

### F7 — the withdrawn hypothesis was already on our disproven ledger **[W]**

`DOCs/Analysis/COUNTERFEIT-ASDFG-SDSC-INVESTIGATION.md` logs **H-CodeLayout** — "Hub
address shifts affect cog timing" — as **Disproven 2026-05-24**, with Stephen's
correction recorded verbatim: *"Code location should not affect performance."* The
reasoning given there: *"The P2 egg-beater gives each cog a deterministic slot pattern
relative to its own clock. Cog instruction timing does not depend on absolute hub
addresses."* `SDSC-DEEP-ANALYSIS-AND-ROADMAP-2026-05-26.md` repeats the ruling.

The 2026-08-11 root-cause analysis re-adopted that idea as its central mechanism eleven
weeks later. **The first-order cause of this whole episode is therefore not propagation
— it is that the project's own disproven-hypothesis ledger was never consulted.**
Propagation is why it then spread to four documents and the driver source.

Full treatment in the analysis document's own appendix, section 4.

### F5 — §4.6 pad measurement understated **[V, corrected]**

Stated "all 24 other measured points pass." The longest run measures pads 2–30: four
failures (8, 15, 22, 29) and **25** passes. Now quoted as a table from
`SD_tx_phase_shmoo_260811-213419.log`, with the tool's own
`SUGGESTED DAT DEFAULT: 4 (band center)` line rather than my paraphrase.

The failure label in the transcripts is `SHIFTED-LATE`, which is direct evidence for the
one-bit-late claim — previously asserted without citing it.

### F6 — §4.2 memory map **[I]**

Addresses quoted from `POST-V161-ROOT-CAUSE-ANALYSIS.md`, which read them from a build
map. Not re-derived; and the v1.7.0 tree has changed there (`cog_stack_end_mark` now sits
between stack and guard). Marked in-document as the layout at the time of that
investigation.

---

## Claims verified directly this session **[V]**

| Claim | Verified against |
|---|---|
| Current write sequence, both sites | `micro_sd_fat32_fs.spin2` — read verbatim |
| Read path uses `FLTL`+`DIRH`, `WYPIN` before `WAITX`/`XINIT` | same; corrected a prior error of mine that showed `DIRL`/`DRVL` and the wrong order |
| `RDFAST` timing `WRFAST finish + 10...17` | `p2kbPasm2Rdfast` |
| Hub slot wait 0–7 clocks / "2-9 clocks depending on when the COG's slot arrives" | `p2kbArchHub`, `p2kbArchP2ArchitectureMentalModel` |
| `do_delete()` checks the entry write and leaves the chain intact | source |
| `allocateCluster()` guards all four FAT writes | source |
| `searchDirectory` propagation expression | source |
| `readNextSector`/`clearCluster` return `status` | source signatures |
| `eofHandle : is_eof`, `isFileContiguous : bContiguous` | source signatures |
| `stop() : status`, `handleError`, `lastFlushError`, `clearFlushError` exist | source |
| `prepStackForCheck` writes `$addee5e5` one long past the stack | `isp_stack_check.spin2` |
| `cog_stack_end_mark` now separates stack from guard | source DAT + its comment |
| Pad shmoo results | three `SD_tx_phase_shmoo_*.log` transcripts |
| 574/574 both cards, audit 23/23 | `shakedown_SN0000-0F14_260812.txt`, `shakedown_SN0001-B9D5_260812.txt` |
| Stack watermark 122/512 in `SD_RT_defrag_tests`, both cards | same transcripts |
| Per-suite counts totalling 574 | `src/regression-tests/README.md`, arithmetic checked |
| Formatter capacity table thresholds | `isp_format_utility.spin2` |
| All five static gates exit 0 | run this session |

## Claims still inherited and unverified **[I]**

Retained in the document because they are attributed there to their source, not asserted
as first-hand:

| Claim | Source | Why not verified |
|---|---|---|
| v1.6.0's two corruption defects' mechanisms | CHANGELOG v1.6.0 + `SD_RT_fatchain_tests` purpose | Pre-dates available transcripts; suite exists and passes, which confirms current behaviour but not the historical mechanism |
| §5.1 stack-detector attribution — the exact 7-suite set correspondence | `POST-V161-ROOT-CAUSE-ANALYSIS.md` | The *fix* is verified in source; the historical sweep correlation is not re-derived |
| `mount_tests` 15/16 → 31/0 on the fix | same | No transcript located |
| §3.1's five later defects "found by hand-editing error paths" | audit narrative | No artifact enumerates them |
| v1.3.2 / v1.5.1 / v1.5.2 timing lineage | CHANGELOG entries + the `writeSector` history comment | Entries are ours and consistent; not traced to the commits |

---

## Recommendation

1. **Run the F1 displacement sweep before the tag**, with N ∈ {4, 8, 12, 16, 20, 24, 28}.
   It needs a `BYTE 0[N]` block in a test top file and one suite run per point. This is
   the fix's own acceptance criterion and it is currently unmet.
2. If it is *not* run, the release should say so rather than carry an invariance claim
   that rests on argument alone — the documents now do say so.
3. F2/F4 leave the *cause* of the phase variation unresolved. That does not block the
   release: the fix removes a variable-latency instruction from the window whichever
   hypothesis is right. It should stay recorded as open rather than settled.
