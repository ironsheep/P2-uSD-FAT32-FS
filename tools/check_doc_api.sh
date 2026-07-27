#!/usr/bin/env bash
#
# check_doc_api.sh — find documented method calls that the driver does not provide.
#
# Third of the documentation audits. The other two check *numbers*
# (check_doc_counts.sh) and *output strings* (check_doc_claims.sh). Neither looks at
# the API surface, and that gap shipped: TEST-CARD-SPECIFICATION.md documented
# sd.openFile(), sd.read(), sd.seek() and sd.closeFile() from January 2026 to July
# 2026 — four methods that have never existed in the handle-based driver. A reader
# who copied those snippets got code that does not compile.
#
# WHAT IT CHECKS: every qualified call `receiver.method(` appearing in a fenced
# ```spin2 block or an inline code span, in any user-facing Markdown file. The
# receiver is resolved to a source object through OBJ declarations harvested from
# BOTH the documents and src/, so `sd.readHandle(...)` is checked against
# micro_sd_fat32_fs's actual PUB set.
#
# OPT-OUT: a block that deliberately shows an API the driver does not have — a
# proposed design in a feasibility study, a template placeholder — is exempted by
# putting an HTML comment on the line before the fence:
#
#     <!-- api-audit: proposed -->
#     ```spin2
#
# It renders as nothing, and it must carry a reason word, so exempting a block is a
# visible act in the diff rather than a silent one. Use it for code that is not
# claiming to be callable. Never use it to quiet a stale example.
#
# WHAT IT DOES NOT CHECK, and why: unqualified calls (`openFile(...)` with no
# receiver). Distinguishing those from Spin2 built-ins and from methods the example
# defines itself needs a built-in table this script does not carry. Qualified calls
# are where the documented API surface actually lives, and they are checkable with
# zero guessing.
#
# Exit codes: 0 = clean, 1 = at least one unknown method. It gates. Run from tools/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Same user-facing set the other two audits use, discovered from git for the same
# reason: a hand-listed set goes stale exactly the way the documents do.
mapfile -t DOCS < <(
    git -C "$ROOT" ls-files --full-name '*.md' 2>/dev/null \
    | grep -vE '^(DOCs/Plans/|DOCs/Agent-Reports/|DOCs/Analysis/|DOCs/procedures/|\.claude/|diagnostic-tests/)' \
    | sort
)

