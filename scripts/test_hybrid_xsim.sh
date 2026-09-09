#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
vivado_root="${XILINX_VIVADO:-$(dirname "$(dirname "$(command -v vivado)")")}"
mkdir -p "$root/build/sim/hybrid_xsim"
cd "$root/build/sim/hybrid_xsim"
xvlog --sv "$root"/rtl/*.sv "$root/tb/tb_hybrid_equivalence.sv" \
    "$root/tb/tb_genesis.sv" "$root/tb/tb_bitcoin_miner_axi.sv" \
    "$vivado_root/data/verilog/src/glbl.v" > compile.log 2>&1
for top in tb_hybrid_equivalence tb_genesis tb_bitcoin_miner_axi; do
    params=()
    if [[ "$top" != tb_hybrid_equivalence ]]; then params=(-generic_top HYBRID=1); fi
    xelab "$top" glbl -L unisims_ver -L unimacro_ver "${params[@]}" \
        -s "$top" > "$top.elaborate.log" 2>&1
    xsim "$top" -runall -log "$top.simulate.log" > "$top.console.log" 2>&1
    if rg -q 'Fatal:|FATAL:|Error:|ERROR:|FAIL ' "$top.simulate.log"; then
        echo "FAIL: inspect $PWD/$top.simulate.log" >&2; exit 1
    fi
    rg 'PASS' "$top.simulate.log"
done
