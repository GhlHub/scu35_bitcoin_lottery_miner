# Component versions

Independent semantic versions start at **1.0.0** for hardware, bootloader,
application, and dashboard in the three-lane build. Earlier images are
unversioned. Bump the affected component for subsequent changes: major for
incompatible interfaces, minor for compatible features, patch for fixes.
Versions are manually maintained, not automatically incremented by rebuilds.

The deployed hardware is **1.2.0**, adding a dedicated INA700 I2C controller.
Application and dashboard are **1.1.0** for power telemetry; bootloader remains
**1.0.0**. This build was flashed and boot-checked on 2026-09-10.
See [power telemetry](power_telemetry.md).

The preceding deployed hardware was restored to **1.0.0**, with hashing and HyperBus sharing
200 MHz. The experimental [hardware 1.1.0 / 210 MHz build](hash210_build.md)
was withdrawn at the user's request before deployment. Bootloader,
application, and dashboard remained at **1.0.0** for that restoration. It restored the earlier
configuration rather than introducing a new hardware release.

| Component | Source of truth | Where visible |
|---|---|---|
| Hardware | `HW_VERSION` in `rtl/bitcoin_miner_axi.sv` | AXI register, application UART banner, telemetry, dashboard |
| Bootloader | `BOOTLOADER_VERSION` and `BOOTLOADER_VERSION_CODE` in `software/common/versions.h` | Boot UART banner, handoff register, telemetry, dashboard |
| Application | `APPLICATION_VERSION` in `software/common/versions.h` | Application UART banner, telemetry, dashboard |
| Dashboard | `DASHBOARD_VERSION` in `dashboard/miner_dashboard.py` | Window title and `--version` |

Hardware register `0x44a300b0` is read-only. Register `0x44a300b4` is a
byte-strobe-aware read/write bootloader handoff register: it resets to zero,
then the bootloader writes its own compiled version. Job starts, stops, and
FIFO clears do not erase it. The application reads the recorded value rather
than assuming that the bootloader matches its own source checkout.
This register is diagnostic metadata, not authenticated identity.

Both packed values encode major in bits 31:24, minor in 23:16, and patch in
15:0. Thus 1.0.0 is `0x01000000`. Zero is reserved for unknown/unversioned.
The bootloader string and packed constant must be updated together.

Telemetry adds `hw_version`, `bootloader_version`, and `application_version`
as `major.minor.patch` strings. Unknown hardware/bootloader versions are JSON
null. The dashboard displays unknown when older firmware omits these fields.
Its own version is local, not supplied by a remote miner.

The `engines` telemetry field now reads the hardware register `0x44a30008`;
it is no longer hard-coded to two. The three-lane hardware uses stride three
and a partially populated second result cluster. Existing settings, discovery
protocol `SCU35/1`, and hash-counter capability `HSH1` remain compatible.

Nonce distribution uses a 32-cycle restoring divide-by-three once per batch,
then assigns `count / 3 + (lane < count % 3)` nonces to each lane. The extra
160 ns of setup at 200 MHz does not change the 527-cycle SHA256d throughput.
This avoids a long combinational divide in the launch path. STOP has priority
over the launch state machine, including while division is in progress.

The regression checks hardware version immutability, boot register reset,
write/readback, byte strobes, persistence across jobs, JSON version formatting,
unknown-version handling, and dashboard display. These versions describe the
selected build; the board now runs three-lane hardware 1.2.0 with power telemetry.
