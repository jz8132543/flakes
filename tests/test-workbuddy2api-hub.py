import hashlib
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "nixos/modules/services/ai/gateway/workbuddy2api-hub-init.py"
)


class WorkBuddyCredentialsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.accounts = root / "accounts"
        self.key_file = root / "api-key"
        self.password_file = root / "password"
        self.key_file.write_text("sk-test-workbuddy-sops-key\n")
        self.password_file.write_text("test-panel-password\n")
        self.settings = self.accounts / "settings.json"

    def run_init(self, success=True):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(self.accounts),
                str(self.key_file),
                str(self.password_file),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode == 0, success, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertNotIn(self.key_file.read_text().strip(), result.stderr)
        return json.loads(self.settings.read_text()) if success else None

    def test_first_start_and_idempotence(self):
        data = self.run_init()
        self.assertEqual(data["api_keys"][0]["key"], "sk-test-workbuddy-sops-key")
        self.assertTrue(data["api_keys"][0]["enabled"])
        self.assertFalse(data["auth_disabled"])
        self.assertFalse(data["panel_password_default"])
        self.assertEqual(
            data["panel_password_hash"],
            hashlib.pbkdf2_hmac(
                "sha256",
                b"test-panel-password",
                bytes.fromhex(data["panel_password_salt"]),
                data["panel_password_rounds"],
            ).hex(),
        )
        self.assertNotIn("test-panel-password", self.settings.read_text())
        self.assertEqual(stat.S_IMODE(self.settings.stat().st_mode), 0o600)
        self.assertEqual(self.run_init(), data)

    def test_rotation_preserves_dashboard_settings(self):
        data = self.run_init()
        custom_key = {"id": "custom", "key": "dashboard-key", "realm": "cn"}
        data["api_keys"].append(custom_key)
        data["auth_disabled"] = True
        data["schedule"] = {"checkin": [9]}
        self.settings.write_text(json.dumps(data))
        self.key_file.write_text("sk-test-workbuddy-rotated-key")
        self.password_file.write_text("rotated-panel-password")
        rotated = self.run_init()
        self.assertEqual(rotated["api_keys"][0]["key"], self.key_file.read_text())
        self.assertEqual(rotated["api_keys"][1], custom_key)
        self.assertEqual(rotated["schedule"], data["schedule"])
        self.assertFalse(rotated["auth_disabled"])
        self.assertNotEqual(rotated["panel_password_hash"], data["panel_password_hash"])
        self.assertEqual(len(rotated["api_keys"]), 2)

    def test_unsafe_credentials_do_not_overwrite_settings(self):
        self.run_init()
        original = self.settings.read_bytes()
        for key, password in [
            ("", "test-panel-password"),
            ("first-key\nsecond-key", "test-panel-password"),
            ("sk-valid-test-key", ""),
            ("sk-valid-test-key", "admin"),
        ]:
            with self.subTest(key=key, password=password):
                self.key_file.write_text(key)
                self.password_file.write_text(password)
                result = subprocess.run(
                    [
                        sys.executable,
                        str(SCRIPT),
                        str(self.accounts),
                        str(self.key_file),
                        str(self.password_file),
                    ],
                    capture_output=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.settings.read_bytes(), original)

    def test_corrupt_settings_are_not_reset(self):
        self.run_init()
        for contents in ["invalid json", "[]", '{"api_keys": {}}']:
            with self.subTest(contents=contents):
                self.settings.write_text(contents)
                self.run_init(success=False)
                self.assertEqual(self.settings.read_text(), contents)


if __name__ == "__main__":
    unittest.main()
