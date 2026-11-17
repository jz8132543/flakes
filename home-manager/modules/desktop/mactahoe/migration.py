"""Audit explicitly retired Golden Gate/Liquid assets; only --apply changes HOME.

Rollback restores only affected shared keys/imports, not retired theme sources.
It refuses to overwrite keys changed again after migration. All output omits
configuration values; the private journal contains only the affected values.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile


WIDGETS = {
    "org.kde.mac.tahoe.liquid.globalmenu": "org.kde.plasma.appmenu",
    "org.kde.mac-tahoe-liquid-kde.launcher": "org.kde.plasma.kickoff",
    "org.kde.mac.tahoe.liquid.icontasks": "org.kde.plasma.icontasks",
    "org.kde.mac.tahoe.liquid.taskmanager": "org.kde.plasma.icontasks",
    "org.kde.mac-tahoe-liquid-kde.trashcan": "org.kde.plasma.trash",
}
THEMES = ("MacTahoeLiquidKde-Light", "MacTahoeLiquidKde-Dark",
          "MacGoldenGateLiquidKde-Light", "MacGoldenGateLiquidKde-Dark")
LEGACY = re.compile(
    r"(?<![A-Za-z0-9.-])(?:[a-z0-9]{32}-)?(?:__aurorae__svg__)?"
    r"(?:MacTahoeLiquidKde(?:-Icons)?(?:-dark|-Dark|-Light)?"
    r"|MacGoldenGate(?:LiquidKde(?:-Light|-Dark)?)?"
    r"|MacTahoeLiquidKde(?:Light|Dark)"
    r"|mac-tahoe-liquid-kde(?:Dark)?|macos-(?:golden-gate|tahoe)-liquid-kde"
    r"|org\.kde\.mac\.tahoe\.liquid(?:\.[a-z]+)?"
    r"|org\.kde\.mac-tahoe-liquid-kde(?:\.[a-z]+)?"
    r"|golden-gate-plugin-paths)(?:-[0-9][A-Za-z0-9.+-]*)?(?:\.colors|\.sh)?"
    r"(?=$|[/\s\"'\]);,:}])"
)
CONFIGS = ("kwinrc", "kdeglobals", "plasmarc", "kcminputrc", "Kvantum/kvantum.kvconfig",
           "gtk-3.0/settings.ini", "gtk-4.0/settings.ini",
           "plasma-org.kde.plasma.desktop-appletsrc")
DCONF_KEYS = (
    "/org/gnome/desktop/interface/gtk-theme",
    "/org/gnome/desktop/interface/icon-theme",
    "/org/gnome/desktop/interface/cursor-theme",
    "/org/gnome/shell/extensions/user-theme/name",
    "/org/gnome/desktop/background/picture-uri",
    "/org/gnome/desktop/background/picture-uri-dark",
    "/org/gnome/desktop/screensaver/picture-uri",
)


def old_text(text):
    return bool(LEGACY.search(text))


def read_text(path):
    # Preserve unrelated bytes, including CRLF, when changing a single key.
    with path.open(encoding="utf-8", newline="") as stream:
        return stream.read()


def ini_lines(text):
    group = ()
    for index, line in enumerate(text.splitlines(keepends=True)):
        if line.startswith("["):
            group = tuple(re.findall(r"\[([^\]]+)\]", line))
        elif "=" in line and not line.lstrip().startswith(("#", ";")):
            raw_key, value = line.rstrip("\r\n").split("=", 1)
            yield index, group, raw_key, raw_key.split("[", 1)[0].strip(), value


def settings_changes(name, text):
    rows = list(ini_lines(text))
    lines = text.splitlines(keepends=True)
    old_widgets = {group for _, group, _, key, value in rows if key == "plugin" and value in WIDGETS}
    old_palette = any(group == ("General",) and key == "ColorScheme" and old_text(value)
                      for _, group, _, key, value in rows)
    changes = []
    for index, group, raw_key, key, value in rows:
        replacement = value
        if name == "kwinrc":
            if (group == ("Plugins",) and key == "liquidglassEnabled") or group == ("Effect-liquidglass",):
                replacement = None
            if group == ("org.kde.kdecoration2",) and key == "theme" and old_text(value):
                replacement = None
        elif name == "kdeglobals":
            if (group, key) in ((("General",), "ColorScheme"), (("Icons",), "Theme"),
                                (("KDE",), "LookAndFeelPackage")) and old_text(value):
                replacement = None
            if old_palette and ((group == ("General",) and key == "ColorSchemeHash")
                                or (group == ("KDE",) and key == "widgetStyle" and value.lower() == "mactahoe")):
                replacement = None
            # Palette entries can have been customized independently; do not
            # erase all Colors:* groups merely because the theme name is old.
        elif name == "plasmarc" and group == ("Theme",) and key == "name" and old_text(value):
            replacement = None
        elif name == "kcminputrc" and group == ("Mouse",) and key == "cursorTheme" and old_text(value):
            replacement = None
        elif name == "Kvantum/kvantum.kvconfig" and group == ("General",) and key == "theme" and old_text(value):
            replacement = None
        elif name in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini"):
            if group == ("Settings",) and key in ("gtk-theme-name", "gtk-icon-theme-name", "gtk-cursor-theme-name") and old_text(value):
                replacement = None
        elif name == "plasma-org.kde.plasma.desktop-appletsrc":
            if key == "plugin" and value in WIDGETS:
                replacement = WIDGETS[value]
            if (key in ("launcherPreset", "defaultLauncherPreset")
                    and group[:-2] in old_widgets and group[-2:] == ("Configuration", "General")):
                replacement = None
        if replacement != value:
            # Duplicate groups/keys are ambiguous and must be resolved manually.
            if sum(g == group and k == raw_key for _, g, k, _, _ in rows) != 1:
                continue
            changes.append({"kind": "ini", "group": list(group), "key": raw_key,
                            "before": lines[index],
                            "after": None if replacement is None else f"{raw_key}={replacement}\n"})
    return changes


def patch_text(text, changes, reverse=False):
    """Apply a scoped journal, rejecting stale values without touching others."""
    for change in changes:
        before, after = (change["after"], change["before"]) if reverse else (change["before"], change["after"])
        lines = text.splitlines(keepends=True)
        if change["kind"] == "ini":
            group = tuple(change["group"])
            matches = [index for index, g, raw, _, _ in ini_lines(text) if g == group and raw == change["key"]]
            if len(matches) > 1:
                raise ValueError("duplicate configuration key")
            current = lines[matches[0]] if matches else None
            if current == after:
                continue
            if current != before:
                raise ValueError("configuration key changed since journal was recorded")
            if matches:
                lines[matches[0]] = after or ""
            elif after is not None:
                header = "".join(f"[{part}]" for part in group)
                indices = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == header]
                if group and not indices:
                    if lines and not lines[-1].endswith("\n"):
                        lines[-1] += "\n"
                    lines.extend([header + "\n", after])
                else:
                    lines.insert(indices[0] + 1 if indices else 0, after)
        else:
            # Only complete, standalone legacy CSS imports or env exports are
            # journaled. No surrounding CSS/configuration (possibly secrets).
            if after is not None and after in lines:
                continue
            if before is None:
                lines.insert(min(change["index"], len(lines)), after)
            elif lines.count(before) != 1:
                raise ValueError("managed line changed since journal was recorded")
            else:
                lines[lines.index(before)] = after or ""
        text = "".join(lines)
    return text


def symlink_ancestor(path):
    return any(parent.is_symlink() for parent in path.parents)


def mount_points():
    # st_dev/ismount alone misses bind mounts on the same filesystem.
    paths = set()
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        raw = line.split()[4]
        paths.add(Path(re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), raw)))
    return paths


def atomic_write(path, text, mode):
    descriptor, temporary = tempfile.mkstemp(prefix=".mactahoe-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


class Dconf:
    def __init__(self, command):
        self.command = command

    def read(self, key):
        return subprocess.run([self.command, "read", key], check=True, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10).stdout.rstrip("\n") or None

    def set(self, key, value):
        args = ["reset", key] if value is None else ["write", key, value]
        subprocess.run([self.command, *args], check=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=10)


class Migration:
    def __init__(self, home, apply=False, assets_only=False, *, config_home=None,
                 data_home=None, state_home=None, dconf=None):
        self.home = Path(os.path.abspath(home))
        if self.home == Path("/") or self.home.is_symlink() or symlink_ancestor(self.home):
            raise ValueError("Refusing filesystem root or symlinked HOME")
        self.config = Path(os.path.abspath(config_home or self.home / ".config"))
        self.data = Path(os.path.abspath(data_home or self.home / ".local/share"))
        self.state = Path(os.path.abspath(state_home or self.home / ".local/state")) / "mactahoe"
        self.apply = apply
        self.assets_only = assets_only
        self.dconf = dconf
        self.backup = None
        self.removed, self.updated, self.deferred, self.leftovers = [], [], [], []
        self.changes = []
        self.mounts = mount_points()

    def defer(self, path, reason):
        entry = {"path": str(path), "reason": reason}
        if entry not in self.deferred:
            self.deferred.append(entry)

    def safe(self, path, *, shared=False):
        if symlink_ancestor(path):
            self.defer(path, "symlinked parent; preserved")
            return False
        if not os.path.lexists(path):
            return False
        info = path.lstat()
        if shared and stat.S_ISLNK(info.st_mode):
            self.defer(path, "shared configuration symlink; preserved")
            return False
        if path in self.mounts or os.path.ismount(path):
            self.defer(path, "mounted target; preserved (including persistent bind mounts)")
            return False
        if not stat.S_ISLNK(info.st_mode) and (info.st_uid != os.getuid() or info.st_nlink > 1 and stat.S_ISREG(info.st_mode)):
            self.defer(path, "foreign-owned or hard-linked file; preserved")
            return False
        if shared and not stat.S_ISREG(info.st_mode):
            self.defer(path, "not a regular shared configuration file")
            return False
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode)):
            self.defer(path, "special file; preserved")
            return False
        return True

    def remove(self, path):
        if not self.safe(path):
            return
        if path.is_dir() and not path.is_symlink():
            if not shutil.rmtree.avoids_symlink_attacks:
                self.defer(path, "platform lacks symlink-safe directory removal")
                return
            if any(mount.is_relative_to(path) for mount in self.mounts):
                self.defer(path, "contains a mounted directory or file; preserved")
                return
            for parent, directories, files in os.walk(path, followlinks=False):
                if any(os.path.ismount(Path(parent) / name) for name in directories + files):
                    self.defer(path, "contains a mounted directory or file; preserved")
                    return
        if str(path) not in self.removed:
            self.removed.append(str(path))

    def settings(self, name):
        path = self.config / name
        if not self.safe(path, shared=True):
            return
        try:
            text = read_text(path)
        except (OSError, UnicodeError):
            self.defer(path, "cannot read UTF-8 configuration")
            return
        changes = settings_changes(name, text)
        self.add_changes(path, text, changes)

    def add_changes(self, path, text, changes):
        if changes:
            self.updated.append(str(path))
            self.changes.extend(dict(change, path=str(path)) for change in changes)
        if old_text(patch_text(text, changes)):
            self.leftovers.append({"path": str(path), "reason": "legacy reference in unowned configuration; preserved"})

    def audit_deferred(self):
        # Read-only inspection can distinguish a modern HM/store link or bind
        # mount from a legacy leftover without ever replacing that shared path.
        for item in self.deferred:
            path = Path(item["path"])
            if item["reason"] not in ("shared configuration symlink; preserved",
                                      "mounted target; preserved (including persistent bind mounts)"):
                continue
            item["legacy_reference"] = None
            try:
                resolved = path.resolve()
                if (symlink_ancestor(path) or not path.is_file()
                        or not (resolved.stat().st_uid == os.getuid() or resolved.is_relative_to("/nix/store"))):
                    continue
                text = read_text(path)
                changes = settings_changes(str(path.relative_to(self.config)), text) if path.is_relative_to(self.config) else []
                item["legacy_reference"] = old_text(text) or bool(changes)
                if item["legacy_reference"]:
                    self.leftovers.append({"path": str(path), "reason": "legacy reference in protected shared path; preserved"})
            except (OSError, UnicodeError):
                pass

    def legacy_lines(self, path, expression):
        if not self.safe(path, shared=True):
            return
        text = read_text(path)
        changes = [{"kind": "line", "before": line, "after": None, "index": index}
                   for index, line in enumerate(text.splitlines(keepends=True))
                   if re.fullmatch(expression, line.rstrip("\r\n")) and old_text(line)
                   and text.splitlines(keepends=True).count(line) == 1]
        self.add_changes(path, text, changes)

    def plan(self):
        for name in THEMES:
            for parent in (self.home / ".themes", self.data / "themes",
                           self.data / "plasma/desktoptheme", self.data / "aurorae/themes"):
                self.remove(parent / name)
        for name in ("org.kde.mac-tahoe-liquid-kde.light", "org.kde.mac-tahoe-liquid-kde.dark"):
            self.remove(self.data / "plasma/look-and-feel" / name)
        for name in WIDGETS:
            self.remove(self.data / "plasma/plasmoids" / name)
        for name in ("MacTahoeLiquidKde", "MacTahoeLiquidKde-Dark", "MacTahoeLiquidKde-Icons", "MacTahoeLiquidKde-Icons-dark"):
            for parent in (self.data / "icons", self.home / ".icons"):
                self.remove(parent / name)
        for name in ("MacTahoeLiquidKdeLight.colors", "MacTahoeLiquidKdeDark.colors"):
            self.remove(self.data / "color-schemes" / name)
        for name in ("mac-tahoe-liquid-kde", "mac-tahoe-liquid-kdeDark"):
            self.remove(self.config / "Kvantum" / name)
        for path in (self.home / "macos-golden-gate-liquid-kde", self.home / "macos-tahoe-liquid-kde",
                     self.data / "mac-tahoe-liquid-kde", self.config / "mac-tahoe-liquid-kde",
                     self.data / "kwin/effects/liquidglass"):
            self.remove(path)
        # Panel Colorizer is not intrinsically retired. Only unlink an explicit
        # old source reference; never delete its independent installation.
        colorizer = self.data / "plasma/plasmoids/luisbocanegra.panel.colorizer"
        if colorizer.is_symlink() and old_text(os.readlink(colorizer)):
            self.remove(colorizer)
        if self.assets_only:
            return
        for name in CONFIGS:
            self.settings(name)
        for name in ("gtk-3.0/gtk.css", "gtk-4.0/gtk.css"):
            self.legacy_lines(self.config / name, r'\s*@import\s+(?:url\(["\'][^"\']+["\']\)|["\'][^"\']+["\'])\s*;\s*')
        self.legacy_lines(self.config / "plasma-workspace/env/golden-gate-plugin-paths.sh",
                          r'\s*(?:export\s+)?(?:QT_PLUGIN_PATH|QML2?_IMPORT_PATH)=[^;`]+')
        # Shared launchers, shortcuts, wallpapers and plasma-manager scripts may
        # include user customizations: report them, do not recursively erase them.
        for path in (self.config / "kglobalshortcutsrc",
                     self.config / "autostart/plasma-manager-autostart.desktop",
                     self.data / "plasma-manager/run_all.sh",
                     self.data / "plasma-manager/scripts/1_script_apply_themes.sh",
                     self.data / "plasma-manager/data/desktop_script_panels.js",
                     self.data / "plasma-manager/data/desktop_script_golden-gate-panel-appearance.js",
                     self.data / "plasma-manager/data/desktop_script_wallpaper_picture.js"):
            if self.safe(path, shared=True) and old_text(read_text(path)):
                self.leftovers.append({"path": str(path), "reason": "shared launcher/shortcut/script; preserved"})
        if self.dconf is not None:
            for key in DCONF_KEYS:
                value = self.dconf.read(key)
                if value and old_text(value):
                    self.changes.append({"kind": "dconf", "key": key, "before": value, "after": None})
                    self.updated.append("dconf:" + key)

    def private_state(self):
        if self.state.is_symlink() or symlink_ancestor(self.state):
            raise ValueError("Refusing symlinked backup/state directory")
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.state.stat().st_uid != os.getuid():
            raise ValueError("Refusing foreign-owned state directory")
        self.state.chmod(0o700)
        return self.state

    def save_backup(self):
        root = self.state / "migration-backups"
        if root.is_symlink() or root.exists() and root.stat().st_uid != os.getuid():
            raise ValueError("Refusing unsafe backup directory")
        root.mkdir(mode=0o700, exist_ok=True)
        root.chmod(0o700)
        self.backup = Path(tempfile.mkdtemp(prefix="migration-", dir=root))
        journal = {"version": 1, "home": str(self.home), "changes": self.changes}
        atomic_write(self.backup / "changes.json", json.dumps(journal, indent=2) + "\n", 0o600)

    def apply_journal(self, changes, reverse=False):
        self.mounts = mount_points()
        prepared = []
        for path in dict.fromkeys(change["path"] for change in changes if "path" in change):
            path = Path(path)
            if not path.is_relative_to(self.config) or not self.safe(path, shared=True):
                raise ValueError(f"Refusing unsafe journal target: {path}")
            subset = [change for change in changes if change.get("path") == str(path)]
            old = read_text(path)
            new = patch_text(old, subset, reverse=reverse)
            if new != old:
                prepared.append((path, old, new, stat.S_IMODE(path.stat().st_mode)))
        dconf_changes = []
        for change in changes:
            if change["kind"] != "dconf":
                continue
            if self.dconf is None or change["key"] not in DCONF_KEYS:
                raise ValueError("dconf backend unavailable or unowned journal key")
            before, after = (change["after"], change["before"]) if reverse else (change["before"], change["after"])
            current = self.dconf.read(change["key"])
            if current == after:
                continue
            if current != before:
                raise ValueError("dconf value changed since journal was recorded")
            dconf_changes.append((change["key"], before, after))
        # Validate all stale values before the first write, including rollback.
        # A runtime failure leaves the durable journal available for recovery.
        if not self.apply:
            return
        for path, old, new, mode in prepared:
            if not self.safe(path, shared=True) or read_text(path) != old:
                raise ValueError("configuration changed during migration")
            atomic_write(path, new, mode)
        for key, _, after in dconf_changes:
            self.dconf.set(key, after)

    def run(self, rollback=None):
        lock = None
        try:
            if self.apply:
                self.private_state()
                path = self.state / "appearance.lock"
                descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
                lock = os.fdopen(descriptor, "r+")
                if os.fstat(descriptor).st_uid != os.getuid() or os.fstat(descriptor).st_nlink != 1:
                    raise ValueError("Refusing unsafe appearance lock")
                os.fchmod(descriptor, 0o600)
                fcntl.flock(lock, fcntl.LOCK_EX)
            if rollback:
                path = Path(os.path.abspath(rollback)) / "changes.json"
                if (not path.is_relative_to(self.state / "migration-backups")
                        or not self.safe(path, shared=True) or path.stat().st_mode & 0o077):
                    raise ValueError("Refusing unsafe rollback journal")
                journal = json.loads(path.read_text(encoding="utf-8"))
                if journal["version"] != 1 or journal["home"] != str(self.home):
                    raise ValueError("Rollback journal belongs to another home or version")
                self.changes = journal["changes"]
                self.updated = list(dict.fromkeys(c.get("path", "dconf:" + c.get("key", "")) for c in self.changes))
                self.apply_journal(self.changes, reverse=True)
            else:
                self.plan()
                if self.apply and self.changes:
                    self.save_backup()
                    self.apply_journal(self.changes)
                if self.apply:
                    for candidate in self.removed.copy():
                        self.removed.remove(candidate)
                        self.mounts = mount_points()
                        path = Path(candidate)
                        self.remove(path)  # Recheck mounts and links just before deletion.
                        if candidate not in self.removed:
                            continue
                        if path.is_symlink() or path.is_file():
                            path.unlink()
                        else:
                            shutil.rmtree(path)
            self.audit_deferred()
            return {"removed": self.removed, "settings": self.updated, "deferred": self.deferred,
                    "leftovers": self.leftovers, "backup": str(self.backup) if self.backup else None,
                    "applied": self.apply, "rollback": bool(rollback),
                    "dconf": "not inspected (--assets-only)" if self.assets_only else
                    "checked" if self.dconf else "not inspected (no --dconf backend)"}
        finally:
            if lock:
                lock.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", default=os.environ.get("HOME"), required="HOME" not in os.environ)
    parser.add_argument("--config-home")
    parser.add_argument("--data-home")
    parser.add_argument("--state-home")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--assets-only", action="store_true")
    parser.add_argument("--dconf", help="dconf executable; only this HOME's session may be accessed")
    parser.add_argument("--rollback", help="restore shared values from a migration backup directory")
    args = parser.parse_args()
    own_home = Path(args.home).absolute() == Path.home().absolute()
    if args.dconf and not own_home:
        parser.error("--dconf cannot access another HOME's session")
    if own_home:
        args.config_home = args.config_home or os.environ.get("XDG_CONFIG_HOME")
        args.data_home = args.data_home or os.environ.get("XDG_DATA_HOME")
        args.state_home = args.state_home or os.environ.get("XDG_STATE_HOME")
    engine = None
    try:
        engine = Migration(args.home, args.apply, args.assets_only, config_home=args.config_home,
                           data_home=args.data_home, state_home=args.state_home,
                           dconf=Dconf(args.dconf) if args.dconf else None)
        result = engine.run(args.rollback)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Do not print subprocess/config values, which can contain private data.
        backup = f" Rollback journal: {engine.backup}." if engine and engine.backup else ""
        parser.exit(1, f"MacTahoe migration stopped ({type(error).__name__}); no further changes. "
                       f"Use --rollback BACKUP --apply to restore affected shared values.{backup}\n")
