# Validation and board bring-up

## Current deployment: power telemetry, 2026-09-10

Hardware 1.2.0, application/dashboard 1.1.0, bootloader 1.0.0 are the current
power-telemetry release. QSPI erase, blank check, programming and read-back
verification passed on SCU35 cable `52041A454A5TA`; the FPGA then booted from
flash. Network telemetry confirmed three lanes, CPU 50 MHz, pool authorization,
and approximately 1.139 MH/s. Both INA700 monitors reported valid data with
zero read errors: about 0.60 W internal 5 V and 0.20 W VCCINT while mining.
These rail powers are not additive and are not wall-plug measurements.

The initial observation reported no miner hardware errors. The UART bridge
was unavailable; application/version/power verification used UDP telemetry.
This is a deployment smoke test, not a long-duration stability or independent
power-calibration test. No EEPROM settings were changed.

See [power telemetry](power_telemetry.md) for circuitry, register conversions,
tests, timing/utilization, image hashes, logs and rebuild instructions.
The sections below retain historical fabric bring-up results; see also
[hybrid validation](hybrid_dsp48.md) for earlier hybrid revisions.

## Fabric implementation completed on 2026-09-09

- Vivado 2026.1 BD validation, address/clock/reset audit, synthesis, placement,
  routing, DRC, CDC inspection, bitstream, and normal SpartanUP PDI generation.
- MicroBlaze: 50 MHz; shared local instruction/data memory: exactly 16 KiB.
  Two fabric engines: 200 MHz. HyperRAM receive clock retains its 90° phase.
- Routed utilization: 11,281 LUTs (69.12%), 13,379 FFs, 17.5 BRAM tiles,
  3 DSP48E2s. Reports are `logs/route_*.rpt`.
- All specified setup/hold/pulse-width constraints pass. Worst reported setup
  slack is 0.019 ns, hold 0.010 ns. The 200 MHz internal clock group has
  0.856 ns setup slack. See the report for individual constrained paths.
- No unconstrained internal endpoints. MII uses the DP83867IR 100-Mbit timing
  bounds with a 0.5 ns board-skew allowance. HyperRAM DQ routing budgets match
  the selected controller reference. **This is not a full external-interface
  timing signoff:** seven inputs and ten outputs still lack conventional I/O
  delays, covering slow/asynchronous control and the calibrated HyperRAM PHY.
  Runtime calibration and board validation are required; fixed untrained
  HyperRAM input delays are deliberately not invented.
- Routed DRC has no errors or critical warnings. Remaining warnings are the
  vendor STARTUP3 KEYCLEARB/TEMPER_FABRIC_B connection and unused internal nets.
  Generated SysMon constraints additionally warn about applying IOSTANDARD
  to internally tied-off VP/VN pins; all actual package ports have explicit
  I/O standards/locations. These vendor warnings have not been suppressed.
- Detailed CDC report has four reset fan-out warnings into EthernetLite's
  four-stage synchronizers and one reset-combination warning into the receive
  clock reset controller's four-stage filter. No custom mining datapath CDC is
  marked unsafe. The vendor reset warnings remain visible for review.
- Bare-metal loader links at 14,552 bytes including BSS and 2 KiB stack.
  FreeRTOS ELF links in 8 MiB HyperRAM with a 2 MiB RTOS heap. SREC checker
  confirms record checksums, address bounds, all four vector stubs, and entry
  at 0x80000000. SHA-256 manifest accompanies packaged files.
- Both BIT and RCDO are independently patched with the loader ELF. Bootgen
  regenerates PDI from Vivado's BIF structure and PLM. Combined MCS is checked
  byte-for-byte: PDI at zero, ASCII SREC at 8 MiB.

The first imported crossbar retained disabled M05..M08 decoder windows. This
was detected from routed unused I²C/MDIO input warnings, corrected explicitly,
and added to the BD audit. The final build includes functioning decoder windows;
the unused input warnings are gone. Early resource/timing reports from before
that correction are not final results.

## Automated tests

Run `make test`; results are in `logs/tests.log` for this build.

- Two-engine AXI register/job/result/IRQ regression.
- Known Bitcoin genesis SHA256d, equal-target acceptance, target-minus-one
  rejection, difficulty-one acceptance, stop/drain/restart without stale results.
