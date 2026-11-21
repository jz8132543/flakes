{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  results = lib.genAttrs [ "arx8" "surface" ] (
    name:
    let
      host = configurations.${name};
      cfg = host.config;
      home = cfg.home-manager.users.tippy;
      target = "/mnt/waydroid/tippy";
      downloads = "${home.xdg.dataHome}/waydroid/data/media/0/Download";
      shared = cfg.fileSystems.${target};
      persistence = cfg.environment.persistence.main;
      entries = home.xdg.desktopEntries;
      session = home.systemd.user.services.waydroid-session;
      disabled = (host.extendModules { modules = [ { desktop.waydroid.enable = false; } ]; }).config;
    in
    assert cfg.virtualisation.waydroid.enable;
    assert cfg.hardware.graphics.enable && cfg.hardware.graphics.enable32Bit;
    assert cfg.services.pipewire.pulse.enable;
    assert cfg.virtualisation.waydroid.package == host.pkgs.waydroid-nftables;
    assert cfg.systemd.services.waydroid-container.wantedBy == [ "multi-user.target" ];
    assert cfg.systemd.services.waydroid-container.unitConfig.RequiresMountsFor == "/var/lib/waydroid";
    assert lib.hasInfix "upgrade --offline" cfg.systemd.services.waydroid-container.preStart;
    assert !(lib.hasInfix "init -f" cfg.systemd.services.waydroid-container.preStart);
    assert session.Unit.ConditionEnvironment == "WAYLAND_DISPLAY";
    assert !(session.Service ? ExecStartPre);
    assert !(lib.elem "graphical-session.target" session.Unit.After);
    assert lib.elem "graphical-session-pre.target" session.Unit.After;
    assert session.Install.WantedBy == [ "graphical-session.target" ];
    assert home.xdg.mimeApps.enable;
    assert
      home.xdg.mimeApps.defaultApplications."application/vnd.android.package-archive" == [
        "waydroid-apk-install.desktop"
      ];
    assert lib.hasSuffix " app install %f" entries.waydroid-apk-install.exec;
    assert lib.hasSuffix " show-full-ui" entries.waydroid-full-ui.exec;
    assert lib.hasSuffix ''"${target}"'' entries.waydroid-files.exec;
    assert lib.any (entry: entry.directory == "/var/lib") persistence.directories;
    assert lib.any (
      entry: entry.directory == ".local/share/waydroid" && entry.mode == "0700"
    ) persistence.users.tippy.directories;
    assert !(cfg.fileSystems ? "${home.home.homeDirectory}/Waydroid");
    assert shared.device == downloads;
    assert shared.fsType == "fuse.bindfs";
    assert lib.all (option: lib.elem option shared.options) [
      "x-systemd.automount"
      "x-systemd.requires-mounts-for=${downloads}"
      "create-for-user=1023"
      "create-for-group=1023"
      "perms=0600:u+X"
      "nodev"
      "nosuid"
      "noexec"
    ];
    assert !disabled.virtualisation.waydroid.enable;
    assert !(builtins.hasAttr target disabled.fileSystems);
    {
      settings = cfg.system.build.waydroidDesktopSettings;
      gpuMode = cfg.desktop.nvidia.mode;
    }
  );
in
assert !configurations.fra0.config.virtualisation.waydroid.enable;
pkgs.runCommand "waydroid-config-test"
  {
    nativeBuildInputs = [
      pkgs.crudini
      pkgs.python3
    ];
    results = builtins.toJSON results;
  }
  ''
    python3 - <<'PY'
    import configparser
    import json
    import os
    import pathlib
    import subprocess

    results = json.loads(os.environ["results"])
    assert results["arx8"]["gpuMode"] == "offload"
    assert results["surface"]["gpuMode"] == "sync"
    for name, result in results.items():
        state = pathlib.Path(name + ".cfg")
        state.write_text(
            "[waydroid]\narch=x86_64\nsystem_datetime=123456\n"
            "system_ota=https://example.invalid/existing.json\n"
            "images_path=/existing/images\nauto_adb=True\n"
            "[properties]\npersist.example.keep=yes\n"
            "persist.waydroid.multi_windows=false\n"
        )
        def merge():
            with open(result["settings"], "rb") as settings:
                subprocess.run(["crudini", "--merge", str(state)], stdin=settings, check=True)
        merge()
        first = state.read_bytes()
        merge()
        assert state.read_bytes() == first, "configuration merge must be idempotent"
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(state)
        assert cfg["waydroid"]["arch"] == "x86_64"
        assert cfg["waydroid"]["system_datetime"] == "123456"
        assert cfg["waydroid"]["images_path"] == "/existing/images"
        assert cfg["waydroid"]["system_ota"] == "https://example.invalid/existing.json"
        assert cfg["waydroid"]["auto_adb"] == "False"
        assert cfg["properties"]["persist.example.keep"] == "yes"
        assert cfg["properties"]["persist.waydroid.multi_windows"] == "true"
        assert cfg["properties"]["persist.waydroid.uevent"] == "true"
        assert cfg["properties"]["persist.waydroid.suspend"] == "false"
        assert "ro.hardware.egl" not in cfg["properties"], "keep native GPU detection"
        assert "ro.hardware.gralloc" not in cfg["properties"]
        assert "ro.hardware.vulkan" not in cfg["properties"]
    print("Waydroid desktop configuration and state preservation passed")
    PY
    touch "$out"
  ''
