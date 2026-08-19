#!/usr/bin/env bash
#
# check_card_labels.sh — verify every card record's label reference resolves to the
# label master, and that the master carries nothing orphaned or duplicated.
#
# WHY THIS EXISTS. Label text is read under a microscope and hand-entered: it is the
# most expensive data in the catalog to produce and the easiest to corrupt by
# copying. It used to live in four places (each card record, CARD-REFERENCE.md, and
# two columns of CARD-CATALOG.md), and an audit found exactly what that produces --
# copies that had diverged, some carrying detail the others had lost.
#
# It now lives once, in DOCs/cards/CARD-LABELS.md, and everything else refers to it
# by ID. That alone would only lower the odds of drift. This script is what removes
# the class: "did the label propagate correctly" stops being a reading task and
# becomes a mechanical one.
#
# Checks:
#   1. Every label ID referenced by a card record exists in the master
#   2. Every master entry is referenced by at least one card record
#   3. No two master entries carry identical printed text (a duplicate-entry smell)
#   4. Label IDs in the master are unique
#   5. No card record has re-acquired its own copy of the printed text
#   6. Every card record declares a Disposition from the allowed set -- the field
#      that says whether a card can still be re-measured, and therefore whether it
#      may carry a performance row
#   7. Every master transcription still appears VERBATIM in CARD-CATALOG.md and
#      CARD-REFERENCE.md -- those two keep the text because a summary table has to
#      be scannable by a human, so they are treated as CACHES of the master rather
#      than as sources. A cached copy is fine; an unchecked copy is the problem.
#
# It gates: a broken reference means a document is pointing at a label that does not
# exist, and a card whose label cannot be resolved is a card we cannot identify.
#
# Deliberately bash 3.2 compatible -- macOS ships 3.2 and this runs at the bench.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

MASTER="DOCs/cards/CARD-LABELS.md"
fail=0

note_fail() { printf "  ${RED}FAIL${NC}   %s\n" "$1"; fail=$((fail + 1)); }
note_warn() { printf "  ${YELLOW}WARN${NC}   %s\n" "$1"; }

if [[ ! -f "$MASTER" ]]; then
    echo "Label master not found: $MASTER" >&2
    exit 1
fi

echo ""
echo -e "${CYAN}Card labels vs the label master${NC}"
echo ""

# ---- the master's IDs ------------------------------------------------------
MASTER_IDS=$(grep -E '^### [a-z0-9-]+$' "$MASTER" | sed 's/^### //' | sort)
N_MASTER=$(printf '%s\n' "$MASTER_IDS" | grep -c . )

# 4. unique IDs in the master
DUP_IDS=$(printf '%s\n' "$MASTER_IDS" | uniq -d)
if [[ -n "$DUP_IDS" ]]; then
    for d in $DUP_IDS; do note_fail "master defines label ID '$d' more than once"; done
fi

# 3. identical printed text under two IDs
DUP_TEXT=$(grep -E '^- \*\*Printed:\*\* ' "$MASTER" \
    | sed 's/^- \*\*Printed:\*\* //' \
    | grep -v '^NOT TRANSCRIBED$' \
    | sort | uniq -d)
if [[ -n "$DUP_TEXT" ]]; then
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        note_fail "two master entries carry identical printed text: \"$t\""
    done <<< "$DUP_TEXT"
fi

# ---- what the card records reference ---------------------------------------
REFERENCED=""
N_RECORDS=0
for f in DOCs/cards/*.md; do
    case "$(basename "$f")" in
        CARD-CATALOG.md|CARD-REFERENCE.md|CATALOG-PROCEDURE.md|CARD-LABELS.md|README.md) continue ;;
    esac
    N_RECORDS=$((N_RECORDS + 1))

    line=$(grep -m1 '^\*\*Label:\*\*' "$f")
    if [[ -z "$line" ]]; then
        note_fail "$(basename "$f") has no **Label:** line"
        continue
    fi

    id=$(printf '%s' "$line" | sed -n 's/.*\[`\([a-z0-9-]*\)`\].*/\1/p')
    if [[ -z "$id" ]]; then
        # 5. a record that carries text instead of a reference has re-acquired a copy
        note_fail "$(basename "$f") **Label:** is not a master reference -- it carries its own text: ${line#\*\*Label:\*\* }"
        continue
    fi

    # 1. the reference resolves
    if ! printf '%s\n' "$MASTER_IDS" | grep -qx "$id"; then
        note_fail "$(basename "$f") references label '$id', which the master does not define"
        continue
    fi
    REFERENCED="$REFERENCED
