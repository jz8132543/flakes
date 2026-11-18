import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

import yaml


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "nixos/modules/desktop/mihomo-subscription.sh"
POLICY_SCRIPT = ROOT / "nixos/modules/desktop/mihomo-runtime-policy.py"

# These executables never invoke curl, Mihomo, or systemctl outside the fixture.
FAKE_COMMAND = r'''
import json
import os
from pathlib import Path
import stat
import sys

import yaml

root = Path(os.environ["TEST_ROOT"])
command = Path(sys.argv[0]).name
args = sys.argv[1:]
record = {"command": command, "argv": args}
code = 0

def mode(path):
    return stat.S_IMODE(path.stat().st_mode)

if command == "curl":
    (root / "curl-stdin").write_text(sys.stdin.read())
    output = Path(args[args.index("--output") + 1])
    code = int(os.environ.get("CURL_EXIT", "0"))
    output.write_bytes(b"partial download" if code else (root / "download.yaml").read_bytes())
    record.update(work=str(output.parent), work_mode=mode(output.parent), source_mode=mode(output))
elif command == "mihomo":
    work = Path(args[args.index("-d") + 1])
    candidate = Path(args[args.index("-f") + 1])
    (root / "validated.yaml").write_bytes(candidate.read_bytes())
    record.update(
        work=str(work), candidate=str(candidate), work_mode=mode(work),
        source_mode=mode(work / "source.yaml"), candidate_mode=mode(candidate),
        geoip=os.readlink(work / "GeoIP.dat"),
        geosite=os.readlink(work / "GeoSite.dat"),
        geoip_bytes=(work / "GeoIP.dat").read_text(),
        geosite_bytes=(work / "GeoSite.dat").read_text(),
    )
    try:
        document = yaml.safe_load(candidate.read_text())
        if not isinstance(document, dict):
            raise ValueError("not a YAML mapping")
        record["valid_yaml"] = True
    except Exception as error:
        print(str(error), file=sys.stderr)
        record["valid_yaml"] = False
        code = 1
    code = int(os.environ.get("MIHOMO_EXIT", "0")) or code
elif command == "systemctl":
    calls = root / "restart-count"
    count = int(calls.read_text()) + 1 if calls.exists() else 1
    calls.write_text(str(count))
    target = Path(os.environ["TEST_TARGET"])
    record["exists"] = target.exists()
    if target.exists():
        (root / f"restart-{count}.yaml").write_bytes(target.read_bytes())
        record.update(target_mode=mode(target), target_inode=target.stat().st_ino)
    record["temporary_modes"] = {
        path.name: mode(path)
        for path in target.parent.iterdir()
        if path.name.startswith((".subscription.", ".previous."))
    }
    code = int(count <= int(os.environ.get("SYSTEMCTL_FAIL_COUNT", "0")))
elif command == "policy-python":
    code = 1
else:
    raise AssertionError(f"unexpected fake command: {command}")

with (root / "commands.jsonl").open("a") as stream:
    stream.write(json.dumps(record) + "\n")
if code:
    # Deliberately hostile tool diagnostics test the updater's redaction boundary.
    error = os.environ.get("COMMAND_ERROR", f"simulated {command} failure")
    print(error)
    print(error, file=sys.stderr)
sys.exit(code)
'''


class SubscriptionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mihomo-subscription-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.credentials = self.root / "credentials"
        self.runtime = self.root / "runtime"
        self.target_directory = self.root / "target"
        for directory in (self.bin, self.credentials, self.runtime, self.target_directory):
            directory.mkdir(mode=0o700)
        self.target = self.target_directory / "config.yaml"
        self.staged = self.runtime / "config.yaml"
        self.token = "FAKE-subscription-token-do-not-log"
        self.url = f"https://subscription.example.test/full?token={self.token}&format=clash"
        self.write_private(self.credentials / "url", (self.url + "\n").encode(), 0o400)
        self.write_private(self.root / "geoip.dat", b"fixture geoip")
        self.write_private(self.root / "geosite.dat", b"fixture geosite")
        self.write_private(self.root / "country.mmdb", b"fixture country database")
        self.prefix = (
            "# full private subscription\n"
            "mixed-port: 7890\n"
            f"secret: '{self.token}'\n"
            "proxies: [{name: fixture, type: ss, server: example.test, port: 443, "
            "cipher: aes-128-gcm, password: '00123'}]\n"
            "proxy-groups: [{name: PROXY, type: select, proxies: [fixture, DIRECT]}]\n"
            "dns: {enable: true, nameserver-policy: {'+.example.test': ['https://1.1.1.1/dns-query#PROXY']}}\n"
            "tun: {enable: true, route-exclude-address: [10.0.0.0/8]}\n"
            "rules: "
        )
        self.suffix = (
            " # preserve this rules comment\n"
            "proxy-providers: {private: {url: 'https://provider.example.test/full', "
            "header: {Authorization: ['0007']}}}\n"
        )
        self.download = (
            self.prefix
            + "['UID,999,DIRECT', 'DST-PORT,22,DIRECT', 'DOMAIN-SUFFIX,example.test,DIRECT', 'MATCH,PROXY']"
            + self.suffix
        ).encode()
        self.write_private(self.root / "download.yaml", self.download)
        self.policy = {"ports": [22, 1022, 50560], "domain": "example.test", "dn42Domain": "overlay.test"}
        self.write_private(self.root / "policy.json", json.dumps(self.policy).encode())
        for name in ("curl", "mihomo", "systemctl", "policy-python"):
            self.write_private(self.bin / name, (f"#!{sys.executable}\n" + FAKE_COMMAND).encode(), 0o700)
        self.bash = shutil.which("bash")
        self.assertIsNotNone(self.bash, "bash must be available to run the updater")
        self.env = {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "HOME": str(self.root),
            "LC_ALL": "C",
            "TEST_ROOT": str(self.root),
            "TEST_TARGET": str(self.target),
            "CREDENTIALS_DIRECTORY": str(self.credentials),
            "RUNTIME_DIRECTORY": str(self.runtime),
            "MIHOMO_GEOIP": str(self.root / "geoip.dat"),
            "MIHOMO_GEOSITE": str(self.root / "geosite.dat"),
            "MIHOMO_MMDB": str(self.root / "country.mmdb"),
            "MIHOMO_POLICY_FILE": "",
            "MIHOMO_POLICY_SCRIPT": str(POLICY_SCRIPT),
            "MIHOMO_PYTHON": sys.executable,
        }

    def write_private(self, path, data, mode=0o600):
        if path.exists():
            path.chmod(0o600)
        path.write_bytes(data)
        path.chmod(mode)

    def run_updater(self, action, **environment):
        command = [self.bash, str(SCRIPT), action]
        if action == "install":
            command.append(str(self.target))
        result = subprocess.run(
            command, env=self.env | environment, capture_output=True, text=True, timeout=15
        )
        self.assertNotIn(self.url, str(command))
        return result

    def records(self, command=None):
        log = self.root / "commands.jsonl"
        records = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return [record for record in records if command is None or record["command"] == command]

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_redacted(result)

    def assert_redacted(self, result):
        for secret in (self.url, self.token):
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertNotIn(secret, json.dumps(self.records()))

    def assert_clean(self):
        self.assertEqual(list(self.runtime.iterdir()), [self.staged] if self.staged.exists() else [])
        self.assertEqual(list(self.target_directory.iterdir()), [self.target] if self.target.exists() else [])

    def seed_previous(self):
        self.write_private(self.staged, b"previous staged configuration\n")
        self.write_private(self.target, b"previous installed configuration\n", 0o640)
        return {
            path: (path.read_bytes(), path.stat().st_ino, stat.S_IMODE(path.stat().st_mode))
            for path in (self.staged, self.target)
        }

    def assert_previous(self, previous):
        for path, snapshot in previous.items():
            self.assertEqual(
                (path.read_bytes(), path.stat().st_ino, stat.S_IMODE(path.stat().st_mode)), snapshot
            )
        self.assertEqual(self.records("systemctl"), [])
        self.assert_clean()

    def test_successful_full_fetch_and_atomic_private_install(self):
        old = b"old installed configuration\n"
        self.write_private(self.target, old)
        with self.target.open("rb") as previous_file:
            old_inode = os.fstat(previous_file.fileno()).st_ino
            self.assert_success(self.run_updater("fetch"))
            self.assertEqual(self.target.read_bytes(), old)
            self.assertEqual(self.records("systemctl"), [])
            self.assertEqual(self.staged.read_bytes(), self.download)
            self.assertEqual((self.root / "validated.yaml").read_bytes(), self.download)
            self.assertEqual(stat.S_IMODE(self.staged.stat().st_mode), 0o600)
            self.assert_clean()
            self.assert_success(self.run_updater("install"))
            self.assertEqual(previous_file.read(), old)
            self.assertNotEqual(self.target.stat().st_ino, old_inode)
        self.assertEqual(self.target.read_bytes(), self.download)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        restarts = self.records("systemctl")
        self.assertEqual(len(restarts), 1)
        self.assertEqual(restarts[0]["argv"], ["try-restart", "mihomo.service"])
        self.assertEqual(restarts[0]["target_mode"], 0o600)
        self.assertTrue(restarts[0]["temporary_modes"])
        self.assertEqual(set(restarts[0]["temporary_modes"].values()), {0o600})
        self.assertEqual((self.root / "restart-1.yaml").read_bytes(), self.download)
        self.assert_clean()

    def test_url_only_sent_on_curl_stdin_and_https_redirects_enforced(self):
        self.assert_success(self.run_updater("fetch"))
        self.assertEqual((self.root / "curl-stdin").read_text(), f'url = "{self.url}"\n')
        curl = self.records("curl")[0]
        args = curl["argv"]
        self.assertEqual(args[:3], ["-q", "--config", "-"])
        for option, value in (
            ("--proto", "=https"), ("--proto-redir", "=https"),
            ("--noproxy", "*"), ("--max-filesize", "10485760"),
        ):
            self.assertEqual(args[args.index(option) + 1], value)
        for option in ("--fail", "--silent", "--location"):
            self.assertIn(option, args)
        self.assertEqual(curl["work_mode"], 0o700)
        self.assertEqual(curl["source_mode"], 0o600)
        validated = self.records("mihomo")[0]
        self.assertIn("-t", validated["argv"])
        self.assertEqual(validated["work"], curl["work"])
        self.assertEqual(validated["candidate"], str(Path(curl["work"]) / "config.yaml"))
        for key in ("source_mode", "candidate_mode"):
            self.assertEqual(validated[key], 0o600)
        self.assertEqual(validated["work_mode"], 0o700)
        self.assertEqual(validated["geoip"], self.env["MIHOMO_GEOIP"])
        self.assertEqual(validated["geosite"], self.env["MIHOMO_GEOSITE"])
        self.assertEqual(validated["geoip_bytes"], "fixture geoip")
        self.assertEqual(validated["geosite_bytes"], "fixture geosite")
        self.assertFalse(Path(curl["work"]).exists())
        self.assertEqual((self.credentials / "url").read_bytes(), (self.url + "\n").encode())
        self.assertEqual(stat.S_IMODE((self.credentials / "url").stat().st_mode), 0o400)
        self.assert_clean()

    def test_identical_download_does_not_restart_or_replace_target(self):
        self.assert_success(self.run_updater("fetch"))
        self.assert_success(self.run_updater("install"))
        before = self.target.stat()
        self.assert_success(self.run_updater("fetch"))
        result = self.run_updater("install")
        self.assert_success(result)
        self.assertIn("unchanged", result.stdout)
        self.assertEqual(len(self.records("curl")), 2)
        self.assertEqual(len(self.records("mihomo")), 2)
        self.assertEqual(len(self.records("systemctl")), 1)
        after = self.target.stat()
        self.assertEqual((before.st_ino, before.st_mtime_ns), (after.st_ino, after.st_mtime_ns))
        self.assert_clean()

    def test_byte_difference_restarts_even_when_yaml_is_equivalent(self):
        self.write_private(self.target, self.download + b"\n")
        self.assertEqual(yaml.safe_load(self.target.read_bytes()), yaml.safe_load(self.download))
        self.assert_success(self.run_updater("fetch"))
        self.assert_success(self.run_updater("install"))
        self.assertEqual(self.target.read_bytes(), self.download)
        self.assertEqual(len(self.records("systemctl")), 1)
        self.assert_clean()

    def test_actual_runtime_policy_is_validated_but_raw_subscription_is_installed(self):
        self.env["MIHOMO_POLICY_FILE"] = str(self.root / "policy.json")
        self.assert_success(self.run_updater("fetch"))
        effective_text = (self.root / "validated.yaml").read_text()
        self.assertTrue(effective_text.startswith(self.prefix))
        self.assertTrue(effective_text.endswith(self.suffix))
        effective = yaml.safe_load(effective_text)
        raw = yaml.safe_load(self.download)
        self.assertEqual(
            {key: value for key, value in effective.items() if key != "rules"},
            {key: value for key, value in raw.items() if key != "rules"},
        )
        rules = effective["rules"]
        self.assertEqual(rules[0], "UID,999,DIRECT")
        for port in self.policy["ports"]:
            private = rules.index("GEOIP,private,DIRECT")
            domestic = rules.index(f"AND,((NETWORK,TCP),(DST-PORT,{port}),(GEOIP,CN)),DIRECT")
            public = rules.index(f"AND,((NETWORK,TCP),(DST-PORT,{port})),PROXY")
            bypass = rules.index("DOMAIN-SUFFIX,example.test,DIRECT")
            self.assertLess(private, domestic)
            self.assertLess(domestic, public)
            self.assertLess(public, bypass)
        self.assertIn("GEOSITE,private,DIRECT", rules)
        self.assertIn("DOMAIN-SUFFIX,overlay.test,DIRECT", rules)
        self.assertNotIn("DST-PORT,22,DIRECT", rules)
        self.assertEqual(self.staged.read_bytes(), self.download)
        self.assert_success(self.run_updater("install"))
        self.assertEqual(self.target.read_bytes(), self.download)
        self.assertEqual(self.records("mihomo")[0]["candidate_mode"], 0o600)
        self.assert_clean()

    def test_download_error_is_redacted_and_keeps_staged_and_target(self):
        previous = self.seed_previous()
        result = self.run_updater("fetch", CURL_EXIT="22", COMMAND_ERROR=self.url)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("download failed", result.stderr)
        self.assert_redacted(result)
        self.assertEqual(self.records("curl")[0]["work_mode"], 0o700)
        self.assertEqual(self.records("curl")[0]["source_mode"], 0o600)
        self.assertEqual(self.records("mihomo"), [])
        self.assert_previous(previous)

    def test_invalid_yaml_is_redacted_and_keeps_staged_and_target(self):
        previous = self.seed_previous()
        self.write_private(self.root / "download.yaml", f"secret: [{self.token}\n".encode())
        result = self.run_updater("fetch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("validation failed", result.stderr)
        self.assertFalse(self.records("mihomo")[0]["valid_yaml"])
        self.assert_redacted(result)
        self.assert_previous(previous)

    def test_mihomo_validation_error_containing_url_is_redacted(self):
        previous = self.seed_previous()
        result = self.run_updater("fetch", MIHOMO_EXIT="1", COMMAND_ERROR=self.url)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("validation failed", result.stderr)
        self.assert_redacted(result)
        self.assert_previous(previous)

    def test_actual_policy_failure_keeps_staged_and_target(self):
        previous = self.seed_previous()
        self.env["MIHOMO_POLICY_FILE"] = str(self.root / "policy.json")
        self.write_private(self.root / "download.yaml", f"secret: [{self.token}\n".encode())
        result = self.run_updater("fetch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("policy preparation failed", result.stderr)
        self.assert_redacted(result)
        self.assertEqual(self.records("mihomo"), [])
        self.assert_previous(previous)

    def test_policy_command_error_containing_url_is_redacted(self):
        previous = self.seed_previous()
        result = self.run_updater(
            "fetch", MIHOMO_POLICY_FILE=str(self.root / "policy.json"),
            MIHOMO_PYTHON=str(self.bin / "policy-python"), COMMAND_ERROR=self.url,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("policy preparation failed", result.stderr)
        self.assertEqual(len(self.records("policy-python")), 1)
        self.assertEqual(self.records("mihomo"), [])
        self.assert_redacted(result)
        self.assert_previous(previous)

    def test_https_only_and_curl_config_injection_rejected(self):
        previous = self.seed_previous()
        for url in (
            "", "https://", f"http://example.test/{self.token}",
            "file:///fixture", "ftp://example.test/full", "//example.test/full",
            f'https://example.test/{self.token}"',
            f'https://example.test/{self.token}"\noutput = "injected"',
            f"https://example.test/{self.token}\\", "https://example.test/with space",
            "https://example.test/with\ttab", "https://example.test/full\nurl=other",
            "https://example.test/full\rurl=other",
        ):
            with self.subTest(url=url):
                self.write_private(self.credentials / "url", url.encode(), 0o400)
                result = self.run_updater("fetch")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stderr, "Invalid Mihomo subscription URL\n")
                self.assert_redacted(result)
                self.assertEqual(self.records(), [])
                self.assert_previous(previous)

    def test_first_install_without_previous_config(self):
        self.assert_success(self.run_updater("fetch"))
        self.assert_success(self.run_updater("install"))
        self.assertEqual(self.target.read_bytes(), self.download)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        self.assertEqual(len(self.records("systemctl")), 1)
        self.assert_clean()

    def test_restart_failure_restores_previous_bytes_and_permissions(self):
        old = b"previous installed configuration\n"
        self.write_private(self.target, old, 0o640)
        self.assert_success(self.run_updater("fetch"))
        result = self.run_updater("install", SYSTEMCTL_FAIL_COUNT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("restored the previous configuration", result.stderr)
        self.assert_redacted(result)
        self.assertEqual(self.target.read_bytes(), old)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o640)
        self.assertEqual(self.staged.read_bytes(), self.download)
        restarts = self.records("systemctl")
        self.assertEqual([record["argv"] for record in restarts], [["try-restart", "mihomo.service"]] * 2)
        self.assertEqual((self.root / "restart-1.yaml").read_bytes(), self.download)
        self.assertEqual((self.root / "restart-2.yaml").read_bytes(), old)
        self.assertEqual(restarts[0]["target_mode"], 0o600)
        self.assertEqual(restarts[1]["target_mode"], 0o640)
        self.assert_clean()

    def test_restart_and_recovery_failure_without_previous_config_removes_target(self):
        self.assert_success(self.run_updater("fetch"))
        result = self.run_updater("install", SYSTEMCTL_FAIL_COUNT="2")
        self.assertNotEqual(result.returncode, 0)
        self.assert_redacted(result)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.staged.read_bytes(), self.download)
        self.assertEqual([record["exists"] for record in self.records("systemctl")], [True, False])
        self.assert_clean()

    def test_restart_error_containing_subscription_url_is_redacted(self):
        self.write_private(self.target, b"previous installed configuration\n")
        self.assert_success(self.run_updater("fetch"))
        result = self.run_updater("install", SYSTEMCTL_FAIL_COUNT="1", COMMAND_ERROR=self.url)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_bytes(), b"previous installed configuration\n")
        self.assert_clean()
        self.assert_redacted(result)


