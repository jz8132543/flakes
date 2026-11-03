#!/usr/bin/env python3
"""Offline edge bridge/recovery tests. No real ATS or systemd operations."""

import importlib.util
import io
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import zlib
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "edge_health", ROOT / "nixos/modules/services/atc/edge-health.py")
EDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EDGE)
CONFIG = {
    "trafficCtl": "/not-a-real-traffic-ctl", "probeTimeoutSec": 2,
    "intervalSec": 5, "staleAfterSec": 15, "interface": None,
    "listenBacklog": 512, "bandwidthMbps": 700,
    "failureThreshold": 2, "maxRecoveries": 3, "recoveryWindowSec": 600,
    "cooldownSec": 300,
}
STATS = {"proxy.process.http.current_client_connections": "1",
          "proxy.process.http.cache_total_hits": "42", "server": "9.2.11",
          "proxy.process.cache.bytes_total": "268435456"}
NUMERIC_STATS = {"proxy.process.http.current_client_connections": 1,
                  "proxy.process.http.cache_total_hits": 42, "server": "9.2.11",
                  "proxy.process.cache.bytes_total": 268435456}


def socket_row(port=8089, state="08", queue=0):
    return f"0: 0100007F:{port:04X} 00000000:0000 {state} 00000000:{queue:08X}\n"


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="atc-edge-", dir="/tmp/kilo")
        self.addCleanup(self.temporary.cleanup)
        self.proc = Path(self.temporary.name)
        files = {
            "meminfo": "MemTotal: 1000 kB\nMemAvailable: 250 kB\n",
            "stat": "cpu 100 0 0 100 0 0 0 10\n",
            "net/tcp": "header\n" + socket_row() + socket_row(state="0A", queue=10),
            "net/tcp6": "header\n" + socket_row() + socket_row(port=443),
            "net/sockstat": "sockets: used 10\nTCP: inuse 1 orphan 0 tw 0 alloc 2 mem 250\n",
            "sys/net/ipv4/tcp_mem": "100 150 200\n",
            "sys/net/core/somaxconn": "1024\n",
            "net/route": "Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT\n"
                         "ens3 00000000 01020304 0003 0 0 10 00000000 0 0 0\n",
            "net/dev": "header\nheader\n  lo: " + " ".join(["0"] * 16) + "\n"
                       "  ens3: " + " ".join(str(n) for n in range(16)) + "\n",
            "loadavg": "0.10 0.20 0.30 1/200 1234\n",
            "pressure/cpu": "some avg10=12.50 avg60=1.00 avg300=1.00 total=10\n",
            "pressure/memory": "some avg10=50.00 total=10\nfull avg10=1.25 total=1\n",
        }
        for name, value in files.items():
            path = self.proc / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
        self.remap = self.proc / "remap.config"
        self.remap.write_text("map http://cloud.example/ https://origin.example/\n")
        self.loaded = self.proc / "loaded_config_hash"
        self.loaded.write_text(EDGE.config_digest(self.proc))
        self.sampler = EDGE.Sampler({**CONFIG, "remapConfig": str(self.remap),
                                   "configDirectory": str(self.proc),
                                   "loadedConfigHash": str(self.loaded)}, self.proc)

    def warm(self):
        with patch.object(EDGE, "probe", return_value=STATS):
            self.sampler.sample()
            self.assertEqual(self.sampler.response()[0], 503)
            (self.proc / "stat").write_text("cpu 110 0 0 110 0 0 0 15\n")
            self.sampler.sample()

    def test_ready_payload_exact_monitor_contract(self):
        self.warm()
        code, payload = self.sampler.response()
        self.assertEqual(code, 200)
        self.assertEqual(payload["ats"], STATS)
        system, cdn = payload["system"], payload["cdn"]
        self.assertEqual(system["inf.name"], "eth0")
        self.assertEqual(system["inf.speed"], 700)
        self.assertEqual(system["proc.net.dev"], "eth0: " + " ".join(map(str, range(16))))
        self.assertEqual(len(system["proc.net.dev"].split(":")), 2)
        self.assertEqual(system["proc.loadavg"], "0.10 0.20 0.30 1/200 1234")
        self.assertIs(system["notAvailable"], False)
        self.assertIs(cdn["ready"], True)
        self.assertEqual(cdn["schema"], 1)
        self.assertIsInstance(cdn["sampled_at"], float)
        self.assertEqual(cdn["memory_available_ratio"], 0.25)
        self.assertEqual(cdn["cpu_steal_ratio"], 0.2)
        self.assertEqual(cdn["cpu_pressure"], 0.125)
        self.assertEqual(cdn["memory_pressure"], 0.0125)
        self.assertEqual(cdn["tcp_memory_ratio"], 1.25)
        self.assertEqual(cdn["close_wait"], 2)
        self.assertEqual(cdn["listener_queue"], 10)
        self.assertEqual(cdn["listener_capacity"], 512)
        json.dumps(payload, allow_nan=False)

    def test_http_response_never_probes(self):
        self.warm()
        with patch.object(EDGE, "probe", side_effect=AssertionError("per-request RPC")):
            for _ in range(20):
                self.assertEqual(self.sampler.response()[0], 200)
        _, first = self.sampler.response()
        first["cdn"]["ready"] = False
        self.assertEqual(self.sampler.response()[0], 200)

    def test_stale_and_clock_rollback_fail_closed(self):
        self.warm()
        for now in (self.sampler.sample_mono + 16, self.sampler.sample_mono - 1):
            code, payload = self.sampler.response(now)
            self.assertEqual(code, 503)
            self.assertIs(payload["cdn"]["ready"], False)
            self.assertIs(payload["system"]["notAvailable"], True)

    def test_failed_sample_replaces_previous_success(self):
        self.warm()
        with patch.object(EDGE, "probe", side_effect=ValueError("worker off")):
            self.sampler.sample()
        code, payload = self.sampler.response()
        self.assertEqual(code, 503)
        self.assertEqual(payload["ats"], {})

    def test_worker_is_not_ready_without_cache_or_remap(self):
        self.warm()
        with patch.object(EDGE, "probe", return_value={**STATS, "proxy.process.cache.bytes_total": 0}):
            self.sampler.sample()
        self.assertEqual(self.sampler.response()[0], 503)
        self.assertIn("cache storage", self.sampler.response()[1]["cdn"]["reason"])
        self.remap.write_text("# generated empty remap file\n\n")
        with patch.object(EDGE, "probe", return_value=STATS):
            self.sampler.sample()
        self.assertEqual(self.sampler.response()[0], 503)
        self.assertIn("remap configuration", self.sampler.response()[1]["cdn"]["reason"])

    def test_pending_reload_is_not_published_as_ready(self):
        self.warm()
        self.remap.write_text("map http://changed.example/ https://origin.example/\n")
        (self.proc / "stat").write_text("cpu 120 0 0 120 0 0 0 20\n")
        with patch.object(EDGE, "probe", return_value=STATS):
            self.sampler.sample()
            self.assertEqual(self.sampler.response()[0], 503)
            self.assertIn("pending reload", self.sampler.response()[1]["cdn"]["reason"])
            self.loaded.write_text(EDGE.config_digest(self.proc))
            (self.proc / "stat").write_text("cpu 130 0 0 130 0 0 0 25\n")
            self.sampler.sample()
            self.assertEqual(self.sampler.response()[0], 200)

    def test_missing_psi_or_interface_is_not_zero_pressure(self):
        for name in ("pressure/memory", "net/route"):
            with self.subTest(name=name):
                self.warm()
                path = self.proc / name
                original = path.read_text()
                path.unlink()
                with patch.object(EDGE, "probe", return_value=STATS):
                    self.sampler.sample()
                self.assertEqual(self.sampler.response()[0], 503)
                path.write_text(original)

    def test_proc_and_psi_inputs_are_bounded(self):
        with self.assertRaises(ValueError):
            EDGE.read_text(self.proc / "net/dev", limit=10)
        for value in ("nan", "101", "-1"):
            with self.assertRaises(ValueError):
                EDGE.pressure(f"some avg10={value}", "some")

    def test_large_proc_inputs_use_small_reads_and_retain_total_bound(self):
        class SysctlFile(io.BytesIO):
            def read(self, size=-1):
                if not 0 <= size <= 4096:
                    raise OSError(12, "Cannot allocate memory")
                return super().read(size)

        data = b"x" * (1024 * 1024)
        with patch.object(EDGE, "open", return_value=SysctlFile(data), create=True):
            self.assertEqual(EDGE.read_bytes("fake-proc"), data)
        with patch.object(EDGE, "open", return_value=SysctlFile(data), create=True):
            with self.assertRaises(ValueError):
                EDGE.read_bytes("fake-proc", limit=4096)

    def test_tcp_counts_include_only_target_port(self):
        self.assertEqual(EDGE.tcp_counts("header\n" + socket_row() + socket_row(port=443)
                                        + socket_row(state="0A", queue=123)), (1, 123))

    def test_listener_queue_is_worst_listener_not_sum(self):
        self.assertEqual(EDGE.tcp_counts("header\n" + socket_row(state="0A", queue=300)
                                        + socket_row(state="0A", queue=400)), (0, 400))
        (self.proc / "net/tcp6").write_text("header\n" + socket_row(state="0A", queue=400))
        self.warm()
        self.assertEqual(self.sampler.response()[1]["cdn"]["listener_queue"], 400)

    def test_config_digest_excludes_changing_t3c_metadata(self):
        path = self.proc / "records.config"
        path.write_text("CONFIG proxy.config.net.listen_backlog INT 512\n")
        first = EDGE.config_digest(self.proc)
        (self.proc / "t3c-apply-metadata.json").write_text('{"now": 1}')
        self.assertEqual(EDGE.config_digest(self.proc), first)
        path.write_text("CONFIG proxy.config.net.listen_backlog INT 1024\n")
        self.assertNotEqual(EDGE.config_digest(self.proc), first)


