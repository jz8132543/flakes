"""Check installed MacTahoe identities, cursor payloads and untouched assets."""

import argparse
import configparser
import hashlib
from pathlib import Path
import re
import subprocess


def ini(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(path)
    return parser


def unchanged(source, target):
    assert source.is_dir(), source
    assert target.is_dir(), target
    for original in source.rglob("*"):
        installed = target / original.relative_to(source)
        assert installed.exists(), installed
        if original.is_file():
            expected = original.read_bytes()
            assert hashlib.sha256(expected).digest() == hashlib.sha256(
                installed.read_bytes()
            ).digest(), installed


def main():
    parser = argparse.ArgumentParser()
    for name in ("gtk", "gtk-visual", "icons", "cursors", "wallpaper", "firefox", "gtk-source", "icons-source"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--gdm-theme", type=Path)
    parser.add_argument("--gnome-shell", type=Path)
    args = parser.parse_args()

    for color in ("Light", "Dark"):
        name = f"MacTahoe-{color}-solid"
        theme = args.gtk / "share/themes" / name
        assert ini(theme / "index.theme")["Desktop Entry"]["Name"] == name
        for css in ("gtk-3.0/gtk.css", "gtk-3.0/gtk-dark.css", "gtk-4.0/gtk.css", "gtk-4.0/gtk-dark.css", "gnome-shell/gnome-shell.css"):
            assert (theme / css).stat().st_size > 1000, theme / css
        assert "-st-accent-color" in (theme / "gnome-shell/gnome-shell.css").read_text()
        assert (theme / "gnome-shell/assets/activities.svg").exists()
        visual_name = f"MacTahoe-Visual-{color}"
        visual = args.gtk_visual / "share/themes" / visual_name
        assert ini(visual / "index.theme")["Desktop Entry"]["Name"] == visual_name
        for css in ("gtk-3.0/gtk.css", "gtk-4.0/gtk.css", "gnome-shell/gnome-shell.css"):
            assert (visual / css).stat().st_size > 1000
        for css in ("gtk-3.0/gtk.css", "gtk-4.0/gtk.css"):
            assert (visual / css).read_bytes() != (theme / css).read_bytes()
        # Pinned upstream's --blur window branch uses 0.75 alpha, while
        # ordinary transparency uses 0.96; a rename of that variant fails.
        assert re.search(r"\.background, \.background.view\s*\{\s*background-color: alpha\([^,]+,\s*0\.75\)",
                         (visual / "gtk-4.0/gtk.css").read_text())

    for suffix in ("", "-light", "-dark"):
        name = f"MacTahoe{suffix}"
        theme = args.icons / "share/icons" / name
        assert ini(theme / "index.theme")["Icon Theme"]["Name"] == name
        assert (theme / "apps/scalable/firefox.svg").exists()
        assert (theme / "cursors/left_ptr").read_bytes()[:4] == b"Xcur"
    for name, source in (("MacTahoe-cursors", "dist"), ("MacTahoe-dark-cursors", "dist-dark")):
        theme = args.cursors / "share/icons" / name
        unchanged(args.icons_source / "cursors" / source, theme)
        assert (theme / "cursors/left_ptr").read_bytes()[:4] == b"Xcur"

    for time in ("day", "night"):
        filename = f"MacTahoe-{time}.jpeg"
        actual = args.wallpaper / "share/wallpapers/MacTahoe" / filename
        assert actual.read_bytes() == (args.gtk_source / "wallpaper" / filename).read_bytes()
    assert not list((args.wallpaper / "share/wallpapers/MacTahoe").glob("*.sh"))
    firefox = args.firefox / "share/mactahoe/firefox"
    unchanged(args.gtk_source / "other/firefox", firefox)
    for css in firefox.rglob("*.css"):
        text = re.sub(r"/\*.*?\*/", "", css.read_text(), flags=re.DOTALL)
        for imported in re.findall(r'@import\s+(?:url\()?\s*[\'"]([^\'"]+)', text):
            if not re.match(r"(?:resource|https?|data):", imported):
                assert (css.parent / imported).exists(), (css, imported)

    if args.gdm_theme:
        resource = args.gdm_theme / "share/gnome-shell/gnome-shell-theme.gresource"
        entries = set(subprocess.check_output(["gresource", "list", str(resource)], text=True).splitlines())
        if args.gnome_shell:
            stock = args.gnome_shell / "share/gnome-shell/gnome-shell-theme.gresource"
            stock_entries = set(subprocess.check_output(["gresource", "list", str(stock)], text=True).splitlines())
            assert stock_entries <= entries
        for css in ("gnome-shell-dark.css", "gnome-shell-light.css", "gnome-shell-high-contrast.css"):
            path = f"/org/gnome/shell/theme/{css}"
            actual = subprocess.check_output(["gresource", "extract", str(resource), path])
            assert actual == (args.gtk_source / "other/gdm/theme" / css).read_bytes()
    print("MacTahoe package assets and identities passed")


if __name__ == "__main__":
    main()
