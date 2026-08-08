# Proposal: `IFDEBUG[n]` — compile-time block elision keyed to a DEBUG channel

**Status:** Draft for discussion with Parallax
**Author:** Iron Sheep Productions, LLC
**Date:** 2026-08-07
**Applies to:** Spin2 language / PNut + pnut-ts compilers
**Measured against:** pnut-ts v1.55.1 (build 2026-07-12)

> **Read §4 before §5.** This is an **ergonomics and safety** proposal, not a capability
> proposal. The behavior it asks for is fully achievable today with existing directives
> (§4.3, measured). What it removes is three-deep boilerplate at every use site and a
> multi-place coupling that nothing enforces. Judge it on that basis.

---

## 1. Summary

`DEBUG_MASK` lets a developer switch a debug channel off and have every `DEBUG[n]()`
statement on that channel generate no code. What it does not do is remove the **code that
exists only to serve those statements** — the `if` that decides whether to report, the
locals that gather the values, the helper call that formats them.

The result is a shape every non-trivial P2 project ends up writing:

```spin2
    if NOT checkStackGuard()                     ' still compiled, still evaluated
        DEBUG[CH_API]("guard failed")            ' vanishes when CH_API is masked off
        halt_worker()                            ' still compiled
```

With the channel off, the condition is still evaluated at runtime on every pass, and the
block is still emitted.

This proposes a compiler-level block conditional, `IFDEBUG[n]` (and its inverse
`IFNDEBUG[n]`), that compiles its indented block **only when `DEBUG[n]()` would itself
compile** — one construct replacing the three nested directives §4.3 requires today.

---

## 2. What the gap actually is

The gap is narrower than it first appears. Most of the surrounding need is already met:

| Need | Existing mechanism |
|---|---|
| Elide a debug *statement* | `DEBUG[n]()` + `DEBUG_MASK` |
| Condition a *constant* on a channel | `DEBUG_MASK` is a normal CON: `(DEBUG_MASK >> CH_API) & 1` |
| Condition code on a *build flag* | `#IFDEF` / `#IFNDEF` with `-D` |
| Detect a debug-enabled build | `__DEBUG__`, auto-defined with `-d` (verified §4.2) |
| Suppress output *per cog* at runtime | `DEBUG_COGS` |

**Not directly expressible:** removing an entire **block of executable code** based on a
`DEBUG_MASK` channel bit. It is achievable *indirectly* (§4.3), which is why this is an
ergonomics proposal.

---

## 3. Why the preprocessor cannot do it directly

The instinctive fix is `#IF DEBUG_MASK & (1 << CH_API)`. That cannot work:

**3.1 There is no `#IF` with expressions.** Spin2's preprocessor provides `#IFDEF`,
`#IFNDEF`, `#ELSEIFDEF`, `#ELSEIFNDEF`, `#ELSE`, `#ENDIF` — all testing symbol
*presence*. (P2KB `p2kbSpin2PreprocessorOverview`.)

**3.2 The preprocessor cannot see `DEBUG_MASK`.** It is a CON integer resolved by the
compiler, in a pass that runs *after* preprocessing. Adding `#IF` alone would not help;
the preprocessor would need valued `#DEFINE`s plus an expression evaluator, giving Spin2
a second constant namespace that resembles CON, can silently disagree with it, and is a
well-known source of confusion in C. That is explicitly **not** what this asks for.

---

## 4. The workaround, measured

### 4.1 Invert the dependency

Make per-channel `#DEFINE` symbols the single source of truth and **derive** `DEBUG_MASK`
from them, so the mask bit and the guarded blocks cannot drift apart:

```spin2
#define DBG_CH_API                          ' ONE switch per channel

CON
#ifdef DBG_CH_API
    M_API = 1 << CH_API
#else
    M_API = 0
#endif
    DEBUG_MASK = M_API | M_MOUNT | M_FILE
```

### 4.2 `__DEBUG__` is available and works

Verified by size differential (a 1024-byte DAT block guarded by `#ifdef __DEBUG__`):

| Build | Size | Block present? |
|---|---|---|
| `pnut-ts -d` | 10254 | **yes** — auto-defined |
| `pnut-ts -d -D __DEBUG__` | 10254 | yes — identical, already defined |
| `pnut-ts` (no `-d`) | 6296 | no |
| `pnut-ts -D __DEBUG__` | 7320 | yes (+1024, forced) |

`__DEBUG__` behaves exactly as P2KB documents.

### 4.3 The complete shape — and it is sufficient

Guarding on the channel symbol alone is **not** enough: with the channel defined but no
`-d`, the block still compiles. Nesting `__DEBUG__` closes that hole, giving a block that
tracks *both* conditions governing whether `DEBUG[n]()` would compile:

```spin2
#ifdef __DEBUG__
#ifdef DBG_CH_API
    if NOT checkStackGuard()
        DEBUG[CH_API]("guard failed")
        halt_worker()
#endif
#endif
```

**Measured, one probe file, pnut-ts v1.55.1:**

