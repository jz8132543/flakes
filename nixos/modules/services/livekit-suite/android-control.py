"""Loopback-only Android touch bridge. Python 3.9+, standard library only."""

import argparse
import array
import fcntl
import hmac
import json
import math
import os
import secrets
import shlex
import signal
import stat
import struct
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

MAX_BODY = 4096
MAX_SEQ = (1 << 53) - 1  # Exact integers shared with JavaScript.
WATCHDOG_SECONDS = 0.250
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, BTN_TOUCH = 0, 330
ABS_X, ABS_Y = 0, 1
ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR = 47, 48
ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 53, 54
ABS_MT_TRACKING_ID, ABS_MT_PRESSURE = 57, 58
INPUT_EVENT = struct.Struct("@llHHi")


class RequestError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def exact_keys(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise RequestError("unexpected or missing object fields")


def integer(value, low, high, name):
    if type(value) is not int or not low <= value <= high:
        raise RequestError(f"invalid {name}")
    return value


def session_id(value):
    try:
        if not isinstance(value, str) or str(uuid.UUID(value)) != value:
            raise ValueError
    except (ValueError, AttributeError):
        raise RequestError("session must be a canonical lowercase UUID") from None
    return value


def decode_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise RequestError("duplicate JSON key")
            result[key] = value
        return result

    def constant(value):
        raise RequestError("non-finite JSON number")

    if len(raw) > MAX_BODY:
        raise RequestError("body too large", 413)
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                          parse_constant=constant)
    except (ValueError, UnicodeError, RecursionError):
        raise RequestError("invalid UTF-8 JSON") from None


def validate_snapshot(value):
    exact_keys(value, ("v", "session", "seq", "type", "points"))
    integer(value["v"], 1, 1, "v")
    session = session_id(value["session"])
    seq = integer(value["seq"], 0, MAX_SEQ, "seq")
    if value["type"] != "snapshot":
        raise RequestError("only snapshot is supported")
    points = value["points"]
    if not isinstance(points, list) or len(points) > 10:
        raise RequestError("points must contain at most 10 contacts")
    contacts = {}
    for point in points:
        exact_keys(point, ("id", "x", "y"))
        ident = integer(point["id"], 0, 9, "contact id")
        if ident in contacts:
            raise RequestError("duplicate contact id")
        coords = []
        for axis in ("x", "y"):
            coordinate = point[axis]
            if (type(coordinate) not in (int, float)
                    or not 0 <= coordinate <= 1 or not math.isfinite(coordinate)):
                raise RequestError(f"invalid {axis} coordinate")
            coords.append(float(coordinate))
        contacts[ident] = tuple(coords)
    return session, seq, contacts


class TouchWriter:
    """Type B frames with contact IDs as slots and per-contact tracking IDs."""

    max_contacts = 10

    def __init__(self, emit, bounds, rotation=0):
        self.emit = emit
        self.bounds = bounds
        self.rotation = rotation
        self.active = {}
        self.next_tracking = 0

    def coordinates(self, x, y):
        # Inverse of the clockwise display rotation, into native ABS coordinates.
        if self.rotation == 90:
            x, y = y, 1 - x
        elif self.rotation == 180:
            x, y = 1 - x, 1 - y
        elif self.rotation == 270:
            x, y = 1 - y, x
        xmin, xmax, ymin, ymax = self.bounds
        return round(xmin + x * (xmax - xmin)), round(ymin + y * (ymax - ymin))

    def snapshot(self, contacts):
        events = [(EV_KEY, BTN_TOUCH, int(bool(contacts)))]
        for ident in sorted(self.active.keys() - contacts.keys()):
            events.extend(((EV_ABS, ABS_MT_SLOT, ident),
                           (EV_ABS, ABS_MT_TRACKING_ID, -1)))
        tracking = dict(self.active)
        for ident in sorted(contacts):
            events.append((EV_ABS, ABS_MT_SLOT, ident))
            if ident not in self.active:
                while self.next_tracking in tracking.values():
                    self.next_tracking = (self.next_tracking + 1) % 65536
                tracking[ident] = self.next_tracking
                self.next_tracking = (self.next_tracking + 1) % 65536
                events.append((EV_ABS, ABS_MT_TRACKING_ID, tracking[ident]))
            x, y = self.coordinates(*contacts[ident])
            events.extend(((EV_ABS, ABS_MT_POSITION_X, x),
                           (EV_ABS, ABS_MT_POSITION_Y, y),
                           (EV_ABS, ABS_MT_TOUCH_MAJOR, 1),
                           (EV_ABS, ABS_MT_PRESSURE, 127)))
        if contacts:
            x, y = self.coordinates(*contacts[min(contacts)])
            events.extend(((EV_ABS, ABS_X, x), (EV_ABS, ABS_Y, y)))
        events.append((EV_SYN, SYN_REPORT, 0))
        self.emit(events)
        self.active = {ident: tracking[ident] for ident in contacts}

    def release(self):
        self.snapshot({})

    def close(self):
        self.release()


