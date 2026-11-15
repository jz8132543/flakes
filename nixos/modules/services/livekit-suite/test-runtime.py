import base64
import hashlib
import hmac
import http.client
import importlib.util
import json
import threading
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).with_name("runtime.py"))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTest(unittest.TestCase):
    master = b"a" * 64

    def test_purpose_separation(self):
        values = {runtime.derive(self.master, purpose) for purpose in ("api", "turn", "redis", "join")}
        self.assertEqual(len(values), 4)
        self.assertTrue(all(len(value) == 64 for value in values))

    def test_jwt_signature_and_grants(self):
        token = runtime.jwt(self.master, "room1", "client1", 900, 12345)
        header, body, signature = token.split(".")
        def decode(value):
            return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
        self.assertEqual(json.loads(decode(header))["alg"], "HS256")
        payload = json.loads(decode(body))
        self.assertEqual(payload["iss"], runtime.API_KEY)
        self.assertEqual(payload["exp"], 13245)
        self.assertEqual(payload["video"]["room"], "room1")
        self.assertNotIn("roomAdmin", payload["video"])
        expected = hmac.new(runtime.derive(self.master, "api").encode(), f"{header}.{body}".encode(), hashlib.sha256).digest()
        self.assertEqual(decode(signature), expected)

    def test_ephemeral_turn(self):
        servers = [{"urls": ["stun:turn.example:3480"]}, {"urls": ["turns:turn.example:443?transport=tcp"]}]
        result = runtime.ice_servers(self.master, servers, "client1", 14400, 10000)
        self.assertNotIn("credential", result[0])
        self.assertEqual(result[1]["username"], "24400:client1")
        expected = base64.b64encode(hmac.new(runtime.derive(self.master, "turn").encode(), b"24400:client1", hashlib.sha1).digest()).decode()
        self.assertEqual(result[1]["credential"], expected)
        self.assertNotIn("credential", servers[1])

    def test_runtime_sfu(self):
        cfg = json.loads(runtime.render_sfu({"redis": {}, "rtc": {"turn_servers": [{"host": "turn.example"}]}}, self.master))
        self.assertEqual(cfg["keys"][runtime.API_KEY], runtime.derive(self.master, "api"))
        self.assertEqual(cfg["redis"]["password"], runtime.derive(self.master, "redis"))
        self.assertEqual(cfg["rtc"]["turn_servers"][0]["secret"], runtime.derive(self.master, "turn"))

    def test_redis_validation(self):
        base = {"bind": "primary.ts", "port": 6390, "maxMemory": "256mb"}
        text = runtime.render_redis(base, self.master)
        self.assertIn("protected-mode yes", text)
        self.assertIn("maxmemory-policy noeviction", text)
        with self.assertRaises(ValueError):
            runtime.render_redis(dict(base, bind="0.0.0.0\nprotected-mode no"), self.master)

    def test_turn_proxy_and_private_peer_denial(self):
        base = {"publicIpv4": "192.0.2.1", "publicIpv6": "", "turnDomain": "turn.example", "tls": {"external": True},
                "settings": {"port": 3480, "tlsPort": 5350, "proxyPort": 5351, "relayStart": 64000, "relayEnd": 64999,
                             "proxyRelayStart": 64500, "proxyRelayEnd": 64999, "relayThreads": 2,
                             "userQuota": 12, "totalQuota": 1024, "staleNonce": 600}}
        text = runtime.render_turn(base, self.master, proxy=True)
        self.assertIn("tcp-proxy-port=5351", text)
        self.assertIn("denied-peer-ip=100.64.0.0-100.127.255.255", text)
        self.assertIn("static-auth-secret=" + runtime.derive(self.master, "turn"), text)
        self.assertNotIn("no-auth", text)
        self.assertNotIn("tcp-proxy-port", runtime.render_turn(base, self.master))

    def test_authenticated_http_api(self):
        base = {"settings": {"port": 0, "tokenTtl": 900, "requestsPerMinute": 30, "maxBodyBytes": 4096},
                "origin": "https://livekit.example", "turnTtl": 14400,
                "public": {"serverUrl": "wss://livekit.example", "nodes": [{"name": "primary", "url": "wss://livekit.example"}],
                           "iceServers": [{"urls": ["turn:turn.example:3480?transport=udp"]}]}}
        server = runtime.make_web_server(base, self.master, "/nonexistent")
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        client = http.client.HTTPConnection(*server.server_address, timeout=2)
        try:
            client.request("GET", "/config.json")
            response = client.getresponse()
            public = json.loads(response.read())
            self.assertEqual(response.status, 200)
            self.assertNotIn("credential", public["iceServers"][0])
            self.assertNotIn(runtime.derive(self.master, "join"), json.dumps(public))
            client.request("POST", "/api/session", json.dumps({"room": "room1"}), {"Content-Type": "application/json"})
            response = client.getresponse()
            response.read()
            self.assertEqual(response.status, 401)
            headers = {"Content-Type": "application/json", "Authorization": "Bearer " + runtime.derive(self.master, "join")}
            for data, status in [({"room": "room1", "node": "primary"}, 200), ({"room": "../bad"}, 400), ({"room": "room1", "node": "invalid"}, 400), ([], 400)]:
                client.request("POST", "/api/session", json.dumps(data), headers)
                response = client.getresponse()
                result = json.loads(response.read())
                self.assertEqual(response.status, status)
                if status == 200:
                    self.assertIn("token", result)
                    self.assertIn("credential", result["iceServers"][0])
                    self.assertEqual(result["serverUrl"], "wss://livekit.example")
            client.request("POST", "/api/session", json.dumps({"room": "room1"}), dict(headers, Origin="https://other.example"))
            response = client.getresponse()
            response.read()
            self.assertEqual(response.status, 403)
            client.request("GET", "/../runtime.py")
            response = client.getresponse()
            response.read()
            self.assertEqual(response.status, 404)
        finally:
            client.close()
            server.shutdown()
            server.server_close()
            worker.join(2)


if __name__ == "__main__":
    unittest.main()