| Build | baseline | channel guard only | **nested `__DEBUG__` + channel** |
|---|---|---|---|
| debug (`-d`) | 9298 | 9350 | **9350** — identical, block present |
| release (no `-d`) | 6308 | 6324 (**+16 residue**) | **6308** — exactly baseline, fully elided |

And for reference, the naive shape (masked statement inside a live `if`) with the channel
**off** measures 9314 against a 9298 baseline — **+16 bytes of live conditional** — while
with the channel **on** it is byte-identical to the guarded shape at 9350.

**Conclusion: §4.3 is correct and complete in both build configurations.** Any claim that
this behavior is unreachable without a language change is false.

---

## 5. Proposed feature

### 5.1 Semantics

`IFDEBUG[n]` compiles its indented block **if and only if `DEBUG[n]()` would compile at
that point**:

> **compile the block ⟺ debug is enabled for this build (`-d`) AND bit *n* is set in `DEBUG_MASK`**

When false, the block is removed entirely — no code, no evaluation. It is the same
condition the compiler already evaluates for `DEBUG[n]()`, at the same layer, so the two
cannot drift.

`IFNDEBUG[n]` is the exact inverse, for code that exists only when a channel is *off*.

In short: `IFDEBUG[n]` collapses §4.3's two nested `#ifdef`s plus the derived-mask CON
stanza into one construct, and makes the coupling structural rather than conventional.

### 5.2 Compile-time, not runtime

A runtime form would leave exactly the code we are removing. Two consequences, both worth
documenting because both are easy to get wrong:

- **No interaction with `DEBUG_COGS`.** That is a runtime gate on *output*; this is a
  compile-time gate on *existence*. A block `IFDEBUG` compiled may still produce no output
  on a cog excluded by `DEBUG_COGS`. Independent, as `DEBUG_MASK` and `DEBUG_COGS`
  already are.
- **The channel index must be a compile-time constant expression.** `IFDEBUG[someVar]` is
  a compile error, not a runtime dispatch.

### 5.3 Shapes — which are useful

**Shape A — statement block. (Core.)**

```spin2
PRI fs_worker()
    IFDEBUG[CH_API]
        if NOT checkStackGuard()
            DEBUG[CH_API]("stack corrupted after cmd ", udec_(cur_cmd))
            halt_worker()
```

Nests inside methods, inside runtime `IF`/`CASE`/`REPEAT`, and inside itself.

**Shape B — inverse block. (Recommended; small increment.)**

```spin2
    IFNDEBUG[CH_TIMING]
        fast_path()                          ' only when instrumentation is off
```

**Shape C — declaration-level elision. (Highest size value; reasonable as phase 2.)**

Debug-only helpers and their storage are pure overhead in a release build, and today need
a separate symbol that can fall out of step with the mask:

```spin2
IFDEBUG[CH_API]
PRI dump_handle_table() | idx
    ...

DAT
IFDEBUG[CH_API]
    trace_buf   BYTE  0[512]                 ' 512 bytes reclaimed in release builds
```

Largest parser change, so shipping A + B first is reasonable.

**Shape D — constant-expression / RHS form. (Explicitly NOT proposed.)**

Already expressible; needs no new syntax:

```spin2
CON
    HAS_API_DEBUG = (DEBUG_MASK >> CH_API) & 1        ' works today
```

`DEBUG_MASK` is an ordinary CON readable in any constant expression. An intrinsic here
would be a second way to spell what the language already says.

**Shape E — same-line single statement. (Not proposed.)** `IFDEBUG[CH_API] halt()` breaks
the block-structured convention `IF`/`REPEAT` already follow.

### 5.4 On `ELSE`

Deliberately omitted. `IFDEBUG[n]` + `IFNDEBUG[n]` covers the ground with no grammar
ambiguity, whereas an `ELSE` attached to `IFDEBUG` invites confusion with the runtime
`IF`/`ELSE` it nests against. It can be added later; it cannot easily be removed.

---

## 6. What it improves, in real code

From `micro_sd_fat32_fs.spin2` (P2-uSD-FAT32-FS), the worker-cog stack integrity gate —
42 bytes, plus a `checkStackGuard()` call on **every command the worker executes**:

```spin2
    if NOT checkStackGuard()
        DEBUG[CH_API]("  [fs_worker] STACK CORRUPTED after cmd ", udec_(cur_cmd))
        pb_status := E_STACK_OVERFLOW
        worker_stack_fault := true
        cog_id := -1
        COGATN(1 << pb_caller)
        cogstop(COGID())
```

Today's correct fix is §4.3's two nested `#ifdef`s. With `IFDEBUG[CH_API]` it is one line
and the coupling is structural. The general shape — *a check that exists only to report
something* — is pervasive in driver code: bounds assertions, invariant checks, protocol
validation, buffer guard verification.

**Scope note:** `IFDEBUG` would let this block be removed cleanly from release builds. It
would **not** explain or fix the separate defect in which this block's presence changes
runtime behavior while never being taken. Different problem; do not read this proposal as
a fix for it.

