#!/usr/bin/env python3
"""Local authoritative DNS with fail-closed, background-only CDN sampling.

Weights expand repeated address records; recursive resolvers may deduplicate them.
No persisted health is trusted on startup. Public DNS is served by CoreDNS;
this process binds DNS and its operational HTTP interface only to loopback.
"""

from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import dataclass
from datetime import datetime
from http.server import BaseHTTPRequestHandler
import http.client
import ipaddress
import json
import logging
import math
import random
import re
import signal
import socket
import socketserver
import struct
import sys
import threading
import time

from dnslib import A, AAAA, CNAME, DNSHeader, DNSRecord, NS, QTYPE, RCODE, RR, SOA


LOG = logging.getLogger("atc-steering")
LABEL = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\Z")
RFC3339 = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\Z")
FAMILIES = ("ipv4", "ipv6")
MAX_BODY = 1024 * 1024


def json_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("duplicate_json_key")
    return result


def reject_constant(value):
    raise ValueError("nonfinite_json")


def number(value, low=0, high=None):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError("not_number")
    if value < low or (high is not None and value > high):
        raise ValueError("out_of_range")
    return float(value)


def timestamp(value):
    if not isinstance(value, str) or not RFC3339.fullmatch(value):
        raise ValueError("timestamp")
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def fresh(stamp, now, age):
    return -2 <= now - stamp <= age


def monitor_health(payload, name, now, max_age):
    try:
        cache = payload["caches"][name]
        if any(type(cache[key]) is not bool for key in ("isAvailable", "ipv4Available", "ipv6Available")):
            return {}, "monitor_malformed", 0
        stamp = timestamp(cache["lastPoll"])
        if not fresh(stamp, now, max_age):
            return {}, "monitor_stale", 0
        if not cache["isAvailable"]:
            return {}, "monitor_down", stamp
        return {family: cache[family + "Available"] for family in FAMILIES}, "ok", stamp
    except (KeyError, TypeError, ValueError, OverflowError, OSError):
        return {}, "monitor_malformed" if payload is not None else "monitor_read_error", 0


def performance(payload, now, max_age):
    """Hard readiness gates are separate from bounded pressure penalties."""
    if payload is None:
        return 0, "metrics_read_error", 0
    try:
        cdn = payload["cdn"]
        if type(cdn["schema"]) is not int or cdn["schema"] != 1 or type(cdn["ready"]) is not bool:
            raise ValueError("schema")
        stamp = number(cdn["sampled_at"])
        if not fresh(stamp, now, max_age):
            return 0, "metrics_stale", stamp
        if not cdn["ready"]:
            return 0, "worker_not_ready", stamp
        available = number(cdn["memory_available_ratio"], high=1)
        steal = number(cdn["cpu_steal_ratio"], high=1)
        cpu = number(cdn["cpu_pressure"], high=1)
        memory = number(cdn["memory_pressure"], high=1)
        tcp = number(cdn["tcp_memory_ratio"])
        close_wait = number(cdn["close_wait"])
        queue = number(cdn["listener_queue"])
        capacity = number(cdn["listener_capacity"], low=1)
        if any(type(cdn[key]) is not int for key in ("close_wait", "listener_queue", "listener_capacity")):
            raise ValueError("counts")
        if available == 0:
            return 0, "memory_exhausted", stamp
        if queue >= capacity:
            return 0, "listener_saturated", stamp
        # Pressure (including CPU=100%) never alone makes a ready pool empty.
        pressure = max(
            1 - min(1, available / 0.15), memory, steal, cpu * 0.6,
            min(1, max(0, (tcp - 0.5) / 0.5)),
            min(1, close_wait / capacity), min(1, queue / capacity),
        )
        return max(0.1, 1 - 0.9 * pressure), "ok" if pressure < 0.1 else "pressure", stamp
    except (KeyError, TypeError, ValueError, OverflowError):
        return 0, "metrics_malformed", 0


@dataclass
class Admission:
    successes: int = 0
    admitted_at: float | None = None
    score: float = 0
    reason: str = "startup"
    last_monitor: float = 0
    last_metrics: float = 0
    logged_at: float = -math.inf


