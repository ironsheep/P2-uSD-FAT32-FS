#!/bin/bash
#
# run_regression.sh - Unified regression runner for SD FAT32 driver
#
# Usage: ./run_regression.sh [options]
#
# Runs all regression suites in dependency order (foundational-first),
# with stop-on-first-failure, per-file progress, and a final summary table.
#
# Options:
#   --from <name>      Resume from a specific suite (substring match on basename).
#                      Compiles only that suite and remaining, then runs from there.
#   --include-format   Include format test (WARNING: erases SD card!)
#   --compile-only     Only compile all tests, do not run on hardware
#   --no-reformat      Do NOT reformat the card during the run (see below)
#   --reformat-only    Reformat the card and exit (recovery after a failed run)
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
# On a suite FAILURE the runner does NOT auto-reformat — that would destroy
# the on-card forensic evidence (e.g. the fatchain DETECT run, where the
# post-failure FAT/VBR damage IS the evidence). It prints a recovery hint
# instead; use --reformat-only when you are done inspecting the card.
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed (or a reformat failed)
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
REFORMAT_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --reformat-only)   REFORMAT_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--from <name>] [--include-format] [--compile-only] [--run-only]"
            echo "          [--external] [--no-reformat] [--reformat-only]"
            echo ""
            echo "Options:"
            echo "  --from <name>      Resume from suite matching <name> (substring match)"
            echo "  --include-format   Include format test (WARNING: erases SD card!)"
            echo "  --compile-only     Only compile, do not run on hardware"
            echo "  --run-only         Only recompile stale .bin files (source or driver newer)"
            echo "  --external         Compile with -D SD_PINS_EXTERNAL (use external SD header)"
            echo "                     Default (no flag): P2 Edge onboard SD slot."
            echo "  --no-reformat      Do not reformat the card during the run"
            echo "  --reformat-only    Reformat the card and exit (recovery after a failed run)"
            echo ""
            echo "The card is treated as SCRATCH on hardware runs: a clean FAT32 baseline is"
            echo "established before the first suite and the card is reformatted around the"
            echo "destructive suites. This runner is the ONLY place that reformats;"
            echo "single-suite run_test.sh never does."
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
            exit 0
            ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# Build per-test --external flag pass-through (for run_test.sh) and direct
# pnut-ts preprocessor flag (for compile-only path that calls pnut-ts directly).
EXTERNAL_FLAG=""
PIN_DEFINE_FLAG=""
if [[ "$EXTERNAL_PINS" == "true" ]]; then
    EXTERNAL_FLAG="--external"
    PIN_DEFINE_FLAG="-D SD_PINS_EXTERNAL"
fi

# --- Card-as-scratch (reformat) machinery -------------------------------------
# DESTRUCTIVE. Regression runner only — see the header block. Nothing here is
# reachable from tools/run_test.sh; it is only used as the launcher below.

FORMAT_VEHICLE_BASE="SD_format_card"
FORMAT_VEHICLE="$PROJECT_ROOT/src/UTILS/${FORMAT_VEHICLE_BASE}.spin2"
REFORMAT_TIMEOUT=300

# Suites that need a guaranteed-clean card going IN (capacity/geometry gates).
REFORMAT_BEFORE=(
    "SD_RT_fatchain_tests"
)

# Suites that can leave the card unusable/altered on the way OUT.
#   fatchain — on an unfixed driver its writes damage the FAT/VBR (Bug A)
#   format   — leaves whatever label/geometry the format suite chose
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
        # Marker choice matters: the vehicle's own "FORMAT SUCCESSFUL!" is only
        # two debug lines ahead of END_SESSION, and pnut-term-ts stops logging
        # the moment it sees END_SESSION — so on a SUCCESSFUL format that line
        # is routinely truncated mid-word out of the log. isp_format_utility's
        # "FORMAT COMPLETE" is emitted only under `if ok` and is followed by
        # four more lines, so it lands intact. Accept either; "FORMAT FAILED"
        # is decisive regardless.
        if [[ "$clean" != *"FORMAT FAILED"* ]]; then
            if [[ "$clean" == *"FORMAT COMPLETE"* || "$clean" == *"FORMAT SUCCESSFUL"* ]]; then
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
    "SD_RT_crc_validation_tests.spin2:120"
    "SD_RT_recovery_tests.spin2:120"
)

