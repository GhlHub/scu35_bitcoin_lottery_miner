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

Event names include `mining_job_received`, `solution_submitted`,
`solution_accepted`, `solution_rejected`, `pool_connected`, `pool_authorized`,
`pool_disconnected`, `difficulty_changed`, `settings_saved`, and error events.
Periodic `status` packets are emitted once per second while subscribed.
`phy_known: false` means MDIO probing did not identify a PHY; the driver allows
the strapped board interface to attempt DHCP, without claiming physical link
status is known.

## Configuration (TCP 4029)

One newline-terminated JSON request per connection, maximum 1024 bytes and
three seconds to complete. All fields are required:

```json
{"command":"configure","mac":"02:00:00:11:22:34","host":"pool.example","port":3333,"worker":"wallet.worker","password":"x"}
```

MAC must be a nonzero unicast address. Host is empty (disable mining) or an
ASCII hostname/IPv4 address, maximum 95 characters; no `stratum+tcp://` prefix.
Port is 1..65535. Worker and password are at most 127 and 63 printable ASCII
characters respectively; quotes/backslashes are deliberately rejected rather
than interpreted as escape sequences. Configure only the selected discovered
device. A positive JSON reply is sent only after EEPROM readback verification.

`{"ok":true,"message":"..."}` means persisted. Pool credentials apply on
reconnection; the active MAC is unchanged until reboot. Errors return
`{"ok":false,"error":"..."}`. There is no read-password or reboot command.

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
