# SCU35 Bitcoin lottery miner

Target: AMD SCU35, `xcsu35p-sbvb625-2-e`, Vivado/Vitis 2026.1.
Requirements are in [initial_prompt.txt](initial_prompt.txt); MicroBlaze is
fixed at **50 MHz** by the subsequent user instruction.

## Build status

Hardware, bootloader, FreeRTOS application, and Python dashboard are implemented
and built. The user approved the block-design/reset review on 2026-09-09.
Synthesis, routing, image generation, and automated tests pass. The SCU35 on
`10.0.1.109:3121`, cable `52041A454A5TA`, was flashed and readback-verified on
2026-09-09. Bring-up has demonstrated HyperRAM calibration, application startup,
FreeRTOS ticks, DHCP, dashboard discovery/temperature telemetry, pool
authorization, and mining-job reception with both caches enabled. Accepted
shares and long-duration stability have not yet been verified.

The implemented design uses 11,281/16,320 LUTs (69.12%), 13,379 registers,
17.5/48 BRAM tiles, and 3/48 DSPs. Both mining engines use fabric; the DSPs belong
to the processor. Mining runs at 200 MHz, with approximately 0.61 MH/s theoretical
combined throughput before job-switching overhead, not a measured pool hash rate.
All specified timing constraints pass; calibrated external HyperRAM timing still
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
- Two VEK280-derived fabric SHA256d engines at 200 MHz, AXI clock conversion,
  and a separate synchronizer for the level-sensitive result interrupt.
- Explicit reset wiring in four continuously running clock domains and a
  10 ms minimum PHY reset hold at 50 MHz.

See [design review](doc/design_review.md) for resource estimates, the address
map, reset details, and byte-order conventions.

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
reconnection. MAC changes take effect on the next reboot. Blank host disables
mining. Credentials are not broadcast or returned in telemetry.

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
and Python 3. The default Vitis install path is `/tools/Xilinx/2026.1/Vitis`;
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
