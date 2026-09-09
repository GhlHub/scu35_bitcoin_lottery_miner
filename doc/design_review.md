# SCU35 hardware review

This records the original design choice and review. The user approved the BD
on 2026-09-09. Implementation/firmware/dashboard are now built; current measured
results and remaining physical tests are in [validation.md](validation.md).
The subsequent four-phase DSP48E2 variant is described in
[hybrid_dsp48.md](hybrid_dsp48.md); the resource estimates below are historical.
The current [three-lane build](three_lane_build.md) retains these clocks,
resets, and peripheral addresses, and adds [component versions](versions.md).
The subsequent [hardware 1.1.0 experiment](hash210_build.md) was withdrawn.
Current source again shares the 200 MHz clock/reset between hashing and
HyperBus; see the [restoration report](restored200_build.md).

## Resource choice

Vivado's part database reports 16,320 LUTs, 48 DSPs, and 48 BRAM tiles for
`xcsu35p-sbvb625-2-e`. AMD's
[product table](https://www.amd.com/en/products/adaptive-socs-and-fpgas/fpga/spartan-ultrascale-plus.html)
also lists the device as approximately 16K LUTs and 48 DSP slices.

The VEK280 reference README reports 81,595 LUTs for its 32-engine fabric OOC
block (about 2,550 LUTs per engine including shared control), and 78,491 LUTs
plus 96 DSP58s for its older five-phase explicit-DSP variant. Its newer
four-phase DSP experiment uses five DSP58s per engine. These are Versal
measurements; they are not SCU35 synthesis results.

An existing local SCU35 HyperBus reference placed report under
`/raid/work/hyperbus_ai3/vivado_projects/hyperbus_test_proj/hyperbus_test_proj.runs/impl_1/`
reports 6,169 LUTs, 17.5 BRAM tiles, and 5 DSPs for that reference system.
It predates this integration and excludes the new mining/network peripherals.

Two fabric engines budget approximately 5,100 LUTs. Reserving roughly
2,000-4,000 additional LUTs for EthernetLite, IIC, SysMon and extra interconnect
gives a preliminary whole-system estimate of 13,300-15,300 LUTs. This is a
planning estimate with limited margin, not evidence of fit. Two engines is
the initial selection; synthesis after review will determine whether to
retain it, reduce to one engine, or port arithmetic to DSP48E2.

SU35P uses DSP48E2 rather than Versal DSP58, so explicit DSP58 instances are
not selected. The current core uses five clocks per SHA round, two
compressions per nonce, plus launch/comparison overhead. Simulation measured
655 cycles from a single-engine start to done. Two engines at 200 MHz suggest
approximately 0.61 MH/s before software/job-change overhead, conditional on
timing closure. The 200 MHz target does not change the 50 MHz CPU clock.

## Clock and reset review

| Clock wizard output | Frequency | Consumers |
| --- | --- | --- |
| clk_out1 | 200 MHz | HyperBus engine, miner, miner side of AXI converter |
| clk_out2 | 200 MHz, +90 degrees | HyperRAM read sampling |
| clk_out3 | **50 MHz** | MicroBlaze, local BRAM control, AXI peripherals, IRQ synchronizer |
| clk_out4 | 300 MHz | IDELAYCTRL reference |
| clk_out5 | 200 MHz, BUFGCE gated | HyperRAM forwarded CK only |

The board active-low reset enters `reset_gen/axi_clk_reset_gen`. Its
active-low peripheral reset cascades into the other three reset controllers.
MMCM `locked` reaches all four controllers. JTAG `Debug_SYS_Rst` now reaches
all four controllers, including the MicroBlaze domain. Auxiliary resets are
explicitly configured active-low and tied high. The clock wizard reset is
tied inactive so the domain reset synchronizers retain running clocks.

The 50 MHz controller supplies MicroBlaze's active-high reset, the LMB
active-high bus reset, and distinct active-low interconnect/peripheral resets.
The 200 MHz controller supplies HyperBus/miner reset; the +90-degree
controller supplies IDDRE1 reset; the 300 MHz controller supplies IDELAYCTRL
reset. No reset synchronizer is clocked by the gated HyperRAM CK output.
The controller's `o_hb_clk_ce` drives the wizard's `clk_out5_ce`.

EthernetLite's PHY reset output passes through a counter that holds the
external PHY reset low for at least 500,000 CPU clocks (10 ms), including
after subsequent resets. The result IRQ crosses through two synchronizer
flip-flops into the 50 MHz domain; AXI transactions use an AXI clock converter.

The audit script verifies connectivity across hierarchy, reset polarities,
the 16 KiB instruction/data mappings, CPU frequency, and the engine count.
Hardware timing/CDC reports still require the post-review implementation.

## Address map and interrupt routing

| Peripheral | Base | Range | Interrupt bit/type |
| --- | --- | --- | --- |
| Local boot BRAM | 0x00000000 | 16 KiB | — |
| HyperBus control | 0x00010000 | 64 KiB | — |
| PMC bridge | Fixed 0x040xxxxx / 0x041xxxxx windows | Per hardware map | — |
| EEPROM IIC | 0x40800000 | 64 KiB | 4, level-high |
| EthernetLite | 0x40E00000 | 64 KiB | 3, rising edge |
| AXI interrupt controller | 0x41200000 | 64 KiB | To MicroBlaze |
| FreeRTOS AXI timer | 0x41C00000 | 64 KiB | 1, level-high |
| QSPI through STARTUP | 0x44A00000 | 64 KiB | 2, rising edge |
| e_uart | 0x44A10000 | 64 KiB | 0, level-high |
| SysMon | 0x44A20000 | 64 KiB | 5, level-high |
| Two-engine miner | 0x44A30000 | 4 KiB | 6, level-high |
| HyperRAM | 0x80000000 | 8 MiB | — |

The interrupt controller's edge mask is `0x0C`, following AMD's Quad SPI and
EthernetLite interface metadata. Miner interrupts must remain level-high.

## Mining conventions and verification

Midstate and header-tail registers retain the VEK280 big-endian SHA word
convention. Nonce start/results likewise represent the SHA message word;
software must byte-swap to obtain the conventional Bitcoin nonce integer
when reconstructing or submitting a header. All possible serialized nonce
words are still covered by the stride scan.

The imported reference compared the raw SHA256d digest as a big-endian
integer. Bitcoin instead interprets those digest bytes as a little-endian
integer. The local engine now reverses the bytes only for target comparison;
the raw first-pass digest remains intact for the second SHA compression.
The genesis test reproduced a rejection before this correction, then passed
at the exact hash target, rejected at one less, and accepted at difficulty 1.
The original VEK280 source has not been modified.

The two-engine AXI regression covers register access, job submission, nonce
results and result IRQ/acknowledgement. The reset regression covers minimum
PHY hold time, repeated reset, asynchronous assertion, and IRQ synchronization.
These tests do not yet cover the complete Stratum job-switching lifecycle.

## Original work plan following the review checkpoint

Items 1–5 are now implemented, except remote FPGA reboot is deliberately not
enabled. Item 6 (physical-board verification) remains. The statements below
describe the pre-synthesis checkpoint, not the current build status.

1. Synthesize, inspect actual resource usage and timing, complete board-level
   HyperRAM/MII timing constraints and CDC checks, implement and export XSA.
   The current XDC establishes pin assignments; it is not a completed timing signoff.
2. Adapt the bare-metal HyperBus bootloader to fit entirely within 16 KiB.
   The upstream example reserves addresses beyond this limit and cannot be
   copied unchanged. Calibrate HyperRAM before loading, bound-check/checksum
   S-records, preserve the running bootloader, install application exception
   vectors at low memory, and transfer to HyperRAM only after verification.
   Preserve the Spartan UltraScale+ `spartanup` PDI packaging workflow.
3. Build the application with the pinned FreeRTOS 202604-LTS kernel and TCP
   stack. Port EthernetLite interrupts/buffers and the MicroBlaze timer/port.
   Read and validate EEPROM settings before initializing networking; use
   `02:00:00:11:22:33` when no valid stored MAC exists, then start DHCP.
4. Define a versioned EEPROM record with CRC and power-failure-safe updates
   for MAC and pool/worker/password settings, respecting board data already
   stored in the EEPROM. Port and test Stratum subscription/authorization,
   job handling, exact share targets, stale-result handling and submission.
5. Implement LAN discovery and the Python dashboard, configuration updates,
   live job/share/temperature telemetry, and a renewable dashboard-presence
   subscription. Investigate a full FPGA reboot through the platform's
   supported reconfiguration path; do not label a CPU reset as an FPGA reboot.
6. Verify the complete boot, DHCP, discovery, persistence and pool flow on hardware.

Board reference: [AMD SCU35 user guide UG1713](https://docs.amd.com/r/en-US/ug1713-scu35-eval-bd).
