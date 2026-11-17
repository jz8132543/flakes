"""Connect existing Firefox profiles without owning registration or unknown CSS."""

import configparser
import json
import os
from pathlib import Path
import re
import sys


def symlink_parent(path, root):
    return any(part.is_symlink() for part in (path, *path.parents) if part.is_relative_to(root))


def connect_profiles(home, profiles_path, styles, managed=()):
    home = Path(os.path.abspath(home))
    root = Path(os.path.abspath(home / profiles_path))
    styles = Path(styles)
    managed = {Path(os.path.abspath(path)) for path in managed}
    report = {"linked": [], "preserved": []}
    if not root.is_relative_to(home) or symlink_parent(root, home):
        report["preserved"].append(str(root))
        return report
    registry = root / "profiles.ini"
    if not registry.is_file():
        return report

    # This registry is read-only, including HM-owned symlinks. Neither user.js
    # nor prefs.js is rewritten; system-color defaults come from Firefox policy.
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(registry, encoding="utf-8")
    except (OSError, UnicodeError, configparser.Error):
        report["preserved"].append(str(registry))
        return report
    for section in parser.sections():
        if not re.fullmatch(r"Profile[0-9]+", section):
            continue
        entry = parser[section]
        if not entry.get("Path"):
            continue
        profile = Path(entry["Path"])
        if entry.get("IsRelative", "1") == "1":
            profile = root / profile
        profile = Path(os.path.abspath(profile))
        if (not profile.is_relative_to(root) or symlink_parent(profile, root)
                or not profile.is_dir()):
            report["preserved"].append(str(profile))
            continue
        if profile in managed:
            continue
        destination = profile / "chrome"
        if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
            report["preserved"].append(str(destination))
            continue
        files = ("userChrome.css", "userContent.css")
        conflicts = [destination / name for name in files
                     if os.path.lexists(destination / name)
                     and not ((destination / name).is_symlink()
                              and os.readlink(destination / name) == str(styles / name))]
        if conflicts:
            report["preserved"].extend(map(str, conflicts))
            continue
        destination.mkdir(mode=0o700, exist_ok=True)
        for name in files:
            target = destination / name
            if not os.path.lexists(target):
                target.symlink_to(styles / name)
                report["linked"].append(str(target))
    return report


if __name__ == "__main__":
    print(json.dumps(connect_profiles(sys.argv[1], sys.argv[2], sys.argv[3],
                                      json.loads(sys.argv[4])), indent=2))
