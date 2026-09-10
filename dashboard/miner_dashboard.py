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
        value = values.get(name, "")
        if len(value) > maximum or any(ord(c) < 32 or ord(c) > 126 or c in '\\"' for c in value):
            raise ValueError(f"{name}: maximum {maximum} printable ASCII characters; no quotes or backslashes")
    if any(not (c.isascii() and (c.isalnum() or c in ".-")) for c in values["host"]):
        raise ValueError("Host must be a hostname or IPv4 address, without a URL prefix")
    result = dict(command="configure", mac=octets.hex(":"), port=port,
                  host=values["host"], worker=values["worker"])
    if "password" in values:
        result["password"] = values["password"]
    return result


def configure(ip, values, port=CONFIG_PORT):
    """Only call for an address selected from received discovery responses."""
    return request_config(ip, validate_settings(values), port)


def request_config(ip, request, port=CONFIG_PORT):
    ipaddress.IPv4Address(ip)
    payload = (json.dumps(request, separators=(",", ":")) + "\n").encode("ascii")
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


def read_settings(ip, port=CONFIG_PORT):
    reply = request_config(ip, {"command": "get_settings"}, port)
    if not reply["ok"]:
        raise ValueError(reply.get("error", "Settings read failed"))
    if "password" in reply:
        raise ValueError("Miner unexpectedly returned a password")
    if type(reply.get("stored")) is not bool or type(reply.get("password_set")) is not bool:
        raise ValueError("Invalid settings response")
    try:
        validate_settings(reply)
        validate_settings(dict(reply, mac=reply["active_mac"]))
    except (KeyError, TypeError, AttributeError) as exc:
        raise ValueError("Invalid settings response") from exc
    return reply


class SettingsFormState:
    """Reject responses for a previous selection or edits made during a read."""
    def __init__(self):
        self.ip, self.generation, self.revision = None, 0, 0

    def select(self, ip):
        self.ip, self.generation, self.revision = ip, self.generation + 1, 0
        return self.token()

    def edited(self):
        self.revision += 1

    def begin_read(self):
        self.generation += 1
        return self.token()

    def token(self):
        return self.ip, self.generation, self.revision

    def accepts(self, token):
        return token == self.token()


def format_hashrate(item):
    value = item.get("hashrate_hps")
    return "unavailable" if value is None else f"{value / 1_000_000:.3f} MH/s"


def validate_power(item):
    power = item.get("power")
    if power is None:
        return  # Older firmware.
    if not isinstance(power, dict) or power.get("source") != "INA700":
        raise ValueError("Invalid power telemetry")
    for name in ("internal_5v", "vccint"):
        rail = power.get(name)
        if not isinstance(rail, dict) or type(rail.get("valid")) is not bool:
            raise ValueError("Invalid power rail")
        if type(rail.get("errors")) is not int or not 0 <= rail["errors"] <= 0xffffffff:
            raise ValueError("Invalid power error count")
        for key, low, high in (("voltage_uv", 0, 204796875), ("current_ua", -15728640, 15728160),
                               ("power_uw", 0, 1610612640), ("temp_milli_c", -256000, 255875),
                               ("age_ms", 0, 3000)):
            value = rail.get(key)
            if rail["valid"]:
                if type(value) is not int or not low <= value <= high:
                    raise ValueError("Invalid power measurement")
            elif value is not None:
                raise ValueError("Unavailable rail must not contain measurements")


def format_power(item):
    power = item.get("power") or {}
    elapsed_ms = max(0, int((time.monotonic() - item["power_seen"]) * 1000)) if "power_seen" in item else 0
    def fresh(rail):
        return rail.get("valid") and rail.get("age_ms", 3001) + elapsed_ms <= 3000
    result = []
    for name, label in (("internal_5v", "Internal 5 V"), ("vccint", "VCCINT core")):
        rail = power.get(name) or {}
        if not fresh(rail):
            result.append(f"{label}: unavailable")
        else:
            result.append(f"{label}: {rail['power_uw']/1e6:.3f} W / "
                          f"{rail['voltage_uv']/1e6:.3f} V / {rail['current_ua']/1e6:.3f} A "
                          f"(sensor {rail['temp_milli_c']/1000:.1f} °C, age {rail['age_ms'] + elapsed_ms} ms)")
        if rail.get("errors"):
            result[-1] += f"; read errors {rail['errors']}"
    rail = power.get("internal_5v") or {}
    if fresh(rail) and rail.get("power_uw", 0) > 0 and item.get("hashrate_hps") is not None:
        result.append(f"5 V efficiency: {item['hashrate_hps']/rail['power_uw']:.3f} MH/s/W")
    return " | ".join(result)


