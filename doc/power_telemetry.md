# INA700 power telemetry

## Hardware and measurement scope

Hardware **1.2.0** adds an AXI IIC 2.1 controller, `power_iic`, at
`0x40810000` (64 KiB decode, crossbar M09). It runs from the existing CPU
50 MHz clock and `reset_gen/axi_clk_peripheral_aresetn`. Its level-high IRQ
is connected to interrupt input 7 but disabled in the polling driver.
No clock domain or reset controller was added. Three hash lanes and HyperBus
remain at 200 MHz. I2C runs at 100 kHz.

SCU35 schematic `038-05204-01_RevA4.pdf`, sheets 9, 26, and 28:

| Device | 7-bit address | Rail | FPGA bus pins |
| --- | --- | --- | --- |
| U61 INA700 | 0x44 | VR_INT_5V0 | M4 SCL, L4 SDA |
| U64 INA700 | 0x45 | VR_VCCINT_0V85 | Same bus |

Both pins use LVCMOS33 and the board's existing 4.7 kΩ pull-ups. The shared
ALERT signal on E3 is unused. EEPROM I2C0 on L1/K1 is unchanged.

The internal 5 V measurement is **not wall-plug power**. VCCINT measures
the core rail, not all FPGA rails. VCCINT is downstream of the internal
5 V supply: **do not add the readings**. Monitor temperature is the INA700's
own die temperature, not the FPGA die temperature already in telemetry.

