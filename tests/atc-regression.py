#!/usr/bin/env python3
"""Local ATC regression tests; never run the complete Ops initialization script.

Requires Python 3, nix, GNU awk, and (for SQL) psql. Examples:
  python3 tests/atc-regression.py
  python3 tests/atc-regression.py --pg-socket /tmp/kilo/atc-pg/socket --pg-port 55432
Start the disposable PostgreSQL server separately, with TCP disabled. All SQL
uses temporary tables and rolls back. No production files or databases are used.
"""

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FIXED = {
    "proxy.config.admin.user_id": "STRING trafficserver",
    "proxy.config.body_factory.template_sets_dir": "STRING /etc/trafficserver/body_factory",
    "proxy.config.http.server_ports": "STRING 8089",
    "proxy.config.cache.ram_cache.size": "INT 33554432",
    "proxy.config.net.listen_backlog": "INT 512",
}
ALIASES = {
    "proxy.config.exec_thread.autoconfig": "proxy.config.exec_thread.autoconfig.enabled",
    "proxy.config.cache.ram_cache.size": "proxy.config.ram_cache.size",
}
CUSTOM = "# Keep this comment and custom records verbatim.\n\nCONFIG proxy.config.http.insert_request_via_str INT 2\nLOCAL proxy.config.custom.label STRING two words\nproxy.config.unrelated.legacy 42\n"


def run(*args, text=None):
    result = subprocess.run(args, input=text, text=True, capture_output=True, cwd=ROOT)
    if result.returncode:
        raise RuntimeError(f"{shlex.join(map(str, args))}:\n{result.stderr}{result.stdout}")
    return result.stdout


def generated_script(attribute, name):
    context = json.loads(run("nix", "eval", "--json", f"path:.#{attribute}",
                             "--apply", "s: builtins.attrNames (builtins.getContext s)"))
    paths = [p for p in context if p.endswith(f"-{name}.drv")]
    assert len(paths) == 1, (name, context)
    derivations = json.loads(run("nix", "derivation", "show", paths[0]))
    drv = next(iter(derivations.get("derivations", derivations).values()))
    print(f"SOURCE {paths[0]}")
    return drv.get("structuredAttrs", {}).get("text") or drv["env"]["text"]


def records_case(script, baseline, work, name, source, expected):
    directory = work / name
    directory.mkdir()
    records = directory / "records.config"
    templates = directory / "body_factory"
    records.write_text(source)
    # Adapt only process boundaries; the generated awk program stays unchanged.
    adapted = script.replace("records=/var/lib/trafficserver/etc/records.config",
                             f"records={shlex.quote(str(records))}")
    adapted = adapted.replace("templates=/var/lib/trafficserver/etc/body_factory",
                              f"templates={shlex.quote(str(templates))}")
    adapted = adapted.replace("chown trafficserver:trafficserver",
                              f"chown {os.getuid()}:{os.getgid()}")
    adapted, count = re.subn(r"/nix/store/[^\s]+/bin/awk '",
                             shlex.quote(shutil.which("awk")) + " '", adapted)
    assert count == 1 and "records=/var/lib/" not in adapted
    assert "templates=/var/lib/" not in adapted
    (directory / "prepare.sh").write_text(adapted)
    # Exercise repair of a dangling body_factory link, not just a missing path.
    templates.symlink_to(directory / "missing-templates")
    run("bash", str(directory / "prepare.sh"))
    output = records.read_text()
    assert output.startswith(CUSTOM), "Unrelated records/comments changed"
    managed = output[len(CUSTOM):].splitlines()
    assert sorted(managed) == sorted(expected), f"{name}: unexpected records:\n{output}"
    assert len(managed) == len(baseline), "Duplicate managed settings remain"
    for key, value in FIXED.items():
        assert f"CONFIG {key} {value}" in managed, (key, output)
    assert templates.is_symlink()
    target = re.search(r'ln -sfnT (\S+) "\$templates"', script).group(1)
    assert os.readlink(templates) == target
    assert records.stat().st_mode & 0o777 == 0o644
    run("bash", str(directory / "prepare.sh"))
    assert records.read_text() == output, "Second preparation is not byte-idempotent"
    assert not list(directory.glob("records.config.*")), "Temporary records leaked"


