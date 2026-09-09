# SCU35 Bitcoin lottery miner

Target: AMD SCU35, `xcsu35p-sbvb625-2-e`, Vivado/Vitis 2026.1.
Requirements are in [initial_prompt.txt](initial_prompt.txt); MicroBlaze is
fixed at **50 MHz** by the subsequent user instruction.

## Build status

The current **three-lane, hardware 1.0.0** configuration has been restored:
hashing and HyperBus share **200 MHz**, and MicroBlaze remains at **50 MHz**.
Expected throughput is **1.139 MH/s** before job-change overhead.
The 210 MHz experiment was withdrawn at the user's request.
See the [restored 200 MHz build](doc/restored200_build.md) and
[component versions](doc/versions.md). This build was QSPI-programmed,
readback-verified, and rebooted on 2026-09-09. Three lanes, pool authorization,
and approximately **1.139 MH/s measured throughput** were confirmed at
`10.0.1.227`, with zero hardware errors during the initial observation.
Utilization is 13,255 LUTs, 16,534 registers, 33 DSPs, and 17.5 BRAM tiles;
hash-domain WNS is +0.535 ns and overall WNS is +0.059 ns.
The board-testing history below describes earlier two-lane images.

Hardware, bootloader, FreeRTOS application, and Python dashboard are implemented
and built. The user approved the block-design/reset review on 2026-09-09.
Synthesis, routing, image generation, and automated tests pass. The SCU35 on
`10.0.1.109:3121`, cable `52041A454A5TA`, was flashed and readback-verified on
2026-09-09. Bring-up has demonstrated HyperRAM calibration, application startup,
FreeRTOS ticks, DHCP, dashboard discovery/temperature telemetry, pool
authorization, and mining-job reception with both caches enabled. Accepted
shares and long-duration stability have not yet been verified.

The board-tested fabric design uses 11,281/16,320 LUTs (69.12%), 13,379 registers,
17.5/48 BRAM tiles, and 3/48 DSPs. Both mining engines use fabric; the DSPs belong
to the processor. Mining runs at 200 MHz, with approximately 0.61 MH/s theoretical
combined throughput before job-switching overhead, not a measured pool hash rate.
All specified timing constraints pass for that build; calibrated external HyperRAM timing still
requires board testing. See [validation and limitations](doc/validation.md).

The design contains:

- MicroBlaze at 50 MHz, exactly 16 KiB local instruction/data BRAM, instruction
  and data caches for the 8 MiB HyperRAM at `0x80000000`. Both caches are
  enabled. After the local HyperBus WREADY fix, flash boot, network startup,
  and pool authorization passed on-board with write-back caching enabled;
  long-duration validation remains outstanding.
- GhlHub HyperBus controller 1.3, e_uart 1.1, AXI IIC for the board EEPROM,
  EthernetLite with MDIO and ping-pong buffers, AXI timer, AXI interrupt
  controller, AXI SysMon, AXI Quad SPI using STARTUP, and PMC bridge.
- Three VEK280-derived SHA256d engines at 200 MHz, asynchronous AXI clock conversion,
  and a separate synchronizer for the level-sensitive result interrupt.
- Explicit reset wiring in four continuously running clock domains and a
  10 ms minimum PHY reset hold at 50 MHz.

See [design review](doc/design_review.md) for resource estimates, the address
map, reset details, and byte-order conventions.

## Hybrid DSP48E2 variant

Current source selects **three hash lanes**, ten DSP adders per lane, with
independent hardware/bootloader/application/dashboard versions starting at
**1.0.0**. The withdrawn hardware 1.1.0 experiment is no longer selected.
See [component versions](doc/versions.md). MicroBlaze remains at 50 MHz;
HyperBus and mining share 200 MHz. The two-lane results below are historical;
the board now runs the three-lane image described above.

