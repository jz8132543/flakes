#!/usr/bin/env python3
"""Smoke-test the pinned RustDesk API against a native PostgreSQL database."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from pathlib import Path


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def stop_process(process):
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def run(args, **kwargs):
    kwargs.setdefault("timeout", 30)
    check = kwargs.pop("check", False)
    result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False, **kwargs)
    if check and result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed with exit status {result.returncode}")
    return result


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def wait(url, process):
    deadline = time.monotonic() + 30
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("RustDesk API process exited during startup")
        try:
            with opener.open(url, timeout=1) as response:
                if response.status == 200:
                    return response.read(256)
        except urllib.error.HTTPError as error:
            if error.code < 500:
                raise RuntimeError(f"RustDesk API returned HTTP {error.code}") from None
        except (OSError, TimeoutError):
            time.sleep(0.1)
    raise RuntimeError("RustDesk API did not become healthy")


@contextmanager
def api(binary, config, state, env):
    port = free_port()
    process = subprocess.Popen(
        [binary, "-c", str(config)],
        cwd=state,
        env={**env, "RUSTDESK_API_GIN_API_ADDR": f"127.0.0.1:{port}"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        base = f"http://127.0.0.1:{port}"
        wait(base + "/api/version", process)
        require(b"<html" in wait(base + "/_admin/", process).lower(), "admin endpoint did not return HTML")
        yield
    finally:
        stop_process(process)


@contextmanager
def postgres(root, base_env):
    data = root / "postgres"
    port = free_port()
    app_env = {
        **base_env,
        "PGHOST": "127.0.0.1",
        "PGPORT": str(port),
        "PGUSER": "rustdesk",
        "PGDATABASE": "rustdesk",
    }
    admin_env = {**app_env, "PGUSER": "postgres", "PGDATABASE": "postgres"}
    run(
        ["initdb", "-D", str(data), "--username=postgres", "--auth=trust", "--no-locale", "--encoding=UTF8"],
        env=admin_env,
        check=True,
    )
    ctl = ["pg_ctl", "-D", str(data), "-w", "-t", "15"]
    try:
        started = run(
            [*ctl, "-l", str(root / "postgres.log"), "-o", f"-h 127.0.0.1 -p {port} -c unix_socket_directories='' -c log_statement=all", "start"],
            env=admin_env,
        )
        if started.returncode:
            log = root / "postgres.log"
            detail = log.read_text().splitlines()[-1] if log.exists() and log.read_text().splitlines() else "no server log"
            error = started.stderr.strip()[-200:]
            raise RuntimeError(f"temporary PostgreSQL startup failed: {detail[:200]} {error}")
        psql = ["psql", "-X", "-w", "-v", "ON_ERROR_STOP=1", "-c"]
        run([*psql, "CREATE ROLE rustdesk LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE"], env=admin_env, check=True)
        run([*psql, "CREATE DATABASE rustdesk OWNER rustdesk"], env=admin_env, check=True)
        yield app_env
    finally:
        if (data / "postmaster.pid").is_file():
            stopped = run([*ctl, "-m", "fast", "stop"], env=admin_env)
            if stopped.returncode:
                run([*ctl, "-m", "immediate", "stop"], env=admin_env, check=True)


def main():
    binary = os.environ.get("RUSTDESK_API_BIN")
    resources = os.environ.get("RUSTDESK_API_RESOURCES")
    admin_sync = os.environ.get("RUSTDESK_ADMIN_SYNC")
    if not binary or not resources or not admin_sync:
        raise RuntimeError("smoke test requires pinned package paths")

    with tempfile.TemporaryDirectory(prefix="rustdesk-api-smoke-") as temporary:
        root = Path(temporary)
        config = root / "config.yaml"
        config.write_text(
            f"""lang: en
app:
  register: false
  show-swagger: 0
  web-client: 1
gin:
  api-addr: 127.0.0.1:0
  mode: release
  resources-path: {resources}
gorm:
  type: postgresql
  max-idle-conns: 2
  max-open-conns: 4
postgresql:
  host: 127.0.0.1
  port: "5432"
  user: ""
  password: ""
  dbname: "postgres"
  sslmode: disable
  time-zone: Asia/Shanghai
logger:
  level: error
  path: /dev/null
rustdesk:
  id-server: 127.0.0.1:21116
  relay-server: 127.0.0.1:21117
  api-server: http://127.0.0.1:21114
  personal: 1
