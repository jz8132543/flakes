#!/usr/bin/env python3
"""Test the DN42 Bash/jq lease-state API without NixOS or remote services."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor


REPO = Path(__file__).resolve().parents[1]
LIBRARY = REPO / "nixos/modules/services/networking/dn42/sdwan-state.sh"
FILTER = LIBRARY.with_suffix(".jq")
TTL = 600
OMITTED = object()
UPDATE = 'source "$1" && sdwan_state_update "$2" "$3" "${@:4}"'


def node(identifier=1, **fields):
    record = {
        "id": identifier,
        "dn42_ip4": f"172.20.0.{identifier}",
        "dn42_ip6": f"fd42::{identifier:x}",
        "endpoints": [
            {"name": "default", "addr": "peer.example.test", "port": 4500}
        ],
        "build_time": 100,
        "updated_at": 0,
    }
    record.update(fields)
    return record


class SdwanStateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for path in (LIBRARY, FILTER):
            if not path.is_file():
                raise RuntimeError(f"Required state helper is not present: {path}")
        missing = [
            command for command in ("bash", "jq", "flock", "mktemp", "mv", "date")
            if shutil.which(command) is None
        ]
        if missing:
            raise RuntimeError("Missing test runtime commands: " + ", ".join(missing))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dn42-sdwan-state-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bootstrap = self.root / "bootstrap.json"
        self.state = self.root / "peers.json"
        self.seed = node()
        self.write_json(self.bootstrap, {"fra0": self.seed})

    @staticmethod
    def write_json(path, value):
        path.write_text(json.dumps(value), encoding="utf-8")

    def environment(self, now, bootstrap=None):
        env = os.environ.copy()
        env.update({
            "DN42_SDWAN_BOOTSTRAP_FILE": str(bootstrap or self.bootstrap),
            "DN42_SDWAN_FILTER": str(FILTER),
            "DN42_SDWAN_LEASE_SECONDS": str(TTL),
            "DN42_SDWAN_NOW": str(now),
        })
        return env

    def command(self, mode, payload=OMITTED, state=None, raw=False):
        args = ["bash", "-c", UPDATE, "dn42-state-test", str(LIBRARY),
                str(state or self.state), mode]
        if payload is not OMITTED:
            args.append(payload if raw else json.dumps(payload))
        return args

    def update(self, mode="init", payload=OMITTED, now=1000, state=None,
               bootstrap=None, raw=False):
        result = subprocess.run(
            self.command(mode, payload, state, raw), env=self.environment(now, bootstrap),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            value = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            self.fail(f"Helper emitted invalid JSON: {error}: {result.stdout!r}")
        self.assertIsInstance(value, dict)
        stored = json.loads((state or self.state).read_text(encoding="utf-8"))
        self.assertEqual(stored, value, "Returned map differs from committed state")
        for record in value.values():
            self.assertIsInstance(record, dict)
            self.assertGreater(record["lease_expires_at"], now)
        return value

    def assert_rejected(self, mode, payload, raw=False):
        before = self.state.read_bytes()
        sidecar = Path(str(self.state) + ".bootstrap.json")
        seed_before = sidecar.read_bytes()
        result = subprocess.run(
            self.command(mode, payload, raw=raw), env=self.environment(1050),
            capture_output=True, text=True, timeout=30,
        )
        try:
            self.assertNotEqual(result.returncode, 0, f"Accepted bad input: {payload!r}")
            self.assertEqual(self.state.read_bytes(), before, "Rejected input changed state")
            self.assertEqual(sidecar.read_bytes(), seed_before,
                             "Rejected input changed bootstrap lease metadata")
            if result.stdout.strip():
                self.assertIsInstance(json.loads(result.stdout), dict)
        finally:
            # Keep malformed-input subtests independent even when a helper accepts one.
            self.state.write_bytes(before)
            sidecar.write_bytes(seed_before)

    def test_source_defines_api_without_maintenance_or_writes(self):
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        result = subprocess.run(
            ["bash", "-c", 'source "$1" && declare -F sdwan_state_update >/dev/null',
             "dn42-source-test", str(LIBRARY)],
            env=self.environment(1000), cwd=self.root,
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir()}, before)

    def test_bootstrap_initial_expiry_is_persisted_and_not_renewed(self):
        first = self.update()
        self.assertEqual(set(first), {"fra0"})
        self.assertEqual(first["fra0"]["lease_expires_at"], 1600)
        sidecar = Path(str(self.state) + ".bootstrap.json")
        self.assertIsInstance(json.loads(sidecar.read_text()), dict)
        self.assertEqual(self.update(now=1300)["fra0"]["lease_expires_at"], 1600)
        self.assertEqual(self.update(now=1599)["fra0"]["lease_expires_at"], 1600)
        self.assertEqual(self.update(now=1600), {})
        self.assertEqual(self.update(now=2000), {})
        self.state.unlink()
        self.assertEqual(self.update(now=2100), {},
                         "Retained seed metadata must prevent cache-loss resurrection")

    def test_static_changes_and_build_versions_do_not_refresh_existing_seed(self):
        self.update()
        changed = node(build_time=999999, endpoints={"default": "new.example.test"})
        changed_bootstrap = self.root / "new-store-bootstrap.json"
        self.write_json(changed_bootstrap, {"fra0": changed, "hkg5": node(5)})
        result = self.update(now=1300, bootstrap=changed_bootstrap)
        self.assertEqual(result["fra0"]["lease_expires_at"], 1600)
        self.assertEqual(result["hkg5"]["lease_expires_at"], 1900)
        changed["build_time"] += 1
        self.write_json(changed_bootstrap, {"fra0": changed, "hkg5": node(5)})
        result = self.update(now=1600, bootstrap=changed_bootstrap)
        self.assertNotIn("fra0", result)
        self.assertEqual(result["hkg5"]["lease_expires_at"], 1900)
        self.assertEqual(self.update(now=2000, bootstrap=changed_bootstrap), {})

    def test_retired_nue0_removed_and_legacy_dynamic_lease_uses_updated_at(self):
        self.write_json(self.state, {
            "fra0": self.seed,
            "nue0": node(3, build_time=999999, updated_at=0),
            "mobile": node(42, updated_at=950),
            "old-windows": node(43, updated_at=0, last_seen=999999),
        })
        result = self.update()
        self.assertEqual(set(result), {"fra0", "mobile"})
        self.assertEqual(result["mobile"]["lease_expires_at"], 1550)
        result = self.update(now=1200)
        self.assertEqual(result["mobile"]["lease_expires_at"], 1550)
        self.assertNotIn("mobile", self.update(now=1550))

    def test_unknown_mobile_register_overwrites_all_client_timestamps(self):
        payload = node(42, endpoints=[], updated_at=999999, last_seen=999999,
                       lease_expires_at=999999)
        del payload["build_time"]
        del payload["dn42_ip6"]
        result = self.update("register", {"mobile": payload})
        registered = result["mobile"]
        self.assertEqual(registered["id"], 42)
        self.assertEqual(registered["build_time"], 0)
        self.assertEqual(registered["endpoints"], [])
        for field in ("updated_at", "last_seen"):
            self.assertEqual(registered[field], 1000)
        self.assertEqual(registered["lease_expires_at"], 1600)
        self.assertEqual(self.bootstrap.read_text(), json.dumps({"fra0": self.seed}))

    def test_endpoint_shapes_and_optional_ipv6_accept_dynamic_windows_nodes(self):
        endpoints = [
            [{"name": "default", "addr": "203.0.113.10", "port": 4500,
              "family": "ipv4"}],
            {"default": "windows.example.test", "v6": "2001:db8::10"},
            [{"name": "default", "value": "windows.example.test"}],
            [{"name": "v6", "addr": "2001:db8::10", "port": 4500,
              "family": "ipv6"}],
            [{"name": f"ep{i}", "addr": f"ep{i}.example.test", "port": 4500}
             for i in range(9)],
        ]
        for index, shape in enumerate(endpoints):
            with self.subTest(shape=shape):
                payload = node(50 + index, endpoints=shape,
                               dn42_ip6="" if index % 2 else "fd42::50")
                result = self.update("register", {f"windows{index}": payload})
                self.assertIn(f"windows{index}", result)
                self.assertEqual(result[f"windows{index}"]["lease_expires_at"], 1600)

    def test_valid_ipv6_compressed_full_and_ipv4_mapped_forms(self):
        for address in ("::", "fd42::1", "FD42:0:0:0:0:0:0:1", "::ffff:192.0.2.1"):
            with self.subTest(address=address):
                result = self.update("register", {"windows": node(44, dn42_ip6=address)})
                self.assertEqual(result["windows"]["dn42_ip6"], address)

    def test_raw_endpoint_ports_and_ipv6_validation(self):
        self.update()
        invalid = (
            "host.example.test:999999", "[2001:db8::1]:999999",
            "[2001:db8::gg]:4500", "[::::]:4500", "1:2:3:4:5:6:7:8:9",
        )
        for mode in ("merge", "register"):
            for address in invalid:
                for endpoints in ({"default": address}, [{"name": "default", "value": address}]):
                    with self.subTest(mode=mode, endpoints=endpoints):
                        self.assert_rejected(mode, {"windows": node(44, endpoints=endpoints)})
        for address in (
            "[2001:db8::1]:1", "[2001:db8::1]:65535", "[::ffff:192.0.2.1]:4500",
            "[2001:db8::1]", "2001:db8::1", "host.example.test:65535",
        ):
            with self.subTest(address=address):
                result = self.update("register", {"windows": node(44, endpoints={"default": address})})
                self.assertEqual(result["windows"]["id"], 44)
                self.assertEqual(result["windows"]["lease_expires_at"], 1600)

    def test_forwarded_cache_keeps_original_lease_even_after_repeat_merges(self):
        remote = node(42, updated_at=1000, last_seen=1000, lease_expires_at=1600)
        result = self.update("merge", {"mobile": remote}, now=1100)
        self.assertEqual(result["mobile"]["lease_expires_at"], 1600)
        result = self.update("merge", {"mobile": remote}, now=1500)
        self.assertEqual(result["mobile"]["updated_at"], 1000)
        self.assertEqual(result["mobile"]["last_seen"], 1000)
        self.assertEqual(result["mobile"]["lease_expires_at"], 1600)
        self.assertNotIn("mobile", self.update("merge", {"mobile": remote}, now=1600))
        self.assertNotIn("mobile", self.update("merge", {"mobile": remote}, now=2000))

    def test_legacy_remote_cache_does_not_get_a_new_local_lease(self):
        remote = {
            "old": node(40, updated_at=0),
            "mobile": node(42, updated_at=900),
            "expired": node(43, updated_at=300),
        }
        result = self.update("merge", remote, now=1000)
        self.assertNotIn("old", result)
        self.assertNotIn("expired", result)
        self.assertEqual(result["mobile"]["lease_expires_at"], 1500)
        self.assertNotIn("mobile", self.update("merge", remote, now=1500))

    def test_expiry_boundary_is_exclusive_and_reregister_can_rejoin(self):
        self.update("register", {"mobile": node(42)})
        self.assertIn("mobile", self.update(now=1599))
        self.assertNotIn("mobile", self.update(now=1600))
        self.assertNotIn("mobile", self.update(now=1601))
        result = self.update("register", {"mobile": node(42)}, now=1700)
        self.assertEqual(result["mobile"]["last_seen"], 1700)
        self.assertEqual(result["mobile"]["lease_expires_at"], 2300)

    def test_real_heartbeat_with_lower_build_time_renews_existing_node(self):
        self.update("register", {"mobile": node(42, build_time=999999)})
        payload = node(42, build_time=1, endpoints={"default": "changed.example.test"})
        result = self.update("register", {"mobile": payload}, now=1200)
        record = result["mobile"]
        self.assertEqual(record["build_time"], 1)
        self.assertEqual(record["last_seen"], 1200)
        self.assertEqual(record["updated_at"], 1200)
        self.assertEqual(record["lease_expires_at"], 1800)
        self.assertNotIn("mobile", self.update(now=1800))

    def test_merge_prefers_last_seen_to_build_time_in_both_directions(self):
        old = node(42, build_time=999999, updated_at=1000, last_seen=1000,
                   lease_expires_at=1600, endpoints={"default": "old.example.test"})
        recent = node(42, build_time=1, updated_at=1100, last_seen=1100,
                      lease_expires_at=1700, endpoints={"default": "new.example.test"})
        self.update("merge", {"mobile": old}, now=1100)
        selected = self.update("merge", {"mobile": recent}, now=1200)["mobile"]
        self.assertEqual(selected["last_seen"], 1100)
        self.assertEqual(selected["build_time"], 1)
        self.assertEqual(selected["lease_expires_at"], 1700)
        self.assertEqual(self.update("merge", {"mobile": old}, now=1300)["mobile"],
                         selected)

    def test_controller_forwarding_preserves_authoritative_registration(self):
        controller_a = self.root / "controller-a.json"
        controller_b = self.root / "controller-b.json"
        a = self.update("register", {"mobile": node(42)}, state=controller_a)
        b = self.update("merge", a, now=1100, state=controller_b)
        self.assertEqual(b["mobile"], a["mobile"])
        a = self.update("merge", b, now=1200, state=controller_a)
        self.assertEqual(a["mobile"]["lease_expires_at"], 1600)
        a = self.update("register", {"mobile": node(42, build_time=1)},
                        now=1300, state=controller_a)
        b = self.update("merge", a, now=1400, state=controller_b)
        self.assertEqual(b["mobile"], a["mobile"])
        self.assertEqual(b["mobile"]["lease_expires_at"], 1900)
        self.assertNotIn("mobile", self.update("merge", a, now=1900, state=controller_b))

    def test_invalid_json_and_nonobject_payloads_do_not_change_state(self):
        self.update("register", {"mobile": node(42)})
        single = json.dumps({"windows": node(44)})
        for mode in ("merge", "register"):
            for payload in ('{', '{"mobile":', '{} {}', single + " " + single,
                            '', 'null', '[]', '1', '"x"'):
                with self.subTest(mode=mode, payload=payload):
                    self.assert_rejected(mode, payload, raw=True)

    def test_bad_records_and_unsafe_endpoints_do_not_change_state(self):
        self.update("register", {"mobile": node(42)})

        def candidate(**fields):
            return node(44, **fields)

        bad_records = [
            None, [], 1, {}, candidate(id=0), candidate(id=100), candidate(id=1.5),
            candidate(id=True), candidate(id="44"), candidate(dn42_ip4="999.1.2.3"),
            candidate(dn42_ip4="172.20.1"), candidate(dn42_ip4="172.20.0.1/24"),
            candidate(dn42_ip6="not-an-ipv6"), candidate(dn42_ip6="fd42::gg"),
            candidate(dn42_ip6="1:2:3:4:5:6:7:8:9"), candidate(dn42_ip6="::::"),
            candidate(dn42_ip6="12345::1"), candidate(dn42_ip6="1:2:3"),
            candidate(endpoints="peer.example.test"), candidate(endpoints=[1]),
            candidate(endpoints=[{"name": "bad\nname", "addr": "host.test", "port": 4500}]),
            candidate(endpoints=[{"name": "default", "addr": "x\nremote_addrs=evil", "port": 4500}]),
            candidate(endpoints=[{"name": "default", "addr": "host.test,%any", "port": 4500}]),
            candidate(endpoints=[{"name": "default", "addr": "$(touch /tmp/no)", "port": 4500}]),
            candidate(endpoints=[{"name": "default", "addr": "host.test", "port": 0}]),
            candidate(endpoints=[{"name": "default", "addr": "host.test", "port": 65536}]),
            candidate(endpoints=[{"name": "default", "addr": "host.test", "port": 1.5}]),
            candidate(endpoints=[{"name": "default", "addr": "host.test", "port": True}]),
            candidate(endpoints=[{"name": "default", "addr": "host.test", "port": 4500,
                                  "family": "invalid"}]),
            candidate(endpoints={"bad\nname": "host.test"}),
            candidate(endpoints=[{"name": "default", "value": "host.test\nanything"}]),
            candidate(endpoints=[{"name": f"ep{i}", "addr": "host.test", "port": 4500}
                                 for i in range(10)]), candidate(build_time="broken"),
        ]
        missing_ip = candidate()
        del missing_ip["dn42_ip4"]
        bad_records.append(missing_ip)
        for mode in ("merge", "register"):
            for bad in bad_records:
                with self.subTest(mode=mode, record=bad):
                    self.assert_rejected(mode, {"bad": bad})

    def test_mixed_valid_and_bad_records_reject_entire_merge(self):
        self.update()
        self.assert_rejected("merge", {
            "mobile": node(42, updated_at=1000, last_seen=1000, lease_expires_at=1600),
            "bad": node(43, dn42_ip4="invalid"),
        })
        self.assert_rejected("register", {"mobile": node(42), "windows": node(43)})
        self.assert_rejected("register", {})

    def test_rejected_update_in_if_command_substitution_preserves_state(self):
        self.update()
        before = self.state.read_bytes()
        command = (
            'source "$1"; if output=$(sdwan_state_update "$2" register "$3"); '
            'then exit 99; fi'
        )
        result = subprocess.run(
            ["bash", "-c", command, "dn42-conditional-test", str(LIBRARY),
             str(self.state), json.dumps({"bad": node(44, dn42_ip4="invalid")})],
            env=self.environment(1050), capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_bytes(), before)

    def test_corrupt_existing_state_rebuilds_valid_bootstrap_with_warning(self):
        for corrupt in ('{"broken":', '[]', 'null', '{} {}', '{"bad":{"id":0}}'):
            with self.subTest(state=corrupt):
                self.state.write_text(corrupt, encoding="utf-8")
                result = subprocess.run(
                    self.command("init"), env=self.environment(1000),
                    capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stderr.strip(), "Corrupt state recovery needs a warning")
                rebuilt = json.loads(result.stdout)
                self.assertEqual(set(rebuilt), {"fra0"})
                self.assertEqual(rebuilt["fra0"]["lease_expires_at"], 1600)
                self.assertEqual(json.loads(self.state.read_text()), rebuilt)

    def test_parallel_registers_keep_all_nodes_and_atomic_json(self):
        self.update()
        errors = []
        stop = threading.Event()
        observed = threading.Event()

        def observe_state():
            while not stop.is_set():
                try:
                    value = json.loads(self.state.read_text(encoding="utf-8"))
                    if not isinstance(value, dict):
                        errors.append("Reader saw non-object state")
                    observed.set()
                except (OSError, json.JSONDecodeError) as error:
                    errors.append(repr(error))
                stop.wait(0.001)

        reader = threading.Thread(target=observe_state, daemon=True)
        reader.start()
        processes = []
        try:
            self.assertTrue(observed.wait(5), "State observer did not start")
            for identifier in range(25, 45):
                name = f"dynamic{identifier}"
                process = subprocess.Popen(
                    self.command("register", {name: node(identifier)}),
                    env=self.environment(1000), stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True,
                )
                processes.append((name, process))
            with ThreadPoolExecutor(max_workers=len(processes)) as workers:
                outputs = list(workers.map(
                    lambda item: item[1].communicate(timeout=60), processes,
                ))
            for (name, process), (stdout, stderr) in zip(processes, outputs):
                self.assertEqual(process.returncode, 0, stderr)
                self.assertIn(name, json.loads(stdout))
        finally:
            for _, process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate()
            stop.set()
            reader.join(timeout=5)
        self.assertFalse(reader.is_alive())
        self.assertEqual(errors, [], "Concurrent reader observed a non-atomic state write")
        final = self.update()
        self.assertEqual(set(final), {"fra0"} | {f"dynamic{i}" for i in range(25, 45)})
        for identifier in range(25, 45):
            self.assertEqual(final[f"dynamic{identifier}"]["id"], identifier)
            self.assertEqual(final[f"dynamic{identifier}"]["lease_expires_at"], 1600)


@unittest.skipUnless(os.environ.get("DN42_SDWAN_CONTROLLER_SCRIPT"),
                     "Set DN42_SDWAN_CONTROLLER_SCRIPT for generated HTTP handler tests")
class SdwanControllerHttpTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dn42-sdwan-http-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.registry = self.root / "registry.json"
        self.bootstrap = self.root / "bootstrap.json"
        self.bootstrap.write_text(json.dumps({"fra0": node()}), encoding="utf-8")
        generated = Path(os.environ["DN42_SDWAN_CONTROLLER_SCRIPT"]).read_text()
        generated, count = re.subn(
            r'^export DN42_SDWAN_BOOTSTRAP_FILE="[^"]+"$',
            f'export DN42_SDWAN_BOOTSTRAP_FILE="{self.bootstrap}"',
            generated, flags=re.MULTILINE,
        )
        self.assertEqual(count, 1, "Generated handler must export its bootstrap file")
        generated, count = re.subn(
            r'^(EXPECTED_AUTH|TOKEN)=\$\(cat "[^"]+"\)$',
            lambda match: match[1] + "=test-token", generated, flags=re.MULTILINE,
        )
        self.assertGreaterEqual(count, 1, "Generated handler authentication not found")
        self.auth_token = "test-token"
        self.handler = self.root / "controller.sh"
        self.handler.write_text(generated, encoding="utf-8")

    def request(self, method, path="/sync", payload=None, now=1000, auth=None,
                raw=False, auth_name="X-DN42-Auth"):
        auth = self.auth_token if auth is None else auth
        body = (payload if raw else json.dumps(payload)).encode() if payload is not None else b""
        wire = (
            f"{method} {path} HTTP/1.1\r\n{auth_name}: {auth}\r\n"
            f"Content-Length: {len(body)}\r\n\r\n"
        ).encode() + body
        env = os.environ.copy()
        env.update({"DN42_SDWAN_STATE_DIR": str(self.root), "DN42_SDWAN_NOW": str(now)})
        result = subprocess.run(
            ["bash", str(self.handler)], input=wire, env=env,
            capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        headers, separator, body = result.stdout.partition(b"\r\n\r\n")
        self.assertTrue(separator, f"Invalid HTTP response: {result.stdout!r}")
        status = int(headers.splitlines()[0].split()[1])
        if status == 200:
            length = re.search(rb"Content-Length: ([0-9]+)", headers)
            self.assertIsNotNone(length)
            self.assertEqual(int(length[1]), len(body))
            return status, json.loads(body)
        return status, body.decode()

    def test_unknown_node_http_registration_expiry_and_reregistration(self):
        status, registered = self.request("POST", payload={"mobile": node(42)})
        self.assertEqual(status, 200)
        self.assertEqual(registered["mobile"]["last_seen"], 1000)
        self.assertEqual(registered["mobile"]["lease_expires_at"], 1600)
        status, queried = self.request("GET", "/peers", now=1200)
        self.assertEqual(status, 200)
        self.assertEqual(queried["mobile"], registered["mobile"])
        status, expired = self.request("GET", "/peers", now=1600)
        self.assertEqual(status, 200)
        self.assertNotIn("mobile", expired)
        status, renewed = self.request("POST", payload={"mobile": node(42)}, now=1700)
        self.assertEqual(status, 200)
        self.assertEqual(renewed["mobile"]["lease_expires_at"], 2300)
        self.assertEqual(self.request("GET", now=1800)[1]["mobile"], renewed["mobile"])

    def test_http_unauthorized_and_malformed_requests_preserve_registry(self):
        self.assertEqual(self.request("GET", "/peers")[0], 200)
        before = self.registry.read_bytes()
        for method in ("GET", "POST"):
            status, _ = self.request(method, payload={"mobile": node(42)}, auth="wrong")
            self.assertEqual(status, 401)
            self.assertEqual(self.registry.read_bytes(), before)
        bad_payloads = ('{', '[]', json.dumps({"bad": node(44, dn42_ip4="invalid")}),
                        json.dumps({"bad": node(44, id=0)}),
                        json.dumps({"mobile": node(42), "windows": node(43)}),
                        "x" * 65537)
        for payload in bad_payloads:
            with self.subTest(payload=payload[:80]):
                status, _ = self.request("POST", payload=payload, raw=True)
                self.assertEqual(status, 400)
                self.assertEqual(self.registry.read_bytes(), before)
        self.assertEqual(self.request("GET", "/not-found")[0], 404)

    def test_http_auth_header_case_preserves_mixed_case_token(self):
        self.auth_token = "MiXeD-test-token"
        generated = self.handler.read_text()
        self.assertEqual(generated.count("EXPECTED_AUTH=test-token"), 1)
        self.handler.write_text(generated.replace(
            "EXPECTED_AUTH=test-token", "EXPECTED_AUTH=" + self.auth_token,
        ), encoding="utf-8")
        for header in ("X-DN42-Auth", "x-dn42-auth", "X-dN42-aUtH"):
            with self.subTest(header=header):
                status, registered = self.request(
                    "POST", payload={"mobile": node(42)}, auth_name=header,
                )
                self.assertEqual(status, 200)
                self.assertIn("mobile", registered)
                self.assertEqual(self.request("GET", "/peers", auth_name=header)[0], 200)
        before = self.registry.read_bytes()
        self.assertEqual(self.request("GET", auth=self.auth_token.lower())[0], 401)
        self.assertEqual(self.registry.read_bytes(), before)

    def test_parallel_http_registrations_preserve_all_dynamic_nodes(self):
        self.assertEqual(self.request("GET", "/peers")[0], 200)

        def register(identifier):
            status, body = self.request("POST", payload={f"phone{identifier}": node(identifier)})
            self.assertEqual(status, 200)
            self.assertIn(f"phone{identifier}", body)

        with ThreadPoolExecutor(max_workers=20) as workers:
            list(workers.map(register, range(25, 45)))
        status, final = self.request("GET", "/peers", now=1100)
        self.assertEqual(status, 200)
        self.assertEqual(set(final), {"fra0"} | {f"phone{i}" for i in range(25, 45)})
        self.assertEqual(json.loads(self.registry.read_text()), final)


@unittest.skipUnless(os.environ.get("DN42_SDWAN_AGENT_SCRIPT"),
                     "Set DN42_SDWAN_AGENT_SCRIPT for generated agent tests")
class SdwanAgentTest(unittest.TestCase):
    def test_sync_removes_retired_peer_interface_and_ike_configuration(self):
        with tempfile.TemporaryDirectory(prefix="dn42-sdwan-agent-") as directory:
            root = Path(directory)
            conf = root / "conf"
            conf.mkdir()
            bootstrap = root / "bootstrap.json"
            bootstrap.write_text(json.dumps({"fra0": node(1, dn42_ip4="172.20.232.1")}),
                                 encoding="utf-8")
            cache = root / "peers.json"
            cache.write_text(json.dumps({"nue0": node(3, updated_at=0)}), encoding="utf-8")
            stale_conf = conf / "sdwan-dn42-nue0-default.conf"
            stale_conf.write_text("connections { dn42-nue0-default {} }\n", encoding="utf-8")
            mock_bin = root / "bin"
            mock_bin.mkdir()
            mock = mock_bin / "mock"
            mock.write_text("#!" + sys.executable + "\n" + r'''
import json
import os
from pathlib import Path
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["DN42_SDWAN_STATE_DIR"])
with (root / "mock-calls.jsonl").open("a") as log:
    log.write(json.dumps([command] + args) + "\n")
if command == "curl":
    sys.exit(7)
if command in ("systemctl", "systemd-notify"):
    sys.exit(99)
if command == "ip" and args == ["-j", "addr", "show", "up"]:
    print(json.dumps([{"ifname": "eth0", "addr_info": [
        {"family": "inet", "local": "172.20.232.1", "scope": "global"}
    ]}]))
elif command == "ip" and args == ["-o", "link", "show", "type", "xfrm"]:
    print("7: dn42x-nue0-de0@NONE: <UP> mtu 1360")
''', encoding="utf-8")
            mock.chmod(0o700)
            for command in ("ip", "ethtool", "curl", "swanctl", "birdc",
                            "systemctl", "systemd-notify"):
                (mock_bin / command).symlink_to(mock)

            generated = Path(os.environ["DN42_SDWAN_AGENT_SCRIPT"]).read_text()
            bootstrap_export = re.search(
                r'export DN42_SDWAN_BOOTSTRAP_FILE="([^"]+)"', generated,
            )
            self.assertIsNotNone(bootstrap_export)
            # The static self-endpoint reader uses this path too, not just the export.
            generated = generated.replace(bootstrap_export[1], str(bootstrap))
            generated, count = re.subn(
                r'(?m)^(\s*)TOKEN=\$\(cat "[^"]+"\)$',
                lambda match: match[1] + "TOKEN=test-token", generated,
            )
            self.assertEqual(count, 1, "Generated agent authentication not found")
            generated, count = re.subn(
                r'export PATH="', f'export PATH="{mock_bin}:', generated, count=1,
            )
            self.assertEqual(count, 1, "Generated agent PATH not found")
            agent = root / "agent.sh"
            agent.write_text(generated, encoding="utf-8")
            env = os.environ.copy()
            env.update({
                "DN42_SDWAN_STATE_DIR": str(root), "DN42_SDWAN_CONF_DIR": str(conf),
                "DN42_SDWAN_NOW": "1000",
            })
            result = subprocess.run(
                ["bash", str(agent), "--sync"], env=env,
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            peers = json.loads(cache.read_text())
            self.assertEqual(set(peers), {"fra0"})
            self.assertEqual(peers["fra0"]["last_seen"], 1000)
            self.assertFalse(stale_conf.exists())
            self.assertFalse(list(conf.glob("*nue0*")))
            calls = [json.loads(line) for line in (root / "mock-calls.jsonl").read_text().splitlines()]
            self.assertIn(["ip", "link", "del", "dn42x-nue0-de0"], calls)
            self.assertIn(["swanctl", "--terminate", "--ike", "dn42-nue0-default"], calls)
            self.assertTrue(any(call[0] == "curl" for call in calls))
            self.assertFalse(any(call[0] in ("systemctl", "systemd-notify") for call in calls))
            self.assertFalse(any(call[:2] == ["swanctl", "--initiate"] for call in calls))


if __name__ == "__main__":
    unittest.main()
