import json
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


class LocalProvidersTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(os.environ["LOCAL_WEBUI_CONFIG"])
        cls.environment = cls.config["environment"]
        cls.script = cls.config["preStart"].split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]

    def synchronize(self, directory):
        with patch.dict(os.environ, self.environment | {"DATA_DIR": str(directory)}):
            exec(compile(self.script, "open-webui-preStart", "exec"), {})

    def test_separate_loopback_providers(self):
        self.assertEqual(self.config["host"], "127.0.0.1")
        self.assertEqual(
            self.environment["OPENAI_API_BASE_URLS"].split(";"),
            [
                f"http://127.0.0.1:{self.config['strataPort']}/v1",
                f"http://127.0.0.1:{self.config['swapPort']}/v1",
            ],
        )
        self.assertEqual(len(self.environment["OPENAI_API_KEYS"].split(";")), 2)
        self.assertEqual(self.environment["ENABLE_OPENAI_API"], "True")
        self.assertNotEqual(self.environment.get("ENABLE_PERSISTENT_CONFIG"), "False")
        self.assertNotEqual(self.environment.get("RESET_CONFIG_ON_START"), "True")

    def test_existing_state_and_idempotency(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "webui.db"
            with sqlite3.connect(database) as connection:
                connection.executescript(
                    "CREATE TABLE config (key TEXT PRIMARY KEY, value JSON NOT NULL, updated_at BIGINT);"
                    "CREATE TABLE chat (id TEXT PRIMARY KEY, content TEXT);"
                    "INSERT INTO chat VALUES ('existing-chat', 'preserve this conversation');"
                )
                connection.executemany(
                    "INSERT INTO config VALUES (?, ?, 42)",
                    [
                        ("openai.api_base_urls", '["http://127.0.0.1:8080/v1"]'),
                        ("openai.api_configs", '{"0":{"model_ids":["old-model"]}}'),
                        ("ui.name", '"Existing UI"'),
                        ("auth.enable_signup", "false"),
                    ],
                )
            self.synchronize(directory)
            with sqlite3.connect(database) as connection:
                first = dict(connection.execute("SELECT key, value FROM config"))
                timestamps = list(connection.execute("SELECT key, updated_at FROM config ORDER BY key"))
                self.assertEqual(first["ui.name"], '"Existing UI"')
                self.assertEqual(first["auth.enable_signup"], "false")
                self.assertEqual(json.loads(first["openai.api_configs"]), {})
                self.assertEqual(json.loads(first["openai.enable"]), True)
                self.assertEqual(
                    json.loads(first["openai.api_base_urls"]),
                    self.environment["OPENAI_API_BASE_URLS"].split(";"),
                )
                self.assertEqual(
                    json.loads(first["openai.api_keys"]), self.environment["OPENAI_API_KEYS"].split(";")
                )
                self.assertEqual(
                    connection.execute("SELECT content FROM chat").fetchone()[0],
                    "preserve this conversation",
                )
                connection.execute("UPDATE config SET updated_at = 7 WHERE key LIKE 'openai.%'")
                timestamps = list(connection.execute("SELECT key, updated_at FROM config ORDER BY key"))
            self.synchronize(directory)
            with sqlite3.connect(database) as connection:
                self.assertEqual(first, dict(connection.execute("SELECT key, value FROM config")))
                self.assertEqual(
                    timestamps,
                    list(connection.execute("SELECT key, updated_at FROM config ORDER BY key")),
                )

    def test_fresh_install_does_not_create_database(self):
        with tempfile.TemporaryDirectory() as directory:
            self.synchronize(directory)
            self.assertFalse((Path(directory) / "webui.db").exists())

    def test_unknown_schema_fails_without_touching_data(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "webui.db"
            with sqlite3.connect(database) as connection:
                connection.executescript(
                    "CREATE TABLE unrelated (value TEXT);"
                    "INSERT INTO unrelated VALUES ('preserved');"
                )
            with self.assertRaises(sqlite3.OperationalError):
                self.synchronize(directory)
            with sqlite3.connect(database) as connection:
                self.assertEqual(
                    connection.execute("SELECT value FROM unrelated").fetchone()[0], "preserved"
                )


if __name__ == "__main__":
    unittest.main()
