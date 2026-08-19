#!/usr/bin/env bash
#
# check_style.sh — audit .spin2 sources against the central Spin2 authoring guide
# (~/.claude/skills-docs/guides/spin2-authoring-guide.md; this script is that
# guide's named reference implementation).
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
# This script is TIER 1 of a four-tier model (decided 2026-08-13; full model and the
# rule-by-rule assignment in DOCs/procedures/RELEASE-CHECKLIST.md section 2):
#
#   T0  compiler already enforces it        (e.g. 1.6 local/DAT name collision)
#   T1  script-checkable, gates             <- THIS SCRIPT
#   T2  agent-auditable: semantic judgement, but repeatable and citable
#   T3  genuinely Stephen's: architectural intent (5.8, 5.9)
#
# What this script does NOT check is mostly T2, NOT "a human read". That distinction
# was the old model's error -- "a shell script cannot check this" is not "a human
# must". Roughly 24 of the guide's 53 rules are T2: naming correspondence (does the
# name describe what is stored / returned), doc-comment SYNC (does it describe what
# the code does today -- not "is it good"), CON grouping, magic-number judgement.
#
# Exit codes: 0 = no FAIL findings (REVIEW items may still be listed), 1 = at least
# one FAIL. Unlike the doc checks, this one CAN fail a release gate.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

# Scope: EVERY tracked .spin2 in the tree, wherever it lives (Stephen, 2026-08-13).
#
# It was src/-only until then, on the rationale that diagnostic-tests/ holds throwaway
# probes that never ship, and holding them to the shipped-code bar would discourage
# writing them. That rationale did not survive contact: an ungated tree accumulates
# violations (10 of 41 diagnostic-tests files carry Rule 1.1 non-ASCII), and a new file
# modelled on an ungated one inherits them -- which is exactly how
# SD_buffer_alignment_sweep.spin2 was written with two Rule 2.1 violations copied from
# SD_tx_phase_shmoo.spin2. Style is a property of the language, not of the audience.
#
# GRACE PERIOD, ends at the next release's checklist section 2. Findings OUTSIDE src/
# report as DEBT and do NOT gate, so widening the scope cannot retroactively fail the
# v1.7.0 tree that was already certified green under the old scope. Run with --strict
# to make them gate. RELEASE-CHECKLIST section 2 carries the instruction to run
# --strict next cycle, clear the debt, and then delete this grace path entirely.
STRICT=0
case "${1:-}" in
    "")         ;;
    --strict)   STRICT=1 ;;
    -h|--help)
        echo "Usage: $0 [--strict]"
        echo ""
        echo "  Tier 1 style audit over every tracked .spin2 file."
        echo ""
        echo "  (no flag)  Findings outside src/ report as DEBT and do not gate."
        echo "             Grace period; ends at the next release (checklist section 2)."
        echo "  --strict   Every finding gates, wherever the file lives."
        echo ""
        echo "  Exit: 0 = no FAIL findings, 1 = at least one FAIL."
        exit 0 ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--strict]   (try --help)" >&2
        exit 2 ;;
esac

