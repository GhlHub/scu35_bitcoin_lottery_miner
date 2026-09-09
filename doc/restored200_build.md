# Restored shared 200 MHz hash/HyperBus configuration

On 2026-09-09 the user withdrew the 210 MHz request. Source and block design
return to **hardware 1.0.0**, retaining three hash lanes and ten DSP48E2
adders per lane. Bootloader, application, and dashboard remain at 1.0.0.

- Hash lanes and the AXI clock converter's master side again use
  `clk_wiz_0/clk_out1` at **200 MHz** and
  `reset_gen/hb_clk_peripheral_aresetn`.
- The converter's slave side again uses the CPU **50 MHz** clock and
  `reset_gen/axi_clk_peripheral_aresetn`. `ACLK_ASYNC=1` is retained.
- HyperBus remains at **200 MHz**, with its original 200 MHz / 90-degree
  receive clock, 300 MHz delay reference, and gated forwarding clock.
- The extra hash clock wizard and both experiment-specific reset controllers
  are removed. The 210 MHz-specific interrupt timing exception is removed,
  restoring the preceding constraints.
- Fresh `make bd` projects select this same shared-clock topology.

Expected throughput returns to **1.139 MH/s** before job-change overhead:
three lanes at 200 MHz, 527 cycles per nonce per lane.

The [original 200 MHz build](three_lane_build.md) remains archived in
`build/three_lane_v1_0_0/`. The withdrawn 210 MHz image/checkpoint remains in
`build/three_lane_v1_1_0/`; it was never programmed into QSPI.

## Restore/rebuild an existing 210 MHz project

```sh
vivado -mode batch -source scripts/restore_hash200.tcl
make test
make test-hybrid
make synth
make implement
vivado -mode batch -source scripts/report_hybrid.tcl
vivado -mode batch -source scripts/check_final.tcl
make images
```

These commands build files only. They do not program QSPI, reboot the board,
change EEPROM settings, or push Git changes.

## Rebuild verification

The restored design passed synthesis, implementation, the full `make test`
suite, and AMD UNISIM hybrid-adder/core equivalence tests (`make test-hybrid`).
The routed result matches the original three-lane 200 MHz timing/resource results:

| Measurement | Result |
| --- | ---: |
| Hash-engine setup WNS | +0.535 ns |
| Overall setup WNS | +0.059 ns |
| Overall hold slack | +0.010 ns |
| LUTs | 13,255 / 16,320 (81.22%) |
| Registers | 16,534 / 32,640 (50.66%) |
| DSP48E2 | 33 / 48 (30 miner, 3 CPU) |
| Block RAM tiles | 17.5 / 48 |
| MMCMs | 1 / 2 |

All user-specified timing constraints pass. The overall critical setup path
crosses from the HyperRAM receive clock to the main 200 MHz clock. This is
not a claim of complete external HyperRAM timing signoff or new on-board
validation. Board deployment was performed separately after user approval,
as recorded below.

Evidence: `logs/route_timing.rpt`, `logs/route_utilization.rpt`,
`logs/restored200_analysis.console.log`, `logs/tests_restored200.log`, and
`logs/xsim_restored200.log`.

The final block-design audit passed with synthesis and implementation both
100% complete and not stale. `make images` completed and the combined MCS
passed byte-for-byte payload verification. Default `build/images/` now
contains the restored 200 MHz image. A copy, routed checkpoint, and reports
are archived in `build/restored_three_lane_v1_0_0/`.

- PDI: 1,163,168 bytes; SHA-256
  `4c0fd7fc13cb4f387ca3f1f8e774107eca83db9a0ee690204a4eaa292c3a1a5f`.
- Application SREC: 578,340 bytes; SHA-256
  `92940e70761b080b48966923313eca77ed076b74b9a9612439f5e2a194a2dc3b`.
- Application SREC and bootloader ELF are byte-identical to the original
  three-lane hardware 1.0.0 archive; no software rebuild was needed.

Packaging evidence: `logs/images_restored200.log` and
`build/images/manifest.json`. These images had not been programmed or tested
on the board at packaging time.

## QSPI deployment

On 2026-09-09, on explicit user request, the restored image was programmed
into the SCU35 on hardware server `10.0.1.109:3121`, cable `52041A454A5TA`.
Erase, blank check, programming, and verification passed, followed by a
successful boot from QSPI. No EEPROM settings were changed.

Serial boot confirmed HyperRAM calibration (window `0x001..0x117`, midpoint
`0x08C`), application launch, three lanes, CPU 50 MHz, and hardware/bootloader/
application version 1.0.0. The miner returned at `10.0.1.227`, authorized with
the saved pool, received jobs, and reported approximately **1.139 MH/s** with
zero hardware errors during the initial observation. This is a boot/mining
smoke test, not a long-duration stability test.

Deployment evidence: `logs/program_restored200.console.log`,
`logs/boot_restored200.console.log`, `logs/uart_restored200_flash.log`, and
`logs/telemetry_restored200_flash.jsonl`.
