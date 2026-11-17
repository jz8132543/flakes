"""One-shot, user-owned MacTahoe GNOME appearance transaction. No desktop is auto-started."""

import argparse
import ast
import configparser
from contextlib import contextmanager
import errno
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile


DEFAULT = {"appearance": "light", "effects": "visual"}
CSS_IMPORT = '/* mactahoe managed import */\n@import url("mactahoe.css");\n'
THEME_CSS = re.compile(r"/nix/store/[^/]+/share/themes/MacTahoe-(?:Visual-)?(?:Light|Dark)(?:-solid)?/gtk-4\.0/gtk\.css")
THEME_LEAF = re.compile(r"/nix/store/[^/]+-mactahoe-(?:visual|compatible)-(?:light|dark)-gtk4\.css")


def warn(message):
    print(f"MacTahoe: {message}", file=sys.stderr, flush=True)


def atomic(path, data=None, target=None, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".mactahoe-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            if target is None:
                stream.write(data)
                stream.flush()
                os.fchmod(stream.fileno(), mode)
                os.fsync(stream.fileno())
        if target is not None:
            os.unlink(temporary)
            os.symlink(target, temporary)
        try:
            os.replace(temporary, path)
        except OSError as error:
            # Impermanence can bind individual config files. Replacing that mount
            # returns EBUSY; update its existing inode, retaining the mount.
            if error.errno != errno.EBUSY or target is not None:
                raise
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                raise RuntimeError(f"Refusing unsafe mounted configuration file: {path}") from error
            descriptor = os.open(path, os.O_WRONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "wb") as stream:
                current = os.fstat(stream.fileno())
                if (info.st_dev, info.st_ino) != (current.st_dev, current.st_ino):
                    raise RuntimeError(f"Configuration file changed while opening: {path}")
                stream.write(data)
                stream.truncate()
                stream.flush()
                os.fsync(stream.fileno())
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


@contextmanager
def locked(directory):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError(f"Unsafe state directory: {directory}")
    directory.chmod(0o700)
    fd = os.open(directory / "appearance.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode) or os.fstat(fd).st_uid != os.getuid():
            raise RuntimeError("Unsafe appearance lock")
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def ini_value(text, group, key, value):
    """Replace only a named scalar, preserving comments and unrelated settings."""
    lines = text.splitlines(keepends=True)
    section = None
    found = False
    output = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if section == group and not found:
                output.append(f"{key}={value}\n")
                found = True
            section = stripped[1:-1]
        if section == group and stripped.split("=", 1)[0] == key:
            if not found:
                output.append(f"{key}={value}\n")
                found = True
        else:
            output.append(line if line.endswith("\n") else line + "\n")
    if not found:
        if section != group:
            output.append(f"\n[{group}]\n")
        output.append(f"{key}={value}\n")
    return "".join(output)


def read_ini(path, group, key, default):
    section = None
    for line in path.read_text().splitlines() if path.exists() else []:
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section == group and line.partition("=")[0].strip() == key:
            return line.partition("=")[2].strip()
    return default


class Transaction:
    def __init__(self):
        self.undo = []
        self.files = set()

    def snapshot(self, path):
        # Impermanence may link a config file into persistent storage. Keep that
        # link; only old Home Manager store links are detached into mutable files.
        if path.is_symlink() and not str(path.resolve()).startswith("/nix/store/"):
            path = path.resolve()
        if path in self.files:
            return path
        self.files.add(path)
        if path.is_symlink():
            target = os.readlink(path)
            self.undo.append(lambda: atomic(path, target=target))
        elif path.exists():
            if not path.is_file():
                raise RuntimeError(f"Not a regular configuration file: {path}")
            data, mode = path.read_bytes(), stat.S_IMODE(path.stat().st_mode)
            self.undo.append(lambda: atomic(path, data, mode=mode))
        else:
            self.undo.append(lambda: path.unlink(missing_ok=True))
        return path

    def write(self, path, text):
        if path.exists() and not path.is_symlink() and path.read_text() == text:
            return
        path = self.snapshot(path)
        atomic(path, text.encode())

    def ini(self, path, group, key, value):
        text = path.read_text() if path.exists() else ""
        self.write(path, ini_value(text, group, key, value))

    def leaf(self, path, target):
        if path.is_symlink() and os.readlink(path) == str(target):
            return
        # Unlike shared config, this leaf must itself be replaced, not followed.
        previous = os.readlink(path) if path.is_symlink() else None
        self.undo.append(lambda: atomic(path, target=previous) if previous else path.unlink(missing_ok=True))
        atomic(path, target=str(target))

    def rollback(self):
        errors = []
        for restore in reversed(self.undo):
            try:
                restore()
            except Exception as error:
                errors.append(str(error))
        return errors


class Appearance:
    def __init__(self, manifest, home=None, environ=None):
        self.manifest = manifest
        self.env = dict(os.environ if environ is None else environ)
        self.home = Path(home or self.env["HOME"])
        self.config = Path(self.env.get("XDG_CONFIG_HOME", self.home / ".config"))
        self.state_dir = Path(self.env.get("XDG_STATE_HOME", self.home / ".local/state")) / "mactahoe"
        self.state_file = self.state_dir / "state.json"
        self.schemas = {}

    def run(self, tool, *arguments):
        command = [self.manifest["commands"][tool], *map(str, arguments)]
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=15, env=self.env)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"Timed out: {tool}") from error
        if result.returncode:
            raise RuntimeError(f"{tool} failed: {result.stderr.strip()}")
        return result.stdout.strip()

    def bus(self, service, path, interface, method, signature=None, arguments=()):
        args = ["--user", "--auto-start=no", "--json=short", "--timeout=5s", "call",
                service, path, interface, method]
        if signature:
            args.extend([signature, *arguments])
        result = self.run("busctl", *args)
        data = json.loads(result)["data"] if result else []
        return data[0] if data else None

    def restore_session_environment(self):
        # System-initiated HM activation does not inherit the graphical shell's
        # environment. Query only an existing, owned user bus; never start one.
        runtime = Path(self.env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        bus = runtime / "bus"
        if not bus.exists():
            return
        info = bus.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            warn("No safe existing user bus; saving preferences for next login")
            return
        self.env.setdefault("XDG_RUNTIME_DIR", str(runtime))
        self.env.setdefault("DBUS_SESSION_BUS_ADDRESS", "unix:path=" + str(bus))
        try:
            variables = self.run("systemctl", "--user", "show-environment")
        except RuntimeError as error:
            warn(f"Cannot read existing graphical-session environment: {error}")
            return
        for line in variables.splitlines():
            key, separator, value = line.partition("=")
            if separator and key in ("XDG_CURRENT_DESKTOP", "WAYLAND_DISPLAY", "DISPLAY", "XDG_SESSION_TYPE"):
                self.env.setdefault(key, value)

    def desktop(self):
        desktop = self.env.get("XDG_CURRENT_DESKTOP", "").upper().split(":")
        if not (self.env.get("WAYLAND_DISPLAY") or self.env.get("DISPLAY")):
            return None
        if not self.env.get("DBUS_SESSION_BUS_ADDRESS"):
            return None
        if "GNOME" not in desktop:
            return None
        if self.bus("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                    "NameHasOwner", "s", ["org.gnome.Shell"]):
            return "GNOME"
        return None

    def gs(self, schema, operation, *args):
        directory = self.schemas.get(schema)
        prefix = ["--schemadir", directory] if directory else []
        return self.run("gsettings", *prefix, operation, schema, *args)

    def hdr(self):
        try:
            data = json.loads(self.run("busctl", "--user", "--auto-start=no", "--json=short", "--timeout=5s", "call",
                                       "org.gnome.Mutter.DisplayConfig", "/org/gnome/Mutter/DisplayConfig",
                                       "org.gnome.Mutter.DisplayConfig", "GetCurrentState"))
            modes = []
            def visit(value):
                if isinstance(value, dict):
                    if "color-mode" in value:
                        mode = value["color-mode"]
                        modes.append(mode.get("data") if isinstance(mode, dict) else mode)
                    for child in value.values():
                        visit(child)
                elif isinstance(value, list):
                    for child in value:
                        visit(child)
            visit(data)
            return any(mode not in (0, [0]) for mode in modes) if modes else None
        except (RuntimeError, ValueError, KeyError):
            return None

    def setting(self, tx, schema, path, key, value, optional=False):
        if optional and key not in self.gs(schema, "list-keys").splitlines():
            warn(f"Unavailable {schema}.{key}; keeping its existing value")
            return
        if self.gs(schema, "writable", key) != "true":
            raise RuntimeError(f"Setting is not writable: {schema}.{key}")
        encoded = json.dumps(value) if not isinstance(value, bool) else str(value).lower()
        full_path = path + key
        previous = self.run("dconf", "read", full_path)
        current = self.gs(schema, "get", key).removeprefix("@as ")
        try:
            same = current == encoded if isinstance(value, bool) else ast.literal_eval(current) == value
        except (ValueError, SyntaxError):
            same = current == encoded
        if same:
            return
        tx.undo.append(lambda: self.run("dconf", "write", full_path, previous) if previous
                       else self.run("dconf", "reset", full_path))
        self.gs(schema, "set", key, encoded)

    def resources(self, state):
        variant = self.manifest["variants"][state["effects"]][state["appearance"]]
        required = [variant["gtk3"], variant["gtk4"], variant["gtk4Leaf"], variant["shell"], variant["wallpaper"],
                    variant["icons"], variant["cursor"]]
        for resource in required:
            if not Path(resource).exists():
                raise RuntimeError(f"Missing declared resource: {resource}")
        leaf = self.config / "gtk-4.0/mactahoe.css"
        if os.path.lexists(leaf):
            known = {v["gtk4Leaf"] for effects in self.manifest["variants"].values() for v in effects.values()}
            if not leaf.is_symlink() or (os.readlink(leaf) not in known and not THEME_LEAF.fullmatch(os.readlink(leaf))):
                raise RuntimeError(f"Unknown GTK4 leaf preserved; move it aside explicitly: {leaf}")
        css = self.config / "gtk-4.0/gtk.css"
        if css.is_symlink() and not str(css.resolve()).startswith("/nix/store/"):
            raise RuntimeError(f"Unknown user CSS symlink preserved; no theme applied: {css}")
        return variant

    def shared(self, tx, state, variant):
        dark = state["appearance"] == "dark"
        for version in ("gtk-3.0", "gtk-4.0"):
            path = self.config / version / "settings.ini"
            for key, value in {"gtk-theme-name": variant["gtkTheme"], "gtk-icon-theme-name": variant["iconTheme"],
                               "gtk-cursor-theme-name": variant["cursorTheme"],
                               "gtk-application-prefer-dark-theme": "1" if dark else "0"}.items():
                tx.ini(path, "Settings", key, value)
        css = self.config / "gtk-4.0/gtk.css"
        text = css.read_text() if css.exists() else ""
        # Only retire our previous fixed-theme import, never arbitrary user CSS.
        legacy = re.compile(r'@import\s+url\(["\'](' + THEME_CSS.pattern + r')["\']\);\s*')
        text = legacy.sub("", text)
        if CSS_IMPORT not in text:
            if text.strip():
                warn(f"Preserving additional user GTK4 CSS in {css}; it may override the theme")
            text = CSS_IMPORT + text
        tx.write(css, text)
        tx.leaf(self.config / "gtk-4.0/mactahoe.css", variant["gtk4Leaf"])
        for key, value in {"gtk-theme": variant["gtkTheme"], "icon-theme": variant["iconTheme"],
                           "cursor-theme": variant["cursorTheme"],
                           "color-scheme": "prefer-dark" if dark else "prefer-light"}.items():
            self.setting(tx, "org.gnome.desktop.interface", "/org/gnome/desktop/interface/", key, value)

    def flatpak(self, tx):
        # nix-flatpak's merge mode retains removed declarations. Mask only our
        # old theme variables at user scope; do not rewrite system overrides.
        system = Path(self.manifest.get("flatpakSystemOverride", "/var/lib/flatpak/overrides/global"))
        user_root = Path(self.env.get("FLATPAK_USER_DIR", str(Path(
            self.env.get("XDG_DATA_HOME", self.home / ".local/share")) / "flatpak")))
        user = user_root / "overrides/global"
        if user.is_symlink():
            warn(f"Preserving symlinked Flatpak overrides: {user}; theme override may remain active")
            return

        def settings(path):
            values = configparser.ConfigParser(interpolation=None, strict=False)
            values.optionxform = str
            if path.is_file():
                values.read_string(path.read_text())
            return values

        system_values, user_values = settings(system), settings(user)
        system_env = system_values["Environment"] if system_values.has_section("Environment") else {}
        user_env = user_values["Environment"] if user_values.has_section("Environment") else {}
        known = {variant["gtkTheme"] for presets in self.manifest["variants"].values() for variant in presets.values()}
        old_theme = user_env.get("GTK_THEME") or system_env.get("GTK_THEME")
        if old_theme not in known:
            if old_theme:
                warn("Preserving custom Flatpak GTK_THEME; those applications may not follow appearance")
            return
        unset = set(user_values.get("Context", "unset-environment", fallback="").split(";"))
        keys = [key for key in ("GTK_THEME", "GTK_APPLICATION_PREFER_DARK_THEME")
                if key not in unset and
                (user_env.get(key, system_env.get(key)) in (known if key == "GTK_THEME" else {"0", "1"}))]
        if keys:
            tx.snapshot(user)
            self.run("flatpak", "override", "--user", *["--unset-env=" + key for key in keys])
            warn("Removed legacy Flatpak theme environment at user scope; reopen running Flatpak applications")

    def extension_policy(self, state):
        supported = {}
        for entry in self.manifest.get("extensions", []):
            try:
                metadata = json.loads(Path(entry["metadata"]).read_text())
                if metadata.get("uuid") != entry["uuid"] or self.manifest["gnomeMajor"] not in metadata.get("shell-version", []):
                    raise ValueError("metadata does not support this GNOME Shell version")
                for schema in entry.get("schemas", []):
                    self.schemas[schema] = entry["schemaDir"]
                supported[entry["role"]] = entry
            except (OSError, ValueError) as error:
                warn(f"Not enabling {entry['uuid']}: {error}")
        enabled = ast.literal_eval(self.gs("org.gnome.shell", "get", "enabled-extensions").removeprefix("@as "))
        disabled = ast.literal_eval(self.gs("org.gnome.shell", "get", "disabled-extensions").removeprefix("@as "))
        managed = set(self.manifest.get("conflictingExtensions", []))
        data_dirs = [self.env.get("XDG_DATA_HOME", str(self.home / ".local/share")),
                     *self.env.get("XDG_DATA_DIRS", "/run/current-system/sw/share").split(":")]
        for uuid in set(enabled + disabled):
            if "/" in uuid or uuid in (".", ".."):
                continue
            for directory in data_dirs:
                metadata_path = Path(directory) / "gnome-shell/extensions" / uuid / "metadata.json"
                try:
                    metadata = json.loads(metadata_path.read_text())
                    if metadata.get("uuid") == uuid and metadata.get("name") in self.manifest.get("conflictingExtensionNames", []):
                        managed.add(uuid)
                        break
                except (OSError, ValueError):
                    continue
        wanted = []
        for entry in self.manifest.get("extensions", []):
            if entry["role"].startswith("functional-"):
                # Seed installed desktop functionality but respect explicit user disables.
                if entry["role"] in supported and entry["uuid"] not in disabled and entry["uuid"] not in enabled:
                    enabled.append(entry["uuid"])
                continue
            managed.add(entry["uuid"])
            if entry["role"] in supported and (entry["role"] != "appindicator" or state["effects"] == "compatible"):
                wanted.append(entry["uuid"])
        return supported, [v for v in enabled if v not in managed] + wanted, \
            [v for v in disabled if v not in managed] + sorted(managed - set(wanted))

    def gnome(self, tx, state, variant):
        supported, enabled, disabled = self.extension_policy(state)
        self.setting(tx, "org.gnome.shell", "/org/gnome/shell/", "enabled-extensions", enabled)
        self.setting(tx, "org.gnome.shell", "/org/gnome/shell/", "disabled-extensions", disabled)
        wallpaper = Path(variant["wallpaper"]).as_uri()
        for key in ("picture-uri", "picture-uri-dark"):
            self.setting(tx, "org.gnome.desktop.background", "/org/gnome/desktop/background/", key, wallpaper)
        self.setting(tx, "org.gnome.desktop.background", "/org/gnome/desktop/background/", "picture-options", "zoom")
        self.setting(tx, "org.gnome.desktop.screensaver", "/org/gnome/desktop/screensaver/", "picture-uri", wallpaper)
        if "user-theme" in supported:
            self.setting(tx, "org.gnome.shell.extensions.user-theme", "/org/gnome/shell/extensions/user-theme/",
                         "name", variant["gtkTheme"])
        if "blur" in supported:
            # No application-wide opacity reduction; protect input candidates and trays.
            for area in ("panel", "overview", "dash-to-dock", "applications"):
                schema = "org.gnome.shell.extensions.blur-my-shell." + area
                value = area in ("overview", "dash-to-dock") or (area == "panel" and state["effects"] == "visual")
                self.setting(tx, schema, "/org/gnome/shell/extensions/blur-my-shell/" + area + "/",
                             "blur", value, optional=True)
        if "perfection" in supported:
            for key, value in {"theme": False, "clock-menu-position": 1, "notification-banner-position": 2}.items():
                self.setting(tx, "org.gnome.shell.extensions.just-perfection", "/org/gnome/shell/extensions/just-perfection/",
                             key, value, optional=True)

    def apply(self, command, effect=None, offline=False):
        with locked(self.state_dir):
            if self.state_file.is_symlink():
                raise RuntimeError("Refusing a symlinked appearance state")
            if self.state_file.exists():
                info = self.state_file.stat()
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                    raise RuntimeError("Unsafe appearance state file")
                self.state_file.chmod(0o600)
            state = json.loads(self.state_file.read_text()) if self.state_file.exists() else DEFAULT.copy()
            if not isinstance(state, dict) or state.get("appearance") not in ("light", "dark") or state.get("effects") not in ("visual", "compatible"):
                raise RuntimeError("Invalid appearance state; existing file left unchanged")
            state = {key: state[key] for key in DEFAULT}
            if command in ("light", "dark"):
                state["appearance"] = command
            elif command == "toggle":
                state["appearance"] = "dark" if state["appearance"] == "light" else "light"
            elif command == "effects":
                if effect not in ("visual", "compatible"):
                    raise RuntimeError("effects requires visual or compatible")
                state["effects"] = effect
            elif command != "apply":
                raise RuntimeError(f"Unknown appearance command: {command}")
            desktop = None if offline else self.desktop()
            tx = Transaction()
            try:
                if desktop:
                    effective = state.copy()
                    if state["effects"] == "visual":
                        hdr = self.hdr()
                        if hdr is not False:
                            effective["effects"] = "compatible"
                            warn(("HDR is active" if hdr else "HDR status is unavailable") +
                                 "; using compatible rendering this session, retaining visual preference and display settings")
                    variant = self.resources(effective)
                    self.shared(tx, effective, variant)
                    self.flatpak(tx)
                    self.gnome(tx, effective, variant)
                # Committing preferences is last. Offline means state-only, not
                # even GTK files or an inactive desktop's dconf keys are touched.
                tx.write(self.state_file, json.dumps(state, sort_keys=True) + "\n")
            except (Exception, KeyboardInterrupt) as error:
                errors = tx.rollback()
                suffix = "; rollback incomplete: " + "; ".join(errors) if errors else "; previous settings restored"
                raise RuntimeError(str(error) + suffix) from error
            print(f"MacTahoe {state['appearance']} + {state['effects']}: " +
                  (f"applied to {desktop}; reopen apps that cache styles" if desktop else "saved for next graphical login"))
            return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--offline", action="store_true", help="save preferences without changing desktop or GTK files")
    parser.add_argument("--restore-session", action="store_true", help="recover an existing graphical session's environment for HM activation")
    parser.add_argument("command", choices=("light", "dark", "toggle", "effects", "apply"))
    parser.add_argument("effect", nargs="?", choices=("visual", "compatible"))
    args = parser.parse_args()
    if (args.command == "effects") != (args.effect is not None):
        parser.error("only effects accepts (and requires) visual or compatible")
    if os.geteuid() == 0:
        parser.error("run as the desktop user, never root")
    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"interrupted by signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        appearance = Appearance(json.loads(args.manifest.read_text()))
        if args.restore_session and not args.offline:
            appearance.restore_session_environment()
        appearance.apply(args.command, args.effect, args.offline)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        warn(str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
