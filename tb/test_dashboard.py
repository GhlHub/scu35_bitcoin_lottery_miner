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
    def test_versions(self):
        self.assertEqual(dashboard.DASHBOARD_VERSION, "1.0.0")
        self.assertEqual(dashboard.format_versions(dict(engines=3, hw_version="1.0.0",
            bootloader_version="1.2.3", application_version="2.0.1")),
            "Lanes 3 | HW 1.0.0 | Boot 1.2.3 | App 2.0.1")
        self.assertIn("HW unknown", dashboard.format_versions({}))
        self.assertIn("Boot unknown", dashboard.format_versions(dict(bootloader_version=None)))

    def test_password_preservation(self):
        values = dict(mac="02:00:00:11:22:33", host="pool.example", port=3333, worker="wallet.worker")
        self.assertNotIn("password", dashboard.validate_settings(values))
        self.assertEqual(dashboard.validate_settings(dict(values, password=""))["password"], "")

    def test_read_settings(self):
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0));server.listen(1);server.settimeout(3)
            received = []
            saved = dict(ok=True, stored=True, password_set=True, mac="02:00:00:11:22:34",
                         active_mac="02:00:00:11:22:33", host="pool.example", port=3334, worker="wallet.worker")
            def mock():
                with server.accept()[0] as client:
                    data = bytearray()
                    while b"\n" not in data:
                        data.extend(client.recv(256))
                    received.append(json.loads(data))
                    encoded = (json.dumps(saved) + "\n").encode()
                    client.sendall(encoded[:10]);client.sendall(encoded[10:])
            worker = threading.Thread(target=mock);worker.start()
            reply = dashboard.read_settings("127.0.0.1", server.getsockname()[1]);worker.join(2)
            self.assertEqual(received, [{"command": "get_settings"}])
            self.assertEqual(reply, saved);self.assertNotIn("password", reply)

    def test_delayed_settings_read(self):
        form = dashboard.SettingsFormState()
        old = form.select("10.0.0.1")
        new = form.select("10.0.0.2")
        self.assertFalse(form.accepts(old));self.assertTrue(form.accepts(new))
        form.edited();self.assertFalse(form.accepts(new))
        reloaded = form.token();self.assertTrue(form.accepts(reloaded))
        latest = form.begin_read();self.assertFalse(form.accepts(reloaded));self.assertTrue(form.accepts(latest))

    def test_detailed_events(self):
        submitted = dict(id=42, method="mining.submit", params=["wallet.worker", "old-job", "0001", "12345678", "7c2bac1d"])
        packet = dict(event="solution_accepted", job_number=6, job_id="new-job", hashrate_hps=758900,
                      details=dict(job_number=5, job_id="old-job", submission=submitted, hash="00"*32))
        rendered = dashboard.format_event(packet)
        self.assertIn("job #5 / old-job", rendered);self.assertNotIn("new-job", rendered)
        self.assertIn('"id":42', rendered);self.assertIn("7c2bac1d", rendered)
        self.assertEqual(dashboard.format_hashrate(packet), "0.759 MH/s")
        self.assertEqual(dashboard.format_hashrate({"hashrate_hps": 0}), "0.000 MH/s")
        self.assertEqual(dashboard.format_hashrate({}), "unavailable")

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
