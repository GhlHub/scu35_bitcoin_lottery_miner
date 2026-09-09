#!/usr/bin/env python3
"""Check Intel HEX addressing and exact byte identity of both flash payloads."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / "build/images"
memory = {}
base = 0
ended = False
for line in (ROOT / "scu35_flash.mcs").read_text("ascii").splitlines():
    if ended or not line.startswith(":"):
        raise ValueError("Bad Intel HEX record")
    data = bytes.fromhex(line[1:])
    if len(data) != data[0]+5 or sum(data) & 255:
        raise ValueError("Bad Intel HEX length/checksum")
    address = int.from_bytes(data[1:3], "big")
    kind, payload = data[3], data[4:-1]
    if kind == 0:
        for i, byte in enumerate(payload):
            target = base + address + i
            if target in memory:
                raise ValueError("Overlapping Intel HEX records")
            memory[target] = byte
    elif kind == 4 and len(payload) == 2:
        base = int.from_bytes(payload, "big") << 16
    elif kind == 1 and not payload:
        ended = True
    else:
        raise ValueError("Unexpected Intel HEX record type")
if not ended:
    raise ValueError("Missing Intel HEX termination")
for name, offset in [("scu35_bootloader.pdi", 0), ("miner.srec", 0x800000)]:
    expected = (ROOT / name).read_bytes()
    actual = bytes(memory.pop(offset+i) for i in range(len(expected)))
    if actual != expected:
        raise ValueError(f"Flash byte mismatch: {name}")
    print(f"PASS: {name} exact bytes at {offset:#010x} ({len(expected)} bytes)")
if any(byte != 255 for byte in memory.values()):
    raise ValueError("Unexpected non-erased data outside flash payloads")
