{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.waydroid;
  waydroid = lib.getExe config.virtualisation.waydroid.package;
  settings = (pkgs.formats.ini { }).generate "waydroid-desktop.cfg" {
    waydroid = {
      auto_adb = "False";
    }
    // lib.optionalAttrs (cfg.drmDevice != null) { drm_device = cfg.drmDevice; };
    properties = {
      "persist.waydroid.multi_windows" = "true";
      # Keep background applications and notification delivery alive.
      "persist.waydroid.suspend" = "false";
      "persist.waydroid.uevent" = "true";
      "persist.waydroid.fake_wifi" = "*";
    }
    // cfg.extraProperties;
  };
  desktopUsers = lib.mapAttrsToList (name: home: {
    inherit name;
    inherit (config.users.users.${name}) group;
    source = "${home.xdg.dataHome}/waydroid/data/media/0/Download";
    target = "/mnt/waydroid/${name}";
  }) (lib.filterAttrs (name: _: config.users.users.${name}.isNormalUser) config.home-manager.users);
  startSession = pkgs.writeShellScript "waydroid-session-start" ''
    set -eu
    # Wait inside the main process so first initialization cannot hold up login.
    ${pkgs.glib}/bin/gdbus wait --system --timeout=1800 id.waydro.Container
    exec ${waydroid} session start
  '';
in
{
  options.desktop.waydroid = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Waydroid with integrated application windows and desktop services.";
    };
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the background Android session after logging into a Wayland desktop.";
    };
    imageType = lib.mkOption {
      type = lib.types.enum [
        "GAPPS"
        "VANILLA"
      ];
      default = "GAPPS";
      description = "Official image used on first initialization. Existing installations are not replaced.";
    };
    drmDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/dri/renderD128";
      description = ''
        Optional DRM render node. By default Waydroid selects a supported GPU,
        skipping the proprietary NVIDIA driver and detecting Mesa/Vulkan itself.
      '';
    };
    sharedFolder = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose Android Downloads at /mnt/waydroid/<username> with an on-demand ownership-mapped mount.";
    };
    extraProperties = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "persist.waydroid.fake_touch" = "com.example.game";
        "persist.waydroid.suspend" = "true";
      };
      description = "Additional Android properties, overriding the desktop defaults when specified.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.waydroid.enable = true;
    hardware.graphics = {
      enable = true;
      enable32Bit = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
    };
    services.pipewire = {
      enable = true;
      audio.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    system.build.waydroidDesktopSettings = settings;
    # Preserve OTA metadata, image locations and user settings in upstream state.
    # Offline upgrade regenerates GPU detection and properties without new images.
    systemd.services.waydroid-container = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # The base persistence profile already mounts /var/lib from /persist.
      unitConfig.RequiresMountsFor = "/var/lib/waydroid";
      path = [ pkgs.crudini ];
      restartTriggers = [ settings ];
      preStart = ''
        if [ ! -f /var/lib/waydroid/waydroid.cfg ] || [ ! -d /var/lib/waydroid/rootfs ]; then
          ${waydroid} init -s ${lib.escapeShellArg cfg.imageType}
        fi
        test -f /var/lib/waydroid/waydroid.cfg
        test -d /var/lib/waydroid/rootfs
        crudini --merge /var/lib/waydroid/waydroid.cfg < ${settings}
        ${waydroid} upgrade --offline
      '';
      serviceConfig.TimeoutStartSec = "30min";
    };

    boot.supportedFilesystems = lib.optional cfg.sharedFolder "fuse.bindfs";
    fileSystems = lib.mkIf cfg.sharedFolder (
      lib.listToAttrs (
        map (user: {
          name = user.target;
          value = {
            device = user.source;
            fsType = "fuse.bindfs";
            options = [
              "noauto"
              "nofail"
              "x-systemd.automount"
              "x-systemd.idle-timeout=60"
              "x-systemd.mount-timeout=15s"
              "x-systemd.requires-mounts-for=${user.source}"
              "nodev"
              "nosuid"
              "noexec"
              "force-user=${user.name}"
              "force-group=${user.group}"
              "perms=0600:u+X"
              # New host files must retain Android's media_rw ownership.
              "create-for-user=1023"
              "create-for-group=1023"
              "create-with-perms=0660:ug+X"
              "chmod-ignore"
              "chown-ignore"
              "chgrp-ignore"
            ];
          };
        }) desktopUsers
      )
    );

    home-manager.sharedModules = [
      (
        { config, ... }:
        let
          homePrefix = "${config.home.homeDirectory}/";
          stateDirectory = "${config.xdg.dataHome}/waydroid";
        in
        {
          home.global-persistence.directories = lib.optional (lib.hasPrefix homePrefix stateDirectory) {
            directory = lib.removePrefix homePrefix stateDirectory;
            mode = "0700";
          };
          systemd.user.services.waydroid-session = lib.mkIf cfg.autostart {
            Unit = {
              Description = "Waydroid integrated Android session";
              After = [
                "graphical-session-pre.target"
                "pipewire-pulse.service"
              ];
              PartOf = [ "graphical-session.target" ];
              ConditionEnvironment = "WAYLAND_DISPLAY";
              StartLimitIntervalSec = 300;
              StartLimitBurst = 3;
            };
            Service = {
              ExecStart = "${startSession}";
              ExecStop = "${waydroid} session stop";
              TimeoutStopSec = 30;
              Restart = "on-failure";
              RestartSec = 5;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
          xdg.desktopEntries = {
            waydroid-apk-install = {
              name = "Install Android APK";
              comment = "Install an APK into the running Waydroid session";
              icon = "waydroid";
              exec = "${waydroid} app install %f";
              terminal = true;
              noDisplay = true;
              mimeType = [ "application/vnd.android.package-archive" ];
              categories = [ "Utility" ];
            };
            waydroid-full-ui = {
              name = "Waydroid Android Desktop";
              comment = "Open the complete Android interface";
              icon = "waydroid";
              exec = "${waydroid} show-full-ui";
              categories = [ "Utility" ];
            };
            waydroid-files =
              lib.mkIf (cfg.sharedFolder && lib.any (user: user.name == config.home.username) desktopUsers)
                {
                  name = "Waydroid Shared Files";
                  comment = "Android Downloads; start Waydroid before opening";
                  icon = "folder-download";
                  exec = "${pkgs.xdg-utils}/bin/xdg-open \"/mnt/waydroid/${config.home.username}\"";
                  categories = [ "Utility" ];
                };
          };
          xdg.mimeApps = {
            enable = true;
            defaultApplications."application/vnd.android.package-archive" = [
              "waydroid-apk-install.desktop"
            ];
          };
        }
      )
    ];
  };
}
