"""Exercise real Nix GC in disposable stores, without contacting SSH hosts."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("nix", type=Path, help="Nix package directory (containing bin/nix)")
parser.add_argument("--client", type=Path, help="Use another sender package; test remote protocols only")
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--expect-failure", action="store_true", help="Confirm the bug in an unpatched Nix")
mode.add_argument("--native-cache", action="store_true", help="Test unpatched cache pull and root handoff")
args = parser.parse_args()
if args.native_cache and args.client:
    parser.error("--native-cache uses one local Nix package and cannot use --client")
bin_dir = args.nix.resolve() / "bin"
client_bin = args.client.resolve() / "bin" if args.client else bin_dir


def command(program, *arguments, env=None, check=True):
    return subprocess.run(
        [str(client_bin / program), *arguments],
        env=env, check=check, capture_output=True, text=True, timeout=60,
    )


def text_path(store, name, expression):
    return command(
        "nix", "--store", f"local?root={store}", "eval", "--impure", "--raw", "--expr",
        f"builtins.toFile {json.dumps(name)} ({expression})",
    ).stdout.strip()


with tempfile.TemporaryDirectory(prefix="nix-copy-gc-") as directory:
    base = Path(directory)
    source = base / "source"
    a = text_path(source, "gc-reused", '"dependency"')
    b = text_path(source, "gc-new", f"builtins.storePath {json.dumps(a)}")
    root = text_path(source, "gc-root", f"builtins.storePath {json.dumps(b)}")
    command(
        "nix-store", "--store", f"local?root={source}", "--realise", root,
        "--add-root", str(base / "source-root"), "--indirect",
    )
    cache = base / "cache"
    if args.native_cache:
        command("nix", "copy", "--from", f"local?root={source}", "--to", f"file://{cache}", root)
    fake_free = base / "free"
    fake_free.write_text("100")
    ssh = base / "ssh"
    ssh.write_text(
        f"#!{sys.executable}\n"
        "import os, sys\n"
        "if '-O' in sys.argv: sys.exit(1)\n"
        "print('started', flush=True)\n"
        "daemon = '--stdio' in ' '.join(sys.argv[1:])\n"
        "program = 'nix-daemon' if daemon else 'nix-store'\n"
        "os.execv(os.environ['TEST_NIX_BIN'] + '/' + program, [program,\n"
        "    '--store', 'local?root=' + os.environ['TEST_STORE'],\n"
        "    '--option', 'build-users-group', '',\n"
        "    '--option', 'min-free', '300', '--option', 'max-free', '10000',\n"
        "    '--option', 'min-free-check-interval', '0',\n"
        "    *(['--stdio'] if daemon else ['--serve', '--write'])])\n"
    )
    ssh.chmod(0o755)

    protocols = ["local"] if args.native_cache else (["ssh", "ssh-ng"] if args.client else ["local", "ssh", "ssh-ng"])
    for protocol in protocols:
        destination = base / f"store-{protocol}"
        local_uri = f"local?root={destination}"
        command("nix", "copy", "--from", f"local?root={source}", "--to", local_uri, a)
        garbage = text_path(destination, "gc-unrelated", '"garbage"')
        env = {
            **os.environ,
            "PATH": f"{base}:{os.environ['PATH']}",
            "TEST_NIX_BIN": str(bin_dir),
            "TEST_STORE": str(destination),
            "_NIX_TEST_FREE_SPACE_FILE": str(fake_free),
        }
        uri = local_uri if protocol == "local" else f"{protocol}://gc-test"
        gc_options = ["--option", "min-free", "300", "--option", "max-free", "10000",
                      "--option", "min-free-check-interval", "0"]
        persistent_root = base / "target-root"
        if args.native_cache:
            result = command(
                "nix-store", "--store", local_uri, "--realise", root,
                "--add-root", str(persistent_root), "--indirect",
                "--option", "substituters", f"file://{cache}",
                *gc_options, env=env, check=False,
            )
        else:
            result = command(
                "nix", "copy", "--from", f"local?root={source}", "--to", uri, root,
                *gc_options, env=env, check=False,
            )
        assert "running auto-GC" in result.stderr, result.stderr
        assert not (destination / garbage.lstrip("/")).exists(), result.stderr
        if args.expect_failure:
            assert result.returncode != 0 and "is not valid" in result.stderr, result.stderr
            print(f"{protocol}: reproduced deletion of a reused dependency")
        else:
            assert result.returncode == 0, result.stderr
            assert (destination / a.lstrip("/")).exists()
            assert (destination / root.lstrip("/")).exists()
            if args.native_cache:
                # The same realise process hands protection to a persistent root.
                command("nix-store", "--store", local_uri, "--gc")
                assert (destination / a.lstrip("/")).exists()
                assert (destination / root.lstrip("/")).exists()
                persistent_root.unlink()
            # Without a persistent root, these brand-new paths are collectable.
            command("nix-store", "--store", local_uri, "--gc")
            assert not (destination / a.lstrip("/")).exists()
            assert not (destination / root.lstrip("/")).exists()
            operation = "native cache pull with persistent root handoff" if args.native_cache else protocol
            print(f"{operation}: protected, unrelated garbage collected, roots released")