class RecoveryTest(unittest.TestCase):
    def test_readiness_failure_does_not_restart_a_live_worker(self):
        with tempfile.TemporaryDirectory(prefix="atc-recovery-", dir="/tmp/kilo") as tmp:
            directory = Path(tmp)
            (directory / "state.json").write_text('{"failures": 1}')
            config = {**CONFIG, "systemctl": "fake", "startupGraceSec": 30, "actionTimeoutSec": 10}
            with patch.object(EDGE, "Path", return_value=directory), patch.object(
                    EDGE.time, "time", return_value=1000), patch.object(
                    EDGE, "command", return_value="ActiveState=active\nExecMainStartTimestampMonotonic=0") as command, patch.object(
                    EDGE, "http_json", return_value={"cdn": {"ready": False, "sampled_at": 1000}}), patch.object(
                    EDGE, "probe", return_value=NUMERIC_STATS) as probe:
                EDGE.recover(config)
                self.assertEqual(command.call_count, 1)
                probe.assert_called_once()
            self.assertEqual(json.loads((directory / "state.json").read_text())["failures"], 0)

    def test_root_recovery_persists_budget_before_systemctl(self):
        with tempfile.TemporaryDirectory(prefix="atc-recovery-", dir="/tmp/kilo") as tmp:
            directory = Path(tmp)
            state_file = directory / "state.json"
            state_file.write_text('{"failures": 1}')
            operations = []

            def command(args, timeout):
                if args[1] == "show":
                    return "ActiveState=active\nExecMainStartTimestampMonotonic=0"
                operations.append(args[1])
                persisted = json.loads(state_file.read_text())
                self.assertEqual(persisted["attempts"], [1000])
                raise subprocess.TimeoutExpired("systemctl", timeout)

            config = {**CONFIG, "systemctl": "fake-systemctl", "startupGraceSec": 30,
                      "actionTimeoutSec": 10}
            with patch.object(EDGE, "Path", return_value=directory), patch.object(
                    EDGE.time, "time", return_value=1000), patch.object(
                    EDGE, "command", side_effect=command), patch.object(
                    EDGE, "http_json", side_effect=ValueError("bridge unavailable")), patch.object(
                    EDGE, "probe", side_effect=ValueError("worker off")):
                with self.assertRaises(subprocess.TimeoutExpired):
                    EDGE.recover(config)
            self.assertEqual(operations, ["restart"])

    def test_corrupt_budget_stops_manager_not_restarts(self):
        with tempfile.TemporaryDirectory(prefix="atc-recovery-", dir="/tmp/kilo") as tmp:
            directory = Path(tmp)
            (directory / "state.json").write_text("[]")
            config = {**CONFIG, "systemctl": "fake-systemctl", "startupGraceSec": 30,
                      "actionTimeoutSec": 10}
            with patch.object(EDGE, "Path", return_value=directory), patch.object(
                    EDGE.time, "time", return_value=1000), patch.object(
                    EDGE, "command", side_effect=[
                        "ActiveState=active\nExecMainStartTimestampMonotonic=0", ""
                    ]) as command, patch.object(EDGE, "probe") as probe:
                EDGE.recover(config)
                self.assertEqual(command.call_args.args[0],
                                 ["fake-systemctl", "stop", "trafficserver.service"])
                probe.assert_not_called()
                self.assertEqual(json.loads((directory / "state.json").read_text())[
                    "cooldownUntil"], 1300)

    def test_failure_threshold_and_three_attempt_budget(self):
        state = {}
        for start in (1000, 1040, 1080):
            self.assertIsNone(EDGE.recovery_action(state, start, False, True, CONFIG))
            self.assertEqual(EDGE.recovery_action(state, start + 10, False, True, CONFIG), "restart")
        self.assertIsNone(EDGE.recovery_action(state, 1110, False, True, CONFIG))
        self.assertEqual(EDGE.recovery_action(state, 1120, False, True, CONFIG), "stop")
        self.assertEqual(len(state["attempts"]), 3)
        self.assertEqual(state["cooldownUntil"], 1420)
        # Even an external start with a healthy worker does not bypass cooldown.
        self.assertEqual(EDGE.recovery_action(state, 1130, True, True, CONFIG), "stop")
        self.assertIsNone(EDGE.recovery_action(state, 1131, False, False, CONFIG))

    def test_failed_start_consumes_budget_then_cools_down(self):
        state = {}
        for now in (1000, 1010, 1020):
            self.assertEqual(EDGE.recovery_action(state, now, False, False, CONFIG), "start")
        self.assertIsNone(EDGE.recovery_action(state, 1030, False, False, CONFIG))
        self.assertEqual(state["cooldownUntil"], 1330)
        self.assertEqual(EDGE.recovery_action(state, 1631, False, False, CONFIG), "start")

    def test_health_resets_failure_not_restart_budget(self):
        state = {"attempts": [990], "failures": 1}
        self.assertIsNone(EDGE.recovery_action(state, 1000, True, True, CONFIG))
        self.assertEqual(state["attempts"], [990])
        self.assertEqual(state["failures"], 0)

    def test_wall_clock_rollback_cannot_reset_budget(self):
        state = {"attempts": [1000], "lastChecked": 1001}
        self.assertEqual(EDGE.recovery_action(state, 900, False, True, CONFIG), "stop")
        self.assertEqual(len(state["attempts"]), 3)


