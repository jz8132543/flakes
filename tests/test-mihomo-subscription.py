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

# These executables never invoke curl, Mihomo, or systemctl outside the fixture.
FAKE_COMMAND = r'''
import json
import os
from pathlib import Path
import stat
import sys

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
    # A non-zero CURL_EXIT models both 4xx/5xx responses and transport errors.
    code = int(os.environ.get("CURL_EXIT", "0"))
    if code:
        record["curl_failed"] = True
    else:
        output.write_bytes((root / "download.yaml").read_bytes())
        record.update(downloaded=True, download_mode=mode(output))
elif command in ("mihomo", "mihomo-smart"):
    record["invoked"] = True
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
        self.staged = self.runtime / "subscription.yaml"
        self.token = "FAKE-subscription-token-do-not-log"
        self.url = f"https://subscription.example.test/full?token={self.token}&format=clash"
        self.write_private(self.credentials / "url", (self.url + "\n").encode(), 0o400)
        self.download = (
            b"# full private subscription\n"
            b"mixed-port: 7890\n"
            b"proxies: [{name: fixture, type: ss, server: example.test, port: 443}]\n"
            b"proxy-groups: [{name: PROXY, type: select, proxies: [fixture, DIRECT]}]\n"
            b"rules: ['MATCH,PROXY']\n"
        )
        self.write_private(self.root / "download.yaml", self.download)
        for name in ("curl", "mihomo", "mihomo-smart", "systemctl"):
            self.write_private(
                self.bin / name, (f"#!{sys.executable}\n" + FAKE_COMMAND).encode(), 0o700
            )
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
            # The updater calls the kernel by absolute path; the fork ships
            # mihomo-smart so a bare `mihomo` PATH lookup would fail.
            "MIHOMO_BIN": str(self.bin / "mihomo"),
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
        # The token must never reach process arguments or command records.
        self.assertNotIn(self.token, str(command))
        self.assertNotIn(self.token, self.records_text())
        return result

    def records_text(self):
        log = self.root / "commands.jsonl"
        return log.read_text() if log.exists() else ""

    def records(self, command=None):
        import json

        lines = self.records_text().splitlines()
        entries = [json.loads(line) for line in lines]
        if command is None:
            return entries
        return [entry for entry in entries if entry["command"] == command]

    def test_successful_full_fetch_and_atomic_private_install(self):
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        self.assertEqual(self.staged.read_bytes(), self.download)
        self.assertEqual(stat.S_IMODE(self.staged.stat().st_mode), 0o600)
        # No leftover download temporaries.
        self.assertEqual(
            [p.name for p in self.runtime.iterdir() if p.name.startswith(".subscription.")],
            [],
        )
        self.assertFalse(any(r["command"] == "systemctl" for r in self.records()))

        result = self.run_updater("install")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Mihomo subscription updated", result.stdout)
        self.assertEqual(self.target.read_bytes(), self.download)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        # The staged file is consumed once installed.
        self.assertFalse(self.staged.exists())
        restarts = self.records("systemctl")
        self.assertEqual(len(restarts), 1)
        self.assertEqual(restarts[0]["argv"], ["try-restart", "mihomo.service"])

    def test_download_failure_keeps_target_and_staged_file(self):
        self.write_private(self.target, b"previous subscription\n")
        self.assertEqual(
            self.run_updater("fetch", CURL_EXIT="22").returncode, 1
        )
        # Nothing is staged, so install has nothing to replace the target with.
        self.assertFalse(self.staged.exists())
        self.assertEqual(self.target.read_bytes(), b"previous subscription\n")
        self.assertFalse(any(r["command"] == "systemctl" for r in self.records()))
        self.assertIn("download failed", self.run_updater("fetch", CURL_EXIT="22").stderr)

    def test_http_error_codes_are_treated_as_failures(self):
        # curl --fail turns every 4xx/5xx into exit 22.
        for code in ("22", "404", "500", "503"):
            with self.subTest(curl_exit=code):
                self.run_updater("fetch", CURL_EXIT=code)
                self.assertFalse(self.staged.exists())
                self.assertFalse(any(r["command"] == "systemctl" for r in self.records()))

    def test_identical_download_does_not_restart(self):
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        self.assertEqual(self.run_updater("install").returncode, 0)
        self.assertEqual(len(self.records("systemctl")), 1)

        # A byte-identical subscription must not restart the daemon.
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        result = self.run_updater("install")
        self.assertEqual(result.returncode, 0)
        self.assertIn("unchanged", result.stdout)
        self.assertEqual(len(self.records("systemctl")), 1)

    def test_restart_failure_restores_previous_bytes_and_permissions(self):
        self.write_private(self.target, b"previous subscription\n", 0o600)
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        self.assertEqual(self.run_updater("install", SYSTEMCTL_FAIL_COUNT="1").returncode, 1)
        # The previous bytes and permissions are restored; the inode may change
        # because restore is an atomic rename from the backup copy.
        self.assertEqual(self.target.read_bytes(), b"previous subscription\n")
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        # A recovery restart is attempted after restoring.
        self.assertEqual(len(self.records("systemctl")), 2)
        # The staged file survives a failed install so the next run can retry
        # without re-downloading.
        self.assertTrue(self.staged.exists())
        self.assertEqual(self.staged.read_bytes(), self.download)

    def test_restart_and_recovery_failure_without_previous_config_removes_target(self):
        self.assertFalse(self.target.exists())
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        self.assertEqual(
            self.run_updater("install", SYSTEMCTL_FAIL_COUNT="2").returncode, 1
        )
        self.assertFalse(self.target.exists())
        self.assertTrue(self.staged.exists())

    def test_install_without_staged_subscription_is_rejected(self):
        result = self.run_updater("install")
        self.assertEqual(result.returncode, 1)
        self.assertIn("No staged", result.stderr)
        self.assertFalse(self.target.exists())

    def test_invalid_action_is_rejected(self):
        result = self.run_updater("reload")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Invalid", result.stderr)

    def test_https_only_and_curl_config_injection_rejected(self):
        # Only https URLs are accepted. Note that `$(id)` passes this filter by
        # design: the URL is written to a curl config file read from stdin and
        # never expanded by a shell, so it cannot inject commands. It is still
        # rejected downstream as an invalid host by curl itself.
        for url in (
            "http://subscription.example.test/full",
            'https://subscription.example.test/"x',
            "ftp://subscription.example.test/full",
            "not a url",
            "",
        ):
            with self.subTest(url=url):
                self.write_private(self.credentials / "url", (url + "\n").encode(), 0o400)
                result = self.run_updater("fetch")
                self.assertEqual(result.returncode, 1)
                self.assertIn("Invalid", result.stderr)
                self.assertFalse(any(r["command"] == "curl" for r in self.records()))

    def test_url_only_sent_on_curl_stdin_and_https_redirects_enforced(self):
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        argv = self.records("curl")[0]["argv"]
        self.assertNotIn(self.url, argv)
        self.assertNotIn(self.token, argv)
        self.assertIn("--config", argv)
        self.assertIn("-", argv)
        # The token reaches curl only through the stdin config file.
        self.assertIn(self.url, (self.root / "curl-stdin").read_text())
        self.assertIn("--proto", argv)
        self.assertIn("=https", argv)
        self.assertIn("--proto-redir", argv)

    def test_error_diagnostics_are_redacted(self):
        result = self.run_updater(
            "fetch", CURL_EXIT="22", COMMAND_ERROR=f"failed for {self.url}"
        )
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(self.token, result.stderr)
        self.assertNotIn(self.url, result.stderr)
        self.assertIn("download failed", result.stderr)

    def test_restart_error_diagnostics_are_redacted(self):
        self.write_private(self.target, b"previous subscription\n")
        self.assertEqual(self.run_updater("fetch").returncode, 0)
        result = self.run_updater(
            "install", SYSTEMCTL_FAIL_COUNT="1", COMMAND_ERROR=f"restart failed for {self.url}"
        )
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(self.token, result.stderr)
        self.assertNotIn(self.url, result.stderr)


class PublishedSubscriptionTest(unittest.TestCase):
    """Checks against the real published subscription documents."""

    def setUp(self):
        self.required = (
            "PUBLISHED_MIHOMO_CONFIG",
            "PUBLISHED_MIHOMO_SMART_CONFIG",
            "PUBLISHED_VLESS_URIS",
            "PUBLISHED_HEALTH_CHECK_URL",
            "MIHOMO_SMART_BIN",
            "MIHOMO_UPDATER_SCRIPT",
        )
        missing = [name for name in self.required if not os.environ.get(name)]
        if missing:
            self.skipTest(f"missing fixtures: {', '.join(missing)}")
        self.document = yaml.safe_load(
            Path(os.environ["PUBLISHED_MIHOMO_CONFIG"]).read_text()
        )

    def test_published_vless_nodes_use_matching_xhttp_and_reality_settings(self):
        document = yaml.safe_load(Path(os.environ["PUBLISHED_MIHOMO_CONFIG"]).read_text())
        self.assertEqual(document["log-level"], "silent")
        proxies = [proxy for proxy in document["proxies"] if proxy["type"] == "vless"]
        self.assertTrue(proxies)
        for proxy in proxies:
            with self.subTest(proxy=proxy["name"]):
                self.assertEqual(proxy["network"], "xhttp")
                self.assertEqual(proxy["servername"], "speedtest.dora.im")
                self.assertNotIn("flow", proxy)
                self.assertTrue(proxy["reality-opts"]["support-x25519mlkem768"])
                self.assertEqual(proxy["xhttp-opts"]["path"], "/speedtest")
                self.assertEqual(proxy["xhttp-opts"]["mode"], "stream-one")
                self.assertEqual(proxy["xhttp-opts"]["x-padding-bytes"], "100-1000")
                self.assertTrue(proxy["xhttp-opts"]["x-padding-obfs-mode"])
                self.assertEqual(proxy["xhttp-opts"]["x-padding-placement"], "header")
                self.assertEqual(proxy["xhttp-opts"]["x-padding-header"], "X-Padding")
                self.assertEqual(proxy["xhttp-opts"]["x-padding-method"], "repeat-x")
                self.assertEqual(proxy["xhttp-opts"]["reuse-settings"], {
                    "max-connections": "3-4",
                    "h-max-request-times": "1800-3000",
                    "h-max-reusable-secs": "1800-3000",
                    "h-keep-alive-period": 30,
                })
                self.assertEqual(proxy["xhttp-opts"]["uplink-chunk-size"], "524288-1048576")
                self.assertEqual(
                    proxy["xhttp-opts"]["sc-max-each-post-bytes"], "524288-1048576"
                )
                self.assertEqual(
                    proxy["xhttp-opts"]["sc-min-posts-interval-ms"], "10-30"
                )
        for group in document["proxy-groups"]:
            if "url" in group:
                self.assertEqual(group["url"], os.environ["PUBLISHED_HEALTH_CHECK_URL"])
        self.assertEqual(
            os.environ["PUBLISHED_HEALTH_CHECK_URL"],
            "https://www.gstatic.com/generate_204",
        )

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
                self.assertEqual(
                    json.loads(query["extra"][0]),
                    {
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
                        "uplinkChunkSize": proxy["xhttp-opts"]["uplink-chunk-size"],
                        "scMaxEachPostBytes": proxy["xhttp-opts"]["sc-max-each-post-bytes"],
                        "scMinPostsIntervalMs": proxy["xhttp-opts"]["sc-min-posts-interval-ms"],
                    },
                )

    def test_subscription_updater_validates_with_the_running_kernel(self):
        # The updater derives its PATH from services.mihomo.package. If that
        # option is not overridden, the fetch path keeps using upstream mihomo.
        self.assertEqual(
            os.environ["MIHOMO_REAL_BIN"],
            os.environ["MIHOMO_SMART_BIN"],
            "services.mihomo.package must be overridden to the running kernel",
        )
        # The fork ships mihomo-smart, so the script must not call bare `mihomo`.
        script = Path(os.environ["MIHOMO_UPDATER_SCRIPT"])
        self.assertTrue(script.is_file(), f"missing updater script: {script}")
        body = script.read_text()
        self.assertIn(
            f"MIHOMO_BIN={os.environ['MIHOMO_SMART_BIN']}",
            body,
            "updater must invoke the kernel by absolute path",
        )
        self.assertNotRegex(body, r"(?<![-\w])mihomo -t ")

    def test_mihomo_smart_fork_parses_its_own_published_configuration(self):
        import subprocess
        import tempfile

        smart = yaml.safe_load(
            Path(os.environ["PUBLISHED_MIHOMO_SMART_CONFIG"]).read_text()
        )
        self.assertEqual(smart["log-level"], "silent")
        # Same members and ordering; only scheduling fields may differ.
        main = yaml.safe_load(Path(os.environ["PUBLISHED_MIHOMO_CONFIG"]).read_text())
        self.assertEqual(smart["proxies"], main["proxies"])

        def members(group):
            return (group["name"], tuple(group.get("proxies", [])))

        self.assertEqual(
            [members(g) for g in smart["proxy-groups"]],
            [members(g) for g in main["proxy-groups"]],
        )
        for smart_group, main_group in zip(smart["proxy-groups"], main["proxy-groups"]):
            if main_group.get("type") == "url-test":
                self.assertEqual(smart_group["type"], "smart")
                self.assertTrue(smart_group["prefer-asn"])
                self.assertTrue(smart_group["uselightgbm"])
            else:
                self.assertEqual(smart_group["type"], main_group["type"])
        # The fork endpoint must not widen the listening surface.
        self.assertFalse(smart["allow-lan"])
        self.assertEqual(smart["bind-address"], "127.0.0.1")
        self.assertEqual(smart["external-controller"], "127.0.0.1:9090")
        self.assertEqual(smart["profile"]["smart-collector-size"], 100)
        self.assertTrue(smart["profile"]["store-selected"])
        self.assertTrue(smart["profile"]["store-fake-ip"])
        self.assertTrue(smart["geo-auto-update"])
        self.assertTrue(smart["lgbm-auto-update"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.yaml"
            text = Path(os.environ["PUBLISHED_MIHOMO_SMART_CONFIG"]).read_text()
            # SOPS placeholders are not real credentials.
            for proxy in smart["proxies"]:
                if proxy["type"] == "vless":
                    text = text.replace(
                        proxy["uuid"], "12345678-1234-1234-1234-123456789abc"
                    )
                    text = text.replace(
                        proxy["reality-opts"]["public-key"],
                        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                    )
                    text = text.replace(
                        proxy["reality-opts"]["short-id"], "0123456789abcdef"
                    )
            source.write_text(text)
            (root / "GeoIP.dat").symlink_to(os.environ["MIHOMO_GEOIP"])
            (root / "GeoSite.dat").symlink_to(os.environ["MIHOMO_GEOSITE"])
            (root / "Country.mmdb").symlink_to(os.environ["MIHOMO_MMDB"])
            result = subprocess.run(
                [os.environ["MIHOMO_SMART_BIN"], "-t", "-d", str(root), "-f", str(source)],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
