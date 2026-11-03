#!/usr/bin/env python3
"""Verify generated TC 8.0.2 Monitor contracts without starting any service.

Optional --tc-source checks JSON keys against the pinned upstream source.
Optional --pg-socket executes ONLY extracted migrations in temporary tables,
inside a rollback transaction on a disposable /tmp/kilo PostgreSQL socket.
Never execute the full traffic-ops-db-init script or connect to a live DB.
"""

import argparse
import copy
import getpass
import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
# config/config.go Config and its UnmarshalJSON duration fields in TC 8.0.2.
TM_FIELDS = set("""
cache_polling_protocol crconfig_backup_file crconfig_history_count
distributed_polling health_flush_interval_ms http_polling_format http_timeout_ms
log_location_access log_location_debug log_location_error log_location_event
log_location_info log_location_warning max_events monitor_config_polling_interval_ms
peer_optimistic_quorum_min serve_read_timeout_ms serve_write_timeout_ms
short_hostname_override stat_buffer_interval_ms stat_flush_interval_ms
static_file_dir stat_polling tmconfig_backup_file traffic_ops_disk_retry_max
traffic_ops_min_retry_interval_ms traffic_ops_max_retry_interval_ms
""".split())
OPS_FIELDS = set("""
cdnName certFile httpListener httpsListener insecure keyFile password url username usingDummyTO
""".split())
ARGS = None


def run(*args, text=None):
    result = subprocess.run(args, input=text, text=True, capture_output=True, cwd=ROOT)
    if result.returncode:
        raise RuntimeError(f"{args}:\n{result.stderr}{result.stdout}")
    return result.stdout


def evaluate(attribute, apply=None, host="fra0"):
    command = ["nix", "eval", "--json", f"path:.#nixosConfigurations.{host}.config.{attribute}"]
    if apply:
        command += ["--apply", apply]
    return json.loads(run(*command))


def generated_text(attribute, name):
    context = evaluate(attribute, "s: builtins.attrNames (builtins.getContext (toString s))")
    paths = [p for p in context if p.endswith(f"-{name}.drv")]
    assert len(paths) == 1, context
    derivations = json.loads(run("nix", "derivation", "show", paths[0]))
    derivation = next(iter(derivations.get("derivations", derivations).values()))
    return derivation.get("structuredAttrs", {}).get("text") or derivation["env"]["text"]


def decode_astats(document, content_type="application/json"):
    """Contract model of cache/astats.go + statistics.go, not a live probe.

    Be stricter than Go's permissive decoder: missing ATS data is never ready.
    System.notAvailable remains a hard failure despite otherwise valid stats.
    """
    if content_type not in ("application/json", "text/json", "text/javascript", ""):
        raise ValueError("unsupported content type")
    if not isinstance(document.get("ats"), dict) or not document["ats"]:
        raise ValueError("missing ATS metrics")
    system = document["system"]
    name, fields = system["proc.net.dev"].split(":")
    counters = fields.split()
    if name != system["inf.name"] or len(counters) < 9:
        raise ValueError("interface contract mismatch")
    if any(not re.fullmatch(r"[0-9]+", counters[i]) for i in (0, 8)):
        raise ValueError("invalid byte counters")
    if type(system["inf.speed"]) is not int or system["inf.speed"] <= 0:
        raise ValueError("invalid Mbps capacity")
    load = re.split(r"[ /\t]+", system["proc.loadavg"].strip())
    if len(load) != 6:
        raise ValueError("invalid loadavg")
    for value in load[:3]:
        float(value)
    for value in load[3:]:
        int(value)
    if type(system.get("notAvailable", False)) is not bool:
        raise ValueError("invalid notAvailable")
    return not system.get("notAvailable", False)


class MonitorContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.monitor = json.loads(generated_text(
            'environment.etc."traffic_monitor/traffic_monitor.cfg".source', "traffic_monitor.cfg"))
        cls.ops = json.loads(generated_text(
            'environment.etc."traffic_monitor/traffic_ops.cfg".source', "traffic_monitor-ops.cfg"))
        cls.script = generated_text("systemd.services.traffic-ops-init.serviceConfig.ExecStart",
                                    "traffic-ops-db-init")
        cls.options = evaluate("services.atc.monitor", "c: { inherit (c) httpTimeoutMs "
                               "healthPollingIntervalMs healthConnectionTimeoutMs "
                               "statPollingIntervalMs peerPollingIntervalMs; }")
        cls.migration = cls.script.split("-- BEGIN managed monitoring contract migration", 1)[1]
        cls.migration = cls.migration.split("-- END managed monitoring contract migration", 1)[0]
        cls.addresses = cls.script.split("-- BEGIN managed edge monitoring addresses", 1)[1]
        cls.addresses = cls.addresses.split("-- END managed edge monitoring addresses", 1)[0]

    def test_supported_keys_and_separate_decoders(self):
        self.assertFalse(set(self.monitor) - TM_FIELDS)
        self.assertFalse(set(self.ops) - OPS_FIELDS)
        self.assertEqual(self.ops["password"], "")
        self.assertTrue(self.monitor["stat_polling"])
        self.assertFalse(self.monitor["distributed_polling"])
        self.assertEqual(self.monitor["cache_polling_protocol"], "both")
        self.assertEqual(self.monitor["http_polling_format"], "application/json")
        self.assertEqual(self.monitor["http_timeout_ms"], self.options["httpTimeoutMs"])
        self.assertNotIn("password", self.monitor)
        for name, value in self.monitor.items():
            if name.endswith("_ms"):
                self.assertIs(type(value), int)
                self.assertGreaterEqual(value, 0)

    def test_runtime_secret_and_nix_assertions(self):
        start = evaluate("systemd.services.traffic-monitor.serviceConfig.ExecStart")
        prestart = evaluate("systemd.services.traffic-monitor.preStart")
        self.assertIn("-opsCfg /run/traffic-monitor/traffic_ops.cfg", start)
        self.assertRegex(start, r"-config /nix/store/\S+-traffic_monitor.cfg")
        self.assertIn("--rawfile password", prestart)
        self.assertIn("chmod 0600 /run/traffic-monitor/traffic_ops.cfg", prestart)
        self.assertEqual(evaluate("assertions", "xs: map (x: x.message) "
                                  "(builtins.filter (x: !x.assertion) xs)"), [])
        self.assertLess(self.options["httpTimeoutMs"] * 100,
                        97 * min(self.options["healthPollingIntervalMs"],
                                  self.options["statPollingIntervalMs"]))

    def test_snapshot_is_published_after_api_start_and_failure_is_not_hidden(self):
        snapshot = evaluate("systemd.services.traffic-ops-snapshot", "s: { inherit (s) "
                            "after requires script serviceConfig; }")
        self.assertTrue(snapshot["serviceConfig"]["RemainAfterExit"])
        self.assertTrue(evaluate("systemd.services.traffic-ops-init.serviceConfig.RemainAfterExit"))
        self.assertIn("traffic-ops.service", snapshot["after"])
        self.assertIn("traffic-ops.service", snapshot["requires"])
        self.assertNotIn("/snapshot?", self.script)
        self.assertIn("/api/5.0/snapshot?cdn=dora-cdn", snapshot["script"])
        self.assertIn("--data-binary", snapshot["script"])
        self.assertIn("--rawfile p", snapshot["script"])
        self.assertIn("--max-time 5", snapshot["script"])
        self.assertIn("exit 1", snapshot["script"])
        self.assertNotIn("|| true", snapshot["script"])

    def test_edge_stats_route_precedes_redirect_and_rejects_forged_proxy_peer(self):
        proxy = evaluate("services.traefik", "t: { inherit (t.staticConfigOptions) entryPoints; "
                         "inherit (t.dynamicConfigOptions.http) routers services middlewares; }", host="sjc0")
        self.assertLess(proxy["entryPoints"]["http"]["http"]["redirections"]["entryPoint"]["priority"],
                        proxy["routers"]["atc-edge-astats"]["priority"])
        for name in ("http", "https"):
            self.assertIs(proxy["entryPoints"][name]["proxyProtocol"]["insecure"], False)
            self.assertEqual(proxy["entryPoints"][name]["proxyProtocol"]["trustedIPs"],
                             ["127.0.0.1/32", "::1/128"])
        service = proxy["services"]["atc-edge"]["loadBalancer"]
        self.assertEqual(service["servers"], [{"url": "http://127.0.0.1:8089"}])
        self.assertEqual(service["healthCheck"]["port"], 9130)
        self.assertEqual(service["healthCheck"]["path"], "/healthz")
        self.assertNotIn("ipStrategy", proxy["middlewares"]["atc-edge-stats-allow"]["ipAllowList"])

    def test_profile_interval_mapping_and_shared_row_safety(self):
        expected = {
            "heartbeat.polling.interval": self.options["healthPollingIntervalMs"],
            "health.polling.interval": self.options["statPollingIntervalMs"],
            "peers.polling.interval": self.options["peerPollingIntervalMs"],
            "health.connection.timeout": self.options["healthConnectionTimeoutMs"],
        }
        for name, value in expected.items():
            self.assertRegex(self.migration, rf"'{re.escape(name)}', '[^']+', '{value}'")
        self.assertIn("'http://${hostname}/_astats'", self.migration)
        self.assertIn("'health.polling.format', 'rascal.properties', 'astats'", self.migration)
        self.assertNotRegex(self.migration, r"DELETE\s+FROM\s+parameter\b")
        self.assertNotRegex(self.migration, r"UPDATE\s+parameter\b")
        self.assertNotIn("CROSS JOIN parameter", self.migration)
        self.assertIn("p.name = 'stat.polling.interval'", self.migration)
        self.assertIn("'status = reported_status'".strip("'"), self.script)
        self.assertIn("tcp_port = 80", self.script)

    def test_logical_interface_and_both_service_families(self):
        self.assertIn("logical statistics interface", self.addresses)
        self.assertIn("SET monitor = true", self.addresses)
        self.assertNotIn("monitor = false", self.addresses)
        data = json.loads((ROOT / "lib/data/data.json").read_text())["cdn"]
        for node in data["edgeNodes"]:
            for address in (node["ipv4"], node.get("ipv6")):
                if address:
                    self.assertIn(f"SELECT '{address}'::inet, 'eth0', s.id, true", self.addresses)
                    self.assertIn(f"AND ip.address = '{address}'::inet", self.addresses)

    def test_astats_parser_contract_and_hard_failures(self):
        document = {
            "ats": {"proxy.process.http.current_client_connections": 7,
                    "proxy.process.http.cache_hit_fresh": 123},
            "system": {"inf.name": "eth0", "inf.speed": 1000,
                       "proc.net.dev": "eth0: 10 1 0 0 0 0 0 0 20 2 0 0 0 0 0 0",
                       "proc.loadavg": "0.10 0.20 0.30 1/200 1234", "notAvailable": False},
        }
        self.assertTrue(decode_astats(document))
        off = copy.deepcopy(document)
        off["system"]["notAvailable"] = True
        self.assertFalse(decode_astats(off), "Worker OFF must not become healthy")
        invalid = [
            {"global": document["ats"]},
            {"ats": {}, "system": document["system"]},
        ]
        for field, value in (("proc.net.dev", " eth0: 10 1 0 0 0 0 0 0 20"),
                             ("proc.net.dev", "enp3s0: 10 1 0 0 0 0 0 0 20"),
                             ("proc.loadavg", "0.1 0.2 0.3"),
                             ("inf.speed", "1000")):
            item = copy.deepcopy(document)
            item["system"][field] = value
            invalid.append(item)
        for item in invalid:
            with self.assertRaises((ValueError, KeyError)):
                decode_astats(item)
        with self.assertRaises(ValueError):
            decode_astats(document, "application/json; charset=utf-8")

    def test_exact_pinned_upstream_fields(self):
        if not ARGS.tc_source:
            self.skipTest("pass --tc-source for upstream source validation")
        source = ARGS.tc_source
        tm = (source / "traffic_monitor/config/config.go").read_text()
        ops = (source / "traffic_monitor/handler/handler.go").read_text()
        tags = lambda text: set(re.findall(r'json:"([^",]+)', text)) - {"-"}
        self.assertEqual(tags(tm), TM_FIELDS)
        self.assertEqual(tags(ops), OPS_FIELDS)
        manager = (source / "traffic_monitor/manager/monitorconfig.go").read_text()
        self.assertIn('intervals.Stat = trafficOpsStatPollIntervalToDuration', manager)
        self.assertIn('monitorConfig.Config["heartbeat.polling.interval"]', manager)
        self.assertNotIn('monitorConfig.Config["stat.polling.interval"]', manager)

    def test_isolated_sql_migration(self):
        if not ARGS.pg_socket:
            self.skipTest("pass --pg-socket for isolated SQL validation")
        socket = ARGS.pg_socket.resolve(strict=True)
        self.assertTrue(socket.is_relative_to(Path("/tmp/kilo")))
        self.assertTrue((socket / f".s.PGSQL.{ARGS.pg_port}").is_socket())
        desired = re.findall(r"\('([^']+)', '([^']+)', '([^']+)', '([^']+)'\)", self.migration)
        self.assertEqual(len(desired), 7)
        quote = lambda s: "'" + s.replace("'", "''") + "'"
        sql = """
BEGIN;
CREATE TEMP TABLE profile (id INT PRIMARY KEY, name TEXT UNIQUE);
CREATE TEMP TABLE parameter (id SERIAL PRIMARY KEY, name TEXT, config_file TEXT,
  value TEXT, UNIQUE(name, config_file, value));
CREATE TEMP TABLE profile_parameter (profile INT, parameter INT,
  PRIMARY KEY(profile, parameter));
INSERT INTO profile VALUES (1,'RASCAL_GLOBAL'), (2,'EDGE_ATS_GLOBAL'), (3,'OTHER');
CREATE TEMP TABLE expected (profile INT, name TEXT, config_file TEXT, value TEXT);
"""
        for profile, name, file, value in desired:
            pid = 1 if profile == "RASCAL_GLOBAL" else 2
            sql += f"INSERT INTO expected VALUES ({pid},{quote(name)},{quote(file)},{quote(value)});\n"
            for old in (value, "stale"):
                sql += ("INSERT INTO parameter(name,config_file,value) VALUES "
                        f"({quote(name)},{quote(file)},{quote(old)});\n")
        sql += """
INSERT INTO parameter(name,config_file,value) VALUES
  ('stat.polling.interval','rascal-config.txt','60000'),
  ('custom','custom.properties','retain');
INSERT INTO profile_parameter SELECT pr.id,p.id FROM profile pr CROSS JOIN parameter p
  WHERE pr.id=3 OR (pr.id=1 AND p.config_file='rascal-config.txt')
  OR (pr.id=2 AND p.config_file='rascal.properties') OR p.name='custom';
CREATE TEMP TABLE original_rows AS SELECT * FROM parameter;
CREATE TEMP TABLE other_links AS SELECT * FROM profile_parameter WHERE profile=3;
"""
        sql += self.migration + """
DO $$ BEGIN
 IF EXISTS ((SELECT pp.profile,p.name,p.config_file,p.value FROM profile_parameter pp
   JOIN parameter p ON p.id=pp.parameter WHERE pp.profile IN (1,2) AND p.name<>'custom'
   EXCEPT SELECT * FROM expected) UNION ALL (SELECT * FROM expected EXCEPT
   SELECT pp.profile,p.name,p.config_file,p.value FROM profile_parameter pp
   JOIN parameter p ON p.id=pp.parameter WHERE pp.profile IN (1,2)))
 THEN RAISE EXCEPTION 'Wrong monitoring profile links'; END IF;
 IF EXISTS (SELECT * FROM original_rows EXCEPT SELECT * FROM parameter)
 THEN RAISE EXCEPTION 'Shared parameter rows mutated'; END IF;
 IF EXISTS ((SELECT * FROM other_links EXCEPT SELECT * FROM profile_parameter)
   UNION ALL (SELECT * FROM profile_parameter WHERE profile=3 EXCEPT SELECT * FROM other_links))
 THEN RAISE EXCEPTION 'Other profile links changed'; END IF;
END $$;
CREATE TEMP TABLE first_rows AS SELECT * FROM parameter;
CREATE TEMP TABLE first_links AS SELECT * FROM profile_parameter;
"""
        sql += self.migration + """
DO $$ BEGIN
 IF EXISTS ((SELECT * FROM first_rows EXCEPT SELECT * FROM parameter) UNION ALL
   (SELECT * FROM parameter EXCEPT SELECT * FROM first_rows)) OR EXISTS
   ((SELECT * FROM first_links EXCEPT SELECT * FROM profile_parameter) UNION ALL
   (SELECT * FROM profile_parameter EXCEPT SELECT * FROM first_links))
 THEN RAISE EXCEPTION 'Monitoring migration not idempotent'; END IF;
END $$;
CREATE TEMP TABLE server (id SERIAL PRIMARY KEY, host_name TEXT UNIQUE);
CREATE TEMP TABLE interface (name TEXT, monitor BOOLEAN, mtu INT, server INT,
  PRIMARY KEY(name,server));
CREATE TEMP TABLE ip_address (address INET, interface TEXT, server INT, service_address BOOLEAN,
  PRIMARY KEY(address,server), FOREIGN KEY(interface,server) REFERENCES interface(name,server));
"""
        nodes = json.loads((ROOT / "lib/data/data.json").read_text())["cdn"]["edgeNodes"]
        for node in nodes:
            sql += f"INSERT INTO server(host_name) VALUES ({quote(node['name'])});\n"
            sql += ("INSERT INTO interface SELECT 'eth0',false,1500,id FROM server "
                    f"WHERE host_name={quote(node['name'])};\n")
            if node.get("ipv6"):
                sql += ("INSERT INTO ip_address SELECT " + quote(node["ipv6"]) + "::inet,'eth0',id,false "
                        "FROM server WHERE host_name=" + quote(node["name"]) + ";\n")
        sql += self.addresses + """
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM interface WHERE NOT monitor) OR EXISTS
   (SELECT 1 FROM ip_address WHERE NOT service_address OR interface<>'eth0')
 THEN RAISE EXCEPTION 'Interface/family availability disabled'; END IF;
END $$;
CREATE TEMP TABLE first_addresses AS SELECT * FROM ip_address;
"""
        sql += self.addresses + """
DO $$ BEGIN
 IF EXISTS ((SELECT * FROM first_addresses EXCEPT SELECT * FROM ip_address) UNION ALL
   (SELECT * FROM ip_address EXCEPT SELECT * FROM first_addresses))
 THEN RAISE EXCEPTION 'Address migration not idempotent'; END IF;
END $$;
ROLLBACK;
"""
        run("psql", "-X", "-h", str(socket), "-p", str(ARGS.pg_port), "-U", getpass.getuser(),
            "-d", "postgres", "-v", "ON_ERROR_STOP=1", text=sql)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tc-source", type=Path)
    parser.add_argument("--pg-socket", type=Path)
    parser.add_argument("--pg-port", type=int, default=55433)
    ARGS, remaining = parser.parse_known_args()
    unittest.main(argv=[__file__, *remaining], verbosity=2)
