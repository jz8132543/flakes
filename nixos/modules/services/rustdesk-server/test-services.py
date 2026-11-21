"""Test real RustDesk rendezvous and authenticated relay using test keys."""
import asyncio
import base64
import importlib.util
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import ExitStack
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

runtime_spec = importlib.util.spec_from_file_location("runtime", Path(__file__).with_name("runtime.py"))
runtime = importlib.util.module_from_spec(runtime_spec)
runtime_spec.loader.exec_module(runtime)


def varint(value):
    output = bytearray()
    while value > 127:
        output.append((value & 127) | 128)
        value >>= 7
    return bytes(output + bytes([value]))


def field(number, value):
    return varint((number << 3) | 2) + varint(len(value)) + value


def request(pair, key):
    return field(18, field(2, pair.encode()) + field(6, key.encode()))


def protobuf_fields(data):
    def read_varint(offset):
        value = 0
        shift = 0
        while offset < len(data) and shift < 70:
            byte = data[offset]
            offset += 1
            value |= (byte & 0x7F) << shift
            if byte < 0x80:
                return value, offset
            shift += 7
        raise ValueError("invalid protobuf varint")

    fields = []
    offset = 0
    while offset < len(data):
        tag, offset = read_varint(offset)
        wire = tag & 7
        if wire == 0:
            value, offset = read_varint(offset)
        elif wire == 2:
            size, offset = read_varint(offset)
            value = data[offset:offset + size]
            if len(value) != size:
                raise ValueError("truncated protobuf field")
            offset += size
        elif wire in (1, 5):
            size = 8 if wire == 1 else 4
            value = data[offset:offset + size]
            offset += size
        else:
            raise ValueError("unsupported protobuf wire type")
        fields.append((tag >> 3, wire, value))
    return fields


def read_rendezvous_frame(stream):
    def receive_exact(size):
        result = bytearray()
        while len(result) < size:
            part = stream.recv(size - len(result))
            if not part:
                raise AssertionError("hbbs closed before the secure-tcp offer")
            result.extend(part)
        return bytes(result)

    first = receive_exact(1)
    width = (first[0] & 3) + 1
    prefix = first + receive_exact(width - 1)
    size = int.from_bytes(prefix, "little") >> 2
    return receive_exact(size)


def verify_secure_tcp_offer(port, public):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as stream:
        stream.settimeout(3)
        rendezvous = read_rendezvous_frame(stream)
    signed_keys = []
    for _, wire, value in protobuf_fields(rendezvous):
        if wire != 2:
            continue
        try:
            signed_keys.extend(
                item for field_number, nested_wire, item in protobuf_fields(value)
                if field_number == 1 and nested_wire == 2 and len(item) == 96
            )
        except ValueError:
            continue
    assert len(signed_keys) == 1, "hbbs did not send its signed secure-tcp phase-one key"
    Ed25519PublicKey.from_public_bytes(public).verify(signed_keys[0][:64], signed_keys[0][64:])


def port_group(offsets):
    for _ in range(100):
        sockets = []
        candidate = socket.socket()
        try:
            candidate.bind(("127.0.0.1", 0))
            base = candidate.getsockname()[1]
        finally:
            candidate.close()
        try:
            if base + max(offsets) > 65535 or base + min(offsets) < 1024:
                continue
            for offset in offsets:
                sock = socket.socket()
                sockets.append(sock)
                sock.bind(("127.0.0.1", base + offset))
            return base
        except OSError:
            continue
        finally:
            for sock in sockets:
                sock.close()
    raise RuntimeError("no free test port group")