@unittest.skipUnless(os.environ.get("PUBLISHED_MIHOMO_CONFIG"), "requires the Nix check fixture")
class PublishedSubscriptionTest(unittest.TestCase):
    def test_published_vless_nodes_use_matching_xhttp_and_reality_settings(self):
        document = yaml.safe_load(Path(os.environ["PUBLISHED_MIHOMO_CONFIG"]).read_text())
        proxies = [proxy for proxy in document["proxies"] if proxy["type"] == "vless"]
        self.assertTrue(proxies)
        for proxy in proxies:
            with self.subTest(proxy=proxy["name"]):
                self.assertEqual(proxy["network"], "xhttp")
                self.assertEqual(proxy["servername"], "speedtest.dora.im")
                self.assertNotIn("flow", proxy)
                self.assertTrue(proxy["reality-opts"]["support-x25519mlkem768"])
                self.assertEqual(proxy["xhttp-opts"]["path"], "/speedtest")
                self.assertEqual(proxy["xhttp-opts"]["host"], proxy["servername"])
                self.assertEqual(proxy["xhttp-opts"]["mode"], "stream-one")
                self.assertEqual(proxy["xhttp-opts"]["x-padding-bytes"], "100-1000")
                self.assertTrue(proxy["xhttp-opts"]["x-padding-obfs-mode"])
                self.assertEqual(proxy["xhttp-opts"]["x-padding-placement"], "header")
                self.assertEqual(proxy["xhttp-opts"]["x-padding-header"], "X-Padding")
                self.assertEqual(proxy["xhttp-opts"]["x-padding-method"], "repeat-x")
                self.assertNotIn("extra", proxy["xhttp-opts"])
                self.assertNotIn("xmux", proxy["xhttp-opts"])
                self.assertEqual(proxy["xhttp-opts"]["reuse-settings"], {
                    "max-connections": "3-3",
                    "h-max-request-times": "600-900",
                    "h-max-reusable-secs": "1800-3000",
                    "h-keep-alive-period": 45,
                })
                self.assertNotIn("max-concurrency", proxy["xhttp-opts"]["reuse-settings"])
        for group in document["proxy-groups"]:
            if group["name"] in ("ALL", "DN42", "NO-DN42"):
                self.assertEqual(group["url"], os.environ["PUBLISHED_HEALTH_CHECK_URL"])

    @unittest.skipUnless(os.environ.get("PUBLISHED_VLESS_URIS"), "requires the URI fixture")
    def test_vless_uris_match_published_mihomo_nodes(self):
        document = yaml.safe_load(Path(os.environ["PUBLISHED_MIHOMO_CONFIG"]).read_text())
        proxies = [proxy for proxy in document["proxies"] if proxy["type"] == "vless"]
        uris = Path(os.environ["PUBLISHED_VLESS_URIS"]).read_text().splitlines()
        self.assertEqual(len(uris), len(proxies))
        for uri, proxy in zip(uris, proxies):
            with self.subTest(proxy=proxy["name"]):
                parsed = urlsplit(uri)
                query = parse_qs(parsed.query)
                self.assertEqual(parsed.scheme, "vless")
                self.assertEqual(parsed.hostname, proxy["server"])
                self.assertEqual(parsed.port, proxy["port"])
                self.assertEqual(query["security"], ["reality"])
                self.assertEqual(query["sni"], [proxy["servername"]])
                self.assertEqual(query["type"], [proxy["network"]])
                self.assertNotIn("flow", query)
                self.assertEqual(query["path"], [proxy["xhttp-opts"]["path"]])
                self.assertEqual(query["host"], [proxy["xhttp-opts"]["host"]])
                self.assertEqual(query["mode"], [proxy["xhttp-opts"]["mode"]])
                self.assertEqual(json.loads(query["extra"][0]), {
                    "xPaddingBytes": proxy["xhttp-opts"]["x-padding-bytes"],
                    "xPaddingObfsMode": proxy["xhttp-opts"]["x-padding-obfs-mode"],
                    "xPaddingPlacement": proxy["xhttp-opts"]["x-padding-placement"],
                    "xPaddingHeader": proxy["xhttp-opts"]["x-padding-header"],
                    "xPaddingMethod": proxy["xhttp-opts"]["x-padding-method"],
                    "xmux": {
                        "maxConnections": proxy["xhttp-opts"]["reuse-settings"]["max-connections"],
                        "hMaxRequestTimes": proxy["xhttp-opts"]["reuse-settings"]["h-max-request-times"],
                        "hMaxReusableSecs": proxy["xhttp-opts"]["reuse-settings"]["h-max-reusable-secs"],
                        "hKeepAlivePeriod": proxy["xhttp-opts"]["reuse-settings"]["h-keep-alive-period"],
                    },
                })

    def test_real_mihomo_accepts_published_configuration_with_arx8_policy(self):
        document = yaml.safe_load(Path(os.environ["PUBLISHED_MIHOMO_CONFIG"]).read_text())
        # Replace encrypted-secret placeholders with public test credentials only.
        for proxy in document["proxies"]:
            if proxy["type"] != "vless":
                continue
            proxy["uuid"] = "12345678-1234-1234-1234-123456789abc"
            proxy["reality-opts"].update({
                "public-key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "short-id": "0123456789abcdef",
            })
        for rule in (
            "DOMAIN,api.noctalia.dev,DIRECT",
            "DOMAIN,api.open-meteo.com,DIRECT",
            "DOMAIN,invite.linuxdo.org,DIRECT",
        ):
            self.assertIn(rule, document["rules"])
            self.assertLess(document["rules"].index(rule), document["rules"].index("MATCH,PROXY"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.yaml"
            effective = root / "config.yaml"
            source.write_text(yaml.safe_dump(document))
            (root / "GeoIP.dat").symlink_to(os.environ["MIHOMO_GEOIP"])
            (root / "GeoSite.dat").symlink_to(os.environ["MIHOMO_GEOSITE"])
            (root / "Country.mmdb").symlink_to(os.environ["MIHOMO_MMDB"])
            for command in (
                [sys.executable, str(POLICY_SCRIPT), str(source), str(effective), os.environ["MIHOMO_POLICY_FILE"]],
                [os.environ["MIHOMO_REAL_BIN"], "-t", "-d", str(root), "-f", str(effective)],
            ):
                result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
