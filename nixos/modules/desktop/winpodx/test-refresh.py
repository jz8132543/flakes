"""Real-Qt refresh regression tests; run with the built WinPodX on PYTHONPATH.

No guest commands, discovery writes or visible windows are used. Testing a
small QObject mixin alone misses PySide's behavior on the full window class.
"""

import os
import tempfile
import threading
import time
import unittest
from contextlib import ExitStack
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QTimer, qInstallMessageHandler
from PySide6.QtWidgets import QApplication
from winpodx.core.app import AppInfo
from winpodx.core.config import Config
from winpodx.core.discovery import DiscoveryError
from winpodx.gui._main_window_apps import AppCrudMixin
from winpodx.gui.main_window import WinpodxWindow
from winpodx.gui.workers import sync_desktop_entries


class RefreshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        root = self.stack.enter_context(tempfile.TemporaryDirectory())
        self.stack.enter_context(patch.dict(os.environ, {
            "HOME": root, "XDG_CONFIG_HOME": root + "/config",
            "XDG_DATA_HOME": root + "/data", "XDG_STATE_HOME": root + "/state",
            "XDG_CACHE_HOME": root + "/cache",
        }))
        cfg = Config()
        cfg.pod.initialized = True
        self.stack.enter_context(patch.object(Config, "load", return_value=cfg))
        for method in ("_start_status_timer", "_on_follow_app_log", "_refresh_update_status",
                       "_refresh_dashboard", "_refresh_info", "_maybe_run_first_launch_checks"):
            self.stack.enter_context(patch.object(WinpodxWindow, method))
        self.stack.enter_context(patch("winpodx.gui.main_window.list_pending", return_value=[]))
        self.stack.enter_context(patch("winpodx.gui.main_window.list_available_apps", return_value=[]))
        self.stack.enter_context(patch.object(WinpodxWindow, "_read_license_text", return_value="MIT"))
        self.stack.enter_context(patch("winpodx.gui._main_window_apps.list_available_apps", return_value=[
            AppInfo("word", "Microsoft Word", r"C:\Office\WINWORD.EXE"),
        ]))
        self.persist = self.stack.enter_context(patch("winpodx.core.discovery.persist_discovered", return_value=[]))
        self.stack.enter_context(patch("winpodx.gui.workers.sync_desktop_entries"))
        self.stack.enter_context(patch("winpodx.desktop.icons.refresh_icon_cache"))
        self.callbacks = []
        self.gui_thread = threading.get_ident()
        self.warnings = []
        old_handler = qInstallMessageHandler(lambda _kind, _context, text: self.warnings.append(text))
        self.addCleanup(qInstallMessageHandler, old_handler)
        for method in ("_set_refresh_state", "_reload_apps", "_cleanup_refresh_worker"):
            original = getattr(AppCrudMixin, method)

            def record(window, *args, original=original, method=method):
                current = threading.get_ident()
                self.callbacks.append((method, current))
                # Report the old cross-thread defect without crashing the test.
                if current == self.gui_thread:
                    return original(window, *args)

            self.stack.enter_context(patch.object(AppCrudMixin, method, record))
        self.dialogs = []
        self.stack.enter_context(patch("winpodx.gui._main_window_apps.actionable_error", side_effect=
            lambda *args, **kwargs: self.dialogs.append(threading.get_ident()) or "Close"))
        self.window = WinpodxWindow()
        self.addCleanup(self.window.close)

    def wait_until(self, condition, timeout=3):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self.app.processEvents()
            if condition():
                return
            time.sleep(0.005)
        self.fail("Qt callback/worker cleanup did not finish before the deadline")

    def check_idle(self):
        self.wait_until(lambda: self.window._refresh_thread is None)
        self.assertEqual(self.window._refresh_state, "idle")
        self.assertTrue(self.window.refresh_btn.isEnabled())
        self.assertIsNone(self.window._refresh_worker)
        self.assertTrue(self.callbacks)
        self.assertTrue(all(tid == self.gui_thread for _, tid in self.callbacks), self.callbacks)
        self.assertFalse(any("different thread" in text or "Destroyed while thread" in text for text in self.warnings), self.warnings)

    def test_success_rebuilds_real_widgets_on_gui_thread(self):
        with patch("winpodx.core.discovery.discover_apps", return_value=[]) as discover:
            for _ in range(3):
                self.window.refresh_btn.click()
                self.check_idle()
            self.assertEqual(discover.call_count, 3)
        self.assertEqual(self.window.apps[0].name, "word")

    def test_failures_show_dialog_and_allow_retry(self):
        for kind in ("pod_not_running", "agent_unavailable", "timeout"):
            with patch("winpodx.core.discovery.discover_apps", side_effect=DiscoveryError("test", kind=kind)):
                before = len(self.dialogs)
                self.window.refresh_btn.click()
                self.check_idle()
                self.wait_until(lambda: len(self.dialogs) > before)
        self.assertTrue(all(tid == self.gui_thread for tid in self.dialogs))
        self.persist.assert_not_called()

    def test_slow_scan_keeps_event_loop_live_and_ignores_duplicate_clicks(self):
        entered, release = threading.Event(), threading.Event()
        ticks = []
        timer = QTimer(self.window)
        timer.timeout.connect(lambda: ticks.append(1))
        timer.start(10)

        def discover(_cfg):
            entered.set()
            release.wait(2)
            return []

        with patch("winpodx.core.discovery.discover_apps", side_effect=discover) as scan:
            try:
                self.window.refresh_btn.click()
                self.wait_until(lambda: entered.is_set() and len(ticks) >= 4)
                worker = self.window._refresh_worker
                for _ in range(20):
                    self.window._on_refresh_apps()
                self.assertIs(self.window._refresh_worker, worker)
                self.assertEqual(scan.call_count, 1)
                self.assertFalse(self.window.refresh_btn.isEnabled())
            finally:
                release.set()
                timer.stop()
                self.check_idle()

    def test_gui_discovery_preserves_nix_owned_shortcuts(self):
        with patch.dict(os.environ, {"WINPODX_DECLARATIVE_SHORTCUTS": "1"}), \
             patch("winpodx.desktop.entry.install_desktop_entry") as install, \
             patch("winpodx.desktop.entry.remove_desktop_entry") as remove, \
             patch("winpodx.desktop.entry.install_desktop_shortcut") as desktop:
            sync_desktop_entries([])
            install.assert_not_called()
            remove.assert_not_called()
            desktop.assert_not_called()


if __name__ == "__main__":
    unittest.main()
