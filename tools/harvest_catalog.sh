#!/usr/bin/env bash
#
# harvest_catalog.sh — turn sweep transcripts into catalog table rows.
#
# WHY THIS EXISTS. Catalog numbers were transcribed from transcripts by hand for
# the project's whole history, and the documents show what that produces: three
# different row labels across eras for the same measurement, and six cards whose
# measured data never reached the summary table at all. Both instruments now emit
# fixed-shape CATALOG-CARD / CATALOG-ROW lines; this reads them back.
#
# The two tables are NEVER merged. SD_speed_characterize measures the CARD (random
# single-sector reads, which pay full internal seek latency on every operation and
# spread cards ~38x); SD_performance_benchmark measures the DRIVER (sequential and
# file traffic, where the bus does the limiting and cards nearly converge). A row
# from one compared against a row from the other shows a large gain or loss that is
# purely an instrument change. That confusion is exactly what the old single mixed
# table caused, and keeping them apart is the whole point of the two-table format.
#
# Usage:
#   ./harvest_catalog.sh logs/*.log            # both tables, from any set of logs
#   ./harvest_catalog.sh --capability logs/*.log
#   ./harvest_catalog.sh --throughput logs/*.log
#
# Output is GitHub-flavoured Markdown, ready to paste under the matching heading
# in DOCs/cards/CARD-CATALOG.md. It prints the driver version banner separately and
# refuses to emit a mixed-version table -- a table whose rows came from two drivers
# cannot state its provenance in one banner, which is the format's core promise.
#
# Deliberately bash 3.2 compatible: macOS ships bash 3.2 and this runs at the bench.

set -uo pipefail

WANT_CAPABILITY=1
WANT_THROUGHPUT=1

case "${1:-}" in
    --capability) WANT_CAPABILITY=1; WANT_THROUGHPUT=0; shift ;;
    --throughput) WANT_CAPABILITY=0; WANT_THROUGHPUT=1; shift ;;
    -h|--help)
        echo "Usage: $0 [--capability|--throughput] <log>..."
        exit 0 ;;
esac

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--capability|--throughput] <log>..." >&2
    exit 2
fi

awk -v want_cap="$WANT_CAPABILITY" -v want_thr="$WANT_THROUGHPUT" '
function rate(lo, hi) {
    # One run prints a number; several print the RANGE they spanned. Never an
    # average -- see the aggregation comment above. A range that collapses to one
    # value is printed as that value, so a stable measurement reads cleanly.
    if (lo == hi) return sprintf("%d KB/s", lo)
    return sprintf("%d-%d KB/s", lo, hi)
}

function field(line, name,   m, rest) {
    # Extract "name=value" from a CATALOG-* line. Values never contain spaces.
    if (match(line, name "=[^ ]+") == 0) return ""
    rest = substr(line, RSTART + length(name) + 1, RLENGTH - length(name) - 1)
    return rest
}

/CATALOG-CARD:/ {
    drv     = field($0, "drv")
    mid     = field($0, "mid")
    pnm     = field($0, "pnm")
    prv     = field($0, "prv")
    psn     = field($0, "psn")
    mdt     = field($0, "mdt")
    sysclk  = field($0, "sysclk")
    tool    = field($0, "tool")

    # CANONICAL KEY FORM.
    #
    # The silicon key keeps the MID as HEX, not a brand name. Mapping MID to a
    # manufacturer is not a function: $9F appears in this project drawer as both a
    # Silicon Power and a Gigastone-branded card, and brand does not predict
    # controller in general -- Gigastone-branded cards here carry three different
    # MIDs. A hex MID is ground truth and always unambiguous; the friendly name is
    # decoration the catalog adds, from a mapping it owns in one place.
    #
    # The Card ID follows the catalog convention: no inner $ sigil, and the
    # manufacture date as YYYYMM with a zero-padded month.
    bare_psn = psn; sub(/^\$/, "", bare_psn)
    split(mdt, mdt_parts, "/")
    mdt_compact = mdt_parts[1] sprintf("%02d", mdt_parts[2])

    silicon = mid "_" pnm "_" prv
    card    = silicon "_" bare_psn "_" mdt_compact

    versions[drv] = 1
    next
}

