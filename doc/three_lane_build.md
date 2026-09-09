# Three-lane version 1.0.0 build

Original 200 MHz build. The later 210 MHz experiment was withdrawn, and
current source has returned to this three-lane hardware 1.0.0 configuration.
See the [restoration report](restored200_build.md) for the new rebuild.

Vivado/Vitis 2026.1, SCU35 `xcsu35p-sbvb625-2-e`, built 2026-09-09.
Three SHA256d lanes at 200 MHz, ten DSP48E2 adders per lane. MicroBlaze
remains at 50 MHz. Hardware, bootloader, application, and dashboard versions
start independently at **1.0.0**; see [component versions](versions.md).

This is a local build, not a board deployment. No QSPI programming, reboot,
EEPROM update, or remote Git push was performed.

## Resource and timing comparison

Baseline is the preceding two-lane, ten-DSP-per-lane evaluation, including
the telemetry hash counter. The new build additionally includes version
registers and a sequential job distributor.

| Metric | Two lanes | Three lanes |
|---|---:|---:|
| LUTs / 16,320 | 11,214 (68.71%) | **13,255 (81.22%)** |
| Flip-flops / 32,640 | 13,490 | **16,534 (50.66%)** |
| DSP48E2 / 48 | 23 | **33 (68.75%)** |
| BRAM tiles / 48 | 17.5 | **17.5 (36.46%)** |
| CARRY8 | 238 | 278 |
| Overall setup WNS | +0.001 ns | **+0.059 ns** |
| Overall hold WHS | +0.010 ns | **+0.010 ns** |
| Miner-domain setup WNS | +0.552 ns | **+0.535 ns** |
| Expected steady-state throughput | 0.759 MH/s | **1.139 MH/s** |

Adding the third lane and version support costs 2,041 LUTs, 3,044 flip-flops,
and ten DSPs. Thirty DSPs belong to the miner and three to MicroBlaze.
There are 3,065 LUTs and 15 DSPs left. Both setup and hold have zero failing
endpoints under the current constraints.

SHA256d remains 527 cycles per nonce per lane, giving
`3 * 200,000,000 / 527 = 1,138,520 H/s` before job-switching overhead,
a 50% architectural throughput increase. This is not a measurement of the
new design on hardware or of pool-effective accepted work.

### Per-clock setup slack

| Domain | Frequency | WNS |
|---|---:|---:|
| Miner / HyperBus (`clk_out1`) | 200 MHz | +0.535 ns |
| MicroBlaze / AXI | 50 MHz | +10.933 ns |
| HyperRAM receive (`clk_out2`) | 200 MHz | +3.980 ns |
| Delay reference (`clk_out4`) | 300 MHz | +2.148 ns |
| MII RX | 25 MHz | +8.694 ns |
| MII TX | 25 MHz | +22.684 ns |
| Debug DRCK | 30 MHz | +14.459 ns |
| Debug UPDATE | 15 MHz | +30.764 ns |

The global critical path is the HyperRAM receive `clk_out2` to HyperBus
`clk_out1` crossing at +0.059 ns. This remains a small margin. The report
does not constitute complete external HyperRAM interface STA signoff;
board calibration, startup, and sustained operation must be tested after
an explicitly authorized deployment.

## Changes needed for timing closure

Simply changing the lane count produced a routed -2.297 ns path through
the combinational divide-by-three in nonce distribution. A 32-cycle restoring
divider now runs once per batch. Each lane receives
`count / 3 + (lane < count % 3)` nonces with stride three. This adds only
160 ns of setup, not extra cycles per hash. STOP overrides an in-progress
launch, including division.

The revised RTL met miner timing, but the default implementation missed
four HyperRAM receive paths by up to 0.051 ns. Post-route AggressiveExplore
alone did not recover that slack. Re-placement/routing with
`Performance_ExplorePostRoutePhysOpt` closed timing at +0.059 ns without
changing clocks, timing exceptions, controller RTL, or I/O constraints.
Fresh projects select this strategy; implementation runs through the enabled
post-route physical optimization step.

## Verification

- `make test` and AMD UNISIM `make test-hybrid` passed.
- Three-lane tests check nonce uniqueness, lane IDs, wraparound, uneven
  batches, zero/one/two-item batches, the full 32-bit count range using
  randomized quota checks, stop during division, and restart afterward.
- The two-lane parameterized regression still passes.
- Version tests cover read-only hardware identity, boot handoff read/write,
  byte strobes, reset-to-unknown, persistence across jobs, JSON formatting,
  unknown older-device versions, and dashboard display.
- Maximum-sized versioned telemetry fits the 2048-byte packet limit.
- Bootloader and application compile; SREC validation passes. Bootloader
  total text/data/BSS reservation is 14,576 bytes, within 16 KiB.
- Final DRC has no errors or critical warnings. Unpipelined DSP warnings
  remain expected for combinational DSP ALUs between existing SHA registers.
  Vivado also emits two existing generated SYSMON pin-IOSTANDARD constraint
  critical warnings during netlist loading; these are distinct from the
  clean final DRC severity summary and are not suppressed.

## Rebuild

For an existing project:

```sh
make test
make test-hybrid
vivado -mode batch -source scripts/configure_hybrid.tcl -tclargs 1 1
make synth
vivado -mode batch -source scripts/configure_three_lane_impl.tcl
make implement
vivado -mode batch -source scripts/report_hybrid.tcl
vivado -mode batch -source scripts/check_final.tcl
make bootloader application
make images
```

These commands build files only; they do not connect to hardware.
Final implementation checkpoint:
`build/vivado/scu35_miner.runs/impl_1/design_1_wrapper_postroute_physopt.dcp`.
The previous deployed image is preserved in
`build/pre_three_lane_images_20260909/`; the two-lane comparison checkpoint
and reports are in `build/dsp10_two_lane_baseline/`.

Evidence: `logs/tests_three_lane_divider.log`,
`logs/xsim_three_lane_divider.log`, `logs/two_lane_regression.log`,
`logs/software_three_lane_final.log`, `logs/synth_three_lane_divider.log`,
`logs/implement_three_lane_explore.log`, `logs/route_utilization.rpt`,
`logs/route_timing.rpt`, `logs/route_bus_skew.rpt`, `logs/route_drc.rpt`,
`logs/report_three_lane.console.log`, `logs/three_lane_miner_timing.rpt`,
`logs/final_audit_three_lane.console.log`, and `logs/images_three_lane.log`.

## Packaged image

`make images` completed at 07:00 PDT on 2026-09-09. The combined
`build/images/scu35_flash.mcs` was verified byte-for-byte against both
payloads. Copies of the packaged bootloader and application ELFs also match
the newly built versioned ELFs exactly.

| Payload | Flash offset | Bytes | SHA-256 |
|---|---:|---:|---|
| FPGA + bootloader PDI | `0x00000000` | 1,163,168 | `3e936aca61c250ba595ffcfccb9dfafbeec7869bce945151dcc16a6955b92a58` |
| Application SREC | `0x00800000` | 578,340 | `92940e70761b080b48966923313eca77ed076b74b9a9612439f5e2a194a2dc3b` |

The final image, checkpoint, and reports are preserved locally in
`build/three_lane_v1_0_0/`. The post-packaging current-run/BD audit is
`logs/final_audit_three_lane_packaged.console.log`. These images have not
been programmed into QSPI or tested on the board.
