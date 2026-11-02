import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time

master, slave = pty.openpty()
fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))


def terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


process = subprocess.Popen(
    [sys.argv[1], "server"], stdin=slave, stdout=slave, stderr=slave,
    preexec_fn=terminal, env=dict(os.environ, TERM="xterm-256color"),
)
os.close(slave)
output = bytearray()


def expect(marker, timeout=20):
    deadline = time.monotonic() + timeout
    while marker not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
            raise AssertionError(f"Interactive tssh stalled before {marker!r}: {bytes(output)!r}")
        try:
            data = os.read(master, 8192)
        except OSError as error:
            raise AssertionError(f"Interactive tssh closed early: {bytes(output)!r}") from error
        output.extend(data)
        if b"\x1b[6n" in data:
            os.write(master, b"\x1b[1;1R")


try:
    expect(b"__INTERACTIVE_READY__")
    os.write(master, b"printf '__INTERACTIVE_COMMAND__'; hostname; exit\r")
    expect(b"__INTERACTIVE_COMMAND__server")
    assert process.wait(timeout=10) == 0
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
