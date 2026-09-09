# Data-cache investigation, 2026-09-09

The initial investigation below was diagnosis only. The user subsequently
authorized a local patch, full rebuild, flash programming, and reboot.

## Authorized local fix

The local RTL and packaged IP now explicitly deassert registered `WREADY`
on the final W handshake. The reference repository under `/raid/work/ghl_ip`
is unchanged. `patches/hyperbus-wready.patch` records the change;
`scripts/fetch_dependencies.sh` applies it to the pinned dependency.

The former probe is now a regression: it fails on the original RTL and
passes on the patched RTL, verifying 79 accepted/stored/commanded words and
eight completed responses across INCR and WRAP bursts. Both full HyperBus
simulations (UltraScale+ and 7-series) report `TB PASS`, including masked
writes and AXI-full/AXI-Lite overlap while posted writes drain.

Vivado IP packaging was rerun, and the generated synthesis source was checked
byte-for-byte against the patched canonical RTL. The previous working image
is preserved under `build/cache_rollback.eaIRBy/images`.

## Hardware result after the patch

The rebuilt image was programmed and readback-verified, then booted from QSPI
at 03:38 PDT on 2026-09-09. The application now enables both caches. JTAG
confirmed MSR `0x1a6` (DCE=1, ICE=1), advancing ticks, and eight RTOS tasks.
It passed the previously stalled startup path, recovered existing EEPROM
settings, acquired `10.0.1.227`, authorized with the pool, and received a job.
See `logs/network_state_cache_fix.log`, `logs/uart_cache_fix.log`, and
`logs/discovery_cache_fix.jsonl`.

This supports the patch as a fix for the observed startup failure, but no
captured hardware AXI trace proves the exact original failing transaction.
Multi-day stability and physical power-cycle testing remain outstanding.
The diagnostic sections below describe the pre-patch investigation, not the
current cache configuration or pending authorization.

## Original diagnostic record

## Correct reference

The user identified `/raid/work/ghl_ip/hyperbus_controller`, not the older
`/raid/work/hyperbus_controller_freertos_port` project initially inspected.
The correct reference and this project's dependency both identify commit
`a3e38a65512daa10a436d7dc5ecaaa477c9811ec`.

The correct reference's `hyperbus_test_proj` and this miner both configure an
8 KiB write-back data cache with eight-word lines, cacheable range
`0x80000000..0x807fffff`, and matching cache AXI connections. Comparing BD
parameters for MicroBlaze, its memory crossbar, HyperBus controller, and clock
wizard showed only the intentional FPU/FPU-exception disable differences.
The reference FreeRTOS application's `platform.c` enables both caches.

Before the patch, the AXI-full frontend source was byte-identical in both trees (SHA-256
`c1e1bcec067419ffd22444ea8cd5284c6d5a7648995242bd4346a96af958ba02`).
Therefore the earlier observation that a different old project used
write-through is not an explanation for the user's known-good build.
Source/settings equivalence is not proof of identical placed/routed timing
or identical workload/AXI request ordering.

## Reproduced protocol defect; hardware causality not established

`tb/tb_hyperbus_wready_probe.sv` sends an eight-word write burst followed
immediately by data for a second burst. AXI permits write data to precede
its address handshake. On the last beat of the first burst:

1. `s_axi_wready` is registered from the old beat count, leaving it high for
   the following cycle (frontend line 252).
2. The beat counter advances beyond the burst length (line 260).
3. A following WVALID/WREADY handshake occurs, but `o_wr_fifo_wr_en` is gated
   off by the new beat count (line 121). The acknowledged beat is dropped.

Both the miner's dependency and the user-specified reference reproduce:

```text
REPRODUCED: AXI accepted W beat 9 but FIFO stored only 8; WDATA=b0000000
```

Run locally, without board access or RTL edits:

```sh
iverilog -g2012 -s tb_hyperbus_wready_probe -o build/sim/hyperbus_wready_probe \
  third_party/hyperbus_controller/rtl/hyperbus_axi_full_frontend.sv \
  tb/tb_hyperbus_wready_probe.sv
vvp build/sim/hyperbus_wready_probe
```

The original probe exited successfully when it demonstrated the defect.
It has since been converted to a regression that fails when a beat is lost
and succeeds only when all tested bursts complete correctly.

A dropped beat can leave a subsequent write waiting for data that the master
already considers delivered. However, no captured miner bus trace yet proves
that its MicroBlaze/crossbar presents this exact sequence. The previous
days-long successful run does not establish that every legal ordering was
exercised, nor does this probe establish that this defect caused the observed
heap-allocation stall. Cache disable remains a workaround, not a diagnosis.

## Next discriminating check

With permission to briefly interrupt the working miner, reproduce the failure
using a separate cache-enabled RAM-only diagnostic, and correlate CPU state
with controller status. If needed, add an ILA to a separate diagnostic build
to capture AW/W/B and AR/R traffic at the HyperBus input. Keep the current
flash image and EEPROM credentials intact and reboot back to the working
image afterward. Confirm the observed transaction before selecting a fix.

AMD documents that write-back can issue burst writes on M_AXI_DC, unlike
write-through's single writes:
https://docs.amd.com/r/en-US/ug984-vivado-microblaze-ref/Interface-Parameters-and-Signals
