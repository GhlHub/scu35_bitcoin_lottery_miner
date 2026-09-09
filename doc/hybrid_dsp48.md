# Hybrid LUT/DSP48E2 miner

This variant retains two engines, their 200 MHz clock, the 50 MHz MicroBlaze,
and the existing AXI register map, interrupts, reset wiring, and firmware.
It is implemented and simulation/timing validated. The running SCU35 was
updated to this variant at 05:36 PDT on 2026-09-09; startup results are below.
The subsequent deployed [telemetry revision](telemetry.md) adds completion
counting and measures approximately 0.759 MH/s. The comparison below records
the original hybrid build before that counter was added.

## Datapath

`EXPLICIT_DSP_SCHEDULE=1` selects the Spartan UltraScale+ hybrid path.
Each engine uses five explicit DSP48E2 slices as modulo-2^32 adders:

- two partial message-schedule sums;
- the final message-schedule sum;
- the partial T1 sum, registered in phase 1;
- the final T1 sum in phase 2.

Boolean functions, rotates, state-update additions, and digest feed-forward
remain in fabric. SHA compression uses four phases per round instead of five.
Registering the partial T1 sum one phase early avoids a three-adder cascade.
The DSPs have no internal pipeline registers; the SHA registers define the
schedule. `dsp48e2_add32.sv` selects A:B plus C with OPMODE `000110011`,
ALUMODE zero, multiplier disabled, and truncates the result to 32 bits.

The original fabric schedule remains selectable with
`EXPLICIT_DSP_SCHEDULE=0`; no DSP58 primitives are instantiated.

## Simulation

`make test` tests both variants with Verilator, including Bitcoin genesis,
target boundaries, abandoned jobs, and two-engine AXI results. Verilator uses
an explicit functional addition model only for the DSP wrapper.

`make test-hybrid` uses Vivado XSIM and the real AMD UNISIM DSP48E2 model,
not that functional fallback. It checks 1,032 addition vectors including
overflow and the A:B split boundary, compares 32 compression blocks and
arbitrary initial states against the baseline, and reruns genesis/AXI tests.
Testbench completion markers and fatal errors are checked explicitly.

Measured single-nonce latency is 527 cycles versus 655 for the fabric path.
Consecutive-nonce tests also measure 2,108 versus 2,620 cycles for four nonces,
confirming the same steady-state interval without per-nonce host commands.
At 200 MHz, two engines imply 759,013 hashes/s versus 610,687 hashes/s,
a 24.29% improvement before job-switching/software overhead. This is a
cycle-derived estimate, not measured pool throughput.

## Routed comparison (Vivado 2026.1, 2026-09-09)

| Metric | Board-tested fabric | Local hybrid |
| --- | ---: | ---: |
| Engines / miner clock | 2 / 200 MHz | 2 / 200 MHz |
| Cycles per nonce | 655 | 527 |
| Calculated combined MH/s | 0.6107 | 0.7590 |
| LUTs | 11,281 (69.12%) | 11,271 (69.06%) |
| Registers | 13,379 | 13,469 |
| DSP48E2s, including CPU | 3 | 13 |
| BRAM tiles | 17.5 | 17.5 |
| Worst setup slack | +0.019 ns | +0.018 ns |
| Worst hold slack | +0.010 ns | +0.002 ns |

All specified setup/hold/pulse-width constraints pass. The 200 MHz internal
clock group has +0.691 ns setup slack. This is a speed improvement, not a
meaningful LUT reduction. External calibrated HyperRAM timing retains the
limitations described in [validation.md](validation.md).

DRC has no errors or critical warnings. In addition to the original two
warnings, the hybrid adds 30 DSP input-pipeline and 10 output-pipeline warnings:
the active ALU is intentionally combinational between external SHA registers.
Twenty advisory messages concern power optimizations for the unused D/multiplier
path. These messages have not been suppressed; the selected datapath passes
post-route timing and functional UNISIM tests. The primitive configuration is
described in [AMD UG1704](https://docs.amd.com/r/en-US/ug1704-spartan-ultrascaleplus-libraries/DSP48E2).

Evidence: `logs/tests_hybrid.log`, `logs/tests_hybrid_xsim.log`,
`build/sim/hybrid_xsim/*.simulate.log`, `logs/route_timing.rpt`,
`logs/route_utilization.rpt`, and `logs/route_drc.rpt`.
Hardware startup is now verified as described below. Pool throughput,
accepted shares, and long-duration stability remain unverified.

## Packaged image

`make images` completed at 04:02 PDT on 2026-09-09. The generated
`build/images/scu35_flash.mcs` contains the hybrid FPGA/bootloader PDI at zero
and the unchanged, cache-enabled application SREC at `0x00800000`.
`verify_mcs.py` confirmed both payloads byte-for-byte. The image was subsequently
flashed and booted with user authorization as recorded below.

- PDI: 1,168,128 bytes, SHA-256
  `e2ffae2511c3fa5a46111c3b72e67b0836145d93a508df8c82c2b494af3255f6`.
- SREC: 564,052 bytes, SHA-256
  `1f343f34381b064c1722cca74a9f5e331db44ebe2d0ce50855479587e280af15`.

Image-generation evidence is in `logs/images_hybrid.log`; the final current-run
and BD audit is in `logs/final_audit_hybrid.console.log`.

## QSPI update and startup verification

At 05:36 PDT on 2026-09-09, the image above was programmed and readback-verified
on SCU35 cable `52041A454A5TA` at `10.0.1.109:3121`. The FPGA was then rebooted
from QSPI without downloading an ELF. No other JTAG target or EEPROM settings
were modified.

UART confirmed HyperRAM calibration window `1..118`, midpoint `8c`, CR0 `bf2f`,
SREC jump to `80000000`, existing EEPROM settings, and network startup.
JTAG confirmed MSR `0x1a6` (instruction and data caches enabled). Dashboard
telemetry reported 50 MHz CPU, two engines, IP `10.0.1.227`, `pool_authorized`,
and `mining_job_received`. This is a startup/connectivity test, not a measured
hashrate or multi-day stability test.

Evidence: `logs/program_remote_flash_hybrid.console.log`,
`logs/boot_remote_hybrid.console.log`, `logs/uart_hybrid_flash.log`,
`logs/network_state_hybrid_flash.log`, and `logs/discovery_hybrid_flash.jsonl`.

## Rebuild or switch variants

The subsequent [ten-DSP-per-engine evaluation](dsp10_evaluation.md) records
the current local build and compares it against the deployed telemetry image.

Fresh `make bd` projects now select three lanes with ten DSPs per lane. To
select five DSPs per lane in an existing project (retaining three lanes):

```sh
vivado -mode batch -source scripts/configure_hybrid.tcl \
  -log logs/configure_hybrid.log -journal logs/configure_hybrid.jou -tclargs 1 0
make synth
make implement
vivado -mode batch -source scripts/report_hybrid.tcl \
  -log logs/report_hybrid.log -journal logs/report_hybrid.jou -tclargs 15
```

Use `-tclargs 0` to select the original fabric schedule, or `-tclargs 1 1` for
ten DSPs per engine. The report script defaults to expecting thirty miner DSPs;
the explicit `-tclargs 15` above checks five DSPs on each of three lanes.
It also checks setup/hold timing. No command above programs hardware.
Prior fabric reports and flash images are preserved locally under
`build/fabric_baseline/` and are not checked into Git.
