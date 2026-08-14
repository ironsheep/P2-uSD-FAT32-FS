#!/bin/bash
#
# run_regression.sh - Unified regression runner for SD FAT32 driver
#
# Usage: ./run_regression.sh [options]
#
# Runs all regression suites in dependency order (foundational-first), with
# per-file progress and a final summary table. Designed to run END-TO-END,
# UNATTENDED, in a single invocation — no chunking, no manual resume.
#
# Options:
#   --from <name>      Resume from a specific suite (substring match on basename).
#                      Compiles only that suite and remaining, then runs from there.
#   --include-format   Include format test (WARNING: erases SD card!)
#   --compile-only     Only compile all tests, do not run on hardware
#   --no-reformat      Do NOT reformat the card during the run (see below)
#   --reformat-only    Reformat the card and exit (recovery after a failed run)
#   --stop-on-failure  Halt at the first failing suite (forensic runs — see below)
#   --no-preflight     Skip the card-identify / sweep-start-fsck preflight
#   --log <file>       Tee all output to <file> (poll it while a background run works)
#
# SCORING: SILENCE IS NOT SUCCESS
# -------------------------------
# A suite is scored ok ONLY if it produced a parseable totals line. Two rules
# enforce that, and both exist because the runner used to score silence green:
#
#   * NO-SUMMARY => FAIL. SUITE_STATE defaults to "ok", so a suite that failed
#     its mount, bailed, and printed nothing but END_SESSION exited 0 with no
#     totals and was recorded as ok 0/0. Every mount-fail and every
#     SETUP-NOT-MET path in every suite was therefore a silent pass. A completed
#     run with no "Tests - Pass:" line now scores fail with reason "no-summary".
#   * BAD TEST COUNTS => FAIL. The framework prints that line when the number of
#     tests it started does not match the number it scored -- i.e. a test was
#     counted and then never recorded a result. That now scores fail with
#     reason "count-mismatch" rather than being a warning nobody reads.
#
# Truncation is the reason both matter on real hardware: the serial capture can
# be cut off mid-line, and the line most often lost is the totals line itself.
# A truncated pass and a truncated failure are indistinguishable downstream, so
# the only safe reading of "no totals" is failure.
#
# REFORMAT-AFTER IS CONDITIONAL
# -----------------------------
# REFORMAT_AFTER runs only when the suite did NOT pass. On a green run the
# suite's own verified end state IS a clean baseline, so a reformat there costs
# a minute of wall clock and proves nothing. REFORMAT_BEFORE is a different
# thing and is not conditional: fatchain wants a deterministic FAT layout so a
# chain bug reproduces, not a capacity guarantee.
#
# END-TO-END BY DEFAULT
# ---------------------
# A certification sweep wants every suite's result in ONE pass, so by default a
# failing suite is RECORDED and the run CONTINUES. Two mechanisms make that safe:
#
#   1. Infrastructure failures are retried, not counted as test failures. A
#      run_test.sh exit 2 (serial download / checksum glitch — a known USB
#      transient on this bench) is retried once. If it fails twice it is
#      reported as INFRA, kept distinct from a real test failure.
#   2. After a failing suite that is listed in REFORMAT_AFTER, the card is returned
#      to a clean FAT32 baseline before the next suite.
#
#      NOTE THE LIMIT: that list holds only fatchain and format. Every OTHER suite
#      starts on whatever the previous one left behind, so cascade IS possible and
#      debris from an earlier suite can read as a defect in a later one. Use
#      --clean-each for certification sweeps to reformat before EVERY suite and make
#      each result an independent measurement. (This note replaces an earlier claim
#      here that one failure "cannot cascade" -- the code never did that.)
#
# Use --stop-on-failure for DETECT-style forensic runs, where the on-card damage
# left by the failing suite IS the evidence and must not be reformatted away.
#
# PREFLIGHT / CLOSING AUDIT
# -------------------------
# Before anything writes to the card, a hardware run identifies the card
# (SD_card_identify: capacity, geometry, SN, warnings) and runs SD_FAT32_fsck
# (check AND repair) on its INCOMING state, so the transcript is self-labeling
# and lost cluster chains leaked by the previous run are reclaimed — once, at
# sweep start, never mid-sweep. The reported Repairs count is the per-run leak
# metric. A sweep-start fsck failure is NOT fatal — the card may have been left
# dirty by an earlier aborted run, and the baseline reformat is about to fix it.
# A card-identify failure IS fatal: no card, no run. After the last suite a
# read-only SD_FAT32_audit runs; that CLOSING audit must pass — it is the run's
# proof that the sweep leaves the card healthy.
#
# CARD IS SCRATCH (regression runner only)
# ----------------------------------------
# Project policy: authorizing a regression run authorizes formatting the card.
# So a hardware run treats the card as scratch by default: it establishes a
# clean FAT32 baseline before the first suite and reformats around the suites
# that are genuinely destructive (see REFORMAT_BEFORE / REFORMAT_AFTER), so a
# full run goes end-to-end unattended and leaves the card mountable.
#
# GUARD: this destructive behavior lives in THIS script only. Single-suite
# tools/run_test.sh never reformats — it is used here purely as the launcher
# for the format vehicle (src/UTILS/SD_format_card.spin2), unmodified.
# --compile-only never touches hardware, so it never reformats.
#
# Reformats are the backstop, not the routine: suites are expected to
# self-establish and self-clean their own fixtures.
#
# Under --stop-on-failure the runner does NOT auto-reformat after a failing
# suite — that would destroy the on-card forensic evidence (e.g. the fatchain
# DETECT run, where the post-failure FAT/VBR damage IS the evidence). It prints
# a recovery hint instead; use --reformat-only when done inspecting the card.
# In the default continue-on-failure mode the card IS returned to baseline after
# a failing destructive suite, because the run has to keep going.
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed, an INFRA failure persisted, a reformat failed,
#       or the closing audit failed
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Verify we're in tools directory ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR_NAME="$(basename "$SCRIPT_DIR")"

if [[ "$TOOLS_DIR_NAME" != "tools" ]]; then
    echo -e "${RED}Error: This script must be run from the tools/ directory${NC}"
    exit 1
fi

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGTEST_DIR="$PROJECT_ROOT/src/regression-tests"
LOG_DIR="$SCRIPT_DIR/logs"

