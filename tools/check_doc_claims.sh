#!/usr/bin/env bash
#
# check_doc_claims.sh — find documented output that the code does not produce.
#
# Companion to check_doc_counts.sh. That one checks *numbers*; this one checks
# *strings* — the sample transcripts, banners, and status lines that documents
# quote as tool output.
#
# Why this exists: the project has 471 regression tests and every one asserts on
# behavior. None compares a description to the behavior it describes. So a stale
# sample transcript has exactly one detection mechanism — someone reading it — and
# if that reading only happens at the release gate, findings arrive under time
# pressure. This script makes the comparison mechanical.
#
# It found real defects on its first run: `FILESYSTEM STATUS: CLEAN` had been
# documented since the audit/fsck engines were consolidated and the tools have
# never printed it; the shipped `.release/src/UTILS/README.md` carried a third copy
# of transcripts that had already been corrected elsewhere.
#
# Two checks:
#
#   1. ORPHANED OUTPUT — a line inside a fenced block that looks like tool output,
#      whose label does not appear in any source debug/fifo string. Either the docs
#      are stale or the tool stopped printing it.
#
#   2. DUPLICATED BLOCKS — the same sample transcript living in more than one
#      document. Duplication is the mechanism of drift: v1.6.1 fixed one of three
#      copies and shipped the other two. Prefer one canonical block that the others
#      link to.
#
# No hardware. Never edits anything. Advisory: always exits 0 so it can sit in a
# release checklist without failing it. Run from tools/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Scope: EVERY user-facing Markdown file versioned in the repo. Project policy
# (Stephen, 2026-07-26): all of them are audited with every release and current with
# every release — patch releases included.
#
# Discovered from git rather than hand-listed, because a hand-listed set goes stale
# exactly the way the documents do. Only internal working areas are excluded: sprint
# plans, agent reports, analyses, process procedures, and the skill overlays are our
# own workspace, not something a user reads.
mapfile -t DOCS < <(
    git -C "$ROOT" ls-files --full-name '*.md' 2>/dev/null \
    | grep -vE '^(DOCs/Plans/|DOCs/Agent-Reports/|DOCs/Analysis/|DOCs/procedures/|\.claude/|diagnostic-tests/)' \
    | sort
)

