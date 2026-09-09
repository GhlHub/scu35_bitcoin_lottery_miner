# Independent 210 MHz hash clock — hardware 1.1.0

**Withdrawn experiment.** The user requested a return to shared 200 MHz
hash/HyperBus operation before this image was deployed. Current source and
build scripts use [hardware 1.0.0 at 200 MHz](restored200_build.md). The
210 MHz-specific helper scripts and testbench below have been removed;
this report and `build/three_lane_v1_1_0/` retain historical results/artifacts.
The commands below describe the experiment, not the current build flow.

Three hash lanes, ten DSP48E2 adders per lane, with an independent 210 MHz
clock. HyperBus stays at 200 MHz, HyperRAM receive sampling stays at 200 MHz
with its existing 90-degree phase, and MicroBlaze/AXI stay at 50 MHz.

Hardware version is **1.1.0**. Bootloader, application, and dashboard remain
**1.0.0**: their code/interfaces are unchanged. The application reads the
hardware version register, so telemetry and the dashboard display the new
hardware version without hard-coding it in software.

## Clock and reset implementation

The original clock wizard is unchanged. A new `hash_clk_wiz` MMCM accepts its
ungated 200 MHz output and generates 210 MHz. It does not reuse the gated
HyperRAM forwarding clock. The FPGA now uses both available MMCMs.

| Consumer | Clock | Reset source |
|---|---|---|
| Three hash lanes | `hash_clk_wiz/clk_out1`, 210 MHz | `hash_reset_210/peripheral_aresetn` |
| AXI converter master side | Same 210 MHz clock | Same 210 MHz reset |
| AXI converter slave side | Existing CPU/AXI 50 MHz clock | `hash_reset_50/peripheral_aresetn` |
| HyperBus controller | Existing 200 MHz clock | Existing HyperBus reset |
| MicroBlaze and other peripherals | Existing 50 MHz clock | Existing CPU/peripheral resets |

Both new reset controllers use the existing active-low CPU peripheral reset
as their cascade input, MDM debug reset, inactive-high auxiliary reset, and
the new hash MMCM's lock signal. Each releases reset synchronously in its
own domain. Thus loss of hash lock resets both converter sides, not just its
master interface. This does not promise recovery of CPU transactions already
outstanding at an unexpected clock failure.

The clock wizard itself is not reset by board/debug reset, so reset
synchronizers retain clocks. AXI clock-converter `ACLK_ASYNC=1` is retained;
its generated clock metadata and OOC constraints now use 50/210 MHz
(20.000/4.762 ns). No integer clock-ratio assumption is made.

The existing two-flop `ASYNC_REG` interrupt synchronizer remains in the CPU
domain. `constraints/interfaces.xdc` now false-paths only the first flop's D
input. Its stage-to-stage path stays timed. This is an asynchronous level
interrupt crossing, not a synchronous 210-to-50 MHz datapath. The vendor
AXI CDC constraints are retained; no blanket clock-group exception was added.

## Validation

- The BD audit verifies hash, HyperBus, receive, delay-reference, and CPU
  frequencies; reset sources/polarities; both converter sides; and three lanes.
- `make test` and `make test-hybrid` pass, including nonce distribution,
  genesis/target checks, hash counter, settings/protocol, and dashboard tests.
- `make test-clock210` uses the actual generated AMD clock wizard, reset
  controllers, and AXI clock converter, connected to the miner RTL. It
  measures a **4.761910 ns** hash-clock period, checks domain-synchronous
  reset release, split address/data writes, read/write response backpressure,
  register values, interrupt assertion/clear, and recovery after board/debug
  reset and simulated lock loss while idle.
- The reset-release check accounts for the UNISIM VHDL FDRE model's 100 ps
  clock-to-output delay; it does not require zero-delay behavioral flops.
- Post-route checks verify clock periods, hash-domain slack, both IRQ
  synchronizer attributes, and positive stage-to-stage synchronizer timing.

Hashing remains **527 cycles per nonce per lane**. Expected throughput is
`3 * 210,000,000 / 527 = 1,195,446 H/s`, about **1.195 MH/s**, before batch/job
overhead: 5% above the three-lane 200 MHz build. This is not a board or
pool-effective hashrate measurement.

## Routed results

