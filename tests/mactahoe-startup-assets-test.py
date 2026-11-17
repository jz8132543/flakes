"""Validate declared assets and callbacks using Plymouth's real script interpreter.

Only Image/Sprite/Window and callback registration are mocked. No daemon, VT,
display manager, user config, or boot configuration is touched by these tests.
"""

import configparser
import ctypes
import os
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET


SOURCE = Path(os.environ.get(
    "STARTUP_SOURCE",
    Path(__file__).resolve().parents[1] / "nixos/modules/desktop/mactahoe/assets",
))
PACKAGE = os.environ.get("STARTUP_PACKAGE")
PLUGIN = os.environ.get("PLYMOUTH_PLUGIN")


class AssetTests(unittest.TestCase):
    def test_original_monochrome_mark_and_license(self):
        logo = ET.parse(SOURCE / "summit.svg").getroot()
        self.assertEqual(logo.attrib["viewBox"], "0 0 96 96")
        self.assertTrue(all(
            element.attrib.get("stroke", "#ffffff") == "#ffffff"
            for element in logo.iter()
        ))
        license_text = (SOURCE / "LICENSE").read_text()
        self.assertIn("MIT License", license_text)
        self.assertIn("2026 flakes contributors", license_text)

    def test_rounded_frame_and_readable_menu(self):
        frame = ET.parse(SOURCE / "selection.svg").getroot()
        rect = frame.find("{http://www.w3.org/2000/svg}rect")
        self.assertGreater(float(rect.attrib["rx"]), 0)
        theme = (SOURCE / "grub-theme.txt").read_text()
        self.assertIn('selected_item_pixmap_style = "selected_*.png"', theme)
        self.assertIn('id = "__timeout__"', theme)
        self.assertIn('font = "DejaVu Sans Regular 18"', theme)
        self.assertIn("e: edit   c: console", theme)

    def test_diagnostics_are_not_intercepted(self):
        script = (SOURCE / "mactahoe.script").read_text()
        self.assertNotIn("SetKeyboardInputFunction", script)
        self.assertIn("Esc: boot details", script)
        for callback in ("DisplayPassword", "DisplayQuestion", "DisplayMessage", "HideMessage"):
            self.assertIn(f"Plymouth.Set{callback}Function(", script)

    @unittest.skipUnless(PACKAGE, "STARTUP_PACKAGE required for built asset checks")
    def test_built_assets(self):
        root = Path(PACKAGE)
        plymouth = root / "share/plymouth/themes/mactahoe"
        grub = root / "share/grub/themes/mactahoe"
        conf = configparser.ConfigParser()
        conf.read(plymouth / "mactahoe.plymouth")
        self.assertEqual(conf["Plymouth Theme"]["ModuleName"], "script")
        self.assertEqual(Path(conf["script"]["ImageDir"]), plymouth)
        self.assertEqual(Path(conf["script"]["ScriptFile"]), plymouth / "mactahoe.script")
        self.assertEqual((plymouth / "mactahoe.script").read_bytes(), (SOURCE / "mactahoe.script").read_bytes())
        expected = [(plymouth / "logo.png", (96, 96)), (plymouth / "progress.png", (220, 4))]
        expected.append((grub / "background.png", (1920, 1080)))
        expected.extend((grub / f"selected_{part}.png", (9, 9)) for part in (
            "nw", "n", "ne", "w", "c", "e", "sw", "s", "se",
        ))
        for image, dimensions in expected:
            with self.subTest(image=image.name):
                data = image.read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(struct.unpack(">II", data[16:24]), dimensions)
        self.assertGreater((grub / "font.pf2").stat().st_size, 1024)
        for name in ("LICENSE", "WALLPAPER-LICENSE", "FONT-LICENSE"):
            self.assertTrue((root / "share/doc/mactahoe-startup" / name).is_file())
        self.assertIn("Bitstream Vera Fonts Copyright", (
            root / "share/doc/mactahoe-startup/FONT-LICENSE"
        ).read_text())


class ScriptReturn(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("object", ctypes.c_void_p)]


