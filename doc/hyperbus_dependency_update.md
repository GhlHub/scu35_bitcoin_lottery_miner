# HyperBus upstream dependency refresh — 2026-09-10

The dependency pin is now
`26bcdc5c0f2044867d4bce6872a646fcee25079c`
([upstream commit](https://github.com/GhlHub/hyperbus_controller/commit/26bcdc5c0f2044867d4bce6872a646fcee25079c)).
It replaces `a3e38a65512daa10a436d7dc5ecaaa477c9811ec` plus the local WREADY patch.
`scripts/fetch_dependencies.sh` checks out this exact commit and no longer
applies a patch. The redundant patch file has been removed; it remains
recoverable from this repository's Git history.

The new upstream canonical RTL and packaged source are byte-identical to the
previously patched dependency. The only difference in its component XML is
the IP packaging creation timestamp. Upstream also adds the WREADY regression
and documentation. The previous dependency's three local modifications were
preserved in its Git stash before switching to the clean pinned commit.
Do not reapply that stash: the functional fix is already upstream.

This changes dependency provenance, not the FPGA interface or application
behavior. Hardware stays **1.2.0**, application/dashboard **1.1.0**, bootloader
**1.0.0**. Three lanes and HyperBus remain at 200 MHz; CPU remains at 50 MHz.

## Existing checkout migration

Inspect `git -C third_party/hyperbus_controller status --short` and preserve
any local changes before switching. The fetch script intentionally rejects
an existing checkout at a different revision instead of overwriting it.
After preserving local changes:

```sh
git -C third_party/hyperbus_controller fetch origin 26bcdc5c0f2044867d4bce6872a646fcee25079c
git -C third_party/hyperbus_controller checkout --detach 26bcdc5c0f2044867d4bce6872a646fcee25079c
bash scripts/fetch_dependencies.sh
bash third_party/hyperbus_controller/scripts/test_axi_wready.sh
vivado -mode batch -source scripts/refresh_hyperbus.tcl
make synth
make platform bootloader application
make test
make test-hybrid
make implement
make images
```

Fresh dependency checkouts use the new pin automatically. No local patching
or regeneration of the already-packaged upstream HyperBus IP is required
for this refresh. Rebuilding files does not program QSPI or modify EEPROM.

## Validation

The upstream WREADY regression passed: 79 AXI beats stored exactly once across
eight INCR/WRAP bursts. `make test` and `make test-hybrid` also passed, including
the three-lane nonce/version/hash-counter tests, 1032 DSP additions and 32-block
hybrid equivalence, EEPROM/JSON/protocol tests, power-monitor driver fault
tests, dashboard tests, and actual Stratum submission formatting tests.

The dependency working tree is clean at the pinned commit. Canonical and
packaged frontend sources match, and the regenerated Vivado source includes
the final-handshake WREADY deassertion. Test logs are `logs/tests_upstream.log`
and `logs/xsim_upstream.log`.

The platform, bootloader and application were rebuilt. The application SREC
is byte-identical to the deployed power-telemetry image, SHA-256
`706f5e9ed893731a6e4b357bb452b6e9f6d84d92a847921ec7db96400988695a`.
The bootloader ELF has a non-loadable metadata difference, but its loadable
binary is byte-identical (SHA-256
`57c7239e878adb959c94c2dff547f9f8bc56a6a0ada2fd9356f786824db088c4`).
Application text/data sizes remain 195,524 / 2,260 bytes.

Synthesis and implementation passed. Routed results match the preceding build:

| Measurement | Result |
| --- | ---: |
| LUTs | 13,644 / 16,320 (83.60%) |
| Registers | 16,911 / 32,640 (51.81%) |
| DSP48E2 | 33 / 48 |
| BRAM tiles | 17.5 / 48 |
| MMCMs | 1 / 2 |
| Hash/shared 200 MHz WNS | +0.544 ns |
| CPU 50 MHz WNS | +10.274 ns |
| Overall setup / hold slack | +0.017 / +0.010 ns |

All specified timing constraints pass. Existing external HyperRAM calibration
qualification and vendor warnings are unchanged. Build logs are
`logs/refresh_upstream.console.log`, `logs/synth_upstream.log`,
`logs/implement_upstream.log`, `logs/platform_upstream.log`, and
`logs/software_upstream.log`.

The final design audit passed with synthesis and implementation current.
`make images` completed and verified exact PDI and SREC bytes in the combined
MCS. The new default image is `build/images/scu35_flash.mcs`; images, routed
checkpoint and reports are archived in `build/upstream_hyperbus_26bcdc5/`.

- PDI: 1,163,840 bytes; SHA-256
  `6693eba5d415b0f272e97d3bb4848ace70f7658d318435619969b36687abb9b4`.
- Application SREC: 593,508 bytes; SHA-256
  `706f5e9ed893731a6e4b357bb452b6e9f6d84d92a847921ec7db96400988695a`.

See `logs/audit_upstream.console.log`, `logs/images_upstream.log`, and
`build/images/manifest.json`.

## QSPI deployment — 2026-09-10

The rebuilt image above was programmed and readback-verified on SCU35 cable
`52041A454A5TA`, then booted from QSPI. An earlier attempt stopped without
changing flash when the cable was absent. The successful retry passed erase,
blank check, program and verify.

Network discovery found the rebooted miner at **10.0.1.162**, with active MAC
`00:0a:35:18:d5:1f` (different from the preceding observation). This deployment
did not write EEPROM settings. Telemetry confirms hardware 1.2.0, bootloader
1.0.0, application 1.1.0, CPU 50 MHz, three lanes, pool authorization, and
approximately 1.139 MH/s. Both INA700 readings are valid, around 0.60 W internal
5 V and 0.20 W VCCINT, with zero sensor read errors or miner hardware errors
during the initial observation. These rail readings are not additive.

Evidence: `logs/program_upstream_retry.console.log`, `logs/boot_upstream.console.log`,
and `logs/telemetry_upstream_boot_discovered.jsonl`. This is a deployment smoke
test, not a long-duration stability test. Component versions are unchanged
because the controller RTL and firmware payloads are functionally unchanged.