Sources: [AMD INA700 board description](https://docs.amd.com/r/en-US/ug1713-scu35-eval-bd/INA700-Devices),
[AMD I2C connectivity](https://docs.amd.com/r/en-US/ug1713-scu35-eval-bd/I2C-Buses-and-Connections),
and [TI INA700 datasheet Rev. B](https://www.ti.com/lit/ds/symlink/ina700.pdf).

## Firmware and dashboard

Application and dashboard advance to **1.1.0**; bootloader remains **1.0.0**.
Hardware 1.1.0 was the withdrawn 210 MHz experiment, so it is not reused.

A separate low-priority FreeRTOS task samples both sensors every second.
It checks manufacturer ID, configures continuous V/I/T conversion with
16-sample averaging (`ADC_CONFIG=0xFB6A`), verifies the setting, and waits
until the next sampling interval before accepting measurements. Each sample
checks configuration, conversion-ready, trim-memory health, and math overflow.
Configuration loss after sensor reset causes reinitialization. Reads use
MSB-first 16-bit voltage/current/temperature and 24-bit power registers.
No sensor calibration register is required for the integrated shunt.

The driver has a 100 ms deadline per I2C transaction and yields while waiting.
NACKs, arbitration loss, and stuck-bus timeouts invalidate the affected sample
and reset only the dedicated IIC controller. Sensors retry independently.
A physically stuck bus needs its electrical cause resolved; reset is not
claimed to clear it. Sensor faults cannot block the mining task indefinitely.
The firmware avoids accessing the new AXI address on older hardware versions.

Every full telemetry packet adds:

```json
"power": {
  "source": "INA700",
  "internal_5v": {
    "valid": true,
    "voltage_uv": 5000000,
    "current_ua": 1200000,
    "power_uw": 6000000,
    "temp_milli_c": 30000,
    "age_ms": 100,
    "errors": 0
  },
  "vccint": {
    "valid": false,
    "voltage_uv": null,
    "current_ua": null,
    "power_uw": null,
    "temp_milli_c": null,
    "age_ms": null,
    "errors": 1
  }
}
```

These are illustrative values, **not board measurements**. Failed or older
than 3-second samples report null measurements, not zero or old power values.
The GUI also ages retained samples locally if status packets are lost.
It displays W, V, A, sensor temperature, age, and read-error counts separately
for each rail. Efficiency uses measured hash rate divided by internal 5 V
power; it is unavailable without a fresh nonzero power measurement. Older
firmware without the power object displays unavailable.

The serializer has a 3072-byte work buffer, but all transmitted IPv4 UDP
payloads are limited to **1472 bytes** for the existing 1500-byte MTU.
Oversized status-plus-share packets are split into a complete status packet
and a `partial: true` event containing the intact submitted solution. The
dashboard merges partial events with cached status. No IP fragmentation or
solution truncation is required. UDP remains best-effort.

## Build and validation

For an existing project:

```sh
vivado -mode batch -source scripts/configure_power.tcl
make synth
make platform bootloader application
make test
make test-hybrid
make implement
vivado -mode batch -source scripts/report_hybrid.tcl
vivado -mode batch -source scripts/check_final.tcl
make images
```

Fresh `make bd` also adds the controller. The static audit verifies its AXI
decode, clock, reset and IRQ; image generation checks both input-buffer paths.

Routed results (2026-09-09):

| Measurement | Result |
| --- | ---: |
| LUTs | 13,644 / 16,320 (83.60%) |
| Registers | 16,911 / 32,640 (51.81%) |
| DSP48E2 | 33 / 48 |
| BRAM tiles | 17.5 / 48 |
| MMCMs | 1 / 2 |
| Shared hash/HyperBus 200 MHz domain WNS | +0.544 ns |
| CPU 50 MHz domain WNS | +10.274 ns |
| Overall WNS / hold slack | +0.017 / +0.010 ns |

All specified timing constraints pass; the existing calibrated external
HyperRAM timing qualification remains unchanged. Added cost versus the
deployed build is 389 LUTs and 377 registers, with no extra DSPs or BRAM.

Tests cover INA700 units/sign extension/limits, identity/configuration,
bad/incomplete reads, reset recovery, AXI dynamic START/repeated START/STOP,
NACK/arbitration/stuck bus deadlines, JSON null/stale/wrap handling, packet
size limits, dashboard formatting/validation, and existing mining regressions.
These are host-model tests for the sensor and I2C firmware; actual INA700
readings must be verified after programming. This build does not program QSPI
or change EEPROM settings.

`make test` and `make test-hybrid` passed. Firmware linked successfully
(application text 195,524 bytes, data 2,260 bytes; 197,784 loaded SREC bytes).
The pre-existing FreeRTOS MicroBlaze port `_stack` compiler warning and
vendor SysMon VP/VN IOSTANDARD warnings remain; no new build errors occurred.

`make images` completed and `verify_mcs.py` checked both payloads byte-for-byte:

- PDI: 1,163,840 bytes, SHA-256
  `40999bb0ebcb61ab41f3ea4f5763d8ada36a982f0448c47f9353c8e69db94dec`.
- Application SREC: 593,508 bytes, SHA-256
  `706f5e9ed893731a6e4b357bb452b6e9f6d84d92a847921ec7db96400988695a`.

The current image is `build/images/scu35_flash.mcs`. Images, routed checkpoint
and reports are archived under `build/power_telemetry_v1_2_0/`. Evidence:
`logs/tests_power.log`, `logs/xsim_power.log`, `logs/software_power_final.log`,
`logs/report_power.console.log`, `logs/audit_power.console.log`, and
`logs/images_power.log`. Actual sensor communication, readings and long-run
behavior had not been tested on hardware at packaging time.

## Deployment smoke test — 2026-09-10

After the SCU35 cable reappeared on `10.0.1.109:3121`, the exact image above
was erased/programmed/readback-verified on cable `52041A454A5TA`, then booted
from QSPI. Earlier attempts stopped before changing flash because that cable
was absent. The UART bridge timed out, so boot/application verification used
network telemetry at `10.0.1.227`.

Telemetry confirms HW 1.2.0, bootloader 1.0.0, application 1.1.0, three lanes,
CPU 50 MHz, pool authorization, and approximately 1.139 MH/s. Both monitors
reported valid samples with zero read errors and zero miner hardware errors
during the initial observation. Example mining readings: internal 5 V about
5.016 V / 0.120 A / 0.598 W, and VCCINT about 0.847 V / 0.236 A / 0.200 W.
These are sensor-reported rail measurements, not independently calibrated
wall-plug measurements, and must not be added together. No EEPROM settings
were changed. Long-duration stability remains unverified.

Evidence: `logs/program_power_retry2.console.log`, `logs/boot_power.console.log`,
and `logs/telemetry_power_boot.jsonl`.