def merge_telemetry(previous, incoming):
    if "power" in incoming:
        incoming = dict(incoming, power_seen=incoming.get("seen", time.monotonic()))
    if incoming.get("partial") is True and incoming["uptime_ms"] >= previous.get("uptime_ms", 0):
        return dict(previous, **incoming)
    return incoming


def format_event(item):
    detail = item.get("details") or {}
    number = detail.get("job_number") or item.get("job_number", 0)
    job = detail.get("job_id") or item.get("job_id", "")
    text = item["event"]
    if job:
        text += f" | job #{number} / {job}"
    submission = detail.get("submission")
    if submission:
        text += " | " + json.dumps(submission, separators=(",", ":"))
    if detail.get("hash"):
        text += " | hash=" + detail["hash"]
    return text


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
                    for key in ["job_number", "shares_submitted", "shares_accepted", "shares_rejected",
                                "hardware_errors", "events_dropped", "hashes_total", "hashrate_sample_ms", "hashrate_hps"]:
                        if key in item and item[key] is not None and (type(item[key]) is not int or item[key] < 0):
                            raise ValueError("Invalid mining telemetry number")
                    if "job_id" in item and (not isinstance(item["job_id"], str) or len(item["job_id"]) > 127):
                        continue
                    detail = item.get("details")
                    if detail is not None:
                        if not isinstance(detail, dict):
                            continue
                        if not isinstance(detail.get("job_id", ""), str) or not isinstance(detail.get("hash", ""), str):
                            continue
                        submission = detail.get("submission")
                        if submission is not None and (not isinstance(submission, dict) or
                                submission.get("method") != "mining.submit" or
                                not isinstance(submission.get("params"), list) or len(submission["params"]) != 5):
                            continue
                    validate_power(item)
                    item = dict(item, ip=peer[0], seen=time.monotonic())
                    self.peers[peer[0]] = item["seen"]
                    self.messages.put(("telemetry", item))
                except (ValueError, TypeError, UnicodeError):
                    continue


DASHBOARD_VERSION = "1.1.0"


def format_versions(item):
    return (f"Lanes {item.get('engines', 'unknown')} | " + " | ".join(
        f"{label} {item.get(key) or 'unknown'}" for key, label in
        [("hw_version", "HW"), ("bootloader_version", "Boot"),
         ("application_version", "App")]))