def sql_case(script, baseline, work, socket, port):
    socket = socket.resolve(strict=True)
    assert socket.is_relative_to(Path("/tmp/kilo")), "Only /tmp/kilo database sockets allowed"
    assert (socket / f".s.PGSQL.{port}").is_socket(), "Temporary PostgreSQL is not running"
    marker = "-- Baseline records.config parameters for EDGE_ATS_GLOBAL"
    assert script.count(marker) == 1
    migration = script.split(marker, 1)[1].split("-- Ensure Role read-only exists", 1)[0]
    assert migration.strip().startswith("DO $$") and migration.strip().endswith("END $$;")
    (work / "migration.sql").write_text(migration)

    def literal(value):
        return "'" + value.replace("'", "''") + "'"

    def values(rows):
        return ",\n".join("(" + ",".join(map(literal, row)) + ")" for row in rows)

    canonical = [(f"CONFIG {key}", "records.config", value) for key, value in baseline.items()]
    canonical.append(("location", "set_dscp_0.config", "/var/lib/trafficserver/etc/dscp"))
    stale = []
    for key in list(baseline) + list(ALIASES.values()) + ["proxy.config.config_dir"]:
        stale += [(key, "records.config", "legacy-value"),
                  (f"CONFIG {key}", "records.config", "INT 999")]
    custom = [("CONFIG proxy.config.unrelated", "records.config", "STRING retain me"),
              ("proxy.config.custom", "records.config", "custom bare value"),
              ("CONFIG proxy.config.cache.ram_cache.size", "other.config", "INT 999")]
    sql = """
BEGIN;
CREATE TEMP TABLE profile (id INT PRIMARY KEY, name TEXT UNIQUE);
CREATE TEMP TABLE parameter (
  id SERIAL PRIMARY KEY, name TEXT, config_file TEXT, value TEXT,
  UNIQUE (name, config_file, value)
);
CREATE TEMP TABLE profile_parameter (
  profile INT REFERENCES profile(id), parameter INT REFERENCES parameter(id),
  PRIMARY KEY (profile, parameter)
);
CREATE TEMP TABLE server (id INT PRIMARY KEY, profile INT, config_update_time TIMESTAMPTZ);
INSERT INTO profile VALUES (1, 'EDGE_ATS_GLOBAL'), (2, 'OTHER_PROFILE');
INSERT INTO server VALUES (1, 1, '2000-01-01'), (2, 2, '2000-01-01');
"""
    sql += "CREATE TEMP TABLE expected (name TEXT, config_file TEXT, value TEXT);\n"
    sql += "INSERT INTO expected VALUES " + values(canonical + custom) + ";\n"
    sql += "INSERT INTO parameter (name, config_file, value) VALUES "
    # Existing correct records exercise the upsert/ON CONFLICT path too.
    sql += values(stale + custom + canonical[:2]) + ";\n"
    sql += """
INSERT INTO profile_parameter SELECT profile.id, parameter.id FROM profile CROSS JOIN parameter;
CREATE TEMP TABLE old_parameters AS SELECT * FROM parameter;
CREATE TEMP TABLE other_links AS SELECT * FROM profile_parameter WHERE profile = 2;
"""
    sql += migration + """
DO $$ BEGIN
  IF EXISTS (
    (SELECT p.name, p.config_file, p.value FROM parameter p JOIN profile_parameter pp
      ON pp.parameter = p.id WHERE pp.profile = 1 EXCEPT SELECT * FROM expected)
    UNION ALL
    (SELECT * FROM expected EXCEPT SELECT p.name, p.config_file, p.value
      FROM parameter p JOIN profile_parameter pp ON pp.parameter = p.id WHERE pp.profile = 1)
  ) THEN RAISE EXCEPTION 'Managed links differ: stale records remain or expected records missing'; END IF;
  IF EXISTS ((SELECT * FROM other_links EXCEPT SELECT * FROM profile_parameter)
    UNION ALL (SELECT * FROM profile_parameter WHERE profile = 2 EXCEPT SELECT * FROM other_links))
  THEN RAISE EXCEPTION 'Other profile links changed'; END IF;
  IF EXISTS (SELECT * FROM old_parameters EXCEPT SELECT * FROM parameter)
  THEN RAISE EXCEPTION 'Shared parameter rows deleted or mutated'; END IF;
  IF (SELECT config_update_time FROM server WHERE id = 1) IS DISTINCT FROM now()
  THEN RAISE EXCEPTION 'Edge update not stamped in migration transaction'; END IF;
  IF (SELECT config_update_time FROM server WHERE id = 2) IS DISTINCT FROM '2000-01-01'::timestamptz
  THEN RAISE EXCEPTION 'Other profile server stamp changed'; END IF;
END $$;
CREATE TEMP TABLE first_parameters AS SELECT * FROM parameter;
CREATE TEMP TABLE first_links AS SELECT * FROM profile_parameter;
"""
    sql += migration + """
DO $$ BEGIN
  IF EXISTS ((SELECT * FROM parameter EXCEPT SELECT * FROM first_parameters)
    UNION ALL (SELECT * FROM first_parameters EXCEPT SELECT * FROM parameter))
  THEN RAISE EXCEPTION 'Parameter values not idempotent'; END IF;
  IF EXISTS ((SELECT * FROM profile_parameter EXCEPT SELECT * FROM first_links)
    UNION ALL (SELECT * FROM first_links EXCEPT SELECT * FROM profile_parameter))
  THEN RAISE EXCEPTION 'Profile links not idempotent'; END IF;
END $$;
-- Missing EDGE_ATS_GLOBAL must be a no-op, without touching other profiles.
UPDATE profile SET name = 'RENAMED_EDGE' WHERE id = 1;
"""
    sql += migration + """
DO $$ BEGIN
  IF EXISTS ((SELECT * FROM parameter EXCEPT SELECT * FROM first_parameters)
    UNION ALL (SELECT * FROM first_parameters EXCEPT SELECT * FROM parameter))
    OR EXISTS ((SELECT * FROM profile_parameter EXCEPT SELECT * FROM first_links)
    UNION ALL (SELECT * FROM first_links EXCEPT SELECT * FROM profile_parameter))
  THEN RAISE EXCEPTION 'Migration without edge profile changed rows'; END IF;
END $$;
ROLLBACK;
"""
    (work / "regression.sql").write_text(sql)
    run("psql", "-X", "-h", str(socket), "-p", str(port), "-U", getpass.getuser(),
        "-d", "postgres", "-v", "ON_ERROR_STOP=1", text=sql)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-socket", type=Path)
    parser.add_argument("--pg-port", type=int, default=55432)
    args = parser.parse_args()
    raw = json.loads(run("nix", "eval", "--json", "--file", str(ROOT / "lib/data/atc-records.nix")))
    baseline = {key: f"{'INT' if isinstance(value, int) else 'STRING'} {value}"
                for key, value in raw.items()}
    for key, value in FIXED.items():
        assert baseline[key] == value, f"Unsafe shared baseline: {key}={baseline[key]}"
    script = generated_script("nixosConfigurations.hkg5.config.systemd.services.trafficserver.preStart",
                              "atc-prepare-records")
    ops = generated_script("nixosConfigurations.fra0.config.systemd.services.traffic-ops-init.serviceConfig.ExecStart",
                           "traffic-ops-db-init") if args.pg_socket else None
    expected = [f"CONFIG {key} {value}" for key, value in baseline.items()]
    legacy = "".join(f"{ALIASES.get(key, key)} {value}\n" for key, value in raw.items())
    legacy += "proxy.config.ram_cache.size 268435456\nproxy.config.net.listen_backlog 55720\n"
    legacy += "proxy.config.body_factory.template_sets_dir /missing/templates\n"
    legacy += "proxy.config.config_dir /obsolete/config\n"
    typed = "\n".join(expected) + "\nCONFIG proxy.config.config_dir STRING /obsolete/config\n"
    custom_expected = [line for line in expected if "proxy.config.log.logging_enabled " not in line]
    custom_expected += ["LOCAL proxy.config.log.logging_enabled INT 2"]
    duplicate = typed + "CONFIG proxy.config.log.logging_enabled INT 0\nLOCAL proxy.config.log.logging_enabled INT 2\n"
    duplicate += "CONFIG proxy.config.ram_cache.size INT 268435456\nCONFIG proxy.config.net.listen_backlog INT 55720\n"
    duplicate += "CONFIG proxy.config.body_factory.template_sets_dir STRING /missing/templates\n"
    typed_alias = typed.replace("proxy.config.exec_thread.autoconfig ",
                                "proxy.config.exec_thread.autoconfig.enabled ")
    tests = [
        ("missing-baseline", CUSTOM, expected),
        ("legacy-and-aliases", CUSTOM + legacy, expected),
        ("typed-records", CUSTOM + typed, expected),
        ("typed-aliases", CUSTOM + typed_alias, expected),
        ("duplicates-and-limits", CUSTOM + duplicate, custom_expected),
        ("indented-legacy", CUSTOM + "  proxy.config.log.logging_enabled 2\n",
         [line.replace("logging_enabled INT 3", "logging_enabled INT 2") for line in expected]),
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="atc-regression-", dir="/tmp/kilo") as tmp:
        work = Path(tmp)
        (work / "generated-prepare.sh").write_text(script)
        for name, source, output in tests:
            try:
                records_case(script, baseline, work, name, source, output)
                print(f"PASS {name} (including byte-idempotence)")
            except (AssertionError, RuntimeError) as error:
                failures.append(name)
                print(f"FAIL {name}: {error}")
        if ops:
            try:
                sql_case(ops, baseline, work, args.pg_socket, args.pg_port)
                print("PASS ops-migration (bare/typed links, isolation, update stamp, idempotence, absent profile)")
            except (AssertionError, RuntimeError) as error:
                failures.append("ops-migration")
                print(f"FAIL ops-migration: {error}")
        else:
            print("SKIP ops-migration: pass --pg-socket for a temporary PostgreSQL server")
    if failures:
        raise SystemExit(f"FAILED: {', '.join(failures)}")


if __name__ == "__main__":
    main()
