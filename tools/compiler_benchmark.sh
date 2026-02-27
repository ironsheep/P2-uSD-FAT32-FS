#!/bin/bash
#
# compiler_benchmark.sh - Compile all top-level .spin2 files and record size/checksum/time
#
# Usage: ./compiler_benchmark.sh [label]
#   label: identifier for this run (e.g., "v1.52.1" or "v1.53.0")
#
# Output: tools/logs/compiler_benchmark_<label>_<timestamp>.txt
#

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${1:-baseline}"
TIMESTAMP=$(date +%y%m%d-%H%M%S)
OUTFILE="$PROJECT_ROOT/tools/logs/compiler_benchmark_${LABEL}_${TIMESTAMP}.txt"

# Get compiler version
COMPILER_VERSION=$(pnut-ts --version 2>&1 | head -1)
COMPILER_PATH=$(which pnut-ts)

# Results array
declare -a RESULTS

compile_file() {
    local src_dir="$1"
    local filename="$2"
    local flags="$3"
    local include_flags="$4"
    local category="$5"

    local basename="${filename%.spin2}"
    local binfile="${src_dir}/${basename}.bin"

    cd "$src_dir"

    # Remove any stale binary
    rm -f "$binfile"

    # Time the compilation (no -o flag; pnut-ts writes .bin next to source)
    local start_ns=$(python3 -c "import time; print(int(time.time()*1000))")
    local output
    output=$(pnut-ts $flags $include_flags "$filename" 2>&1)
    local exit_code=$?
    local end_ns=$(python3 -c "import time; print(int(time.time()*1000))")
    local elapsed_ms=$(( end_ns - start_ns ))

    if [ $exit_code -ne 0 ] || [ ! -f "$binfile" ]; then
        RESULTS+=("$category|$filename|FAILED|0|n/a|${elapsed_ms}")
        echo "  FAIL: $filename ($output)"
        return
    fi

    # Get size and checksum
    local size=$(wc -c < "$binfile" | tr -d ' ')
    local md5=$(md5 -q "$binfile")

    # Clean up binary
    rm -f "$binfile"

    RESULTS+=("$category|$filename|OK|$size|$md5|${elapsed_ms}")
    printf "  %-45s %6d B  %4d ms  %s\n" "$filename" "$size" "$elapsed_ms" "$md5"
}

echo "========================================"
echo "  Compiler Benchmark: $LABEL"
echo "  Compiler: $COMPILER_VERSION"
echo "  Path: $COMPILER_PATH"
echo "  Date: $(date)"
echo "========================================"
echo ""

# Track total time
TOTAL_START=$(python3 -c "import time; print(int(time.time()*1000))")

# --- Regression tests (with -d) ---
echo "--- Regression Tests (18 files, compiled with -d) ---"
RT_DIR="$PROJECT_ROOT/regression-tests"
RT_INC="-I ../src/ -I ../src/UTILS/ -I ../src/DEMO/ -I ./"
for f in \
    SD_RT_mount_tests.spin2 \
    SD_RT_volume_tests.spin2 \
    SD_RT_file_ops_tests.spin2 \
    SD_RT_read_write_tests.spin2 \
    SD_RT_seek_tests.spin2 \
    SD_RT_directory_tests.spin2 \
    SD_RT_dirhandle_tests.spin2 \
    SD_RT_subdir_ops_tests.spin2 \
    SD_RT_multihandle_tests.spin2 \
    SD_RT_multicog_tests.spin2 \
    SD_RT_error_handling_tests.spin2 \
    SD_RT_register_tests.spin2 \
    SD_RT_speed_tests.spin2 \
    SD_RT_crc_diag_tests.spin2 \
    SD_RT_raw_sector_tests.spin2 \
    SD_RT_multiblock_tests.spin2 \
    SD_RT_format_tests.spin2 \
    SD_RT_fifo_tests.spin2 \
; do
    compile_file "$RT_DIR" "$f" "-d" "$RT_INC" "regression"
done
echo ""