def gui(args):
    import tkinter as tk
    from tkinter import ttk, messagebox
    root = tk.Tk()
    root.title(f"SCU35 Bitcoin lottery miners — Dashboard v{DASHBOARD_VERSION}")
    root.geometry("1320x800")
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
    columns = ("ip", "mac", "temp", "rate", "job", "shares", "network", "age")
    table = ttk.Treeview(pane, columns=columns, show="headings", height=8, selectmode="browse")
    for key, label, width in zip(columns, ["IP address", "Active MAC", "Die °C", "Measured hashrate", "Job # / pool ID", "Submitted / accepted / rejected", "Network", "Last seen"], [120, 155, 65, 140, 230, 210, 75, 70]):
        table.heading(key, text=label);table.column(key, width=width)
    table.pack(fill="x")
    live = tk.StringVar(value="Select a miner to inspect live counters.")
    ttk.Label(pane, textvariable=live, wraplength=1250).pack(anchor="w", pady=5)
    power_live = tk.StringVar(value="Power telemetry: select a miner")
    ttk.Label(pane, textvariable=power_live, wraplength=1250).pack(anchor="w", pady=5)
    ttk.Label(pane, text="Internal 5 V is not wall-plug power; VCCINT is core-only. Do not add these readings.").pack(anchor="w")
    form = ttk.LabelFrame(pane, text="Save complete configuration to selected miner", padding=10)
    form.pack(fill="x", pady=10)
    fields = {}
    for row, (key, label) in enumerate([("mac", "MAC (after reboot)"), ("host", "Pool host"), ("port", "Pool port"), ("worker", "Worker / wallet.worker"), ("password", "Pool password")]):
        ttk.Label(form, text=label).grid(row=row, column=0, sticky="w", padx=5)
        var = tk.StringVar(value="3333" if key == "port" else "")
        ttk.Entry(form, textvariable=var, width=75, show="*" if key == "password" else "").grid(row=row, column=1, sticky="ew", pady=2)
        fields[key] = var
    form.columnconfigure(1, weight=1)
    edit_password = tk.BooleanVar(value=False)
    ttk.Checkbutton(form, text="Replace stored password (unchecked = preserve; checked + blank = clear)",
                    variable=edit_password).grid(row=5, column=0, columnspan=2, sticky="w")
    settings_status = tk.StringVar(value="Select a miner to read its saved settings. Passwords are never read back.")
    ttk.Label(form, textvariable=settings_status, wraplength=1150).grid(row=6, column=0, columnspan=2, sticky="w")
    log = tk.Text(pane, height=9, state="disabled", wrap="word")
    log.pack(fill="both", expand=True)
    def append(text):
        log.configure(state="normal")
        log.insert("end", time.strftime("%H:%M:%S ") + text + "\n")
        if int(log.index("end-1c").split(".")[0]) > 500:
            log.delete("1.0", "100.0")
        log.see("end");log.configure(state="disabled")
    form_state = SettingsFormState()
    loading_form = False
    def edited(*_args):
        if not loading_form:
            form_state.edited()
    for var in fields.values():
        var.trace_add("write", edited)
    edit_password.trace_add("write", edited)
    def load_settings():
        selection = table.selection()
        if not selection:
            return
        token = form_state.begin_read()
        settings_status.set("Reading saved settings from EEPROM…")
        save_button.configure(state="disabled")
        def worker():
            try:
                messages.put(("settings_read", (token, read_settings(selection[0]))))
            except (OSError, ValueError) as exc:
                messages.put(("read_error", (token, str(exc))))
        threading.Thread(target=worker, daemon=True).start()
    def selected(_event=None):
        nonlocal loading_form
        selection = table.selection()
        if selection and selection[0] != form_state.ip:
            form_state.select(selection[0])
            loading_form = True
            for key, var in fields.items():
                var.set("3333" if key == "port" else "")
            fields["mac"].set(miners[selection[0]]["mac"])
            edit_password.set(False)
            loading_form = False
            load_settings()
    table.bind("<<TreeviewSelect>>", selected)
    def save():
        selection = table.selection()
        if not selection:
            messagebox.showerror("Select a miner", "Select a discovered miner first.");return
        ip = selection[0]
        try:
            raw = {key: var.get() for key, var in fields.items() if key != "password" or edit_password.get()}
            values = validate_settings(raw)
        except ValueError as exc:
            messagebox.showerror("Invalid settings", str(exc));return
        if not messagebox.askyesno("Write EEPROM", f"Save these settings to {ip}?\nPool settings reconnect immediately. MAC changes require a board reboot."):
            return
        save_button.configure(state="disabled")
        token = form_state.token()
        def worker():
            try:
                reply = configure(ip, values)
                messages.put(("saved", (token, reply)))
            except (OSError, ValueError) as exc:
                messages.put(("save_error", (token, str(exc))))
        threading.Thread(target=worker, daemon=True).start()
    save_button = ttk.Button(form, text="Save to EEPROM", command=save)
    save_button.grid(row=7, column=1, sticky="e", pady=6)
    save_button.configure(state="disabled")
    def reload_settings():
        if form_state.revision and not messagebox.askyesno("Reload settings", "Discard local edits and reload EEPROM settings?"):
            return
        load_settings()
    ttk.Button(form, text="Read EEPROM settings", command=reload_settings).grid(row=7, column=0, sticky="w")
    def update():
        nonlocal loading_form
        for _ in range(100):
            try:
                kind, value = messages.get_nowait()
            except queue.Empty:
                break
            if kind == "telemetry":
                ip = value["ip"]
                miners[ip] = merge_telemetry(miners.get(ip, {}), value)
                if not table.exists(ip):
                    table.insert("", "end", iid=ip);append(f"Discovered {ip} ({value['mac']})")
                identity = (value["uptime_ms"] // 1000, value["event_seq"])
                if value["event"] != "status" and last_events.get(ip) != identity:
                    append(f"{ip}: {format_event(value)}");last_events[ip] = identity
            elif kind == "settings_read":
                token, reply = value
                if token[:2] != form_state.token()[:2]:
                    continue
                save_button.configure(state="normal")
                if not form_state.accepts(token):
                    settings_status.set("Read completed; newer local edits were preserved. Use Read EEPROM settings to reload.")
                    continue
                loading_form = True
                for key in ("mac", "host", "port", "worker"):
                    fields[key].set(str(reply[key]))
                fields["password"].set("");edit_password.set(False)
                loading_form = False
                form_state.revision = 0
                note = "Saved EEPROM settings loaded" if reply["stored"] else "No valid EEPROM settings; defaults shown"
                note += "; password " + ("stored (preserved unless replaced)" if reply["password_set"] else "not set")
                if reply["mac"] != reply["active_mac"]:
                    note += f"; active MAC remains {reply['active_mac']} until reboot"
                settings_status.set(note)
            elif kind == "read_error":
                token, error = value
                if token[:2] == form_state.token()[:2]:
                    save_button.configure(state="normal")
                    settings_status.set("Read failed: " + error + ". Older firmware may need updating.")
            elif kind == "saved":
                token, reply = value;ip = token[0]
                if token[:2] == form_state.token()[:2]:
                    save_button.configure(state="normal")
                if reply["ok"]:
                    append(f"{ip}: settings saved; MAC changes need reboot")
                    if form_state.accepts(token):
                        load_settings()
                else:
                    messagebox.showerror("Save failed", str(reply.get("error", "Unknown error")))
            elif kind == "save_error":
                token, error = value
                if token[:2] == form_state.token()[:2]:
                    save_button.configure(state="normal")
                messagebox.showerror("Save failed", error)
            elif kind == "error":
                status.set(value)
        now = time.monotonic()
        for ip, item in miners.items():
            age = now - item["seen"]
            table.item(ip, values=(ip, item["mac"], f"{item['temp_centi']/100:.2f}",
                "stale" if age > 5 else format_hashrate(item), f"{item.get('job_number', '—')} / {item.get('job_id', '—')}",
                f"{item.get('shares_submitted', '—')} / {item.get('shares_accepted', '—')} / {item.get('shares_rejected', '—')}",
                "stale" if age > 5 else "up" if item.get("network_up") else "down", f"{age:.0f}s"))
        if form_state.ip in miners:
            item = miners[form_state.ip]
            freshness = "STALE — " if now-item["seen"] > 5 else ""
            power_live.set(freshness + format_power(item))
            live.set(f"{freshness}{form_state.ip}: pool {'authorized' if item.get('pool_authorized') else 'not authorized'} | "
                     f"mining {'active' if item.get('mining') else 'idle'} | completed hashes {item.get('hashes_total', 'unavailable')} | "
                     f"sample {item.get('hashrate_sample_ms', 0)} ms | hardware errors {item.get('hardware_errors', 0)} | "
                     f"events dropped {item.get('events_dropped', 0)} | {format_versions(item)}")
        status.set(f"{sum(now-m['seen'] < 5 for m in miners.values())} live / {len(miners)} discovered")
        root.after(100, update)
    def close():
        discovery.stopped.set();discovery.join(timeout=1);root.destroy()
    root.protocol("WM_DELETE_WINDOW", close)
    discovery.start();update();root.mainloop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version=f"SCU35 dashboard {DASHBOARD_VERSION}")
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