# --- Parse Arguments ---
INCLUDE_FORMAT=false
COMPILE_ONLY=false
RUN_ONLY=false
FROM_SUITE=""
EXTERNAL_PINS=false
REFORMAT=true
CLEAN_EACH=false
REFORMAT_ONLY=false
STOP_ON_FAILURE=false
PREFLIGHT=true
TEE_LOG=""
STACK_REPORT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --log requires a file path${NC}"
                exit 1
            fi
            TEE_LOG="$2"
            shift 2
            ;;
        --from)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --from requires a suite name (substring match)${NC}"
                exit 1
            fi
            FROM_SUITE="$2"
            shift 2
            ;;
        --include-format)  INCLUDE_FORMAT=true; shift ;;
        --compile-only)    COMPILE_ONLY=true; shift ;;
        --run-only)        RUN_ONLY=true; shift ;;
        --external)        EXTERNAL_PINS=true; shift ;;
        --no-reformat)     REFORMAT=false; shift ;;
        --clean-each)      CLEAN_EACH=true; shift ;;
        --reformat-only)   REFORMAT_ONLY=true; shift ;;
        --stop-on-failure) STOP_ON_FAILURE=true; shift ;;
        --no-preflight)    PREFLIGHT=false; shift ;;
        --stack-report)    STACK_REPORT=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--from <name>] [--include-format] [--compile-only] [--run-only]"
            echo "          [--external] [--no-reformat] [--reformat-only]"
            echo "          [--stop-on-failure] [--no-preflight] [--log <file>] [--stack-report]"
            echo ""
            echo "Options:"
            echo "  --from <name>      Resume from suite matching <name> (substring match)"
            echo "  --include-format   Include format test (WARNING: erases SD card!)"
            echo "  --compile-only     Only compile, do not run on hardware"
            echo "  --run-only         Only recompile stale .bin files (source or driver newer)"
            echo "  --external         Compile with -D SD_PINS_EXTERNAL (use external SD header)"
            echo "                     Default (no flag): P2 Edge onboard SD slot."
            echo "  --no-reformat      Do not reformat the card during the run"
            echo "  --clean-each       Reformat before EVERY suite, so each one starts from a"
            echo "                     known-clean card. Use for certification sweeps: without"
            echo "                     it a suite inherits whatever the previous one left, and"
            echo "                     debris is indistinguishable from a real defect."
            echo "  --reformat-only    Reformat the card and exit (recovery after a failed run)"
            echo "  --stop-on-failure  Halt at the first failing suite, preserving on-card"
            echo "                     evidence. Default: record it and CONTINUE to the end."
            echo "  --no-preflight     Skip card-identify + sweep-start fsck (audit + reclaim)"
            echo "  --log <file>       Tee output to <file> (pollable during a background run)"
            echo "  --stack-report     MEASUREMENT BUILD: compile every suite with"
            echo "                     -D SD_INCLUDE_STACK_REPORT (enlarged worker stack +"
            echo "                     per-suite watermark line) and collect the watermarks"
            echo "                     into the sweep summary. Release sizing input; see the"
            echo "                     formula at the STACK_SIZE CON in the driver."
            echo ""
            echo "The card is treated as SCRATCH on hardware runs: a clean FAT32 baseline is"
            echo "established before the first suite and the card is reformatted around the"
            echo "destructive suites. This runner is the ONLY place that reformats;"
            echo "single-suite run_test.sh never does."
            echo ""
            echo "The run is END-TO-END by default: suite failures are recorded and the sweep"
            echo "continues; serial-download transients are retried once and reported as INFRA."
            echo ""
            echo "Examples:"
            echo "  $0                              # Full regression, Edge socket, card as scratch"
            echo "  $0 --include-format             # Full regression + format suite"
            echo "  $0 --from volume                # Resume from SD_RT_volume_tests"
            echo "  $0 --compile-only               # Compile check only (never touches the card)"
            echo "  $0 --run-only                   # Run only (after prior compile)"
            echo "  $0 --external                   # Full regression on external SD header"
            echo "  $0 --no-reformat                # Preserve card contents across the run"
            echo "  $0 --reformat-only              # Restore a card left dirty by a failed run"
            echo "  $0 --stop-on-failure            # Forensic run: halt + preserve evidence"
            echo "  $0 --log ../DOCs/sweep.txt      # Full sweep, transcript teed to a file"
            echo "  $0 --stack-report               # Measurement sweep: collect stack watermarks"
            exit 0
            ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# --- Tee all output to a transcript -----------------------------------------
# Done immediately after arg parsing so the banner and every phase land in the
# file. Enables "launch in background, poll the log" instead of chunked runs.
#
# ALWAYS ON as of 2026-08-14. It used to require --log, and the 587/587 run that
# certified 28 suites was launched without it: every per-suite log survived, but the
# aggregate -- including the Tree: provenance line added that same morning, whose entire
# purpose is tying a result to a commit -- went to the console and was lost. A record
# that depends on the operator remembering a flag is not a record. --log still overrides
# the default path.
if [[ -z "$TEE_LOG" ]]; then
    TEE_LOG="${SCRIPT_DIR}/logs/sweep_$(date +%y%m%d-%H%M%S).txt"
fi
mkdir -p "$(dirname "$TEE_LOG")"
exec > >(tee -a "$TEE_LOG") 2>&1

# Build per-test --external flag pass-through (for run_test.sh) and direct
# pnut-ts preprocessor flag (for compile-only path that calls pnut-ts directly).
EXTERNAL_FLAG=""
PIN_DEFINE_FLAG=""
if [[ "$EXTERNAL_PINS" == "true" ]]; then
    EXTERNAL_FLAG="--external"
    PIN_DEFINE_FLAG="-D SD_PINS_EXTERNAL"
fi

# Measurement-build flag pass-through (--stack-report → run_test.sh) and direct
# pnut-ts define for the compile phases that invoke pnut-ts themselves. Suites
# only — the support vehicles (format/identify/audit/fsck) don't use the test
# framework and stay on the release stack size.
STACK_FLAG=""
STACK_DEFINE_FLAG=""
if [[ "$STACK_REPORT" == "true" ]]; then
    STACK_FLAG="--stack-report"
    STACK_DEFINE_FLAG="-D SD_INCLUDE_STACK_REPORT"
fi

# --- Card-as-scratch (reformat) machinery -------------------------------------
# DESTRUCTIVE. Regression runner only — see the header block. Nothing here is
# reachable from tools/run_test.sh; it is only used as the launcher below.

FORMAT_VEHICLE_BASE="SD_format_card"
FORMAT_VEHICLE="$PROJECT_ROOT/src/UTILS/${FORMAT_VEHICLE_BASE}.spin2"
REFORMAT_TIMEOUT=300

# Preflight / closing vehicles (all live in src/UTILS). Identify and the
# closing audit are read-only; the sweep-start fsck REPAIRS (reclaims lost
# cluster chains) — see _run_fsck.
IDENTIFY_VEHICLE_BASE="SD_card_identify"
IDENTIFY_TIMEOUT=60
AUDIT_VEHICLE_BASE="SD_FAT32_audit"
AUDIT_TIMEOUT=300
FSCK_VEHICLE_BASE="SD_FAT32_fsck"
FSCK_TIMEOUT=300

# Suites that need a freshly-formatted card going IN. fatchain is here for
# FAT-LAYOUT DETERMINISM: its tests build and verify specific cluster-chain
# shapes, and starting from a just-formatted FAT is what makes a failure
# reproduce identically run-to-run. (Not a capacity gate — the suite fits on
# any supported card.)
REFORMAT_BEFORE=(
    "SD_RT_fatchain_tests"
)

# Suites that can leave the card unusable/altered on the way OUT.
#   fatchain — on an unfixed driver its writes damage the FAT/VBR (Bug A)
#   format   — leaves whatever label/geometry the format suite chose
# Applied ONLY when the suite did not end ok (decision 7, 2026-08-09): a green
# run of these suites leaves a healthy card — the closing audit proves it — so
# the redundant format is skipped.
REFORMAT_AFTER=(
    "SD_RT_fatchain_tests"
    "SD_RT_format_tests"
)

REFORMAT_COUNT=0
REFORMAT_TIME=0

