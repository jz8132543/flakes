#!/usr/bin/env python3
"""Bounded ATS statistics bridge and independent, budgeted systemd recovery."""

import argparse
import copy
import fcntl
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
import itertools
import json
import math
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
import zlib


MAX_HTTP = 2 * 1024 * 1024
MAX_PROC = 8 * 1024 * 1024


def read_bytes(path, limit=MAX_PROC):
    raw = bytearray()
    with open(path, "rb") as source:
        # proc_sys_call_handler allocates the requested count, not the file size.
        # Small reads avoid ENOMEM while retaining the full input-size bound.
        while len(raw) <= limit:
            chunk = source.read(min(4096, limit + 1 - len(raw)))
            if not chunk:
                break
            raw.extend(chunk)
    if len(raw) > limit:
        raise ValueError("input exceeds sampling limit")
    return bytes(raw)


def read_text(path, limit=MAX_PROC):
    return read_bytes(path, limit).decode("ascii")


def command(args, timeout):
    # Commands have tiny, bounded outputs. Never capture worker logs or run ss.
    result = subprocess.run(args, timeout=timeout, capture_output=True, text=True,
                            check=True, env={**os.environ, "LC_ALL": "C"})
    if len(result.stdout) > 65536:
        raise ValueError("command output exceeds limit")
    return result.stdout.strip()


def http_json(port, path, timeout):
    # Numeric loopback only, no proxies, DNS, redirects, or bridge self-probes.
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    deadline = time.monotonic() + timeout
    timer = None
    try:
        connection.request("GET", path, headers={"Connection": "close", "Accept-Encoding": "gzip, deflate"})
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("HTTP deadline expired")
        transport = connection.sock

        def expire():
            try:
                # Shutdown also interrupts HTTPResponse's buffered socket file.
                transport.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        timer = threading.Timer(remaining, expire)
        timer.daemon = True
        timer.start()
        response = connection.getresponse()
        data = response.read(MAX_HTTP + 1)
        if response.status != 200 or len(data) > MAX_HTTP:
            raise ValueError("HTTP probe failed or exceeds limit")
        if response.getheader("Content-Type", "").split(";", 1)[0] not in (
                "application/json", "text/json", "text/javascript"):
            raise ValueError("HTTP probe is not JSON")
        encoding = response.getheader("Content-Encoding", "identity").strip().lower()
        if encoding in ("gzip", "deflate"):
            decoder = zlib.decompressobj(31 if encoding == "gzip" else 15)
            try:
                data = decoder.decompress(data, MAX_HTTP + 1)
            except zlib.error as error:
                raise ValueError("invalid compressed HTTP probe") from error
            if len(data) > MAX_HTTP or decoder.unconsumed_tail:
                raise ValueError("decompressed HTTP probe exceeds limit")
            if not decoder.eof or decoder.unused_data:
                raise ValueError("incomplete compressed HTTP probe")
        elif encoding not in ("", "identity"):
            raise ValueError("unsupported HTTP probe encoding")
        value = json.loads(data, parse_constant=lambda _: (_ for _ in ()).throw(
            ValueError("non-finite JSON")))
        if not isinstance(value, dict):
            raise ValueError("HTTP probe is not an object")
        return value
    finally:
        if timer:
            timer.cancel()
        connection.close()


def probe(traffic_ctl, timeout):
    if command([traffic_ctl, "server", "status"], timeout) != "Proxy -- on":
        raise ValueError("ATS worker is off")
    result = http_json(8089, "/_astats", timeout)
    stats = result.get("global")
    if not isinstance(stats, dict) or not stats or not all(
            isinstance(key, str)
            and isinstance(value, (str, int, float)) and not isinstance(value, bool)
            for key, value in stats.items()):
        raise ValueError("invalid ATS global statistics")
    # Reject unrelated JSON (e.g. a remapped origin) as a successful worker probe.
    if "proxy.process.http.current_client_connections" not in stats:
        raise ValueError("ATS connection metric is absent")
    normalized = {}
    for key, value in stats.items():
        if isinstance(value, str):
            try:
                value = int(value)
            except ValueError:
                try:
                    value = float(value)
                except ValueError:
                    pass
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("non-finite ATS counter")
        if isinstance(value, str) and (key == "proxy.process.http.current_client_connections"
                                      or key.startswith("plugin.remap_stats.")):
            raise ValueError("invalid ATS numeric counter")
        normalized[key] = value
    # astats (unlike stats_over_http) requires numeric JSON for remap counters.
    return normalized


