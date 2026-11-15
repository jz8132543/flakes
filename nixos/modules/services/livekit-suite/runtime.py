"""Runtime-only secrets, LiveKit/Coturn/Redis rendering and a bounded join API."""
import base64
import collections
import hashlib
import hmac
import http.server
import json
import mimetypes
import os
import re
import secrets
import socketserver
import sys
import threading
import time
import urllib.parse
import uuid
from pathlib import Path

API_KEY = "livekit-suite"


def read_master(path):
    value = Path(path).read_bytes().strip()
    if len(value) < 32:
        raise ValueError("master secret must contain at least 32 high-entropy bytes")
    return value


def derive(master, purpose):
    return hmac.new(master, ("livekit-suite/v1/" + purpose).encode(), hashlib.sha256).hexdigest()


def b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def jwt(master, room, identity, ttl, now=None):
    now = int(time.time()) if now is None else now
    payload = {
        "iss": API_KEY, "sub": identity, "nbf": now - 10, "iat": now, "exp": now + ttl,
        "jti": secrets.token_hex(16),
        "video": {"roomJoin": True, "room": room, "canPublish": True,
                  "canSubscribe": True, "canPublishData": True},
    }
    header = b64url(b'{"alg":"HS256","typ":"JWT"}')
    message = header + "." + b64url(json.dumps(payload, separators=(",", ":")).encode())
    signature = hmac.new(derive(master, "api").encode(), message.encode(), hashlib.sha256).digest()
    return message + "." + b64url(signature)


def ice_servers(master, servers, identity, ttl, now=None):
    now = int(time.time()) if now is None else now
    username = f"{now + ttl}:{identity}"
    credential = base64.b64encode(hmac.new(derive(master, "turn").encode(), username.encode(), hashlib.sha1).digest()).decode()
    return [dict(server, **({"username": username, "credential": credential}
            if any(url.startswith(("turn:", "turns:")) for url in server["urls"]) else {}))
            for server in servers]


def render_sfu(base, master):
    base["keys"] = {API_KEY: derive(master, "api")}
    base["redis"]["password"] = derive(master, "redis")
    for server in base["rtc"]["turn_servers"]:
        server["secret"] = derive(master, "turn")
    return json.dumps(base)


