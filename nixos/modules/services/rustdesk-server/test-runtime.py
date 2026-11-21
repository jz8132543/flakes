import base64
import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).with_name("runtime.py"))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class IdentityTest(unittest.TestCase):
    def setUp(self):
        self.key = Ed25519PrivateKey.generate()
        self.public = self.key.public_key()
        self.raw_public = self.public.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        self.pem = self.key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        self.ssh = self.public.public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)

    def test_roundtrip_and_signature(self):
        public = runtime.public_bytes(self.ssh)
        self.assertEqual(public, self.raw_public)
        private = base64.b64decode(runtime.sodium_private(self.pem, public))
        self.assertEqual(len(private), 64)
        self.assertEqual(private[32:], public)
        recreated = Ed25519PrivateKey.from_private_bytes(private[:32])
        Ed25519PublicKey.from_public_bytes(private[32:]).verify(recreated.sign(b"rustdesk-test"), b"rustdesk-test")

    def test_mismatched_public_refused(self):
        with self.assertRaises(ValueError):
            runtime.sodium_private(self.pem, b"x" * 32)

    def test_idempotent_and_rotation_refused(self):
        original = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            os.chdir(directory)
            try:
                public = base64.b64encode(self.raw_public)
                private = runtime.sodium_private(self.pem, self.raw_public)
                runtime.provision_identity(private, public)
                runtime.provision_identity(private, public)
                self.assertEqual(stat.S_IMODE(Path("id_ed25519").stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(Path("id_ed25519.pub").stat().st_mode), 0o644)
                self.assertEqual(Path("id_ed25519").read_bytes().strip(), private)
                with self.assertRaises(ValueError):
                    runtime.provision_identity(b"changed-key", public)
                self.assertEqual(Path("id_ed25519").read_bytes().strip(), private)
            finally:
                os.chdir(original)

    def test_symlink_refused(self):
        original = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            os.chdir(directory)
            try:
                Path("outside").write_bytes(b"unchanged")
                Path("id_ed25519").symlink_to("outside")
                with self.assertRaises(ValueError):
                    runtime.provision_identity(b"a" * 88, base64.b64encode(self.raw_public))
                self.assertEqual(Path("outside").read_bytes(), b"unchanged")
            finally:
                os.chdir(original)


if __name__ == "__main__":
    unittest.main()
