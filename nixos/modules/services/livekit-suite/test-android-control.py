"""Host-only tests; no root, Android, third-party modules or uinput required."""

import http.client
import importlib.util
import json
import os
import socket
import stat
import struct
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "android_control", Path(__file__).with_name("android-control.py"))
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
SESSION = "12345678-1234-4234-8234-123456789abc"
OTHER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"


def snapshot(seq=0, points=None, session=SESSION):
    return {"v": 1, "session": session, "seq": seq, "type": "snapshot",
            "points": [{"id": 0, "x": 0.25, "y": 0.75}] if points is None else points}


class ValidationTests(unittest.TestCase):
    def test_valid_multitouch_and_empty(self):
        points = [{"id": 0, "x": 0, "y": 1}, {"id": 9, "x": 1, "y": 0}]
        self.assertEqual(control.validate_snapshot(snapshot(points=points)),
                         (SESSION, 0, {0: (0.0, 1.0), 9: (1.0, 0.0)}))
        self.assertEqual(control.validate_snapshot(snapshot(points=[]))[2], {})

    def test_invalid_fields(self):
        for field, values in {
            "v": [True, 0, 2, 1.0],
            "session": [None, "not-a-uuid", SESSION.upper(), SESSION.replace("-", "")],
            "seq": [True, -1, 1.5, 2 ** 53, "1"],
            "type": ["down", "up", "cancel"],
            "points": [None, {}, [{"id": 0, "x": 0, "y": 0}] * 11],
        }.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    data = snapshot()
                    data[field] = value
                    with self.assertRaises(control.RequestError):
                        control.validate_snapshot(data)
        data = snapshot()
        data["extra"] = 1
        with self.assertRaises(control.RequestError):
            control.validate_snapshot(data)
        del data["extra"]
        del data["seq"]
        with self.assertRaises(control.RequestError):
            control.validate_snapshot(data)

    def test_invalid_contacts(self):
        invalid = [{"id": -1, "x": 0, "y": 0}, {"id": 10, "x": 0, "y": 0},
                   {"id": True, "x": 0, "y": 0}, {"id": 0, "x": True, "y": 0},
                   {"id": 0, "x": -0.1, "y": 0}, {"id": 0, "x": 0, "y": 1.1},
                   {"id": 0, "x": float("nan"), "y": 0}, {"id": 0, "x": float("inf"), "y": 0},
                   {"id": 0, "x": "0", "y": 0}, {"id": 0, "x": 0}, [],
                   {"id": 0, "x": 0, "y": 0, "pressure": 1}]
        for point in invalid:
            with self.subTest(point=point), self.assertRaises(control.RequestError):
                control.validate_snapshot(snapshot(points=[point]))
        with self.assertRaises(control.RequestError):
            control.validate_snapshot(snapshot(points=[{"id": 0, "x": 0, "y": 0}] * 2))

    def test_json_rejects_duplicates_nonfinite_and_bad_encoding(self):
        for raw in (b'{"v":1,"v":1}', b'{"x":NaN}', b'{"x":Infinity}',
                    b'\xff', b'{', b'[' * 1500, b' ' * 4097):
            with self.subTest(raw=raw[:40]), self.assertRaises(control.RequestError):
                control.decode_json(raw)
        with self.assertRaises(control.RequestError):
            control.validate_snapshot(control.decode_json(
                json.dumps(snapshot()).replace("0.25", "1e999").encode()))


