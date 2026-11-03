import copy
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

import yaml

SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "nixos/modules/desktop/mihomo-runtime-policy.py"
)
spec = importlib.util.spec_from_file_location("mihomo_runtime_policy", SCRIPT)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimePolicyTest(unittest.TestCase):
    def setUp(self):
        self.password = "FAKE-provider-password:do-not-log"
        self.policy = {
            "ports": [22, 1022, 50560, 22],
            "domain": "example.test",
            "dn42Domain": "overlay.test",
        }
        self.config = {
            "mode": "rule",
            "secret": self.password,
            "proxies": [{"name": "fixture", "type": "ss", "password": self.password}],
            "proxy-groups": [
                {"name": "PROXY", "type": "select", "proxies": ["fixture", "DIRECT"]}
            ],
            "proxy-providers": {
                "private": {
                    "url": "https://example.test/sub",
                    "header": {"Authorization": [self.password]},
                }
            },
            "dns": {
                "nameserver-policy": {
                    "+.example.test": ["https://1.1.1.1/dns-query#PROXY"]
                }
            },
            "tun": {"enable": True, "route-exclude-address": ["10.0.0.0/8"]},
            "rules": [
                "UID,999,DIRECT",
                "PROCESS-NAME,charon,DIRECT",
                "DST-PORT,22,DIRECT",
                "DST-PORT,1022,DIRECT",
                "DST-PORT,50560,DIRECT",
                "DST-PORT,2222,DIRECT",
                "DST-PORT,22,DIRECT,no-resolve",
                "AND,((NETWORK,UDP),(DST-PORT,22)),DIRECT",
                "DOMAIN-SUFFIX,example.test,DIRECT",
                "GEOIP,private,DIRECT,no-resolve",
                "MATCH,PROXY",
            ],
        }

    def test_only_rule_settings_change_and_input_is_immutable(self):
        original = copy.deepcopy(self.config)
        result = runtime.prepare_policy(self.config, self.policy)
        self.assertEqual(self.config, original)
        self.assertEqual(
            {k: v for k, v in result.items() if k != "rules"},
            {k: v for k, v in original.items() if k != "rules"},
        )

    def test_exact_ports_and_existing_rules_preserved(self):
        result = runtime.prepare_policy(self.config, self.policy)["rules"]
        for port in [22, 1022, 50560]:
            self.assertNotIn(f"DST-PORT,{port},DIRECT", result)
            self.assertIn(f"AND,((NETWORK,TCP),(DST-PORT,{port})),PROXY", result)
        for rule in self.config["rules"]:
            if rule not in {
                "DST-PORT,22,DIRECT",
                "DST-PORT,1022,DIRECT",
                "DST-PORT,50560,DIRECT",
            }:
                self.assertIn(rule, result)
        self.assertEqual(result[:2], self.config["rules"][:2])

    def test_private_domestic_and_public_order_before_domain_bypass(self):
        rules = runtime.prepare_policy(self.config, self.policy)["rules"]
        guard = rules.index("GEOIP,private,DIRECT")
        for port in [22, 1022, 50560]:
            direct = rules.index(
                f"AND,((NETWORK,TCP),(DST-PORT,{port}),(GEOIP,CN)),DIRECT"
            )
            proxy = rules.index(f"AND,((NETWORK,TCP),(DST-PORT,{port})),PROXY")
            self.assertLess(guard, direct)
            self.assertLess(direct, proxy)
            self.assertLess(proxy, rules.index("DOMAIN-SUFFIX,example.test,DIRECT"))
        for guard in [
            "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
            "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
            "IP-CIDR,fc00::/7,DIRECT,no-resolve",
            "DOMAIN-SUFFIX,overlay.test,DIRECT",
            "DOMAIN-SUFFIX,ts,DIRECT",
            "DOMAIN-SUFFIX,et,DIRECT",
        ]:
            self.assertLess(
                rules.index(guard),
                rules.index("AND,((NETWORK,TCP),(DST-PORT,22)),PROXY"),
            )
        self.assertFalse(
            any("ts.example.test" in rule or "DST-PORT,443" in rule for rule in rules)
        )

    def test_idempotence_and_duplicate_managed_rules(self):
        once = runtime.prepare_policy(self.config, self.policy)
        repeated = {
            **once,
            "rules": once["rules"]
            + ["GEOIP,private,DIRECT", "AND,((NETWORK,TCP),(DST-PORT,22)),PROXY"],
        }
        self.assertEqual(runtime.prepare_policy(once, self.policy), once)
        self.assertEqual(runtime.prepare_policy(repeated, self.policy), once)

    def test_fallback_insertion_before_first_match(self):
        self.config["rules"] = [
            "UID,999,DIRECT",
            "MATCH,PROXY",
            "DOMAIN-SUFFIX,example.test,DIRECT",
        ]
        rules = runtime.prepare_policy(self.config, self.policy)["rules"]
        self.assertLess(
            rules.index("AND,((NETWORK,TCP),(DST-PORT,22)),PROXY"),
            rules.index("MATCH,PROXY"),
        )

    def test_invalid_ports_domains_rules_and_missing_adapter_rejected(self):
        for ports in [[], [0], [65536], [True], ["22,PROXY"], "22"]:
            with self.subTest(ports=ports), self.assertRaises(ValueError):
                runtime.prepare_policy(self.config, {**self.policy, "ports": ports})
        for key in ["domain", "dn42Domain"]:
            for domain in [
                "bad,PROXY",
                "bad\nDOMAIN,x,PROXY",
                ".invalid",
                "-invalid",
                "a" * 254,
            ]:
                with self.subTest(key=key, domain=domain), self.assertRaises(
                    ValueError
                ):
                    runtime.prepare_policy(self.config, {**self.policy, key: domain})
        with self.assertRaises(ValueError):
            runtime.prepare_policy({**self.config, "rules": [42]}, self.policy)
        with self.assertRaises(ValueError):
            runtime.prepare_policy({**self.config, "proxy-groups": []}, self.policy)

    def test_cli_private_output_immutable_source_and_no_secret_logging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / "credential.yaml"
            output = root / "config.yaml"
            policy = root / "policy.json"
            credential.write_text(yaml.safe_dump(self.config), encoding="utf-8")
            os.chmod(credential, 0o400)
            original = credential.read_bytes()
            policy.write_text(json.dumps(self.policy), encoding="utf-8")
            command = [
                sys.executable,
                str(SCRIPT),
                str(credential),
                str(output),
                str(policy),
            ]
            for _ in range(2):
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")
                self.assertEqual(credential.read_bytes(), original)
                self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
                self.assertEqual(
                    yaml.safe_load(output.read_text()),
                    runtime.prepare_policy(self.config, self.policy),
                )
            self.assertFalse(list(root.glob(".config-*")))

    def test_cli_yaml_error_is_redacted_and_does_not_replace_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / "credential.yaml"
            output = root / "config.yaml"
            policy = root / "policy.json"
            credential.write_text(f"secret: [{self.password}\n", encoding="utf-8")
            output.write_text("previous-good-config", encoding="utf-8")
            policy.write_text(json.dumps(self.policy), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(credential),
                    str(output),
                    str(policy),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertEqual(
                result.stderr, "Mihomo runtime policy preparation failed\n"
            )
            self.assertNotIn(self.password, result.stdout + result.stderr)
            self.assertEqual(output.read_text(), "previous-good-config")

    def test_yaml_boolean_like_credentials_remain_strings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / "credential.yaml"
            output = root / "config.yaml"
            policy = root / "policy.json"
            credential.write_text(
                "secret: off\nproxies:\n  - name: PROXY\n    password: yes\n"
                "    udp: true\nrules: ['MATCH,PROXY']\n",
                encoding="utf-8",
            )
            policy.write_text(json.dumps(self.policy), encoding="utf-8")
            runtime.prepare_file(credential, output, policy)
            result = yaml.load(output.read_text(), Loader=runtime.ConfigLoader)
            self.assertEqual(result["secret"], "off")
            self.assertEqual(result["proxies"][0]["password"], "yes")
            self.assertIs(result["proxies"][0]["udp"], True)

    def test_non_rule_yaml_text_is_preserved_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / "credential.yaml"
            output = root / "config.yaml"
            policy = root / "policy.json"
            prefix = "# private config\nproxies: [{name: PROXY, password: 00123}]\nsecret: off\nrules: "
            suffix = " # rules comment\nproxy-providers: {private: {header: {Authorization: [0007]}}}\n"
            credential.write_text(prefix + "['MATCH,PROXY']" + suffix, encoding="utf-8")
            policy.write_text(json.dumps(self.policy), encoding="utf-8")
            runtime.prepare_file(credential, output, policy)
            self.assertTrue(output.read_text().startswith(prefix))
            self.assertTrue(output.read_text().endswith(suffix))

    def test_runtime_yaml_block_flow_and_missing_rules(self):
        documents = [
            "proxies: [{name: PROXY}]\nrules:\n- 'MATCH,PROXY'\n",
            "proxies: [{name: PROXY}]\nrules:\n  - 'MATCH,PROXY'\n...\n",
            "{proxies: [{name: PROXY}], rules: ['MATCH,PROXY']}\n",
            "proxies: [{name: PROXY}]\n...\n",
            "{proxies: [{name: PROXY}]}\n",
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / "credential.yaml"
            output = root / "config.yaml"
            policy = root / "policy.json"
            policy.write_text(json.dumps(self.policy), encoding="utf-8")
            for text in documents:
                with self.subTest(text=text):
                    credential.write_text(text, encoding="utf-8")
                    runtime.prepare_file(credential, output, policy)
                    self.assertEqual(
                        yaml.safe_load(output.read_text()),
                        runtime.prepare_policy(yaml.safe_load(text), self.policy),
                    )

    def test_same_file_and_nonprivate_directory_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                runtime.prepare_file(root / "config", root / "config", root / "policy")
            os.chmod(root, 0o755)
            with self.assertRaises(ValueError):
                runtime.prepare_file(
                    root / "credential", root / "config", root / "policy"
                )


if __name__ == "__main__":
    unittest.main()