def ioctl_code(direction, number, size=0):
    return (direction << 30) | (size << 16) | (ord("U") << 8) | number


class UInputWriter(TouchWriter):
    def __init__(self, path, bounds, rotation):
        if os.geteuid() != 0:
            raise RuntimeError("uinput requires root (uid 0); use su, not plain Termux")
        self.fd = None
        self.created = False
        try:
            self.fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            if not stat.S_ISCHR(os.fstat(self.fd).st_mode):
                raise RuntimeError("uinput path is not a character device")
            version = array.array("I", [0])
            fcntl.ioctl(self.fd, ioctl_code(2, 45, 4), version, True)
            if version[0] < 5:
                raise RuntimeError("kernel uinput API >= 5 (UI_DEV_SETUP) required")
            for event in (EV_SYN, EV_KEY, EV_ABS):
                fcntl.ioctl(self.fd, ioctl_code(1, 100, 4), event)
            fcntl.ioctl(self.fd, ioctl_code(1, 101, 4), BTN_TOUCH)
            fcntl.ioctl(self.fd, ioctl_code(1, 110, 4), 1)  # INPUT_PROP_DIRECT
            xmin, xmax, ymin, ymax = bounds
            axes = {ABS_X: (xmin, xmax), ABS_Y: (ymin, ymax),
                    ABS_MT_SLOT: (0, 9), ABS_MT_TRACKING_ID: (0, 65535),
                    ABS_MT_POSITION_X: (xmin, xmax), ABS_MT_POSITION_Y: (ymin, ymax),
                    ABS_MT_TOUCH_MAJOR: (0, 255), ABS_MT_PRESSURE: (0, 255)}
            for axis, (minimum, maximum) in axes.items():
                fcntl.ioctl(self.fd, ioctl_code(1, 103, 4), axis)
                info = struct.pack("=H2xiiiiii", axis, 0, minimum, maximum, 0, 0, 0)
                fcntl.ioctl(self.fd, ioctl_code(1, 4, len(info)), info)
            setup = struct.pack("=HHHH80sI", 3, 0x1209, 1, 1,
                                b"LiveKit Android Touch", 0)
            fcntl.ioctl(self.fd, ioctl_code(1, 3, len(setup)), setup)
            fcntl.ioctl(self.fd, ioctl_code(0, 1))
            self.created = True
            super().__init__(self.write_events, bounds, rotation)
            self.release()
        except Exception:
            self.destroy()
            raise

    def write_events(self, events):
        data = b"".join(INPUT_EVENT.pack(0, 0, *event) for event in events)
        while data:
            written = os.write(self.fd, data)
            if written <= 0 or written % INPUT_EVENT.size:
                raise OSError("short or unaligned uinput write")
            data = data[written:]

    def destroy(self):
        if self.fd is not None:
            try:
                if self.created:
                    fcntl.ioctl(self.fd, ioctl_code(0, 2))
            finally:
                os.close(self.fd)
                self.fd = None

    def close(self):
        if self.fd is None:
            return
        try:
            self.release()
        finally:
            self.destroy()


