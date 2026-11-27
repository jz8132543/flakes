import contextlib
import errno
import importlib.util
import io
import json
import multiprocessing
import os
from pathlib import Path
import socket
import stat
import tempfile
import unittest
from unittest.mock import patch

source = Path(os.environ.get("APPEARANCE_SOURCE", Path(__file__).resolve().parents[1] /
                            "home-manager/modules/desktop/mactahoe/appearance.py"))
spec = importlib.util.spec_from_file_location("mactahoe_appearance", source)
appearance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appearance)


class RecordedAppearance(appearance.Appearance):
    def __init__(self, manifest, home):
        super().__init__(manifest, home, {"HOME": str(home)})
        self.active = "GNOME"
        self.calls = []
        self.values = {}
        self.fail = None
        self.fail_once = True

    def desktop(self):
        return self.active

    def hdr(self):
        return False

    def run(self, tool, *args):
        self.calls.append((tool, *args))
        if self.fail and self.fail(tool, args):
            if self.fail_once:
                self.fail = None
            raise RuntimeError("Injected command failure")
        if tool == "gsettings":
            if args[0] == "--schemadir":
                args = args[2:]
            operation, schema, *rest = args
            path = "/" + schema.replace(".", "/") + "/"
            if operation == "writable":
                return "true"
            if operation == "list-keys":
                return "blur\ntheme\nclock-menu-position\nnotification-banner-position"
            key = rest[0]
            if operation == "get":
                return self.values.get(path + key, "[]" if key.endswith("extensions") else "'old-value'")
            if operation == "set":
                self.values[path + key] = rest[1]
                return ""
        if tool == "dconf":
            operation, path, *rest = args
            if operation == "read":
                return self.values.get(path, "")
            if operation == "write":
                self.values[path] = rest[0]
            if operation == "reset":
                self.values.pop(path, None)
            return ""
        raise AssertionError(f"Unexpected command {tool} {args}")


def toggles(manifest, root):
    with contextlib.redirect_stdout(io.StringIO()):
        runtime = appearance.Appearance(manifest, root, {"HOME": str(root)})
        for _ in range(5):
            runtime.apply("toggle", offline=True)


class AppearanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.manifest = {"variants": {}, "commands": {}, "extensions": [], "gnomeMajor": "51",
                         "conflictingExtensions": ["rounded@conflict", "desaturate@conflict"]}
        for effects in ("visual", "compatible"):
            self.manifest["variants"][effects] = {}
            for mode in ("light", "dark"):
                prefix = self.root / "store" / effects / mode
                prefix.mkdir(parents=True)
                variant = {
                    "gtkTheme": f"MacTahoe-Visual-{mode.title()}" if effects == "visual" else f"MacTahoe-{mode.title()}-solid",
                    "iconTheme": "MacTahoe-" + mode, "cursorTheme": "MacTahoe-" + mode + "-cursors",
                }
                for resource in ("gtk3", "gtk4", "shell", "wallpaper", "icons", "cursor"):
                    path = prefix / resource
                    path.write_text("fixture " + effects + " " + mode)
                    variant[resource] = str(path)
                leaf = prefix / "gtk4-leaf.css"
                leaf.write_text('@import url("' + variant["gtk4"] + '");\n')
                variant["gtk4Leaf"] = str(leaf)
                self.manifest["variants"][effects][mode] = variant
        for role in ("user-theme", "blur", "appindicator", "perfection", "magic-lamp", "functional-kimpanel"):
            metadata = self.root / (role + ".json")
            uuid = role + "@test"
            metadata.write_text(json.dumps({"uuid": uuid, "shell-version": ["51"]}))
            self.manifest["extensions"].append({"role": role, "uuid": uuid, "metadata": str(metadata), "schemas": []})
        self.subject = RecordedAppearance(self.manifest, self.home)
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        stdout = contextlib.redirect_stdout(self.stdout)
        stderr = contextlib.redirect_stderr(self.stderr)
        stdout.__enter__()
        stderr.__enter__()
        self.addCleanup(stdout.__exit__, None, None, None)
        self.addCleanup(stderr.__exit__, None, None, None)

    def apply(self, command="apply", effect=None, offline=False):
        return self.subject.apply(command, effect, offline)

    def state(self):
        return json.loads(self.subject.state_file.read_text())

    def test_four_combinations_and_independent_dimensions(self):
        for mode in ("light", "dark"):
            for effects in ("visual", "compatible"):
                with self.subTest(mode=mode, effects=effects):
                    self.apply(mode)
                    self.apply("effects", effects)
                    variant = self.manifest["variants"][effects][mode]
                    self.assertEqual(self.state(), {"appearance": mode, "effects": effects})
                    self.assertEqual(os.readlink(self.subject.config / "gtk-4.0/mactahoe.css"), variant["gtk4Leaf"])
                    self.assertIn(variant["gtk4"], Path(variant["gtk4Leaf"]).read_text())
                    self.assertIn("gtk-theme-name=" + variant["gtkTheme"], (self.subject.config / "gtk-3.0/settings.ini").read_text())
                    self.assertEqual(json.loads(self.subject.values["/org/gnome/desktop/background/picture-uri"]), Path(variant["wallpaper"]).as_uri())
                    enabled = json.loads(self.subject.values["/org/gnome/shell/enabled-extensions"])
                    self.assertEqual("appindicator@test" in enabled, effects == "compatible")

    def test_offline_saves_only_state_no_commands_or_config(self):
        self.subject.active = None
        self.apply("dark")
        self.apply("effects", "compatible")
        self.assertFalse(self.subject.config.exists())
        self.assertFalse(self.subject.calls)
        self.assertEqual(self.state(), {"appearance": "dark", "effects": "compatible"})

    def test_reactivation_recovers_only_existing_session_environment(self):
        runtime = self.root / "runtime"
        runtime.mkdir()
        self.subject.env['XDG_RUNTIME_DIR'] = str(runtime)
        with patch.object(self.subject, 'run') as command:
            self.subject.restore_session_environment()
            command.assert_not_called()
        with socket.socket(socket.AF_UNIX) as bus:
            bus.bind(str(runtime / 'bus'))
            with patch.object(self.subject, 'run', return_value='XDG_CURRENT_DESKTOP=GNOME\nWAYLAND_DISPLAY=wayland-0\nUNRELATED_SECRET=private\n') as command:
                self.subject.restore_session_environment()
                command.assert_called_once_with('systemctl', '--user', 'show-environment')
        self.assertEqual(self.subject.env['XDG_CURRENT_DESKTOP'], 'GNOME')
        self.assertEqual(self.subject.env['WAYLAND_DISPLAY'], 'wayland-0')
        self.assertNotIn('UNRELATED_SECRET', self.subject.env)
        self.assertFalse(self.subject.state_file.exists())

    def test_reactivation_refuses_a_symlinked_bus(self):
        runtime = self.root / "runtime"
        runtime.mkdir()
        self.subject.env['XDG_RUNTIME_DIR'] = str(runtime)
        with socket.socket(socket.AF_UNIX) as bus:
            bus.bind(str(runtime / 'actual-bus'))
            (runtime / 'bus').symlink_to(runtime / 'actual-bus')
            with patch.object(self.subject, 'run') as command:
                self.subject.restore_session_environment()
                command.assert_not_called()

    def test_offline_missing_resources_still_saves_preference(self):
        Path(self.manifest["variants"]["visual"]["dark"]["gtk4"]).unlink()
        self.apply("dark", offline=True)
        self.assertEqual(self.state()["appearance"], "dark")
        self.assertFalse(self.subject.calls)

    def test_default_and_permissions(self):
        self.apply(offline=True)
        self.assertEqual(self.state(), appearance.DEFAULT)
        for path, mode in ((self.subject.state_dir, 0o700), (self.subject.state_file, 0o600),
                           (self.subject.state_dir / "appearance.lock", 0o600)):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), mode)

    def test_parallel_toggles_are_serialized(self):
        self.apply(offline=True)
        workers = [multiprocessing.get_context("fork").Process(target=toggles, args=(self.manifest, self.home)) for _ in range(4)]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(10)
            self.assertFalse(worker.is_alive())
            self.assertEqual(worker.exitcode, 0)
        self.assertEqual(self.state(), appearance.DEFAULT)

    def test_login_and_reactivation_keep_preference(self):
        self.apply("dark", offline=True)
        self.apply("effects", "compatible", offline=True)
        self.apply()
        self.apply()
        self.assertEqual(self.state(), {"appearance": "dark", "effects": "compatible"})
        self.subject.active = None
        self.apply()
        self.assertEqual(self.state(), {"appearance": "dark", "effects": "compatible"})
        self.subject.active = "GNOME"
        self.apply()
        self.assertEqual(self.state(), {"appearance": "dark", "effects": "compatible"})

    def test_unknown_css_preserved_and_import_idempotent(self):
        css = self.subject.config / "gtk-4.0/gtk.css"
        css.parent.mkdir(parents=True)
        custom = "/* personal */\nwindow { color: red; }\n"
        css.write_text(custom)
        self.apply()
        self.apply("dark")
        self.apply()
        self.assertEqual(css.read_text(), appearance.CSS_IMPORT + custom)
        self.assertIn("Preserving additional user GTK4 CSS", self.stderr.getvalue())

    def test_unknown_leaf_refuses_before_mutation(self):
        leaf = self.subject.config / "gtk-4.0/mactahoe.css"
        leaf.parent.mkdir(parents=True)
        leaf.write_text("user CSS")
        with self.assertRaisesRegex(RuntimeError, "Unknown GTK4 leaf"):
            self.apply()
        self.assertEqual(leaf.read_text(), "user CSS")
        self.assertFalse(self.subject.calls)

    def test_unknown_css_symlink_is_not_followed_for_writing(self):
        css = self.subject.config / "gtk-4.0/gtk.css"
        css.parent.mkdir(parents=True)
        external = self.root / "personal.css"
        external.write_text("user styles")
        css.symlink_to(external)
        with self.assertRaisesRegex(RuntimeError, "Unknown user CSS symlink"):
            self.apply()
        self.assertTrue(css.is_symlink())
        self.assertEqual(external.read_text(), "user styles")
        self.assertFalse(self.subject.calls)

    def test_missing_resource_preflight_prevents_partial_apply(self):
        self.apply()
        old_state, old_values = self.state(), self.subject.values.copy()
        Path(self.manifest["variants"]["visual"]["dark"]["gtk4"]).unlink()
        with self.assertRaisesRegex(RuntimeError, "Missing declared resource"):
            self.apply("dark")
        self.assertEqual(self.state(), old_state)
        self.assertEqual(self.subject.values, old_values)

    def test_failure_restores_state_css_and_dconf(self):
        self.apply()
        files = {p: p.read_bytes() for p in self.subject.config.rglob("*") if p.is_file() and not p.is_symlink()}
        leaf = self.subject.config / "gtk-4.0/mactahoe.css"
        target, values, state = os.readlink(leaf), self.subject.values.copy(), self.state()
        self.subject.fail = lambda tool, args: tool == "gsettings" and "picture-uri-dark" in args
        with self.assertRaisesRegex(RuntimeError, "previous settings restored"):
            self.apply("dark")
        self.assertEqual(self.state(), state)
        self.assertEqual(self.subject.values, values)
        self.assertEqual(os.readlink(leaf), target)
        self.assertTrue(all(p.read_bytes() == data for p, data in files.items()))

    def test_state_commit_failure_rolls_back_desktop(self):
        self.apply()
        state, values = self.state(), self.subject.values.copy()
        atomic = appearance.atomic
        def failed_commit(path, *args, **kwargs):
            if path == self.subject.state_file:
                raise OSError("state disk full")
            return atomic(path, *args, **kwargs)
        with patch.object(appearance, "atomic", failed_commit), self.assertRaisesRegex(RuntimeError, "state disk full"):
            self.apply("dark")
        self.assertEqual(self.state(), state)
        self.assertEqual(self.subject.values, values)

    def test_rollback_failure_is_reported(self):
        self.apply()
        self.subject.fail_once = False
        self.subject.fail = lambda tool, args: tool == "dconf" and args[0] == "write" or tool == "gsettings" and "picture-uri-dark" in args
        with self.assertRaisesRegex(RuntimeError, "rollback incomplete"):
            self.apply("dark")

    def test_unrelated_extensions_and_input_method_preserved(self):
        self.subject.values["/org/gnome/shell/enabled-extensions"] = json.dumps(["user@custom", "functional-kimpanel@test", "appindicator@test", "rounded@conflict"])
        self.subject.values["/org/gnome/shell/disabled-extensions"] = json.dumps(["user@disabled"])
        for effects in ("visual", "compatible", "visual"):
            self.apply("effects", effects)
            enabled = json.loads(self.subject.values["/org/gnome/shell/enabled-extensions"])
            disabled = json.loads(self.subject.values["/org/gnome/shell/disabled-extensions"])
            self.assertEqual(enabled.count("user@custom"), 1)
            self.assertIn("functional-kimpanel@test", enabled)
            self.assertIn("user@disabled", disabled)
            self.assertNotIn("rounded@conflict", enabled)

    def test_respects_disabled_functional_extensions(self):
        self.subject.values["/org/gnome/shell/disabled-extensions"] = json.dumps(["functional-kimpanel@test"])
        self.apply()
        self.assertNotIn("functional-kimpanel@test", json.loads(self.subject.values["/org/gnome/shell/enabled-extensions"]))

    def test_incompatible_extensions_not_force_enabled(self):
        metadata = Path(self.manifest["extensions"][0]["metadata"])
        metadata.write_text(json.dumps({"uuid": "user-theme@test", "shell-version": ["50"]}))
        self.apply()
        self.assertNotIn("user-theme@test", json.loads(self.subject.values["/org/gnome/shell/enabled-extensions"]))
        self.assertIn("Not enabling", self.stderr.getvalue())
        self.assertNotIn("/org/gnome/shell/extensions/user-theme/name", self.subject.values)

    def test_reapply_is_idempotent_for_gsettings_and_css_leaf(self):
        self.apply()
        leaf = self.subject.config / "gtk-4.0/mactahoe.css"
        inode = leaf.lstat().st_ino
        self.subject.calls.clear()
        self.apply()
        self.assertEqual(leaf.lstat().st_ino, inode)
        self.assertFalse(any(call[0] == "gsettings" and "set" in call for call in self.subject.calls))

    def test_never_changes_launchers_or_shortcuts(self):
        self.subject.config.mkdir()
        paths = [self.subject.config / name for name in ("kglobalshortcutsrc", "plasma-org.kde.plasma.desktop-appletsrc")]
        for path in paths:
            path.write_text("personal launchers and shortcuts")
        self.apply()
        self.apply("dark")
        self.apply("effects", "compatible")
        self.assertTrue(all(path.read_text() == "personal launchers and shortcuts" for path in paths))

    def test_invalid_state_is_not_reset_to_defaults(self):
        self.apply(offline=True)
        self.subject.state_file.write_text('{"appearance":"wrong"}')
        with self.assertRaisesRegex(RuntimeError, "Invalid appearance state"):
            self.apply()
        self.assertEqual(self.subject.state_file.read_text(), '{"appearance":"wrong"}')

    def test_state_and_lock_symlinks_are_rejected(self):
        self.apply(offline=True)
        external = self.root / "external"
        external.write_text("never change")
        self.subject.state_file.unlink()
        self.subject.state_file.symlink_to(external)
        with self.assertRaisesRegex(RuntimeError, "symlinked appearance state"):
            self.apply()
        self.subject.state_file.unlink()
        lock = self.subject.state_dir / "appearance.lock"
        lock.unlink()
        lock.symlink_to(external)
        with self.assertRaises(OSError):
            self.apply()
        self.assertEqual(external.read_text(), "never change")

    def test_ini_preserves_comments_groups_and_other_keys(self):
        original = "# user comment\n[General]\nunchanged=yes\n[Other]\nkey=value\n"
        result = appearance.ini_value(original, "General", "theme", "MacTahoe-Dark-solid")
        self.assertIn("unchanged=yes\ntheme=MacTahoe-Dark-solid\n[Other]", result)
        self.assertIn("# user comment", result)
        self.assertEqual(appearance.ini_value(result, "General", "theme", "MacTahoe-Dark-solid"), result)

    def test_mounted_file_in_place_write_and_rollback(self):
        file = self.home / "mounted-configuration"
        file.write_text("old user configuration")
        inode = file.stat().st_ino
        tx = appearance.Transaction()
        with patch.object(appearance.os, "replace", side_effect=OSError(errno.EBUSY, "bind mount")):
            tx.write(file, "new")
            self.assertEqual(file.read_text(), "new")
            self.assertEqual(tx.rollback(), [])
        self.assertEqual(file.read_text(), "old user configuration")
        self.assertEqual(file.stat().st_ino, inode)

    def test_hdr_fallback_keeps_visual_preference_without_output_changes(self):
        for detected in (True, None):
            with patch.object(self.subject, "hdr", return_value=detected):
                self.apply()
            self.assertEqual(self.state()["effects"], "visual")
            self.assertIn("MacTahoe-Light-solid", (self.subject.config / "gtk-3.0/settings.ini").read_text())
            self.assertIn("retaining visual preference", self.stderr.getvalue())

    def test_offline_detection_and_no_bus_activation(self):
        runtime = appearance.Appearance(self.manifest, self.home, {"HOME": str(self.home)})
        with patch.object(runtime, "bus", side_effect=AssertionError("must not contact bus")):
            self.assertIsNone(runtime.desktop())
            for desktop in ("Umbriel:Noctalia", "KDE"):
                runtime.env.update({"XDG_CURRENT_DESKTOP": desktop, "WAYLAND_DISPLAY": "wayland-0", "DBUS_SESSION_BUS_ADDRESS": "test"})
                runtime.apply("dark")
                self.assertFalse(runtime.config.exists())
        runtime.env.update({"XDG_CURRENT_DESKTOP": "GNOME", "WAYLAND_DISPLAY": "wayland-0", "DBUS_SESSION_BUS_ADDRESS": "test"})
        with patch.object(runtime, "bus", return_value=True) as bus:
            self.assertEqual(runtime.desktop(), "GNOME")
            bus.assert_called_once_with("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                        "NameHasOwner", "s", ["org.gnome.Shell"])
        with patch.object(runtime, "run", return_value='{"data":[false]}') as run:
            self.assertIsNone(runtime.desktop())
            self.assertTrue(all("--auto-start=no" in call.args for call in run.call_args_list))


if __name__ == "__main__":
    unittest.main()
