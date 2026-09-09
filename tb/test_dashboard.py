#!/usr/bin/env python3
import importlib.util
import json
import queue
import socket
import threading
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("dashboard", Path(__file__).resolve().parents[1] / "dashboard/miner_dashboard.py")
dashboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dashboard)


class DashboardTests(unittest.TestCase):
    def test_validation(self):
        values = dict(mac="02:00:00:11:22:33", host="pool.example", port="3333", worker="wallet.worker", password="x")
        self.assertEqual(dashboard.validate_settings(values)["port"], 3333)
        for key, value in [("mac", "01:00:00:11:22:33"), ("host", "stratum+tcp://pool"),
                           ("port", 65536), ("worker", 'bad"quote'), ("password", "x"*64)]:
            with self.assertRaises(ValueError):
                dashboard.validate_settings(dict(values, **{key: value}))

    def test_configure(self):
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0));server.listen(1)
            received = []
            def mock():
                with server.accept()[0] as client:
                    data = bytearray()
                    while b"\n" not in data:
                        data.extend(client.recv(256))
                    received.append(json.loads(data))
                    client.sendall(b'{"ok":true}\n')
            worker = threading.Thread(target=mock);worker.start()
            reply = dashboard.configure("127.0.0.1", dict(mac="02:00:00:11:22:33", host="pool.example",
                port=3333, worker="test.worker", password="test"), server.getsockname()[1])
            worker.join(2)
            self.assertTrue(reply["ok"])
            self.assertEqual(received[0]["command"], "configure")

    def test_discovery(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
            server.bind(("127.0.0.1", 0));server.settimeout(2)
            messages = queue.Queue();client = dashboard.Discovery(messages, ["127.0.0.1"], server.getsockname()[1])
            client.start()
            try:
                data, address = server.recvfrom(128)
                self.assertEqual(data, b"SCU35_DISCOVER/1")
                server.sendto(b'not JSON', address)
                packet = dict(protocol="SCU35/1", mac="02:00:00:11:22:33", seq=1, event_seq=0,
                    uptime_ms=1000, temp_centi=4500, event="status", network_up=True)
                server.sendto(json.dumps(packet).encode(), address)
                kind, reply = messages.get(timeout=2)
                self.assertEqual(kind, "telemetry");self.assertEqual(reply["ip"], "127.0.0.1")
            finally:
                client.stopped.set();client.join(2)


if __name__ == "__main__":
    unittest.main()