$id"
done

# 2. nothing in the master is orphaned
ORPHANS=$(comm -23 <(printf '%s\n' "$MASTER_IDS") <(printf '%s\n' "$REFERENCED" | grep -v '^$' | sort -u))
if [[ -n "$ORPHANS" ]]; then
    for o in $ORPHANS; do note_fail "master defines label '$o', which no card record references"; done
fi

# ---- 6. every record declares a disposition --------------------------------
#
# WHY THIS IS CHECKED. The catalog's performance tables are PRISTINE: one banner
# naming the driver version, no per-row provenance, no exception table. That
# format is only honest because a full re-sweep is one afternoon -- which is only
# true if every card carrying a performance row is still available to re-measure.
#
# `retained` is a COMMITMENT, not an observation: the card belongs to this project
# permanently, and dying is the only way out. A card that was measured once and
# then went into service elsewhere is NOT retained, must not carry a performance
# row, and normally should not have a card record at all -- its numbers belong in
# the experiment record that produced them.
#
# Without this field, availability lived in prose scattered across three
# documents, and reading it that way is how the working 8 GB Kingston came to be
# annotated with the death of a different, uncatalogued 2 GB Kingston.
VALID_DISPOSITIONS="retained dead deployed not-in-possession not-located"
for f in DOCs/cards/*.md; do
    case "$(basename "$f")" in
        CARD-CATALOG.md|CARD-REFERENCE.md|CATALOG-PROCEDURE.md|CARD-LABELS.md|README.md) continue ;;
    esac
    dline=$(grep -m1 '^\*\*Disposition:\*\*' "$f")
    if [[ -z "$dline" ]]; then
        note_fail "$(basename "$f") has no **Disposition:** line -- is this card still available to re-measure?"
        continue
    fi
    d=$(printf '%s' "$dline" | sed -n 's/^\*\*Disposition:\*\* *`\([a-z-]*\)`.*/\1/p')
    if ! printf '%s' "$VALID_DISPOSITIONS" | tr ' ' '\n' | grep -qx "$d"; then
        note_fail "$(basename "$f") declares disposition '$d', which is not one of: $VALID_DISPOSITIONS"
        continue
    fi
    if [[ "$d" != "retained" ]]; then
        note_warn "$(basename "$f") is '$d' -- it cannot be re-measured, so it must carry NO performance row"
    fi
done

# ---- 7. the two reader-facing caches still agree with the master -----------
#
# These files keep the label text rather than an ID, because their whole job is to
# be read at a glance. What makes that safe is this check: a single changed
# character in either copy, or an edit to the master that is not carried across,
# fails here. That is the difference between a cache and a second source.
for cache in DOCs/cards/CARD-CATALOG.md DOCs/cards/CARD-REFERENCE.md; do
    while IFS= read -r entry; do
        id=${entry%%$'\t'*}
        txt=${entry#*$'\t'}
        [[ "$txt" == "NOT TRANSCRIBED" ]] && continue
        if ! grep -qF -- "$txt" "$cache"; then
            note_fail "$(basename "$cache") no longer carries the transcription for '$id' verbatim -- the master says: \"$txt\""
        fi
    done < <(awk '/^### /{id=$2} /^- \*\*Printed:\*\* /{sub(/^- \*\*Printed:\*\* /,""); print id "\t" $0}' "$MASTER")
done

# ---- transcriptions still owed ---------------------------------------------
UNTRANSCRIBED=$(grep -B2 '^- \*\*Printed:\*\* NOT TRANSCRIBED$' "$MASTER" | grep -E '^### ' | sed 's/^### //')
if [[ -n "$UNTRANSCRIBED" ]]; then
    for u in $UNTRANSCRIBED; do note_warn "label '$u' has no transcription yet (see 'Entries needing a microscope')"; done
fi

echo ""
printf "  %d card record(s), %d label(s) in the master\n" "$N_RECORDS" "$N_MASTER"
echo ""

if [[ $fail -eq 0 ]]; then
    echo -e "${GREEN}Every label reference resolves, and the master carries nothing orphaned or duplicated.${NC}"
    echo ""
    exit 0
fi

echo -e "${RED}${fail} label finding(s).${NC}"
echo ""
exit 1
