#!/bin/bash
#
# run_spi_sweep.sh - Characterize max reliable SPI speed on external SD header
#
# Sweeps multiple SYSCLK values to probe SPI frequencies between 22-25 MHz.
# At each SYSCLK, the test runs at the highest SPI frequency below 25 MHz,
# performing 10 write-read-verify round-trips of 8 sectors each.
#
# Must be run from the tools/ directory.
#

set +e

TEST_FILE="../diagnostic-tests/SD_spi_limit_test.spin2"

# SYSCLK values (MHz) that give unique SPI frequencies in the 22-25 MHz gap
# Sorted by resulting SPI frequency ascending:
#   220 MHz -> hp=5 -> 22.000 MHz
#   270 MHz -> hp=6 -> 22.500 MHz
#   320 MHz -> hp=7 -> 22.857 MHz
#   370 MHz -> hp=8 -> 23.125 MHz
#   280 MHz -> hp=6 -> 23.333 MHz
#   380 MHz -> hp=8 -> 23.750 MHz
#   240 MHz -> hp=5 -> 24.000 MHz
#   290 MHz -> hp=6 -> 24.167 MHz
#   390 MHz -> hp=8 -> 24.375 MHz
#   350 MHz -> hp=7 -> 25.000 MHz (known FAIL, included as control)

SYSCLK_VALUES=(220 270 320 370 280 380 240 290 390 350)

# Parallel arrays for expected SPI frequency (for display)
SPI_EXPECTED=("22.000" "22.500" "22.857" "23.125" "23.333" "23.750" "24.000" "24.167" "24.375" "25.000")

echo ""
echo "============================================================"
echo "  SPI Max Speed Characterization - External Header"
echo "  Sweeping SYSCLK to probe 22-25 MHz SPI range"
echo "============================================================"
echo ""

# Save original file
cp "$TEST_FILE" "${TEST_FILE}.bak"

RESULTS=()
idx=0

for SYSCLK in "${SYSCLK_VALUES[@]}"; do
    CLKFREQ="${SYSCLK}_000_000"
    EXPECTED_SPI="${SPI_EXPECTED[$idx]}"

    echo "--- Testing SYSCLK=${SYSCLK} MHz (expected SPI ~${EXPECTED_SPI} MHz) ---"

    # Patch _CLKFREQ in the test file
    sed -i '' "s/    _CLKFREQ        = [0-9_]*/    _CLKFREQ        = ${CLKFREQ}/" "$TEST_FILE"

    # Run the test (60s timeout is plenty for 10 iterations)
    OUTPUT=$(./run_test.sh "$TEST_FILE" -t 60 2>&1)

    # Extract the result from the log
    LOGFILE=$(echo "$OUTPUT" | grep "^Log file:" | sed 's/Log file: //')
    if [ -z "$LOGFILE" ]; then
        LOGFILE=$(echo "$OUTPUT" | grep "tools/logs/" | tail -1 | sed 's/.*tools/tools/')
    fi

    if [ -n "$LOGFILE" ] && [ -f "$LOGFILE" ]; then
        RESULT_LINE=$(grep "RESULT=" "$LOGFILE" | tail -1)
        ACTUAL_LINE=$(grep "actual=" "$LOGFILE" | tail -1)
        HP_VAL=$(echo "$ACTUAL_LINE" | grep -o 'hp=[0-9]*' | head -1)
        ACTUAL_HZ=$(echo "$ACTUAL_LINE" | grep -o 'actual=[0-9_]*' | head -1)

        if echo "$RESULT_LINE" | grep -q "RESULT=PASS"; then
            RESULTS+=("PASS")
            echo "  -> PASS (${HP_VAL}, ${ACTUAL_HZ} Hz)"
        elif echo "$RESULT_LINE" | grep -q "RESULT=FAIL"; then
            FAIL_DETAIL=$(echo "$RESULT_LINE" | grep -o 'errors=[0-9]*/[0-9]*')
            RESULTS+=("FAIL")
            echo "  -> FAIL (${HP_VAL}, ${ACTUAL_HZ} Hz, ${FAIL_DETAIL})"
        elif echo "$OUTPUT" | grep -q "MOUNT_FAIL"; then
            RESULTS+=("MOUNT_FAIL")
            echo "  -> MOUNT_FAIL"
        else
            RESULTS+=("UNKNOWN")
            echo "  -> UNKNOWN (check log: $LOGFILE)"
        fi
    else
        RESULTS+=("NO_LOG")
        echo "  -> NO_LOG (compilation or download failed?)"
    fi

    echo ""
    idx=$((idx + 1))
done

# Restore original file
mv "${TEST_FILE}.bak" "$TEST_FILE"

# Print summary table sorted by SPI frequency
echo "============================================================"
echo "  SUMMARY - SPI Max Speed Characterization"
echo "============================================================"
echo ""
echo "  SPI (MHz)   SYSCLK  hp   Result"
echo "  ---------   ------  --   ------"
echo "  21.875      350     8    PASS (previous test)"

idx=0
for SYSCLK in "${SYSCLK_VALUES[@]}"; do
    EXPECTED_SPI="${SPI_EXPECTED[$idx]}"
    RESULT="${RESULTS[$idx]}"
    echo "  ${EXPECTED_SPI}      ${SYSCLK}     -    ${RESULT}"
    idx=$((idx + 1))
done

echo ""
echo "============================================================"
echo ""