- PHY reset hold/reassertion and IRQ synchronizer behavior.
- SREC length/checksum/type rejection.
- EEPROM save interruption at every byte boundary; old record survives until
  new commit, factory prefix unchanged, bad MAC/string rejection.
- Exact integer targets against Python decimal-ratio arithmetic, including
  fractional, large, scientific-notation, saturation, and randomized cases.
- Software SHA256d against hashlib at padding/block boundaries; header and
  Merkle assembly with an independent Python calculation; genesis known hash.
- Typed coreJSON parsing, array lookup, numeric overflow and unsafe strings.
- Dashboard configuration validation and loopback UDP/TCP mock-device tests.
- Actual Ethernet interface receive routine with mocked MMIO/driver: oversized
  and undersized IPv4 packets are rejected before copying; full-MTU and ARP
  packets have their FCS allowance removed. Address/undefined-behavior sanitizers
  are enabled for this and the EEPROM/SREC C regression.

These tests do **not** simulate the full FreeRTOS network stack on MicroBlaze or
a real pool session. On-board calibration, DHCP, and telemetry have now been
observed as described below. Accepted pool shares, temperature accuracy against
an external reference, and actual hash rate have not yet been measured.
The one compiler warning is in the unchanged AMD port's intentional `_stack - 2`
linker-symbol arithmetic. Project-owned C builds without warnings.

## First physical bring-up

UART bridge: `10.0.1.109:2323`. RAM-loaded testing found and addressed:

