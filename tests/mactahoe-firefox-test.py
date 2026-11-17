import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

source = Path(os.environ["FIREFOX_SOURCE"])
spec = importlib.util.spec_from_file_location("firefox", source)
firefox = importlib.util.module_from_spec(spec)
spec.loader.exec_module(firefox)


class FirefoxTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name) / "home"
        self.root = self.home / ".mozilla/firefox"
        self.root.mkdir(parents=True)
        self.styles = self.home / ".local/share/mactahoe-firefox"
        self.styles.mkdir(parents=True)
        for name in ("userChrome.css", "userContent.css"):
            (self.styles / name).write_text(f'@import url("file:///nix/store/theme/{name}");\n')

    def profile(self, name="default", registered_path=None):
        path = self.root / name
        path.mkdir()
        (self.root / "profiles.ini").write_text(f"[Profile0]\nPath={registered_path or name}\nIsRelative=1\n")
        return path

    def connect(self, managed=()):
        return firefox.connect_profiles(self.home, ".mozilla/firefox", self.styles, managed)

    def test_missing_registry_never_creates_one(self):
        self.assertEqual(self.connect()["linked"], [])
        self.assertFalse((self.root / "profiles.ini").exists())

    def test_safe_import_repeat_preserves_registry_userjs_and_credentials(self):
        profile = self.profile()
        files = [profile / name for name in ("user.js", "prefs.js", "logins.json", "places.sqlite", "extensions.json")]
        for path in files:
            path.write_text("private user data")
        registry = self.root / "profiles.ini"
        before = registry.stat().st_mtime_ns, registry.read_bytes()
        result = self.connect()
        self.assertEqual(len(result["linked"]), 2)
        for name in ("userChrome.css", "userContent.css"):
            self.assertEqual(os.readlink(profile / "chrome" / name), str(self.styles / name))
        self.assertEqual(self.connect()["linked"], [])
        self.assertEqual((registry.stat().st_mtime_ns, registry.read_bytes()), before)
        self.assertTrue(all(path.read_text() == "private user data" for path in files))

    def test_unknown_css_kept_and_no_partial_import(self):
        profile = self.profile()
        chrome = profile / "chrome"
        chrome.mkdir()
        custom = chrome / "userChrome.css"
        custom.write_text("/* user's unknown CSS */")
        result = self.connect()
        self.assertIn(str(custom), result["preserved"])
        self.assertEqual(custom.read_text(), "/* user's unknown CSS */")
        self.assertFalse((chrome / "userContent.css").exists())

    def test_unknown_css_symlinks_are_preserved_even_when_broken(self):
        profile = self.profile()
        (profile / "chrome").mkdir()
        css = profile / "chrome/userChrome.css"
        css.symlink_to(self.home / "missing.css")
        result = self.connect()
        self.assertIn(str(css), result["preserved"])
        self.assertTrue(css.is_symlink())
        self.assertFalse((profile / "chrome/userContent.css").exists())

    def test_profile_and_chrome_parent_symlinks_are_not_followed(self):
        profile = self.profile()
        external = self.home / "external"
        external.mkdir()
        (profile / "chrome").symlink_to(external)
        self.assertTrue(self.connect()["preserved"])
        self.assertEqual(list(external.iterdir()), [])
        (profile / "chrome").unlink()
        profile.rmdir()
        profile.symlink_to(external)
        self.assertTrue(self.connect()["preserved"])
        self.assertEqual(list(external.iterdir()), [])

    def test_out_of_root_and_managed_profiles_not_modified(self):
        profile = self.profile(registered_path="../../outside")
        outside = self.home / "outside"
        outside.mkdir()
        self.assertTrue(self.connect()["preserved"])
        self.assertFalse((outside / "chrome").exists())
        (self.root / "profiles.ini").write_text("[Profile0]\nPath=default\nIsRelative=1\n")
        self.assertEqual(self.connect(managed=[profile])["linked"], [])
        self.assertFalse((profile / "chrome").exists())

    def test_symlinked_profile_root_and_invalid_registry_preserved(self):
        (self.root / "profiles.ini").write_text("not an ini file")
        self.assertTrue(self.connect()["preserved"])
        real = self.root.with_name("actual-firefox")
        self.root.rename(real)
        self.root.symlink_to(real)
        self.assertTrue(self.connect()["preserved"])

    def test_module_imports_existing_css_and_locks_light_colors(self):
        module = Path(os.environ["FIREFOX_MODULE_SOURCE"]).read_text()
        for key in ("layout.css.prefers-color-scheme.content-override", "browser.theme.content-theme",
                    "browser.theme.toolbar-theme"):
            self.assertIn(f'"{key}" = 1;', module)
            self.assertIn(f'"{key}"', module.split("lib.elem name [", 1)[1].split("]", 1)[0])
        self.assertRegex(module, r']\s*then\s*"locked"\s*else\s*"default";')
        self.assertIn("userChrome = lib.mkBefore chrome;", module)
        self.assertIn("userContent = lib.mkBefore content;", module)
        self.assertNotIn('"profiles.ini"', module)
        self.assertNotIn("programs.firefox.profiles = {", module)


if __name__ == "__main__":
    unittest.main()
