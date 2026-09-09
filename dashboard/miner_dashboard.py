#!/usr/bin/env python3
"""SCU35 trusted-LAN discovery, live telemetry, and EEPROM configuration.

Standard-library only. GUI requires Python's tkinter package. Credentials are
sent over plain TCP to the selected miner; use an isolated/trusted mining LAN.
"""
import argparse
import ipaddress
import json
import queue
import socket
import threading
import time

DISCOVERY_PORT = 4028
CONFIG_PORT = 4029


def validate_settings(values):
    mac = values["mac"].split(":")
    if len(mac) != 6 or any(len(x) != 2 for x in mac):
        raise ValueError("MAC must contain six colon-separated hex bytes")
    try:
        octets = bytes(int(x, 16) for x in mac)
    except ValueError as exc:
        raise ValueError("Invalid MAC address") from exc
    if not any(octets) or octets[0] & 1:
        raise ValueError("MAC must be nonzero and unicast")
    port = int(values["port"])
    if not 1 <= port <= 65535:
        raise ValueError("Port must be 1..65535")
    for name, maximum in [("host", 95), ("worker", 127), ("password", 63)]:
        value = values[name]
        if len(value) > maximum or any(ord(c) < 32 or ord(c) > 126 or c in '\\"' for c in value):
            raise ValueError(f"{name}: maximum {maximum} printable ASCII characters; no quotes or backslashes")
    if any(not (c.isascii() and (c.isalnum() or c in ".-")) for c in values["host"]):
        raise ValueError("Host must be a hostname or IPv4 address, without a URL prefix")
    return dict(command="configure", mac=octets.hex(":"), port=port,
                host=values["host"], worker=values["worker"], password=values["password"])