if [[ ${#DOCS[@]} -eq 0 ]]; then
    echo -e "${RED}No user-facing Markdown discovered via git ls-files — aborting.${NC}"
    exit 0
fi

mapfile -t SRCS < <(git -C "$ROOT" ls-files --full-name 'src/*.spin2' 'src/**/*.spin2' 2>/dev/null | sort)

# ---- receiver -> object bindings -------------------------------------------
#
# Harvested from every OBJ declaration in src/ and in the documents. This project
# binds names consistently (`sd : "micro_sd_fat32_fs"` everywhere), so a receiver
# used in a document that declares no OBJ of its own still resolves correctly.
: > "$TMP/bind.txt"
{
    printf '%s\n' "${SRCS[@]}" | while read -r f; do [[ -f "$f" ]] && cat "$f"; done
    printf '%s\n' "${DOCS[@]}" | while read -r f; do [[ -f "$f" ]] && cat "$f"; done
} | awk '
    /^[[:space:]]*(OBJ|obj)([[:space:]]|$)/ { inobj = 1; next }
    /^[[:space:]]*(PUB|PRI|CON|DAT|VAR|pub|pri|con|dat|var)([[:space:]]|$)/ { inobj = 0 }
    /^[[:space:]]*```/ { inobj = 0 }
    inobj && match($0, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\[[^]]*\])?[[:space:]]*:[[:space:]]*"[^"]+"/) {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        recv = line; sub(/[[:space:]:[].*$/, "", recv)
        if (match(line, /"[^"]+"/)) {
            obj = substr(line, RSTART + 1, RLENGTH - 2)
            sub(/\.spin2$/, "", obj)
            print recv "\t" obj
        }
    }
' | sort -u > "$TMP/bind.txt"

# ---- PUB surface of each object --------------------------------------------
: > "$TMP/pubs.txt"
for f in "${SRCS[@]}"; do
    [[ -f "$f" ]] || continue
    obj="$(basename "$f" .spin2)"
    # Spin2 is case-INSENSITIVE (p2kbLanguageCaseSensitivity): MyMethod, mymethod
    # and MYMETHOD are one identifier. The driver declares PUB ERROR() in caps and
    # every caller writes sd.error(). Fold case so the audit matches the compiler.
    grep -oE '^PUB[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
        | awk -v o="$obj" '{ print o "\t" tolower($2) }' >> "$TMP/pubs.txt"
done
sort -u -o "$TMP/pubs.txt" "$TMP/pubs.txt"

if [[ ! -s "$TMP/pubs.txt" ]]; then
    echo -e "${RED}Could not build a PUB surface from src/ — aborting.${NC}"
    exit 0
fi

# ---- every qualified call in the documents ---------------------------------
#
# Fenced spin2 blocks and inline code spans both count: a reader copies either.
: > "$TMP/calls.txt"
for d in "${DOCS[@]}"; do
    [[ -f "$d" ]] || continue
    awk -v doc="$d" '
        /^[[:space:]]*<!--[[:space:]]*api-audit:[[:space:]]*[A-Za-z]/ { exempt = 1; next }
        /^[[:space:]]*```/ {
            if (inblk) { inblk = 0; exempt = 0; next }
            tag = $0; sub(/^[[:space:]]*```[[:space:]]*/, "", tag)
            inblk = (tolower(tag) == "spin2")
            if (exempt) { skipblk = 1; exempt = 0 } else skipblk = 0
            next
        }
        {
            if (inblk && skipblk) next
            line = $0
            if (!inblk) {
                # Outside a fence, only inline code spans are considered.
                keep = ""
                while (match(line, /`[^`]+`/)) {
                    keep = keep " " substr(line, RSTART + 1, RLENGTH - 2)
                    line = substr(line, RSTART + RLENGTH)
                }
                line = keep
            } else {
                sub(/'"'"'.*$/, "", line)          # strip trailing comment
            }
            while (match(line, /[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/)) {
                s = substr(line, RSTART, RLENGTH)
                sub(/[[:space:]]*\($/, "", s)
                split(s, p, ".")
                print doc "\t" FNR "\t" p[1] "\t" p[2]
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$d" >> "$TMP/calls.txt"
done

echo ""
echo -e "${CYAN}Documented API audit — $(wc -l < "$TMP/calls.txt" | tr -d ' ') qualified call(s) across ${#DOCS[@]} user-facing document(s)${NC}"
echo ""

fails=0
unresolved=0

while IFS=$'\t' read -r doc ln recv meth; do
    [[ -z "${recv:-}" ]] && continue
    obj="$(awk -F'\t' -v r="$recv" '$1 == r { print $2; exit }' "$TMP/bind.txt")"
    if [[ -z "$obj" ]]; then
        unresolved=$((unresolved + 1))
        continue
    fi
    # Only judge receivers bound to an object we actually have sources for.
    grep -qP "^\Q$obj\E\t" "$TMP/pubs.txt" || { unresolved=$((unresolved + 1)); continue; }
    if ! grep -qxF "$obj	${meth,,}" "$TMP/pubs.txt"; then
        printf "  ${RED}FAIL${NC}    %-56s %s\n" "$doc:$ln" "$recv.$meth() — $obj has no such PUB"
        fails=$((fails + 1))
    fi
done < <(sort -u "$TMP/calls.txt")

if [[ $fails -eq 0 ]]; then
    echo -e "  ${GREEN}Every documented method call exists in the object it is called on.${NC}"
fi

echo ""
if [[ $unresolved -gt 0 ]]; then
    echo -e "  ${YELLOW}${unresolved} call(s) skipped${NC} — receiver not bound to an object under src/ (Spin2 built-ins, structure accessors, third-party objects)."
    echo ""
fi

[[ $fails -gt 0 ]] && exit 1
exit 0
