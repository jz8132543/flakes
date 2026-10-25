{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = lib.attrByPath [ "programs" "winpodx" ] { } osConfig;
  enabled = (cfg.enable or false) && config.home.username == (cfg.userName or "");
  inherit (cfg) package;
  toml = pkgs.formats.toml { };
  settings = lib.recursiveUpdate {
    rdp = {
      user = cfg.guestUser;
      password = ""; # Filled privately once, never placed in the Nix Store.
      password_updated = "";
      ip = "127.0.0.1";
      port = cfg.rdpPort;
      scale = 100;
      inherit (cfg) dpi;
      freerdp_source = "native";
      multimon = "span";
      media_drive_enabled = true;
      extra_flags = "/auto-reconnect-max-retries:0 -auto-reconnect";
    };
    pod = {
      inherit (cfg)
        backend
        image
        language
        region
        keyboard
        timezone
        ;
      container_name = "winpodx-windows";
      win_version = cfg.winVersion;
      cpu_cores = cfg.cpuCores;
      ram_gb = cfg.ramGb;
      disk_size = cfg.diskSize;
      storage_path = cfg.storagePath;
      vnc_port = cfg.vncPort;
      auto_start = cfg.autoStart;
      idle_timeout = cfg.idleTimeout;
      idle_action = "pause";
      boot_timeout = 1800;
      guest_autosync = true;
      disk_autogrow = true;
      max_sessions = cfg.maxSessions;
      initialized = true;
      network = "user";
      tuning_profile = "auto";
      disguise_level = "off";
      usb_live = true;
    };
    reverse_open = {
      enabled = cfg.reverseOpen;
      deny_dangerous = true;
    };
    install.auto_resume = true;
    logging.level = "INFO";
    ui.language = "zh";
    desktop.mime_associations = true;
  } cfg.settings;
  seed = toml.generate "winpodx-initial.toml" settings;
  deploy = pkgs.writeShellScriptBin "winpodx-deploy" ''
    export WINPODX_CLI=${package}/bin/winpodx
    export WINPODX_BUNDLE_DIR=${package}/share/winpodx
    export WINPODX_SEED=${seed}
    export WINPODX_SETTINGS=${package}/share/winpodx/config/oem/deployment-settings.json
    export WINPODX_STORAGE=${lib.escapeShellArg cfg.storagePath}
    export WINPODX_INITIAL_DEPLOYMENT=${if cfg.initialDeployment.enable then "1" else "0"}
    export WINPODX_PASSWORD_FILE=${
      lib.escapeShellArg (if cfg.passwordFile == null then "" else cfg.passwordFile)
    }
    export WINPODX_WINDOWS_KEY_FILE=${
      lib.escapeShellArg (
        if cfg.activation.windowsProductKeyFile == null then "" else cfg.activation.windowsProductKeyFile
      )
    }
    export WINPODX_OFFICE_KEY_FILE=${
      lib.escapeShellArg (
        if cfg.activation.officeProductKeyFile == null then "" else cfg.activation.officeProductKeyFile
      )
    }
    export PATH=${
      lib.makeBinPath [
        pkgs.podman
        pkgs.podman-compose
        pkgs.freerdp
        pkgs.iproute2
        pkgs.coreutils
        pkgs.util-linux
        pkgs.jq
      ]
    }:$PATH
    ${builtins.readFile ./winpodx-deploy.sh}
  '';
  shortcuts = lib.filterAttrs (_: app: app.enable) cfg.shortcuts;
  profiles = lib.filterAttrs (_: app: app.executable != null) shortcuts;
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = settings.rdp.password == "" && !(settings.pod ? guest_agent_token);
        message = "Guest passwords and agent tokens must remain runtime secrets, not Nix settings.";
      }
    ];
    home.packages = [ deploy ];
    home.sessionVariables.WINPODX_DECLARATIVE_SHORTCUTS = "1";
    home.file = {
      ".config/winpodx/nixos.toml".source = seed;
    }
    // lib.mapAttrs' (
      id: app:
      lib.nameValuePair ".local/share/winpodx/apps/${id}/app.toml" {
        source = toml.generate "winpodx-${id}.toml" {
          name = app.slug;
          full_name = app.desktopName;
          inherit (app) executable;
          source = "user";
          description = app.comment;
          inherit (app) categories;
          mime_types = app.mimeType;
          wm_class_hint = app.wmClass;
        };
      }
    ) profiles;
    # The initial config is copied once. WinPodX owns subsequent writes and tokens.
    home.activation.winpodxConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run mkdir -p ${lib.escapeShellArg cfg.storagePath}
      run ${pkgs.e2fsprogs}/bin/chattr +C ${lib.escapeShellArg cfg.storagePath} || true
      run ${deploy}/bin/winpodx-deploy init
    '';
    home.global-persistence.directories = [
      "Storage/WinPodX"
      ".config/winpodx"
      ".local/share/winpodx"
    ];
    systemd.user.services.winpodx-deploy = lib.mkIf cfg.initialDeployment.enable {
      Unit.Description = "Resumable first deployment of WinPodX, Office and activation";
      Service = {
        Type = "oneshot";
        ExecStart = "${deploy}/bin/winpodx-deploy";
        TimeoutStartSec = "8h";
        Restart = "on-failure";
        RestartSec = "5min";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.winpodx-tray = {
      Unit = {
        Description = "WinPodX native tray and idle monitor";
        After = [
          "graphical-session.target"
        ]
        ++ lib.optional cfg.initialDeployment.enable "winpodx-deploy.service";
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${package}/bin/winpodx tray";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [
          "WINPODX_DECLARATIVE_SHORTCUTS=1"
          "PATH=${
            lib.makeBinPath [
              pkgs.wmctrl
              pkgs.xdg-utils
            ]
          }:/run/current-system/sw/bin"
        ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    xdg.desktopEntries = {
      winpodx-gui = {
        name = "WinPodX 控制中心";
        exec = "${package}/bin/winpodx gui";
        icon = "preferences-system";
        terminal = false;
        categories = [
          "Settings"
          "System"
        ];
      };
      winpodx-launch = {
        name = "WinPodX 应用抽屉";
        exec = "${package}/bin/winpodx launch";
        icon = "system-search";
        terminal = false;
        categories = [ "Utility" ];
      };
    };
    xdg.mimeApps.defaultApplications = lib.foldlAttrs (
      result: id: app:
      result // lib.genAttrs app.mimeType (_: [ "winpodx-${id}.desktop" ])
    ) { } shortcuts;
  };
}