class ProbeTest(unittest.TestCase):
    def test_compressed_http_is_bounded_and_validated(self):
        payload = json.dumps({"global": STATS}).encode()
        for encoding, bits in (("deflate", 15), ("gzip", 31)):
            encoder = zlib.compressobj(wbits=bits)
            encoded = encoder.compress(payload) + encoder.flush()

            class Response:
                status = 200

                def read(self, size):
                    return encoded

                def getheader(self, name, default=None):
                    return {"Content-Type": "application/json", "Content-Encoding": encoding}.get(name, default)

            class Connection:
                sock = None

                def request(self, *args, **kwargs):
                    pass

                def getresponse(self):
                    return Response()

                def close(self):
                    pass

            with patch.object(EDGE.http.client, "HTTPConnection", return_value=Connection()):
                self.assertEqual(EDGE.http_json(1, "/", 1), {"global": STATS})
                encoded = encoded[:-1]
                with self.assertRaises(ValueError):
                    EDGE.http_json(1, "/", 1)
                encoder = zlib.compressobj(wbits=bits)
                encoded = encoder.compress(b"x" * (EDGE.MAX_HTTP + 1)) + encoder.flush()
                with self.assertRaises(ValueError):
                    EDGE.http_json(1, "/", 1)

    def test_worker_off_or_rpc_timeout_never_probes_listener(self):
        for failure in ("Proxy -- off", subprocess.TimeoutExpired("ctl", 2)):
            with patch.object(EDGE, "command") as command, patch.object(EDGE, "http_json") as http:
                if isinstance(failure, Exception):
                    command.side_effect = failure
                else:
                    command.return_value = failure
                with self.assertRaises((ValueError, subprocess.TimeoutExpired)):
                    EDGE.probe("ctl", 2)
                http.assert_not_called()

    def test_json_requires_actual_ats_metrics_but_keeps_server_version(self):
        with patch.object(EDGE, "command", return_value="Proxy -- on"):
            with patch.object(EDGE, "http_json", return_value={"global": STATS}):
                self.assertEqual(EDGE.probe("ctl", 2), NUMERIC_STATS)
            for value in ({}, {"global": {}}, {"global": {"unrelated": 1}}, {"global": []}):
                with patch.object(EDGE, "http_json", return_value=value):
                    with self.assertRaises(ValueError):
                        EDGE.probe("ctl", 2)

    def test_remap_counters_are_numeric_and_never_fabricated(self):
        stats = {**STATS, "plugin.remap_stats.code.in_bytes": "123",
                 "proxy.process.cache.ram_cache.hit_ratio": "0.25"}
        with patch.object(EDGE, "command", return_value="Proxy -- on"), patch.object(
                EDGE, "http_json", return_value={"global": stats}):
            result = EDGE.probe("ctl", 2)
            self.assertEqual(result["plugin.remap_stats.code.in_bytes"], 123)
            self.assertEqual(result["proxy.process.cache.ram_cache.hit_ratio"], 0.25)
            stats["plugin.remap_stats.code.in_bytes"] = "unknown"
            with self.assertRaises(ValueError):
                EDGE.probe("ctl", 2)

    def test_trickling_http_has_wall_time_deadline(self):
        server = socket.socket()
        self.addCleanup(server.close)
        server.bind(("127.0.0.1", 0))
        server.listen(1)

        def trickle():
            client, _ = server.accept()
            with client:
                client.recv(4096)
                try:
                    for _ in range(10):
                        client.sendall(b"H")
                        time.sleep(0.05)
                except OSError:
                    pass

        thread = threading.Thread(target=trickle, daemon=True)
        thread.start()
        start = time.monotonic()
        with self.assertRaises((OSError, ValueError, EDGE.http.client.HTTPException)):
            EDGE.http_json(server.getsockname()[1], "/_astats", 0.15)
        self.assertLess(time.monotonic() - start, 0.5)
        thread.join(timeout=1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