/CATALOG-ROW:/ {
    if (card == "") { orphans++; next }
    instr = field($0, "instr")

    if (instr == "random_access") {
        # Keyed by card AND landed clock: SD_speed_characterize walks a speed
        # ladder, so one card legitimately produces several rows in one run.
        key = card SUBSEP field($0, "landed_hz")
        kbps = field($0, "kbps") + 0
        if (!(key in cap_seen)) {
            cap_seen[key] = 1
            cap_order[++cap_n] = key
            cap_lo[key] = kbps
            cap_hi[key] = kbps
        } else {
            if (kbps < cap_lo[key]) cap_lo[key] = kbps
            if (kbps > cap_hi[key]) cap_hi[key] = kbps
        }
        cap_runs[key]++
        cap_card[key]    = card
        cap_silicon[key] = silicon
        cap_mean[key]    = field($0, "mean_us")
        cap_min[key]     = field($0, "min_us")
        cap_max[key]     = field($0, "max_us")
        cap_landed[key]  = field($0, "landed_hz")
        cap_iters[key]   = field($0, "iters")
    } else if (instr == "throughput") {
        key = card SUBSEP field($0, "op") SUBSEP field($0, "bytes")
        kbps = field($0, "kbps") + 0
        if (!(key in thr_seen)) {
            thr_seen[key] = 1
            thr_order[++thr_n] = key
            thr_lo[key] = kbps
            thr_hi[key] = kbps
        } else {
            # REPEAT RUNS AGGREGATE AS A RANGE, NEVER AN AVERAGE.
            #
            # Round 11b measured one physical card moving up to 3x between rounds.
            # An average over runs would report a single confident number for a
            # measurement that is not stable, and hide the very dispersion the
            # repeat run was performed to expose. Overwriting silently -- which
            # this script did before repeat runs existed -- would be worse still:
            # it would report the LAST run as if it were the only one.
            if (kbps < thr_lo[key]) thr_lo[key] = kbps
            if (kbps > thr_hi[key]) thr_hi[key] = kbps
        }
        thr_runs[key]++
        thr_card[key]    = card
        thr_silicon[key] = silicon
        thr_op[key]      = field($0, "op")
        thr_bytes[key]   = field($0, "bytes")
        thr_avg[key]     = field($0, "avg_us")
        thr_pct[key]     = field($0, "pct_bus")
        thr_lim[key]     = field($0, "limiter")
        thr_spi[key]     = field($0, "spi_hz")
    }
    next
}

END {
    nver = 0
    for (v in versions) { nver++; onever = v }
    if (nver == 0) {
        print "No CATALOG-CARD lines found. Were these logs produced by an instrument that emits them?" > "/dev/stderr"
        exit 1
    }
    if (nver > 1) {
        printf "REFUSING: rows span %d driver versions:", nver > "/dev/stderr"
        for (v in versions) printf " %s", v > "/dev/stderr"
        print "" > "/dev/stderr"
        print "A pristine table states ONE driver version in its banner. Re-sweep on one driver, or harvest each separately." > "/dev/stderr"
        exit 1
    }
    if (orphans > 0)
        printf "note: %d CATALOG-ROW line(s) had no preceding CATALOG-CARD and were skipped\n\n", orphans > "/dev/stderr"

    print "**All figures measured on driver v" onever ".**"
    print ""

    if (want_cap && cap_n > 0) {
        print "### Card capability (random access)"
        print ""
        print "Single-sector reads at random offsets. This is a property of the CARD:"
        print "every read pays the controller full internal seek latency, which is why"
        print "these figures spread widely across cards."
        print ""
        print "| Silicon key | Card ID | Reads | Landed clock | Throughput | Runs | Mean latency | Min | Max |"
        print "|---|---|---:|---:|---:|---:|---:|---:|---:|"
        for (i = 1; i <= cap_n; i++) {
            k = cap_order[i]
            printf "| `%s` | `%s` | %s | %.2f MHz | **%s** | %d | %s us | %s us | %s us |\n", \
                cap_silicon[k], cap_card[k], cap_iters[k], cap_landed[k] / 1000000, \
                rate(cap_lo[k], cap_hi[k]), cap_runs[k], cap_mean[k], cap_min[k], cap_max[k]
        }
        print ""
    }

    if (want_thr && thr_n > 0) {
        print "### Driver throughput by traffic type"
        print ""
        print "What an application actually gets from this driver. Limiter attribution"
        print "belongs on THIS table only: the random-access metric above is card-bound"
        print "for every card by construction, so it would carry one constant answer."
        print ""
        print "| Silicon key | Card ID | Traffic | Bytes | SPI | Throughput | Runs | % of bus | Limiter |"
        print "|---|---|---|---:|---:|---:|---:|---:|---|"
        for (i = 1; i <= thr_n; i++) {
            k = thr_order[i]
            printf "| `%s` | `%s` | %s | %s | %.2f MHz | **%s** | %d | %s%% | %s |\n", \
                thr_silicon[k], thr_card[k], thr_op[k], thr_bytes[k], thr_spi[k] / 1000000, \
                rate(thr_lo[k], thr_hi[k]), thr_runs[k], thr_pct[k], thr_lim[k]
        }
        print ""
    }

    if (cap_n == 0 && thr_n == 0)
        print "No CATALOG-ROW lines found in these logs." > "/dev/stderr"
}
' "$@"
