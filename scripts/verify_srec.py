#!/usr/bin/env python3
"""Validate the exact application SREC handed to the bootloader."""
import argparse
from pathlib import Path

def verify(path):
    memory = {}
    entry = None
    count = 0
    for number, line in enumerate(Path(path).read_text("ascii").splitlines(), 1):
        if entry is not None:
            raise ValueError("Records follow termination record")
        if len(line) < 4 or line[0] != "S" or line[1] not in "012356789":
            raise ValueError(f"Bad record on line {number}")
        kind = int(line[1]);data = bytes.fromhex(line[2:])
        if data[0] != len(data)-1 or sum(data) & 255 != 255:
            raise ValueError(f"Bad length/checksum on line {number}")
        width = {0:2,1:2,2:3,3:4,5:2,6:3,7:4,8:3,9:2}[kind]
        address = int.from_bytes(data[1:1+width], "big")
        payload = data[1+width:-1]
        if kind in (1, 2, 3):
            count += 1
            if not ((0 <= address and address+len(payload) <= 0x50) or
                    (0x80000000 <= address and address+len(payload) <= 0x80800000)):
                raise ValueError(f"Record targets protected memory on line {number}")
            for offset, value in enumerate(payload):
                if address+offset in memory:
                    raise ValueError("Overlapping application records")
                memory[address+offset] = value
        elif kind in (5, 6):
            if payload or address != count:
                raise ValueError("Invalid data-record count")
        elif kind >= 7:
            if payload:
                raise ValueError("Payload in termination record")
            entry = address
    if entry is None or entry & 3 or entry < 0x80000000 or entry not in memory:
        raise ValueError("Entry must point to aligned, loaded HyperRAM code")
    for vector in (0, 8, 16, 32):
        if any(vector+i not in memory for i in range(8)):
            raise ValueError(f"Missing vector at {vector:#x}")
    return entry, len(memory), count

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument("srec")
    args = parser.parse_args();entry, size, count = verify(args.srec)
    print(f"PASS: {count} records, {size} loaded bytes, four vectors, entry {entry:#010x}")
