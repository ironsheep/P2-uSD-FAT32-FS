#!/usr/bin/env bash
#
# check_error_handling.sh — find places where a fallible call's status is thrown away.
#
# Fifth of the audit scripts. The other four look at documentation — numbers
# (check_doc_counts.sh), output strings (check_doc_claims.sh), the API surface
# (check_doc_api.sh) and source style (check_style.sh). None of them looks at whether
# the driver notices its own failures, and that gap is the cross-cutting root cause
# behind the July 2026 error-reporting audit
# (DOCs/Analysis/ERROR-REPORTING-AUDIT-2026-07-31.md).
#
# THE PATTERN THIS EXISTS TO CATCH. `writeSector()`, `readSector()`,
# `allocateCluster()` and `searchDirectory()` all return a status a call site may
# silently drop, and Spin2 issues no warning for an unused return value. Four of the
# five Tier-1 findings in that audit are the same mistake made in four places:
#
#     writeSector(fat_sec + result >> 7, BUF_FAT)      ' FAT write — status discarded
#
# The card rejects the write, the in-memory buffer says the cluster is allocated, the
# card says it is free, and the next allocation hands the same cluster to a second
# file. Two successful-looking writes, one cross-linked FAT. Nothing in the toolchain
# says a word. Hence a grep-able convention, so the class is checkable instead of
# re-auditable.
#
# THE FOUR RULES
#
#   1. DISCARDED STATUS — a call to one of the four functions written as a bare
#      statement (the call is the whole line) discards its result. Consume it, or
#      declare the omission deliberate with a trailing comment of exactly this form:
#
#          writeSector(n_sec, BUF_DIR)   ' status intentionally ignored: <reason>
#
#      The reason is mandatory. An exemption you have to justify in the diff is a
#      different act from an omission nobody noticed, which is the whole point.
#
#   2. UNCHECKED allocateCluster() RESULT — `allocateCluster()` returns E_DISK_FULL
#      (-60) or E_IO_ERROR (-7) on failure. Assigning that to a variable counts as
#      "consuming" it under rule 1 while still being the audit's finding A5: passing
#      -60 to `clearCluster()` computes `clus2sec(-60)` and writes zeros at a wild
#      address. So the assignment must be followed immediately by a negativity test
#      on the same variable. `do_create()` already does this correctly and is the
#      pattern to copy.
#
#   3. searchDirectory() FAILURE SIGNAL — searchDirectory() returns a bare boolean,
#      so an I/O error during the scan is indistinguishable from "not found" (finding
#      B1). The fix (plan §14.3, OQ-4 Option A) adds a companion field,
#      `search_io_status`, following the established `initCard()` / `last_init_error`
#      precedent. This rule therefore ACTIVATES ONLY ONCE THAT FIELD EXISTS: until
#      then there is no signal to consult and flagging every call site would be noise.
#      Once the field lands, every method calling searchDirectory() must read it.
#
#   4. BOOLEAN XOR STATUS CODE — the governing convention for the driver (plan §14.4)
#      is that a method returns EITHER a boolean OR a status code, never both, with
#      failure detail in a companion field. The hybrid is not a style preference: in
#      Spin2 `TRUE` is -1 and `E_TIMEOUT` is -1, the identical 32 bits, so the two
#      channels literally collide and no comparison can separate them. `eofHandle()`
#      on a bad handle reports "at EOF"; `isFileContiguous()` on an I/O error reports
#      "contiguous". Both are the most dangerous wrong answer for their caller. This
#      rule flags any method that assigns its return variable both a comparison result
#      and an error code (or tests that same variable for negativity, which proves it
#      can hold one).
#
# WHAT IT DOES NOT CHECK, and why: `clearCluster()` and `readNextSector()` have no
# return value at all today — there is nothing to drop, so there is nothing to grep.
# They are C3 in the audit and are fixed by giving them a status; once they have one,
# add them to WATCHED below and this script starts guarding them too.
#
# Advisory exit code (always 0), matching check_doc_counts.sh and check_doc_claims.sh,
# so it can sit in a release checklist without failing the build. It never edits
# anything and never needs hardware. Run it from tools/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

# The fallible primitives whose status a call site can silently drop.
WATCHED='writeSector|readSector|allocateCluster|searchDirectory'

# ---------------------------------------------------------------------------
# ALLOWLIST — legitimate predicates, exempt from rule 4.
#
# These nine answer a yes/no question about state and cannot meaningfully fail, so a
# boolean IS the right return type for them (audit §F2, plan §14.1). Without this
# list the boolean-XOR-status rule flags all nine on every run, and sooner or later
# somebody "fixes" a method that was never broken. The reason is recorded per entry
# so it survives without the plan document:
#
#   isLeapYear           — arithmetic on a year; no I/O, no failure mode
#   validateHandle       — range + in-use check on an index; no I/O
#   isFileOpenForWrite   — scans the in-memory handle table; no I/O
#   isFileOpenAny        — same, for the compaction open-file check
#   isComplete           — reads two in-memory async fields; no I/O
#   isHighSpeedActive    — compares the cached spi_freq against a constant
#   getLastCMD23Used     — returns a recorded flag from the last transfer
#   getCmd23Supported    — returns a capability decoded from SCR at init time
#   checkStackGuard      — inspects guard bytes in hub RAM; boolean is correct here.
#                          Audit §A7 is about escalating what the CALLER does with
#                          the result, NOT about changing this return type.
# ---------------------------------------------------------------------------
PREDICATE_ALLOWLIST='isLeapYear validateHandle isFileOpenForWrite isFileOpenAny isComplete isHighSpeedActive getLastCMD23Used getCmd23Supported checkStackGuard'

