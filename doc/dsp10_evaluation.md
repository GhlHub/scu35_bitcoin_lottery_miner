# Ten-DSP-per-engine evaluation

Historical two-lane evaluation. Current source/configuration scripts select
three lanes and add component versioning; see [versions](versions.md).
The commands below describe the original run, not a two-lane selector in
the current scripts.

Built and routed with Vivado 2026.1 on 2026-09-09. This is a local evaluation;
QSPI and the running board were not changed. Existing `build/images/` files
still contain the previously deployed five-DSP-per-engine telemetry image.

## Scope

The two mining engines remain at 200 MHz and MicroBlaze remains at 50 MHz.
Each engine adds DSP48E2 implementations for three round-setup additions
(`h + Sigma1`, `Ch + K`, `Sigma0 + Maj`) and two state-update additions
(`T1 + T2`, `d + T1`). Together with the existing five DSP adders, this uses
ten DSPs per engine. Digest feed-forward additions remain in fabric.
Firmware, clocks, constraints, and engine count are unchanged.

The `DSP_ROUND_STATE` parameter selects these five additional DSP adders;
`EXPLICIT_DSP_SCHEDULE=1, DSP_ROUND_STATE=0` retains the previous hybrid.

## Routed comparison

Baseline is the immediately preceding five-DSP hybrid **with telemetry and
the hardware hash counter**, not the earlier pre-telemetry build.

| Resource / timing | Five DSPs/engine | Ten DSPs/engine | Change |
|---|---:|---:|---:|
| LUTs / 16,320 | 11,304 (69.26%) | 11,214 (68.71%) | -90 |
| Flip-flops / 32,640 | 13,478 | 13,490 (41.33%) | +12 |
| DSP48E2 / 48 | 13 | 23 (47.92%) | +10 |
| BRAM tiles / 48 | 17.5 | 17.5 (36.46%) | 0 |
| CARRY8 | 278 | 238 | -40 |
| Overall setup WNS | +0.010 ns | +0.001 ns | -0.009 ns |
| Overall hold WHS | +0.010 ns | +0.010 ns | 0 |
| Miner-to-miner setup WNS | +0.566 ns | +0.552 ns | -0.014 ns |

Twenty DSPs belong to the miner; three belong to MicroBlaze. The extra ten
DSPs save only 90 LUTs device-wide (about 0.8% of previous LUT usage).
This run demonstrates a modest area reduction, **not a timing improvement**.

### Intra-clock setup WNS

| Domain | Frequency | Previous | New |
|---|---:|---:|---:|
| Miner / HyperBus (`clk_out1`) | 200 MHz | +0.566 ns | +0.552 ns |
| MicroBlaze / AXI | 50 MHz | +12.670 ns | +12.701 ns |
| HyperRAM receive (`clk_out2`) | 200 MHz | +3.688 ns | +4.060 ns |
| Delay reference (`clk_out4`) | 300 MHz | +2.085 ns | +2.426 ns |
| MII RX | 25 MHz | +8.251 ns | +9.026 ns |
| MII TX | 25 MHz | +22.895 ns | +22.617 ns |
| Debug DRCK | 30 MHz | +14.656 ns | +15.029 ns |
| Debug UPDATE | 15 MHz | +30.972 ns | +30.286 ns |

All user-specified timing constraints pass. The overall +0.001 ns WNS is
the HyperRAM receive `clk_out2` to HyperBus `clk_out1` crossing, not the
miner datapath. That 1 ps margin is very small. This is timing closure under
the current constraints, not complete external HyperRAM interface STA signoff.

## Functional checks

- `make test` passed, including genesis, AXI, counter, and software tests.
- `make test-hybrid` passed using the AMD UNISIM DSP48E2 model.
- Equivalence tests compare fabric, five-DSP, and ten-DSP implementations
  across 32 blocks, including zero/all-ones inputs and arbitrary initial states.
  Five- and ten-DSP completion pulses and digests match cycle-for-cycle.
- SHA256d remains 527 cycles/nonce, approximately 0.759 MH/s combined at
  200 MHz before job-change overhead. This variant has not been measured on
  hardware; it has no architectural throughput increase over the deployed hybrid.
- Routed checks confirm 20 miner DSPs, nonnegative setup/hold slack, and
  passing bus-skew constraints. DRC has no errors or critical warnings.
  Unpipelined DSP advisories remain because the DSP ALUs are combinational
  between existing SHA pipeline registers; they have not been suppressed.

## Reproduce and evidence

```sh
make test
make test-hybrid
vivado -mode batch -source scripts/configure_hybrid.tcl -tclargs 1 1
make synth
make implement
vivado -mode batch -source scripts/report_hybrid.tcl
vivado -mode batch -source scripts/check_final.tcl
```

Current checkpoint:
`build/vivado/scu35_miner.runs/impl_1/design_1_wrapper_routed.dcp`.
Baseline RTL, checkpoint, and reports are preserved locally in
`build/dsp5_telemetry_baseline/`.

Evidence: `logs/tests_dsp10.log`, `logs/xsim_dsp10.log`,
`logs/synth_dsp10.log`, `logs/implement_dsp10.log`,
`logs/route_utilization.rpt`, `logs/route_timing.rpt`,
`logs/route_drc.rpt`, `logs/route_bus_skew.rpt`,
`logs/dsp5_baseline_miner_timing.rpt`, `logs/dsp10_miner_timing.rpt`,
`logs/report_dsp10.console.log`, and `logs/final_audit_dsp10.console.log`.

No flash image was generated or programmed for this evaluation. A future
deployment must first regenerate images from this build with `make images`.