"""
        )
        state = root / "state"
        state.mkdir(mode=0o700)
        (state / "data").mkdir(mode=0o700)
        (state / "runtime").mkdir(mode=0o700)
        (state / "conf").mkdir(mode=0o700)
        (state / "conf" / "admin").symlink_to(Path(resources) / "../conf/admin")
        (state / "resources").symlink_to(resources)

        base_env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("PG", "RUSTDESK_API_"))
        }
        with postgres(root, base_env) as pg:
            api_env = {
                **pg,
                "RUSTDESK_API_JWT_KEY": "rustdesk-api-smoke-only",
                "RUSTDESK_API_GORM_TYPE": "postgresql",
                "RUSTDESK_API_POSTGRESQL_HOST": pg["PGHOST"],
                "RUSTDESK_API_POSTGRESQL_PORT": pg["PGPORT"],
                "RUSTDESK_API_POSTGRESQL_USER": pg["PGUSER"],
                "RUSTDESK_API_POSTGRESQL_PASSWORD": "''",
                "RUSTDESK_API_POSTGRESQL_DBNAME": pg["PGDATABASE"],
                "RUSTDESK_API_POSTGRESQL_SSLMODE": "disable",
                "RUSTDESK_API_POSTGRESQL_TIME_ZONE": "Asia/Shanghai",
                "RUSTDESK_API_LOGGER_LEVEL": "error",
                "RUSTDESK_API_LOGGER_PATH": "/dev/null",
            }

            def query(statement):
                return run(
                    ["psql", "-XAtqw", "-v", "ON_ERROR_STOP=1", "-c", statement],
                    env=pg,
                    check=True,
                ).stdout.strip()

            with api(binary, config, state, api_env):
                require((Path(resources) / "admin/index.html").is_file(), "admin UI static assets missing")
                require(not any((state / "data").iterdir()), "PostgreSQL API created a SQLite data file")
                require(query("SELECT current_user = 'rustdesk' AND rolsuper = false FROM pg_roles WHERE rolname = current_user") == "t",
                        "API smoke test did not use the non-superuser PostgreSQL role")
                require(query("SELECT count(*) FROM users WHERE id = 1 AND username = 'admin' AND password <> '' AND is_admin") == "1",
                        "PostgreSQL API did not initialize administrator ID 1")
                require(query("SELECT count(*) FROM users") == "1", "PostgreSQL API created unexpected users")
                require(int(query("SELECT count(*) FROM groups")) >= 2, "PostgreSQL API did not initialize groups")
                require(int(query("SELECT count(*) FROM versions")) >= 1, "PostgreSQL API did not initialize versions")
                require(query("""
                    SELECT count(*) FROM (VALUES ('users'), ('groups'), ('versions'), ('address_books')) AS expected(name)
                    WHERE to_regclass('public.' || expected.name) IS NOT NULL
                """) == "4", "PostgreSQL API schema is incomplete")
                versions_before = query("SELECT coalesce(json_agg(json_build_array(id, version) ORDER BY id), '[]') FROM versions")

            credentials = root / "admin-credentials"
            credentials.mkdir(mode=0o700)
            admin_test_password = "smoke-admin,'quote"
            (credentials / "admin-password").write_text(admin_test_password + "\n", encoding="utf-8")
            (credentials / "admin-password").chmod(0o600)
            sync_env = {**pg, "CREDENTIALS_DIRECTORY": str(credentials)}
            run([sys.executable, "-B", admin_sync, "admin"], env=sync_env, check=True)
            admin_hash = query("SELECT password FROM users WHERE id = 1")
            require(query("SELECT username = 'i' AND is_admin AND password = crypt('smoke-admin,''quote', password) FROM users WHERE id = 1") == "t",
                    "administrator synchronization did not set the application account")
            require(admin_test_password not in (root / "postgres.log").read_text(),
                    "administrator password appeared in PostgreSQL statement logs")
            run([sys.executable, "-B", admin_sync, "admin"], env=sync_env, check=True)
            require(query("SELECT password FROM users WHERE id = 1") == admin_hash,
                    "idempotent administrator synchronization changed the password hash")
            admin_before = query("SELECT json_build_array(id, username, nickname, is_admin, group_id) FROM users WHERE id = 1")

            user_hash = "$2a$10$smoke-test-hash-never-used-for-login-000000000000000000"
            user_id = int(query("""
                INSERT INTO users (username, email, password, nickname, avatar, group_id, is_admin, status, remark)
                VALUES ('smoke-user', 'smoke@example.invalid', '%s', 'Smoke User', '', 1, false, 1, 'synthetic')
                RETURNING id
            """ % user_hash))
            row_id = int(query("""
                INSERT INTO address_books
                    (id, username, password, hostname, alias, platform, tags, hash, user_id,
                     force_always_relay, rdp_port, rdp_username, online, login_name, same_server,
                     collection_id, created_at, updated_at)
                VALUES
                    ('smoke-peer', 'desktop', '', 'synthetic-host', 'Synthetic', 'linux',
                     '["office", "smoke"]', '', %d, true, '', '', false, 'smoke-user', true,
                     0, TIMESTAMP '2025-02-03 17:19:29', TIMESTAMP '2025-02-03 17:19:29')
                RETURNING row_id
            """ % user_id))
            user_before = query(
                "SELECT json_build_array(id, username, password, nickname, is_admin, group_id) "
                f"FROM users WHERE id = {user_id}"
            )
            address_before = query(f"""
                SELECT json_build_array(row_id, id, user_id, tags::json, force_always_relay, online,
                    same_server, to_char(created_at, 'YYYY-MM-DD HH24:MI:SS'),
                    to_char(updated_at, 'YYYY-MM-DD HH24:MI:SS'), pg_typeof(created_at)::text)
                FROM address_books WHERE row_id = {row_id}
            """)
            require(json.loads(address_before)[3] == ["office", "smoke"], "address book JSON did not persist")
            require(json.loads(address_before)[4:7] == [True, False, True], "address book booleans did not persist")
            require(json.loads(address_before)[-1] == "timestamp without time zone", "address book timestamp type changed")
            require(admin_hash and json.loads(user_before)[2] == user_hash, "synthetic user hash was not stored")

            with api(binary, config, state, api_env):
                require(not any((state / "data").iterdir()), "PostgreSQL restart created a SQLite data file")
                require(query("SELECT password FROM users WHERE id = 1 AND is_admin") == admin_hash,
                        "administrator hash or role changed after restart")
                require(query("SELECT count(*) FROM users WHERE is_admin") == "1", "administrator was duplicated")
                require(query(f"SELECT json_build_array(id, username, nickname, is_admin, group_id) FROM users WHERE id = 1") == admin_before,
                        "administrator identity changed after restart")
                require(query(f"SELECT json_build_array(id, username, password, nickname, is_admin, group_id) FROM users WHERE id = {user_id}") == user_before,
                        "synthetic user data changed after restart")
                require(query(f"""
                    SELECT json_build_array(row_id, id, user_id, tags::json, force_always_relay, online,
                        same_server, to_char(created_at, 'YYYY-MM-DD HH24:MI:SS'),
                        to_char(updated_at, 'YYYY-MM-DD HH24:MI:SS'), pg_typeof(created_at)::text)
                    FROM address_books WHERE row_id = {row_id}
                """) == address_before, "address book data changed after restart")
                require(query("SELECT coalesce(json_agg(json_build_array(id, version) ORDER BY id), '[]') FROM versions") == versions_before,
                        "version rows changed after restart")
                require(query("SELECT current_user = 'rustdesk' AND rolsuper = false FROM pg_roles WHERE rolname = current_user") == "t",
                        "PostgreSQL application role is unexpectedly privileged")
                require(query("""
                    SELECT coalesce((
                        SELECT last_value >= (SELECT max(id) FROM users)
                        FROM pg_sequences
                        WHERE schemaname = 'public'
                          AND sequencename = split_part(pg_get_serial_sequence('public.users', 'id'), '.', 2)
                    ), false)
                """) == "t", "user ID sequence is not current")
                require(query("""
                    SELECT coalesce((
                        SELECT last_value >= (SELECT max(row_id) FROM address_books)
                        FROM pg_sequences
                        WHERE schemaname = 'public'
                          AND sequencename = split_part(pg_get_serial_sequence('public.address_books', 'row_id'), '.', 2)
                    ), false)
                """) == "t", "address book ID sequence is not current")

        print("RustDesk API native PostgreSQL initialization, persistence, and non-superuser smoke: passed")


if __name__ == "__main__":
    main()
