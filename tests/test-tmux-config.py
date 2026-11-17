#!/usr/bin/env python3
"""Check TCP-only SSH probes and optionally a built Home Manager tmux config."""

import os
import fcntl
from pathlib import Path
import pty
import re
import runpy
import select
import shutil
import socket
import struct
import subprocess
import tempfile
import termios
import threading
import time
import unittest

try:
    import pyte
except ImportError:
    pyte = None


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "home-manager/modules/tippy/tmux/tmux-ssh-status.sh"
).read_text()
FUNCTIONS, MAIN = SOURCE.split("\nssh_pid=", 1)
MOCKS = r'''
find_ssh_pid() { printf '%s' "$ACTIVE_SSH"; }
load_ssh_args() { SSH_ARGS=("$SSH_PROGRAM" -p "$SSH_PORT" user@alias.example); }
test_ssh() {
  printf 'ssh:%s\n' "$*" >> "$CALL_LOG"
  printf 'hostname %s\nport %s\n' "$SSH_HOST" "$SSH_PORT"
}
timeout() {
  printf 'timeout:%s\n' "$1" >> "$CALL_LOG"
  shift
  "$@"
}
tcping() {
  printf 'tcping:%s\n' "$*" >> "$CALL_LOG"
  printf '%s\n' "$TCP_OUTPUT"
  return "$TCP_EXIT"
}
ping() {
  printf 'ICMP called\n' >> "$CALL_LOG"
  printf 'time=999ms\n'
}
'''