| Metric | Three lanes, 200 MHz (HW 1.0.0) | Three lanes, 210 MHz (HW 1.1.0) |
|---|---:|---:|
| LUTs / 16,320 | 13,255 (81.22%) | **13,284 (81.40%)** |
| Flip-flops / 32,640 | 16,534 | **16,603 (50.87%)** |
| DSP48E2 / 48 | 33 | **33 (68.75%)** |
| BRAM tiles / 48 | 17.5 | **17.5 (36.46%)** |
| MMCM / 2 | 1 | **2** |
| Overall setup WNS | +0.059 ns | **+0.082 ns** |
| Overall hold WHS | +0.010 ns | **+0.010 ns** |
| Hash-domain WNS | +0.535 ns | **+0.413 ns** |

The change costs 29 LUTs, 69 flip-flops, and one MMCM in this routed build.
All specified setup/hold constraints pass with zero failing endpoints.

| Domain | Frequency | Setup WNS |
|---|---:|---:|
| Hash | 210 MHz | **+0.413 ns** |
| HyperBus | 200 MHz | **+0.841 ns** |
| MicroBlaze / AXI | 50 MHz | **+11.125 ns** |
| HyperRAM receive | 200 MHz, existing 90-degree phase | +3.953 ns |
| Delay reference | 300 MHz | +1.972 ns |
| MII RX | 25 MHz | +8.784 ns |
| MII TX | 25 MHz | +22.644 ns |
| Debug DRCK | 30 MHz | +15.246 ns |
| Debug UPDATE | 15 MHz | +30.720 ns |

The global +0.082 ns WNS is the existing external HyperRAM DQ routing
budget. The internal receive-to-HyperBus crossing has +0.087 ns slack.
These remain small margins, and the calibrated external interface still
requires board validation; this is not complete external-interface STA signoff.

The interrupt synchronizer stage-to-stage path has +19.340 ns slack. The
first run without its new asynchronous-input exception incorrectly treated
the IRQ input as a synchronous 210-to-50 MHz path and reported -0.792 ns.
The final build includes the narrowly scoped exception, not a broad waiver.

## Rebuild

For an existing project:

```sh
vivado -mode batch -source scripts/configure_hash210.tcl
make test
make test-hybrid
make test-clock210
make synth
vivado -mode batch -source scripts/configure_three_lane_impl.tcl
make implement
vivado -mode batch -source scripts/report_hybrid.tcl
vivado -mode batch -source scripts/report_hash210.tcl
vivado -mode batch -source scripts/check_final.tcl
make images
```

Fresh `make bd` projects also source `scripts/hash_clock_210.tcl`, so they
contain the same clock/reset topology. The implementation retains
`Performance_ExplorePostRoutePhysOpt`. These commands never program hardware.

The previous 200 MHz version 1.0.0 image/checkpoint/reports are preserved in
`build/three_lane_v1_0_0/`. See [the 200 MHz report](three_lane_build.md)
for its baseline results.

## Packaged image and evidence

`make images` completed at 07:19 PDT on 2026-09-09. The combined
`build/images/scu35_flash.mcs` was verified byte-for-byte against its PDI and
application payloads. Bootloader ELF and application SREC are byte-identical
to the preceding 1.0.0 software artifacts.

| Payload | Offset | Bytes | SHA-256 |
|---|---:|---:|---|
| FPGA + bootloader PDI | `0x00000000` | 1,168,960 | `099a3ebb51c6de15d7b142fb2082d535a01130705cceea5a621a5cca72caa91c` |
| Application SREC | `0x00800000` | 578,340 | `92940e70761b080b48966923313eca77ed076b74b9a9612439f5e2a194a2dc3b` |

Image, checkpoint, and reports are preserved in `build/three_lane_v1_1_0/`.
No QSPI programming, reboot, EEPROM change, or remote Git push was performed.

Final DRC contains no errors or critical warnings; existing combinational
DSP pipeline advisories, unused-net, and STARTUP warnings remain. The
generated SYSMON pin-IOSTANDARD constraint warnings during implementation
are unchanged from earlier builds. Bus-skew checks pass.

Evidence: `logs/configure_hash210.console.log`, `logs/tests_hash210.log`,
`logs/xsim_hash210.log`, `logs/test_hash210_clocking.console.log`,
`logs/synth_hash210.log`, `logs/implement_hash210_final.log`,
`logs/route_timing.rpt`, `logs/route_utilization.rpt`,
`logs/report_hash210.console.log`, `logs/hash210_miner_timing.rpt`,
`logs/hash210_clocks.rpt`, `logs/hash210_exceptions.rpt`,
`logs/hash210_clock_interaction.rpt`, `logs/report_hash210_dsp.console.log`,
`logs/images_hash210.log`, and `logs/final_audit_hash210_packaged.console.log`.