The earlier deployed four-phase hybrid LUT/DSP48E2 implementation uses five DSP adders
per engine. The preceding two-lane evaluation maps five more additions into DSPs,
for ten per engine; it does not update the board. Both measure **527 cycles per nonce**,
versus 655 for the original fabric implementation: approximately **0.759 MH/s**
combined at 200 MHz, a 24.3% improvement before software/job-change overhead.
The MicroBlaze remains at 50 MHz. This variant was flashed, readback-verified,
and booted on 2026-09-09; pool authorization and job reception passed with
both caches enabled. Routed timing passes; utilization is 11,271 LUTs (69.06%),
13,469 registers, 13 DSP48E2s, and 17.5 BRAM tiles.
See [hybrid implementation and validation](doc/hybrid_dsp48.md)
for timing/resource results, tests, and how to select the fabric baseline.
The subsequent two-lane hardware-counter/telemetry update reported
approximately **0.759 MH/s measured device throughput**. Its utilization is
11,304 LUTs (69.26%), 13,478 registers, and 13 DSPs, with timing passing.

The local ten-DSP-per-engine evaluation routes at **11,214 LUTs (68.71%),
13,490 registers, and 23 DSPs**: 90 fewer LUTs for ten additional DSPs.
Miner setup slack is +0.552 ns; overall WNS is +0.001 ns on a HyperRAM
clock crossing. Throughput is unchanged. See the
[ten-DSP evaluation](doc/dsp10_evaluation.md) for the comparison and tests.
This evaluation has not been packaged or flashed.

## Ready-built files

These files are generated locally by the build flow below and are not checked
into Git. Dependency checkouts and tool logs are also excluded.

- `build/images/scu35_flash.mcs`: combined flash programming image.
- `build/images/scu35_bootloader.pdi`: FPGA image with the bare-metal loader in BRAM.
- `build/images/miner.srec`: application S-record text, including low vectors.
- `build/images/{bootloader,miner}.elf`: debug symbols/executables.
- `build/images/manifest.json`: offsets, byte sizes, SHA-256 checksums.

Flash layout: PDI at `0x00000000`, raw ASCII `miner.srec` at `0x00800000`.
The combined MCS has been checked byte-for-byte against both payloads. The
application entry is `0x80000000`; the loader installs vectors at 0, 8, 16, and
32 only after validating the image. The loader occupies 14,552 bytes including
its BSS and reserved 2 KiB stack, within the 16 KiB local memory.

Use Vivado Hardware Manager with the configuration-memory part appropriate to
your board revision. Back up existing flash first, then program and verify the
combined MCS. This replaces existing flash contents. The remote SCU35 was
programmed with explicit overwrite approval, without a backup. Select the
board's QSPI boot mode and power-cycle.
Do not flash the unpatched `design_1_wrapper.pdi` or treat the application SREC
addresses as physical flash addresses. See [bring-up checklist](doc/validation.md).

## Dashboard

```sh
python3 dashboard/miner_dashboard.py
# For another interface/subnet, supply its directed broadcast:
python3 dashboard/miner_dashboard.py --broadcast 192.168.1.255
# Alternatively target a known miner IP; diagnostic mode needs no GUI:
python3 dashboard/miner_dashboard.py --headless --broadcast 192.168.1.20 --seconds 30
```

Python 3 uses only its standard library; GUI mode additionally requires tkinter
(Ubuntu package `python3-tk`). Select a discovered miner, enter its MAC and pool
host/port/worker/password, and choose **Save to EEPROM**. Pool settings trigger
reconnection. Selecting a miner automatically reads its saved MAC, pool host,
port, and wallet/worker from EEPROM. The password stays write-only: it is
preserved unless **Replace stored password** is checked. MAC changes take
effect on the next reboot. Blank host disables mining.