_in_list() {   # _in_list <needle> <haystack...>
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Reformat the card to a clean FAT32 baseline. Returns non-zero on failure.
_reformat_card() {
    local why="$1"
    local start end elapsed exit_code log clean ok

    printf "  ${CYAN}[reformat]${NC} %-36s " "$why"
    start=$(date +%s)
    set +e
    "$SCRIPT_DIR/run_test.sh" "$FORMAT_VEHICLE" -t "$REFORMAT_TIMEOUT" $EXTERNAL_FLAG > /dev/null 2>&1
    exit_code=$?
    set -e
    end=$(date +%s)
    elapsed=$((end - start))
    REFORMAT_COUNT=$((REFORMAT_COUNT + 1))
    REFORMAT_TIME=$((REFORMAT_TIME + elapsed))

    # Confirm the card really was formatted — a clean exit is not proof.
    ok=false
    log=$(ls -t "$LOG_DIR/${FORMAT_VEHICLE_BASE}_"*.log 2>/dev/null | head -1)
    if [[ $exit_code -eq 0 && -n "$log" ]]; then
        # pnut-term-ts timestamps can split lines mid-word: strip per-line
        # timestamps, then join so the marker is contiguous again.
        clean=$(sed -E 's/^\[[-0-9T:.]+\] //' "$log" | tr -d '\r\0' | tr -d '\n')
        # The vehicle's own success line is the marker. It lands intact because
        # SD_format_card drains the debug backlog before END_SESSION; without
        # that drain pnut-term-ts stopped logging mid-word and the line was
        # routinely truncated out. "FORMAT FAILED" is decisive regardless.
        if [[ "$clean" != *"FORMAT FAILED"* ]]; then
            if [[ "$clean" == *"FORMAT SUCCESSFUL"* ]]; then
                ok=true
            fi
        fi
    fi

    if [[ "$ok" == true ]]; then
        printf "${GREEN}OK${NC} [%3ds]\n" "$elapsed"
        return 0
    fi

    printf "${RED}FAILED${NC} [%3ds]\n" "$elapsed"
    echo ""
    echo -e "${RED}============================================================${NC}"
    echo -e "${RED}  CARD REFORMAT FAILED — $why${NC}"
    echo -e "${RED}============================================================${NC}"
    echo -e "  run_test.sh exit code: $exit_code"
    if [[ -n "$log" ]]; then
        echo -e "  ${CYAN}Log: $log${NC}"
    else
        echo -e "  ${YELLOW}No format log found in $LOG_DIR${NC}"
    fi
    echo -e "  The card is NOT in a known state. Regression aborted."
    echo ""
    return 1
}

# --- Log normalization ---------------------------------------------------------
# pnut-term-ts writes a per-line timestamp and can split a logical line mid-word,
# so no marker is reliably greppable in the raw log. Strip timestamps/CRs/NULs,
# join everything, then re-split on "Cog" boundaries to rebuild logical lines.
_clean_log() {   # _clean_log <logfile>
    sed -E 's/^\[[-0-9T:.]+\] //' "$1" | tr -d '\r\0' | tr -d '\n' | sed $'s/Cog/\\\nCog/g'
}

_latest_log() {  # _latest_log <basename> -> path of newest matching log, or empty
    ls -t "$LOG_DIR/${1}_"*.log 2>/dev/null | head -1
}

# --- Preflight / closing vehicles ----------------------------------------------
# Identify and the closing audit are read-only; the sweep-start fsck REPAIRS
# (reclaims lost chains). All are run through the unmodified run_test.sh.

# Identify the card in the socket. Echoes the vehicle's own L1/L2/L3 summary into
# the transcript so the run is self-labeling (capacity, geometry, SN, warnings).
# Returns non-zero if the card cannot be identified — no card, no run.
_identify_card() {
    local exit_code log line
    printf "  ${CYAN}[card]${NC}      %-36s " "identify"
    set +e
    "$SCRIPT_DIR/run_test.sh" "$PROJECT_ROOT/src/UTILS/${IDENTIFY_VEHICLE_BASE}.spin2" \
        -t "$IDENTIFY_TIMEOUT" $EXTERNAL_FLAG > /dev/null 2>&1
    exit_code=$?
    set -e

    log=$(_latest_log "$IDENTIFY_VEHICLE_BASE")
    if [[ $exit_code -ne 0 || -z "$log" ]]; then
        printf "${RED}FAILED${NC}\n"
        echo ""
        echo -e "${RED}============================================================${NC}"
        echo -e "${RED}  CARD IDENTIFY FAILED — is a card seated in the socket?${NC}"
        echo -e "${RED}============================================================${NC}"
        echo -e "  run_test.sh exit code: $exit_code"
        [[ -n "$log" ]] && echo -e "  ${CYAN}Log: $log${NC}"
        echo ""
        return 1
    fi

    printf "${GREEN}OK${NC}\n"
    # L1/L2/L3 are the vehicle's own identification summary lines — echo them
    # into the transcript verbatim so the cert report needs no hand-transcription.
    # Trailing [SYSTEM]/session lines carry no "Cog" prefix, so _clean_log cannot
    # split them off the last L-line — cut them here.
    _clean_log "$log" | grep -aoE "L[123]: .*" | sed -E 's/(\[SYSTEM\]|=== Headless).*$//' \
        | head -3 | sed 's/^/              /'
    return 0
}

# Run the read-only FAT32 audit. Sets AUDIT_PASS / AUDIT_FAIL / AUDIT_LOG.
# Returns non-zero if the audit reported failures or did not complete.
_run_audit() {   # _run_audit <label>
    local why="$1"
    local exit_code clean summary start end elapsed
    AUDIT_PASS=0
    AUDIT_FAIL=0
    AUDIT_LOG=""

    printf "  ${CYAN}[audit]${NC}     %-36s " "$why"
    start=$(date +%s)
    set +e
    "$SCRIPT_DIR/run_test.sh" "$PROJECT_ROOT/src/UTILS/${AUDIT_VEHICLE_BASE}.spin2" \
        -t "$AUDIT_TIMEOUT" $EXTERNAL_FLAG > /dev/null 2>&1
    exit_code=$?
    set -e
    end=$(date +%s)
    elapsed=$((end - start))

    AUDIT_LOG=$(_latest_log "$AUDIT_VEHICLE_BASE")
    if [[ $exit_code -ne 0 || -z "$AUDIT_LOG" ]]; then
        printf "${RED}DID NOT RUN${NC} [%3ds]\n" "$elapsed"
        return 1
    fi

    clean=$(_clean_log "$AUDIT_LOG")
    # The v1.6.0 audit runs the shared four-pass engine, which emits
    # "FSCK COMPLETE"; the pre-consolidation shallow audit emitted
    # "AUDIT COMPLETE". Accept either so archived logs still parse.
    if ! echo "$clean" | grep -qaE "AUDIT COMPLETE|FSCK COMPLETE"; then
        printf "${RED}INCOMPLETE${NC} [%3ds]\n" "$elapsed"
        return 1
    fi

    # Two output vintages. Deep engine (v1.6.0):
    #   Errors: 0  Repairs: 0
    #   Structural checks: 23 pass, 0 fail
    # Shallow audit (pre-v1.6.0):
    #   Tests: 39  Pass: 39
    #   Fail: 0
    AUDIT_PASS=""; AUDIT_FAIL=""; AUDIT_ERRORS=""; AUDIT_REPAIRS=""
    summary=$(echo "$clean" | grep -aE "Structural checks: *[0-9]+ pass" | tail -1)
    if [[ -n "$summary" ]]; then
        AUDIT_PASS=$(echo "$summary" | sed -E 's/.*checks: *([0-9]+) pass.*/\1/')
        AUDIT_FAIL=$(echo "$summary" | sed -E 's/.*, *([0-9]+) fail.*/\1/')
        summary=$(echo "$clean" | grep -aE "Errors: *[0-9]+" | tail -1)
        [[ -n "$summary" ]] && AUDIT_ERRORS=$(echo "$summary" | sed -E 's/.*Errors: *([0-9]+).*/\1/')
        # Lost/orphaned clusters (Bug-A damage) are counted as REPAIRS, not
        # errors -- a read-only audit reports "Repairs needed: N". Gating only
        # on Errors would pass a damaged card, so the repair count gates too.
        summary=$(echo "$clean" | grep -aE "Repairs( needed)?: *[0-9]+" | tail -1)
        [[ -n "$summary" ]] && AUDIT_REPAIRS=$(echo "$summary" | sed -E 's/.*Repairs( needed)?: *([0-9]+).*/\2/')
    else
        summary=$(echo "$clean" | grep -a "Tests:.*Pass:" | tail -1)
        [[ -n "$summary" ]] && AUDIT_PASS=$(echo "$summary" | sed -E 's/.*Pass: *([0-9]+).*/\1/')
        summary=$(echo "$clean" | grep -a "Fail:" | tail -1)
        [[ -n "$summary" ]] && AUDIT_FAIL=$(echo "$summary" | sed -E 's/.*Fail: *([0-9]+).*/\1/')
    fi

    # An unparseable summary is NOT a clean card. Never default these to 0 --
    # a silent zero would let a damaged card pass the closing-audit gate.
    if ! [[ "$AUDIT_PASS" =~ ^[0-9]+$ && "$AUDIT_FAIL" =~ ^[0-9]+$ ]]; then
        printf "${RED}UNPARSEABLE${NC} [%3ds]\n" "$elapsed"
        AUDIT_PASS=0; AUDIT_FAIL=0
        return 1
    fi
    [[ "$AUDIT_ERRORS" =~ ^[0-9]+$ ]] || AUDIT_ERRORS=0
    [[ "$AUDIT_REPAIRS" =~ ^[0-9]+$ ]] || AUDIT_REPAIRS=0

    if [[ $AUDIT_FAIL -gt 0 || $AUDIT_ERRORS -gt 0 || $AUDIT_REPAIRS -gt 0 ]]; then
        printf "${RED}%d pass, %d FAIL, %d errors, %d repairs${NC} [%3ds]\n" \
            "$AUDIT_PASS" "$AUDIT_FAIL" "$AUDIT_ERRORS" "$AUDIT_REPAIRS" "$elapsed"
        return 1
    fi
    printf "${GREEN}OK${NC} (%d/%d) [%3ds]\n" "$AUDIT_PASS" "$AUDIT_PASS" "$elapsed"
    return 0
}

# Run the FAT32 fsck (check AND repair) — the sweep-start reclamation step.
# Same four-pass engine as the audit, but repairs are APPLIED: lost cluster
# chains left by a prior run are reclaimed here, once, before suite 1 — never
# mid-sweep (decision 8, 2026-08-09). The Repairs count is the per-run leak
# metric: error_injection T13 leaks ~2 clusters by design; markedly more than
# that is a signal worth reading the fsck log over.
# Sets FSCK_ERRORS / FSCK_REPAIRS / FSCK_LOG. Returns non-zero if fsck did not
# complete, was unparseable, or left errors it could not repair.
_run_fsck() {   # _run_fsck <label>
    local why="$1"
    local exit_code clean summary start end elapsed
    FSCK_ERRORS=""
    FSCK_REPAIRS=""
    FSCK_LOG=""

    printf "  ${CYAN}[fsck]${NC}      %-36s " "$why"
    start=$(date +%s)
    set +e
    "$SCRIPT_DIR/run_test.sh" "$PROJECT_ROOT/src/UTILS/${FSCK_VEHICLE_BASE}.spin2" \
        -t "$FSCK_TIMEOUT" $EXTERNAL_FLAG > /dev/null 2>&1
    exit_code=$?
    set -e
    end=$(date +%s)
    elapsed=$((end - start))

    FSCK_LOG=$(_latest_log "$FSCK_VEHICLE_BASE")
    if [[ $exit_code -ne 0 || -z "$FSCK_LOG" ]]; then
        printf "${RED}DID NOT RUN${NC} [%3ds]\n" "$elapsed"
        return 1
    fi

    clean=$(_clean_log "$FSCK_LOG")
    if ! echo "$clean" | grep -qa "FSCK COMPLETE"; then
        printf "${RED}INCOMPLETE${NC} [%3ds]\n" "$elapsed"
        return 1
    fi

    # Repair mode summarizes as "Errors: N  Repairs: N". Never default to 0 —
    # an unparseable summary is not a clean card.
    summary=$(echo "$clean" | grep -aE "Errors: *[0-9]+" | tail -1)
    if [[ -n "$summary" ]]; then
        FSCK_ERRORS=$(echo "$summary" | sed -E 's/.*Errors: *([0-9]+).*/\1/')
        FSCK_REPAIRS=$(echo "$summary" | sed -E 's/.*Repairs: *([0-9]+).*/\1/')
    fi
    if ! [[ "$FSCK_ERRORS" =~ ^[0-9]+$ && "$FSCK_REPAIRS" =~ ^[0-9]+$ ]]; then
        printf "${RED}UNPARSEABLE${NC} [%3ds]\n" "$elapsed"
        return 1
    fi

    if [[ $FSCK_ERRORS -gt 0 ]]; then
        printf "${RED}%d errors, %d repairs${NC} [%3ds]\n" "$FSCK_ERRORS" "$FSCK_REPAIRS" "$elapsed"
        echo -e "              ${CYAN}fsck log: ${FSCK_LOG}${NC}"
        return 1
    fi
    if [[ $FSCK_REPAIRS -gt 0 ]]; then
        printf "${YELLOW}clean after %d repairs (reclaimed lost chains)${NC} [%3ds]\n" "$FSCK_REPAIRS" "$elapsed"
    else
        printf "${GREEN}clean, nothing to reclaim${NC} [%3ds]\n" "$elapsed"
    fi
    return 0
}

if [[ "$REFORMAT_ONLY" == true ]]; then
    if [[ "$COMPILE_ONLY" == true ]]; then
        echo -e "${RED}Error: --reformat-only and --compile-only are mutually exclusive${NC}"
        exit 1
    fi
    mkdir -p "$LOG_DIR"
    echo ""
    echo -e "${BOLD}  Reformatting SD card (erases all data)${NC}"
    echo ""
    if _reformat_card "on request"; then
        echo ""
        echo -e "  ${GREEN}Card reformatted — clean FAT32 baseline restored.${NC}"
        echo ""
        exit 0
    fi
    exit 1
fi

# --- Define test suites in dependency order ---
# Format: "filename:timeout_secs"
# Ordered foundational-first so failures in lower layers are caught early.

# Layer 1: Mount/Init
SUITES=(
    "SD_RT_mount_tests.spin2:120"
)

# Layer 2: Raw I/O (below filesystem)
SUITES+=(
    "SD_RT_raw_sector_tests.spin2:120"
    "SD_RT_multiblock_tests.spin2:90"
)

# Layer 3: Hardware features
SUITES+=(
    "SD_RT_register_tests.spin2:120"
    "SD_RT_speed_tests.spin2:120"
    "SD_RT_crc_diag_tests.spin2:120"
)

# Layer 4: Error handling and recovery
SUITES+=(
    "SD_RT_error_handling_tests.spin2:120"
    # Test 36 (dir-extend true-code witness) creates+deletes ~1 cluster of
    # directory entries (~250 file ops at 8 sec/clus) -- budget raised from 120
    "SD_RT_error_injection_tests.spin2:180"
    "SD_RT_crc_validation_tests.spin2:120"
    "SD_RT_recovery_tests.spin2:120"
)

# Layer 5: Basic file I/O
SUITES+=(
    "SD_RT_file_ops_tests.spin2:120"
    "SD_RT_read_write_tests.spin2:90"
    "SD_RT_write_integrity_tests.spin2:180"
    "SD_RT_fatchain_tests.spin2:120"
    "SD_RT_multihandle_tests.spin2:120"
)

# Layer 6: File operations
SUITES+=(
    "SD_RT_seek_tests.spin2:120"
    "SD_RT_volume_tests.spin2:120"
    "SD_RT_subdir_ops_tests.spin2:120"
)

# Layer 7: Directory operations
SUITES+=(
    "SD_RT_directory_tests.spin2:120"
    "SD_RT_dirhandle_tests.spin2:120"
)

# Layer 8: Inter-cog
SUITES+=(
    "SD_RT_fifo_tests.spin2:120"
    "SD_RT_multicog_tests.spin2:120"
    "SD_RT_cogcwd_tests.spin2:120"
    "SD_RT_timestamp_tests.spin2:120"
    "SD_RT_stress_tests.spin2:120"
    "SD_RT_async_tests.spin2:120"
    "SD_RT_defrag_tests.spin2:120"
)

# Optional: Format (destructive!)
if [[ "$INCLUDE_FORMAT" == true ]]; then
    SUITES+=("SD_RT_format_tests.spin2:300")
fi

TOTAL_SUITES=${#SUITES[@]}

# --- Resolve --from to a starting index ---
START_INDEX=0

if [[ -n "$FROM_SUITE" ]]; then
    FOUND_FROM=false
    for i in "${!SUITES[@]}"; do
        FILE="${SUITES[$i]%%:*}"
        if [[ "$FILE" == *"$FROM_SUITE"* ]]; then
            START_INDEX=$i
            FOUND_FROM=true
            break
        fi
    done

    if [[ "$FOUND_FROM" == false ]]; then
        echo -e "${RED}Error: No suite matching '$FROM_SUITE'${NC}"
        echo ""
        echo "Available suites:"
        for entry in "${SUITES[@]}"; do
            echo "  ${entry%%:*}"
        done
        exit 1
    fi

    SKIP_COUNT=$START_INDEX
    RUN_COUNT=$((TOTAL_SUITES - START_INDEX))
    echo -e "${YELLOW}Resuming from: ${SUITES[$START_INDEX]%%:*}${NC}"
    echo -e "${YELLOW}Skipping $SKIP_COUNT suites, running $RUN_COUNT${NC}"
    echo ""
fi

# --- Banner ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  SD FAT32 Driver — Regression Suite${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
if [[ -n "$FROM_SUITE" ]]; then
    echo "  Total suites: ${TOTAL_SUITES} (running ${RUN_COUNT} from #$((START_INDEX + 1)))"
else
    echo "  Test suites: ${TOTAL_SUITES}"
fi

# TREE PROVENANCE -- stamp what was actually built, not just how.
#
# Added 2026-08-14. Pinning which tree produced the 2026-08-06..08-11 sweeps took
# compiling sixteen commits and matching binary byte sizes, because the transcripts
# recorded the suite count, the card and the pin config but never the commit. The
# answer mattered: every sweep that showed the write-path failure turned out to have
# run on a tree matching NO commit -- uncommitted bench edits -- which is the single
# most important fact about that defect's exposure. Do not remove this.
#
# --dirty is the load-bearing half. A clean describe is reproducible; a dirty one says
# "this result cannot be tied to any commit" and must be read that way.
GIT_STAMP=$(git -C "$PROJECT_ROOT" describe --tags --always --dirty 2>/dev/null || echo "unknown")
GIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
echo "  Tree:        ${GIT_STAMP}  (${GIT_BRANCH} @ ${GIT_SHA})"
if [[ "$GIT_STAMP" == *-dirty ]]; then
    echo "               ^^ UNCOMMITTED CHANGES -- this result is not reproducible from"
    echo "                  any commit. Commit before a certifying run."
fi
echo "  Format test: $([[ "$INCLUDE_FORMAT" == true ]] && echo "INCLUDED (destructive!)" || echo "excluded")"
echo "  SD pins:     $([[ "$EXTERNAL_PINS" == true ]] && echo "EXTERNAL header (base pin 16)" || echo "P2 Edge onboard slot")"
if [[ "$COMPILE_ONLY" == true ]]; then
    echo "  Card:        untouched (compile only)"
elif [[ "$REFORMAT" == true ]]; then
    echo "  Card:        SCRATCH — baseline reformat + reformat around destructive suites"
else
    echo "  Card:        preserved (--no-reformat) — suites must self-establish"
fi
if [[ "$COMPILE_ONLY" != true ]]; then
    echo "  Preflight:   $([[ "$PREFLIGHT" == true ]] && echo "card identify + sweep-start fsck (reclaim) / closing audit" || echo "skipped (--no-preflight)")"
    echo "  On failure:  $([[ "$STOP_ON_FAILURE" == true ]] && echo "STOP (preserve on-card evidence)" || echo "record and CONTINUE to the end")"
fi
if [[ -n "$TEE_LOG" ]]; then
    echo "  Transcript:  $TEE_LOG"
fi
if [[ "$COMPILE_ONLY" == true ]]; then
    echo "  Mode: COMPILE ONLY"
elif [[ "$RUN_ONLY" == true ]]; then
    echo "  Mode: RUN ONLY (using existing .bin files)"
else
    echo "  Mode: COMPILE + RUN"
fi
if [[ "$STACK_REPORT" == true ]]; then
    echo "  Build:       STACK MEASUREMENT (-D SD_INCLUDE_STACK_REPORT, enlarged worker stack)"
fi
echo ""

# --- Compute include paths once ---
_relpath() {
    python3 -c "import os; print(os.path.relpath('$1', '$2'))"
}
SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$REGTEST_DIR")"
UTILS_PATH="$(_relpath "$PROJECT_ROOT/src/UTILS" "$REGTEST_DIR")"
DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$REGTEST_DIR")"
CACHE_DIR="$PROJECT_ROOT/.pnut-cache"

# --- Phase 1: Compile tests (from START_INDEX onward) ---
DRIVER_SRC="$PROJECT_ROOT/src/micro_sd_fat32_fs.spin2"

# Determine if a .bin needs recompiling: missing, or older than source or driver
_needs_compile() {
    local spin_file="$1"
    local bin_file="${spin_file%.spin2}.bin"
    [[ ! -f "$bin_file" ]] && return 0
    [[ "$spin_file" -nt "$bin_file" ]] && return 0
    [[ "$DRIVER_SRC" -nt "$bin_file" ]] && return 0
    return 1
}

if [[ "$RUN_ONLY" == true ]]; then
    echo -e "${CYAN}--- Phase 1: Compile (--run-only, stale bins only) ---${NC}"
    echo ""

    COMPILE_PASS=0
    COMPILE_FAIL=0
    COMPILE_SKIP=0
    COMPILE_FAILED_FILES=()

    cd "$REGTEST_DIR"

    # Cache toggle: set USE_CACHE=0 to disable. Default: enabled.
    if [[ "$USE_CACHE" == "0" ]]; then
        CACHE_FLAGS=""
    else
        CACHE_FLAGS="--cache --cache-dir $CACHE_DIR"
    fi

    for i in "${!SUITES[@]}"; do
        if [[ $i -lt $START_INDEX ]]; then
            continue
        fi
        entry="${SUITES[$i]}"
        FILE="${entry%%:*}"
        BASENAME="${FILE%.spin2}"

        if _needs_compile "$FILE"; then
            if pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG $STACK_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" >/dev/null 2>&1; then
                SIZE=$(wc -c < "${BASENAME}.bin" | tr -d ' ')
                echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes) [recompiled]"
                COMPILE_PASS=$((COMPILE_PASS + 1))
            else
                echo -e "  ${RED}FAIL${NC}: $FILE"
                pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG $STACK_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" 2>&1 | grep -i error || true
                COMPILE_FAIL=$((COMPILE_FAIL + 1))
                COMPILE_FAILED_FILES+=("$FILE")
            fi
        else
            COMPILE_SKIP=$((COMPILE_SKIP + 1))
        fi
    done

    cd "$SCRIPT_DIR"

    echo ""
    if [[ $COMPILE_PASS -gt 0 || $COMPILE_FAIL -gt 0 ]]; then
        echo -e "  Compiled: ${GREEN}${COMPILE_PASS} pass${NC}, ${RED}${COMPILE_FAIL} fail${NC}, ${COMPILE_SKIP} up-to-date"
    else
        echo -e "  All ${COMPILE_SKIP} .bin files up-to-date"
    fi
    echo ""

    if [[ $COMPILE_FAIL -gt 0 ]]; then
        echo -e "${RED}Compile failures:${NC}"
        for f in "${COMPILE_FAILED_FILES[@]}"; do
            echo "  - $f"
        done
        echo ""
        echo -e "${RED}Fix compile errors before running tests.${NC}"
        exit 1
    fi
else
    echo -e "${CYAN}--- Phase 1: Compiling test suites ---${NC}"
    echo ""

    COMPILE_PASS=0
    COMPILE_FAIL=0
    COMPILE_FAILED_FILES=()

    cd "$REGTEST_DIR"

    # Cache toggle: set USE_CACHE=0 to disable pnut-ts object cache. Default: enabled.
    # When enabled on a full run, clear cache once at start (skip on --from resume).
    if [[ "$USE_CACHE" == "0" ]]; then
        CACHE_FLAGS=""
        echo "  Cache DISABLED (override: USE_CACHE=0)"
    else
        CACHE_FLAGS="--cache --cache-dir $CACHE_DIR"
        if [[ -z "$FROM_SUITE" && -d "$CACHE_DIR" ]]; then
            rm -rf "$CACHE_DIR"
            echo "  Cache cleared (rm -rf $CACHE_DIR)"
        fi
    fi

    for i in "${!SUITES[@]}"; do
        if [[ $i -lt $START_INDEX ]]; then
            continue
        fi

        entry="${SUITES[$i]}"
        FILE="${entry%%:*}"
        if [[ ! -f "$FILE" ]]; then
            echo -e "  ${RED}MISSING${NC}: $FILE"
            COMPILE_FAIL=$((COMPILE_FAIL + 1))
            COMPILE_FAILED_FILES+=("$FILE")
            continue
        fi

        BASENAME="${FILE%.spin2}"
        if pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG $STACK_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" >/dev/null 2>&1; then
            SIZE=$(wc -c < "${BASENAME}.bin" | tr -d ' ')
            echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes)"
            COMPILE_PASS=$((COMPILE_PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC}: $FILE"
            pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG $STACK_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" 2>&1 | grep -i error || true
            COMPILE_FAIL=$((COMPILE_FAIL + 1))
            COMPILE_FAILED_FILES+=("$FILE")
        fi
    done

    cd "$SCRIPT_DIR"

    echo ""
    echo -e "  Compile results: ${GREEN}${COMPILE_PASS} pass${NC}, ${RED}${COMPILE_FAIL} fail${NC}"
    echo ""

    if [[ $COMPILE_FAIL -gt 0 ]]; then
        echo -e "${RED}Compile failures:${NC}"
        for f in "${COMPILE_FAILED_FILES[@]}"; do
            echo "  - $f"
        done
        echo ""
        echo -e "${RED}Fix compile errors before running tests.${NC}"
        exit 1
    fi
fi

# --- Phase 1b: Compile the support vehicles ---
# Built here so a broken vehicle fails the run up front, not halfway through on
# hardware. run_test.sh recompiles each at launch time anyway.
#   reformat vehicle  — SD_format_card   (needed unless --no-reformat)
#   preflight vehicles— SD_card_identify + SD_FAT32_audit + SD_FAT32_fsck
#                       (unless --no-preflight)
VEHICLES=()
[[ "$REFORMAT"  == true ]] && VEHICLES+=("${FORMAT_VEHICLE_BASE}:reformat vehicle")
if [[ "$PREFLIGHT" == true ]]; then
    VEHICLES+=("${IDENTIFY_VEHICLE_BASE}:preflight: card identify")
    VEHICLES+=("${AUDIT_VEHICLE_BASE}:preflight/closing: FAT32 audit")
    VEHICLES+=("${FSCK_VEHICLE_BASE}:preflight: sweep-start fsck")
fi

if [[ ${#VEHICLES[@]} -gt 0 ]]; then
    UTILS_DIR="$PROJECT_ROOT/src/UTILS"
    V_SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$UTILS_DIR")"
    V_DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$UTILS_DIR")"
    V_REGTEST_PATH="$(_relpath "$PROJECT_ROOT/src/regression-tests" "$UTILS_DIR")"
    cd "$UTILS_DIR"
    for vehicle in "${VEHICLES[@]}"; do
        V_BASE="${vehicle%%:*}"
        V_ROLE="${vehicle#*:}"
        if [[ "$RUN_ONLY" == true ]] && ! _needs_compile "${V_BASE}.spin2"; then
            echo -e "  ${GREEN}OK${NC}: ${V_BASE}.spin2 (${V_ROLE}, up-to-date)"
        elif pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$V_SRC_PATH" -I . -I "$V_DEMO_PATH" -I "$V_REGTEST_PATH" "${V_BASE}.spin2" >/dev/null 2>&1; then
            V_SIZE=$(wc -c < "${V_BASE}.bin" | tr -d ' ')
            echo -e "  ${GREEN}OK${NC}: ${V_BASE}.spin2 (${V_SIZE} bytes) [${V_ROLE}]"
        else
            echo -e "  ${RED}FAIL${NC}: ${V_BASE}.spin2 [${V_ROLE}]"
            pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$V_SRC_PATH" -I . -I "$V_DEMO_PATH" -I "$V_REGTEST_PATH" "${V_BASE}.spin2" 2>&1 | grep -i error || true
            cd "$SCRIPT_DIR"
            echo ""
            if [[ "$V_BASE" == "$FORMAT_VEHICLE_BASE" ]]; then
                echo -e "${RED}The reformat vehicle does not compile — the runner cannot establish${NC}"
                echo -e "${RED}a clean card. Fix it, or rerun with --no-reformat.${NC}"
            else
                echo -e "${RED}A preflight vehicle does not compile. Fix it, or rerun with${NC}"
                echo -e "${RED}--no-preflight to skip card identify + fsck/audit.${NC}"
            fi
            exit 1
        fi
    done
    cd "$SCRIPT_DIR"
    echo ""
fi

# --- Phase 1c: Consumer-compatibility compile sweep -----------------------------
#
# The regression suites and the three support vehicles above are OUR code. They are
# not what a user builds. The shipped consumers are src/EXAMPLES/, src/DEMO/ and the
# rest of src/UTILS/ -- and until v1.7.0 NOTHING compiled them, so a driver change
# could rename a public method, ship a green suite sweep, and leave the demo shell
# broken in the release bundle. That is the most invisible kind of break: no test
# names it, and the first person to find it is the user.
#
# Each file is compiled from ITS OWN directory with EXACTLY the include flags its
# README gives the user -- not the harness's everything-on-the-path invocation.
# v1.6.1 found three utilities that built green in the harness for years while
# failing the command in the docs, and this sweep is where that class of defect is
# caught. Do not "simplify" these to a shared -I list.
CONSUMER_PASS=0
CONSUMER_FAIL=0
CONSUMER_FAILED_FILES=()

_sweep_consumer_dir() {
    local dir="$1"; shift
    local includes="$1"; shift      # documented -I flags, verbatim
    local dbg="$1"; shift           # "-d" or ""
    local spin_file base

    cd "$PROJECT_ROOT/$dir" || return
    for spin_file in *.spin2; do
        [[ -f "$spin_file" ]] || continue
        base="${spin_file%.spin2}"
        if [[ "$RUN_ONLY" == true ]] && ! _needs_compile "$spin_file"; then
            continue
        fi
        if pnut-ts $dbg $CACHE_FLAGS $includes "$spin_file" >/dev/null 2>&1; then
            CONSUMER_PASS=$((CONSUMER_PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC}: $dir/$spin_file"
            pnut-ts $dbg $CACHE_FLAGS $includes "$spin_file" 2>&1 | grep -i error || true
            CONSUMER_FAIL=$((CONSUMER_FAIL + 1))
            CONSUMER_FAILED_FILES+=("$dir/$spin_file")
        fi
    done
    cd "$SCRIPT_DIR"
}

echo -e "${CYAN}--- Phase 1c: Consumer compile sweep (EXAMPLES, DEMO, UTILS) ---${NC}"
echo ""
_sweep_consumer_dir "src/EXAMPLES" "-I .."              ""
_sweep_consumer_dir "src/DEMO"     "-I .. -I ../UTILS"  ""
_sweep_consumer_dir "src/UTILS"    "-I .."              "-d"

if [[ $CONSUMER_FAIL -gt 0 ]]; then
    echo ""
    echo -e "${RED}Consumer compile failures:${NC}"
    for f in "${CONSUMER_FAILED_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
    echo -e "${RED}A shipped consumer no longer builds with the command its README${NC}"
    echo -e "${RED}gives the user. Fix the source or the documented command before${NC}"
    echo -e "${RED}running on hardware.${NC}"
    exit 1
fi
echo -e "  ${GREEN}${CONSUMER_PASS} consumer program(s) compiled with their documented commands.${NC}"
echo ""

if [[ "$COMPILE_ONLY" == true ]]; then
    if [[ $COMPILE_PASS -gt 0 ]]; then
        echo -e "${GREEN}All ${COMPILE_PASS} test suites compiled successfully.${NC}"
    else
        echo -e "${GREEN}All test suites up-to-date.${NC}"
    fi
    exit 0
fi

# --- Phase 2: Run tests on hardware (from START_INDEX onward) ---
echo -e "${CYAN}--- Phase 2: Running tests on hardware ---${NC}"
echo ""

# Arrays to store per-suite results for summary table
declare -a RESULT_NAMES=()
declare -a RESULT_PASS=()
declare -a RESULT_FAIL=()
declare -a RESULT_TIME=()
declare -a RESULT_STATE=()   # ok | fail | infra
declare -a RESULT_REASON=()  # "" | no-summary | count-mismatch
declare -a RESULT_STACK=()   # --stack-report only: "<used>/<size>" | "n/a" | "-"
STACK_MAX=0                  # highest watermark seen across the sweep
STACK_MAX_SUITE=""
STACK_MAX_SIZE=0
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TIME=0
SUITES_RUN=0
FAILED_SUITE=""
declare -a FAILED_SUITES=()
declare -a INFRA_SUITES=()
REFORMAT_FAILED=false
CARD_LEFT_DIRTY=false
CARD_IS_FRESH=false        # true = nothing has touched the card since the last format
PREFLIGHT_FSCK_FAIL=false
CLOSING_AUDIT_FAIL=false

# --- Preflight: identify the card, fsck its INCOMING state --------------------
# Runs BEFORE the baseline reformat, while the card still holds whatever the last
# run left. The fsck REPAIRS: lost cluster chains leaked by the previous run are
# reclaimed here, once, at sweep start (decision 8, 2026-08-09 — never
# mid-sweep), and the reported Repairs count is the per-run leak metric.
# Identify is fatal (no card, no run); a dirty or failed fsck is informational —
# the baseline reformat below establishes a known state regardless.
if [[ "$PREFLIGHT" == true ]]; then
    if ! _identify_card; then
        exit 1
    fi
    if [[ "$REFORMAT" == true ]]; then
        if ! _run_fsck "sweep-start (audit + reclaim)"; then
            PREFLIGHT_FSCK_FAIL=true
            echo -e "              ${YELLOW}sweep-start fsck failed or could not fully repair —${NC}"
            echo -e "              ${YELLOW}informational; the baseline reformat below establishes a known state.${NC}"
        fi
    else
        # --no-reformat preserves card contents. Fsck repairs are WRITES, so
        # the incoming check stays read-only on this path.
        if ! _run_audit "incoming (read-only)"; then
            PREFLIGHT_FSCK_FAIL=true
            echo -e "              ${YELLOW}incoming card not clean — informational only (--no-reformat:${NC}"
            echo -e "              ${YELLOW}no baseline reformat will run; suites must self-establish).${NC}"
        fi
    fi
    echo ""
fi

# Establish a known-clean FAT32 baseline before the first suite. Also applies
# to a --from resume: suites self-establish their own fixtures, so a clean card
# is the correct starting state. Use --no-reformat to preserve card contents.
if [[ "$REFORMAT" == true ]]; then
    if ! _reformat_card "baseline (clean FAT32)"; then
        exit 1
    fi
    CARD_IS_FRESH=true
    echo ""
fi

for i in "${!SUITES[@]}"; do
    if [[ $i -lt $START_INDEX ]]; then
        continue
    fi

    entry="${SUITES[$i]}"
    FILE="${entry%%:*}"
    TIMEOUT="${entry##*:}"
    BASENAME="${FILE%.spin2}"
    SUITES_RUN=$((SUITES_RUN + 1))
    SUITE_NUM=$((i + 1))

    # Suites that require a guaranteed-clean card going in. Skipped when the
    # card was just formatted and nothing has run since (avoids a double format
    # at the head of a --from resume).
    if [[ "$REFORMAT" == true && "$CARD_IS_FRESH" == false ]] && \
       { [[ "$CLEAN_EACH" == true ]] || _in_list "$BASENAME" "${REFORMAT_BEFORE[@]}"; }; then
        if ! _reformat_card "before $BASENAME"; then
            REFORMAT_FAILED=true
            break
        fi
    fi

    CARD_IS_FRESH=false
    START_TIME=$(date +%s)

    # Run the test via run_test.sh.
    # run_test.sh exit 2 == download/serial failure: the binary never reached the
    # P2, so the suite did not execute. That is an INFRASTRUCTURE fault (the known
    # USB checksum transient on this bench), not a test result — retry it once
    # before believing it. Exit 3 (timeout) is NOT retried: a hang can be a real
    # driver defect and must not be papered over.
    RETRIED=false
    set +e
    ./run_test.sh "../src/regression-tests/$FILE" -t "$TIMEOUT" $EXTERNAL_FLAG $STACK_FLAG > /dev/null 2>&1
    RUN_EXIT=$?
    if [[ $RUN_EXIT -eq 2 ]]; then
        RETRIED=true
        ./run_test.sh "../src/regression-tests/$FILE" -t "$TIMEOUT" $EXTERNAL_FLAG $STACK_FLAG > /dev/null 2>&1
        RUN_EXIT=$?
    fi
    set -e

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    # Parse log for pass/fail counts
    SUITE_PASS=0
    SUITE_FAIL=0
    SUMMARY_FOUND=false
    BAD_COUNTS=false

    LATEST_LOG=$(ls -t "$LOG_DIR/${BASENAME}_"*.log 2>/dev/null | head -1)

    if [[ -n "$LATEST_LOG" ]]; then
        # pnut-term-ts timestamps can split summary lines mid-word.
        # Strip timestamps, CRs, and NULs, join everything, then re-split on "Cog"
        # boundaries to reconstruct logical lines.
        CLEAN_LOG=$(sed -E 's/^\[[-0-9T:.]+\] //' "$LATEST_LOG" | tr -d '\r\0' | tr -d '\n' | sed $'s/Cog/\\\nCog/g')

        # Try ALL COGS line first (multi-cog tests), then regular summary
        SUMMARY_LINE=$(echo "$CLEAN_LOG" | grep -a "ALL COGS.*Tests - Pass:" 2>/dev/null | tail -1)
        if [[ -z "$SUMMARY_LINE" ]]; then
            SUMMARY_LINE=$(echo "$CLEAN_LOG" | grep -a "Tests - Pass:" 2>/dev/null | tail -1)
        fi

        if [[ -n "$SUMMARY_LINE" ]]; then
            SUITE_PASS=$(echo "$SUMMARY_LINE" | sed -E 's/.*Pass: *([0-9]+).*/\1/')
            SUITE_FAIL=$(echo "$SUMMARY_LINE" | sed -E 's/.*Fail: *([0-9]+).*/\1/')
            SUMMARY_FOUND=true
        fi

        # The framework prints "BAD TEST COUNTS" when its own bookkeeping shows
        # tests that were counted but never scored (or scored extra) — a suite
        # whose totals line balances can still be hiding vanished tests.
        if echo "$CLEAN_LOG" | grep -qa "BAD TEST COUNTS"; then
            BAD_COUNTS=true
        fi
    fi

    # Measurement builds: capture the per-suite worker-stack watermark line
    # (emitted by isp_rt_utilities beside the totals). Absence is NOT a failure
    # here — a suite that died before its totals is already scored by the
    # no-summary rule; "-" just marks the missing datum.
    SUITE_STACK="-"
    if [[ "$STACK_REPORT" == true && -n "$LATEST_LOG" ]]; then
        # Single contract point for BOTH line forms the framework emits (numeric and
        # n/a) -- see reportStackWatermark in isp_rt_utilities.spin2.
        WM_LINE=$(echo "$CLEAN_LOG" | grep -aE "STACK WATERMARK: (n/a|[0-9]+) of [0-9]+" | tail -1)
        if [[ "$WM_LINE" =~ STACK\ WATERMARK:\ (n/a|[0-9]+)\ of\ ([0-9]+) ]]; then
            WM_USED="${BASH_REMATCH[1]}"
            WM_SIZE="${BASH_REMATCH[2]}"
            SUITE_STACK="${WM_USED}/${WM_SIZE}"
            if [[ "$WM_USED" != "n/a" ]] && (( WM_USED > STACK_MAX )); then
                STACK_MAX=$WM_USED
                STACK_MAX_SUITE="$BASENAME"
                STACK_MAX_SIZE=$WM_SIZE
            fi
        fi
    fi
    RESULT_STACK+=("$SUITE_STACK")

    # Classify the outcome:
    #   infra — the suite never executed (download/serial died twice)
    #   fail  — it executed and reported failures, timed out / crashed, produced
    #           no parseable totals line (no-summary), or its framework flagged
    #           inconsistent bookkeeping (count-mismatch)
    #   ok    — executed, zero failures, totals parsed, counts consistent
    # SILENCE IS NEVER SUCCESS: a suite that fails mount, bails, and prints only
    # END_SESSION used to score ok 0/0 — it now scores fail/no-summary.
    SUITE_STATE="ok"
    SUITE_REASON=""
    if [[ $RUN_EXIT -eq 2 ]]; then
        SUITE_STATE="infra"
    elif [[ "$SUMMARY_FOUND" == false && $RUN_EXIT -eq 0 ]]; then
        SUITE_STATE="fail"
        SUITE_REASON="no-summary"
    elif [[ "$BAD_COUNTS" == true ]]; then
        SUITE_STATE="fail"
        SUITE_REASON="count-mismatch"
    elif [[ $RUN_EXIT -ne 0 || $SUITE_FAIL -gt 0 ]]; then
        SUITE_STATE="fail"
    fi

    # Store results
    RESULT_NAMES+=("$BASENAME")
    RESULT_PASS+=("$SUITE_PASS")
    RESULT_FAIL+=("$SUITE_FAIL")
    RESULT_TIME+=("$ELAPSED")
    RESULT_STATE+=("$SUITE_STATE")
    RESULT_REASON+=("$SUITE_REASON")
    TOTAL_PASS=$((TOTAL_PASS + SUITE_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + SUITE_FAIL))
    TOTAL_TIME=$((TOTAL_TIME + ELAPSED))

    RETRY_NOTE=""
    [[ "$RETRIED" == true ]] && RETRY_NOTE="  (retried)"

    # Print progress line
    case "$SUITE_STATE" in
        infra)
            printf "  ${YELLOW}[%2d/%d] %-38s   INFRA — suite did not execute  [%3ds]${NC}\n" \
                "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$ELAPSED"
            INFRA_SUITES+=("$BASENAME")
            ;;
        fail)
            printf "  ${RED}[%2d/%d] %-38s %4d pass, %3d fail  [%3ds]%s%s${NC}\n" \
                "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$SUITE_PASS" "$SUITE_FAIL" "$ELAPSED" "$RETRY_NOTE" \
                "${SUITE_REASON:+  ($SUITE_REASON)}"
            FAILED_SUITE="$BASENAME"
            FAILED_SUITES+=("$BASENAME")
            ;;
        *)
            printf "  ${GREEN}[%2d/%d]${NC} %-38s %4d pass, %3d fail  [%3ds]%s\n" \
                "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$SUITE_PASS" "$SUITE_FAIL" "$ELAPSED" "$RETRY_NOTE"
            ;;
    esac

    # --stop-on-failure: halt here and preserve the on-card evidence that
    # explains the failure (deliberately NO reformat).
    if [[ "$SUITE_STATE" != "ok" && "$STOP_ON_FAILURE" == true ]]; then
        if _in_list "$BASENAME" "${REFORMAT_AFTER[@]}"; then
            CARD_LEFT_DIRTY=true
        fi
        break
    fi

    # Default (continue) mode: return the card to a clean baseline after a
    # destructive suite that did NOT end ok (decision 7, 2026-08-09). A GREEN
    # destructive run leaves a healthy card — its own pass plus the closing
    # audit prove it — so the redundant format is skipped. A failing one still
    # reformats, because the run has to keep going and a damaged card would
    # cascade the failure into every suite after it. Forensics on a failed
    # destructive suite need --stop-on-failure.
    if [[ "$REFORMAT" == true && "$SUITE_STATE" != "ok" ]] && _in_list "$BASENAME" "${REFORMAT_AFTER[@]}"; then
        if ! _reformat_card "after $BASENAME"; then
            REFORMAT_FAILED=true
            break
        fi
        CARD_IS_FRESH=true
    fi
done

# --- Closing audit: prove the sweep leaves the card healthy -------------------
# Skipped when a reformat failed (card state unknown, audit would be meaningless)
# or when --stop-on-failure deliberately preserved a damaged card for inspection.
if [[ "$PREFLIGHT" == true && "$REFORMAT_FAILED" == false && "$CARD_LEFT_DIRTY" == false ]]; then
    echo ""
    if ! _run_audit "closing (read-only)"; then
        CLOSING_AUDIT_FAIL=true
    fi
fi

# --- Summary Table ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Regression Results${NC}"
echo -e "${BOLD}============================================================${NC}"
printf "  %-4s %-38s %5s %5s %5s\n" "#" "Suite" "Pass" "Fail" "Time"
printf "  %-4s %-38s %5s %5s %5s\n" "--" "--------------------------------------" "----" "----" "----"

for j in "${!RESULT_NAMES[@]}"; do
    IDX=$((START_INDEX + j + 1))
    case "${RESULT_STATE[$j]}" in
        infra)
            printf "  ${YELLOW}%2d  %-38s %5s %5s %4ds  INFRA${NC}\n" \
                "$IDX" "${RESULT_NAMES[$j]}" "-" "-" "${RESULT_TIME[$j]}"
            ;;
        fail)
            printf "  ${RED}%2d  %-38s %5d %5d %4ds%s${NC}\n" \
                "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_PASS[$j]}" "${RESULT_FAIL[$j]}" "${RESULT_TIME[$j]}" \
                "${RESULT_REASON[$j]:+  (${RESULT_REASON[$j]})}"
            ;;
        *)
            printf "  %2d  %-38s %5d %5d %4ds\n" \
                "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_PASS[$j]}" "${RESULT_FAIL[$j]}" "${RESULT_TIME[$j]}"
            ;;
    esac
