#!/usr/bin/env python3
"""Deterministic CDN scheduler and loopback DNS regression tests.

Run using the repository's locked input, without a global registry:
  nix shell --impure --expr 'let f = builtins.getFlake (toString ./.);
    p = import f.inputs.nixpkgs { system = builtins.currentSystem; };
    in p.python3.withPackages (ps: [ ps.dnslib ])' -c python3 tests/atc-steering.py
All health/pressure inputs are fixtures; network tests bind only loopback.
Set ATC_TEST_COREDNS to the locked CoreDNS binary to include its front door.
"""

import copy
from collections import Counter
from datetime import datetime, timezone
import http.client
from http.server import BaseHTTPRequestHandler
import importlib.util
import json
import logging
import os
from pathlib import Path
import random
import socket
import struct
import subprocess
import sys
import threading
import tempfile
import time
import unittest

from dnslib import DNSRecord, EDNS0, QTYPE, RCODE


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("steering", ROOT / "nixos/modules/services/atc/steering.py")
steering = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = steering
SPEC.loader.exec_module(steering)
logging.disable(logging.CRITICAL)

CONFIG = {
    "zone": "cdn.example.test", "nameservers": ["control.example.test"],
    "admin": "admin.example.test", "ttl": 30, "max_age": 20,
    "recovery_successes": 3, "slow_start": 60,
    "edges": [
        {"name": "small", "ipv4": "192.0.2.5", "ipv6": None, "weight": 5},
        {"name": "large", "ipv4": "192.0.2.8", "ipv6": "2001:db8::8", "weight": 8},
    ],
    "origins": {
        "control": {"ipv4": "192.0.2.1", "ipv6": "2001:db8::1"},
        "other": {"ipv4": "192.0.2.2", "ipv6": None},
    },
    "services": {"code": "control", "chat": "control", "office": "other", "unknown": "missing"},
    "apex_origin": "control", "origin_bypass_services": ["chat"],
}


class Clock:
    def __init__(self):
        self.now = 1800000000.0
        self.tick = 100.0

    def advance(self, seconds=5):
        self.now += seconds
        self.tick += seconds


def fixtures(clock):
    stamp = datetime.fromtimestamp(clock.now, timezone.utc).isoformat()
    monitor = {"caches": {
        name: {"isAvailable": True, "ipv4Available": True, "ipv6Available": name == "large",
               "lastPoll": stamp, "status": "REPORTED"}
        for name in ("small", "large")
    }}
    metrics = {name: {"cdn": {
        "schema": 1, "sampled_at": clock.now, "ready": True,
        "memory_available_ratio": 0.5, "cpu_steal_ratio": 0.0,
        "cpu_pressure": 0.0, "memory_pressure": 0.0, "tcp_memory_ratio": 0.1,
        "close_wait": 0, "listener_queue": 0, "listener_capacity": 512,
    }} for name in ("small", "large")}
    return monitor, metrics


class SteeringTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.config = copy.deepcopy(CONFIG)
        self.scheduler = steering.Scheduler(self.config, random.Random(83),
                                            wall=lambda: self.clock.now, monotonic=lambda: self.clock.tick)
        self.authority = steering.Authority(self.scheduler)

    def update(self):
        monitor, metrics = fixtures(self.clock)
        self.scheduler.update(monitor, metrics)
        return monitor, metrics

    def prime(self):
        for _ in range(16):
            self.update()
            self.clock.advance()

    def query(self, name="code", kind="A"):
        fqdn = f"{name}.cdn.example.test" if name else "cdn.example.test"
        return self.authority.resolve(DNSRecord.question(fqdn, kind))[0]

    def addresses(self, reply):
        return [str(rr.rdata) for rr in reply.rr if rr.rtype in (QTYPE.A, QTYPE.AAAA)]

    def test_startup_and_all_false_fallback_are_service_specific(self):
        self.assertEqual(self.addresses(self.query()), ["192.0.2.1"])
        self.prime()
        monitor, metrics = fixtures(self.clock)
        for cache in monitor["caches"].values():
            cache.update(isAvailable=False, ipv4Available=False, ipv6Available=False)
        self.scheduler.update(monitor, metrics)
        self.assertEqual(self.scheduler.choose("ipv4"), [])
        for service, expected in (("code", "192.0.2.1"), ("office", "192.0.2.2"), ("", "192.0.2.1")):
            self.assertEqual(self.addresses(self.query(service)), [expected])
        self.assertEqual(self.query("unknown").header.rcode, RCODE.SERVFAIL)

    def test_apex_without_explicit_origin_fails_closed(self):
        self.config["apex_origin"] = None
        scheduler = steering.Scheduler(self.config)
        reply, _ = steering.Authority(scheduler).resolve(DNSRecord.question("cdn.example.test"))
        self.assertEqual(reply.header.rcode, RCODE.SERVFAIL)

    def test_monitor_false_stale_malformed_and_read_error(self):
        mutations = [None, {}, {"caches": []}]
        monitor, _ = fixtures(self.clock)
        for field, value in (("isAvailable", False), ("ipv4Available", False),
                             ("ipv6Available", "false"), ("isAvailable", 1),
                             ("lastPoll", "0001-01-01T00:00:00Z"), ("lastPoll", "bad"),
                             ("lastPoll", "2027-01-15T08:00:00")):
            changed = copy.deepcopy(monitor)
            changed["caches"]["large"][field] = value
            mutations.append(changed)
        for payload in mutations:
            self.prime()
            _, metrics = fixtures(self.clock)
            self.scheduler.update(payload, metrics)
            self.assertEqual(self.scheduler.choose("ipv4", "large"), [], payload)

    def test_nanosecond_offset_last_poll_is_accepted(self):
        monitor, _ = fixtures(self.clock)
        value = datetime.fromtimestamp(self.clock.now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
        monitor["caches"]["large"]["lastPoll"] = value + ".123456789+00:00"
        flags, reason, _ = steering.monitor_health(monitor, "large", self.clock.now, 20)
        self.assertEqual(reason, "ok")
        self.assertTrue(flags["ipv6"])

    def test_per_family_health_and_v4_only_nodata(self):
        self.prime()
        monitor, metrics = fixtures(self.clock)
        monitor["caches"]["large"]["ipv6Available"] = False
        self.scheduler.update(monitor, metrics)
        self.assertEqual(set(self.scheduler.choose("ipv4")), {"192.0.2.5", "192.0.2.8"})
        self.assertEqual(self.scheduler.choose("ipv6"), [])
        self.assertEqual(self.addresses(self.query("code", "AAAA")), ["2001:db8::1"])
        for name in ("small", "office", "origin-other"):
            reply = self.query(name, "AAAA")
            self.assertEqual(reply.header.rcode, RCODE.NOERROR)
            self.assertEqual(self.addresses(reply), [])
            self.assertEqual(reply.auth[0].rtype, QTYPE.SOA)

    def test_repeated_weighted_records_and_bypass(self):
        self.prime()
        counts = {"192.0.2.5": 0, "192.0.2.8": 0}
        for _ in range(1300):
            reply = self.query()
            addresses = self.addresses(reply)
            self.assertEqual(Counter(addresses), {"192.0.2.5": 5, "192.0.2.8": 8})
            counts[addresses[0]] += 1
        self.assertLess(abs(counts["192.0.2.8"] / 1300 - 8 / 13), 0.04)
        self.assertEqual(self.addresses(self.query("code", "AAAA")), ["2001:db8::8"] * 8)
        self.assertEqual(self.addresses(self.query("chat")), ["192.0.2.1"])
        self.assertEqual(self.query("unknown").header.rcode, RCODE.SERVFAIL)
        self.assertEqual(self.addresses(self.query("origin-control")), ["192.0.2.1"])

    def test_recovery_new_probes_and_slow_start(self):
        monitor, metrics = self.update()
        for _ in range(8):
            self.scheduler.update(monitor, metrics)
        self.assertEqual(self.scheduler.choose("ipv4"), [])
        self.clock.advance()
        self.update()
        self.assertEqual(self.scheduler.choose("ipv4"), [])
        self.clock.advance()
        self.update()
        weight = self.scheduler.status()["nodes"]["large"]["ipv4"]["weight"]
        self.assertAlmostEqual(weight, 8 * 0.05)
        self.clock.advance(5)
        self.update()
        self.assertGreater(self.scheduler.status()["nodes"]["large"]["ipv4"]["weight"], weight)
        monitor, metrics = fixtures(self.clock)
        metrics["large"]["cdn"]["ready"] = False
        self.scheduler.update(monitor, metrics)
        self.assertEqual(self.scheduler.choose("ipv4", "large"), [])
        self.clock.advance()
        self.update()
        self.assertEqual(self.scheduler.choose("ipv4", "large"), [])

    def test_timeout_removes_all_copies_without_dropping_healthy_peer(self):
        self.prime()
        monitor, metrics = fixtures(self.clock)
        # fetch_json returns None for HTTP timeout/refusal/non-200 responses.
        metrics["large"] = None
        self.scheduler.update(monitor, metrics)
        self.assertEqual(self.addresses(self.query()), ["192.0.2.5"] * 5)
        self.assertEqual(self.addresses(self.query("code", "AAAA")), ["2001:db8::1"])
        state = self.scheduler.status()["nodes"]["large"]["ipv4"]
        self.assertEqual(state["records"], 0)
        self.assertEqual(state["reason"], "metrics_read_error")

    def test_pressure_reduces_copies_but_keeps_ready_node(self):
        self.prime()
        for _ in range(8):
            monitor, metrics = fixtures(self.clock)
            metrics["large"]["cdn"]["tcp_memory_ratio"] = 2
            self.scheduler.update(monitor, metrics)
            self.clock.advance()
        self.assertEqual(Counter(self.addresses(self.query())), {"192.0.2.5": 5, "192.0.2.8": 1})

    def test_weight_limits_and_large_repeated_response_truncation(self):
        for weights in ((0, 8), (5.5, 8), (128, 129)):
            config = copy.deepcopy(CONFIG)
            for edge, weight in zip(config["edges"], weights):
                edge["weight"] = weight
            with self.assertRaises(ValueError):
                steering.Scheduler(config)
        for edge in self.config["edges"]:
            edge["weight"] = 128
        self.prime()
        request = DNSRecord.question("route-code.cdn.example.test").pack()
        udp = DNSRecord.parse(self.authority.packet(request))
        self.assertEqual(udp.header.tc, 1)
        self.assertFalse(udp.rr)
        tcp = DNSRecord.parse(self.authority.packet(request, tcp=True))
        self.assertEqual(len(self.addresses(tcp)), 256)

    def test_hard_faults_and_unknown_metrics_zero_weight(self):
        for field, value in (("ready", False), ("memory_available_ratio", 0),
                             ("listener_queue", 512), ("schema", True), ("cpu_pressure", float("nan")),
                             ("tcp_memory_ratio", None), ("close_wait", 0.5),
                             ("sampled_at", self.clock.now - 50), ("listener_capacity", 0)):
            self.prime()
            monitor, metrics = fixtures(self.clock)
            metrics["large"]["cdn"][field] = value
            self.scheduler.update(monitor, metrics)
            self.assertEqual(self.scheduler.choose("ipv4", "large"), [], field)
        for payload in (None, {}, {"cdn": {}}, {"cdn": []}):
            self.prime()
            monitor, metrics = fixtures(self.clock)
            metrics["large"] = payload
            self.scheduler.update(monitor, metrics)
            self.assertEqual(self.scheduler.choose("ipv4", "large"), [])

    def test_pressure_ewma_hysteresis_and_gradual_recovery(self):
        self.prime()
        for field, value in (("cpu_pressure", 1), ("cpu_steal_ratio", 1),
                             ("memory_pressure", 1), ("tcp_memory_ratio", 2),
                             ("close_wait", 800), ("listener_queue", 400)):
            monitor, metrics = fixtures(self.clock)
            for node in metrics.values():
                node["cdn"][field] = value
            self.scheduler.update(monitor, metrics)
            self.assertTrue(self.scheduler.choose("ipv4"), field)
            self.clock.advance()
        depressed = self.scheduler.status()["nodes"]["large"]["ipv4"]["score"]
        self.update()
        restored = self.scheduler.status()["nodes"]["large"]["ipv4"]["score"]
        self.assertGreater(restored, depressed)
        self.assertLess(restored, 1)
        self.assertAlmostEqual(restored - depressed, (1 - depressed) * 0.1)

    def test_expiry_without_poll_and_stalled_sampler_readmission(self):
        self.prime()
        self.clock.advance(30)
        self.assertEqual(self.scheduler.choose("ipv4"), [])
        self.assertTrue(self.scheduler.status()["stale"])
        self.update()
        self.assertEqual(self.scheduler.choose("ipv4"), [])
        self.assertEqual(self.addresses(self.query()), ["192.0.2.1"])

    def test_old_edge_does_not_expire_fresh_peer(self):
        self.prime()
        monitor, metrics = fixtures(self.clock)
        metrics["large"]["cdn"]["sampled_at"] -= 19
        self.scheduler.update(monitor, metrics)
        self.clock.advance(2)
        self.assertEqual(self.scheduler.choose("ipv4", "large"), [])
        self.assertEqual(self.scheduler.choose("ipv4", "small"), ["192.0.2.5"] * 5)
        self.update()
        self.assertEqual(self.scheduler.choose("ipv4", "large"), [])

    def test_authority_cname_negative_and_unsupported_queries(self):
        for kind in ("NS", "SOA"):
            reply = self.query("", kind)
            self.assertEqual(reply.header.aa, 1)
            self.assertEqual(reply.header.ra, 0)
            self.assertEqual(reply.rr[0].rtype, getattr(QTYPE, kind))
            self.assertTrue(all(rr.ttl == 30 for rr in reply.rr))
        alias = self.query("code", "CNAME")
        self.assertEqual(str(alias.rr[0].rdata), "route-code.cdn.example.test.")
        self.assertEqual(self.addresses(self.query("route-code")), ["192.0.2.1"])
        unknown = self.query("absent")
        self.assertEqual(unknown.header.rcode, RCODE.NXDOMAIN)
        self.assertEqual(unknown.auth[0].rtype, QTYPE.SOA)
        txt = self.query("", "TXT")
        self.assertEqual(txt.header.rcode, RCODE.NOERROR)
        self.assertFalse(txt.rr)
        self.assertEqual(txt.auth[0].rtype, QTYPE.SOA)
        outside, _ = self.authority.resolve(DNSRecord.question("notcdn.example.test"))
        self.assertEqual(outside.header.rcode, RCODE.REFUSED)
        self.assertEqual(outside.header.aa, 0)
        malformed = DNSRecord.parse(self.authority.packet(b"\xab\xcdgarbage"))
        self.assertEqual(malformed.header.id, 0xabcd)
        self.assertEqual(malformed.header.rcode, RCODE.FORMERR)
        request = DNSRecord.question("cdn.example.test")
        request.q.qclass = 3
        reply, _ = self.authority.resolve(request)
        self.assertEqual(reply.header.rcode, RCODE.REFUSED)
        request.q.qclass = 1
        request.header.opcode = 5
        reply, _ = self.authority.resolve(request)
        self.assertEqual(reply.header.rcode, RCODE.NOTIMP)

    def test_udp_truncation_and_tcp_full_authority_response(self):
        self.config["nameservers"] = [f"{'n' * 60}{i}.{'d' * 60}{i}.example.test" for i in range(8)]
        scheduler = steering.Scheduler(self.config)
        authority = steering.Authority(scheduler)
        request = DNSRecord.question("cdn.example.test", "NS").pack()
        udp = DNSRecord.parse(authority.packet(request))
        tcp = DNSRecord.parse(authority.packet(request, tcp=True))
        self.assertEqual(udp.header.tc, 1)
        self.assertLessEqual(len(udp.pack()), 512)
        self.assertEqual(tcp.header.tc, 0)
        self.assertEqual(len(tcp.rr), 8)
        request = DNSRecord.question("cdn.example.test", "NS")
        request.add_ar(EDNS0(udp_len=4096))
        edns = DNSRecord.parse(authority.packet(request.pack()))
        self.assertEqual(edns.header.tc, 0)
        self.assertEqual(edns.ar[0].rclass, 1232)
        request.ar.clear()
        request.add_ar(EDNS0(version=1, udp_len=1232))
        badvers = DNSRecord.parse(authority.packet(request.pack()))
        self.assertEqual(badvers.ar[0].ttl >> 24, 1)
        self.assertFalse(badvers.rr)

    def test_loopback_udp_tcp_and_status(self):
        self.prime()
        listeners = steering.servers(self.scheduler, 0, 0)
        threads = []
        try:
            for server in listeners:
                self.assertEqual(server.server_address[0], "127.0.0.1")
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                threads.append(thread)
            port = listeners[0].server_address[1]
            for tcp in (False, True):
                reply = DNSRecord.parse(DNSRecord.question("code.cdn.example.test").send("127.0.0.1", port, tcp=tcp, timeout=2))
                self.assertEqual(reply.header.aa, 1)
                self.assertEqual(Counter(self.addresses(reply)), {"192.0.2.5": 5, "192.0.2.8": 8})
            with socket.create_connection(("127.0.0.1", port), timeout=2) as connection:
                for kind in ("A", "AAAA"):
                    packet = DNSRecord.question("chat.cdn.example.test", kind).pack()
                    framed = struct.pack("!H", len(packet)) + packet
                    connection.sendall(framed[:1])
                    connection.sendall(framed[1:])
                    header = connection.recv(2)
                    size = struct.unpack("!H", header)[0]
                    data = bytearray()
                    while len(data) < size:
                        data.extend(connection.recv(size - len(data)))
                    self.assertEqual(len(self.addresses(DNSRecord.parse(bytes(data)))), 1)
            conn = http.client.HTTPConnection("127.0.0.1", listeners[2].server_address[1], timeout=2)
            conn.request("GET", "/status")
            response = conn.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(json.loads(response.read())["schema"], 1)
            conn.request("GET", "/metrics")
            response = conn.getresponse()
            self.assertIn(b"atc_dns_edge_weight", response.read())
            conn.close()
        finally:
            for server in listeners:
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(timeout=2)

    def test_sampler_total_budget_and_bounded_outstanding_requests(self):
        self.config.update(poll_budget=0.02)
        release = threading.Event()
        calls = []

        def blocked(*args):
            calls.append(args)
            release.wait(2)
            return None

        sampler = steering.Sampler(self.scheduler, threading.Event(), fetch=blocked)
        try:
            started = time.monotonic()
            for _ in range(3):
                sampler.poll()
            self.assertLess(time.monotonic() - started, 0.5)
            self.assertLessEqual(len(calls), 3)
            self.assertEqual(len(sampler.pending), 3)
            self.assertEqual(self.scheduler.choose("ipv4"), [])
        finally:
            release.set()
            sampler.executor.shutdown(wait=True, cancel_futures=True)

    def test_http_fetch_loopback_json_errors_and_size_limit(self):
        class FixtureHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                body = {"/ok": b'{"cdn":{"schema":1}}', "/bad": b"invalid",
                        "/duplicate": b'{"ready":false,"ready":true}', "/nan": b'{"value":NaN}',
                        "/big": b"x" * (steering.MAX_BODY + 1)}.get(self.path, b"error")
                self.send_response(503 if self.path == "/down" else 200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = steering.TCPServer(("127.0.0.1", 0), FixtureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            args = ("127.0.0.1", server.server_address[1])
            self.assertEqual(steering.fetch_json(*args, "/ok", time.monotonic() + 2, 1), {"cdn": {"schema": 1}})
            for path in ("/bad", "/down", "/big", "/duplicate", "/nan"):
                self.assertIsNone(steering.fetch_json(*args, path, time.monotonic() + 2, 1))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_http_slow_headers_obey_absolute_deadline(self):
        class SlowHeaders(BaseHTTPRequestHandler):
            def do_GET(self):
                try:
                    self.wfile.write(b"HTTP/1.1 200 OK\r\nX-Slow: ")
                    self.wfile.flush()
                    for _ in range(100):
                        self.wfile.write(b"x")
                        self.wfile.flush()
                        time.sleep(0.01)
                except OSError:
                    pass

            def log_message(self, *args):
                pass

        server = steering.TCPServer(("127.0.0.1", 0), SlowHeaders)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            started = time.monotonic()
            result = steering.fetch_json("127.0.0.1", server.server_address[1], "/", started + 0.05, 1)
            self.assertIsNone(result)
            self.assertLess(time.monotonic() - started, 0.5)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    @unittest.skipUnless(os.environ.get("ATC_TEST_COREDNS"), "set ATC_TEST_COREDNS to a locked CoreDNS binary")
    def test_coredns_frontdoor_udp_tcp_no_cache(self):
        self.prime()
        listeners = steering.servers(self.scheduler, 0, 0)
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            public_port = reserve.getsockname()[1]
        process = None
        try:
            for server in listeners:
                threading.Thread(target=server.serve_forever, daemon=True).start()
            with tempfile.TemporaryDirectory(prefix="atc-dns-", dir="/tmp/kilo") as directory:
                corefile = Path(directory) / "Corefile"
                corefile.write_text(f"""cdn.example.test:{public_port} {{
    bind 127.0.0.1
    forward . 127.0.0.1:{listeners[0].server_address[1]} {{
        max_concurrent 256
    }}
    errors
}}
""")
                process = subprocess.Popen([os.environ["ATC_TEST_COREDNS"], "-conf", str(corefile)],
                                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                deadline = time.monotonic() + 5
                while True:
                    if process.poll() is not None:
                        self.fail(process.communicate()[0])
                    try:
                        with socket.create_connection(("127.0.0.1", public_port), timeout=0.05):
                            break
                    except OSError:
                        if time.monotonic() > deadline:
                            self.fail("CoreDNS did not become ready")
                        time.sleep(0.01)
                addresses = set()
                for tcp in (False, True):
                    for _ in range(64):
                        packet = DNSRecord.question("code.cdn.example.test").send("127.0.0.1", public_port, tcp=tcp, timeout=2)
                        reply = DNSRecord.parse(packet)
                        self.assertEqual(reply.header.aa, 1)
                        self.assertEqual(Counter(self.addresses(reply)), {"192.0.2.5": 5, "192.0.2.8": 8})
                        addresses.update(self.addresses(reply))
                self.assertEqual(addresses, {"192.0.2.5", "192.0.2.8"})
                monitor, metrics = fixtures(self.clock)
                for cache in monitor["caches"].values():
                    cache["isAvailable"] = False
                self.scheduler.update(monitor, metrics)
                # Re-query the exact name already used above: no stale edge answer.
                reply = DNSRecord.parse(DNSRecord.question("code.cdn.example.test").send("127.0.0.1", public_port, timeout=2))
                self.assertEqual(self.addresses(reply), ["192.0.2.1"])
                reply = DNSRecord.parse(DNSRecord.question("office.cdn.example.test").send("127.0.0.1", public_port, timeout=2))
                self.assertEqual(self.addresses(reply), ["192.0.2.2"])
                reply = DNSRecord.parse(DNSRecord.question("missing.cdn.example.test").send("127.0.0.1", public_port, timeout=2))
                self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN)
        finally:
            if process is not None:
                process.terminate()
                process.communicate(timeout=5)
            for server in listeners:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