mapfile -t FILES < <(git -C "$ROOT" ls-files --full-name '*.spin2' 2>/dev/null | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo -e "${RED}No tracked .spin2 files found -- aborting.${NC}"
    exit 0
fi

gated=0
for f in "${FILES[@]}"; do [[ "$f" == src/* ]] && gated=$((gated + 1)); done

fails=0
reviews=0
debt=0

# A finding is DEBT (non-gating) only when the grace period is in force AND it names a
# .spin2 outside src/. Doc-fragment findings carry .md paths and are unaffected -- they
# gate exactly as before.
fail() {
    if [[ $STRICT -eq 0 && "$1" == *.spin2 && "$1" != src/* ]]; then
        printf "  ${YELLOW}DEBT${NC}    %-52s %s\n" "$1" "$2"; debt=$((debt + 1)); return
    fi
    printf "  ${RED}FAIL${NC}    %-52s %s\n" "$1" "$2"; fails=$((fails + 1))
}
review() { printf "  ${YELLOW}REVIEW${NC}  %-52s %s\n" "$1" "$2"; reviews=$((reviews + 1)); }

echo ""
if [[ $STRICT -eq 1 ]]; then
    echo -e "${CYAN}Spin2 style audit — ${#FILES[@]} tracked .spin2 files (STRICT: all gate)${NC}"
else
    echo -e "${CYAN}Spin2 style audit — ${#FILES[@]} tracked .spin2 files (${gated} under src/ gate; the rest report as DEBT)${NC}"
fi
echo ""

# --- Rule 1.1: ASCII only -------------------------------------------------------
#
# The guide forbids non-ASCII in code, strings and signatures, and explicitly
# PERMITS Unicode box-drawing (U+2500-U+257F) and block elements (U+2580-U+259F)
# inside comments for diagrams. A blanket non-ASCII grep therefore over-reports
# massively -- this project's sources carry ~4000 box-drawing characters in comment
# diagrams, all of them legal.
#
# The guide (rule 1.1, "The general rule, stated unambiguously" -- Stephen,
# 2026-07-27) makes this absolute: the box-drawing (U+2500-U+257F) and block-element
# (U+2580-U+259F) ranges are the ONLY non-ASCII permitted anywhere in a .spin2 file.
# Every other codepoint above 127 is a FAIL wherever it appears, COMMENTS INCLUDED.
#
# The decisive reason is the VSCode Spin2 extension, which flags these characters as
# illegal in comments too. A conformant file must not light up the supported editor
# with errors -- that teaches authors to ignore its diagnostics.
#
# The box-drawing exception is NOT negotiable and is NOT an aesthetic preference:
# those characters ship with the original Propeller Tool on Windows and a large part
# of the user-created P1/P2 code base uses them. We actively preserve them so our
# source reads as ordinary Propeller source to the community. Do not "simplify" this
# check by dropping the two ranges.
#
# This check used to emit REVIEW items for comment prose, because the guide's
# forbidden-character table was scoped to "code, strings, and method signatures" and
# said nothing about comments. That silence is now resolved in the guide, so there is
# nothing left for the script to hedge about.
echo -e "${CYAN}Rule 1.1 — ASCII only (box-drawing excepted)${NC}"
for f in "${FILES[@]}"; do
    # Every codepoint above 127 anywhere in the file, except the two diagram ranges.
    # Reported with the offending character named, so the fix is obvious.
    hits=$(perl -CSD -ne '
        while (/([^\x00-\x7F])/g) {
            my $c = $1; my $o = ord($c);
            next if ($o >= 0x2500 && $o <= 0x257F) || ($o >= 0x2580 && $o <= 0x259F);
            printf("%d:U+%04X", $., $o); print " $c\n";
        }' "$f" 2>/dev/null | head -3)
    [[ -n "$hits" ]] && fail "$f" "illegal non-ASCII: $(echo "$hits" | tr '\n' ' ')"
done
[[ $fails -eq 0 && $debt -eq 0 ]] && echo -e "  ${GREEN}ASCII throughout, apart from box-drawing diagrams in comments.${NC}"

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

# ================================================================================
# PASS 2 — Spin2 example code inside user-facing Markdown
# ================================================================================
#
# Project policy (Stephen, 2026-07-26): example code in the documents conforms to
# the same guide as the shipped source. A reader copies what we print; an example
# that violates the guide teaches the violation.
#
# Scope is the same user-facing Markdown set check_doc_claims.sh audits, discovered
# from git for the same reason: a hand-listed set goes stale exactly the way the
# documents do.
#
# Only rules that are meaningful for a FRAGMENT are applied. Rule 3.2 (PUB before
# PRI) is deliberately NOT applied: an excerpt legitimately shows one method, and
# the ordering of a file cannot be judged from a slice of it.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mapfile -t DOCS < <(
    git -C "$ROOT" ls-files --full-name '*.md' 2>/dev/null \
    | grep -vE '^(DOCs/Plans/|DOCs/Agent-Reports/|DOCs/Analysis/|DOCs/procedures/|\.claude/|diagnostic-tests/)' \
    | sort
)

# Flatten every fenced spin2 block to "doc:line:code", keeping the line number the
# reader would see in the document so a finding is directly actionable. A block id
# is carried too, so rule 2.4 can reason about one fragment at a time.
: > "$TMP/frag.txt"
blocks=0
for d in "${DOCS[@]}"; do
    [[ -f "$d" ]] || continue
    n=$(awk -v doc="$d" '
        /^[[:space:]]*```/ {
            if (inblk) { inblk = 0; next }
            tag = $0; sub(/^[[:space:]]*```[[:space:]]*/, "", tag)
            if (tolower(tag) == "spin2") { inblk = 1; blk++ ; emitted++ }
            next
        }
        inblk { printf "%s:%d:%d:%s\n", doc, FNR, blk, $0 }
        END { print emitted+0 > "/dev/stderr" }
    ' "$d" 2>>"$TMP/counts.txt" >> "$TMP/frag.txt")
done
blocks=$(awk '{ s += $1 } END { print s+0 }' "$TMP/counts.txt" 2>/dev/null)

echo ""
echo -e "${CYAN}Spin2 examples in Markdown — ${blocks:-0} fenced block(s) across ${#DOCS[@]} user-facing document(s)${NC}"

if [[ ! -s "$TMP/frag.txt" ]]; then
    echo -e "  ${GREEN}No fenced spin2 examples to audit.${NC}"
else
    # --- Rule 1.1: ASCII only (code and string literals) ------------------------
    echo ""
    echo -e "${CYAN}Rule 1.1 — ASCII only${NC}"
    found=0
    hits=$(LC_ALL=C awk -F: '
        { doc = $1; ln = $2; code = $0
          sub(/^[^:]*:[0-9]+:[0-9]+:/, "", code)
          if (code ~ /^[[:space:]]*'"'"'/) next            # comment line
          line = code
          while (match(line, /"[^"]*"/)) {
              s = substr(line, RSTART, RLENGTH)
              if (s ~ /[^\x00-\x7F]/) { print doc":"ln": "s; break }
              line = substr(line, RSTART + RLENGTH)
          } }
    ' "$TMP/frag.txt" 2>/dev/null)
    if [[ -n "$hits" ]]; then
        while IFS= read -r h; do fail "${h%%:*}" "non-ASCII in an example string literal: ${h#*:}"; done <<< "$hits"
        found=1
    fi
    [[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"

    # --- Rule 1.8: @"" is invalid ----------------------------------------------
    echo ""
    echo -e "${CYAN}Rule 1.8 — no empty string literal @\"\"${NC}"
    found=0
    hits=$(grep -F '@""' "$TMP/frag.txt" 2>/dev/null | awk -F: '{ print $1":"$2 }')
    if [[ -n "$hits" ]]; then
        while IFS= read -r h; do fail "${h%%:*}" "@\"\" at :${h##*:}"; done <<< "$hits"
        found=1
    fi
    [[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"

    # --- Rule 2.1: no single-letter names in a shown signature ------------------
    echo ""
    echo -e "${CYAN}Rule 2.1 — no single-letter variable names in signatures${NC}"
    found=0
    hits=$(awk -F: '
        { doc = $1; ln = $2; sig = $0
          sub(/^[^:]*:[0-9]+:[0-9]+:/, "", sig)
          if (sig !~ /^(PUB|PRI)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/) next
          gsub(/^[^(]*\(/, "", sig)
          n = split(sig, parts, /[(),|:]/)
          for (i = 1; i <= n; i++) {
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
              gsub(/\).*$/, "", parts[i])
              if (parts[i] ~ /^[A-Za-z]$/) print doc":"ln": "parts[i]
          } }
    ' "$TMP/frag.txt" 2>/dev/null)
    if [[ -n "$hits" ]]; then
        while IFS= read -r h; do fail "${h%%:*}" "single-letter name in an example signature at :$(echo "$h" | cut -d: -f2) — $(echo "$h" | cut -d: -f3-)"; done <<< "$hits"
        found=1
    fi
    [[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"

    # --- Rule 2.4: object constants referenced through the object ---------------
    #
    # Flagged only when the SAME fragment both declares an object and defines a CON
    # name that object already defines. That pairing is the actual defect the rule
    # describes — a second source of truth in the reader's file. A fragment that
    # merely defines a constant, with no object in view, is not judged: the excerpt
    # does not show enough to know.
    echo ""
    echo -e "${CYAN}Rule 2.4 — no local copy of an object's constant${NC}"
    found=0
    hits=$(awk -F: -v root="$ROOT" '
        function loadconsts(objname,   path, line, nm, cmd) {
            if (objname in loaded) return
            loaded[objname] = 1
            cmd = "git -C \"" root "\" ls-files --full-name \"src/*/" objname ".spin2\" \"src/" objname ".spin2\" 2>/dev/null"
            path = ""
            while ((cmd | getline line) > 0) { if (path == "") path = line }
            close(cmd)
            if (path == "") return
            inCon = 0
            while ((getline line < (root "/" path)) > 0) {
                if (line ~ /^(CON|con)([[:space:]]|$)/) { inCon = 1; continue }
                if (line ~ /^(PUB|PRI|DAT|VAR|OBJ|pub|pri|dat|var|obj)([[:space:]]|$)/) { inCon = 0; continue }
                if (!inCon) continue
                # A constant the object DOCUMENTS as user-overridable is not a
                # second source of truth -- redefining it in the consuming CON
                # block IS the configuration mechanism the object provides, and
                # showing that in a document is correct. MAX_OPEN_FILES is the
                # live case.
                if (tolower(line) ~ /user-overridable/) continue
                if (match(line, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)) {
                    nm = substr(line, RSTART, RLENGTH)
                    gsub(/[[:space:]]|=/, "", nm)
                    consts[objname, nm] = 1
                }
            }
            close(root "/" path)
        }
        { doc = $1; ln = $2; blk = $3; code = $0
          sub(/^[^:]*:[0-9]+:[0-9]+:/, "", code)
          sub(/'"'"'.*$/, "", code)
          key = doc SUBSEP blk

          if (code ~ /^(OBJ|obj)([[:space:]]|$)/) { sect[key] = "OBJ"; next }
          if (code ~ /^(CON|con)([[:space:]]|$)/) { sect[key] = "CON"; next }
          if (code ~ /^(PUB|PRI|DAT|VAR|pub|pri|dat|var)([[:space:]]|$)/) { sect[key] = "OTHER"; next }

          if (sect[key] == "OBJ" && match(code, /"[^"]+"/)) {
              o = substr(code, RSTART + 1, RLENGTH - 2)
              sub(/\.spin2$/, "", o)
              objs[key, ++nobj[key]] = o
              loadconsts(o)
              next
          }
          if (sect[key] == "CON" && match(code, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)) {
              nm = substr(code, RSTART, RLENGTH); gsub(/[[:space:]]|=/, "", nm)
              cname[key, ++ncon[key]] = nm; cline[key, ncon[key]] = ln
          } }
        END {
            for (k in nobj)
                for (i = 1; i <= nobj[k]; i++)
                    for (j = 1; j <= ncon[k]; j++)
                        if ((objs[k, i], cname[k, j]) in consts) {
                            split(k, kk, SUBSEP)
                            print kk[1] ":" cline[k, j] ": " cname[k, j] " duplicates " objs[k, i] "." cname[k, j]
                        }
        }
    ' "$TMP/frag.txt" 2>/dev/null | sort -u)
    if [[ -n "$hits" ]]; then
        while IFS= read -r h; do fail "${h%%:*}" "at :$(echo "$h" | cut -d: -f2) —$(echo "$h" | cut -d: -f3-)"; done <<< "$hits"
        found=1
    fi
    [[ $found -eq 0 ]] && echo -e "  ${GREEN}None.${NC}"
fi

# --- summary -------------------------------------------------------------------

echo ""
if [[ $debt -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}${debt} DEBT finding(s) outside src/${NC} — non-gating this cycle."
    echo "  Scope widened 2026-08-13; these predate the widening or were written under it."
    echo "  At the next release's checklist section 2: run ./check_style.sh --strict,"
    echo "  clear every finding, then delete the grace path from this script."
fi

if [[ $fails -eq 0 && $reviews -eq 0 && $debt -eq 0 ]]; then
    echo -e "${GREEN}Conformant on every mechanical rule.${NC}"
elif [[ $fails -eq 0 && $reviews -eq 0 ]]; then
    echo -e "${GREEN}src/ conformant on every mechanical rule.${NC} ${YELLOW}${debt} finding(s) outside src/ carried as debt.${NC}"
elif [[ $fails -eq 0 ]]; then
    echo -e "${GREEN}No FAIL findings.${NC} ${YELLOW}${reviews} REVIEW item(s) — a judgement call, see notes above.${NC}"
else
    echo -e "${RED}${fails} FAIL finding(s)${NC}, ${YELLOW}${reviews} REVIEW item(s)${NC}."
fi
echo ""
echo "  This is TIER 1 only. What it cannot check is mostly TIER 2 -- agent-auditable,"
echo "  not \"a human read\": naming correspondence (2.2, 2.3), consistent base names"
echo "  (2.1.3), same-name-same-description (2.5), CON grouping (3.5), doc-comment SYNC"
echo "  (Part 4), magic-number judgement (5.7). Tier model and rule assignment:"
echo "  DOCs/procedures/RELEASE-CHECKLIST.md section 2. Rules: the central Spin2"
echo "  authoring guide (~/.claude/skills-docs/guides/spin2-authoring-guide.md)."
echo ""

[[ $fails -gt 0 ]] && exit 1
exit 0
