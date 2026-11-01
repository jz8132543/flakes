import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


master, slave = pty.openpty()


def resize(rows, columns):
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


resize(40, 100)


def controlling_terminal():
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)


process = subprocess.Popen(
    [sys.argv[1], "--auto-transport", "-t", "-n", "server", "sh", "-c", "stty size; sleep 3; stty size"],
    stdin=slave, stdout=slave, stderr=slave, preexec_fn=controlling_terminal,
)
os.close(slave)
output = bytearray()


def expect(value):
    deadline = time.monotonic() + 20
    while value not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
            raise AssertionError(f"PTY output did not contain {value!r}: {bytes(output)!r}")
        try:
            output.extend(os.read(master, 8192))
        except OSError as error:
            raise AssertionError(f"PTY closed before {value!r}, exit={process.poll()}: {bytes(output)!r}") from error


try:
    expect(b"40 100")
    resize(50, 120)
    os.kill(process.pid, signal.SIGWINCH)
    expect(b"50 120")
    assert process.wait(timeout=10) == 0
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
