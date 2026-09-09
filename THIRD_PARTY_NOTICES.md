# Third-party sources

Project-owned source is provided under the root Apache-2.0 license.
Retain each dependency's own license and notices when distributing it.

| Source | Revision | License location |
| --- | --- | --- |
| Local VEK280 Bitcoin miner | b0354ad2f636737b011931a4f47ed0d38226dae0 | Root LICENSE (Apache-2.0) |
| GhlHub/hyperbus_controller | a3e38a65512daa10a436d7dc5ecaaa477c9811ec | third_party/hyperbus_controller/LICENSE and individual source headers |
| GhlHub/e_uart | 72f014c35d812936c70f2e17acdd32a491c1fcdd | third_party/e_uart/LICENSE |
| FreeRTOS/FreeRTOS-LTS, 202604-LTS | 0b25dc50bae4cb971c7a459b109e52ab2f01a6b8 | third_party/FreeRTOS-LTS and component LICENSE files |
| FreeRTOS-Kernel | 3a22924e0a9ddbbc8b0758881c33b3422a5cc20d | Component LICENSE.md |
| FreeRTOS-Plus-TCP | c12361095aca68aeed858f45d14395fbffa92c0d | Component LICENSE.md |
| coreJSON | cffa492da18c890181d64462f8af63992a69d3b0 | Component LICENSE |

`software/common/sha256_sw.*` is copied from the Apache-2.0 VEK280 reference.
`software/application/FreeRTOSConfig.h`, `port_hooks.c`, and the linker-script
templates derive from the MIT-licensed AMD 2026 MicroBlaze example in the local
HyperBus FreeRTOS reference. Their AMD copyright/SPDX headers are retained.
The application combines the requested LTS kernel with the MIT-licensed,
SDT-aware MicroBlazeV9 port in Vitis 2026.1 `freertos10_xilinx_v1_18`. The
kernel itself is the pinned LTS kernel, not the older vendor kernel. BSP and
port source are read from the installed Vitis distribution without modification.

AMD IP and generated output retain AMD notices and applicable tool/IP terms.
The installed AMD SCU35 board files v2.0 provide the production board pinout.
HyperRAM pins are taken from the GhlHub SCU35 reference constraints.

The local HyperBus checkout includes `patches/hyperbus-wready.patch`, fixing
the AXI write-ready tail cycle in both RTL and packaged source. IP metadata
checksums were regenerated. Original copyright/SPDX headers are retained;
the fix was subsequently committed and pushed upstream as `26bcdc5`.
This build retains the tested pinned revision plus patch. Other downloaded
repositories remain unmodified. The derived UART package under
build/ip_repo changes the vendor to `github.com` to match the reference BD,
sets Spartan UltraScale+ support, and refreshes checksums using `ipx` commands.