class SshStatusTests(unittest.TestCase):
    def run_status(self, **overrides):
        with tempfile.TemporaryDirectory(prefix="tmux-ssh-test-", dir="/tmp/kilo") as directory:
            log = Path(directory) / "calls"
            env = {
                **os.environ,
                "CALL_LOG": str(log),
                "ACTIVE_SSH": "42",
                "SSH_PROGRAM": "ssh",
                "SSH_HOST": "real.example",
                "SSH_PORT": "22",
                "TCP_OUTPUT": '{"record":"probe","success":true,"duration_ms":0.4}',
                "TCP_EXIT": "0",
                **overrides,
            }
            script = (FUNCTIONS + MOCKS + "\nssh_pid=" + MAIN).replace("@ssh@", "test_ssh")
            result = subprocess.run(
                ["bash", "-c", script, "test-status", "1"],
                capture_output=True, text=True, env=env, timeout=5, check=True,
            )
            calls = log.read_text() if log.exists() else ""
            self.assertNotIn("ICMP", calls)
            self.assertEqual(result.stderr, "")
            self.assertNotIn("#[", result.stdout)
            self.assertEqual(result.stdout, result.stdout.strip() + "\n")
            return result.stdout, calls

    def test_sub_millisecond_latency_is_not_replaced(self):
        output, calls = self.run_status()
        self.assertIn("alias TCP 0.4ms", output)
        self.assertIn("timeout:2s", calls)
        self.assertIn("tcping:--timeout-ms 1200 -c 1 -o json real.example:22", calls)
        self.assertIn("ssh:-G -p 22 user@alias.example", calls)

    def test_nonstandard_port_and_rounding(self):
        output, calls = self.run_status(
            SSH_PORT="2222",
            TCP_OUTPUT='{"record":"probe","success":true,"duration_ms":17.6}',
        )
        self.assertIn("alias:2222 TCP 18ms", output)
        self.assertIn("real.example:2222", calls)

    def test_failed_probe_never_falls_back_to_icmp(self):
        output, calls = self.run_status(
            TCP_OUTPUT='{"record":"probe","success":false,"duration_ms":1200}',
            TCP_EXIT="1",
        )
        self.assertIn("alias TCP --", output)
        self.assertNotIn("1200ms", output)
        self.assertEqual(calls.count("tcping:"), 1)

    def test_missing_or_invalid_probe_output(self):
        for data in ("", "not json", '{"record":"summary","duration_ms":12}'):
            with self.subTest(data=data):
                output, _ = self.run_status(TCP_OUTPUT=data, TCP_EXIT="124")
                self.assertIn("alias TCP --", output)

    def test_ipv6_endpoint(self):
        for host in ("2001:db8::1", "[2001:db8::1]"):
            with self.subTest(host=host):
                output, calls = self.run_status(SSH_HOST=host, SSH_PORT="2222")
                self.assertIn("alias:2222 TCP 0.4ms", output)
                self.assertIn("[2001:db8::1]:2222", calls)

    def test_tssh_probe_is_not_reported_as_tunnel_rtt(self):
        output, _ = self.run_status(SSH_PROGRAM="tssh")
        self.assertIn("alias TCP probe 0.4ms", output)

    def test_local_pane_does_not_probe(self):
        output, calls = self.run_status(ACTIVE_SSH="")
        self.assertNotIn("TCP", output)
        self.assertEqual(calls, "")

    def test_real_tcping_against_local_listener(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            listener.settimeout(5)
            port = listener.getsockname()[1]

            def accept_probe():
                with listener.accept()[0]:
                    pass

            worker = threading.Thread(target=accept_probe)
            worker.start()
            try:
                script = FUNCTIONS + '\nget_latency 127.0.0.1 "$1"'
                result = subprocess.run(
                    ["bash", "-c", script, "test-latency", str(port)],
                    capture_output=True, text=True, timeout=5, check=True,
                )
                self.assertGreaterEqual(float(result.stdout.strip()), 0)
                self.assertEqual(result.stderr, "")
            finally:
                worker.join(timeout=5)
            self.assertFalse(worker.is_alive())


@unittest.skipUnless(os.environ.get("TMUX_TEST_CONFIG"), "TMUX_TEST_CONFIG not provided")
class ThemeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="tmux-theme-test-", dir="/tmp/kilo")
        cls.socket = str(Path(cls.directory.name) / "tmux.sock")
        cls.config = os.environ["TMUX_TEST_CONFIG"]
        cls.addClassCleanup(cls.directory.cleanup)
        cls.addClassCleanup(
            subprocess.run, ["tmux", "-S", cls.socket, "kill-server"],
            capture_output=True, timeout=10,
        )
        cls.tmux("-f", cls.config, "new-session", "-d", "-s", "theme-test")

    @classmethod
    def tmux(cls, *args):
        result = subprocess.run(
            ["tmux", "-S", cls.socket, *args],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode or result.stderr:
            raise AssertionError(f"tmux {args}: {result.stdout}{result.stderr}")
        return result.stdout.strip()

    def test_telemetry_without_battery_or_time(self):
        self.assertEqual(self.tmux("show-options", "-gv", "@dracula-plugins"), "")
        right = self.tmux("show-options", "-gv", "status-right")
        for component in ("tmux-ssh-status", "tmux-net-speed", "cpu_percentage", "ram_percentage"):
            self.assertIn(component, right)
        self.assertEqual(self.tmux("show-options", "-gqv", "@dracula-status-right"), "")
        for removed in ("battery", "%H:%M", "dracula-status-right", "weather", "network.sh"):
            self.assertNotIn(removed, right)

    def test_status_left_is_hidden(self):
        self.assertEqual(self.tmux("show-options", "-gv", "status-left"), "")
        self.assertEqual(self.tmux("show-options", "-gv", "status-left-length"), "0")

    def test_theme_and_original_settings(self):
        for name, expected in (
            ("status-position", "top"), ("status-interval", "3"),
            ("history-limit", "200000"), ("mouse", "on"),
            ("prefix", "C-b"), ("clock-mode-style", "24"),
            ("clock-mode-colour", "#bd93f9"),
        ):
            with self.subTest(option=name):
                self.assertEqual(self.tmux("show-options", "-gv", name), expected)
        self.assertIn("#bd93f9", self.tmux("show-options", "-gv", "pane-active-border-style"))
        self.assertIn("#282a36", self.tmux("show-options", "-gv", "window-style"))

    def test_status_is_white_and_matches_pane_background(self):
        for name in (
            "status-style", "status-right",
            "window-status-format", "window-status-current-format", "message-style",
            "message-command-style",
        ):
            with self.subTest(option=name):
                style = self.tmux("show-options", "-gv", name)
                self.assertIn("bg=#282a36", style)
                self.assertIn("fg=#ffffff", style)
                self.assertNotRegex(style, r"bg=(?!#282a36\b)[^,\]]+")
                self.assertNotRegex(style, r"fg=(?!#ffffff\b)[^,\]]+")
        self.assertIn("bold]", self.tmux("show-options", "-gv", "window-status-current-format"))

    def test_status_widgets_are_compact(self):
        right = self.tmux("show-options", "-gv", "status-right")
        self.assertEqual(right.count("|"), 3)
        for padding in ("| ", " |", "CPU ", "RAM ", "\u2502"):
            self.assertNotIn(padding, right)
        for option in ("@cpu_percentage_format", "@ram_percentage_format"):
            self.assertEqual(self.tmux("show-options", "-gv", option), "%d%%")
        net_speed = re.search(r"#\((\S+/bin/tmux-net-speed)\)", right).group(1)
        output = subprocess.run(
            [net_speed], capture_output=True, text=True, timeout=5, check=True,
        ).stdout
        self.assertRegex(output, r"^\u2193-?\d+[BKM]/s \u2191-?\d+[BKM]/s$")

    def test_shortcuts(self):
        prefix = self.tmux("list-keys", "-T", "prefix")
        root = self.tmux("list-keys", "-T", "root")
        for action in ("clock-mode", "tmux-system-info", "btm-detail", "autoclipboard"):
            self.assertIn(action, prefix)
        for key in ("M-1", "M-9", "WheelUpPane", "WheelDownPane"):
            self.assertIn(key, root)

    def test_reload_preserves_widgets_and_sessions(self):
        before = self.tmux("show-options", "-gv", "status-right")
        sessions = self.tmux("list-sessions", "-F", "#{session_name}")
        self.tmux("source-file", self.config)
        self.assertEqual(before, self.tmux("show-options", "-gv", "status-right"))
        self.assertEqual(sessions, self.tmux("list-sessions", "-F", "#{session_name}"))
        self.test_status_left_is_hidden()

    def test_reload_clears_legacy_status_colours(self):
        self.tmux("set-option", "-g", "status-bg", "#1e1e1e")
        self.tmux("set-option", "-g", "status-fg", "#bd93f9")
        self.tmux("source-file", self.config)
        self.assertEqual(self.tmux("show-options", "-gv", "status-bg"), "default")
        self.assertEqual(self.tmux("show-options", "-gv", "status-fg"), "default")
        self.test_status_is_white_and_matches_pane_background()

    def test_reload_clears_legacy_battery_and_time(self):
        self.tmux("set-option", "-g", "@dracula-status-right", "battery.sh %H:%M")
        self.tmux("source-file", self.config)
        self.test_telemetry_without_battery_or_time()

    @unittest.skipUnless(pyte, "pyte not installed")
    def test_rendered_status_background_including_blank_cells(self):
        self.tmux("set-option", "-g", "status-bg", "#1e1e1e")
        self.tmux("source-file", self.config)
        screen = pyte.Screen(160, 40)
        # Ignore terminal status queries; only rendering is under test.
        screen.report_device_status = lambda *args, **kwargs: None
        stream = pyte.Stream(screen)
        terminal, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 160, 0, 0))
        client = subprocess.Popen(
            [shutil.which("tmux"), "-S", self.socket, "attach-session", "-t", "theme-test"],
            stdin=slave, stdout=slave, stderr=slave,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        os.close(slave)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if select.select([terminal], [], [], 0.1)[0]:
                    stream.feed(os.read(terminal, 65536).decode(errors="replace"))
                if "RAM" in screen.display[0]:
                    break
            self.assertIn("RAM", screen.display[0], "Status line did not render")
            cells = [screen.buffer[0][column] for column in range(160)]
            blanks = [cell for cell in cells if cell.data == " "]
            self.assertGreater(len(blanks), 10)
            self.assertEqual({cell.bg for cell in blanks}, {"282a36"})
            self.assertEqual({cell.bg for cell in cells}, {"282a36"})
            self.assertEqual({cell.fg for cell in cells if cell.data.strip()}, {"ffffff"})
        finally:
            client.terminate()
            client.wait(timeout=5)
            os.close(terminal)

    def test_real_terminal_clock_and_system_info(self):
        terminal_run = runpy.run_path(
            str(Path(__file__).with_name("test-bottom-monitor.py"))
        )["terminal_run"]
        for width in (80, 160):
            with self.subTest(width=width):
                output = terminal_run(
                    [shutil.which("tmux"), "-S", self.socket, "attach-session", "-t", "theme-test"],
                    (40, width),
                    [(0.5, b"\x02t"), (1.0, b"q"), (1.5, b"\x02I"),
                     (3.5, b"\r"), (4.0, b"\x02d")],
                )
                self.assertIn("Kernel", output, "Fastfetch popup did not render")
                self.assertIn("NixOS", output)
                self.assertNotIn("not found", output)
                self.assertNotIn("%H:%M", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
