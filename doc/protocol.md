# SCU35/1 LAN protocol

IPv4, trusted LAN only. No authentication, TLS, or Internet exposure.

## Discovery and telemetry (UDP 4028)

Send the exact ASCII bytes `SCU35_DISCOVER/1` to the subnet broadcast address
or a miner's address. The miner replies to the sender's IP/UDP port with JSON.
Send `SCU35_SUBSCRIBE/1` to receive periodic status and queued events. Renew
every two seconds; subscriptions expire after five seconds. Four simultaneous
subscribers are supported. UDP is best-effort: events may be lost or reordered.

Responses contain `protocol: "SCU35/1"`, `seq`, `event_seq`, `event`, active
`mac`, `uptime_ms`, `temp_centi` (temperature in hundredths of a degree C),
`cpu_mhz`, `engines`, `network_up`, `phy_known`, `reboot_supported`, and
`config_port`. The sender's IP is the miner address. No password is included.

Versioned firmware adds `hw_version`, `bootloader_version`, and
`application_version` strings (for example `1.0.0`). Unknown hardware or
bootloader versions are null. `engines` is read from the hardware lane-count
register. See [component versions](versions.md) for encoding and provenance.

The enhanced firmware adds `pool_connected`, `pool_authorized`, `mining`,
`job_number` (boot-local count of valid mining.notify messages), and `job_id`
(the opaque pool-assigned ID). Counters `shares_submitted`, `shares_accepted`,
`shares_rejected`, `hardware_errors`, and `events_dropped` persist across
jobs/reconnections and reset on reboot. UDP events remain best-effort; the
counters make missed events visible.

`hashrate_hps` is a measured integer number of completed double hashes per
second, sampled approximately once per second. It uses the difference of the
FPGA's free-running hash counter, divided by elapsed RTOS ticks, not the share
difficulty or theoretical clock rate. `hashrate_source` is `hardware_counter`,
`hashrate_sample_ms` reports the actual interval, and `hashes_total` accumulates
observed completions in a 64-bit firmware counter. `hashrate_hps: null` means
the hardware capability is absent or no sample has completed; zero is a valid
idle measurement. This is device throughput, not pool-effective accepted work.

Each packet has `details` with event-specific `job_number`, `job_id`,
`submission`, and `hash`. Share events contain the exact sent request, e.g.:

```json
{"job_number":7,"job_id":"pool-job-42","submission":{"id":4,"method":"mining.submit","params":["wallet.worker","pool-job-42","00000001","495fab29","7c2bac1d"]},"hash":"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"}
```

The five submission parameters are worker/wallet, job ID, extranonce2, ntime,
and nonce, preserving their transmitted strings. The hash is displayed in
conventional Bitcoin order. Accepted/rejected/timeout events retain the original
submission even if a new job is active. For other events `submission` is null.
These unicast events disclose the worker/wallet to subscribers, but never the
pool password. They are not sent as unsolicited subnet broadcasts.

Event names include `mining_job_received`, `solution_submitted`,
`solution_accepted`, `solution_rejected`, `pool_connected`, `pool_authorized`,
`pool_disconnected`, `difficulty_changed`, `settings_saved`, and error events.
Periodic `status` packets are emitted once per second while subscribed.
`phy_known: false` means MDIO probing did not identify a PHY; the driver allows
the strapped board interface to attempt DHCP, without claiming physical link
status is known.

Application 1.1.0 adds the `power` object documented in
[power telemetry](power_telemetry.md), with independent internal 5 V and VCCINT
readings. Invalid or stale readings are null. Oversized share/status packets
are sent as a full status plus a `partial: true` event; merge partial events
with the preceding status. Each UDP payload is at most 1472 bytes.

## Configuration (TCP 4029)

One newline-terminated JSON request per connection, maximum 1024 bytes and
three seconds to complete. A read-only request retrieves non-secret settings
directly from the newest valid EEPROM record without writing anything:

```json
{"command":"get_settings"}
```

The response has `ok`, `stored`, saved `mac`, `active_mac`, `host`, `port`,
`worker` (wallet/worker exactly as stored), and the boolean `password_set`.
No password field is returned. When no valid record exists, `stored` is false
and defaults are returned. I2C failures return an error rather than claiming
that EEPROM is empty. Saved MAC changes may differ from `active_mac` until
reboot. This endpoint is unauthenticated; use a trusted LAN.

To write settings, all fields except `password` are required:

```json
{"command":"configure","mac":"02:00:00:11:22:34","host":"pool.example","port":3333,"worker":"wallet.worker","password":"x"}
```

MAC must be a nonzero unicast address. Host is empty (disable mining) or an
ASCII hostname/IPv4 address, maximum 95 characters; no `stratum+tcp://` prefix.
Port is 1..65535. Worker and password are at most 127 and 63 printable ASCII
characters respectively; quotes/backslashes are deliberately rejected rather
than interpreted as escape sequences. Configure only the selected discovered
device. A positive JSON reply is sent only after EEPROM readback verification.
Omitting `password` preserves the current stored password; an explicit empty
string clears it. The GUI preserves it by default and requires the separate
"Replace stored password" checkbox to send a replacement, including blank.

`{"ok":true,"message":"..."}` means persisted. Pool credentials apply on
reconnection; the active MAC is unchanged until reboot. Errors return
`{"ok":false,"error":"..."}`. There is no read-password or reboot command.

## Hardware hash counter

At miner base `0x44a30000`, read-only offset `0x0a8` returns capability signature
`0x48534831` (HSH1); offset `0x0ac` returns the aggregate modulo-2^32 completed
SHA256d count across engines. Every completed double hash counts regardless of
target qualification. Job start/stop and result FIFO clear do not reset it;
FPGA reset does. Firmware samples frequently enough to use unsigned subtraction
across rollover. Older images return no signature and report rate unavailable.
Updating firmware alone cannot add this hardware capability.

## EEPROM layout

M24C64-compatible, I²C address 0x50, 16-bit byte addresses, 32-byte write pages.
Two 512-byte records at 0x1000/0x1200 preserve addresses 0..0x0fff. Record fields
are explicitly serialized little-endian, not compiler-structure dumps:

| Offset | Content |
| --- | --- |
| 0 | `S35C` magic |
| 4 | version 1 |
| 8 | 32-bit sequence counter |
| 16 | six MAC bytes |
| 22 | 16-bit pool port |
| 24 | host[96], NUL-terminated |
| 120 | worker[128], NUL-terminated |
| 248 | password[64], NUL-terminated |
| 504 | CRC-32/IEEE of bytes 0..503 |
| 511 | commit byte 0xa5 |

Reserved bytes are zero. Saving invalidates the inactive slot, writes/verifies
its body, then commits/verifies the last byte. Boot chooses the newer valid
slot with wrap-safe sequence comparison. No valid record or an I²C read error
selects the default MAC and disables mining until configured.
