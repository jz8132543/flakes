"""Run interactive commands in a real PTY for terminal regression tests."""

import errno
import fcntl
import os
import pty
import re
import select
import signal
import struct
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
