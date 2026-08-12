#!/usr/bin/env bash
#
# check_doc_counts.sh — report where documented counts have drifted from reality.
#
# Counts of things in the repository (suites, tests, structural checks) get
# written into several documents and then quietly go stale. This script measures
# the real numbers and prints them beside the documented ones so bumping them is
# a 30-second job at release time instead of an audit.
#
# It never edits anything and never needs hardware. Run it from tools/.
#
# Convention this supports: documented counts carry a version stamp — "471 tests
# across 26 suites (as of v1.6.1)" — rather than a bare number or a vague floor.
# A stamped exact number is precise and obviously datable; a floor ("at least
# 465") is unfalsifiable and tells a reader nothing they can act on. When this
# script reports drift, update the number AND the stamp together.
#
# Sample transcripts in documents are a different case and are NOT checked here:
# they are captured artifacts, stamped with the card and date they came from, so
# their contents cannot go stale. Re-capture them when a utility's output format
# changes, not on a schedule.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

drift=0

# ---- measure reality -------------------------------------------------------

SUITES_ON_DISK=$(ls src/regression-tests/SD_RT_*_tests.spin2 2>/dev/null | wc -l | tr -d ' ')

# Test total: the suite README's own grand-total row is the project's authority.
# Verify it against the sum of the per-suite rows in the same table.
README_TOTAL=$(grep -oE '\*\*Grand Total \([0-9]+ suites\)\*\* \| \*\*[0-9]+\*\*' \
    src/regression-tests/README.md 2>/dev/null | grep -oE '[0-9]+\*\*$' | tr -d '*')
README_SUITES=$(grep -oE '\*\*Grand Total \([0-9]+ suites\)\*\*' \
    src/regression-tests/README.md 2>/dev/null | grep -oE '[0-9]+')

# Structural checks the audit/fsck engine actually runs. Match call sites only —
# `auditRunTest(@"...")` — so the `PRI auditRunTest(...)` definition is not counted
# as a 24th check.
AUDIT_CHECKS=$(grep -c 'auditRunTest(@' src/UTILS/isp_fsck_utility.spin2 2>/dev/null)

# Suites enumerated in the release workflow.
WORKFLOW_SUITES=$(grep -c 'regression-tests/SD_RT_' .github/workflows/release.yml 2>/dev/null)

report() {
    local label="$1" actual="$2" documented="$3" where="$4"
    if [[ "$actual" == "$documented" ]]; then
        printf "  ${GREEN}OK${NC}     %-26s %-6s %s\n" "$label" "$actual" "$where"
    else
        printf "  ${RED}DRIFT${NC}  %-26s actual %-6s documented %-6s %s\n" \
            "$label" "$actual" "$documented" "$where"
        drift=$((drift + 1))
    fi
}

echo ""
echo -e "${CYAN}Documented counts vs reality${NC}"
echo ""

report "suite count" "$SUITES_ON_DISK" "$README_SUITES" "src/regression-tests/README.md"
report "suites in release.yml" "$SUITES_ON_DISK" "$WORKFLOW_SUITES" ".github/workflows/release.yml"

# Every place the test total is repeated.
#
# SCAN SET includes .release/ -- those README variants are what release.yml copies
# into the shipped bundle, so they are the ones a user actually reads. They were
# omitted until 2026-08-12 and had drifted to 471/26 while the tracked tree said
# 574/27.
#
# PATTERN allows intervening words ("471 automated tests"), because requiring
# "NNN tests" adjacency is what let that drift through a green run of this script.
DOC_SET=(README.md DOCs/*.md src/regression-tests/README.md
         .release/README.md .release/src/README.md .release/src/*/README.md)

while IFS=: read -r file line _; do
    [[ -z "$file" ]] && continue
    n=$(sed -n "${line}p" "$file" | grep -oE '[0-9]{3,}( [a-z]+)* tests?' | grep -oE '^[0-9]+' | head -1)
    [[ -z "$n" ]] && continue
    report "test total" "$README_TOTAL" "$n" "$file:$line"
done < <(grep -rnE '[0-9]{3,}( [a-z]+)* tests?' "${DOC_SET[@]}" 2>/dev/null)

# Every place the SUITE count is repeated in prose ("27 test suites", "27 test files").
while IFS=: read -r file line _; do
    [[ -z "$file" ]] && continue
    n=$(sed -n "${line}p" "$file" | grep -oE '[0-9]{1,3} test (suites|files)' | grep -oE '^[0-9]+' | head -1)
    [[ -z "$n" ]] && continue
    report "suite count" "$SUITES_ON_DISK" "$n" "$file:$line"
done < <(grep -rnE '[0-9]{1,3} test (suites|files)' "${DOC_SET[@]}" 2>/dev/null)

report "structural checks" "$AUDIT_CHECKS" \
    "$(grep -oE 'Structural checks: [0-9]+ pass' DOCs/SD-CARD-UTILITIES.md 2>/dev/null | grep -oE '[0-9]+' | head -1)" \
    "DOCs/SD-CARD-UTILITIES.md"

echo ""
if [[ $drift -eq 0 ]]; then
    echo -e "${GREEN}No drift — documented counts match reality.${NC}"
else
    echo -e "${YELLOW}${drift} drifted count(s). Update the number and its \"as of vX.Y.Z\" stamp together.${NC}"
fi
echo ""

# Counts are advisory, not a build gate: exit 0 either way so this can run in a
# release checklist without failing it.
exit 0