- STARTUP needs a discarded initial SPI transfer (also present in AMD
  `XSpi_CfgInitialize`, CR #721229). Subsequent JEDEC ID is `20bb18`.
- The calibration helper reads CR0 before tuning; the observed resulting
  `bfff` selected four-clock latency, inconsistent with the controller's
  seven-clock setting. The loader now explicitly writes/readback-checks
  `bf2f` after calibration: seven-clock base latency, fixed 2x, 46-ohm drive,
  normal operation, reserved ones, and 32-byte wrapped bursts.
- Data-cache-enabled heap allocation initially stalled on a HyperRAM access.
  The first working image left the data cache disabled as a workaround.
  The subsequent patched, cache-enabled image is described below.
- The installed SDT MicroBlaze FreeRTOS port configures INTC but omits its
  real-mode start. The timer hook now calls `XStartInterruptCntrl`: MER reads
  `3`, RTOS ticks advance at approximately 100 Hz, and network tasks run.

With these changes loaded into RAM, the board acquired DHCP address
`10.0.1.227` and answered dashboard discovery/subscriptions with 50 MHz CPU,
two engines, and temperature near 37 degrees C. See `logs/uart_resume.log`.
No mining credentials have been installed by this debug session.

The fixes were then packaged, flashed, and verified at 03:10 PDT on
2026-09-09 (`logs/program_remote_flash_fixed.log`). A JTAG-triggered FPGA
reboot loaded the PDI and SREC from QSPI, without downloading either ELF.
UART confirmed calibration window `1..118`, midpoint `8c`, CR0 `bf2f`,
JEDEC ID `20bb18`, `Jump 80000000`, application startup, and `Network up`.
Dashboard subscriptions again reported `10.0.1.227`, 50 MHz, and approximately
37 degrees C; evidence is in `logs/discovery_flash_boot.jsonl` and
`logs/uart_resume.log`. This verifies warm FPGA reconfiguration from flash;
a physical power-cycle and long-duration/pool stress test remain outstanding.

Tested payload SHA-256 values:

- PDI: `875f682b1b3dd35899844742f1415f544bc34b34422f42d38a4fd11fb1c4d36a`
- SREC: `88d7faa336047c5f1aa08351d43caca3f51e9ffcb8441c7b2c84e4777a16da47`

## HyperBus patch and cache-enabled flash boot

On 2026-09-09 at 03:38 PDT, the local WREADY fix was rebuilt through
synthesis, implementation, and image packaging, then programmed and verified
on SCU35 cable `52041A454A5TA`. The other JTAG board was untouched. Route
setup/hold slack is +0.019/+0.010 ns; the MicroBlaze remains at 50 MHz.
The focused regression fails on the original RTL and passes on the patch;
both full controller simulations and `make test` pass.

The FPGA was rebooted from QSPI without an ELF download. UART recorded
HyperRAM calibration window `1..116`, midpoint `8b`, CR0 `bf2f`, SREC jump,
existing EEPROM settings, and network startup. JTAG recorded MSR `0x1a6`,
explicitly decoding DCE=1 and ICE=1, advancing RTOS ticks, and eight tasks.
Dashboard telemetry at `10.0.1.227` recorded `pool_authorized` and
`mining_job_received`. No credentials were rewritten. This is a successful
cache-enabled startup test, not a multi-day soak or accepted-share test.

Evidence: `logs/program_remote_flash_cache_fix.log`,
`logs/boot_remote_cache_fix.log`, `logs/uart_cache_fix.log`,
`logs/network_state_cache_fix.log`, and `logs/discovery_cache_fix.jsonl`.
The previous working image is retained in `build/cache_rollback.eaIRBy/images`.

Tested payload SHA-256 values:

- PDI: `a34c9f81b1fdeda0beb02977064691823c47a28154c1beddf573f082e46d3bdd`
- SREC: `1f343f34381b064c1722cca74a9f5e331db44ebe2d0ce50855479587e280af15`

The generated manifest's `hardware_tested: false` remains conservative: it
does not certify an end-to-end miner/pool test. The scoped checks above are
the record of what has actually been exercised on hardware.

On 2026-09-09, the user supplied `10.0.1.109:3121` and explicitly authorized
overwriting the SCU35 flash without backup. Cable `52041A454A5TA`, device
`xcsu35p_0`, was checked before programming. The separate Zynq target was not
programmed. Vivado's embedded programmer detected QSPI ID `20bb18`, density
16 MiB; erase, blank check, programming, and verification all passed.
See `logs/program_remote_flash.log` and `scripts/program_remote_flash.tcl`.
The image was `build/images/scu35_flash.mcs`, containing the PDI at zero and
application SREC at 8 MiB. Previous contents were overwritten and no backup
was made. That initial operation left the FPGA running the flash programmer;
the subsequent debug/fixed-image boot results are recorded above.

For the remaining bring-up, provide the SCU35 UART connection or follow this
checklist (step 1 programming/verification is already complete):

1. Confirm board revision/pinout and its actual QSPI memory part. Back up any
   existing flash image. Program and verify `build/images/scu35_flash.mcs`
   through Vivado Hardware Manager. Use QSPI boot mode and power-cycle.
2. Open the e_uart serial connection at 115200 baud, 8N1. Expect the 50 MHz
   loader banner, HyperRAM passing window/midpoint, flash JEDEC ID, and
   `Jump 80000000`. A validation failure must print `Boot failed` and stop.
3. Confirm application banner and selected MAC, then a DHCP address on the
   router. Test power-up without DHCP/cable and subsequent recovery. If PHY
   MDIO is unavailable on the board revision, verify strapped MII operation;
   telemetry intentionally reports `phy_known: false` in this case.
4. Start the dashboard. Confirm discovery, stable temperature updates, and
   expiry/re-establishment after closing/reopening the dashboard. Use a
   directed broadcast argument if the machine has multiple interfaces.
5. Save a unique MAC and pool settings. Confirm success reply/readback. Check
   pool reconnection, then reboot and confirm the new active MAC and retained
   credentials. Ensure another board is not using the fallback MAC.
6. Confirm subscription, authorization, job reception, and eventually accepted
   shares with a pool that permits sufficiently low difficulty. A lottery miner
   may take a long time to submit a share at ordinary pool difficulty; do not
   treat short-term absence of submissions as proof of failure. CPU rechecks
   every hardware candidate before submission.
7. Exercise changing jobs/credentials, pool rejection/disconnect, expired
   subscription, malformed/oversized messages, lease renewal and power-cycle.

Full FPGA reboot from the dashboard is currently unsupported. The design has a
PMC bridge, but no verified remote reconfiguration API is enabled. Use the board
PROGRAM_B control/power-cycle; a jump to application code is not an FPGA reboot.

## References

- [AMD SCU35 board guide](https://docs.amd.com/r/en-US/ug1713-scu35-eval-bd).
- [TI DP83867IR datasheet, sections 6.12–6.15](https://www.ti.com/lit/ds/symlink/dp83867ir.pdf).
- HyperBus dependency `doc/theory_of_operation.md` and its reference XDC.
- Installed AMD `xsysmon_hw.h`/`xsysmon.h`: UltraScale temperature offset 0x400
  and conversion differ from the 7-series defaults in legacy SDT macros.
