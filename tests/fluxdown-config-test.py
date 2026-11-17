import configparser
import json
import os
from pathlib import Path
import subprocess
import sys


for name, result in json.loads(sys.argv[1]).items():
    package = Path(result["package"])
    for executable in ("fluxdown-desktop", "fluxdown-agent", "fluxdownd", "fluxdown_nmh"):
        assert os.access(package / "bin" / executable, os.X_OK), (name, executable)

    for browser, field, expected in (
        ("firefox", "allowed_extensions", "fluxdown@fluxdown.app"),
        ("chromium", "allowed_origins", "chrome-extension://meleenglfggcmcajknpeeeiobnpfmahc/"),
    ):
        manifest = json.loads(
            (Path(result[f"{browser}Manifest"]) / "com.fluxdown.nmh.json").read_text()
        )
        assert manifest["name"] == "com.fluxdown.nmh"
        assert manifest["type"] == "stdio"
        assert manifest["path"] == "/home/tippy/.local/share/fluxdown/fluxdown_nmh.sh"
        assert expected in manifest[field]
        assert ("allowed_origins" in manifest) == (browser == "chromium")

    desktop = configparser.ConfigParser(interpolation=None)
    desktop.read(package / "share/applications/com.fluxdown.app.desktop")
    assert desktop["Desktop Entry"]["Exec"] == "fluxdown-desktop %U"
    assert "x-scheme-handler/magnet" in desktop["Desktop Entry"]["MimeType"].split(";")
    autostart = configparser.ConfigParser(interpolation=None)
    autostart.read(Path(result["autostart"]) / "fluxdown.desktop")
    assert autostart["Desktop Entry"]["Exec"] == f"{package}/bin/fluxdown-agent --autostart"
    # Upstream's registration diagnosis parses only single-quoted exec paths.
    assert f"exec '{package}/bin/fluxdown_nmh' \"$@\"" in Path(result["relay"]).read_text()

    # Check the shipped relay starts without opening a GUI or requiring a daemon.
    completed = subprocess.run(
        [package / "bin/fluxdown_nmh"],
        input="",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, completed.stderr
    print(f"{name}: package, native hosts, desktop associations and autostart verified")
