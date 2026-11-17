"""Apply MacTahoe's native Plasma layout without restarting the desktop shell."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def run_command(command, timeout, capture=False):
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
        start_new_session=True,
    )
    try:
        output, error = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
        raise RuntimeError(f"Timed out after {timeout}s: {command[0]}") from None
    if process.returncode:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command[:4])}\n{error or ''}")
    return output


def parse_layout(script):
    try:
        text = script.split("var layout =", 1)[1].lstrip()
        layout, _ = json.JSONDecoder().raw_decode(text)
        if not isinstance(layout.get("panels"), list) or not isinstance(layout.get("desktops"), list):
            raise ValueError("Missing layout collections")
        return layout
    except (IndexError, ValueError, AttributeError) as error:
        raise RuntimeError("Unrecognized Plasma layout snapshot") from error


def has_declared_panels(layout):
    panels = layout["panels"]
    top = [p for p in panels if "org.kde.plasma.appmenu" in [a["plugin"] for a in p.get("applets", [])]]
    dock = [p for p in panels if "org.kde.plasma.icontasks" in [a["plugin"] for a in p.get("applets", [])]]
    if len(top) > 1 or len(dock) > 1:
        raise RuntimeError("Ambiguous native panel layout; refusing to replace user panels")
    return len(panels) >= 2 and len(top) == 1 and len(dock) == 1 and top[0] is not dock[0]


def desktop_screens(layout):
    screens = set()
    for desktop in layout["desktops"]:
        value = desktop.get("config", {}).get("/", {}).get("lastScreen")
        try:
            screen = int(value)
            if screen < 0:
                raise ValueError("Negative screen")
        except (ValueError, TypeError):
            raise RuntimeError("Cannot determine the active desktop screen") from None
        screens.add(screen)
    if not screens:
        raise RuntimeError("Plasma has no active desktop")
    return sorted(screens)


class Session:
    def __init__(self, args):
        self.args = args

    def bus(self, method, signature=None, arguments=()):
        command = [self.args.busctl, "--user", "--auto-start=no", "--json=short", "--timeout=3s",
                   "call", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", method]
        if signature:
            command += [signature, *map(str, arguments)]
        output = run_command(command, timeout=5, capture=True)
        if not output or not output.strip():
            return None
        data = json.loads(output)["data"]
        return data[0] if data else None

    def layout(self):
        script = self.bus("dumpCurrentLayoutJS")
        if isinstance(script, list):
            script = bytes(script).decode("utf-8")
        return parse_layout(script)

    def wait_ready(self):
        deadline = time.monotonic() + self.args.ready_timeout
        last_error = "No ready desktop"
        while time.monotonic() < deadline:
            try:
                layout = self.layout()
                if layout["desktops"]:
                    return layout
            except (RuntimeError, ValueError, TypeError, KeyError) as error:
                last_error = str(error)
            time.sleep(0.2)
        raise RuntimeError(f"Plasma did not become ready: {last_error}")

    def run_script(self, path):
        # Bash errexit exposes failures hidden by the generated run-once ERR trap.
        run_command([self.args.bash, "-e", str(path)], self.args.command_timeout)

    def apply(self):
        for path in (self.args.panels_script, self.args.panel_finalizer):
            if not path.is_file():
                raise RuntimeError(f"Missing declared resource: {path}")
        layout = self.wait_ready()
        if layout["panels"] and not has_declared_panels(layout):
            print("MacTahoe: retaining existing user panels; layout initialization skipped", flush=True)
            return
        if not layout["panels"]:
            # Invalidate only our panel marker when rollback lost the actual layout.
            (self.args.cache_dir / "last_run_desktop_script_panels").unlink(missing_ok=True)
            self.run_script(self.args.panels_script)
        result = self.bus("evaluateScript", "s", [self.args.panel_finalizer.read_text()])
        if json.loads(result) != self.args.expected_state:
            raise RuntimeError("Plasma did not retain the declared panel geometry")

        print("MacTahoe native panel geometry applied without changing appearance or launchers", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--busctl", required=True)
    parser.add_argument("--bash", required=True)
    for name in ("panels-script", "panel-finalizer", "cache-dir"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--expected-state", type=json.loads, required=True)
    parser.add_argument("--ready-timeout", type=float, default=15)
    parser.add_argument("--command-timeout", type=float, default=20)
    args = parser.parse_args()
    try:
        Session(args).apply()
    except (RuntimeError, ValueError, OSError, TypeError, KeyError) as error:
        print(f"MacTahoe session application failed: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
