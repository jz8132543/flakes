import copy
import http.server
import ipaddress
import json
import pathlib
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager


FIXTURES = json.loads(sys.argv[1])
SOURCES = [
    "172.20.232.0/26",
    "fd53:90fd:4bb6::/48",
    "127.0.0.0/8",
    "::1/128",
]
SING_BOX_SOURCES = SOURCES + ["::ffff:172.20.232.0/122", "::ffff:127.0.0.0/104"]
UUID = "00000000-0000-4000-8000-000000000001"


def route(config, source, domain, inbound="socks-in"):
    address = ipaddress.ip_address(source)
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        address = address.ipv4_mapped
    for rule in config["routing"]["rules"]:
        if inbound not in rule.get("inboundTag", [inbound]):
            continue
        if "source" in rule and not any(
            address in ipaddress.ip_network(net) for net in rule["source"]
        ):
            continue
        if "domain" in rule and not any(
            domain == suffix[7:] or domain.endswith("." + suffix[7:])
            for suffix in rule["domain"]
        ):
            continue
        return rule.get("outboundTag", rule.get("balancerTag"))
    return "direct"


for name, fixture in FIXTURES.items():
    core, config, args = fixture["core"], fixture["config"], fixture["args"]
    assert fixture["xrayEnabled"] == (core == "xray")
    assert fixture["singBoxEnabled"] == (core == "sing-box")
    assert fixture["templateMode"] == "0400"
    assert set(fixture["secretModes"].values()) == {"0400"}
    assert fixture["templateNames"] == [f"{core}-config.json"]
    assert fixture["restartUnits"] == [f"{core}.service"]
    assert fixture["templatePath"].startswith("/run/secrets/rendered/")
    assert (
        fixture["service"]["LoadCredential"] == f"config.json:{fixture['templatePath']}"
    )
    assert "CREDENTIALS_DIRECTORY" in str(fixture["service"]["ExecStart"])
    assert fixture["restartCommand"].endswith(f"restart {core}.service")
    assert fixture["service"]["MemoryMax"] == "192M"
    assert fixture["service"]["MemoryHigh"] == "150M"
    assert fixture["environment"]["GOMEMLIMIT"] == "128MiB"
    assert fixture["environment"]["GOGC"] == "50"
    assert not fixture["service"].get("LoadCredential", "").endswith("/nix/store")
    port = args.get("xrayPort", 8555)
    assert {8443, 8444, port} <= set(fixture["firewall"]["tcp"])
    assert {8443, 8444, port} <= set(fixture["firewall"]["udp"])
    assert 1080 not in fixture["firewall"]["tcp"]
    assert fixture["traefik"]["services"]["xray"]["loadbalancer"]["servers"] == [
        {"address": f"127.0.0.1:{port}"}
    ]
    assert fixture["traefik"]["routers"]["xray"]["tls"]["passthrough"]
    assert (
        args.get("serverName", "speedtest.dora.im")
        in fixture["traefik"]["routers"]["xray"]["rule"]
    )
    if core != "xray":
        assert config["route"]["final"] == "direct"
        if not args.get("ss"):
            assert config["inbounds"][0]["users"][0]["flow"] == "xtls-rprx-vision"
        assert (
            config["route"]["rules"][0]["rules"][1]["source_ip_cidr"]
            == SING_BOX_SOURCES
        )
        continue
    assert config["outbounds"][0] == {"protocol": "freedom", "tag": "direct"}
    primary = config["inbounds"][0]
    if args.get("ss"):
        assert primary["protocol"] == "shadowsocks"
        assert primary["settings"]["network"] == "tcp,udp"
    else:
        assert primary["settings"]["decryption"] == "none"
        assert primary["settings"]["clients"] == [{"id": "@xray/uuid@"}]
        stream = primary["streamSettings"]
        assert stream["network"] == "xhttp" and stream["security"] == "reality"
        assert stream["xhttpSettings"]["mode"] == args.get("xhttpMode", "stream-one")
        assert stream["xhttpSettings"]["path"] == args.get("xhttpPath", "/speedtest")
        assert stream["xhttpSettings"]["host"] == args.get(
            "serverName", "speedtest.dora.im"
        )
        assert stream["xhttpSettings"]["extra"] == {
            "xPaddingBytes": "100-1000",
            "xPaddingObfsMode": True,
            "xPaddingPlacement": "header",
            "xPaddingHeader": "X-Padding",
            "xPaddingMethod": "repeat-x",
        }
        assert (
            stream["realitySettings"]["target"]
            == f"{args.get('serverName', 'speedtest.dora.im')}:443"
        )
    if args.get("needProxy"):
        proxies = [
            out for out in config["outbounds"] if out["tag"].startswith("proxy-")
        ]
        assert len(proxies) == len(args.get("proxyHosts", ["fra0", "tyo0", "sjc0"]))
        for outbound in proxies:
            assert outbound["settings"]["encryption"] == "none"
            assert "flow" not in outbound["settings"]
            assert (
                outbound["streamSettings"]["xhttpSettings"]
                == FIXTURES["default"]["config"]["inbounds"][0]["streamSettings"][
                    "xhttpSettings"
                ]
            )
        if len(proxies) > 1:
            assert config["observatory"]["subjectSelector"] == ["proxy-"]
            assert (
                config["observatory"]["probeUrl"]
                == "https://speedtest.dora.im/generate_204"
            )
            assert config["routing"]["balancers"][0]["fallbackTag"] == "block"
            assert config["routing"]["balancers"][0]["strategy"]["type"] == "leastPing"
        else:
            assert "observatory" not in config and "balancers" not in config["routing"]
    if args.get("socks", True):
        assert config["routing"]["rules"][-2]["source"] == SOURCES
        assert config["routing"]["rules"][-1]["outboundTag"] == "block"
        expected = "proxy-0" if name == "single" else "proxy-balancer"
        for source in [
            "127.0.0.2",
            "::1",
            "172.20.232.1",
            "fd53:90fd:4bb6::1",
            "::ffff:172.20.232.1",
            "::ffff:127.0.0.1",
        ]:
            assert route(config, source, "example.com") == "direct"
            assert route(config, source, "api.openai.com") == (
                expected if args.get("needProxy") else "direct"
            )
        for source in [
            "172.20.232.64",
            "172.20.233.1",
            "fd53:90fd:4bb7::1",
            "198.51.100.1",
            "::ffff:172.20.233.1",
        ]:
            assert route(config, source, "example.com") == "block"
            assert route(config, source, "api.openai.com") == "block"
        assert route(config, "127.0.0.1", "notopenai.com") == "direct"
        assert route(config, "198.51.100.1", "api.openai.com", primary["tag"]) == (
            expected if args.get("needProxy") else "direct"
        )
    else:
        assert len(config["inbounds"]) == 1
        assert not any(
            "socks-in" in rule.get("inboundTag", [])
            for rule in config["routing"]["rules"]
        )