# Layer 5: Basic file I/O
SUITES+=(
    "SD_RT_file_ops_tests.spin2:120"
    "SD_RT_read_write_tests.spin2:90"
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
echo "  Format test: $([[ "$INCLUDE_FORMAT" == true ]] && echo "INCLUDED (destructive!)" || echo "excluded")"
echo "  SD pins:     $([[ "$EXTERNAL_PINS" == true ]] && echo "EXTERNAL header (base pin 16)" || echo "P2 Edge onboard slot")"
if [[ "$COMPILE_ONLY" == true ]]; then
    echo "  Card:        untouched (compile only)"
elif [[ "$REFORMAT" == true ]]; then
    echo "  Card:        SCRATCH — baseline reformat + reformat around destructive suites"
else
    echo "  Card:        preserved (--no-reformat) — suites must self-establish"
fi
if [[ "$COMPILE_ONLY" == true ]]; then
    echo "  Mode: COMPILE ONLY"
elif [[ "$RUN_ONLY" == true ]]; then
    echo "  Mode: RUN ONLY (using existing .bin files)"
else
    echo "  Mode: COMPILE + RUN"
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
            if pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" >/dev/null 2>&1; then
                SIZE=$(wc -c < "${BASENAME}.bin" | tr -d ' ')
                echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes) [recompiled]"
                COMPILE_PASS=$((COMPILE_PASS + 1))
            else
                echo -e "  ${RED}FAIL${NC}: $FILE"
                pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" 2>&1 | grep -i error || true
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
        if pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" >/dev/null 2>&1; then
            SIZE=$(wc -c < "${BASENAME}.bin" | tr -d ' ')
            echo -e "  ${GREEN}OK${NC}: $FILE (${SIZE} bytes)"
            COMPILE_PASS=$((COMPILE_PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC}: $FILE"
            pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$SRC_PATH" -I "$UTILS_PATH" -I "$DEMO_PATH" -I . "$FILE" 2>&1 | grep -i error || true
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

# --- Phase 1b: Compile the reformat vehicle ---
# Built here so a broken format utility fails the run up front, not halfway
# through on hardware. run_test.sh recompiles it at launch time anyway.
if [[ "$REFORMAT" == true ]]; then
    UTILS_DIR="$PROJECT_ROOT/src/UTILS"
    V_SRC_PATH="$(_relpath "$PROJECT_ROOT/src" "$UTILS_DIR")"
    V_DEMO_PATH="$(_relpath "$PROJECT_ROOT/src/DEMO" "$UTILS_DIR")"
    cd "$UTILS_DIR"
    if [[ "$RUN_ONLY" == true ]] && ! _needs_compile "${FORMAT_VEHICLE_BASE}.spin2"; then
        echo -e "  ${GREEN}OK${NC}: ${FORMAT_VEHICLE_BASE}.spin2 (reformat vehicle, up-to-date)"
    elif pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$V_SRC_PATH" -I . -I "$V_DEMO_PATH" "${FORMAT_VEHICLE_BASE}.spin2" >/dev/null 2>&1; then
        V_SIZE=$(wc -c < "${FORMAT_VEHICLE_BASE}.bin" | tr -d ' ')
        echo -e "  ${GREEN}OK${NC}: ${FORMAT_VEHICLE_BASE}.spin2 (${V_SIZE} bytes) [reformat vehicle]"
    else
        echo -e "  ${RED}FAIL${NC}: ${FORMAT_VEHICLE_BASE}.spin2 [reformat vehicle]"
        pnut-ts -d $CACHE_FLAGS $PIN_DEFINE_FLAG -I "$V_SRC_PATH" -I . -I "$V_DEMO_PATH" "${FORMAT_VEHICLE_BASE}.spin2" 2>&1 | grep -i error || true
        cd "$SCRIPT_DIR"
        echo ""
        echo -e "${RED}The reformat vehicle does not compile — the runner cannot establish${NC}"
        echo -e "${RED}a clean card. Fix it, or rerun with --no-reformat.${NC}"
        exit 1
    fi
    cd "$SCRIPT_DIR"
    echo ""
fi

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
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TIME=0
SUITES_RUN=0
FAILED_SUITE=""
REFORMAT_FAILED=false
CARD_LEFT_DIRTY=false
CARD_IS_FRESH=false        # true = nothing has touched the card since the last format

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
    if [[ "$REFORMAT" == true && "$CARD_IS_FRESH" == false ]] && _in_list "$BASENAME" "${REFORMAT_BEFORE[@]}"; then
        if ! _reformat_card "before $BASENAME"; then
            REFORMAT_FAILED=true
            break
        fi
    fi

    CARD_IS_FRESH=false
    START_TIME=$(date +%s)

    # Run the test via run_test.sh
    set +e
    ./run_test.sh "../src/regression-tests/$FILE" -t "$TIMEOUT" $EXTERNAL_FLAG > /dev/null 2>&1
    RUN_EXIT=$?
    set -e

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    # Parse log for pass/fail counts
    SUITE_PASS=0
    SUITE_FAIL=0

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
        fi
    fi

    # Determine if this suite failed
    SUITE_FAILED=false
    if [[ $RUN_EXIT -ne 0 ]]; then
        SUITE_FAILED=true
    elif [[ $SUITE_FAIL -gt 0 ]]; then
        SUITE_FAILED=true
    fi

    # Store results
    RESULT_NAMES+=("$BASENAME")
    RESULT_PASS+=("$SUITE_PASS")
    RESULT_FAIL+=("$SUITE_FAIL")
    RESULT_TIME+=("$ELAPSED")
    TOTAL_PASS=$((TOTAL_PASS + SUITE_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + SUITE_FAIL))
    TOTAL_TIME=$((TOTAL_TIME + ELAPSED))

    # Print progress line
    if [[ "$SUITE_FAILED" == true ]]; then
        printf "  ${RED}[%2d/%d] %-38s %4d pass, %3d fail  [%3ds]${NC}\n" \
            "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$SUITE_PASS" "$SUITE_FAIL" "$ELAPSED"
        FAILED_SUITE="$BASENAME"
        # Deliberately NO reformat here: a failed destructive suite leaves the
        # on-card evidence that explains the failure. Preserve it for inspection.
        if _in_list "$BASENAME" "${REFORMAT_AFTER[@]}"; then
            CARD_LEFT_DIRTY=true
        fi
        break
    else
        printf "  ${GREEN}[%2d/%d]${NC} %-38s %4d pass, %3d fail  [%3ds]\n" \
            "$SUITE_NUM" "$TOTAL_SUITES" "$BASENAME" "$SUITE_PASS" "$SUITE_FAIL" "$ELAPSED"
    fi

    # Suites that can leave the card unusable/altered on the way out
    if [[ "$REFORMAT" == true ]] && _in_list "$BASENAME" "${REFORMAT_AFTER[@]}"; then
        if ! _reformat_card "after $BASENAME"; then
            REFORMAT_FAILED=true
            break
        fi
        CARD_IS_FRESH=true
    fi
done

# --- Summary Table ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Regression Results${NC}"
echo -e "${BOLD}============================================================${NC}"
printf "  %-4s %-38s %5s %5s %5s\n" "#" "Suite" "Pass" "Fail" "Time"
printf "  %-4s %-38s %5s %5s %5s\n" "--" "--------------------------------------" "----" "----" "----"

for j in "${!RESULT_NAMES[@]}"; do
    IDX=$((START_INDEX + j + 1))
    if [[ "${RESULT_FAIL[$j]}" -gt 0 ]] || { [[ -n "$FAILED_SUITE" ]] && [[ "${RESULT_NAMES[$j]}" == "$FAILED_SUITE" ]]; }; then
        printf "  ${RED}%2d  %-38s %5d %5d %4ds${NC}\n" \
            "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_PASS[$j]}" "${RESULT_FAIL[$j]}" "${RESULT_TIME[$j]}"
    else
        printf "  %2d  %-38s %5d %5d %4ds\n" \
            "$IDX" "${RESULT_NAMES[$j]}" "${RESULT_PASS[$j]}" "${RESULT_FAIL[$j]}" "${RESULT_TIME[$j]}"
    fi
done

printf "  %-4s %-38s %5s %5s %5s\n" "--" "--------------------------------------" "----" "----" "----"
printf "  %-4s %-38s %5d %5d %4ds\n" "" "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_TIME"
if [[ $REFORMAT_COUNT -gt 0 ]]; then
    printf "  %-4s %-38s %5s %5s %4ds\n" "" "card reformats (${REFORMAT_COUNT})" "" "" "$REFORMAT_TIME"
fi
echo ""

if [[ "$REFORMAT_FAILED" == true ]]; then
    echo -e "  ${RED}ABORTED: card reformat failed — see the block above.${NC}"
    echo -e "  ${YELLOW}The card is in an unknown state; results after this point are void.${NC}"
    echo ""
    exit 1
fi

if [[ -n "$FAILED_SUITE" ]]; then
    echo -e "  ${RED}STOPPED: $FAILED_SUITE failed (suite $SUITE_NUM of $TOTAL_SUITES)${NC}"
    if [[ -n "$LATEST_LOG" ]]; then
        echo -e "  ${CYAN}Log: $LATEST_LOG${NC}"
    fi
    if [[ "$CARD_LEFT_DIRTY" == true ]]; then
        echo ""
        echo -e "  ${YELLOW}$FAILED_SUITE is destructive — the card was left as-is so you can${NC}"
        echo -e "  ${YELLOW}inspect the damage (e.g. run the SD FAT32 audit).${NC}"
        echo -e "  ${CYAN}When done: ./run_regression.sh --reformat-only${NC}"
    fi
    echo ""
    exit 1
fi

if [[ -n "$FROM_SUITE" ]]; then
    echo -e "  ${GREEN}Result: ALL $SUITES_RUN SUITES PASSED (resumed from #$((START_INDEX + 1)))${NC}"
else
    echo -e "  ${GREEN}Result: ALL $TOTAL_SUITES SUITES PASSED${NC}"
fi
echo ""
exit 0