if [[ ${#DOCS[@]} -eq 0 ]]; then
    echo -e "${RED}No user-facing Markdown discovered via git ls-files — aborting.${NC}"
    exit 0
fi

# ---- corpus of every string the code can actually print --------------------

find src -name '*.spin2' -print0 2>/dev/null \
    | xargs -0 grep -ho '"[^"]*"' 2>/dev/null \
    | tr -d '"' > "$TMP/corpus.txt"

if [[ ! -s "$TMP/corpus.txt" ]]; then
    echo -e "${RED}Could not build a source-string corpus from src/ — aborting.${NC}"
    exit 0
fi

# ---- check 1: orphaned output lines ---------------------------------------

# A fenced line is "output-looking" if it carries one of these shapes. Anchored on
# punctuation the tools actually emit — a bare word like "Repairs" also appears in
# prose tables and ASCII diagrams, and a check that cries wolf gets ignored.
OUTPUT_SHAPE='\[(OK|PASS|FAIL|USED|INFO)\]|STATUS:|^ *=== .* ===|^ *Pass [0-9]+(/[0-9]+)?:|Errors:|Repairs( needed)?:|Warnings:|Structural checks:|Free clusters:|Tests:|Passed:|Failed:'

# Lines that are plainly not tool output, even inside a fence: ASCII flow diagrams
# and code examples. Checked before OUTPUT_SHAPE so they never reach the corpus
# lookup.
NOT_OUTPUT='^[[:space:]]*[|+\\/]|^[[:space:]]*[A-Z_]+[[:space:]]*[:=]=?[[:space:]]*\('

orphans=0
echo ""
echo -e "${CYAN}1. Documented output not found in source${NC}"
echo ""

for doc in "${DOCS[@]}"; do
    [[ -f "$doc" ]] || continue
    # awk prints "lineno:text" for lines inside ``` fences only.
    awk '/^```/{f=!f; next} f{print FNR":"$0}' "$doc" 2>/dev/null \
    | grep -E ":.*($OUTPUT_SHAPE)" \
    | while IFS=: read -r ln text; do
        # Diagrams and code examples live in fences too; they are not claims.
        printf '%s' "$text" | grep -qE "$NOT_OUTPUT" && continue
        # Reduce the line to its stable label: drop leading blanks, then cut at
        # the first digit, '$', or run of dots/underscores — those carry values
        # that legitimately vary between runs.
        # Strip result prefixes that are synthesized at runtime rather than stored
        # in the string: auditRunTest() prints "[PASS] " + the test name, so the
        # corpus holds the name alone. Leaving the prefix on guarantees a miss.
        label=$(printf '%s' "$text" \
            | sed -E 's/^[[:space:]]+//; s/^\[(OK|PASS|FAIL|USED|INFO)\][[:space:]]*//' \
            | sed -E 's/[0-9].*$//; s/\$.*$//; s/\.\.\..*$//; s/\[[^]]*$//; s/[[:space:]]+$//')
        # Too short to be distinctive — skip rather than guess.
        [[ ${#label} -lt 8 ]] && continue
        if ! grep -qF "$label" "$TMP/corpus.txt"; then
            printf "  ${RED}ORPHAN${NC}  %s:%s\n          %s\n" "$doc" "$ln" "$label"
            echo x >> "$TMP/orphan.count"
        fi
      done
done

[[ -f "$TMP/orphan.count" ]] && orphans=$(wc -l < "$TMP/orphan.count" | tr -d ' ')
if [[ "$orphans" == "0" ]]; then
    echo -e "  ${GREEN}None — every documented output label exists in source.${NC}"
fi

# ---- check 2: duplicated sample blocks ------------------------------------

echo ""
echo -e "${CYAN}2. Sample blocks duplicated across documents${NC}"
echo ""

# Only compare blocks that actually look like tool output — code examples and
# directory trees legitimately repeat across documents and are not drift risks.
blockno=0
for doc in "${DOCS[@]}"; do
    [[ -f "$doc" ]] || continue
    n=$(awk '/^```/{c++} END{print int(c/2)}' "$doc" 2>/dev/null)
    [[ -z "$n" || "$n" -eq 0 ]] && continue
    for ((i = 1; i <= n; i++)); do
        blockno=$((blockno + 1))
        body="$TMP/b$blockno"
        awk -v want="$i" '
            /^```/ { seen++; infence = (seen % 2 == 1); if (infence) cur++; next }
            infence && cur == want { print }
        ' "$doc" > "$body" 2>/dev/null
        # Must contain at least two output-shaped lines to count as a transcript.
        hits=$(grep -cE "$OUTPUT_SHAPE" "$body" 2>/dev/null || true)
        [[ "${hits:-0}" -lt 2 ]] && continue
        start=$(awk -v want="$i" '
            /^```/ { seen++; infence = (seen % 2 == 1); if (infence) { cur++; if (cur == want) { print FNR + 1; exit } } }
        ' "$doc")
        # Normalize away run-specific values, then hash the whole block.
        h=$(sed -E 's/[0-9]+/#/g; s/[[:space:]]+/ /g; s/^ //; s/ $//' "$body" \
            | md5sum | cut -d' ' -f1)
        printf '%s\t%s:%s\n' "$h" "$doc" "$start" >> "$TMP/blocks.txt"
    done
done
[[ -f "$TMP/blocks.txt" ]] || : > "$TMP/blocks.txt"

dupes=0
while read -r key; do
    locs=$(awk -F'\t' -v k="$key" '$1==k {print $2}' "$TMP/blocks.txt" | tr '\n' ' ')
    printf "  ${YELLOW}DUPLICATE${NC} transcript in: %s\n" "$locs"
    echo x >> "$TMP/dupe.count"
done < <(cut -f1 "$TMP/blocks.txt" | sort | uniq -d)

[[ -f "$TMP/dupe.count" ]] && dupes=$(wc -l < "$TMP/dupe.count" | tr -d ' ')
if [[ "$dupes" == "0" ]]; then
    echo -e "  ${GREEN}None — no sample block is maintained in two places.${NC}"
fi

# ---- summary --------------------------------------------------------------

echo ""
if [[ "$orphans" == "0" && "$dupes" == "0" ]]; then
    echo -e "${GREEN}Documented output matches source, and nothing is duplicated.${NC}"
else
    echo -e "${YELLOW}${orphans} orphaned output line(s), ${dupes} duplicated block(s).${NC}"
    echo ""
    echo "  An ORPHAN means the docs claim output the code does not produce. Re-capture"
    echo "  the transcript from a real log, and stamp it with the card and date."
    echo ""
    echo "  A DUPLICATE means one transcript is maintained in several files, which is"
    echo "  how they drift apart. Keep one canonical copy and link to it."
fi
echo ""

exit 0