def configure(ip, values, port=CONFIG_PORT):
    """Only call for an address selected from received discovery responses."""
    ipaddress.IPv4Address(ip)
    payload = (json.dumps(validate_settings(values), separators=(",", ":")) + "\n").encode("ascii")
    with socket.create_connection((ip, port), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(payload)
        data = bytearray()
        while b"\n" not in data:
            chunk = sock.recv(256)
            if not chunk:
                raise OSError("Miner closed the connection without a complete reply")
            data.extend(chunk)
            if len(data) > 2048:
                raise ValueError("Oversized miner reply")
        reply = json.loads(data.split(b"\n", 1)[0])
        if not isinstance(reply, dict) or not isinstance(reply.get("ok"), bool):
            raise ValueError("Invalid miner reply")
        return reply


class Discovery(threading.Thread):
    def __init__(self, messages, broadcasts, port=DISCOVERY_PORT):
        super().__init__(daemon=True)
        self.messages, self.broadcasts, self.port = messages, broadcasts, port
        self.stopped = threading.Event()
        self.scan = threading.Event()
        self.peers = {}

    def run(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.bind(("0.0.0.0", 0))
            sock.settimeout(0.2)
            discovery_at = subscribe_at = 0
            while not self.stopped.is_set():
                now = time.monotonic()
                if now >= discovery_at or self.scan.is_set():
                    self.scan.clear()
                    discovery_at = now + 5
                    for address in self.broadcasts:
                        try:
                            sock.sendto(b"SCU35_DISCOVER/1", (address, self.port))
                        except OSError as exc:
                            self.messages.put(("error", str(exc)))
                if now >= subscribe_at:
                    subscribe_at = now + 2
                    for ip, seen in list(self.peers.items()):
                        if now - seen > 15:
                            del self.peers[ip]
                            continue
                        try:
                            sock.sendto(b"SCU35_SUBSCRIBE/1", (ip, self.port))
                        except OSError:
                            pass
                try:
                    data, peer = sock.recvfrom(2049)
                except socket.timeout:
                    continue
                if len(data) > 2048 or peer[1] != self.port:
                    continue
                try:
                    item = json.loads(data)
                    if not isinstance(item, dict) or item.get("protocol") != "SCU35/1":
                        continue
                    if not isinstance(item.get("mac"), str) or len(item["mac"]) != 17:
                        continue
                    for key in ["seq", "event_seq", "uptime_ms", "temp_centi"]:
                        if type(item.get(key)) is not int:
                            raise ValueError("Invalid telemetry number")
                    if not isinstance(item.get("event"), str) or len(item["event"]) > 63:
                        continue
                    item = dict(item, ip=peer[0], seen=time.monotonic())
                    self.peers[peer[0]] = item["seen"]
                    self.messages.put(("telemetry", item))
                except (ValueError, TypeError, UnicodeError):
                    continue


def gui(args):
    import tkinter as tk
    from tkinter import ttk, messagebox
    root = tk.Tk()
    root.title("SCU35 Bitcoin lottery miners")
    root.geometry("1050x650")
    messages = queue.Queue()
    discovery = Discovery(messages, args.broadcast)
    miners, last_events = {}, {}
    pane = ttk.Frame(root, padding=12)
    pane.pack(fill="both", expand=True)
    ttk.Label(pane, text="Trusted LAN only • Settings use unencrypted TCP • Assign a unique MAC to each board").pack(anchor="w")
    toolbar = ttk.Frame(pane); toolbar.pack(fill="x", pady=8)
    ttk.Button(toolbar, text="Discover now", command=discovery.scan.set).pack(side="left")
    status = tk.StringVar(value="Discovering miners…")
    ttk.Label(toolbar, textvariable=status).pack(side="left", padx=12)
    columns = ("ip", "mac", "temp", "network", "age", "event")
    table = ttk.Treeview(pane, columns=columns, show="headings", height=8, selectmode="browse")
    for key, label, width in zip(columns, ["IP address", "Active MAC", "Die °C", "Network", "Last seen", "Latest event"], [130, 160, 80, 90, 80, 250]):
        table.heading(key, text=label);table.column(key, width=width)
    table.pack(fill="x")
    form = ttk.LabelFrame(pane, text="Save complete configuration to selected miner", padding=10)
    form.pack(fill="x", pady=10)
    fields = {}
    for row, (key, label) in enumerate([("mac", "MAC (after reboot)"), ("host", "Pool host"), ("port", "Pool port"), ("worker", "Worker / wallet.worker"), ("password", "Pool password")]):
        ttk.Label(form, text=label).grid(row=row, column=0, sticky="w", padx=5)
        var = tk.StringVar(value="3333" if key == "port" else "")
        ttk.Entry(form, textvariable=var, width=75, show="*" if key == "password" else "").grid(row=row, column=1, sticky="ew", pady=2)
        fields[key] = var
    form.columnconfigure(1, weight=1)
    ttk.Label(form, text="Blank pool host disables mining. Existing credentials are never broadcast or read back.").grid(row=5, column=0, columnspan=2, sticky="w")
    log = tk.Text(pane, height=9, state="disabled", wrap="word")
    log.pack(fill="both", expand=True)
    def append(text):
        log.configure(state="normal")
        log.insert("end", time.strftime("%H:%M:%S ") + text + "\n")
        if int(log.index("end-1c").split(".")[0]) > 500:
            log.delete("1.0", "100.0")
        log.see("end");log.configure(state="disabled")
    def selected(_event=None):
        selection = table.selection()
        if selection:
            fields["mac"].set(miners[selection[0]]["mac"])
    table.bind("<<TreeviewSelect>>", selected)
    def save():
        selection = table.selection()
        if not selection:
            messagebox.showerror("Select a miner", "Select a discovered miner first.");return
        ip = selection[0]
        try:
            values = validate_settings({key: var.get() for key, var in fields.items()})
        except ValueError as exc:
            messagebox.showerror("Invalid settings", str(exc));return
        if not messagebox.askyesno("Write EEPROM", f"Save these settings to {ip}?\nPool settings reconnect immediately. MAC changes require a board reboot."):
            return
        save_button.configure(state="disabled")
        def worker():
            try:
                reply = configure(ip, values)
                messages.put(("saved", (ip, reply)))
            except (OSError, ValueError) as exc:
                messages.put(("save_error", str(exc)))
        threading.Thread(target=worker, daemon=True).start()
    save_button = ttk.Button(form, text="Save to EEPROM", command=save)
    save_button.grid(row=6, column=1, sticky="e", pady=6)
    ttk.Label(form, text="FPGA reboot: not yet supported; use PROGRAM_B / power cycle").grid(row=6, column=0, sticky="w")
    def update():
        for _ in range(100):
            try:
                kind, value = messages.get_nowait()
            except queue.Empty:
                break
            if kind == "telemetry":
                ip = value["ip"];miners[ip] = value
                if not table.exists(ip):
                    table.insert("", "end", iid=ip);append(f"Discovered {ip} ({value['mac']})")
                identity = (value["uptime_ms"] // 1000, value["event_seq"])
                if value["event"] != "status" and last_events.get(ip) != identity:
                    append(f"{ip}: {value['event']}");last_events[ip] = identity
            elif kind == "saved":
                ip, reply = value;save_button.configure(state="normal")
                if reply["ok"]:
                    fields["password"].set("");append(f"{ip}: settings saved; MAC changes need reboot")
                else:
                    messagebox.showerror("Save failed", str(reply.get("error", "Unknown error")))
            elif kind == "save_error":
                save_button.configure(state="normal");messagebox.showerror("Save failed", value)
            elif kind == "error":
                status.set(value)
        now = time.monotonic()
        for ip, item in miners.items():
            age = now - item["seen"]
            table.item(ip, values=(ip, item["mac"], f"{item['temp_centi']/100:.2f}",
                "stale" if age > 5 else "up" if item.get("network_up") else "down", f"{age:.0f}s", item["event"]))
        status.set(f"{sum(now-m['seen'] < 5 for m in miners.values())} live / {len(miners)} discovered")
        root.after(100, update)
    def close():
        discovery.stopped.set();discovery.join(timeout=1);root.destroy()
    root.protocol("WM_DELETE_WINDOW", close)
    discovery.start();update();root.mainloop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--broadcast", action="append", help="Directed broadcast or miner IPv4 address; repeat for multiple interfaces")
    parser.add_argument("--headless", action="store_true", help="Print telemetry without tkinter")
    parser.add_argument("--seconds", type=float, default=0, help="Headless duration; zero runs until interrupted")
    args = parser.parse_args()
    args.broadcast = args.broadcast or ["255.255.255.255"]
    for address in args.broadcast:
        ipaddress.IPv4Address(address)
    if not args.headless:
        gui(args);return
    messages = queue.Queue();discovery = Discovery(messages, args.broadcast);discovery.start()
    end = time.monotonic() + args.seconds if args.seconds > 0 else float("inf")
    try:
        while time.monotonic() < end:
            try:
                kind, item = messages.get(timeout=0.25)
                print(json.dumps(dict(kind=kind, data=item)), flush=True)
            except queue.Empty:
                pass
    except KeyboardInterrupt:
        pass
    finally:
        discovery.stopped.set();discovery.join(timeout=1)


if __name__ == "__main__":
    main()