done

printf "  %-4s %-38s %5s %5s %5s\n" "--" "--------------------------------------" "----" "----" "----"
printf "  %-4s %-38s %5d %5d %4ds\n" "" "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_TIME"
if [[ $REFORMAT_COUNT -gt 0 ]]; then
    printf "  %-4s %-38s %5s %5s %4ds\n" "" "card reformats (${REFORMAT_COUNT})" "" "" "$REFORMAT_TIME"
fi
echo ""

# --- Stack watermarks (--stack-report measurement sweeps only) -----------------
# The max across a FULL green sweep is the release-sizing input. The sizing
# formula and its application rules live at the STACK_SIZE CON in the driver --
# the arithmetic below implements it; change them together.
if [[ "$STACK_REPORT" == true ]]; then
    echo -e "${BOLD}  Worker-stack watermarks (measurement build)${NC}"
    printf "  %-4s %-38s %s\n" "#" "Suite" "Stack used/size (longs)"
    for j in "${!RESULT_NAMES[@]}"; do
        IDX=$((START_INDEX + j + 1))
        printf "  %2d  %-38s %s\n" "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_STACK[$j]}"
    done
    if [[ $STACK_MAX -gt 0 ]]; then
        SUGGESTED=$(( ((STACK_MAX + 32 + 15) / 16) * 16 ))
        echo ""
        echo -e "  Max watermark: ${BOLD}${STACK_MAX}${NC} of ${STACK_MAX_SIZE} longs (${STACK_MAX_SUITE})"
        echo -e "  Suggested release STACK_SIZE: ${BOLD}${SUGGESTED}${NC} (max + 32, rounded up to multiple of 16)"
        echo -e "  ${YELLOW}Apply ONLY after a FULL green sweep; annotate with sweep date + card serial.${NC}"
    else
        echo ""
        echo -e "  ${YELLOW}No watermark lines captured — no suite reached its totals line.${NC}"
    fi
    echo ""
