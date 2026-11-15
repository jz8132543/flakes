import hashlib
import json
import os
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path


def initialize(data_dir, password_file):
    data_dir = Path(data_dir)
    config_file = data_dir / "app_config.json"
    backup_file = data_dir / "app_config.json.bak"
    config = None
    for candidate in (config_file, backup_file):
        if not candidate.exists():
            continue
        try:
            loaded = json.loads(candidate.read_text())
        except (ValueError, UnicodeError):
            continue
        if not isinstance(loaded, dict):
            continue
        if not isinstance(loaded.get("users", []), list):
            raise RuntimeError("Existing dashboard user list is invalid")
        config = loaded
        break

    if config is None:
        if config_file.exists() or backup_file.exists():
            raise RuntimeError("Existing dashboard configuration and backup are unusable")
        config = {
            "users": [],
            "accounts": [],
            "settings": {"allowRegistration": False},
        }

    users = config.setdefault("users", [])
    administrator = next(
        (
            user
            for user in users
            if isinstance(user, dict) and user.get("username") == "i"
        ),
        None,
    )
    changed = administrator is None
    if administrator is None:
        password = Path(password_file).read_text().rstrip("\r\n")
        if not password or password == "admin123":
            raise ValueError("A non-default administrator password is required")
        administrator = {
            "id": "u_" + uuid.uuid4().hex[:8],
            "username": "i",
            "passwordHash": hashlib.sha256(
                (password + "ctyun_salt_2026").encode()
            ).hexdigest(),
            "role": "admin",
            "maxQuota": 999,
            "createdAt": datetime.now(timezone.utc).isoformat(),
        }
        users.append(administrator)
    elif administrator.get("role") != "admin":
        raise RuntimeError("The i account must be an administrator before removing admin")

    removed = [
        user
        for user in users
        if isinstance(user, dict) and user.get("username") == "admin"
    ]
    documents = []
    if removed:
        if not administrator.get("id"):
            raise RuntimeError("The i administrator has no user ID")
        removed_ids = {user["id"] for user in removed if user.get("id")}
        config["users"] = [user for user in users if user not in removed]
        for account in config.get("accounts", []):
            if isinstance(account, dict) and account.get("ownerId") in removed_ids:
                account["ownerId"] = administrator["id"]
        sessions_file = data_dir / "auth_sessions.json"
        if sessions_file.exists():
            sessions = json.loads(sessions_file.read_text())
            if not isinstance(sessions, dict):
                raise RuntimeError("Existing dashboard session store is invalid")
            remaining = {
                token: session
                for token, session in sessions.items()
                if not isinstance(session, dict)
                or session.get("userId") not in removed_ids
            }
            if remaining != sessions:
                documents.append((sessions_file, remaining))
        changed = True

    if not changed:
        return
    documents.extend(((config_file, config), (backup_file, config)))
    for candidate, document in documents:
        with tempfile.NamedTemporaryFile(
            mode="w", dir=data_dir, prefix=".app_config-", delete=False
        ) as output:
            temporary = Path(output.name)
            try:
                json.dump(document, output, indent=2)
                output.flush()
                os.fsync(output.fileno())
                os.replace(temporary, candidate)
            finally:
                temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    initialize(*sys.argv[1:])