async def relay_roundtrip(port, public):
    url = f"ws://127.0.0.1:{port + 2}"
    async with connect(url, open_timeout=3, proxy=None) as wrong:
        await wrong.send(request(uuid.uuid4().hex, "wrong-public-key"))
        try:
            await asyncio.wait_for(wrong.recv(), 3)
        except ConnectionClosed:
            pass
        else:
            raise AssertionError("relay accepted an invalid public key")

    pair = uuid.uuid4().hex
    async with connect(url, open_timeout=3, proxy=None) as first, connect(url, open_timeout=3, proxy=None) as second:
        await first.send(request(pair, public))
        await second.send(request(pair, public))
        payload = b"rustdesk-screen-payload" * 256
        await second.send(payload)
        assert await asyncio.wait_for(first.recv(), 3) == payload
        await first.send(b"return-control-payload")
        assert await asyncio.wait_for(second.recv(), 3) == b"return-control-payload"


def main():
    processes = []
    with tempfile.TemporaryDirectory(prefix="rustdesk-test-") as directory, ExitStack() as stack:
        root = Path(directory)
        test_credentials = root / "test-credentials"
        test_credentials.mkdir()
        key = Ed25519PrivateKey.generate()
        public = key.public_key()
        raw = public.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        public_text = base64.b64encode(raw).decode()
        private_pem = key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        (test_credentials / "public-key").write_bytes(
            public.public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)
        )
        (test_credentials / "private-key").write_bytes(private_pem)

        public_only = root / "relay-credentials"
        public_only.mkdir()
        (public_only / "public-key").write_bytes((test_credentials / "public-key").read_bytes())
        signal_credentials = root / "signal-credentials"
        signal_credentials.mkdir()
        (signal_credentials / "public-key").write_bytes((test_credentials / "public-key").read_bytes())
        (signal_credentials / "private-key").write_bytes(private_pem)
        env = dict(
            os.environ,
            ALWAYS_USE_RELAY="N",
            RUST_LOG="warn",
            SINGLE_BANDWIDTH="128",
            TOTAL_BANDWIDTH="1024",
            LIMIT_SPEED="128",
            DOWNGRADE_THRESHOLD="1",
        )
        relay = port_group([0, 2])
        signal = port_group([-1, 0, 2])

        def start(role, args, credentials):
            state = root / role
            state.mkdir()
            log = stack.enter_context(tempfile.TemporaryFile())
            role_env = dict(env, CREDENTIALS_DIRECTORY=str(credentials))
            executable = shutil.which("hbbs" if role == "signal" else "hbbr")
            process = subprocess.Popen(
                [
                    sys.executable,
                    str(Path(__file__).with_name("runtime.py").resolve()),
                    role,
                    executable,
                    *args,
                ],
                cwd=state,
                env=role_env,
                stdout=log,
                stderr=log,
            )
            processes.append((process, log))
            return state

        def wait_port(port):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if any(process.poll() is not None for process, _ in processes):
                    raise AssertionError("RustDesk server exited during startup")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                        return
                except OSError:
                    time.sleep(0.05)
            raise AssertionError("RustDesk listener did not start")

        try:
            relay_state = start("relay", ["--port", str(relay)], public_only)
            signal_state = start(
                "signal",
                ["--port", str(signal), "--key", "_", "--relay-servers", f"127.0.0.1:{relay},127.0.0.1:{relay}"],
                signal_credentials,
            )
            wait_port(relay + 2)
            wait_port(signal)

            stored = base64.b64decode((signal_state / "id_ed25519").read_bytes())
            assert stored == base64.b64decode(runtime.sodium_private(private_pem, raw))
            assert not (relay_state / "id_ed25519").exists()
            verify_secure_tcp_offer(signal, raw)

            # RegisterPeer (#6), with a nested id field, over the real hbbs UDP port.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.settimeout(3)
                udp.sendto(field(6, field(1, b"rustdesk-test-client")), ("127.0.0.1", signal))
                packet = udp.recv(4096)
                assert packet.startswith(varint((7 << 3) | 2))

            asyncio.run(relay_roundtrip(relay, public_text))
            assert all(process.poll() is None for process, _ in processes)
            print("hbbs key provisioning, signed secure-tcp offer, and UDP peer registration: passed")
            print("relay-only node has no signing private key: passed")
            print("hbbr invalid-key rejection and authenticated binary forwarding: passed")
        finally:
            for process, _ in processes:
                process.terminate()
            for process, _ in processes:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
