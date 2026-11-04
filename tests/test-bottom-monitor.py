#!/usr/bin/env python3
"""Exercise the generated bottom config and diagnostic launcher in real PTYs."""

import argparse
import errno
import fcntl
import os
import pty
import re
import select
import shlex
import signal
import struct
import subprocess
import termios
import time


def terminal_run(command, size, events, timeout=7):
    child, terminal = pty.fork()
    if child == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ["FZF_DEFAULT_OPTS"] = ""
        os.execv(command[0], command)

    fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", *size, 0, 0))
    output = bytearray()
    pending = list(events)
    started = time.monotonic()
    status = None
    try:
        while time.monotonic() - started < timeout:
            elapsed = time.monotonic() - started
            while pending and elapsed >= pending[0][0]:
                os.write(terminal, pending.pop(0)[1])
            if select.select([terminal], [], [], 0.05)[0]:
                try:
                    data = os.read(terminal, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    data = b""
                output.extend(data)
            waited, result = os.waitpid(child, os.WNOHANG)
            if waited:
                status = result
                break
        if status is None:
            raise AssertionError(f"Terminal command did not exit: {command}")
        assert os.waitstatus_to_exitcode(status) == 0, output[-4000:].decode(errors="replace")
        text = output.decode(errors="replace")
        return re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    finally:
        try:
            os.killpg(child, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if status is None:
            os.waitpid(child, 0)
        os.close(terminal)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bottom")
    parser.add_argument("config")
    parser.add_argument("details")
    parser.add_argument("--tmux")
    parser.add_argument("--tmux-config")
    args = parser.parse_args()

    for size in ((24, 80), (50, 160), (70, 240)):
        output = terminal_run(
            [args.bottom, "--config_location", args.config, "--read_only"],
            size,
            [(1.0, b"e"), (1.5, b"e"), (1.8, b"f"), (2.0, b"f"), (2.3, b"q")],
        )
        assert "CPU" in output and "PID" in output, output[-3000:]
        assert "invalid" not in output.lower(), output[-3000:]
        if size[1] == 240:
            for column in ("Virt", "T.Read", "T.Write", "Nice", "Pri"):
                assert column in output, f"Missing wide-screen column: {column}"
        print(f"PASS: bottom dashboard/expand/freeze at {size[1]}x{size[0]}")

    output = terminal_run(
        [args.bottom, "--config_location", args.config, "--read_only",
         "--get_threads", "--tree", "--tree_collapse", "--expanded"],
        (50, 160),
        [(1.4, b"q")],
    )
    assert "PID" in output
    print("PASS: expanded thread/tree view")

    help_result = subprocess.run([args.details, "--help"], capture_output=True, text=True, check=True)
    assert "No automatic privilege escalation" in help_result.stdout
    result = subprocess.run([args.details, "missing-view"], capture_output=True, text=True)
    assert result.returncode == 2
    for pid in ("0", "-1", "not-a-pid", "1;exit", "999999999999"):
        result = subprocess.run([args.details, "process-info", pid], capture_output=True, text=True)
        assert result.returncode == 1, (pid, result.stdout, result.stderr)
    print("PASS: help, unsupported views, and PID validation")

    for view, expected in (("pressure-snapshot", "pressure"), ("filesystem-snapshot", "Inode usage")):
        result = subprocess.run(
            [args.details, view], capture_output=True, text=True, check=True,
            env={**os.environ, "PATH": "/nonexistent"},
        )
        assert expected in result.stdout
    print("PASS: pressure/filesystem snapshots without PATH dependencies")

    for view, expected in (
        ("cpu", "%iowait"), ("interrupts", "CPU"), ("memory", "swpd"),
        ("disk", "r/s"), ("network", "rxpck/s"), ("process-live", "TGID"),
    ):
        command = [args.details, view]
        if view == "process-live":
            command.append(str(os.getpid()))
        try:
            result = subprocess.run(command, capture_output=True, timeout=3)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            output = result.stdout
        except subprocess.TimeoutExpired as result:
            output = result.stdout or b""
        assert expected.encode() in output, f"No expected live metrics from {view}"
        print(f"PASS: live {view} metrics")

    output = terminal_run(
        [args.details], (35, 140),
        [(0.8, b"\r"), (2.0, b"\x03"), (2.7, b"\x1b")],
    )
    assert "%usr" in output, "CPU live view did not start"
    assert output.count("Performance >") >= 2, "Ctrl-C did not return to the menu"
    print("PASS: diagnostics menu -> CPU -> Ctrl-C -> menu -> Esc")

    output = terminal_run(
        [args.details, "process", str(os.getpid())], (35, 140),
        [(0.8, b"\r"), (2.0, b"\x03"), (2.7, b"\x1b")],
    )
    assert "TGID" in output, "Per-process live view did not start"
    assert output.count(f"PID {os.getpid()} >") >= 2, "Did not return to PID submenu"
    print("PASS: PID submenu -> pidstat -> Ctrl-C -> submenu -> Esc")

    if args.tmux:
        assert args.tmux_config, "--tmux requires an isolated --tmux-config"
        socket = f"/tmp/kilo/bottom-monitor-test-{os.getpid()}.sock"
        command = shlex.join([args.bottom, "--config_location", args.config, "--read_only"])
        try:
            output = terminal_run(
                [args.tmux, "-S", socket, "-f", args.tmux_config, "new-session", command],
                (50, 160),
                [(1.0, b"\x02M"), (2.0, b"\x1b"), (2.7, b"q")],
            )
            assert "Performance >" in output, "tmux did not open the diagnostics popup"
            print("PASS: tmux Ctrl-b M -> diagnostics popup -> Esc -> bottom")
        finally:
            subprocess.run(
                [args.tmux, "-S", socket, "kill-server"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )


if __name__ == "__main__":
    main()