def pressure(raw, category):
    for line in raw.splitlines():
        fields = line.split()
        if fields and fields[0] == category:
            values = dict(field.split("=", 1) for field in fields[1:])
            value = float(values["avg10"]) / 100.0
            if not math.isfinite(value) or not 0 <= value <= 1:
                break
            return value
    raise ValueError("missing or invalid PSI")


def tcp_counts(raw, port=8089):
    waiting = queue = 0
    for line in raw.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 5:
            raise ValueError("invalid TCP table")
        if int(fields[1].rsplit(":", 1)[1], 16) != port:
            continue
        if fields[3] == "08":
            waiting += 1
        elif fields[3] == "0A":
            queue = max(queue, int(fields[4].split(":")[1], 16))
    return waiting, queue


class Sampler:
    def __init__(self, config, proc=Path("/proc")):
        self.config = config
        self.proc = proc
        self.previous_cpu = None
        self.payload = {"ats": {}, "system": {"notAvailable": True},
                        "cdn": {"schema": 1, "sampled_at": 0.0, "ready": False}}
        self.sample_mono = None
        self.lock = threading.Lock()

    def system_sample(self):
        def read(name):
            return read_text(self.proc / name)

        memory = {line.split(":", 1)[0]: int(line.split()[1])
                  for line in read("meminfo").splitlines()}
        total = memory["MemTotal"]
        if total <= 0:
            raise ValueError("invalid physical memory")
        cpu = tuple(map(int, read("stat").splitlines()[0].split()[1:9]))
        if len(cpu) != 8:
            raise ValueError("invalid CPU counters")
        old = self.previous_cpu
        self.previous_cpu = cpu
        # No interval baseline yet: fail closed for the first sample.
        if old is None or any(new < before for new, before in zip(cpu, old)):
            raise ValueError("CPU sampling baseline unavailable")
        elapsed = sum(cpu) - sum(old)
        if elapsed <= 0:
            raise ValueError("CPU counters did not advance")
        waiting = queue = 0
        for name in ("net/tcp", "net/tcp6"):
            try:
                count, backlog = tcp_counts(read(name))
            except FileNotFoundError:
                if name != "net/tcp6":
                    raise
                continue
            waiting += count
            queue = max(queue, backlog)
        sockstat = [line.split() for line in read("net/sockstat").splitlines()
                    if line.startswith("TCP:")]
        tcp_memory = int(sockstat[0][sockstat[0].index("mem") + 1])
        high = int(read("sys/net/ipv4/tcp_mem").split()[2])
        if high <= 0:
            raise ValueError("invalid TCP high watermark")
        interface = self.config.get("interface")
        if not interface:
            routes = [line.split() for line in read("net/route").splitlines()[1:]]
            defaults = [route for route in routes if route[1] == "00000000"
                        and int(route[3], 16) & 1 and route[0] != "lo"]
            if defaults:
                interface = min(defaults, key=lambda route: int(route[6]))[0]
            else:
                routes6 = [line.split() for line in read("net/ipv6_route").splitlines()]
                defaults6 = [route for route in routes6 if route[0] == "0" * 32
                             and route[1] == "00" and route[-1] != "lo"
                             and int(route[8], 16) & 1]
                if defaults6:
                    interface = min(defaults6, key=lambda route: int(route[5], 16))[-1]
        devices = {}
        for line in read("net/dev").splitlines()[2:]:
            name, counters = line.split(":", 1)
            fields = counters.split()
            if len(fields) != 16 or any(int(field) < 0 for field in fields):
                raise ValueError("invalid interface counters")
            devices[name.strip()] = " ".join(fields)
        if interface not in devices or interface == "lo":
            raise ValueError("no monitored egress interface")
        loadavg = read("loadavg").strip()
        if len(loadavg.split()) != 5:
            raise ValueError("invalid load average")
        capacity = min(self.config["listenBacklog"], int(read("sys/net/core/somaxconn")))
        return {
            "inf.name": "eth0", "inf.speed": self.config["bandwidthMbps"],
            "proc.net.dev": "eth0: " + devices[interface], "proc.loadavg": loadavg,
        }, {
            "memory_available_ratio": min(1.0, max(0.0, memory["MemAvailable"] / total)),
            "cpu_steal_ratio": (cpu[7] - old[7]) / elapsed,
            "cpu_pressure": pressure(read("pressure/cpu"), "some"),
            "memory_pressure": pressure(read("pressure/memory"), "full"),
            "tcp_memory_ratio": tcp_memory / high,
            "close_wait": waiting, "listener_queue": queue, "listener_capacity": capacity,
            "interface": interface,
        }

    def sample(self):
        # Timestamp completion separately from freshness's monotonic clock.
        payload = {"ats": {}, "system": {"notAvailable": True},
                   "cdn": {"schema": 1, "ready": False}}
        errors = []
        try:
            system, metrics = self.system_sample()
            payload["system"].update(system)
            payload["cdn"].update(metrics)
        except (OSError, ValueError, IndexError, KeyError) as error:
            errors.append(str(error))
        try:
            payload["ats"] = probe(self.config["trafficCtl"], self.config["probeTimeoutSec"])
            capacity = float(payload["ats"].get("proxy.process.cache.bytes_total", 0))
            if not math.isfinite(capacity) or capacity <= 0:
                raise ValueError("ATS cache storage is not initialized")
            payload["cdn"]["cache_capacity_bytes"] = capacity
            remaps = read_text(self.config["remapConfig"], 1024 * 1024)
            if not any(line.split() and line.split()[0] in ("map", "regex_map")
                       for line in remaps.splitlines()):
                raise ValueError("ATS remap configuration is not ready")
            if config_digest(self.config["configDirectory"]) != read_text(
                    self.config["loadedConfigHash"], 256).strip():
                raise ValueError("ATS configuration is pending reload")
        except (OSError, ValueError, subprocess.SubprocessError, http.client.HTTPException) as error:
            errors.append(str(error))
        payload["cdn"]["ready"] = not errors
        payload["cdn"]["sampled_at"] = time.time()
        payload["cdn"]["reason"] = "; ".join(errors)[:256]
        payload["system"]["notAvailable"] = bool(errors)
        with self.lock:
            self.payload = payload
            self.sample_mono = time.monotonic()

    def response(self, now=None):
        with self.lock:
            payload = copy.deepcopy(self.payload)
            sampled = self.sample_mono
        now = time.monotonic() if now is None else now
        if sampled is None or not 0 <= now - sampled <= self.config["staleAfterSec"]:
            payload["cdn"].update(ready=False, reason="sampling unavailable or stale")
            payload["system"]["notAvailable"] = True
        return (200 if payload["cdn"]["ready"] else 503), payload

    def run(self):
        while True:
            start = time.monotonic()
            self.sample()
            # One producer only. No overlapping work or catch-up loops.
            time.sleep(max(0.1, self.config["intervalSec"] - (time.monotonic() - start)))