class Scheduler:
    def __init__(self, config, rng=None, wall=time.time, monotonic=time.monotonic):
        self.config = config
        self.wall = wall
        self.monotonic = monotonic
        self.rng = rng or random.SystemRandom()
        self.lock = threading.Lock()
        self.zone = config["zone"].lower().rstrip(".") + "."
        if len(self.zone) > 200 or any(not LABEL.fullmatch(s) for s in self.zone.rstrip(".").split(".")):
            raise ValueError("invalid_zone")
        self.edges = config["edges"]
        self.origins = config["origins"]
        self.services = config["services"]
        if not 1 <= len(self.edges) <= 128 or len(self.origins) > 128 or len(self.services) > 128:
            raise ValueError("configuration_limit")
        names = [edge["name"] for edge in self.edges]
        if len(set(names)) != len(names) or set(names) & (set(self.services) | set(self.origins)):
            raise ValueError("name_collision")
        for name in names + list(self.origins) + list(self.services):
            if not LABEL.fullmatch(name) or name.startswith(("route-", "origin-")):
                raise ValueError("invalid_label")
        if any(len(s) > 57 for s in self.services) or any(len(s) > 56 for s in self.origins):
            raise ValueError("internal_label_limit")
        if any(not isinstance(origin, str) or not LABEL.fullmatch(origin) for origin in self.services.values()):
            raise ValueError("invalid_service_origin")
        for node in self.edges + list(self.origins.values()):
            for family, version in (("ipv4", 4), ("ipv6", 6)):
                if node.get(family) is not None and ipaddress.ip_address(node[family]).version != version:
                    raise ValueError("address_family")
        for edge in self.edges:
            number(edge["weight"], low=1, high=256)
            if type(edge["weight"]) is not int:
                raise ValueError("weight_requires_integer")
            if not edge.get("ipv4"):
                raise ValueError("metrics_requires_ipv4")
        if sum(edge["weight"] for edge in self.edges) > 256:
            raise ValueError("weighted_record_limit")
        self.max_age = number(config.get("max_age", 20), low=1, high=120)
        self.recovery = int(number(config.get("recovery_successes", 3), low=1, high=20))
        self.slow_start = number(config.get("slow_start", 60), low=1, high=600)
        self.ttl = int(number(config.get("ttl", 30), low=1, high=300))
        self.bypass = set(config.get("origin_bypass_services", []))
        if any(self.services.get(s) not in self.origins for s in self.bypass):
            raise ValueError("unknown_bypass_origin")
        self.apex_origin = config.get("apex_origin")
        if self.apex_origin is not None and self.apex_origin not in self.origins:
            raise ValueError("unknown_apex_origin")
        self.admissions = {(e["name"], f): Admission() for e in self.edges for f in FAMILIES}
        self.snapshot = {"updated_at": None, "expires_at": 0, "nodes": {}}
        self.queries = {}

    def update(self, monitor, metrics, now=None, tick=None):
        now = self.wall() if now is None else now
        tick = self.monotonic() if tick is None else tick
        nodes = {}
        stalled = self.snapshot["updated_at"] is not None and tick >= self.snapshot["expires_at"]
        for edge in self.edges:
            name = edge["name"]
            healthy, monitor_reason, monitor_stamp = monitor_health(monitor, name, now, self.max_age)
            score, metrics_reason, metrics_stamp = performance(metrics.get(name), now, self.max_age)
            for family in FAMILIES:
                state = self.admissions[name, family]
                previous = self.snapshot["nodes"].get(name, {}).get(family, {})
                if stalled or (state.successes and tick >= previous.get("expires_at", 0)):
                    state.successes = 0
                    state.admitted_at = None
                    state.score = 0
                reason = monitor_reason if monitor_reason != "ok" else metrics_reason
                if not edge.get(family):
                    reason = "no_address"
                elif monitor_reason == "ok" and not healthy.get(family):
                    reason = "family_down"
                ok = bool(edge.get(family) and healthy.get(family) and score > 0)
                expires = tick
                # A repeated bridge snapshot is not a new successful probe.
                advanced = monitor_stamp > state.last_monitor and metrics_stamp > state.last_metrics
                if not ok:
                    state.successes = 0
                    state.admitted_at = None
                    state.score = 0
                else:
                    remaining = min(self.max_age - (now - monitor_stamp), self.max_age - (now - metrics_stamp))
                    expires = tick + min(self.max_age, remaining)
                    if advanced:
                        state.successes = min(self.recovery, state.successes + 1)
                        if state.admitted_at is None and state.successes >= self.recovery:
                            state.admitted_at = tick
                        if state.score == 0:
                            state.score = score
                        elif score < state.score - 0.03:
                            state.score += 0.5 * (score - state.score)
                        elif score > state.score + 0.03:
                            state.score += 0.1 * (score - state.score)
                    if state.admitted_at is None:
                        reason = "recovering"
                state.last_monitor = monitor_stamp
                state.last_metrics = metrics_stamp
                ramp = 0 if state.admitted_at is None else min(1, max(0.05, (tick - state.admitted_at) / self.slow_start))
                weight = edge["weight"] * state.score * ramp if ok else 0
                if reason != state.reason:
                    if reason not in ("ok", "pressure") or tick - state.logged_at >= 30:
                        LOG.info("edge=%s family=%s reason=%s", name, family, reason)
                        state.logged_at = tick
                    state.reason = reason
                nodes.setdefault(name, {})[family] = {
                    "address": edge.get(family), "weight": weight, "score": state.score,
                    "records": max(1, math.floor(weight + 0.5)) if weight > 0 else 0,
                    "reason": reason, "successes": state.successes, "expires_at": expires,
                }
        with self.lock:
            self.snapshot = {"updated_at": now, "expires_at": tick + self.max_age, "nodes": nodes}

    def status(self):
        with self.lock:
            snapshot = self.snapshot
            stale = self.monotonic() >= snapshot["expires_at"]
            tick = self.monotonic()
            nodes = {name: {family: dict(value, weight=0 if stale or tick >= value["expires_at"] else value["weight"],
                                         records=0 if stale or tick >= value["expires_at"] else value["records"],
                                         reason="snapshot_stale" if stale else
                                         "evidence_stale" if value["weight"] > 0 and tick >= value["expires_at"] else value["reason"])
                            for family, value in families.items()}
                     for name, families in snapshot["nodes"].items()}
            return {"schema": 1, "updated_at": snapshot["updated_at"], "stale": stale,
                    "nodes": nodes, "origin_bypass_services": sorted(self.bypass),
                    "dns_queries": dict(self.queries)}

    def choose(self, family, only=None):
        with self.lock:
            snapshot = self.snapshot
            if self.monotonic() >= snapshot["expires_at"]:
                return []
            candidates = [families[family] for name, families in snapshot["nodes"].items()
                          if (only is None or only == name) and families[family]["weight"] > 0
                          and self.monotonic() < families[family]["expires_at"]]
            addresses = []
            for node in candidates:
                addresses.extend([node["address"]] * node["records"])
            self.rng.shuffle(addresses)
            return addresses

    def count(self, outcome):
        with self.lock:
            self.queries[outcome] = self.queries.get(outcome, 0) + 1


