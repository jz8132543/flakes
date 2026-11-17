#!/usr/bin/env python3
"""Exercise generated network workers in isolated user-systemd services."""

import ast
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
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
                  setupRequires = cfg.systemd.services.tailscale-setup.requires;
                  daemon = cfg.systemd.services.tailscaled.serviceConfig;
                  daemonAfter = cfg.systemd.services.tailscaled.after;
                  daemonBefore = cfg.systemd.services.tailscaled.before;
                  daemonStartLimit = cfg.systemd.services.tailscaled.startLimitIntervalSec;
                  set = cfg.systemd.services.tailscaled-set.serviceConfig;
                  setStartLimit = cfg.systemd.services.tailscaled-set.startLimitIntervalSec;
                  mihomo = cfg.systemd.services.mihomo.serviceConfig;
                  mihomoStartLimit = cfg.systemd.services.mihomo.startLimitIntervalSec;
                  mihomoUnitDrv = cfg.systemd.units."mihomo.service".unit.drvPath;
                  waitOnline = cfg.systemd.services.NetworkManager-wait-online.serviceConfig;
                  waitOnlineStartLimit = cfg.systemd.services.NetworkManager-wait-online.startLimitIntervalSec;
                  storageUser = cfg.systemd.user.services.storage-papers.unitConfig.ConditionUser;
                  storagePath = cfg.systemd.user.services.storage-papers.environment.PATH;
                  storageCredentials = { inherit (cfg.sops.templates."rclone-papers.conf") owner mode; };
                  ccInit = builtins.head cfg.home-manager.users.tippy.systemd.user.services.cc-switch-init.Service.ExecStart;
                  ccInitDrv = builtins.head (builtins.attrNames (builtins.getContext (builtins.head cfg.home-manager.users.tippy.systemd.user.services.cc-switch-init.Service.ExecStart)));
                  nectarlink = { inherit (cfg.systemd.user.services.nectarlink) wantedBy partOf serviceConfig; };
                  nectarlinkAdb = { inherit (cfg.systemd.user.services.nectarlink-adb) wantedBy partOf serviceConfig; };
                  nectarlinkStateDrv = builtins.head (builtins.attrNames (builtins.getContext cfg.systemd.user.services.nectarlink.serviceConfig.ExecStartPre));
                  nectarlinkPort = cfg.desktop.nectarlink.port;
                  nectarlinkPackage = toString cfg.desktop.nectarlink.package;
                  nectarlinkPackageDrv = cfg.desktop.nectarlink.package.drvPath;
                  gsconnectEnabled = builtins.hasAttr "gsconnect-magicdns-poll" cfg.home-manager.users.tippy.systemd.user.services;
                  key = cfg.sops.secrets.tailscale_preauth_key.path;
                  timer = cfg.systemd.timers.dn42-sdwan-agent.timerConfig;
                }""",
            ],
            cwd=cls.repo, text=True,
        ))
        subprocess.run(
            ["nix-store", "--realise", cls.config["agentDrv"],
              cls.config["mihomoUnitDrv"], cls.config["ccInitDrv"], cls.config["nectarlinkStateDrv"]],
            check=True, stdout=subprocess.DEVNULL,
        )
        cls.agent_script = Path(cls.config["agent"]["ExecStart"]).read_text()
        cls.worker_path = re.search(r'export PATH="([^"]+)"', cls.agent_script)[1]
        cls.wait_script = Path(cls.config["mihomo"]["ExecStartPre"][2]).read_text()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="network-background-", dir="/tmp/kilo")
        self.root = Path(self.temp.name)
        self.unit = "network-background-test-" + uuid.uuid4().hex
        self.bin = self.root / "bin"
        self.bin.mkdir()
        mock = self.bin / "mock"
        mock.write_text("#!" + sys.executable + "\n" + MOCK)
        mock.chmod(0o700)
        # No-op commands must not spend the readiness budget starting Python.
        fast_mock = self.bin / "fast-mock"
        fast_mock.write_text('''#!/bin/sh
if [ "${0##*/}" = ip ]; then
    case "$*" in
        "-4 route show table main default")
            [ ! -f "$NETWORK_TEST_ROOT/default4" ] || printf 'default via 192.0.2.1 dev eth0\n'
            exit 0;;
        "-6 route show table main default")
            [ ! -f "$NETWORK_TEST_ROOT/default6" ] || printf 'default via fe80::1 dev eth0\n'
            exit 0;;
    esac
    for arg do
        if [ "$arg" = -j ]; then
            printf '[]\\n'
            break
        fi
    done
fi
''')
        fast_mock.chmod(0o700)
        for command in ("ip", "ethtool", "curl", "systemctl", "swanctl", "birdc", "tailscale"):
            target = fast_mock if command in ("ip", "ethtool", "systemctl", "birdc") else mock
            (self.bin / command).symlink_to(target)

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
        (self.root / "fail-reload").touch()
        self.recover_network()
        self.assertTrue(list((self.root / "conf").glob("sdwan-*.conf")))
        self.assertTrue((self.root / "state" / "reload-pending").exists())
        (self.root / "fail-reload").unlink()
        self.wait_for(
            lambda: (self.root / "reloaded").exists()
            and not (self.root / "state" / "reload-pending").exists(),
            "Pending configuration reload was lost across offline failures",
        )

    def test_dn42_readiness_does_not_wait_for_local_state_lock(self):
        state = self.root / "state"
        state.mkdir()
        script = self.agent_script.replace(
            'export PATH="', f'export PATH="{self.bin}:', 1,
        )
        script = re.sub(r'TOKEN=\$\(cat "[^"]+"\)', "TOKEN=test-token", script)
        with (state / "peers.json.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.start_worker(script, self.config["agent"])
            self.assertFalse((state / "peers.json").exists())
            self.assertFalse((self.root / "attempts").exists())
            fcntl.flock(lock, fcntl.LOCK_UN)
        self.wait_for(lambda: (self.root / "attempts").exists(),
                      "Background reconciliation did not resume after releasing the lock")

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

    def test_infrastructure_dependencies_and_unlimited_retries(self):
        for prefix in ("daemon", "set", "mihomo", "waitOnline"):
            self.assertEqual(self.config[prefix + "StartLimit"], 0)
        self.assertEqual(self.config["daemon"]["Restart"], "always")
        self.assertEqual(self.config["mihomo"]["Restart"], "always")
        self.assertEqual(self.config["set"]["Restart"], "on-failure")
        self.assertEqual(self.config["waitOnline"]["Restart"], "on-failure")
        self.assertNotIn("network.target", self.config["daemonBefore"])
        self.assertNotIn("network-online.target", self.config["daemonAfter"])
        self.assertNotIn("tailscaled.service", self.config["setupRequires"])
        self.assertIn("nm-online -q --timeout=30", self.config["waitOnline"]["ExecStart"][-1])

    def accelerated_wait_script(self):
        return self.wait_script.replace(
            "export PATH=", f'export PATH="{self.bin}:"', 1,
        ).replace("tries=60", "tries=2").replace("sleep 1", "sleep 0.05")

    def test_mihomo_wait_checks_route_content_and_both_address_families(self):
        env = dict(os.environ, NETWORK_TEST_ROOT=str(self.root))
        script = self.accelerated_wait_script()
        result = subprocess.run(["bash", "-c", script], env=env, capture_output=True)
        self.assertEqual(result.returncode, 1, "Empty successful ip output was mistaken for a route")
        for family in ("default4", "default6"):
            with self.subTest(family=family):
                (self.root / family).touch()
                result = subprocess.run(["bash", "-c", script], env=env, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                (self.root / family).unlink()

    def test_mihomo_recovers_after_more_than_five_failed_attempts(self):
        script = self.accelerated_wait_script()
        script = script.replace(
            'tries=2', 'echo attempt >> "$NETWORK_TEST_ROOT/attempts"\ntries=2',
        ).replace('exit 0', 'touch "$NETWORK_TEST_ROOT/connected"\nsleep 30\nexit 0')
        self.start_worker(script, {"Type": "exec", "Restart": self.config["mihomo"]["Restart"]},
                          runtime_limit=False)
        attempts = self.root / "attempts"
        self.wait_for(lambda: attempts.exists() and len(attempts.read_text().splitlines()) >= 7,
                      "Startup retries stopped while the network was offline")
        (self.root / "default4").touch()
        self.wait_for(lambda: (self.root / "connected").exists(),
                      "Startup did not recover after the default route appeared")

    def test_desktop_startup_regressions(self):
        self.assertEqual(self.config["storageUser"], "tippy")
        self.assertTrue(self.config["storagePath"].startswith("/run/wrappers/bin:"))
        self.assertEqual(self.config["storageCredentials"]["owner"], "tippy")
        self.assertEqual(self.config["storageCredentials"]["mode"], "0400")
        self.assertFalse(self.config["gsconnectEnabled"])
        for key in ("nectarlink", "nectarlinkAdb"):
            service = self.config[key]
            self.assertEqual(service["wantedBy"], ["graphical-session.target"])
            self.assertIn("graphical-session.target", service["partOf"])
            self.assertEqual(service["serviceConfig"]["UMask"], "0077")
        self.assertIn("tcp:localhost:5037", self.config["nectarlinkAdb"]["serviceConfig"]["ExecStart"])
        self.assertTrue(self.config["nectarlink"]["serviceConfig"]["ExecStart"].endswith(
            "--minimized"))
        script = Path(self.config["ccInit"]).read_text()
        self.assertEqual(subprocess.run(["bash", "-n", self.config["ccInit"]]).returncode, 0)
        python = script.split("<<'PYEOF'\n", 1)[1].split("\nPYEOF", 1)[0]
        ast.parse(python)

    def test_nectarlink_initial_settings_are_private_and_preserve_preferences(self):
        data_home = self.root / "data"
        env = dict(os.environ, XDG_DATA_HOME=str(data_home))
        script = self.config["nectarlink"]["serviceConfig"]["ExecStartPre"]
        subprocess.run([script], env=env, check=True)
        directory = data_home / "Nectarlink"
        settings_file = directory / "desktop-settings.json"
        settings = json.loads(settings_file.read_text())
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(settings_file.stat().st_mode & 0o777, 0o600)
        port_file = directory / "port"
        preferred_ports = [self.config["nectarlinkPort"]] * 2
        self.assertEqual([int(port) for port in port_file.read_text().split()], preferred_ports)
        for key in ("autoClipboard", "closeToTray", "sendToMenu", "nectarIsland"):
            self.assertTrue(settings[key])
        self.assertEqual(settings["language"], "zh_CN")
        self.assertTrue(settings["awayMode"])
        self.assertTrue(settings["walkthroughCompleted"])
        settings.update(theme="graphite", autoClipboard=False, autoUpdate=True, installUpdates=True,
                        language="en", awayMode=False, walkthroughCompleted=False)
        settings_file.write_text(json.dumps(settings))
        port_file.write_text("54321 54322\n")
        subprocess.run([script], env=env, check=True)
        updated = json.loads(settings_file.read_text())
        self.assertEqual(updated["theme"], "graphite")
        self.assertFalse(updated["autoClipboard"])
        self.assertFalse(updated["autoUpdate"])
        self.assertFalse(updated["installUpdates"])
        self.assertFalse(updated["startWithWindows"])
        self.assertEqual(updated["language"], "zh_CN")
        self.assertTrue(updated["awayMode"])
        self.assertTrue(updated["walkthroughCompleted"])
        self.assertEqual([int(port) for port in port_file.read_text().split()], preferred_ports)

    @unittest.skipUnless(shutil.which("Xvfb") and shutil.which("xwininfo"), "Xvfb and xwininfo required")
    def test_nectarlink_minimized_stays_hidden(self):
        subprocess.run(["nix-store", "--realise", self.config["nectarlinkPackageDrv"]],
                       check=True, stdout=subprocess.DEVNULL)
        xvfb = subprocess.Popen(
            ["Xvfb", "-displayfd", "1", "-screen", "0", "1024x768x24", "-nolisten", "tcp"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        try:
            display = ":" + xvfb.stdout.readline().strip()
            self.assertNotEqual(display, ":")
            for minimized in (False, True):
                with self.subTest(minimized=minimized):
                    env = dict(os.environ, DISPLAY=display, QT_QPA_PLATFORM="xcb",
                               QT_QUICK_BACKEND="software", NECTARLINK_NO_ADB="1",
                               DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/kilo/no-session-bus",
                               DBUS_SYSTEM_BUS_ADDRESS="unix:path=/tmp/kilo/no-system-bus")
                    args = [self.config["nectarlinkPackage"] + "/bin/nectarlink-desktop",
                            "--ui-check", "--data-dir", str(self.root / f"desktop-{minimized}")]
                    if minimized:
                        args.append("--minimized")
                    app = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL)
                    try:
                        visible = False
                        deadline = time.monotonic() + 3
                        while time.monotonic() < deadline:
                            self.assertIsNone(app.poll(), "Desktop exited before window check")
                            tree = subprocess.check_output(
                                ["xwininfo", "-root", "-children"], env=env, text=True)
                            for window in re.findall(r"^\s+(0x[0-9a-fA-F]+)", tree, re.MULTILINE):
                                info = subprocess.run(["xwininfo", "-id", window], env=env,
                                                      capture_output=True, text=True)
                                visible |= "Map State: IsViewable" in info.stdout
                            if visible:
                                break
                            time.sleep(0.1)
                        self.assertEqual(visible, not minimized)
                    finally:
                        app.terminate()
                        app.wait(timeout=25)
        finally:
            xvfb.terminate()
            xvfb.wait(timeout=10)
            xvfb.stdout.close()


if __name__ == "__main__":
    unittest.main()
