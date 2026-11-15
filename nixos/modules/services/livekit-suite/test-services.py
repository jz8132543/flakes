"""Local binary smoke test, never touches deployed hosts or production credentials."""
import base64
import hashlib
import hmac
import importlib.util
import os
import shutil
import socket
import struct
import subprocess
import tempfile
import time
import urllib.request
from contextlib import ExitStack
from pathlib import Path

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).with_name("runtime.py"))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def attribute(kind, value):
    return struct.pack("!HH", kind, len(value)) + value + b"\0" * (-len(value) % 4)


def message(kind, body, transaction):
    return struct.pack("!HHI", kind, len(body), 0x2112A442) + transaction + body


def attributes(packet):
    result = {}
    offset = 20
    while offset + 4 <= len(packet):
        kind, length = struct.unpack("!HH", packet[offset:offset + 4])
        result[kind] = packet[offset + 4:offset + 4 + length]
        offset += 4 + length + (-length % 4)
    return result


def main():
    for binary in ("redis-server", "livekit-server", "turnserver"):
        if shutil.which(binary) is None:
            raise RuntimeError(f"required binary missing: {binary}")
    master = b"local-smoke-secret-not-production" * 2
    processes = []
    with tempfile.TemporaryDirectory(prefix="livekit-suite-smoke-") as temp, ExitStack() as stack:
        directory = Path(temp)

        def start(name, command, config):
            path = directory / (name + ".conf")
            path.write_text(config)
            log = stack.enter_context(tempfile.TemporaryFile())
            process = subprocess.Popen(command + [str(path)], stdout=log, stderr=log)
            processes.append((name, process, log))
            return process

        def ready(port):
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                for name, process, log in processes:
                    if process.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(f"{name} exited: {log.read().decode(errors='replace')}")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                        return
                except OSError:
                    time.sleep(0.05)
            raise RuntimeError(f"listener {port} not ready")

        try:
            redis_port, signal_port, rtc_port, turn_port, proxy_port, unused_tls = [free_port() for _ in range(6)]
            start("redis", ["redis-server"], runtime.render_redis({"bind": "127.0.0.1", "port": redis_port, "maxMemory": "64mb"}, master))
            ready(redis_port)
            base = {
                "port": signal_port, "bind_addresses": ["127.0.0.1"], "region": "local-test",
                "redis": {"address": f"127.0.0.1:{redis_port}"},
                "rtc": {"tcp_port": rtc_port, "port_range_start": 63000, "port_range_end": 63010,
                        "node_ip": "127.0.0.1", "use_external_ip": False, "enable_loopback_candidate": True,
                        "turn_servers": [], "packet_buffer_size_video": 2048, "packet_buffer_size_audio": 512,
                        "pli_throttle": {"low_quality": "500ms", "mid_quality": "1s", "high_quality": "1s"},
                        "congestion_control": {"enabled": True, "allow_pause": True, "use_send_side_bwe": True},
                        "allow_tcp_fallback": True},
                "room": {"enabled_codecs": [{"mime": codec} for codec in
                          ("audio/opus", "audio/red", "video/rtx", "video/av1", "video/h265", "video/vp9", "video/h264")]},
                "node_selector": {"kind": "regionaware", "sort_by": "sysload", "regions": [{"name": "local-test", "lat": 0, "lon": 0}]},
            }
            start("sfu", ["livekit-server", "--config"], runtime.render_sfu(base, master))
            ready(signal_port)
            with urllib.request.urlopen(f"http://127.0.0.1:{signal_port}/", timeout=3) as response:
                assert response.status == 200
            print("Redis + SFU startup and HTTP health: passed")

            turn_base = {"publicIpv4": "127.0.0.1", "publicIpv6": "", "turnDomain": "turn.example",
                         "tls": {"external": True}, "settings": {"port": turn_port, "tlsPort": unused_tls,
                         "proxyPort": proxy_port, "relayStart": 64000, "relayEnd": 64010,
                         "proxyRelayStart": 64500, "proxyRelayEnd": 64510, "relayThreads": 1,
                         "userQuota": 12, "totalQuota": 1024, "staleNonce": 600}}
            start("turn", ["turnserver", "-c"], runtime.render_turn(turn_base, master) + f"pidfile={directory}/turn.pid\ncpus=1\n")
            start("turn-proxy", ["turnserver", "-c"], runtime.render_turn(turn_base, master, proxy=True) + f"pidfile={directory}/proxy.pid\ncpus=1\n")
            ready(turn_port)
            ready(proxy_port)
            transaction = os.urandom(12)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.settimeout(3)
                client.sendto(message(0x0003, attribute(0x0019, b"\x11\0\0\0"), transaction), ("127.0.0.1", turn_port))
                packet = client.recv(4096)
                assert struct.unpack("!H", packet[:2])[0] == 0x0113, packet.hex()
                attrs = attributes(packet)
                username = f"{int(time.time()) + 600}:test-client".encode()
                password = base64.b64encode(hmac.new(runtime.derive(master, "turn").encode(), username, hashlib.sha1).digest())
                body = attribute(0x0019, b"\x11\0\0\0") + attribute(0x0006, username) + attribute(0x0014, attrs[0x0014]) + attribute(0x0015, attrs[0x0015])
                transaction = os.urandom(12)
                key = hashlib.md5(username + b":" + attrs[0x0014] + b":" + password).digest()
                prefix = message(0x0003, body + b"\0" * 24, transaction)[:-24]
                signed = body + attribute(0x0008, hmac.new(key, prefix, hashlib.sha1).digest())
                client.sendto(message(0x0003, signed, transaction), ("127.0.0.1", turn_port))
                packet = client.recv(4096)
                assert struct.unpack("!H", packet[:2])[0] == 0x0103, packet.hex()
            print("Coturn UDP TURN REST authenticated allocation: passed")

            with socket.create_connection(("127.0.0.1", proxy_port), timeout=3) as client:
                client.settimeout(3)
                source = socket.inet_aton("198.51.100.7")
                address = source + socket.inet_aton("127.0.0.1") + struct.pack("!HH", 34567, turn_port)
                proxy = b"\r\n\r\n\0\r\nQUIT\n" + b"\x21\x11" + struct.pack("!H", len(address)) + address
                transaction = os.urandom(12)
                client.sendall(proxy + message(0x0001, b"", transaction))
                packet = client.recv(4096)
                while len(packet) < 20 or len(packet) < 20 + struct.unpack("!H", packet[2:4])[0]:
                    chunk = client.recv(4096)
                    if not chunk:
                        raise RuntimeError("proxy connection closed before STUN response")
                    packet += chunk
                assert struct.unpack("!H", packet[:2])[0] == 0x0101, packet.hex()
                mapped = attributes(packet)[0x0020]
                decoded = bytes(a ^ b for a, b in zip(mapped[4:8], struct.pack("!I", 0x2112A442)))
                assert decoded == source, (decoded, source)
            print("Coturn PROXY v2 preserves client XOR-MAPPED-ADDRESS: passed")
        except BaseException:
            for name, process, log in processes:
                log.seek(0)
                print(f"{name} logs: {log.read().decode(errors='replace')}")
            raise
        finally:
            for _, process, _ in reversed(processes):
                process.terminate()
            for _, process, _ in reversed(processes):
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