def fetch_json(host, port, path, deadline, socket_timeout):
    """Fixed-IP, no proxy/redirect HTTP fetch; bounded bytes and poll deadline."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return None
    conn = http.client.HTTPConnection(host, port, timeout=min(socket_timeout, remaining))
    timer = None
    try:
        conn.request("GET", path, headers={"Connection": "close", "Accept": "application/json"})
        sock = conn.sock
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None

        def expire():
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        # Interrupt even slow-drip HTTP headers at the absolute poll deadline.
        timer = threading.Timer(remaining, expire)
        timer.daemon = True
        timer.start()
        response = conn.getresponse()
        if response.status != 200:
            return None
        parts = []
        size = 0
        while True:
            if response.isclosed():
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            # Keep the socket reference: Connection: close detaches conn.sock.
            sock.settimeout(min(socket_timeout, remaining))
            part = response.read1(min(65536, MAX_BODY + 1 - size))
            if not part:
                break
            size += len(part)
            if size > MAX_BODY:
                return None
            parts.append(part)
        result = json.loads(b"".join(parts), object_pairs_hook=json_object, parse_constant=reject_constant)
        return result if isinstance(result, dict) else None
    except (OSError, ValueError, http.client.HTTPException, AttributeError):
        return None
    finally:
        if timer is not None:
            timer.cancel()
        conn.close()


class Sampler:
    def __init__(self, scheduler, stop, fetch=fetch_json):
        self.scheduler = scheduler
        self.stop = stop
        self.fetch = fetch
        self.executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="health")
        self.pending = {}

    def poll(self):
        cfg = self.scheduler.config
        deadline = time.monotonic() + cfg.get("poll_budget", 3)
        jobs = {"monitor": ("127.0.0.1", 8087, "/publish/CrStates")}
        jobs.update({e["name"]: (e["ipv4"], 80, "/_astats") for e in self.scheduler.edges})
        current = {}
        for name, args in jobs.items():
            previous = self.pending.get(name)
            if previous is not None and not previous.done():
                continue
            current[name] = self.executor.submit(self.fetch, *args, deadline, cfg.get("http_timeout", 1))
            self.pending[name] = current[name]
        if current:
            wait(current.values(), timeout=max(0, deadline - time.monotonic()))
        values = {}
        for name, future in current.items():
            if future.done() and not future.cancelled():
                try:
                    values[name] = future.result()
                except Exception:
                    values[name] = None
            else:
                future.cancel()
        self.scheduler.update(values.get("monitor"), values)

    def run(self):
        try:
            while not self.stop.is_set():
                started = time.monotonic()
                self.poll()
                self.stop.wait(max(0.1, self.scheduler.config.get("poll_interval", 5) - (time.monotonic() - started)))
        finally:
            self.executor.shutdown(wait=False, cancel_futures=True)


class Authority:
    def __init__(self, scheduler):
        self.scheduler = scheduler
        self.zone = scheduler.zone
        self.nameservers = [name.rstrip(".") + "." for name in scheduler.config["nameservers"]]
        if not 1 <= len(self.nameservers) <= 8:
            raise ValueError("nameserver_limit")

    def soa(self):
        return RR(self.zone, QTYPE.SOA, ttl=self.scheduler.ttl,
                  rdata=SOA(self.nameservers[0], self.scheduler.config["admin"].rstrip(".") + ".",
                            (1, 300, 60, 86400, self.scheduler.ttl)))

    def resolve(self, request):
        reply = request.reply(ra=0, aa=1)
        reply.header.ad = 0
        reply.header.cd = 0
        outcome = "nodata"
        if request.header.opcode != 0:
            reply.header.rcode = RCODE.NOTIMP
            reply.header.aa = 0
            return reply, "refused"
        if len(request.questions) != 1 or request.header.qr:
            reply.header.rcode = RCODE.FORMERR
            reply.header.aa = 0
            return reply, "refused"
        question = request.q
        name = str(question.qname).lower()
        if question.qclass != 1 or not (name == self.zone or name.endswith("." + self.zone)):
            reply.header.rcode = RCODE.REFUSED
            reply.header.aa = 0
            return reply, "refused"
        label = name[:-len(self.zone)].rstrip(".")
        origin = None
        service = None
        only = None
        direct = False
        if not label:
            origin = self.scheduler.apex_origin
        elif label in self.scheduler.services or (label.startswith("route-") and label[6:] in self.scheduler.services):
            service = label if label in self.scheduler.services else label[6:]
            origin = self.scheduler.services[service]
            if origin not in self.scheduler.origins:
                reply.header.rcode = RCODE.SERVFAIL
                return reply, "servfail"
            if label == service:
                target = "route-" + service + "." + self.zone
                reply.add_answer(RR(name, QTYPE.CNAME, ttl=self.scheduler.ttl, rdata=CNAME(target)))
                name = target
                if question.qtype == QTYPE.CNAME:
                    return reply, "alias"
            direct = service in self.scheduler.bypass
        elif label in self.scheduler.origins or (label.startswith("origin-") and label[7:] in self.scheduler.origins):
            origin = label if label in self.scheduler.origins else label[7:]
            direct = True
        elif label in {e["name"] for e in self.scheduler.edges}:
            only = label
        else:
            reply.header.rcode = RCODE.NXDOMAIN
            reply.add_auth(self.soa())
            return reply, "nxdomain"

        if question.qtype == QTYPE.NS and not label:
            for ns in self.nameservers:
                reply.add_answer(RR(self.zone, QTYPE.NS, ttl=self.scheduler.ttl, rdata=NS(ns)))
            return reply, "authority"
        if question.qtype == QTYPE.SOA and not label:
            reply.add_answer(self.soa())
            return reply, "authority"
        if question.qtype not in (QTYPE.A, QTYPE.AAAA):
            reply.add_auth(self.soa())
            return reply, outcome

        family = "ipv4" if question.qtype == QTYPE.A else "ipv6"
        addresses = [] if direct else self.scheduler.choose(family, only)
        if addresses:
            outcome = "edge"
        elif origin in self.scheduler.origins:
            address = self.scheduler.origins[origin].get(family)
            addresses = [address] if address else []
            outcome = "origin" if address else "nodata"
        elif only is not None and not next(e for e in self.scheduler.edges if e["name"] == only).get(family):
            outcome = "nodata"
        else:
            reply.rr.clear()
            reply.header.rcode = RCODE.SERVFAIL
            return reply, "servfail"
        if addresses:
            for address in addresses:
                reply.add_answer(RR(name, question.qtype, ttl=self.scheduler.ttl,
                                     rdata=A(address) if family == "ipv4" else AAAA(address)))
        else:
            reply.add_auth(self.soa())
        return reply, outcome

    def packet(self, data, tcp=False):
        try:
            request = DNSRecord.parse(data)
            options = [record for record in request.ar if record.rtype == QTYPE.OPT]
            if len(options) > 1:
                reply = request.reply(ra=0, aa=0)
                reply.header.rcode = RCODE.FORMERR
                outcome = "malformed"
            elif options and (options[0].ttl >> 16) & 255:
                reply = request.reply(ra=0, aa=0)
                reply.add_ar(RR(".", QTYPE.OPT, rclass=1232, ttl=1 << 24, rdata=[]))
                outcome = "refused"  # EDNS extended RCODE=16 (BADVERS).
            else:
                reply, outcome = self.resolve(request)
                if options:
                    reply.add_ar(RR(".", QTYPE.OPT, rclass=1232, ttl=0, rdata=[]))
            self.scheduler.count(outcome)
            packed = reply.pack()
            udp_limit = max(512, min(1232, options[0].rclass)) if options else 512
            if not tcp and len(packed) > udp_limit:
                reply.rr.clear()
                reply.auth.clear()
                reply.header.tc = 1
                packed = reply.pack()
            return packed
        except Exception:
            self.scheduler.count("malformed")
            ident = struct.unpack("!H", data[:2])[0] if len(data) >= 2 else 0
            return DNSRecord(DNSHeader(id=ident, qr=1, rcode=RCODE.FORMERR)).pack()


class BoundedThreads(socketserver.ThreadingMixIn):
    daemon_threads = True
    block_on_close = False
    request_queue_size = 64

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(32)
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


class TCPServer(BoundedThreads, socketserver.TCPServer):
    allow_reuse_address = True


class UDPServer(BoundedThreads, socketserver.UDPServer):
    max_packet_size = 4096


class DNSHandler(socketserver.BaseRequestHandler):
    def handle(self):
        authority = self.server.authority
        if isinstance(self.request, tuple):
            data, sock = self.request
            sock.sendto(authority.packet(data), self.client_address)
            return
        self.request.settimeout(2)
        try:
            for _ in range(16):
                header = self.read_exact(2)
                if not header:
                    return
                size = struct.unpack("!H", header)[0]
                if not 12 <= size <= 4096:
                    return
                data = self.read_exact(size)
                if data is None:
                    return
                answer = authority.packet(data, tcp=True)
                self.request.sendall(struct.pack("!H", len(answer)) + answer)
        except OSError:
            return

    def read_exact(self, size):
        data = bytearray()
        deadline = time.monotonic() + 2
        while len(data) < size:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            self.request.settimeout(remaining)
            part = self.request.recv(size - len(data))
            if not part:
                return None
            data.extend(part)
        return bytes(data)


class StatusHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(2)

    def do_GET(self):
        status = self.server.scheduler.status()
        if self.path == "/status":
            body = json.dumps(status, allow_nan=False).encode()
            content_type = "application/json"
        elif self.path == "/metrics":
            lines = [f"atc_dns_snapshot_stale {int(status['stale'])}"]
            for name, families in status["nodes"].items():
                for family, value in families.items():
                    lines.append(f'atc_dns_edge_weight{{node="{name}",family="{family}"}} {value["weight"]:.6f}')
                    lines.append(f'atc_dns_edge_records{{node="{name}",family="{family}"}} {value["records"]}')
            for result, count in sorted(status["dns_queries"].items()):
                lines.append(f'atc_dns_queries_total{{result="{result}"}} {count}')
            body = ("\n".join(lines) + "\n").encode()
            content_type = "text/plain; version=0.0.4"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def servers(scheduler, dns_port, status_port):
    authority = Authority(scheduler)
    udp = UDPServer(("127.0.0.1", dns_port), DNSHandler)
    try:
        tcp = TCPServer(("127.0.0.1", udp.server_address[1]), DNSHandler)
        status = TCPServer(("127.0.0.1", status_port), StatusHandler)
    except Exception:
        udp.server_close()
        if "tcp" in locals():
            tcp.server_close()
        raise
    udp.authority = tcp.authority = authority
    status.scheduler = scheduler
    status.slots = threading.BoundedSemaphore(8)
    return udp, tcp, status


def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    with open(sys.argv[1], encoding="utf-8") as source:
        config = json.load(source, object_pairs_hook=json_object, parse_constant=reject_constant)
    scheduler = Scheduler(config)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    listeners = servers(scheduler, config["dns_port"], config["status_port"])
    for server in listeners:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Thread(target=Sampler(scheduler, stop).run, daemon=True).start()
    LOG.info("reason=startup_closed dns=127.0.0.1:%s status=127.0.0.1:%s", config["dns_port"], config["status_port"])
    stop.wait()
    for server in listeners:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
