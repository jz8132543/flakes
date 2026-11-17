import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

source = Path(os.environ["MIGRATION_SOURCE"])
spec = importlib.util.spec_from_file_location("migration", source)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class FakeDconf:
    def __init__(self, values):
        self.values = values.copy()
        self.written = []

    def read(self, key):
        return self.values.get(key)

    def set(self, key, value):
        self.values[key] = value
        self.written.append(key)


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name) / "home"
        self.home.mkdir()

    def file(self, name, content):
        target = self.home / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return target

    def test_absent_and_default_dry_run_do_not_write_state(self):
        result = migration.Migration(self.home).run()
        self.assertEqual(result["removed"], [])
        self.assertEqual(result["settings"], [])
        path = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        result = migration.Migration(self.home).run()
        self.assertIn(str(path), result["settings"])
        self.assertIn("MacTahoeLiquidKde", path.read_text())
        self.assertFalse((self.home / ".local/state").exists())
        self.assertIsNone(result["backup"])

    def test_cli_dry_run_is_default_and_obeys_xdg_state_home(self):
        self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        state = self.home / "custom-state"
        environment = {**os.environ, "HOME": str(self.home), "XDG_STATE_HOME": str(state),
                       "XDG_CONFIG_HOME": str(self.home / ".config"),
                       "XDG_DATA_HOME": str(self.home / ".local/share")}
        output = subprocess.check_output([sys.executable, "-B", source, "--home", self.home],
                                         env=environment, text=True)
        self.assertFalse(json.loads(output)["applied"])
        self.assertFalse(state.exists())
        output = subprocess.check_output([sys.executable, "-B", source, "--home", self.home, "--apply"],
                                         env=environment, text=True)
        self.assertTrue(Path(json.loads(output)["backup"]).is_relative_to(state))

    def test_assets_are_unlinked_without_touching_their_source(self):
        original = Path(self.directory.name) / "source"
        original.mkdir()
        (original / "data").write_text("unchanged upstream")
        link = self.home / ".themes/MacTahoeLiquidKde-Light"
        link.parent.mkdir()
        link.symlink_to(original, target_is_directory=True)
        preserved = self.file(".themes/MacTahoe-Light-solid/data", "new theme")
        result = migration.Migration(self.home, True).run()
        self.assertFalse(link.exists())
        self.assertEqual((original / "data").read_text(), "unchanged upstream")
        self.assertEqual(preserved.read_text(), "new theme")
        self.assertIn(str(link), result["removed"])
        self.assertIsNone(result["backup"])

    def test_explicit_namespaces_only_and_retired_sources_not_backed_up(self):
        source_path = self.file("macos-golden-gate-liquid-kde/private-source", "do not archive theme source")
        files = [self.file(name, "retain") for name in (
            "macos-golden-gate-liquid-kde-personal/notes", ".themes/MacMyTheme/data",
            ".themes/My-liquid-theme/data", ".local/share/kwin/effects/forceblur/data",
            ".local/share/wallpapers/MacGoldenGate/personal.jpg",
            ".local/share/plasma/plasmoids/luisbocanegra.panel.colorizer/data",
        )]
        result = migration.Migration(self.home, True).run()
        self.assertFalse(source_path.exists())
        self.assertTrue(all(path.read_text() == "retain" for path in files))
        self.assertIsNone(result["backup"])

    def test_rime_credentials_launchers_shortcuts_and_unrelated_icons_preserved(self):
        files = [self.file(name, "private state") for name in (
            ".config/ibus/rime/user.yaml", ".local/share/keyrings/login.keyring",
            ".local/share/kwalletd/wallet", ".local/share/icons/hicolor/apps/nectarlink.png",
            ".mozilla/firefox/default/logins.json", ".local/share/applications/custom.desktop",
        )]
        shortcuts = self.file(".config/kglobalshortcutsrc", "[org.kde.mac.tahoe.liquid.globalmenu]\nshortcut=Meta+Space\n")
        result = migration.Migration(self.home, True).run()
        self.assertTrue(all(path.read_text() == "private state" for path in files))
        self.assertIn("Meta+Space", shortcuts.read_text())
        self.assertIn(str(shortcuts), [item["path"] for item in result["leftovers"]])

    def test_scoped_backup_and_rollback_preserve_unrelated_later_edits(self):
        path = self.file(".config/kwinrc", """[Wayland]
InputMethod=/etc/profiles/per-user/tippy/share/applications/plasma-ibus-wayland.desktop
[Xwayland]
Scale=1.25
[Private]
password=must-not-enter-backup
[org.kde.kdecoration2]
theme=__aurorae__svg__MacGoldenGateLiquidKde-Light
[Plugins]
liquidglassEnabled=true
blurEnabled=true
shapecornersEnabled=true
[Effect-liquidglass]
MaterialPreset=2
""")
        result = migration.Migration(self.home, True).run()
        text = path.read_text()
        for value in ("InputMethod=/etc/profiles", "Scale=1.25", "blurEnabled=true", "shapecornersEnabled=true"):
            self.assertIn(value, text)
        self.assertNotIn("theme=", text)
        self.assertNotIn("liquidglassEnabled", text)
        backup = Path(result["backup"])
        self.assertTrue(backup.is_relative_to(self.home / ".local/state/mactahoe/migration-backups"))
        saved = (backup / "changes.json").read_text()
        self.assertNotIn("must-not-enter-backup", saved)
        self.assertNotIn("InputMethod", saved)
        self.assertNotIn("Scale", saved)
        for directory in (backup, backup.parent, backup.parent.parent):
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((backup / "changes.json").stat().st_mode), 0o600)
        path.write_text(text.replace("Scale=1.25", "Scale=1.75"))
        migration.Migration(self.home).run(rollback=backup)
        self.assertNotIn("theme=", path.read_text())
        migration.Migration(self.home, True).run(rollback=backup)
        self.assertIn("theme=__aurorae__svg__MacGoldenGateLiquidKde-Light", path.read_text())
        self.assertIn("Scale=1.75", path.read_text())
        migration.Migration(self.home, True).run(rollback=backup)

    def test_widget_conversion_only_removes_presets_of_replaced_widget(self):
        path = self.file(".config/plasma-org.kde.plasma.desktop-appletsrc", """[Containments][47][Applets][49]
plugin=org.kde.mac.tahoe.liquid.icontasks
[Containments][47][Applets][49][Configuration][General]
launchers=applications:firefox.desktop,applications:org.kde.konsole.desktop
[Containments][47][Applets][48]
plugin=org.kde.mac-tahoe-liquid-kde.launcher
[Containments][47][Applets][48][Configuration][General]
launcherPreset=2
[Containments][28][Applets][31]
plugin=org.kde.plasma.systemtray
[Containments][28][Applets][31][Configuration][General]
knownItems=network,ibus
launcherPreset=retain
[ScreenMapping]
items=0
""")
        migration.Migration(self.home, True).run()
        text = path.read_text()
        for value in ("plugin=org.kde.plasma.icontasks", "plugin=org.kde.plasma.kickoff",
                      "launchers=applications:firefox.desktop,applications:org.kde.konsole.desktop",
                      "knownItems=network,ibus", "[ScreenMapping]\nitems=0", "launcherPreset=retain"):
            self.assertIn(value, text)
        self.assertNotIn("launcherPreset=2", text)

    def test_shared_scripts_launchers_and_mixed_css_are_reported_not_erased(self):
        payload = self.file(".local/share/plasma-manager/data/desktop_script_panels.js",
                            "const theme = 'MacTahoeLiquidKde-Light';\nuserPanelSettings();\n")
        trigger = self.file(".config/autostart/plasma-manager-autostart.desktop",
                            "Exec=/home/tippy/mac-tahoe-liquid-kde/run_all.sh --user-custom-argument\n")
        css = self.file(".config/gtk-4.0/gtk.css", '@import url("MacTahoeLiquidKde-Light/gtk.css"); .custom {color: red;}\n')
        result = migration.Migration(self.home, True).run()
        self.assertTrue(all(path.exists() for path in (payload, trigger, css)))
        self.assertTrue({str(payload), str(trigger), str(css)} <= {item["path"] for item in result["leftovers"]})

    def test_css_import_and_kvantum_key_only_are_backed_up(self):
        old_import = '@import url("/old/MacTahoeLiquidKde-Light/gtk.css");\n'
        custom = '/* mactahoe managed import */ @import url("mactahoe.css");\n.custom {color: red;}\n'
        css = self.file(".config/gtk-4.0/gtk.css", old_import + custom)
        kvantum = self.file(".config/Kvantum/kvantum.kvconfig", "[General]\ntheme=mac-tahoe-liquid-kdeDark\nsecret=unrelated-private-value\n")
        result = migration.Migration(self.home, True).run()
        self.assertEqual(css.read_text(), custom)
        self.assertEqual(kvantum.read_text(), "[General]\nsecret=unrelated-private-value\n")
        backup = Path(result["backup"])
        self.assertNotIn("unrelated-private-value", (backup / "changes.json").read_text())
        self.assertNotIn(".custom", (backup / "changes.json").read_text())
        migration.Migration(self.home, True).run(rollback=backup)
        self.assertEqual(css.read_text(), old_import + custom)

    def test_namespace_prefixes_and_unrelated_crlf_bytes_are_preserved(self):
        untouched = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light-personal\n")
        path = self.file(".config/kdeglobals", "")
        original = b"[General]\r\nColorScheme=MacTahoeLiquidKdeDark\r\n[Private]\r\npassword=keep\r\n"
        path.write_bytes(original)
        result = migration.Migration(self.home, True).run()
        self.assertEqual(path.read_bytes(), b"[General]\r\n[Private]\r\npassword=keep\r\n")
        self.assertIn("MacTahoeLiquidKde-Light-personal", untouched.read_text())
        migration.Migration(self.home, True).run(rollback=result["backup"])
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(migration.old_text("/user/mac-tahoe-liquid-kde-personal/gtk.css"))
        self.assertTrue(migration.old_text("/nix/store/" + "a" * 32 + "-mac-tahoe-liquid-kde-1.0/plugins"))

    def test_rollback_css_preserves_charset_order(self):
        css = self.file(".config/gtk-4.0/gtk.css", '@charset "UTF-8";\n@import url("/old/MacTahoeLiquidKde-Light/gtk.css");\n.custom {}\n')
        original = css.read_text()
        result = migration.Migration(self.home, True).run()
        migration.Migration(self.home, True).run(rollback=result["backup"])
        self.assertEqual(css.read_text(), original)

    def test_explicit_fixture_home_never_uses_another_homes_xdg_environment(self):
        external = Path(self.directory.name) / "other-home"
        external.mkdir()
        config = external / "config"
        config.mkdir()
        private = config / "plasmarc"
        private.write_text("[Theme]\nname=MacTahoeLiquidKde-Light\n")
        fixture = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Dark\n")
        environment = {**os.environ, "HOME": str(external), "XDG_CONFIG_HOME": str(config),
                       "XDG_STATE_HOME": str(external / "state"), "XDG_DATA_HOME": str(external / "data")}
        subprocess.check_output([sys.executable, "-B", source, "--home", self.home, "--apply"],
                                env=environment, text=True)
        self.assertNotIn("MacTahoeLiquidKde", fixture.read_text())
        self.assertIn("MacTahoeLiquidKde", private.read_text())
        self.assertFalse((external / "state").exists())

    def test_dconf_backup_is_allowlisted_and_rollback_preserves_other_preferences(self):
        theme = "/org/gnome/desktop/interface/gtk-theme"
        private = "/org/example/credentials"
        backend = FakeDconf({theme: "'MacTahoeLiquidKde-Light'", private: "do-not-back-up"})
        result = migration.Migration(self.home, dconf=backend).run()
        self.assertIn("dconf:" + theme, result["settings"])
        self.assertEqual(backend.written, [])
        result = migration.Migration(self.home, True, dconf=backend).run()
        backup = Path(result["backup"])
        self.assertIsNone(backend.read(theme))
        self.assertNotIn("do-not-back-up", (backup / "changes.json").read_text())
        backend.values[private] = "new private value"
        migration.Migration(self.home, True, dconf=backend).run(rollback=backup)
        self.assertEqual(backend.read(theme), "'MacTahoeLiquidKde-Light'")
        self.assertEqual(backend.read(private), "new private value")

    def test_parent_symlink_never_crossed_and_shared_leaf_symlink_preserved(self):
        external = Path(self.directory.name) / "external"
        external.mkdir()
        old = external / "MacTahoeLiquidKde-Light"
        old.mkdir()
        (old / "keep").write_text("external source")
        (self.home / ".themes").symlink_to(external, target_is_directory=True)
        source_config = external / "config"
        source_config.write_text("[Theme]\nname=MacTahoeLiquidKde-Light\n")
        (self.home / ".config").mkdir()
        config = self.home / ".config/plasmarc"
        config.symlink_to(source_config)
        result = migration.Migration(self.home, True).run()
        self.assertTrue((old / "keep").exists())
        self.assertTrue(config.is_symlink())
        self.assertIn("MacTahoeLiquidKde", source_config.read_text())
        self.assertTrue(result["deferred"])
        self.assertIsNone(result["backup"])

    def test_file_hardlink_is_not_replaced(self):
        path = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        other = self.home / "linked-config"
        os.link(path, other)
        result = migration.Migration(self.home, True).run()
        self.assertEqual(path.stat().st_ino, other.stat().st_ino)
        self.assertEqual(len(result["deferred"]), 1)

    def test_nested_directory_symlink_never_deletes_external_data(self):
        external = Path(self.directory.name) / "private"
        external.mkdir()
        protected = external / "credentials"
        protected.write_text("private")
        retired = self.home / ".themes/MacTahoeLiquidKde-Light"
        retired.mkdir(parents=True)
        (retired / "linked-directory").symlink_to(external, target_is_directory=True)
        migration.Migration(self.home, True).run()
        self.assertFalse(retired.exists())
        self.assertEqual(protected.read_text(), "private")

    def test_runtime_failure_retains_recoverable_private_journal(self):
        theme = "/org/gnome/desktop/interface/gtk-theme"
        backend = FakeDconf({theme: "'MacTahoeLiquidKde-Light'"})
        path = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        engine = migration.Migration(self.home, True, dconf=backend)
        with patch.object(backend, "set", side_effect=OSError("simulated dconf write failure")):
            with self.assertRaises(OSError):
                engine.run()
        self.assertTrue((engine.backup / "changes.json").is_file())
        self.assertNotIn("MacTahoeLiquidKde", path.read_text())
        migration.Migration(self.home, True, dconf=backend).run(rollback=engine.backup)
        self.assertIn("MacTahoeLiquidKde", path.read_text())
        lock = self.home / ".local/state/mactahoe/appearance.lock"
        self.assertEqual(stat.S_IMODE(lock.stat().st_mode), 0o600)

    def test_persistent_file_mount_and_nested_bind_mount_refused(self):
        config = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        asset = self.file("macos-tahoe-liquid-kde/persistent-bind-file", "persistent private data")
        old = self.file(".themes/MacTahoeLiquidKde-Light/nested/keep", "keep")
        # Mock mountinfo, not just st_dev: same-filesystem bind mounts must count.
        with patch.object(migration, "mount_points", return_value={config, asset, old.parent}):
            result = migration.Migration(self.home, True).run()
        self.assertEqual(result["removed"], [])
        self.assertEqual(result["settings"], [])
        self.assertTrue(all(path.exists() for path in (config, asset, old)))
        self.assertEqual(len(result["deferred"]), 3)

    def test_persisted_parent_directory_is_allowed_without_removing_mount(self):
        path = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        state = self.home / ".local/state/mactahoe"
        with patch.object(migration, "mount_points", return_value={path.parent, state}):
            result = migration.Migration(self.home, True).run()
        self.assertNotIn("MacTahoeLiquidKde", path.read_text())
        self.assertTrue(path.parent.is_dir())
        self.assertTrue(Path(result["backup"]).is_relative_to(state))

    def test_mount_appearing_after_plan_is_refused(self):
        path = self.file(".themes/MacTahoeLiquidKde-Light/keep", "keep").parent
        with patch.object(migration, "mount_points", side_effect=[set(), {path}]):
            result = migration.Migration(self.home, True).run()
        self.assertTrue(path.is_dir())
        self.assertEqual(result["removed"], [])

    def test_symlinked_state_or_backup_refuses_before_shared_mutation(self):
        path = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        state = self.home / ".local/state/mactahoe"
        state.parent.mkdir(parents=True)
        state.symlink_to(self.home / "elsewhere")
        with self.assertRaises(ValueError):
            migration.Migration(self.home, True).run()
        self.assertIn("MacTahoeLiquidKde", path.read_text())
        self.assertFalse((self.home / "elsewhere").exists())
        state.unlink()
        state.mkdir()
        (state / "migration-backups").symlink_to(self.home)
        with self.assertRaises(ValueError):
            migration.Migration(self.home, True).run()
        self.assertIn("MacTahoeLiquidKde", path.read_text())

    def test_rollback_conflict_preflight_does_not_change_other_files(self):
        first = self.file(".config/kwinrc", "[Plugins]\nliquidglassEnabled=true\n")
        second = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        result = migration.Migration(self.home, True).run()
        second.write_text("[Theme]\nname=MyNewTheme\n")
        with self.assertRaises(ValueError):
            migration.Migration(self.home, True).run(rollback=result["backup"])
        self.assertNotIn("liquidglassEnabled", first.read_text())
        self.assertIn("MyNewTheme", second.read_text())

    def test_assets_only_and_partial_repeat(self):
        path = self.file(".config/plasmarc", "[Theme]\nname=MacTahoeLiquidKde-Light\n")
        asset = self.file(".themes/MacTahoeLiquidKde-Dark/data", "retired")
        migration.Migration(self.home, True, assets_only=True).run()
        self.assertFalse(asset.exists())
        self.assertIn("MacTahoeLiquidKde", path.read_text())
        migration.Migration(self.home, True).run()
        result = migration.Migration(self.home, True).run()
        self.assertEqual(result["removed"], [])
        self.assertEqual(result["settings"], [])
        self.assertIsNone(result["backup"])


if __name__ == "__main__":
    unittest.main()