class ShellWriter:
    """Approximate one completed gesture; never inject held contacts on snapshots."""

    max_contacts = 1

    def __init__(self, prefix, width, height):
        self.prefix = prefix
        self.width, self.height = width, height
        self.gesture = None
        self.process = None
        result = self.run_command(["/system/bin/id", "-u"], probe=True)
        if result.stdout.strip() not in ("0", "2000"):
            raise RuntimeError("shell backend requires root or authorized Shizuku shell uid 2000")

    def run_command(self, args, probe=False):
        command = self.prefix + [shlex.join(args)] if self.prefix else args
        if probe:
            return subprocess.run(command, check=True, capture_output=True,
                                  text=True, timeout=10)
        return subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def snapshot(self, contacts):
        if contacts:
            ident, (x, y) = next(iter(contacts.items()))
            position = (round(x * (self.width - 1)), round(y * (self.height - 1)))
            if self.gesture is None or self.gesture[0] != ident:
                self.gesture = (ident, position, position, time.monotonic())
            else:
                self.gesture = (ident, self.gesture[1], position, self.gesture[3])
        elif self.gesture is not None:
            _, start, end, started = self.gesture
            self.gesture = None
            if self.process is not None and self.process.poll() is None:
                raise RequestError("previous shell gesture still running; gesture dropped", 429)
            duration = max(1, min(1000, round((time.monotonic() - started) * 1000)))
            args = ["/system/bin/input", "touchscreen"]
            if start == end and duration < 200:
                args += ["tap", *map(str, end)]
            else:
                args += ["swipe", *map(str, start), *map(str, end), str(duration)]
            self.process = self.run_command(args)

    def release(self):
        self.gesture = None
        # An already started input swipe is finite, but cannot be safely cancelled.
        if self.process is not None and self.process.poll() is not None:
            self.process = None

    def close(self):
        self.release()


class ControlState:
    def __init__(self, writer, clock=time.monotonic):
        self.writer, self.clock = writer, clock
        self.lock = threading.RLock()
        self.session = None
        self.controller = None
        self.deadline = 0
        self.last_seq = -1
        self.last_snapshot = 0
        self.contacts = {}
        self.used_sessions = set()
        self.failed = False

    def clear_contacts(self):
        try:
            self.writer.release()
        finally:
            self.contacts = {}

    def revoke(self):
        try:
            self.clear_contacts()
        finally:
            self.session = self.controller = None
            self.last_seq = -1
            self.deadline = 0

    def tick(self):
        with self.lock:
            now = self.clock()
            if self.session is not None and now >= self.deadline:
                self.revoke()
            elif self.contacts and now - self.last_snapshot >= WATCHDOG_SECONDS:
                self.clear_contacts()  # Keep the grant and sequence high-water mark.

    def new_session(self, value):
        value = session_id(value)
        if value in self.used_sessions:
            raise RequestError("session already used; create a new UUID", 409)
        if len(self.used_sessions) >= 4096:
            raise RequestError("runtime grant limit reached; restart daemon", 409)
        return value

    def dispatch(self, path, value):
        with self.lock:
            if self.failed:
                raise RequestError("input backend failed; restart daemon", 503)
            self.tick()
            if path == "/grant":
                exact_keys(value, ("session", "controller", "ttl_ms"))
                session = self.new_session(value["session"])
                controller = value["controller"]
                if (not isinstance(controller, str) or not controller
                        or len(controller) > 256 or any(ord(c) < 32 for c in controller)):
                    raise RequestError("invalid controller identity")
                ttl = integer(value["ttl_ms"], 1, 3600000, "ttl_ms")
                if self.session is not None:
                    raise RequestError("grant exists; revoke or reset explicitly", 409)
                self.clear_contacts()
                self.session, self.controller = session, controller
                self.used_sessions.add(session)
                self.deadline = self.clock() + ttl / 1000
                self.last_seq = -1
            elif path == "/snapshot":
                session, seq, contacts = validate_snapshot(value)
                self.require_session(session)
                if seq <= self.last_seq:
                    raise RequestError("stale or duplicate seq", 409)
                if len(contacts) > self.writer.max_contacts:
                    raise RequestError("backend does not support this contact count", 422)
                # Advance even when a shell command is dropped: never replay that command.
                self.last_seq = seq
                self.writer.snapshot(contacts)
                self.contacts = contacts
                self.last_snapshot = self.clock()
            elif path == "/revoke":
                exact_keys(value, ("session",))
                self.require_session(session_id(value["session"]))
                self.revoke()
            elif path == "/reset":
                exact_keys(value, ("session", "new_session"))
                self.require_session(session_id(value["session"]))
                replacement = self.new_session(value["new_session"])
                self.clear_contacts()
                self.session, self.last_seq = replacement, -1
                self.used_sessions.add(replacement)
            elif path == "/status":
                exact_keys(value, ())
            else:
                raise RequestError("unknown endpoint", 404)
            return {"ok": True, "session": self.session, "controller": self.controller,
                    "seq": self.last_seq, "active": len(self.contacts),
                    "ttl_ms": max(0, round((self.deadline - self.clock()) * 1000))}

    def require_session(self, session):
        if self.session is None or session != self.session:
            raise RequestError("session not granted", 403)

    def backend_failed(self):
        with self.lock:
            self.failed = True
            try:
                self.revoke()
            except OSError:
                pass
            finally:
                try:
                    self.writer.close()
                except OSError:
                    pass