fi

# --- Verdict ------------------------------------------------------------------
# Anything short of "every suite ran and passed, and the card ends healthy" is a
# non-zero exit. Each condition is reported separately so the cause is explicit.
RUN_OK=true

if [[ "$REFORMAT_FAILED" == true ]]; then
    echo -e "  ${RED}ABORTED: card reformat failed — see the block above.${NC}"
    echo -e "  ${YELLOW}The card is in an unknown state; results after this point are void.${NC}"
    RUN_OK=false
fi

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    if [[ "$STOP_ON_FAILURE" == true ]]; then
        echo -e "  ${RED}STOPPED: $FAILED_SUITE failed (suite $SUITE_NUM of $TOTAL_SUITES)${NC}"
    else
        echo -e "  ${RED}FAILED SUITES (${#FAILED_SUITES[@]}):${NC}"
        for f in "${FAILED_SUITES[@]}"; do
            echo -e "    ${RED}- $f${NC}  ($(_latest_log "$f"))"
        done
    fi
    RUN_OK=false
fi

if [[ ${#INFRA_SUITES[@]} -gt 0 ]]; then
    echo -e "  ${YELLOW}INFRASTRUCTURE FAILURES (${#INFRA_SUITES[@]}) — suite never executed,${NC}"
    echo -e "  ${YELLOW}retried once and still failed to download. NOT a driver result:${NC}"
    for f in "${INFRA_SUITES[@]}"; do
        echo -e "    ${YELLOW}- $f${NC}"
    done
    echo -e "  ${CYAN}Re-run just these: ./run_regression.sh --from <name>${NC}"
    RUN_OK=false
fi

if [[ "$CLOSING_AUDIT_FAIL" == true ]]; then
    echo -e "  ${RED}CLOSING AUDIT FAILED — the sweep left the card unhealthy.${NC}"
    echo -e "  ${CYAN}Audit log: ${AUDIT_LOG}${NC}"
    echo -e "  ${YELLOW}Treat as a hard blocker: on a fixed driver the sweep must end clean.${NC}"
    RUN_OK=false
fi

if [[ "$PREFLIGHT_FSCK_FAIL" == true ]]; then
    echo -e "  ${YELLOW}Note: the sweep-start card check did not come back clean — fsck failed,${NC}"
    echo -e "  ${YELLOW}could not fully repair, or the read-only audit found issues. Pre-existing,${NC}"
    echo -e "  ${YELLOW}informational.${NC}"
fi

if [[ "$CARD_LEFT_DIRTY" == true ]]; then
    echo ""
    echo -e "  ${YELLOW}$FAILED_SUITE is destructive — the card was left as-is so you can${NC}"
    echo -e "  ${YELLOW}inspect the damage (e.g. run the SD FAT32 audit).${NC}"
    echo -e "  ${CYAN}When done: ./run_regression.sh --reformat-only${NC}"
fi

if [[ "$RUN_OK" == false ]]; then
    echo ""
    exit 1
fi

if [[ -n "$FROM_SUITE" ]]; then
    echo -e "  ${GREEN}Result: ALL $SUITES_RUN SUITES PASSED (resumed from #$((START_INDEX + 1)))${NC}"
else
    echo -e "  ${GREEN}Result: ALL $TOTAL_SUITES SUITES PASSED${NC}"
fi
if [[ "$PREFLIGHT" == true && "$CLOSING_AUDIT_FAIL" == false ]]; then
    echo -e "  ${GREEN}Card health: closing audit clean.${NC}"
fi
echo ""
exit 0
