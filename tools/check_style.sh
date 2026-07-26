#!/usr/bin/env bash
#
# check_style.sh — audit .spin2 sources against DOCs/procedures/SPIN2-AUTHORING-GUIDE.md.
#
# Project policy: all P2 code we produce conforms to that guide, and a release does
# not ship with a finding outstanding.
#
# WHERE THIS RUNS IN THE CYCLE: after the feature is complete, BEFORE regression
# testing. Not on every edit. The reason is the same one that cost this project four
# re-runs in v1.6.1 -- any change to source must precede the verification that
# certifies that source. Conform first, compile, then regression test, then hardware.
# Reformatting after a green run silently invalidates it.
#
# The guide has rules a script cannot judge (naming quality, "describe the data",
# doc-comment content). Those stay a human read. This covers what is mechanical, so
# the human read is short enough to actually happen.
#
# Exit codes: 0 = no FAIL findings (REVIEW items may still be listed), 1 = at least
# one FAIL. Unlike the doc checks, this one CAN fail a release gate.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

# Scope: everything under src/ -- driver, utilities, demo, examples, regression
# suites. diagnostic-tests/ is deliberately excluded: those are throwaway probes we
# write to answer one question, they never ship, and holding them to the shipped-code
# bar would discourage writing them.
mapfile -t FILES < <(git -C "$ROOT" ls-files --full-name 'src/*.spin2' 'src/**/*.spin2' 2>/dev/null | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo -e "${RED}No .spin2 files found under src/ -- aborting.${NC}"
    exit 0
fi

fails=0
reviews=0

fail()   { printf "  ${RED}FAIL${NC}    %-52s %s\n" "$1" "$2"; fails=$((fails + 1)); }
review() { printf "  ${YELLOW}REVIEW${NC}  %-52s %s\n" "$1" "$2"; reviews=$((reviews + 1)); }

echo ""
echo -e "${CYAN}Spin2 style audit — ${#FILES[@]} files under src/${NC}"
echo ""

# --- Rule 1.1: ASCII only -------------------------------------------------------
#
# The guide forbids non-ASCII in code, strings and signatures, and explicitly
# PERMITS Unicode box-drawing (U+2500-U+257F) and block elements (U+2580-U+259F)
# inside comments for diagrams. A blanket non-ASCII grep therefore over-reports
# massively -- this project's sources carry ~4000 box-drawing characters in comment
# diagrams, all of them legal.
#
# Split into two findings: non-ASCII reaching code or a string literal is a FAIL
# (it can corrupt compilation or print garbage to the terminal); a non-box-drawing
# character in a comment is a REVIEW, because the guide's forbidden-character table
# is scoped to "code, strings, and method signatures" and does not clearly rule on
# comment prose.
echo -e "${CYAN}Rule 1.1 — ASCII only${NC}"
for f in "${FILES[@]}"; do
    # Non-ASCII inside a string literal, on a line that is not a comment.
    hits=$(LC_ALL=C awk '
        /^[[:space:]]*'"'"'/ { next }                       # skip comment lines
        { line = $0
          while (match(line, /"[^"]*"/)) {
              s = substr(line, RSTART, RLENGTH)
              if (s ~ /[^\x00-\x7F]/) { print FNR": "s; break }
              line = substr(line, RSTART + RLENGTH)
          } }
    ' "$f" 2>/dev/null | head -3)
    [[ -n "$hits" ]] && fail "$f" "non-ASCII in a string literal: $(echo "$hits" | tr '\n' ' ')"

    # Non-ASCII in a comment that is not box-drawing or a block element.
    other=$(LC_ALL=C grep -nP '^[[:space:]]*'"'"'.*[^\x00-\x7F]' "$f" 2>/dev/null \
        | LC_ALL=C grep -vP '^[0-9]+:[^\x00-\x7F]*$' \
        | LC_ALL=C perl -ne 'print if /[^\x00-\x7F]/ && do { my $c = $_; $c =~ s/[\x{2500}-\x{257F}\x{2580}-\x{259F}]//g; $c =~ /[^\x00-\x7F]/ }' 2>/dev/null | wc -l | tr -d ' ')
    [[ "${other:-0}" -gt 0 ]] && review "$f" "$other comment line(s) with non-box-drawing non-ASCII"
done
[[ $fails -eq 0 ]] && echo -e "  ${GREEN}No non-ASCII in code or string literals.${NC}"

# --- Rule 1.8: @"" is invalid ---------------------------------------------------
echo ""
echo -e "${CYAN}Rule 1.8 — no empty string literal @\"\"${NC}"
found=0
for f in "${FILES[@]}"; do
    n=$(grep -c '@""' "$f" 2>/dev/null)
    [[ "${n:-0}" -gt 0 ]] && { fail "$f" "$n occurrence(s) of @\"\""; found=1; }
done
[[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"

# --- Rule 2.1: no single-letter variable names ----------------------------------
#
# Checks method signatures only: parameters, return names, and locals. A
# single-letter name inside a body is not reliably distinguishable from a constant.
echo ""
echo -e "${CYAN}Rule 2.1 — no single-letter variable names in signatures${NC}"
found=0
for f in "${FILES[@]}"; do
    hits=$(grep -nE '^(PUB|PRI)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$f" 2>/dev/null \
        | awk -F: '{ ln=$1; $1=""; sig=substr($0,2)
            # Keep only the parameter list, return list and locals.
            gsub(/^[^(]*\(/, "", sig)
            n = split(sig, parts, /[(),|:]/)
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                gsub(/\).*$/, "", parts[i])
                if (parts[i] ~ /^[A-Za-z]$/) { print ln": "parts[i]; }
            } }' | head -4)
    [[ -n "$hits" ]] && { fail "$f" "single-letter name(s): $(echo "$hits" | tr '\n' ' ')"; found=1; }
done
[[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"

# --- Rule 4.1: no '' doc comments on CON/DAT/VAR declaration lines --------------
#
# pnut-ts extracts '' comments into the interface document; on a declaration line
# they land in the wrong place. Permitted inside #IFDEF blocks per the guide.
echo ""
echo -e "${CYAN}Rule 4.1 — no '' doc comments on CON/DAT/VAR declaration lines${NC}"
found=0
for f in "${FILES[@]}"; do
    hits=$(grep -nE "^[[:space:]]*(CON|DAT|VAR)[[:space:]]+.*''" "$f" 2>/dev/null | head -3)
    [[ -n "$hits" ]] && { fail "$f" "$(echo "$hits" | cut -d: -f1 | tr '\n' ' ')"; found=1; }
done
[[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"

# --- Rule 3.2: PUB before PRI ---------------------------------------------------
echo ""
echo -e "${CYAN}Rule 3.2 — all PUB methods precede the first PRI${NC}"
found=0
for f in "${FILES[@]}"; do
    firstPri=$(grep -nE '^PRI[[:space:]]' "$f" 2>/dev/null | head -1 | cut -d: -f1)
    lastPub=$(grep -nE '^PUB[[:space:]]' "$f" 2>/dev/null | tail -1 | cut -d: -f1)
    [[ -z "$firstPri" || -z "$lastPub" ]] && continue
    if [[ "$lastPub" -gt "$firstPri" ]]; then
        fail "$f" "PUB at :$lastPub follows first PRI at :$firstPri"
        found=1
    fi
done
[[ $found -eq 0 ]] && echo -e "  ${GREEN}Ordering correct.${NC}"

# --- summary -------------------------------------------------------------------

echo ""
if [[ $fails -eq 0 && $reviews -eq 0 ]]; then
    echo -e "${GREEN}Conformant on every mechanical rule.${NC}"
elif [[ $fails -eq 0 ]]; then
    echo -e "${GREEN}No FAIL findings.${NC} ${YELLOW}${reviews} REVIEW item(s) — a judgement call, see notes above.${NC}"
else
    echo -e "${RED}${fails} FAIL finding(s)${NC}, ${YELLOW}${reviews} REVIEW item(s)${NC}."
fi
echo ""
echo "  Rules a script cannot judge stay a human read: naming quality (2.2, 2.3),"
echo "  consistent base names (2.1.3), same-name-same-description (2.5), CON block"
echo "  organization (3.5), and doc-comment content (Part 4). See"
echo "  DOCs/procedures/SPIN2-AUTHORING-GUIDE.md."
echo ""

[[ $fails -gt 0 ]] && exit 1
exit 0