def serve(config):
    sampler = Sampler(config)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(2)

        def do_GET(self):
            if self.path not in ("/_astats", "/healthz"):
                self.send_error(404)
                return
            code, payload = sampler.response()
            data = json.dumps(payload, allow_nan=False, separators=(",", ":")).encode()
            self.send_response(code)
            # Traffic Monitor 8.0.2 compares this header as an exact string.
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_args):
            pass

    threading.Thread(target=sampler.run, daemon=True, name="ats-sampler").start()
    # Single request handler bounds thread and connection memory. Sampling is independent.
    class BridgeServer(HTTPServer):
        request_queue_size = 32

    server = BridgeServer(("127.0.0.1", 9130), Handler)
    server.serve_forever()


def recovery_action(state, now, healthy, active, config):
    if now < state.get("lastChecked", now):
        # A wall-clock rollback must not erase a persistent restart budget.
        state["attempts"] = [now] * config["maxRecoveries"]
        state["cooldownUntil"] = now + config["cooldownSec"]
    state["lastChecked"] = now
    attempts = [stamp for stamp in state.get("attempts", [])
                if now - config["recoveryWindowSec"] < stamp <= now]
    state["attempts"] = attempts
    if now < state.get("cooldownUntil", 0):
        return "stop" if active else None
    if healthy:
        state["failures"] = 0
        return None
    state["failures"] = state.get("failures", 0) + 1
    if active and state["failures"] < config["failureThreshold"]:
        return None
    if len(attempts) >= config["maxRecoveries"]:
        state["cooldownUntil"] = now + config["cooldownSec"]
        state["failures"] = 0
        return "stop" if active else None
    state["attempts"].append(now)
    state["failures"] = 0
    return "restart" if active else "start"