class ControlServer(HTTPServer):
    def __init__(self, port, token, state):
        self.token, self.state = token.encode("ascii"), state
        super().__init__(("127.0.0.1", port), ControlHandler)
        self.timeout = 0.050

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(0.5)
        return connection, address


class ControlHandler(BaseHTTPRequestHandler):
    server_version = "AndroidControl/1"
    sys_version = ""

    def log_message(self, format, *args):
        pass  # Do not log tokens, identities or payloads.

    def respond(self, status, value):
        body = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_POST(self):
        try:
            if self.headers.get_all("Origin"):
                raise RequestError("browser-origin requests are not allowed", 403)
            auth = self.headers.get_all("Authorization", [])
            expected = b"Bearer " + self.server.token
            if len(auth) != 1 or not hmac.compare_digest(auth[0].encode("utf-8"), expected):
                raise RequestError("invalid bearer token", 401)
            lengths = self.headers.get_all("Content-Length", [])
            if self.headers.get_all("Transfer-Encoding") or len(lengths) != 1:
                raise RequestError("one Content-Length required; no chunked requests")
            if not lengths[0].isascii() or not lengths[0].isdigit():
                raise RequestError("invalid Content-Length")
            if len(lengths[0]) > 4:
                raise RequestError("invalid body size", 413)
            size = int(lengths[0])
            if not 0 < size <= MAX_BODY:
                raise RequestError("invalid body size", 413)
            types = self.headers.get_all("Content-Type", [])
            if len(types) != 1 or types[0].split(";", 1)[0].strip().lower() != "application/json":
                raise RequestError("Content-Type must be application/json", 415)
            raw = self.rfile.read(size)
            if len(raw) != size:
                raise RequestError("incomplete body")
            value = decode_json(raw)
            try:
                result = self.server.state.dispatch(self.path, value)
            except OSError:
                self.server.state.backend_failed()
                raise RequestError("input backend failed; restart daemon", 503) from None
            status = 200
        except RequestError as error:
            status, result = error.status, {"ok": False, "error": str(error)}
        except OSError:
            self.close_connection = True
            return
        try:
            self.respond(status, result)
        except OSError:
            self.close_connection = True

    def method_not_allowed(self):
        self.respond(405, {"ok": False, "error": "POST only"})

    do_GET = do_HEAD = do_PUT = do_PATCH = do_DELETE = method_not_allowed
    do_OPTIONS = do_TRACE = do_CONNECT = method_not_allowed