mapfile -t SRCS < <(git -C "$ROOT" ls-files --full-name 'src/*.spin2' 'src/**/*.spin2' 2>/dev/null | sort)

if [[ ${#SRCS[@]} -eq 0 ]]; then
    echo -e "${RED}No Spin2 sources discovered via git ls-files — aborting.${NC}"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Does the searchDirectory companion field exist yet? Rule 3 is gated on this.
if grep -qE '^[[:space:]]+search_io_status[[:space:]]+LONG' "${SRCS[@]}" 2>/dev/null; then
    SEARCH_FIELD_PRESENT=1
else
    SEARCH_FIELD_PRESENT=0
fi

: > "$TMP/findings.txt"
: > "$TMP/exempt.txt"

for f in "${SRCS[@]}"; do
    [[ -f "$f" ]] || continue
    awk -v file="$f" -v watched="$WATCHED" -v allow="$PREDICATE_ALLOWLIST" \
        -v have_field="$SEARCH_FIELD_PRESENT" -v exemptfile="$TMP/exempt.txt" '
    # Index of the comment-opening apostrophe — the first one not inside a
    # double-quoted string, or 0 if the line is all code. Spin2 has no
    # apostrophe-quoted strings, so quote state is the only thing to track.
    # Code and comment both derive from this one scan.
    function splitat(line,   i, c, inq) {
        inq = 0
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (c == "\"") inq = !inq
            else if (c == "'"'"'" && !inq) return i
        }
        return 0
    }
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function emit(rule, ln, msg) { printf "%s\t%d\t%s\t%s\n", file, ln, rule, msg }

    # Close out the method we were accumulating rule-4 state for.
    function flush_method() {
        if (m_name == "") return
        if (m_ret != "" && m_has_cmp && (m_has_status || m_has_negtest)) {
            # Spin2 is case-INSENSITIVE (p2kbLanguageCaseSensitivity), so the
            # allowlist is stored and looked up folded — the same treatment
            # check_doc_api.sh gives the PUB surface.
            if (!(tolower(m_name) in allowed)) {
                emit("R4", m_cmp_line, m_name "() returns a boolean AND a status code" \
                     " (comparison at :" m_cmp_line ", error code at :" m_evidence_line \
                     ") -- a method returns one or the other, never both (plan 14.4)")
            }
        }
        m_name = ""; m_ret = ""; m_has_cmp = 0; m_has_status = 0; m_has_negtest = 0
    }

    BEGIN {
        n = split(allow, a, " ")
        for (i = 1; i <= n; i++) allowed[tolower(a[i])] = 1
        m_name = ""
    }

    {
        at = splitat($0)
        code[NR] = (at ? substr($0, 1, at - 1) : $0)
        cmt[NR]  = (at ? substr($0, at)        : "")
    }

    END {
        for (ln = 1; ln <= NR; ln++) {
            c = code[ln]
            bare = trim(c)

            # ---- method tracking (for rule 4) --------------------------------
            if (bare ~ /^(PUB|PRI|pub|pri)[[:space:]]+[A-Za-z_]/) {
                flush_method()
                hdr = bare
                sub(/^(PUB|PRI|pub|pri)[[:space:]]+/, "", hdr)
                m_name = hdr
                sub(/[[:space:](:|].*$/, "", m_name)
                # return variable: the token after the colon that follows the
                # parameter list, before any local-variable list.
                m_ret = ""
                if (match(hdr, /\)[[:space:]]*:[[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
                    r = substr(hdr, RSTART, RLENGTH)
                    sub(/^\)[[:space:]]*:[[:space:]]*/, "", r)
                    m_ret = r
                }
                m_has_cmp = 0; m_has_status = 0; m_has_negtest = 0
                continue
            }

            # ---- rule 4 accumulation -----------------------------------------
            if (m_ret != "") {
                if (match(bare, "^" m_ret "[[:space:]]*:=")) {
                    rhs = substr(bare, RSTART + RLENGTH)
                    if (rhs ~ /<>|==|>=|<=|=<|=>/ || rhs ~ /(^|[^A-Za-z0-9_])(TRUE|true|FALSE|false)([^A-Za-z0-9_]|$)/) {
                        if (!m_has_cmp) { m_has_cmp = 1; m_cmp_line = ln }
                    }
                    if (rhs ~ /pb_status/ || rhs ~ /(^|[^A-Za-z0-9_])E_[A-Z0-9_]+/) {
                        if (!m_has_status) { m_has_status = 1; m_evidence_line = ln }
                    }
                }
                if (bare ~ ("(^|[^A-Za-z0-9_])" m_ret "[[:space:]]*(<|>)=?[[:space:]]*0([^0-9]|$)")) {
                    if (!m_has_negtest) { m_has_negtest = 1; if (!m_has_status) m_evidence_line = ln }
                }
            }

            # ---- rule 1: bare-statement call, status discarded ---------------
            if (match(bare, "^(" watched ")\\(")) {
                fn = substr(bare, RSTART, RLENGTH - 1)
                if (cmt[ln] ~ /'"'"'[[:space:]]*status intentionally ignored:[[:space:]]*[^[:space:]]/) {
                    exempt++
                } else {
                    emit("R1", ln, fn "() status discarded -- consume it, or add" \
                         " \"'"'"' status intentionally ignored: <reason>\"")
                }
            }

            # ---- rule 2: unchecked allocateCluster() result -------------------
            if (match(bare, "^[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?[[:space:]]*:=[[:space:]]*allocateCluster\\(")) {
                v = bare; sub(/[[:space:]]*:=.*$/, "", v); sub(/\[.*$/, "", v)
                # next line carrying actual code
                nx = 0
                for (j = ln + 1; j <= NR; j++) {
                    if (trim(code[j]) != "") { nx = j; break }
                }
                ok = 0
                if (nx && trim(code[nx]) ~ ("(^|[^A-Za-z0-9_])" v "[[:space:]]*(<|>)=?[[:space:]]*0([^0-9]|$)")) ok = 1
                if (!ok)
                    emit("R2", ln, "allocateCluster() result in `" v "` is not tested for" \
                         " failure before use -- E_DISK_FULL (-60) reaches clus2sec()" \
                         " (audit A5; do_create() has the correct guard)")
            }

            # ---- rule 3: searchDirectory() failure signal ---------------------
            if (have_field == 1 && bare ~ /searchDirectory\(/ && m_name != "" && m_name != "searchDirectory") {
                sd_line[m_name] = ln
                sd_seen[m_name] = 1
            }
            if (have_field == 1 && bare ~ /search_io_status/ && m_name != "")
                sd_consults[m_name] = 1
        }
        flush_method()

        if (have_field == 1)
            for (nm in sd_seen)
                if (!(nm in sd_consults))
                    emit("R3", sd_line[nm], nm "() calls searchDirectory() without consulting" \
                         " search_io_status -- an I/O failure reads as \"not found\" (audit B1)")

        if (exempt > 0) printf "%d\n", exempt >> exemptfile
    }
    ' "$f" >> "$TMP/findings.txt"
done

# ---- report ----------------------------------------------------------------

exempt_total=$(awk '{ n += $1 } END { print n + 0 }' "$TMP/exempt.txt" 2>/dev/null || echo 0)
total=$(wc -l < "$TMP/findings.txt" | tr -d ' ')

echo ""
echo -e "${CYAN}Error-handling audit — ${#SRCS[@]} Spin2 source(s)${NC}"
echo ""

if [[ "$total" -eq 0 ]]; then
    echo -e "  ${GREEN}Every fallible call site consumes its status, and no method mixes a boolean with a status code.${NC}"
else
    for rule in R1 R2 R3 R4; do
        case "$rule" in
            R1) hdr="Discarded status" ;;
            R2) hdr="Unchecked allocateCluster() result" ;;
            R3) hdr="searchDirectory() failure signal not consulted" ;;
            R4) hdr="Boolean and status code in one return" ;;
        esac
        n=$(grep -c $'\t'"$rule"$'\t' "$TMP/findings.txt" || true)
        [[ "$n" -eq 0 ]] && continue
        echo -e "  ${YELLOW}${hdr}${NC} (${n})"
        while IFS=$'\t' read -r file ln r msg; do
            [[ "$r" == "$rule" ]] || continue
            printf "    ${RED}%-34s${NC} %s\n" "$file:$ln" "$msg"
        done < "$TMP/findings.txt"
        echo ""
    done
fi

echo ""
if [[ "$SEARCH_FIELD_PRESENT" -eq 0 ]]; then
    echo -e "  ${CYAN}Rule 3 inactive${NC} — no \`search_io_status\` companion field in the sources yet."
    echo -e "  It arms itself automatically once that field lands (plan §14.3 / OQ-4)."
fi
[[ "$exempt_total" -gt 0 ]] && \
    echo -e "  ${CYAN}${exempt_total} call site(s) exempted${NC} by an explicit \"status intentionally ignored:\" comment."

echo ""
if [[ "$total" -eq 0 ]]; then
    echo -e "${GREEN}Clean.${NC}"
else
    echo -e "${YELLOW}${total} finding(s). Each is a place the driver can fail and report success.${NC}"
fi
echo ""

# Advisory only — never fails a build. Same posture as check_doc_counts.sh.
exit 0
