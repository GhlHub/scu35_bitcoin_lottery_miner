# EEPROM readback and enhanced telemetry

This local revision adds FPGA completion counting, firmware settings readback
and detailed telemetry, and an updated Python GUI. It was programmed,
readback-verified, and rebooted from QSPI with user authorization on
2026-09-09 at 06:11 PDT.

## Behavior

- Selecting a miner reads its saved MAC, pool host, port, and wallet/worker
  directly from EEPROM over explicit TCP. The GUI distinguishes saved/active
  MACs and empty EEPROM/read errors. A manual reload button is also available.
- Passwords are never read back. Saving other fields preserves the password
  unless replacement is explicitly selected. Checked replacement plus blank
  password intentionally clears it.
- Delayed settings replies cannot overwrite edits made since the request or
  populate a different selected miner. Overlapping reloads use request tokens.
- Job numbers count valid pool notifications since boot; opaque pool IDs are
  displayed separately. Submissions and accepted/rejected/timeout events retain
  their original job, exact transmitted mining.submit parameters, and hash.
- Hardware counts all completed SHA256d hashes, not only qualifying shares.
  Firmware measures rate from unsigned counter deltas and elapsed RTOS ticks,
  accumulating a 64-bit observed total. Idle rate is zero; unsupported hardware
  or an incomplete first sample is unavailable, not a fabricated estimate.

Full wire-format and privacy details are in [protocol.md](protocol.md).

## Validation

- Both fabric/hybrid RTL tests and actual DSP48E2 UNISIM simulations pass.
  Counter tests check qualifying and nonqualifying hashes across engines,
  and preservation across job changes/result clears.
- Host C tests check password omission/clearing, no secret in readback/telemetry,
  JSON validity and bounded output, rate arithmetic and counter rollover.
- The actual Stratum result/acknowledgment code is exercised with mocked I/O,
  including partial sends, genesis nonce/hash byte order, and a late response
  after the active job changes.
- Python tests cover configuration readback, password preservation, stale
  selection/edit/reload guards, and rendering full share details and rate.
- The FPGA rebuild meets all specified timing constraints: setup/hold slack
  +0.010/+0.010 ns. Utilization is 11,304 LUTs (69.26%), 13,478 registers,
  13 DSP48E2s, and 17.5 BRAM tiles. CPU remains 50 MHz and engines 200 MHz.

Runtime EEPROM readback, job-ID telemetry, pool authorization, and measured
board hashrate are verified. Steady-state one-second samples reported about
759,000 hashes/s (examples: 759,014, 759,020, and 759,008), with zero reported
hardware errors or dropped events during the short check. Startup idle samples
reported zero. This is measured device throughput, not accepted-pool hashrate.
No live share occurred during this check; new-format submission/acknowledgment
events are validated by host tests, not yet a live pool response.

The actual GUI readback helper retrieved a valid EEPROM record containing MAC,
pool host/port, and wallet/worker. `password_set` was true and no password field
was returned. JTAG confirmed both caches enabled (MSR `0x1a6`).
No EEPROM configuration was written during development or deployment.
The prior flash image is preserved locally under
`build/hybrid_pre_telemetry/images/`.

Tests: `make test`, `make test-hybrid`. Logs: `logs/tests_telemetry.log`,
`logs/xsim_telemetry.log`, `logs/application_telemetry.log`, and
`logs/images_telemetry.log` (generated artifacts, excluded from Git).

Deployment evidence: `logs/program_remote_flash_telemetry.console.log`,
`logs/boot_remote_telemetry.console.log`, `logs/uart_telemetry_flash.log`,
`logs/settings_readback_telemetry.json` (only presence flags, not pool/wallet
values), `logs/network_state_telemetry_flash.log`, and
`logs/discovery_telemetry_flash.jsonl`.

Deployed payload SHA-256:

- PDI: `d1522371657852a4433c52ed4319fd30390dc4c1bcc2a03d34a7d98b85f0e81e`
- SREC: `ca9dfaf0ef20d1d7d18bd090f6dd9a18b1d96b23775ec3025a9eb29857362950`