# --- Diagnostic tests (with -d) ---
echo "--- Diagnostic Tests (4 files, compiled with -d) ---"
DT_DIR="$PROJECT_ROOT/diagnostic-tests"
DT_INC="-I ../src/ -I ../src/UTILS/ -I ../src/DEMO/ -I ../regression-tests/"
for f in \
    SD_card_info_tests.spin2 \
    SD_freq_sweep_tests.spin2 \
    SD_spi_limit_test.spin2 \
    SD_diag_fsck_window_test.spin2 \
; do
    compile_file "$DT_DIR" "$f" "-d" "$DT_INC" "diagnostic"
done
echo ""

# --- Utilities (no -d) ---
echo "--- Utilities (7 files, no debug) ---"
UT_DIR="$PROJECT_ROOT/src/UTILS"
UT_INC="-I ../ -I ./ -I ../DEMO/ -I ../../regression-tests/"
for f in \
    SD_format_card.spin2 \
    SD_FAT32_fsck.spin2 \
    SD_FAT32_audit.spin2 \
    SD_card_characterize.spin2 \
    SD_frequency_characterize.spin2 \
    SD_performance_benchmark.spin2 \
    SD_speed_characterize.spin2 \
; do
    compile_file "$UT_DIR" "$f" "" "$UT_INC" "utility"
done
echo ""

# --- Demo (no -d) ---
echo "--- Demo (1 file, no debug) ---"
DM_DIR="$PROJECT_ROOT/src/DEMO"
DM_INC="-I ../ -I ../UTILS/ -I ./ -I ../../regression-tests/"
compile_file "$DM_DIR" "SD_demo_shell.spin2" "" "$DM_INC" "demo"
echo ""

# --- Examples (no -d) ---
echo "--- Examples (4 files, no debug) ---"
EX_DIR="$PROJECT_ROOT/src/EXAMPLES"
EX_INC="-I ../ -I ../UTILS/ -I ../DEMO/ -I ../../regression-tests/"
for f in \
    SD_example_read_write.spin2 \
    SD_example_data_logger.spin2 \
    SD_example_directory_walk.spin2 \
    SD_example_multicog.spin2 \
; do
    compile_file "$EX_DIR" "$f" "" "$EX_INC" "example"
done
echo ""

TOTAL_END=$(python3 -c "import time; print(int(time.time()*1000))")
TOTAL_MS=$(( TOTAL_END - TOTAL_START ))

echo "========================================"
echo "  Total: ${#RESULTS[@]} files compiled in ${TOTAL_MS} ms"
echo "========================================"

# Write results file
{
    echo "# Compiler Benchmark Results"
    echo ""
    echo "Label: $LABEL"
    echo "Compiler: $COMPILER_VERSION"
    echo "Path: $COMPILER_PATH"
    echo "Date: $(date)"
    echo "Total files: ${#RESULTS[@]}"
    echo "Total time: ${TOTAL_MS} ms"
    echo ""
    echo "| Category | File | Status | Size (B) | MD5 Checksum | Time (ms) |"
    echo "|---|---|---|---|---|---|"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r cat file status size md5 time <<< "$r"
        echo "| $cat | $file | $status | $size | $md5 | $time |"
    done
    echo ""
    echo "## Summary by Category"
    echo ""
    for cat in regression diagnostic utility demo example; do
        count=0; total_size=0; total_time=0; fails=0
        for r in "${RESULTS[@]}"; do
            IFS='|' read -r c f s sz m t <<< "$r"
            if [ "$c" = "$cat" ]; then
                count=$((count + 1))
                if [ "$s" = "OK" ]; then
                    total_size=$((total_size + sz))
                    total_time=$((total_time + t))
                else
                    fails=$((fails + 1))
                fi
            fi
        done
        if [ $count -gt 0 ]; then
            echo "- **$cat**: $count files, $total_size bytes total, ${total_time} ms total ($fails failures)"
        fi
    done
} > "$OUTFILE"

echo ""
echo "Results written to: $OUTFILE"