@unittest.skipUnless(PLUGIN, "PLYMOUTH_PLUGIN required for native interpreter checks")
class NativeScriptTests(unittest.TestCase):
    def setUp(self):
        self.lib = ctypes.CDLL(PLUGIN)
        signatures = {
            "script_state_new": ([ctypes.c_void_p], ctypes.c_void_p),
            "script_state_destroy": ([ctypes.c_void_p], None),
            "script_parse_string": ([ctypes.c_char_p, ctypes.c_char_p], ctypes.c_void_p),
            "script_parse_op_free": ([ctypes.c_void_p], None),
            "script_execute": ([ctypes.c_void_p, ctypes.c_void_p], ScriptReturn),
            "script_obj_unref": ([ctypes.c_void_p], None),
            "script_obj_as_bool": ([ctypes.c_void_p], ctypes.c_bool),
            "script_lib_math_setup": ([ctypes.c_void_p], ctypes.c_void_p),
            "script_lib_math_destroy": ([ctypes.c_void_p], None),
        }
        for name, (args, result) in signatures.items():
            fn = getattr(self.lib, name)
            fn.argtypes, fn.restype = args, result
        self.state = self.lib.script_state_new(None)
        self.ops = []
        self.math = self.lib.script_lib_math_setup(self.state)
        self.execute('''
            Window.width = 1024; Window.height = 768;
            Window.GetX = fun() { return 0; };
            Window.GetY = fun() { return 0; };
            Window.GetWidth = fun() { return Window.width; };
            Window.GetHeight = fun() { return Window.height; };
            Window.SetBackgroundTopColor = fun(r, g, b) {};
            Window.SetBackgroundBottomColor = fun(r, g, b) {};
            fun mock_image(width, height) {
                value = []; value.width = width; value.height = height;
                return value | Image;
            }
            Image.GetWidth = fun() { return this.width; };
            Image.GetHeight = fun() { return this.height; };
            Image.Scale = fun(width, height) { return mock_image(width, height); };
            Image.Text = fun(text, r, g, b, a, font) {
                value = mock_image(300, 20); value.text = text; return value;
            };
            Image |= fun(name) {
                if (name == "progress.png") return mock_image(220, 4);
                return mock_image(96, 96);
            };
            Sprite.SetImage = fun(image) { this.image = image; };
            Sprite.SetPosition = fun(x, y, z) { this.x = x; this.y = y; this.z = z; };
            Sprite.SetOpacity = fun(value) { this.opacity = value; };
            Sprite |= fun(image) {
                value = []; value.image = image; value.opacity = 1;
                return value | Sprite;
            };
        ''')
        for name, callback in (
            ("Refresh", "refresh"), ("BootProgress", "progress"),
            ("DisplayNormal", "normal"), ("DisplayPassword", "password"),
            ("DisplayQuestion", "question"), ("DisplayMessage", "message"),
            ("HideMessage", "hide_message"), ("Quit", "quit"),
        ):
            # Native Plymouth invokes callbacks with no `this` object. Global
            # function names preserve that scope, unlike callbacks.member().
            self.execute(f"Plymouth.Set{name}Function = fun(f) {{ global.on_{callback} = f; }};")
        self.execute((SOURCE / "mactahoe.script").read_text())

    def tearDown(self):
        self.lib.script_state_destroy(self.state)
        self.lib.script_lib_math_destroy(self.math)
        for op in reversed(self.ops):
            self.lib.script_parse_op_free(op)

    def execute(self, source, expect_true=False):
        op = self.lib.script_parse_string(source.encode(), b"mactahoe-test")
        self.assertTrue(op, "native Plymouth parser rejected script")
        self.ops.append(op)
        result = self.lib.script_execute(self.state, op)
        self.assertIn(result.type, (0, 1), "native Plymouth execution failed")
        try:
            if expect_true:
                self.assertTrue(self.lib.script_obj_as_bool(result.object), source)
        finally:
            if result.object:
                self.lib.script_obj_unref(result.object)

    def test_progress_is_bounded_monotonic_and_visible(self):
        self.execute('''
            on_progress(1, -1);
            return progress == 0 && bar.fill.opacity == 0;
        ''', True)
        self.execute('''
            on_progress(2, 0.5); on_progress(3, 0.2);
            return progress == 0.5 && bar.fill.image.GetWidth() == 110 && bar.fill.opacity == 1;
        ''', True)
        self.execute('on_progress(4, 2); return progress == 1 && bar.fill.image.GetWidth() == 220;', True)

    def test_password_question_error_and_normal_callbacks(self):
        self.execute('''
            on_password("Unlock disk", 3);
            return status == "password" && prompt.sprite.image.text == "Unlock disk"
              && entry.sprite.image.text == "[ *** ]";
        ''', True)
        self.execute('''
            on_message("Incorrect password"); on_progress(1, 1); on_refresh();
            return message.sprite.image.text == "Incorrect password" && message.sprite.opacity == 1
              && prompt.sprite.opacity == 1 && entry.sprite.opacity == 1;
        ''', True)
        self.execute('''
            on_hide_message("Unrelated message");
            return message.sprite.opacity == 1;
        ''', True)
        self.execute('''
            on_hide_message("Incorrect password"); on_question("Recovery option", "yes");
            return message.sprite.opacity == 0 && status == "question" && entry.sprite.image.text == "yes";
        ''', True)
        self.execute('''
            on_normal();
            return status == "normal" && entry.sprite.opacity == 0 && prompt.sprite.opacity == 0;
        ''', True)

    def test_refresh_repositions_logo_and_fades_without_hiding_errors(self):
        self.execute('''
            for (i = 0; i < 30; i++) on_refresh();
            return logo.sprite.opacity == 1 && logo.sprite.x == 464;
        ''', True)
        self.execute('''
            Window.width = 1920; Window.height = 1080; on_refresh();
            return logo.sprite.x == 912 && bar.fill.x == 850;
        ''', True)
        self.execute('''
            on_message("Disk failure"); on_progress(1, 1);
            for (i = 0; i < 30; i++) on_refresh();
            return logo.sprite.opacity == 0 && message.sprite.opacity == 1;
        ''', True)
        self.execute('on_quit(); return bar.track.opacity == 0 && bar.fill.opacity == 0;', True)


if __name__ == "__main__":
    unittest.main()