assert "iptables" in FIXTURES["default"]["firewall"]["extraCommands"]
assert (
    "ip6 saddr fd53:90fd:4bb6::/48" in FIXTURES["proxy"]["firewall"]["extraInputRules"]
)


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for(predicate, message, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(message)


@contextmanager
def process(command, directory, port):
    with (directory / "process.log").open("wb") as log:
        child = subprocess.Popen(command, stdout=log, stderr=log)
        try:

            def ready():
                assert child.poll() is None, f"Process failed: {directory.name}"
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                        return True
                except OSError:
                    return False

            wait_for(ready, f"Process did not listen: {directory.name}")
            yield child
        except Exception:
            log.flush()
            diagnostic = (directory / "process.log").read_text(errors="replace")
            for value in [private_key, public_key, UUID]:
                diagnostic = diagnostic.replace(value, "<test credential>")
            print(
                f"{directory.name}:\n" + "\n".join(diagnostic.splitlines()[-30:]),
                file=sys.stderr,
            )
            raise
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


def fetch_socks(proxy_port, host, target_port, proxy_host="127.0.0.1"):
    with socket.create_connection((proxy_host, proxy_port), timeout=10) as sock:

        def read_exact(length):
            data = b""
            while len(data) < length:
                chunk = sock.recv(length - len(data))
                assert chunk, "SOCKS reply ended early"
                data += chunk
            return data

        sock.sendall(b"\x05\x01\x00")
        assert read_exact(2) == b"\x05\x00"
        name = host.encode()
        sock.sendall(
            b"\x05\x01\x00\x03"
            + bytes([len(name)])
            + name
            + struct.pack("!H", target_port)
        )
        reply = read_exact(4)
        if reply[1] != 0:
            return b""
        remaining = {1: 6, 4: 18}.get(reply[3])
        if remaining is None:
            assert reply[3] == 3
            remaining = read_exact(1)[0] + 2
        read_exact(remaining)
        sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        data = b""
        try:
            while chunk := sock.recv(4096):
                data += chunk
        except ConnectionResetError:
            pass
        return data


class Handler(http.server.BaseHTTPRequestHandler):
    hits = 0

    def do_GET(self):
        Handler.hits += 1
        body = b"" if self.path == "/generate_204" else b"xhttp-ok"
        self.send_response(204 if not body else 200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    key_lines = subprocess.check_output(["xray", "x25519"], text=True)
    keys = dict(line.split(": ", 1) for line in key_lines.splitlines() if ": " in line)
    private_key = keys["PrivateKey"]
    public_key = keys["Password (PublicKey)"]

    def materialize(fixture):
        uuid = "AAAAAAAAAAAAAAAAAAAAAA==" if fixture["args"].get("ss") else UUID
        text = json.dumps(fixture["config"])
        replacements = {
            "uuid": uuid,
            "private_key": private_key,
            "public_key": public_key,
            "short_id": "0123456789abcdef",
        }
        for name, value in replacements.items():
            text = text.replace(f"@xray/{name}@", value)
        return json.loads(text)

    # These are disposable test keys, never the repository's SOPS credentials.
    for name, fixture in FIXTURES.items():
        path = root / f"{name}.json"
        path.write_text(json.dumps(materialize(fixture)))
        command = (
            ["xray", "run", "-test", "-config", str(path)]
            if fixture["core"] == "xray"
            else ["sing-box", "check", "-c", str(path)]
        )
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"{fixture['core']} parser rejected {name}: {result.stdout} {result.stderr}"
        )

    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost",
            "-keyout",
            str(root / "target.key"),
            "-out",
            str(root / "target.crt"),
        ],
        check=True,
        capture_output=True,
    )
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["h2", "http/1.1"])
    context.load_cert_chain(root / "target.crt", root / "target.key")
    tls_target = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    tls_target.socket = context.wrap_socket(tls_target.socket, server_side=True)
    http_target = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    for target in [tls_target, http_target]:
        threading.Thread(target=target.serve_forever, daemon=True).start()
    try:
        inbound_port = free_port()
        server = materialize(FIXTURES["default"])
        server["inbounds"] = server["inbounds"][:1]
        server["inbounds"][0].update(listen="127.0.0.1", port=inbound_port)
        reality = server["inbounds"][0]["streamSettings"]["realitySettings"]
        reality.update(
            target=f"127.0.0.1:{tls_target.server_port}", serverNames=["localhost"]
        )
        server["inbounds"][0]["streamSettings"]["xhttpSettings"]["host"] = "localhost"
        server["dns"] = {"hosts": {"api.openai.com": "127.0.0.1"}}
        # VLESS's upstream private-target protection stays enabled in production.
        server["outbounds"][0]["settings"] = {
            "domainStrategy": "UseIP",
            "finalRules": [
                {
                    "action": "allow",
                    "ip": ["127.0.0.0/8", "::1"],
                    "port": str(http_target.server_port),
                }
            ],
        }
        server_dir = root / "server"
        server_dir.mkdir()
        server_path = server_dir / "config.json"
        server_path.write_text(json.dumps(server))
        with process(
            ["xray", "run", "-config", str(server_path)], server_dir, inbound_port
        ):
            proxy_port = free_port()
            client = materialize(FIXTURES["proxy"])
            client["inbounds"] = [
                dict(client["inbounds"][1], listen="::", port=proxy_port)
            ]
            client["observatory"].update(
                probeUrl=f"http://127.0.0.1:{http_target.server_port}/generate_204",
                probeInterval="1s",
            )
            for outbound in client["outbounds"][2:]:
                outbound["settings"].update(
                    address="127.0.0.1",
                    port=inbound_port if outbound["tag"] == "proxy-1" else 9,
                )
                outbound["streamSettings"]["realitySettings"]["serverName"] = (
                    "localhost"
                )
                outbound["streamSettings"]["xhttpSettings"]["host"] = "localhost"
            client_dir = root / "client"
            client_dir.mkdir()
            client_path = client_dir / "config.json"
            client_path.write_text(json.dumps(client))
            with process(
                ["xray", "run", "-config", str(client_path)], client_dir, proxy_port
            ):
                wait_for(
                    lambda: fetch_socks(
                        proxy_port, "api.openai.com", http_target.server_port
                    ).endswith(b"xhttp-ok"),
                    "Health-checked relay never reached the target",
                    timeout=30,
                )
                assert fetch_socks(
                    proxy_port,
                    "api.openai.com",
                    http_target.server_port,
                    "::ffff:127.0.0.1",
                ).endswith(b"xhttp-ok")

            denied = copy.deepcopy(client)
            denied_port = free_port()
            denied["inbounds"][0]["port"] = denied_port
            # Map an unowned source to loopback without changing host interfaces.
            for rule in denied["routing"]["rules"]:
                if "source" in rule:
                    rule["source"] = [
                        source
                        for source in SOURCES
                        if "127.0.0.0" not in source and source != "::1/128"
                    ]
            denied_dir = root / "denied"
            denied_dir.mkdir()
            denied_path = denied_dir / "config.json"
            denied_path.write_text(json.dumps(denied))
            with process(
                ["xray", "run", "-config", str(denied_path)], denied_dir, denied_port
            ):
                assert not fetch_socks(
                    denied_port, "api.openai.com", http_target.server_port
                )
                assert not fetch_socks(
                    denied_port, "127.0.0.1", http_target.server_port
                )
                assert not fetch_socks(
                    denied_port,
                    "api.openai.com",
                    http_target.server_port,
                    "::ffff:127.0.0.1",
                )

            mihomo_port = free_port()
            shared = server["inbounds"][0]["streamSettings"]["xhttpSettings"]
            mihomo = {
                "mixed-port": mihomo_port,
                "bind-address": "127.0.0.1",
                "mode": "rule",
                "log-level": "silent",
                "proxies": [
                    {
                        "name": "relay",
                        "type": "vless",
                        "server": "127.0.0.1",
                        "port": inbound_port,
                        "uuid": UUID,
                        "tls": True,
                        "servername": "localhost",
                        "client-fingerprint": "chrome",
                        "reality-opts": {
                            "public-key": public_key,
                            "short-id": "0123456789abcdef",
                            "support-x25519mlkem768": True,
                        },
                        "network": "xhttp",
                        "xhttp-opts": {
                            "path": shared["path"],
                            "mode": shared["mode"],
                            "host": shared["host"],
                            "x-padding-bytes": shared["extra"]["xPaddingBytes"],
                            "x-padding-obfs-mode": shared["extra"]["xPaddingObfsMode"],
                            "x-padding-placement": shared["extra"]["xPaddingPlacement"],
                            "x-padding-header": shared["extra"]["xPaddingHeader"],
                            "x-padding-method": shared["extra"]["xPaddingMethod"],
                        },
                    }
                ],
                "rules": ["MATCH,relay"],
            }
            mihomo_dir = root / "mihomo"
            mihomo_dir.mkdir()
            mihomo_path = mihomo_dir / "config.json"
            mihomo_path.write_text(json.dumps(mihomo))
            with process(
                ["mihomo", "-d", str(mihomo_dir), "-f", str(mihomo_path)],
                mihomo_dir,
                mihomo_port,
            ):
                assert fetch_socks(
                    mihomo_port, "127.0.0.1", http_target.server_port
                ).endswith(b"xhttp-ok")
    finally:
        for target in [http_target, tls_target]:
            target.shutdown()
            target.server_close()

print(
    "Xray parser, routing/credentials/firewall, relay health selection, SOCKS denial and Mihomo XHTTP interop passed"
)
