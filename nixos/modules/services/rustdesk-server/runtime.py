"""Provision RustDesk identities from runtime credentials."""
import base64
import csv
import hmac
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)


def public_bytes(data):
    key = serialization.load_ssh_public_key(data.strip())
    if not isinstance(key, Ed25519PublicKey):
        raise TypeError("RustDesk requires an Ed25519 public key")
    return key.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def sodium_private(data, public):
    key = serialization.load_pem_private_key(data, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise TypeError("RustDesk requires an Ed25519 private key")
    actual = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if not hmac.compare_digest(actual, public):
        raise ValueError("RustDesk public and private credentials do not match")
    seed = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    return base64.b64encode(seed + actual)


def provision_identity(private, public):
    target = Path("id_ed25519")
    published = Path("id_ed25519.pub")
    if published.is_symlink():
        raise ValueError("refusing a symlinked RustDesk public identity")
    if published.exists() and published.read_bytes().strip() != public:
        raise ValueError("existing RustDesk public identity differs")
    if target.is_symlink():
        raise ValueError("refusing a symlinked RustDesk identity")
    if target.exists():
        if not hmac.compare_digest(target.read_bytes().strip(), private):
            raise ValueError("existing RustDesk identity differs; explicit operator migration is required")
    else:
        # Never let the upstream fallback silently generate another identity.
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(private + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
    os.chmod(target, 0o600)
    fd = os.open(published, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "wb") as stream:
        stream.write(public + b"\n")


def sync_admin():
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    password = (credentials / "admin-password").read_bytes().rstrip(b"\r\n")
    if not password or b"\0" in password:
        raise ValueError("invalid administrator password credential")
    password = password.decode("utf-8")
    sql = """\
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TEMP TABLE rustdesk_admin_password (value text) ON COMMIT DROP;
\\copy pg_temp.rustdesk_admin_password FROM '{password_file}' WITH (FORMAT csv)
DO $admin_sync$
DECLARE
  changed integer;
  secret text;
BEGIN
  SELECT value INTO STRICT secret FROM pg_temp.rustdesk_admin_password;
  UPDATE users
     SET username = 'i', password = crypt(secret, gen_salt('bf'))
   WHERE id = 1 AND is_admin
     AND (username <> 'i' OR password IS DISTINCT FROM crypt(secret, password));
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed > 0 THEN
    DELETE FROM user_tokens WHERE user_id = 1;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users
     WHERE id = 1 AND username = 'i' AND is_admin
       AND password = crypt(secret, password)
  ) THEN
    RAISE EXCEPTION 'administrator synchronization failed';
  END IF;
END
$admin_sync$;
COMMIT;
"""
    with tempfile.TemporaryDirectory(prefix="rustdesk-admin-") as directory:
        password_file = Path(directory) / "password.csv"
        with password_file.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream).writerow([password])
        password_file.chmod(0o600)
        script = Path(directory) / "sync.sql"
        script.write_text(sql.format(password_file=password_file), encoding="utf-8")
        script.chmod(0o600)
        result = subprocess.run(
            ["psql", "-X", "-q", "-w", "-v", "ON_ERROR_STOP=1", "-f", str(script)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        if result.returncode:
            detail = result.stderr.replace(password, "[redacted]").replace(directory, "[temporary-directory]").strip()
            raise RuntimeError("PostgreSQL administrator synchronization failed: " + detail[:500])


def main():
    mode = sys.argv[1]
    if mode == "public":
        print(base64.b64encode(public_bytes(Path(sys.argv[2]).read_bytes())).decode())
        return
    if mode == "admin":
        sync_admin()
        return
    if Path(".env").exists():
        raise ValueError("existing upstream .env may override declarative credentials; explicit migration is required")
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    public = public_bytes((credentials / "public-key").read_bytes())
    encoded = base64.b64encode(public)
    if mode == "signal":
        private = sodium_private((credentials / "private-key").read_bytes(), public)
        provision_identity(private, encoded)
        api_jwt = credentials / "api-jwt"
        if api_jwt.exists():
            os.environ["MUST_LOGIN"] = "Y"
            os.environ["RUSTDESK_API_JWT_KEY"] = api_jwt.read_text().strip()
        argv = sys.argv[2:]
        if "--key" in argv:
            index = argv.index("--key")
            if index + 1 >= len(argv) or argv[index + 1] != "_":
                raise ValueError("signal command must use the declarative key placeholder")
        else:
            argv.extend(["--key", "_"])
    elif mode == "relay":
        # Relay-only machines never receive the signing private key.
        os.environ["KEY"] = encoded.decode()
        argv = sys.argv[2:]
    else:
        raise ValueError("unknown RustDesk role")
    os.execv(argv[0], argv)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, TypeError, UnicodeError, subprocess.SubprocessError):
        raise SystemExit("RustDesk credential setup failed; inspect paths/key types and existing identity before retrying") from None
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
