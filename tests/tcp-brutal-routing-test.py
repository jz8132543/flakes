#!/usr/bin/env python3
"""Run the Nix-generated TCP Brutal scripts with isolated route/proc mocks."""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


MOCK = r'''
import json
import os
from pathlib import Path
import shlex
import sys

root = Path(os.environ["BRUTAL_TEST_ROOT"])
if Path(sys.argv[0]).name == "sysctl":
    print("bbr")
    sys.exit(0)
args = sys.argv[1:]
family = args[0]
if args[1:] == ["route", "show", "default"]:
    with (root / "queries").open("a") as log:
        log.write(family + "\n")
    print(json.loads(os.environ["BRUTAL_DEFAULTS"])[family])
    sys.exit(0)
commands = ([shlex.split(line) for line in sys.stdin if line.strip()]
            if args[1:] == ["-batch", "-"] else [args[1:]])
for command in commands:
    if command[:2] != ["route", "replace"]:
        raise SystemExit("Unexpected ip operation: " + repr(command))
    with (root / "routes").open("a") as log:
        log.write(json.dumps([family, command]) + "\n")
    # Model the kernel rejecting an off-prefix gateway without RTNH_F_ONLINK.
    required = json.loads(os.environ["BRUTAL_REQUIRE_ONLINK"])
    if "via" in command and command[command.index("via") + 1] in required:
        if "onlink" not in command:
            print("RTNETLINK answers: No route to host", file=sys.stderr)
            sys.exit(1)
'''


class TcpBrutalRoutingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = shutil.which("bash")
        cls.awk = shutil.which("awk")
        if not cls.bash or not cls.awk:
            raise RuntimeError("bash and awk are required")
        if os.environ.get("TCP_BRUTAL_CN_SCRIPT") and os.environ.get("TCP_BRUTAL_NON_CN_SCRIPT"):
            cls.scripts = {
                "cn": Path(os.environ["TCP_BRUTAL_CN_SCRIPT"]).read_text(),
                "!cn": Path(os.environ["TCP_BRUTAL_NON_CN_SCRIPT"]).read_text(),
            }
            return
        repo = Path(__file__).resolve().parents[1]
        # Evaluate only this module with the locked input; no kernel build or registry.
        expression = r'''
          let
            flake = builtins.getFlake ("path:" + toString ./.);
            pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
            render = target:
              let module = import ./nixos/modules/optimize/brutal.nix {
                inherit (pkgs) lib;
                inherit (flake) inputs;
                pkgs = pkgs // {
                  writeShellScriptBin = name: text: { outPath = text; };
                };
                config = {
                  boot.kernelPackages = pkgs.linuxPackages;
                  optimize.brutal = {
                    inherit target;
                    enable = true;
                    bandwidth = 500;
                    enableIpv4 = true;
                    enableIpv6 = true;
                    extraCidrs = [ "198.51.100.0/24" "2001:db8:ffff::/48" ];
                  };
                };
              };
              in pkgs.lib.removeSuffix "/bin/tcp-brutal-apply-rules"
                module.config.content.systemd.services.tcp-brutal-china-rules.serviceConfig.ExecStart;
          in { cn = render "cn"; "!cn" = render "!cn"; }
        '''
        cls.scripts = json.loads(subprocess.check_output(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            cwd=repo, text=True, timeout=120,
        ))

    def exercise(self, target, defaults, expected):
        with tempfile.TemporaryDirectory(prefix="tcp-brutal-", dir=os.environ.get("TMPDIR", "/tmp/kilo")) as temp:
            root = Path(temp)
            mock = root / "mock"
            mock.write_text("#!" + sys.executable + "\n" + MOCK)
            mock.chmod(0o700)
            for name in ("ip", "sysctl"):
                (root / name).symlink_to(mock)
            proc = root / "rules"
            proc.touch()
            (root / "ipv4.txt").write_text("1.0.1.0/24\n")
            (root / "ipv6.txt").write_text("2400:3200::/32\n")
            (root / "private-ipv4.txt").write_text("10.0.0.0/8\n")
            (root / "private-ipv6.txt").write_text("fc00::/7\n")
            script = self.scripts[target].replace("/proc/net/tcp_brutal/rules", str(proc))
            for name, replacement in (("ip", root / "ip"), ("sysctl", root / "sysctl"),
                                      ("awk", self.awk)):
                script, count = re.subn(r"/nix/store/[^/]+/bin/" + name + r"\b",
                                        str(replacement), script)
                self.assertGreater(count, 0)
            script = re.sub(r"/nix/store/[^/]+-china-cidrs", str(root), script)
            script = re.sub(r"/nix/store/[^/]+-private-ipv([46])\.txt",
                            lambda match: str(root / f"private-ipv{match[1]}.txt"), script)
            self.assertNotRegex(script, r"/nix/store/[^/]+/bin/ip\b")
            subprocess.run([self.bash, "-n"], input=script, text=True, check=True)
            required = [via for _, via, onlink in expected.values() if onlink]
            result = subprocess.run(
                [self.bash, "-c", script], text=True, capture_output=True, timeout=10,
                env={**os.environ, "BRUTAL_TEST_ROOT": str(root),
                     "BRUTAL_DEFAULTS": json.dumps(defaults),
                     "BRUTAL_REQUIRE_ONLINK": json.dumps(required)},
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("TCP Brutal rules successfully applied!", result.stdout)
            self.assertEqual((root / "queries").read_text().splitlines(), ["-4", "-6"])
            routes = [json.loads(line) for line in (root / "routes").read_text().splitlines()] \
                if (root / "routes").exists() else []
            for family in ("-4", "-6"):
                commands = [command for route_family, command in routes if route_family == family]
                if family not in expected:
                    self.assertEqual(commands, [])
                    continue
                dev, via, onlink = expected[family]
                self.assertEqual(len(commands), 2 if target == "cn" else 5)
                for command in commands:
                    self.assertEqual(command[command.index("dev") + 1], dev)
                    self.assertEqual("via" in command, via is not None)
                    if via is not None:
                        self.assertEqual(command[command.index("via") + 1], via)
                    self.assertEqual("onlink" in command, onlink)
                    self.assertEqual(command[-2:], ["proto", "233"])
                    self.assertIn("lock", command)
                ccs = [command[command.index("lock") + 1] for command in commands]
                self.assertEqual(ccs, ["brutal"] * 2 if target == "cn"
                                 else ["brutal", "brutal", "bbr", "bbr", "brutal"])

    def test_default_gateway_matrix(self):
        normal = {
            "-4": "default via 192.0.2.1 dev eth0 proto static",
            "-6": "default via 2001:db8::1 dev eth0 proto static",
        }
        cases = [
            ("hkg5", {"-4": "default via 216.23.94.1 dev enp3s0 proto static",
                       "-6": "default via 2401:2660:2::1 dev enp3s0 proto static metric 1024 onlink pref medium"},
             {"-4": ("enp3s0", "216.23.94.1", False),
              "-6": ("enp3s0", "2401:2660:2::1", True)}),
            ("normal", normal, {"-4": ("eth0", "192.0.2.1", False),
                                "-6": ("eth0", "2001:db8::1", False)}),
            ("ipv4-onlink", {**normal, "-4": normal["-4"] + " onlink"},
             {"-4": ("eth0", "192.0.2.1", True), "-6": ("eth0", "2001:db8::1", False)}),
            ("link-local", {**normal, "-6": "default via fe80::1 dev eth0 proto ra"},
             {"-4": ("eth0", "192.0.2.1", False), "-6": ("eth0", "fe80::1", False)}),
            ("device-before-gateway", {family: "default dev ppp0\n" + route + " onlink"
                                       for family, route in normal.items()},
             {family: ("ppp0", None, False) for family in normal}),
            ("other-default-onlink", {family: route + "\n" + route.replace("eth0", "eth1") + " onlink"
                                      for family, route in normal.items()},
             {"-4": ("eth0", "192.0.2.1", False), "-6": ("eth0", "2001:db8::1", False)}),
            ("selected-default-onlink", {family: route + " onlink\n" + route.replace("eth0", "eth1")
                                         for family, route in normal.items()},
             {"-4": ("eth0", "192.0.2.1", True), "-6": ("eth0", "2001:db8::1", True)}),
            ("multipath", {family: "default proto static\n  nexthop " + route.split("default ")[1]
                            + " weight 1\n  nexthop " + route.split("default ")[1].replace("eth0", "eth1")
                            + " weight 1 onlink" for family, route in normal.items()},
             {"-4": ("eth0", "192.0.2.1", False), "-6": ("eth0", "2001:db8::1", False)}),
            ("ipv4-only", {**normal, "-6": ""}, {"-4": ("eth0", "192.0.2.1", False)}),
            ("ipv6-only", {**normal, "-4": ""}, {"-6": ("eth0", "2001:db8::1", False)}),
            ("no-default", {"-4": "", "-6": ""}, {}),
        ]
        for target in ("cn", "!cn"):
            for name, defaults, expected in cases:
                with self.subTest(target=target, case=name):
                    self.exercise(target, defaults, expected)


if __name__ == "__main__":
    unittest.main()