def render_turn(base, master, proxy=False):
    s = base["settings"]
    domain = base["turnDomain"]
    if not re.fullmatch(r"[A-Za-z0-9.-]+", domain):
        raise ValueError("invalid TURN realm")
    lines = [
        f"listening-port={s['port']}", f"tls-listening-port={0 if base['tls']['external'] else s['tlsPort']}",
        "fingerprint", "use-auth-secret", f"static-auth-secret={derive(master, 'turn')}",
        f"realm={domain}", f"server-name={domain}",
        f"min-port={s['proxyRelayStart'] if proxy else s['relayStart']}",
        f"max-port={s['proxyRelayEnd'] if proxy else s['relayEnd']}",
        f"relay-threads={s['relayThreads']}",
        f"user-quota={s['userQuota']}", f"total-quota={s['totalQuota']}",
        f"stale-nonce={s['staleNonce']}", "cli=0", "no-multicast-peers", "no-tcp-relay",
        "rfc5780=0", "stun-backward-compatibility=0", "log-file=stdout", "simple-log",
    ]
    # Block TURN access to private services and multicast; public SFU ICE remains allowed.
    for low, high in [
        ("0.0.0.0", "0.255.255.255"), ("10.0.0.0", "10.255.255.255"),
        ("100.64.0.0", "100.127.255.255"), ("127.0.0.0", "127.255.255.255"),
        ("169.254.0.0", "169.254.255.255"), ("172.16.0.0", "172.31.255.255"),
        ("192.168.0.0", "192.168.255.255"), ("224.0.0.0", "255.255.255.255"),
        ("::", "::1"), ("fc00::", "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
        ("fe80::", "febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
        ("ff00::", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
    ]:
        lines.append(f"denied-peer-ip={low}-{high}")
    for key in ("publicIpv4", "publicIpv6"):
        if base[key]:
            # This suite expects the advertised address to exist on a local interface.
            # NAT deployments must supply an explicit external-ip mapping in a future adapter.
            lines.extend([f"listening-ip={base[key]}", f"relay-ip={base[key]}"])
    if base["tls"]["external"]:
        lines.append("no-tls")
        if proxy:
            # Coturn's proxy listener replaces ordinary TCP listeners, so run it
            # separately from the normal UDP/TCP service with a disjoint relay pool.
            lines.extend(["no-udp", f"tcp-proxy-port={s['proxyPort']}"])
            if base["publicIpv4"] != "127.0.0.1":
                lines.append("listening-ip=127.0.0.1")
    else:
        credential_dir = os.environ["CREDENTIALS_DIRECTORY"]
        lines.extend([f"cert={credential_dir}/tls-cert", f"pkey={credential_dir}/tls-key"])
    return "\n".join(lines) + "\n"


def render_redis(base, master):
    bind = base["bind"]
    if not re.fullmatch(r"[A-Za-z0-9.:_-]+", bind):
        raise ValueError("invalid Redis bind address")
    memory = base["maxMemory"]
    if not re.fullmatch(r"[0-9]+[kKmMgG][bB]?", memory):
        raise ValueError("invalid Redis memory limit")
    binds = "127.0.0.1" if bind == "127.0.0.1" else f"127.0.0.1 {bind}"
    return f"""bind {binds}
port {base['port']}
protected-mode yes
requirepass {derive(master, 'redis')}
save ""
appendonly no
maxmemory {memory}
maxmemory-policy noeviction
logfile ""
"""


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, address, handler):
        self.slots = threading.BoundedSemaphore(32)
        super().__init__(address, handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


def make_web_server(base, master, assets):
    public = base["public"]
    limits = base["settings"]
    access = derive(master, "join")
    attempts = collections.deque()
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "LiveKitSuite"
        sys_version = ""

        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, fmt, *args):
            # No request URLs, Authorization values or tokens in logs.
            return

        def reply(self, status, value, content_type="application/json"):
            data = json.dumps(value).encode() if content_type == "application/json" else value
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' wss:; media-src 'self' blob:; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path == "/healthz":
                self.reply(200, {"ok": True})
            elif path in ("/config.json", "/.well-known/livekit-suite"):
                self.reply(200, public)
            elif path in ("/", "/index.html", "/app.js", "/style.css", "/livekit-client.umd.js"):
                filename = "index.html" if path == "/" else path[1:]
                target = Path(assets) / filename
                kind = "text/javascript" if filename.endswith(".js") else mimetypes.guess_type(filename)[0] or "application/octet-stream"
                self.reply(200, target.read_bytes(), kind)
            else:
                self.reply(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/api/session":
                self.reply(404, {"error": "not found"})
                return
            with lock:
                now = time.monotonic()
                while attempts and attempts[0] < now - 60:
                    attempts.popleft()
                if len(attempts) >= limits["requestsPerMinute"]:
                    self.reply(429, {"error": "rate limit"})
                    return
                attempts.append(now)
            origin = self.headers.get("Origin")
            if origin and origin != base["origin"]:
                self.reply(403, {"error": "origin denied"})
                return
            if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + access).encode()):
                self.reply(401, {"error": "invalid join key"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > limits["maxBodyBytes"] or self.headers.get("Transfer-Encoding"):
                    raise ValueError("invalid body length")
                if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                    raise ValueError("JSON required")
                data = json.loads(self.rfile.read(length))
                room = data.get("room", "")
                if not isinstance(room, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", room):
                    raise ValueError("invalid room name")
                chosen = data.get("node", "")
                nodes = {node["name"]: node["url"] for node in public["nodes"]}
                if not isinstance(chosen, str) or (chosen and chosen not in nodes):
                    raise ValueError("unknown node")
                identity = "client-" + str(uuid.uuid4())
                now = int(time.time())
                self.reply(200, {
                    "identity": identity, "serverUrl": nodes.get(chosen, public["serverUrl"]),
                    "token": jwt(master, room, identity, limits["tokenTtl"], now),
                    "iceServers": ice_servers(master, public["iceServers"], identity, base["turnTtl"], now),
                    "expiresAt": now + limits["tokenTtl"],
                })
            except (ValueError, TypeError, AttributeError, UnicodeError, RecursionError):
                self.reply(400, {"error": "invalid request"})

    return Server(("127.0.0.1", limits["port"]), Handler)


def main():
    mode = sys.argv[1]
    if mode == "access":
        print(derive(read_master(sys.argv[2]), "join"))
        return
    base = json.loads(Path(sys.argv[2]).read_text())
    master = read_master(Path(os.environ["CREDENTIALS_DIRECTORY"]) / "master")
    if mode == "web":
        make_web_server(base, master, sys.argv[3]).serve_forever()
        return
    render = {"sfu": render_sfu, "turn": render_turn,
              "turn-proxy": lambda base, master: render_turn(base, master, proxy=True),
              "redis": render_redis}[mode]
    target = Path(os.environ["SUITE_RUNTIME"]) / "config"
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(render(base, master))
    executable = sys.argv[3]
    args = {"sfu": ["--config", str(target)], "turn": ["-c", str(target)],
            "turn-proxy": ["-c", str(target)], "redis": [str(target)]}[mode]
    os.execv(executable, [executable] + args)


if __name__ == "__main__":
    main()
