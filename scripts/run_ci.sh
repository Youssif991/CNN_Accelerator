#!/bin/bash
#
# run_ci.sh — Runs every testbench in src/tb/ against Icarus Verilog
# Used by GitHub Actions CI. Fails (non-zero exit) if ANY testbench fails.
#
# Usage: ./run_ci.sh
#

set -uo pipefail   # NOTE: not using -e, we want to run ALL testbenches even if one fails

TB_FILES=$(find src/tb -name "tb_*.v")

TOTAL=0
PASSED=0
FAILED_LIST=()

echo "Discovered testbenches:"
echo "$TB_FILES" | sed 's/^/   /'

for TB in $TB_FILES; do
    TOTAL=$((TOTAL+1))
    TB_NAME=$(basename "$TB" .v)
    OUT_BIN="/tmp/${TB_NAME}_sim"

    # Match testbench to its own design file by name: tb_X.v -> X.v.
    # The match is informational only: the compile below uses all RTL sources,
    # so a missing match is not fatal. For example, tb_bqs_system_disp
    # exercises the same bqs_system top level as tb_bqs_system.
    DUT_NAME="${TB_NAME#tb_}"
    DUT_FILE=$(find src/rtl -iname "${DUT_NAME}.v")

    echo ""
    echo "Running: $TB_NAME  (DUT: ${DUT_FILE:-<all sources>})"

    if ! iverilog -g2012 -o "$OUT_BIN" $(find src/rtl -name "*.v") "$TB"; then
        echo "COMPILE ERROR: $TB_NAME"
        FAILED_LIST+=("$TB_NAME (compile error)")
        continue
    fi

    SIM_OUTPUT=$(vvp "$OUT_BIN" 2>&1)
    echo "$SIM_OUTPUT"

    if echo "$SIM_OUTPUT" | grep -q "TEST FAILED"; then
        echo "FAILED: $TB_NAME"
        FAILED_LIST+=("$TB_NAME (assertion failure)")
    elif echo "$SIM_OUTPUT" | grep -qi "error"; then
        echo "FAILED: $TB_NAME (runtime error detected)"
        FAILED_LIST+=("$TB_NAME (runtime error)")
    else
        echo "PASSED: $TB_NAME"
        PASSED=$((PASSED+1))
    fi
done

echo ""
echo "CI SUMMARY: $PASSED / $TOTAL testbenches passed"

if [ ${#FAILED_LIST[@]} -ne 0 ]; then
    echo "Failed testbenches:"
    for F in "${FAILED_LIST[@]}"; do
        echo "  - $F"
    done
    exit 1
fi

exit 0
