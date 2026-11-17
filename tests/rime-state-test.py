import configparser
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RimeStateTest(unittest.TestCase):
    data = Path(os.environ["RIME_DATA"])
    subdir = Path(os.environ["RIME_SUBDIR"])

    def initialize(self, home):
        script = os.environ["RIME_INIT"].replace(os.environ["RIME_HOME"], str(home))
        subprocess.run(["bash", "-c", 'run() { "$@"; }\n' + script], check=True)

    def test_runtime_files_are_not_declarative(self):
        for name in ("user.yaml", "installation.yaml"):
            self.assertFalse((self.data / "share/rime-build" / name).exists())
            self.assertTrue((self.data / "share/rime-data" / name).is_file())
        self.assertFalse(list((self.data / "share/rime-build/build").glob("*.yaml")))
        self.assertTrue((self.data / "share/rime-data/build/wanxiang.schema.yaml").is_file())

    def test_first_login_creates_writable_state(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self.initialize(home)
            for name in ("user.yaml", "installation.yaml"):
                state = home / self.subdir / name
                self.assertFalse(state.is_symlink())
                self.assertTrue(state.stat().st_mode & 0o200)
                self.assertEqual(state.read_bytes(), (self.data / "share/rime-data" / name).read_bytes())

    def test_existing_learning_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self.initialize(home)
            rime = home / self.subdir
            for name in ("user.yaml", "installation.yaml", "wanxiang.userdb"):
                (rime / name).write_text("existing learned state\n")
            self.initialize(home)
            for name in ("user.yaml", "installation.yaml", "wanxiang.userdb"):
                self.assertEqual((rime / name).read_text(), "existing learned state\n")

    def test_runtime_with_home_manager_links(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            rime = home / self.subdir
            source = self.data / "share/rime-build"
            for path in source.rglob("*"):
                target = rime / path.relative_to(source)
                if path.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.symlink_to(path)
            self.initialize(home)
            for _ in range(2):
                result = subprocess.run(
                    [os.environ["RIME_SMOKE"], str(self.data / "share/rime-data"),
                     str(rime), "fcitx-rime" if os.environ.get("FCITX_CONFIG") else "ibus-rime"],
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("failed to save config", result.stderr)

    def test_compiled_cache_is_refreshed_without_touching_learning(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            build = home / self.subdir / "build"
            build.mkdir(parents=True)
            schema = build / "wanxiang.schema.yaml"
            source = self.data / "share/rime-data/build/wanxiang.schema.yaml"
            schema.symlink_to(source)
            learned = build / "tips.userdb"
            learned.mkdir()
            (learned / "data").write_text("learned state\n")
            for _ in range(2):
                self.initialize(home)
                self.assertFalse(schema.is_symlink())
                self.assertTrue(schema.stat().st_mode & 0o200)
                self.assertEqual(schema.read_bytes(), source.read_bytes())
                self.assertEqual((learned / "data").read_text(), "learned state\n")
                schema.write_text("stale generated cache\n")

    @unittest.skipUnless(os.environ.get("FCITX_CONFIG"), "Fcitx-specific migration")
    def test_legacy_store_links_become_writable(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            rime = home / self.subdir
            rime.mkdir(parents=True)
            for name in ("user.yaml", "installation.yaml"):
                (rime / name).symlink_to(self.data / "share/rime-data" / name)
            self.initialize(home)
            for name in ("user.yaml", "installation.yaml"):
                state = rime / name
                self.assertFalse(state.is_symlink())
                self.assertTrue(state.stat().st_mode & 0o200)
                self.assertEqual(state.read_bytes(), (self.data / "share/rime-data" / name).read_bytes())

    @unittest.skipUnless(os.environ.get("FCITX_CONFIG"), "Fcitx-specific hotkeys")
    def test_shift_is_reserved_for_rime(self):
        config = configparser.ConfigParser()
        config.read(os.environ["FCITX_CONFIG"])
        self.assertEqual(config["Behavior"]["ActiveByDefault"], "True")
        self.assertEqual(config["Behavior"]["ShareInputState"], "All")
        self.assertEqual(dict(config["Hotkey/TriggerKeys"]), {"0": "Control+space"})
        self.assertEqual(dict(config["Hotkey/AltTriggerKeys"]), {})
        self.assertEqual(dict(config["Hotkey/EnumerateForwardKeys"]), {})
        profile = configparser.ConfigParser()
        profile.read(os.environ["FCITX_PROFILE"])
        self.assertEqual(profile["Groups/0"]["DefaultIM"], "rime")
        self.assertEqual(profile["Groups/0/Items/0"]["Name"], "keyboard-us")
        self.assertEqual(profile["Groups/0/Items/1"]["Name"], "rime")
        self.assertEqual(profile["Groups/1"]["DefaultIM"], "keyboard-us")
        import json
        chromium_args = json.loads(os.environ.get("CHROMIUM_ARGS", "[]"))
        self.assertIn("--enable-wayland-ime", chromium_args)
        self.assertIn("--wayland-text-input-version=3", chromium_args)
        self.assertNotIn("--gtk-version=4", chromium_args)
        self.assertTrue(any(arg.startswith("--enable-features=") and "WaylandWindowDecorations" in arg for arg in chromium_args))

    def test_konsole_defaults_to_english(self):
        config = (self.data / "share/rime-build/default.custom.yaml").read_text()
        self.assertIn('"konsole":\n      ascii_mode: true', config)
        self.assertIn('"org.kde.konsole":\n      ascii_mode: true', config)


if __name__ == "__main__":
    unittest.main()
