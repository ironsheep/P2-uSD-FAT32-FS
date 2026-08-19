#!/usr/bin/env bash
#
# check_doc_version.sh — verify the driver's version constant, its printable
# string, and the newest CHANGELOG heading all say the same thing.
#
# WHY THIS GATES. The driver gained a version constant on 2026-08-19 for one
# reason: every performance figure in the card catalog is a measurement of the
# driver as much as of the card, and until the driver could name itself, no
# measurement could name the driver that produced it. Characterization tools now
# stamp DRIVER_VERSION_* into their transcripts, and the catalog states its
# provenance from that stamp in a single banner.
#
# That makes a stale constant worse than no constant. A hand-bumped number that
# silently disagrees with the changelog does not merely go unnoticed — it labels
# a whole sweep's worth of rows with the wrong driver, and the mislabelling is
# indistinguishable from correct data afterwards. So unlike check_doc_counts.sh,
# which is advisory, this one exits non-zero.
#
# It never edits anything and never needs hardware. Run it from anywhere.
#
# Deliberately bash 3.2 compatible (no associative arrays, no mapfile), unlike
# the four older audit scripts — see the punch-list item on their bash 4+
# requirement. macOS ships bash 3.2, and a release gate that cannot run on the
# release machine is not a gate.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

DRIVER="src/micro_sd_fat32_fs.spin2"
CHANGELOG="CHANGELOG.md"

fail=0

note_fail() {
    printf "  ${RED}FAIL${NC}   %s\n" "$1"
    fail=$((fail + 1))
}

note_ok() {
    printf "  ${GREEN}OK${NC}     %s\n" "$1"
}

# ---- read the three sources ------------------------------------------------

con_field() {
    # $1 = constant name; prints its integer value, or nothing if absent.
    grep -oE "^[[:space:]]*$1[[:space:]]*=[[:space:]]*[0-9]+" "$DRIVER" 2>/dev/null \
        | grep -oE '[0-9]+$' | head -1
}

MAJOR="$(con_field DRIVER_VERSION_MAJOR)"
MINOR="$(con_field DRIVER_VERSION_MINOR)"
PATCH="$(con_field DRIVER_VERSION_PATCH)"

# The printable form the tools actually stamp into transcripts.
STR_VERSION="$(grep -oE '^[[:space:]]*str_driver_version[[:space:]]+BYTE[[:space:]]+"[0-9]+\.[0-9]+\.[0-9]+"' \
    "$DRIVER" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

# The newest version heading in the changelog: "## [1.8.0] - unreleased" or
# "## [1.8.0] - 2026-08-19". An [Unreleased] placeholder heading carries no
# number and is skipped, so a draft section above the newest real release does
# not break the check.
CHANGELOG_VERSION="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

echo ""
echo -e "${CYAN}Driver version vs changelog${NC}"
echo ""

# ---- check that each source exists at all ----------------------------------

if [[ -z "$MAJOR" || -z "$MINOR" || -z "$PATCH" ]]; then
    note_fail "DRIVER_VERSION_MAJOR/MINOR/PATCH not all found in $DRIVER"
    echo ""
    exit 1
fi
CON_VERSION="$MAJOR.$MINOR.$PATCH"
note_ok "constants            $CON_VERSION  ($DRIVER)"

if [[ -z "$STR_VERSION" ]]; then
    note_fail "str_driver_version string not found in $DRIVER"
else
    note_ok "version string       $STR_VERSION  ($DRIVER)"
fi

if [[ -z "$CHANGELOG_VERSION" ]]; then
    note_fail "no versioned heading found in $CHANGELOG (expected '## [X.Y.Z]')"
else
    note_ok "newest changelog     $CHANGELOG_VERSION  ($CHANGELOG)"
fi

echo ""

# ---- compare ---------------------------------------------------------------

if [[ -n "$STR_VERSION" && "$STR_VERSION" != "$CON_VERSION" ]]; then
    note_fail "version string \"$STR_VERSION\" disagrees with the constants ($CON_VERSION)."
    echo "         Tools print the string; comparisons use the constants. They must match."
fi

if [[ -n "$CHANGELOG_VERSION" && "$CHANGELOG_VERSION" != "$CON_VERSION" ]]; then
    note_fail "the driver says $CON_VERSION but the newest changelog heading says $CHANGELOG_VERSION."
    echo "         Bump the CON block in $DRIVER and str_driver_version together,"
    echo "         or add the changelog section for the version the driver claims."
fi

echo ""
if [[ $fail -eq 0 ]]; then
    echo -e "${GREEN}Version is consistent — driver, string and changelog all say $CON_VERSION.${NC}"
    echo ""
    exit 0
fi

echo -e "${RED}${fail} version inconsistency(ies). Every sweep row stamped by this build would be mislabelled.${NC}"
echo ""
exit 1