def atomic_json(path, data):
    temporary = path.with_suffix(".tmp")
    with open(temporary, "w") as target:
        json.dump(data, target, allow_nan=False)
        target.flush()
        os.fsync(target.fileno())
    os.replace(temporary, path)


def recover(config):
    directory = Path("/var/lib/atc-edge-recovery")
    with open(directory / "lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        state_path = directory / "state.json"
        try:
            state = json.loads(read_text(state_path, 65536))
            if not isinstance(state, dict) or not isinstance(state.get("attempts", []), list):
                raise ValueError("invalid recovery state")
            for value in state.get("attempts", []) + [
                    state.get("cooldownUntil", 0), state.get("lastChecked", 0),
                    state.get("failures", 0)]:
                if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                    raise ValueError("invalid recovery counters")
        except FileNotFoundError:
            state = {}
        except (ValueError, TypeError):
            # Corrupt budget is not permission to start a restart storm.
            state = {"cooldownUntil": time.time() + config["cooldownSec"]}
        now = time.time()
        status = dict(line.split("=", 1) for line in command([
            config["systemctl"], "show", "trafficserver.service",
            "--property=ActiveState,ExecMainStartTimestampMonotonic"], 3).splitlines())
        active = status["ActiveState"] in ("active", "activating", "deactivating")
        started = int(status.get("ExecMainStartTimestampMonotonic", "0")) / 1000000
        if now >= state.get("cooldownUntil", 0) and active and started and (
                0 <= time.monotonic() - started < config["startupGraceSec"]):
            return
        healthy = False
        if now >= state.get("cooldownUntil", 0):
            try:
                cached = http_json(9130, "/healthz", 1)["cdn"]
                age = now - cached["sampled_at"]
                healthy = cached["ready"] is True and 0 <= age <= config["staleAfterSec"]
            except (OSError, ValueError, KeyError, TypeError, http.client.HTTPException):
                pass
            if not healthy:
                # Confirm failure directly if the bridge itself is down. Ops is never consulted.
                try:
                    probe(config["trafficCtl"], config["probeTimeoutSec"])
                    healthy = True
                except (OSError, ValueError, subprocess.SubprocessError, http.client.HTTPException) as error:
                    print(f"ATS liveness probe failed: {type(error).__name__}: {str(error)[:200]}", flush=True)
        action = recovery_action(state, now, healthy, active, config)
        # Persist budget BEFORE the operation, including failed/timed-out starts.
        atomic_json(state_path, state)
        if action:
            print(f"ATS recovery: {action}; attempts={len(state['attempts'])}; "
                  f"cooldownUntil={state.get('cooldownUntil', 0)}", flush=True)
            command([config["systemctl"], action, "trafficserver.service"],
                    config["actionTimeoutSec"])


def config_digest(directory):
    digest = hashlib.sha256()
    paths = list(itertools.islice(Path(directory).rglob("*"), 10001))
    if len(paths) > 10000:
        raise ValueError("configuration tree exceeds file limit")
    total = 0
    for path in sorted(paths):
        if path.suffix not in (".config", ".yaml") or not path.is_file():
            continue
        digest.update(str(path.relative_to(directory)).encode())
        digest.update(b"\0")
        data = read_bytes(path, 4 * 1024 * 1024)
        total += len(data)
        if total > 32 * 1024 * 1024:
            raise ValueError("configuration tree exceeds byte limit")
        digest.update(data)
        digest.update(b"\0")
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config")
    parser.add_argument("--recover", action="store_true")
    parser.add_argument("--digest")
    args = parser.parse_args()
    if args.digest:
        print(config_digest(args.digest))
        return
    config = json.loads(read_text(args.config))
    if args.recover:
        recover(config)
    else:
        serve(config)


if __name__ == "__main__":
    main()
