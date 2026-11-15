import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "ctyun_dashboard_init",
    Path(__file__).with_name("init.py"),
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class InitializationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name) / "data"
        self.data.mkdir()
        self.password = Path(self.temp.name) / "password"
        self.password.write_text("test-password\n")
        self.config = self.data / "app_config.json"
        self.backup = self.data / "app_config.json.bak"

    def initialize(self):
        module.initialize(self.data, self.password)

    def test_fresh_admin_and_private_backup(self):
        self.initialize()
        config = json.loads(self.config.read_text())
        admin = config["users"][0]
        self.assertEqual(admin["username"], "i")
        self.assertEqual(admin["role"], "admin")
        self.assertEqual(
            admin["passwordHash"],
            hashlib.sha256(b"test-passwordctyun_salt_2026").hexdigest(),
        )
        self.assertFalse(config["settings"]["allowRegistration"])
        for candidate in (self.config, self.backup):
            self.assertEqual(json.loads(candidate.read_text()), config)
            self.assertEqual(candidate.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("test-password", candidate.read_text())

    def test_preserve_existing_i_without_reading_secret(self):
        original = json.dumps(
            {"users": [{"username": "i", "role": "admin", "passwordHash": "changed"}]}
        )
        self.config.write_text(original)
        self.password.unlink()
        self.initialize()
        self.assertEqual(self.config.read_text(), original)
        self.assertFalse(self.backup.exists())

    def test_add_i_to_backup_when_main_is_corrupt(self):
        self.config.write_text("corrupt")
        existing = {"username": "admin", "role": "admin", "passwordHash": "unchanged"}
        self.backup.write_text(json.dumps({"users": [existing]}))
        self.initialize()
        config = json.loads(self.config.read_text())
        self.assertEqual(len(config["users"]), 1)
        self.assertEqual(config["users"][0]["username"], "i")
        self.assertEqual(json.loads(self.backup.read_text()), config)

    def test_reject_corruption_without_overwriting_state(self):
        self.config.write_text("corrupt")
        with self.assertRaises(RuntimeError):
            self.initialize()
        self.assertEqual(self.config.read_text(), "corrupt")
        self.assertFalse(self.backup.exists())

    def test_preserve_existing_users_accounts_settings_and_keys(self):
        original = {
            "users": [
                {
                    "id": "u_root",
                    "username": "root",
                    "role": "admin",
                    "passwordHash": "changed",
                },
                {"id": "u_other", "username": "other", "role": "user"},
            ],
            "accounts": [
                {"id": "account", "ownerId": "u_root", "password": "encrypted"}
            ],
            "settings": {"allowRegistration": False, "keepAliveInterval": 120},
        }
        self.config.write_text(json.dumps(original))
        key = self.data / ".master.key"
        key.write_bytes(b"existing-key")
        self.initialize()
        updated = json.loads(self.config.read_text())
        self.assertEqual(updated["users"][:-1], original["users"])
        self.assertEqual(updated["users"][-1]["username"], "i")
        self.assertNotIn(
            updated["users"][-1]["id"], {u["id"] for u in original["users"]}
        )
        self.assertEqual(updated["accounts"], original["accounts"])
        self.assertEqual(updated["settings"], original["settings"])
        self.assertEqual(key.read_bytes(), b"existing-key")
        self.assertEqual(json.loads(self.backup.read_text()), updated)
        self.assertFalse(list(self.data.glob(".app_config-*")))

    def test_reject_invalid_user_list_without_overwriting_state(self):
        original = '{"users":null,"accounts":[{"id":"existing"}]}'
        self.config.write_text(original)
        with self.assertRaises(RuntimeError):
            self.initialize()
        self.assertEqual(self.config.read_text(), original)

    def test_reject_empty_and_default_passwords(self):
        for password in ("\n", "admin123\n"):
            with self.subTest(password=password):
                self.password.write_text(password)
                with self.assertRaises(ValueError):
                    self.initialize()
                self.assertFalse(self.config.exists())
                self.assertFalse(self.backup.exists())

    def test_restart_does_not_reset_password(self):
        self.initialize()
        original = self.config.read_text()
        self.password.write_text("replacement-secret")
        self.initialize()
        self.assertEqual(self.config.read_text(), original)

    def test_create_admin_i_when_only_regular_users_exist(self):
        existing = {"id": "u_other", "username": "other", "role": "user"}
        self.config.write_text(json.dumps({"users": [existing]}))
        self.initialize()
        users = json.loads(self.config.read_text())["users"]
        self.assertEqual(users[0], existing)
        self.assertEqual(users[1]["username"], "i")
        self.assertEqual(users[1]["role"], "admin")

    def test_failed_atomic_write_preserves_existing_config(self):
        original = '{"users":[{"username":"admin","role":"admin"}]}'
        self.config.write_text(original)
        with patch.object(module.os, "replace", side_effect=OSError("write failed")):
            with self.assertRaises(OSError):
                self.initialize()
        self.assertEqual(self.config.read_text(), original)
        self.assertFalse(self.backup.exists())
        self.assertFalse(list(self.data.glob(".app_config-*")))

    def test_remove_admin_transfer_accounts_and_revoke_its_sessions(self):
        administrator = {
            "id": "u_i",
            "username": "i",
            "role": "admin",
            "passwordHash": "unchanged",
        }
        other = {"id": "u_other", "username": "other", "role": "user"}
        original = {
            "users": [
                {"id": "u_admin", "username": "admin", "role": "admin"},
                administrator,
                other,
            ],
            "accounts": [
                {"id": "old", "ownerId": "u_admin", "password": "encrypted"},
                {"id": "other", "ownerId": "u_other"},
            ],
            "settings": {"allowRegistration": False},
        }
        self.config.write_text(json.dumps(original))
        sessions_file = self.data / "auth_sessions.json"
        sessions = {
            "old-token": {"userId": "u_admin"},
            "i-token": {"userId": "u_i"},
            "other-token": {"userId": "u_other"},
        }
        sessions_file.write_text(json.dumps(sessions))
        self.password.unlink()
        self.initialize()
        updated = json.loads(self.config.read_text())
        self.assertEqual(updated["users"], [administrator, other])
        self.assertEqual(
            updated["accounts"][0],
            {"id": "old", "ownerId": "u_i", "password": "encrypted"},
        )
        self.assertEqual(updated["accounts"][1], original["accounts"][1])
        self.assertEqual(updated["settings"], original["settings"])
        self.assertEqual(json.loads(self.backup.read_text()), updated)
        del sessions["old-token"]
        self.assertEqual(json.loads(sessions_file.read_text()), sessions)
        self.assertEqual(sessions_file.stat().st_mode & 0o777, 0o600)
        before_restart = self.config.read_text()
        self.initialize()
        self.assertEqual(self.config.read_text(), before_restart)

    def test_regular_i_must_not_remove_last_admin(self):
        original = {
            "users": [
                {"id": "u_admin", "username": "admin", "role": "admin"},
                {"id": "u_i", "username": "i", "role": "user"},
            ]
        }
        self.config.write_text(json.dumps(original))
        with self.assertRaises(RuntimeError):
            self.initialize()
        self.assertEqual(json.loads(self.config.read_text()), original)
        self.assertFalse(self.backup.exists())

    def test_invalid_sessions_do_not_modify_users(self):
        original = {
            "users": [
                {"id": "u_admin", "username": "admin", "role": "admin"},
                {"id": "u_i", "username": "i", "role": "admin"},
            ]
        }
        self.config.write_text(json.dumps(original))
        sessions_file = self.data / "auth_sessions.json"
        sessions_file.write_text("corrupt")
        with self.assertRaises(ValueError):
            self.initialize()
        self.assertEqual(json.loads(self.config.read_text()), original)
        self.assertEqual(sessions_file.read_text(), "corrupt")


if __name__ == "__main__":
    unittest.main()