The enhanced dashboard shows measured device hashrate, job number/pool ID,
submitted/accepted/rejected share counts, completed hashes, and error counters.
Share events show the exact `mining.submit` JSON and corresponding Bitcoin hash.
This exposes the wallet/worker to trusted-LAN subscribers, never the password.
The enhanced firmware and hardware counter are now deployed together; old
firmware cannot provide settings readback or measured hashrate. See
[enhanced telemetry validation](doc/telemetry.md) for the current deployment status.

Assign a unique MAC to every board: unconfigured boards use `02:00:00:11:22:33`.
Settings use two CRC-protected EEPROM slots at `0x1000` and `0x1200`; the first
4 KiB of factory/other data is untouched. See [protocol](doc/protocol.md).

Use a trusted/isolated LAN: configuration and Stratum V1 are unencrypted and
configuration access is unauthenticated. Do not expose ports 4028/UDP or
4029/TCP to the Internet. Remote FPGA reboot is not enabled; use PROGRAM_B or
a power-cycle. A CPU restart is not presented as an FPGA reboot.

## Reproduce and review

Dependencies are pinned by [fetch_dependencies.sh](scripts/fetch_dependencies.sh).
The pinned HyperBus revision plus the included WREADY patch preserves the
tested source configuration. That fix is also upstream in
[`GhlHub/hyperbus_controller` commit `26bcdc5`](https://github.com/GhlHub/hyperbus_controller/commit/26bcdc5).
The local UART package is refreshed with Vivado's IP packager because the
downloaded package is not directly accepted for the target part.

Install Vivado/Vitis 2026.1 with SCU35 board files v2.0, and make `vivado`
available on `PATH`. Tests also require GCC, Make, Verilator, Icarus Verilog,
Python 3, and ripgrep. The default Vitis install path is `/tools/Xilinx/2026.1/Vitis`;
firmware scripts accept `VITIS_ROOT` for another location (adjust the Makefile
platform command and diagnostic Tcl tool paths accordingly).

The remote bring-up scripts target the original lab server and SCU35 cable.
Review those target settings before using them on another board; flash
programming requires the explicit `OVERWRITE_SCU35` argument.

```sh
bash scripts/fetch_dependencies.sh
mkdir -p logs
vivado -mode batch -source third_party/hyperbus_controller/scripts/package_hyperbus_ip.tcl -log logs/package_hyperbus.log -journal logs/package_hyperbus.jou
vivado -mode batch -source scripts/package_uart.tcl -log logs/package_uart.log -journal logs/package_uart.jou
make bd
make sim
make review
# After the user's review approval:
make synth
make platform
make bootloader application
make implement
make images
make test
make test-hybrid # actual AMD DSP48E2 simulation model (XSIM)
```

`make bd` refuses to overwrite an existing project. The project is
`build/vivado/scu35_miner.xpr`; the block design is `design_1`.
`make review` opens that project and its block design in the GUI. Expand the
`reset_gen` hierarchy to inspect the four domain reset controllers.
Run `make synth` to synthesize the approved design and export its hardware platform.

The BSP uses the Vitis 2026.1 SDT-aware MicroBlazeV9 port with the requested
202604-LTS kernel and TCP stack. `make platform` refreshes an existing platform
from the XSA. Firmware-only rebuilds do not need synthesis or routing:

```sh
make bootloader application
make package
```

`make package` patches both the original BIT and RCDO, regenerates the normal
SpartanUP PDI using Vivado's BIF/PLM, creates the MCS, and verifies its bytes.
Compiler/build reports are under `logs/`; routed reports are `route_*.rpt`.

`make sim` checks AXI job/result transfers for the two-engine configuration,
the known Bitcoin genesis hash and target boundaries, and PHY reset/IRQ
synchronizer behavior. These simulations do not establish FPGA fit or timing.

## Sources

The original VEK280 project is read-only reference material at
`/raid/work/vek280_bitcoin_miner`, commit
`b0354ad2f636737b011931a4f47ed0d38226dae0`. Selected RTL and the AXI testbench
were copied locally, with SCU35-specific changes recorded in the review document.
Third-party licensing and revisions are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