---

## 7. Why a language change rather than convention

With §4.3 established as sufficient, the honest case rests on three points — all
ergonomic:

1. **Nothing enforces the coupling.** The `#define`, the CON stanza, and the two nested
   `#ifdef`s at each use site are four places that must agree. A channel added to one and
   not the others fails silently, and the failure mode is invisible code rather than a
   compile error.
2. **Three-deep nesting at every use site.** §4.3's shape is correct but heavy, and P2KB's
   own preprocessor guidance lists deep nesting as an anti-pattern. In practice developers
   write the one-deep version and unknowingly ship the residue.
3. **Discoverability.** A construct documented beside `DEBUG_MASK` is found by the person
   already hitting the problem; a four-part convention has to be taught.

**This is a real but modest case.** If the answer is "document the §4.3 pattern and move
on," that is a defensible outcome and the measurements here support it directly.

---

## 8. Compatibility and adoption

**This should not ship in one compiler only.** Spin2 code moves through OBEX and is built
by both PNut and pnut-ts; a directive accepted by one and rejected by the other fragments
the ecosystem and pushes the cost onto every downstream user. The request is for the
feature to land in **PNut and pnut-ts together**, with pnut-ts following PNut on syntax.

- **Backward compatible.** New keywords in the `DEBUG[n]` family; existing code unaffected.
- **Version gating.** Presumably a `{Spin2_v##}` bump, per precedent for keyword additions.
  (`DEBUG_MASK` needed none, being a CON rather than a keyword — that precedent does not
  apply.)
- **flexspin.** A third-party compiler would need to follow; §5.1's single rule keeps that
  burden small.

---

## 9. Alternatives considered

| Alternative | Verdict |
|---|---|
| `#IF <expr>` reading `DEBUG_MASK` | **Rejected.** Preprocessor precedes CON resolution (§3.2); needs valued `#DEFINE`s + evaluator; second constant namespace |
| **Convention only — §4.3 nested guards** | **Viable and sufficient.** The genuine alternative to this proposal; adopt regardless as interim guidance |
| Runtime `if (DEBUG_MASK >> n) & 1` | **Rejected.** Emits exactly the code being removed |
| Compiler dead-code elimination | **Rejected.** Far larger change; unpredictable; the point is a *guarantee*, not an optimization |

---

## 10. Asks

1. A decision on whether §7's ergonomic case justifies the feature, given §4.3 works today.
2. If yes: agreement on §5.1's rule and `IFDEBUG[n]` / `IFNDEBUG[n]` naming, and whether
   Shape C is phase 1 or phase 2.
3. **Unrelated defect found while measuring this — worth fixing on its own:**
   `#error` and `#warn` appear to be silently ignored by pnut-ts v1.55.1. An
   *unconditional* `#error "..."` at file scope compiles clean and exits 0:

   ```
   $ pnut-ts -d -o ctlout ctl.spin2
   pnut-ts: Wrote ctlout (9230 bytes)
   pnut-ts: Done          # exit code 0 — the #error never fired
   ```

   This is dangerous well beyond this proposal: `#error` is the standard way to make an
   unsupported build configuration fail loudly, and a silently-ignored one converts a
   deliberate hard stop into a silent mis-build. It also invalidated an earlier draft of
   this document, which used `#error` to probe for `__DEBUG__` and wrongly concluded the
   symbol was missing.

---

## Appendix: reproducing the measurements

`diagnostic-tests/SD_debug_mask_block_elision_probe.spin2` builds all shapes under
preprocessor control, so every variant comes from one file:

```bash
# DEBUG BUILD
pnut-ts -d                                   -o A_baseline    probe.spin2   # 9298
pnut-ts -d -D PROBE_ONE                      -o B_masked_off  probe.spin2   # 9314  (+16 residue)
pnut-ts -d -D PROBE_TWO                      -o C_chan_off    probe.spin2   # 9298
pnut-ts -d -D PROBE_TWO  -D DBG_CH_B         -o D_chan_on     probe.spin2   # 9350
pnut-ts -d -D PROBE_ONE  -D DBG_CH_B         -o E_masked_on   probe.spin2   # 9350
pnut-ts -d -D PROBE_THREE -D DBG_CH_B        -o F_nested_on   probe.spin2   # 9350

# RELEASE BUILD (no -d)
pnut-ts                                      -o G_baseline    probe.spin2   # 6308
pnut-ts    -D PROBE_TWO  -D DBG_CH_B         -o H_chan_on     probe.spin2   # 6324  (+16 residue)
pnut-ts    -D PROBE_THREE -D DBG_CH_B        -o I_nested_on   probe.spin2   # 6308  (fully elided)
```

Control for the §10.3 defect:

```bash
printf 'CON\n  _CLKFREQ = 350_000_000\n#error "must fire"\nPUB main()\n  waitms(1)\n' > ctl.spin2
pnut-ts -d -o ctlout ctl.spin2 ; echo "exit: $?"      # observed: compiles, exit 0
```