class StateTests(unittest.TestCase):
    def setUp(self):
        self.now = 10.0
        self.frames = []
        self.writer = control.TouchWriter(self.frames.append, (100, 1100, 200, 2200))
        self.state = control.ControlState(self.writer, lambda: self.now)
        self.grant()
        self.frames.clear()

    def grant(self, session=SESSION, ttl_ms=60000):
        return self.state.dispatch("/grant", {"session": session,
                                               "controller": "controller-1", "ttl_ms": ttl_ms})

    def error(self, path, value, status):
        with self.assertRaises(control.RequestError) as raised:
            self.state.dispatch(path, value)
        self.assertEqual(raised.exception.status, status)

    def test_ordering_and_pinned_session(self):
        self.state.dispatch("/snapshot", snapshot(5))
        frames = len(self.frames)
        self.now += 0.1
        self.error("/snapshot", snapshot(5), 409)
        self.error("/snapshot", snapshot(4, points=[]), 409)
        self.error("/snapshot", snapshot(100, session=OTHER), 403)
        self.error("/grant", {"session": OTHER, "controller": "controller-2", "ttl_ms": 1000}, 409)
        self.assertEqual(len(self.frames), frames)
        self.assertEqual(self.state.last_snapshot, 10.0)
        self.state.dispatch("/snapshot", snapshot(8, points=[]))
        self.assertEqual(self.writer.active, {})

    def test_full_state_releases_missing_contact(self):
        self.state.dispatch("/snapshot", snapshot(points=[{"id": 0, "x": 0, "y": 0},
                                                         {"id": 9, "x": 1, "y": 1}]))
        self.state.dispatch("/snapshot", snapshot(1, points=[{"id": 9, "x": 0.5, "y": 0.5}]))
        frame = self.frames[-1]
        self.assertIn((control.EV_ABS, control.ABS_MT_SLOT, 0), frame)
        self.assertIn((control.EV_ABS, control.ABS_MT_TRACKING_ID, -1), frame)
        self.assertEqual(set(self.writer.active), {9})
        self.assertEqual(frame[0], (control.EV_KEY, control.BTN_TOUCH, 1))
        self.assertEqual(frame[-1], (control.EV_SYN, control.SYN_REPORT, 0))
        self.state.dispatch("/snapshot", snapshot(2, points=[]))
        self.assertEqual(self.frames[-1][0], (control.EV_KEY, control.BTN_TOUCH, 0))

    def test_tracking_lifetime(self):
        self.state.dispatch("/snapshot", snapshot(0))
        tracking = self.writer.active[0]
        self.state.dispatch("/snapshot", snapshot(1))
        self.assertEqual(self.writer.active[0], tracking)
        self.assertNotIn(control.ABS_MT_TRACKING_ID, [code for _, code, _ in self.frames[-1]])
        self.state.dispatch("/snapshot", snapshot(2, points=[]))
        self.state.dispatch("/snapshot", snapshot(3))
        self.assertNotEqual(self.writer.active[0], tracking)

    def test_tracking_wrap_does_not_duplicate_live_tracking_id(self):
        self.writer.snapshot({0: (0, 0)})
        self.writer.next_tracking = 0
        self.writer.snapshot({0: (0, 0), 1: (1, 1)})
        self.assertEqual(len(set(self.writer.active.values())), 2)

    def test_reset_requires_new_uuid_and_preserves_deadline(self):
        self.state.dispatch("/snapshot", snapshot(10))
        deadline = self.state.deadline
        self.error("/reset", {"session": SESSION, "new_session": SESSION}, 409)
        self.state.dispatch("/reset", {"session": SESSION, "new_session": OTHER})
        self.assertFalse(self.writer.active)
        self.assertEqual(self.state.last_seq, -1)
        self.assertEqual(self.state.deadline, deadline)
        self.error("/snapshot", snapshot(11), 403)
        self.error("/revoke", {"session": SESSION}, 403)
        self.state.dispatch("/snapshot", snapshot(0, session=OTHER))
        self.state.dispatch("/revoke", {"session": OTHER})
        self.assertIsNone(self.state.session)
        self.assertFalse(self.writer.active)
        self.error("/snapshot", snapshot(1, session=OTHER), 403)
        self.error("/grant", {"session": SESSION, "controller": "c", "ttl_ms": 1000}, 409)

    def test_watchdog_retains_sequence_and_pin(self):
        self.state.dispatch("/snapshot", snapshot(100))
        self.now += 0.249
        self.state.tick()
        self.assertTrue(self.writer.active)
        self.now += 0.002
        self.state.tick()
        self.assertFalse(self.writer.active)
        self.assertEqual(self.state.session, SESSION)
        self.assertEqual(self.state.last_seq, 100)
        self.error("/snapshot", snapshot(99), 409)
        count = len(self.frames)
        self.state.tick()
        self.assertEqual(len(self.frames), count)
        self.state.dispatch("/snapshot", snapshot(101))
        self.assertTrue(self.writer.active)

    def test_periodic_snapshots_refresh_watchdog(self):
        for seq in range(30):
            self.state.dispatch("/snapshot", snapshot(seq))
            self.now += 1 / 120
            self.state.tick()
            self.assertTrue(self.writer.active)
        self.now += 0.251
        self.state.tick()
        self.assertFalse(self.writer.active)

    def test_grant_expiry_cannot_be_extended_by_data(self):
        self.state.dispatch("/snapshot", snapshot())
        self.now = self.state.deadline
        self.error("/snapshot", snapshot(1), 403)
        self.assertIsNone(self.state.session)
        self.assertFalse(self.writer.active)
        self.grant(OTHER)
        self.assertEqual(self.state.session, OTHER)

    def test_invalid_payload_does_not_advance_or_refresh(self):
        self.state.dispatch("/snapshot", snapshot(1))
        self.now += 0.1
        self.error("/snapshot", snapshot(2, points=[{"id": 10, "x": 0, "y": 0}]), 400)
        self.assertEqual(self.state.last_seq, 1)
        self.assertEqual(self.state.last_snapshot, 10)

    def test_grant_validation(self):
        self.state.dispatch("/revoke", {"session": SESSION})
        for controller in ("", "a" * 257, "bad\nidentity", None):
            self.error("/grant", {"session": OTHER, "controller": controller, "ttl_ms": 1000}, 400)
        for ttl in (0, -1, True, 3600001):
            self.error("/grant", {"session": OTHER, "controller": "c", "ttl_ms": ttl}, 400)

    def test_rotations_and_absolute_bounds(self):
        expected = {0: (350, 1700), 90: (850, 1700),
                    180: (850, 700), 270: (350, 700)}
        for rotation, coordinates in expected.items():
            writer = control.TouchWriter(self.frames.append, self.writer.bounds, rotation)
            self.assertEqual(writer.coordinates(0.25, 0.75), coordinates)
            writer.snapshot({9: (0.25, 0.75)})
            self.assertIn((control.EV_ABS, control.ABS_MT_POSITION_X, coordinates[0]), self.frames[-1])

    def test_backend_failure_revokes_and_fails_closed(self):
        self.state.dispatch("/snapshot", snapshot())
        self.state.backend_failed()
        self.assertIsNone(self.state.session)
        self.assertFalse(self.writer.active)
        self.error("/snapshot", snapshot(1), 503)

    def test_backend_failure_still_revokes_if_release_write_fails(self):
        self.state.dispatch("/snapshot", snapshot())
        with patch.object(self.writer, "emit", side_effect=OSError("device gone")):
            self.state.backend_failed()
        self.assertIsNone(self.state.session)
        self.assertFalse(self.state.contacts)
        self.assertTrue(self.state.failed)


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.state = control.ControlState(control.TouchWriter(lambda _: None, (0, 100, 0, 100)))
        self.server = control.ControlServer(0, "test-secret", self.state)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, method="POST", path="/status", value=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=2)
        try:
            connection.request(method, path, json.dumps({} if value is None else value),
                               headers if headers is not None else {
                                   "Authorization": "Bearer test-secret", "Content-Type": "application/json"})
            response = connection.getresponse()
            body = response.read()
            return response.status, json.loads(body) if body else None
        finally:
            connection.close()

    def test_loopback_post_only_and_auth(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        self.assertEqual(self.request()[0], 200)
        for method in ("GET", "HEAD", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE", "CONNECT"):
            self.assertEqual(self.request(method=method)[0], 405)
        self.assertEqual(self.request(headers={"Content-Type": "application/json"})[0], 401)
        self.assertEqual(self.request(headers={"Authorization": "Bearer wrong"})[0], 401)
        self.assertEqual(self.request(headers={"Authorization": "Bearer test-secret",
                                              "Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.request(headers={"Authorization": "Bearer test-secret",
                                              "Content-Type": "application/json", "Origin": "https://evil.test"})[0], 403)
        self.assertEqual(self.request(path="/missing")[0], 404)

    def test_authenticated_grant_reset_revoke(self):
        self.assertEqual(self.request(path="/grant", value={"session": SESSION,
                              "controller": "c", "ttl_ms": 60000})[0], 200)
        self.assertEqual(self.request(path="/snapshot", value=snapshot())[0], 200)
        self.assertEqual(self.request(path="/snapshot", value=snapshot())[0], 409)
        self.assertEqual(self.request(path="/reset", value={"session": SESSION, "new_session": OTHER})[0], 200)
        self.assertEqual(self.request(path="/revoke", value={"session": OTHER})[0], 200)

    def test_http_framing_and_duplicate_auth(self):
        for suffix, status in (("Content-Length: 2\r\nAuthorization: Bearer test-secret\r\n", 401),
                               ("Content-Length: 2\r\nTransfer-Encoding: chunked\r\n", 400),
                               ("Content-Length: 2\r\nContent-Length: 2\r\n", 400),
                               ("Content-Length: 4097\r\n", 413),
                               ("Content-Length: " + "9" * 5000 + "\r\n", 413)):
            with socket.create_connection(("127.0.0.1", self.port), timeout=2) as connection:
                raw = ("POST /status HTTP/1.0\r\nAuthorization: Bearer test-secret\r\n"
                       "Content-Type: application/json\r\n" + suffix + "\r\n{}")
                connection.sendall(raw.encode())
                self.assertIn(f" {status} ".encode(), connection.recv(4096))

    def test_slow_http_does_not_block_independent_watchdog(self):
        self.request(path="/grant", value={"session": SESSION, "controller": "c", "ttl_ms": 60000})
        self.request(path="/snapshot", value=snapshot())
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as connection:
            connection.sendall(b"POST /snapshot HTTP/1.0\r\nContent-Length: 20\r\n"
                               b"Authorization: Bearer test-secret\r\nContent-Type: application/json\r\n\r\n{")
            self.state.last_snapshot -= 1
            self.state.tick()
            self.assertFalse(self.state.contacts)
            self.assertFalse(self.state.failed)


class PlatformTests(unittest.TestCase):
    def test_uinput_requires_root_before_opening_device(self):
        with patch.object(control.os, "geteuid", return_value=10000), \
                self.assertRaisesRegex(RuntimeError, "root"):
            control.UInputWriter("/nonexistent", (0, 100, 0, 100), 0)

    def test_ioctl_layouts(self):
        self.assertEqual(struct.calcsize("=HHHH80sI"), 92)
        self.assertEqual(struct.calcsize("=H2xiiiiii"), 28)
        self.assertEqual(control.ioctl_code(1, 3, 92), 0x405C5503)
        self.assertEqual(control.ioctl_code(2, 45, 4), 0x8004552D)
        self.assertIn(control.INPUT_EVENT.size, (16, 24))

    def test_uinput_initialization_writes_and_idempotent_destroy(self):
        calls, frames = [], []

        def ioctl(fd, operation, value=0, *args):
            calls.append(operation)
            if operation == control.ioctl_code(2, 45, 4):
                value[0] = 5
            return 0

        def write(fd, data):
            frames.extend(control.INPUT_EVENT.iter_unpack(data))
            return len(data)

        with patch.object(control.os, "geteuid", return_value=0), \
                patch.object(control.os, "open", return_value=123), \
                patch.object(control.os, "fstat", return_value=SimpleNamespace(st_mode=stat.S_IFCHR)), \
                patch.object(control.os, "write", side_effect=write), \
                patch.object(control.os, "close") as close, \
                patch.object(control.fcntl, "ioctl", side_effect=ioctl):
            writer = control.UInputWriter("/dev/uinput", (0, 1079, 0, 2399), 0)
            writer.snapshot({0: (0.5, 0.5), 9: (1, 1)})
            writer.close()
            writer.close()
            close.assert_called_once_with(123)
        self.assertIn(control.ioctl_code(0, 1), calls)
        self.assertEqual(calls.count(control.ioctl_code(0, 2)), 1)
        self.assertIn((0, 0, control.EV_ABS, control.ABS_MT_TRACKING_ID, -1), frames)
        self.assertEqual(frames[-1], (0, 0, control.EV_SYN, control.SYN_REPORT, 0))

    def test_private_runtime_token_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "token")
            inode = control.create_token_file(path, "random-runtime-secret")
            self.assertEqual(os.stat(path).st_ino, inode)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                control.create_token_file(path, "replacement")
            os.chmod(directory, 0o755)
            with self.assertRaisesRegex(RuntimeError, "private"):
                control.create_token_file(os.path.join(directory, "other"), "secret")

    def test_shell_fallback_only_completes_on_empty_snapshot(self):
        class Result:
            stdout = "2000\n"

            def poll(self):
                return 0

        with patch.object(control.ShellWriter, "run_command", return_value=Result()) as run:
            writer = control.ShellWriter(["/private/rish", "-c"], 1080, 2400)
            run.reset_mock()
            writer.snapshot({0: (0.2, 0.3)})
            writer.snapshot({0: (0.6, 0.7)})
            run.assert_not_called()
            writer.snapshot({})
            args = run.call_args.args[0]
            self.assertEqual(args[:3], ["/system/bin/input", "touchscreen", "swipe"])
            self.assertLessEqual(int(args[-1]), 1000)
            run.reset_mock()
            writer.snapshot({0: (0.5, 0.5)})
            writer.release()
            writer.snapshot({})
            run.assert_not_called()
            state = control.ControlState(writer)
            state.dispatch("/grant", {"session": SESSION, "controller": "c", "ttl_ms": 1000})
            with self.assertRaises(control.RequestError) as raised:
                state.dispatch("/snapshot", snapshot(points=[{"id": 0, "x": 0, "y": 0},
                                                            {"id": 1, "x": 1, "y": 1}]))
            self.assertEqual(raised.exception.status, 422)


if __name__ == "__main__":
    unittest.main(verbosity=2)
