"""Reconcile SOPS-managed credentials before the gateway starts."""

import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile


def main():
    accounts_dir, api_key_file, password_file = map(Path, sys.argv[1:])
    api_key = api_key_file.read_text().strip()
    password = password_file.read_text().strip()
    if not api_key or any(not 33 <= ord(char) <= 126 for char in api_key):
        raise ValueError("SOPS API key must be a non-empty, single-line ASCII token")
    if not password or password == "admin":
        raise ValueError("SOPS dashboard password must not be empty or the upstream default")

    settings_path = accounts_dir / "settings.json"
    data = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get("api_keys", []), list):
        raise ValueError("Invalid WorkBuddy settings; refusing to overwrite them")

    # Keep dashboard-managed keys and settings, but rotate the reserved SOPS key.
    data["api_keys"] = [
        {
            "id": "sops",
            "name": "SOPS (CPA shared key)",
            "key": api_key,
            "realm": "",
            "enabled": True,
        }
    ] + [entry for entry in data.get("api_keys", []) if entry.get("id") != "sops"]
    data["auth_disabled"] = False

    rounds = 120_000
    salt = data.get("panel_password_salt", "")
    try:
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt), rounds
        ).hex()
    except ValueError:
        digest = ""
    if (
        not salt
        or data.get("panel_password_rounds") != rounds
        or not hmac.compare_digest(digest, data.get("panel_password_hash", ""))
    ):
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt), rounds
        ).hex()
    data.update(
        panel_password_salt=salt,
        panel_password_rounds=rounds,
        panel_password_hash=digest,
        panel_password_default=False,
    )

    accounts_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=accounts_dir, prefix=".settings-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, settings_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
