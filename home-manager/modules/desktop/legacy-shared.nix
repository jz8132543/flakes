{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  inherit (lib.hm.gvariant) mkTuple mkUint32;
in
{
  # The archived GNOME module still supplies these when it is enabled.
  config = lib.mkIf (!osConfig.desktop.gnome.enable) {
    home.packages = with pkgs; [
      blackbox-terminal
      seahorse
    ];

    gtk = {
      enable = true;
      font = {
        name = "Inter";
        size = 11;
      };
      gtk3.bookmarks = [
        "file://${config.home.homeDirectory}/.local/XDG/Desktop 桌面"
        "file://${config.home.homeDirectory}/.local/XDG/Documents"
        "file://${config.home.homeDirectory}/.local/XDG/Downloads"
        "file://${config.home.homeDirectory}/.local/XDG/Music"
        "file://${config.home.homeDirectory}/.local/XDG/Pictures"
        "file://${config.home.homeDirectory}/.local/XDG/Videos"
        "file://${config.home.homeDirectory}/Storage/BottlesShare Bottles 共享目录"
      ];
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = lib.genAttrs [
        "text/html"
        "application/xhtml+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "application/x-extension-htm"
        "application/x-extension-html"
        "application/x-extension-shtml"
        "application/x-extension-xhtml"
        "application/x-extension-xht"
      ] (_: lib.mkForce [ "firefox.desktop" ]);
    };

    dconf.settings = {
      "org/gnome/desktop/media-handling" = {
        automount = true;
        autorun-never = false;
        autorun-x-content-start-app = [ "x-content/unix-software" ];
      };
      "org/gnome/Console".theme = "auto";
      "ca/desrt/dconf-editor".show-warning = false;
      "com/raggesilver/BlackBox" = {
        terminal-padding = mkTuple [
          (mkUint32 5)
          (mkUint32 5)
          (mkUint32 5)
          (mkUint32 5)
        ];
        theme-light = "Tomorrow";
        theme-dark = "Tomorrow Night";
        show-menu-button = false;
      };
    };

    home.sessionVariables = {
      CLUTTER_BACKEND = "wayland";
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
      MOZ_ENABLE_WAYLAND = "1";
      NIXOS_OZONE_WL = "1";
    };

    systemd.user.services.reset-volume-on-login = {
      Unit = {
        Description = "Reset audio volume to 0 on login";
        After = [ "wireplumber.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "reset-volume-zero" ''
          for i in $(seq 1 30); do
            if ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 0 2>/dev/null; then
              exit 0
            fi
            sleep 0.2
          done
        ''}";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
