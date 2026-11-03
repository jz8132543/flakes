#!/usr/bin/env python3
"""Exercise generated network workers in isolated user-systemd services."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


MOCK = r'''
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["NETWORK_TEST_ROOT"])
command = Path(sys.argv[0]).name
args = sys.argv[1:]
online = (root / "online").exists()

if command == "ip":
    if "-j" in args:
        print("[]")
elif command == "curl" or (command == "tailscale" and args[0] == "up"):
    with (root / "attempts").open("a") as log:
        log.write(command + "\n")
    if not online:
        if (root / "fail-fast").exists():
            print("Temporary connection failure", file=sys.stderr)
            sys.exit(7)
        time.sleep(30)
        sys.exit(7)
    if command == "curl":
        print("{}")
    else:
        (root / "connected").touch()
elif command == "tailscale":
    state = "Running" if (root / "authenticated").exists() else "NoState"
    print('{"BackendState":"' + state + '"}')
elif command == "swanctl":
    if args[0] == "--load-all":
        if (root / "fail-reload").exists():
            sys.exit(1)
        (root / "reloaded").touch()
    elif args[0] == "--initiate":
        if not online:
            sys.exit(1)
        (root / "connected").touch()
'''


class NetworkBackgroundStartupTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo = Path(__file__).resolve().parents[1]
        cls.config = json.loads(subprocess.check_output(
            [
                "nix", "eval", "--json", "path:.#nixosConfigurations.arx8.config",
                "--apply", """cfg: {
                  agent = cfg.systemd.services.dn42-sdwan-agent.serviceConfig;
                  agentDrv = (builtins.head cfg.systemd.services.dn42-sdwan-agent.restartTriggers).drvPath;
                  setup = cfg.systemd.services.tailscale-setup.serviceConfig;
                  agentStartLimit = cfg.systemd.services.dn42-sdwan-agent.startLimitIntervalSec;
                  setupStartLimit = cfg.systemd.services.tailscale-setup.startLimitIntervalSec;
                  setupScript = cfg.systemd.services.tailscale-setup.script;
                  key = cfg.sops.secrets.tailscale_preauth_key.path;
                  timer = cfg.systemd.timers.dn42-sdwan-agent.timerConfig;
                }""",
            ],
            cwd=cls.repo, text=True,
        ))
        subprocess.run(
            ["nix-store", "--realise", cls.config["agentDrv"]],
            check=True, stdout=subprocess.DEVNULL,
        )
        cls.agent_script = Path(cls.config["agent"]["ExecStart"]).read_text()
        cls.worker_path = re.search(r'export PATH="([^"]+)"', cls.agent_script)[1]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="network-background-", dir="/tmp/kilo")
        self.root = Path(self.temp.name)
        self.unit = "network-background-test-" + uuid.uuid4().hex
        self.bin = self.root / "bin"
        self.bin.mkdir()
        mock = self.bin / "mock"
        mock.write_text("#!" + sys.executable + "\n" + MOCK)
        mock.chmod(0o700)
        for command in ("ip", "ethtool", "curl", "systemctl", "swanctl", "birdc", "tailscale"):
            (self.bin / command).symlink_to(mock)

    def tearDown(self):
        for suffix in (".timer", ".service"):
            subprocess.run(
                ["systemctl", "--user", "stop", self.unit + suffix],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        subprocess.run(
            ["systemctl", "--user", "reset-failed", self.unit + ".service"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.temp.cleanup()

    def wait_for(self, predicate, message, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        journal = subprocess.check_output(
            ["journalctl", "--user", "-u", self.unit, "--no-pager", "-n", "40"],
            text=True,
        )
        self.fail(message + "\n" + journal)

    def start_worker(self, script, properties, timer=False, runtime_limit=True):
        worker = self.root / "worker"
        worker.write_text(script)
        worker.chmod(0o700)
        command = ["systemd-run", "--user", "--quiet", "--unit=" + self.unit]
        for key in ("Type", "NotifyAccess", "RemainAfterExit", "Restart"):
            if key in properties:
                value = properties[key]
                if isinstance(value, bool):
                    value = "yes" if value else "no"
                command.append(f"--property={key}={value}")
        command += [
            "--property=StartLimitIntervalSec=0",
            "--property=TimeoutStartSec=5s",
            "--property=TimeoutStopSec=1s",
            "--setenv=NETWORK_TEST_ROOT=" + str(self.root),
            "--setenv=DN42_SDWAN_STATE_DIR=" + str(self.root / "state"),
            "--setenv=DN42_SDWAN_CONF_DIR=" + str(self.root / "conf"),
        ]
        if runtime_limit:
            command.append("--property=RuntimeMaxSec=2s")
        if timer:
            command += [
                "--on-active=0.01s", "--on-unit-inactive=0.1s",
                "--timer-property=AccuracySec=0.01s",
            ]
        else:
            command.append("--property=RestartSec=0.1s")
        command.append(str(worker))
        subprocess.run(command, check=True, timeout=10)
        started = time.monotonic()
        subprocess.run(
            ["systemctl", "--user", "start", self.unit + ".service"],
            check=True, timeout=10,
        )
        self.assertLess(time.monotonic() - started, 2, "Start waited for remote connectivity")

    def recover_network(self):
        attempts = self.root / "attempts"
        self.wait_for(
            lambda: attempts.exists() and len(attempts.read_text().splitlines()) >= 6,
            "Worker stopped retrying after repeated offline timeouts",
        )
        (self.root / "online").touch()
        self.wait_for(
            lambda: (self.root / "connected").exists(),
            "Worker did not connect after network recovery",
        )

    def test_dn42_readiness_and_timer_recovery(self):
        self.assertEqual(self.config["agent"]["Type"], "notify")
        self.assertEqual(self.config["agentStartLimit"], 0)
        self.assertEqual(self.config["timer"]["OnUnitInactiveSec"], "30s")
        script = self.agent_script.replace(
            'export PATH="', f'export PATH="{self.bin}:', 1,
        )
        script = re.sub(r'TOKEN=\$\(cat "[^"]+"\)', "TOKEN=test-token", script)
        self.start_worker(script, self.config["agent"], timer=True)
        self.assertTrue(list((self.root / "conf").glob("sdwan-*.conf")))
        self.assertTrue((self.root / "state" / "reload-pending").exists())
        (self.root / "fail-reload").touch()
        self.recover_network()
        self.assertTrue((self.root / "state" / "reload-pending").exists())
        (self.root / "fail-reload").unlink()
        self.wait_for(
            lambda: (self.root / "reloaded").exists()
            and not (self.root / "state" / "reload-pending").exists(),
            "Pending configuration reload was lost across offline failures",
        )

    def tailscale_script(self):
        key = self.root / "key"
        key.write_text("test-key\n")
        script = "#!/bin/bash\nset -e\n"
        script += f'export PATH="{self.bin}:{self.worker_path}"\n'
        script += self.config["setupScript"].replace(self.config["key"], str(key))
        return script.replace("/tmp/tailscale-setup.log", str(self.root / "login.log"))

    def test_tailscale_nonblocking_login_and_retry(self):
        self.assertEqual(self.config["setup"]["Type"], "exec")
        self.assertEqual(self.config["setupStartLimit"], 0)
        self.assertEqual(self.config["setup"]["Restart"], "on-failure")
        (self.root / "authenticated").touch()
        self.start_worker(self.tailscale_script(), self.config["setup"])
        self.recover_network()
        self.wait_for(
            lambda: subprocess.check_output(
                ["systemctl", "--user", "show", self.unit, "-p", "SubState", "--value"],
                text=True,
            ).strip() == "exited",
            "Successful login did not remain active",
        )

    def test_tailscale_fast_login_errors_do_not_fail_the_service(self):
        (self.root / "fail-fast").touch()
        script = self.tailscale_script().replace("sleep 10", "sleep 0.1")
        self.start_worker(script, self.config["setup"], runtime_limit=False)
        attempts = self.root / "attempts"
        self.wait_for(
            lambda: attempts.exists() and len(attempts.read_text().splitlines()) >= 6,
            "Ordinary login failures were not retried inside the worker",
        )
        self.assertEqual(subprocess.check_output(
            ["systemctl", "--user", "show", self.unit, "-p", "NRestarts", "--value"],
            text=True,
        ).strip(), "0")
        self.assertEqual(subprocess.check_output(
            ["systemctl", "--user", "show", self.unit, "-p", "ActiveState", "--value"],
            text=True,
        ).strip(), "active")
        self.recover_network()

    def test_postgres_routes_are_preserved_by_login(self):
        routes = json.loads(subprocess.check_output(
            [
                "nix", "eval", "--json", "path:.#nixosConfigurations.fra0.config",
                "--apply", """cfg: {
                  flags = cfg.services.tailscale.extraSetFlags;
                  addresses = cfg.networking.interfaces.lo.ipv4.addresses;
                  blockingUnit = builtins.hasAttr "tailscale-advertise-postgres" cfg.systemd.services;
                }""",
            ],
            cwd=self.repo, text=True,
        ))
        self.assertIn("--advertise-routes=10.222.222.1/32", routes["flags"])
        self.assertIn("--accept-routes", routes["flags"])
        self.assertIn({"address": "10.222.222.1", "prefixLength": 32}, routes["addresses"])
        self.assertFalse(routes["blockingUnit"])


if __name__ == "__main__":
    unittest.main()
