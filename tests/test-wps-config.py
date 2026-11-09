#!/usr/bin/env python3
"""Run with WPS_CONFIG_SCRIPT pointing to pkgs.wpsoffice-cn.configureWps."""

import configparser
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class WpsConfigTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config_home = self.home / "custom-config"
        self.config = self.config_home / "Kingsoft" / "Office.conf"
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config_home))
        self.script = os.environ["WPS_CONFIG_SCRIPT"]

    def run_merge(self):
        result = subprocess.run([self.script], env=self.env, check=True, capture_output=True)
        self.assertEqual(result.stderr, b"")

    def seed(self, content):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_text(content)

    def assert_policy(self):
        settings = configparser.ConfigParser(interpolation=None)
        settings.optionxform = str
        settings.read(self.config)
        self.assertEqual(settings["General"]["languages"], "zh_CN")
        self.assertEqual(
            settings["6.0"][r"common\do_not_detect_file_association_while_startup"], "true"
        )
        self.assertNotIn("", settings)

    def test_missing_config(self):
        self.run_merge()
        self.assert_policy()
        self.assertFalse((self.home / ".config").exists())

    def test_default_xdg_path(self):
        self.env.pop("XDG_CONFIG_HOME")
        self.config = self.home / ".config" / "Kingsoft" / "Office.conf"
        self.run_merge()
        self.assert_policy()

    def test_replace_existing_policy(self):
        self.seed("[General]\nlanguages=en_US\n[6.0]\n"
                  "common\\do_not_detect_file_association_while_startup=false\n")
        self.run_merge()
        self.assert_policy()

    def test_preserve_user_settings_and_qt_values(self):
        original = (
            "; User comment\n[6.0]\n"
            'plugins\\custom="@ByteArray({\\"value\\":\\"100%\\"})"\n'
            "wps\\RecentFiles\\files\\1\\FileName=/tmp/document.docx\n"
            "[kdcsdk]\nNotFirstOpen=true\n"
            "[UnixUpdateInfo]\nUserRejectUpdateVersion=12.1.2.29183\n"
        )
        self.seed(original)
        self.run_merge()
        content = self.config.read_text()
        for line in original.splitlines():
            self.assertIn(line + "\n", content)
        self.assert_policy()

    def test_no_rewrite_when_unchanged(self):
        self.run_merge()
        before = self.config.read_bytes(), self.config.stat().st_mtime_ns, self.config.stat().st_ino
        self.run_merge()
        after = self.config.read_bytes(), self.config.stat().st_mtime_ns, self.config.stat().st_ino
        self.assertEqual(before, after)

    def test_preserve_file_mode(self):
        self.seed("[General]\nlanguages=en_US\n")
        self.config.chmod(0o600)
        self.run_merge()
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_duplicate_keys(self):
        self.seed("[General]\nlanguages=en_US\nlanguages=zh_TW\n")
        self.run_merge()
        self.assert_policy()
        self.assertEqual(self.config.read_text().count("languages="), 1)

    def test_concurrent_launches(self):
        processes = [subprocess.Popen([self.script], env=self.env) for _ in range(6)]
        for process in processes:
            self.assertEqual(process.wait(timeout=10), 0)
        self.assert_policy()
        self.assertFalse(list(self.config.parent.glob(".Office.conf.*")))


if __name__ == "__main__":
    unittest.main()
