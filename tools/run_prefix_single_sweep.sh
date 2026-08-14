#!/usr/bin/env bash
#
# run_prefix_single_sweep.sh — walk SD_prefix_single_probe across every DAT pad size.
#
# THE QUESTION. SD_prefix_write_probe proved that v1.6.1's MULTI-BLOCK write path stores
# one-bit-late data at one caller-buffer position in eight. Multi-block has one caller,
# reachable only from public writeSectorsRaw(). The SINGLE-BLOCK writeSector() has 41 call
# sites and carries every filesystem write — file data, directory entries, FAT, FSInfo.
# This sweep asks whether that path is exposed too.
#
# WHY A SWEEP AND NOT ONE RUN. writeSectorRaw() bytemoves into the driver's INTERNAL
# buffer, so the streamer's source address is fixed by the build's DAT layout. It cannot
# be varied at runtime — only by rebuilding with a different pad. One build per position.
#
# READING IT. ANY SHIFTED verdict at ANY pad means ordinary file writes in released builds
# could corrupt data. All-correct means released exposure was confined to raw multi-block
# users. Do not read a single pad's result as the answer.
#
# Destructive only to LBA 100_000, a sanctioned scratch sector. Run from tools/.
#
# BASH 3.2 COMPATIBLE. The macOS host ships bash 3.2, where "${arr[@]}" on an empty
# array under `set -u` aborts. Every array expansion here uses the ${arr[@]+"${arr[@]}"}
# form. Do not "simplify" them back -- the failure mode is a silent NO RESULT in the one
# cell that takes no defines, which reads as a probe fault rather than a script bug.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

PROBE="../diagnostic-tests/SD_prefix_single_probe.spin2"
PADS=(BASELINE PAD_4 PAD_8 PAD_12 PAD_16 PAD_20 PAD_24 PAD_28 PAD_32)
# PAD_32 was added after the first sweep: the baseline landed on long-slice 6, not 0, and
# PAD_24 duplicated it -- so seven of eight positions were covered and slice 0 was blind.

# Two passes. PRE-FIX answers "were released users exposed on this path". FIXED answers
# "does the v1.7.0 hoist hold across layouts on the path 41 call sites use" -- which the
# multi-block alignment sweep never covered, because it can only vary a CALLER buffer.
DRIVERS=("PREFIX:" "FIXED:USE_FIXED_DRIVER")

echo ""
echo -e "${CYAN}Pre-fix SINGLE-BLOCK write sweep — driver as tagged at v1.6.1${NC}"
echo -e "${CYAN}Path under test: writeSectorRaw -> writeSector (every filesystem write)${NC}"
echo ""

shifted=0
other=0
results=()
addrs=()

for drv in "${DRIVERS[@]}"; do
  drvName="${drv%%:*}"; drvDef="${drv#*:}"
  echo -e "${CYAN}--- ${drvName} driver ---${NC}"
  for pad in "${PADS[@]}"; do
    args=()
    [[ -n "$drvDef" ]] && args+=(-D "$drvDef")
    [[ "$pad" != "BASELINE" ]] && args+=(-D "$pad")
    # ${arr[@]+"${arr[@]}"} is the bash-3.2-safe empty-array expansion; a bare
    # "${args[@]}" aborts under `set -u` on macOS when no defines are given.
    out=$(./run_test.sh "$PROBE" ${args[@]+"${args[@]}"} 2>&1)

    line=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\* pad=[^:]+: A=[A-Z-]+  B=[A-Z-]+' | head -1)
    addr=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'DRIVER INTERNAL BUF: \$?[0-9A-Fa-f_]+' | grep -oE '[0-9A-Fa-f_]+$' | head -1)
    [[ -n "$addr" ]] && addrs+=("$addr")

    if [[ -z "$line" ]]; then
        printf "  %-10s ${RED}NO RESULT${NC} — probe did not report (compile or download failure)\n" "$pad"
        other=$((other + 1)); results+=("$pad: NO RESULT"); continue
    fi

    if echo "$line" | grep -q "SHIFTED"; then
        printf "  %-10s ${RED}%s${NC}\n" "$pad" "$line"
        shifted=$((shifted + 1))
    elif echo "$line" | grep -qE "OTHER|FAIL"; then
        printf "  %-10s ${YELLOW}%s${NC}\n" "$pad" "$line"
        other=$((other + 1))
    else
        printf "  %-10s ${GREEN}%s${NC}\n" "$pad" "$line"
    fi
    results+=("$drvName $pad: $line")
  done
  echo ""
done

echo ""
# SELF-VALIDATION. If the pad never moved the driver's internal buffer, every verdict
# above is a null result that reports correct and means nothing. Refuse to conclude.
uniq_addrs=$(printf "%s\n" ${addrs[@]+"${addrs[@]}"} | sort -u | grep -c . || true)
echo "  driver internal buffer addresses seen: ${uniq_addrs} distinct of ${#addrs[@]} runs"
if [[ "${#addrs[@]}" -gt 1 && "$uniq_addrs" -lt 2 ]]; then
    echo ""
    echo -e "${RED}NULL EXPERIMENT — the pad never moved the driver's buffer.${NC}"
    echo "  Every verdict above is meaningless. The pad block is not displacing the"
    echo "  driver object; the link order is not what this probe assumes. Fix that"
    echo "  before reading any result."
    exit 2
fi

echo ""
echo "============================================================"
prefixShift=$(printf "%s\n" ${results[@]+"${results[@]}"} | grep -c "^PREFIX .*SHIFTED" || true)
fixedShift=$(printf "%s\n" ${results[@]+"${results[@]}"} | grep -c "^FIXED .*SHIFTED" || true)

if [[ "$fixedShift" -gt 0 ]]; then
    echo -e "${RED}THE FIX DOES NOT HOLD: ${fixedShift} shifted position(s) on the CURRENT driver.${NC}"
    echo "  This is a live defect in v1.7.0 on the path every filesystem write uses."
    echo "  STOP. Do not ship. Report which pads failed."
elif [[ "$prefixShift" -gt 0 ]]; then
    echo -e "${RED}${prefixShift} PRE-FIX position(s) store SHIFTED data.${NC}"
    echo "  Ordinary file writes in released builds could corrupt data, on every release"
    echo "  from v0.9.3 through v1.6.1. The v1.7.0 upgrade note must be STRENGTHENED."
    echo "  The current driver is clean at every position tested."
elif [[ $shifted -gt 0 ]]; then
    echo -e "${RED}${shifted} shifted position(s) -- see the per-pass lines above.${NC}"
elif [[ $other -gt 0 ]]; then
    echo -e "${YELLOW}${other} inconclusive position(s).${NC} Not an answer either way — resolve"
    echo "  the instrument before drawing a conclusion."
else
    echo -e "${GREEN}All ${#PADS[@]} positions correct on BOTH drivers.${NC}"
    echo ""
    echo "  PRE-FIX: the single-block path — every filesystem write — was NOT exposed in"
    echo "  released code at any long position. Released exposure was confined to raw"
    echo "  multi-block users (writeSectorsRaw), which SD_prefix_write_probe confirmed"
    echo "  fails at 1 position in 8. The v1.7.0 upgrade note should say exactly that"
    echo "  rather than warning every user."
    echo ""
    echo "  FIXED: the v1.7.0 hoist holds across every layout position on the path 41"
    echo "  call sites use — coverage the multi-block alignment sweep could not reach."
fi
echo "============================================================"
echo ""

[[ $shifted -gt 0 ]] && exit 1
exit 0