def create_token_file(path, token):
    parent = os.stat(os.path.dirname(path))
    if not stat.S_ISDIR(parent.st_mode) or parent.st_mode & 0o077:
        raise RuntimeError("token directory must be private (chmod 700)")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="ascii") as output:
        output.write(token + "\n")
    return os.stat(path, follow_symlinks=False).st_ino


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("uinput", "shell"), default="uinput")
    parser.add_argument("--uinput", default="/dev/uinput")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--rotation", type=int, choices=(0, 90, 180, 270), default=0)
    parser.add_argument("--x-min", type=int, default=0)
    parser.add_argument("--x-max", type=int)
    parser.add_argument("--y-min", type=int, default=0)
    parser.add_argument("--y-max", type=int)
    parser.add_argument("--shell-prefix", default="",
                        help="trusted command prefix, e.g. '/path/to/rish -c'")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token-file", required=True,
                        help="new runtime token file in an existing private directory")
    args = parser.parse_args()
    if not (2 <= args.width <= 65536 and 2 <= args.height <= 65536
            and 1 <= args.port <= 65535):
        parser.error("invalid screen size or port")
    bounds = (args.x_min, args.x_max if args.x_max is not None else args.width - 1,
              args.y_min, args.y_max if args.y_max is not None else args.height - 1)
    if not (0 <= bounds[0] < bounds[1] <= 2147483647
            and 0 <= bounds[2] < bounds[3] <= 2147483647):
        parser.error("invalid ABS bounds")
    if args.backend == "shell" and (args.rotation or args.x_min or args.y_min
                                    or args.x_max is not None or args.y_max is not None):
        parser.error("shell uses current display pixels; rotation and ABS overrides must be zero/unset")
    if args.backend == "uinput" and args.shell_prefix:
        parser.error("--shell-prefix is only available with --backend shell")
    writer = server = state = worker = None
    token_path, token_inode = os.path.abspath(args.token_file), None
    stop = threading.Event()

    def watchdog():
        while not stop.wait(0.010):
            try:
                state.tick()
            except OSError:
                print("Input backend failed; daemon stopping", file=sys.stderr)
                try:
                    state.backend_failed()
                finally:
                    stop.set()

    try:
        if args.backend == "uinput":
            writer = UInputWriter(args.uinput, bounds, args.rotation)
        else:
            writer = ShellWriter(shlex.split(args.shell_prefix), args.width, args.height)
        state = ControlState(writer)
        token = secrets.token_urlsafe(32)
        server = ControlServer(args.port, token, state)
        token_inode = create_token_file(token_path, token)
        signal.signal(signal.SIGTERM, lambda *_: stop.set())
        signal.signal(signal.SIGINT, lambda *_: stop.set())
        worker = threading.Thread(target=watchdog, name="touch-watchdog", daemon=True)
        worker.start()
        print(f"Listening on 127.0.0.1:{args.port}; backend={args.backend}; token file={token_path}",
              flush=True)
        while not stop.is_set() and not state.failed:
            server.handle_request()
        stop.set()
        worker.join()
        return 1 if state.failed else 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Cannot start/control Android input: {error}. Check root, CONFIG_INPUT_UINPUT, "
              "device path, ioctl support, SELinux or Shizuku authorization.", file=sys.stderr)
        return 1
    finally:
        stop.set()
        if worker is not None:
            worker.join()
        if server is not None:
            server.server_close()
        if writer is not None:
            try:
                with state.lock if state is not None else threading.RLock():
                    writer.close()
            except OSError:
                pass
        if token_inode is not None:
            try:
                if os.stat(token_path, follow_symlinks=False).st_ino == token_inode:
                    os.unlink(token_path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    sys.exit(main())
