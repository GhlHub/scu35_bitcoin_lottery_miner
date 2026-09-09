#!/usr/bin/env python3
"""Cross-check portable mining arithmetic against Python's independent library."""
import ctypes as C
import hashlib
import random
import subprocess
import unittest
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-Wall", "-Wextra", "-Werror",
                "-Isoftware/common", "software/common/bitcoin.c", "software/common/sha256_sw.c",
                "-o", "build/libbitcoin_test.so"], cwd=ROOT, check=True)
lib = C.CDLL(str(ROOT / "build/libbitcoin_test.so"))
lib.bitcoin_target.argtypes = [C.c_char_p, C.c_size_t, C.POINTER(C.c_uint32)]
lib.sha256d.argtypes = [C.c_char_p, C.c_size_t, C.c_void_p]
lib.bitcoin_build_header.argtypes = [C.c_char_p] * 5 + [C.c_size_t, C.c_char_p, C.c_size_t,
    C.c_char_p, C.c_size_t, C.c_char_p, C.c_size_t, C.c_char_p, C.c_size_t, C.c_void_p]

def sha256d(data):
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()

class BitcoinTests(unittest.TestCase):
    def test_targets(self):
        rng = random.Random(35)
        values = ["1", "0.0001", "0.5", "1.5", "4294967297", "1e80", "1e-80",
                  "12345678901234567890.123456789", "0.000000000000001"]
        values += [f"{rng.randrange(1, 10**18)}e{rng.randrange(-50, 50)}" for _ in range(300)]
        for value in values:
            out = (C.c_uint32 * 8)()
            self.assertEqual(lib.bitcoin_target(value.encode(), len(value), out), 0, value)
            numerator, denominator = Decimal(value).as_integer_ratio()
            expected = min((0xffff << 208) * denominator // numerator, (1 << 256) - 1)
            actual = int.from_bytes(b"".join(x.to_bytes(4, "big") for x in out), "big")
            self.assertEqual(actual, expected, value)
        for value in ["", "0", "-1", "NaN", "1e", "1.2.3", "1e999", ".5"]:
            self.assertNotEqual(lib.bitcoin_target(value.encode(), len(value), (C.c_uint32 * 8)()), 0)

    def test_hashes(self):
        for n in [0, 1, 55, 56, 63, 64, 65, 80, 128, 4096]:
            data = bytes(i % 256 for i in range(n)); out = C.create_string_buffer(32)
            lib.sha256d(data, n, out)
            self.assertEqual(out.raw, sha256d(data))

    def test_header(self):
        parts = [b"coinbase_prefix", b"extra1", b"extra2", b"coinbase_suffix"]
        version, prev = bytes.fromhex("20000000"), bytes(range(32))
        bits, time = bytes.fromhex("1d00ffff"), bytes.fromhex("65000001")
        branches = [sha256d(b"branch1"), sha256d(b"branch2")]
        out = C.create_string_buffer(80)
        lib.bitcoin_build_header(version, prev, bits, time, parts[0], len(parts[0]),
            parts[1], len(parts[1]), parts[2], len(parts[2]), parts[3], len(parts[3]),
            b"".join(branches), len(branches), out)
        root = sha256d(b"".join(parts))
        for branch in branches:
            root = sha256d(root + branch)
        expected = version[::-1] + b"".join(prev[i:i+4][::-1] for i in range(0, 32, 4))
        expected += root + time[::-1] + bits[::-1] + bytes(4)
        self.assertEqual(out.raw, expected)

    def test_genesis(self):
        header = bytes.fromhex("01000000" + "00"*32 +
            "3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a" +
            "29ab5f49ffff001d1dac2b7c")
        out = C.create_string_buffer(32);lib.sha256d(header, len(header), out)
        self.assertEqual(out.raw[::-1].hex(), "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")

if __name__ == "__main__":
    unittest.main()
