{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.desktop.inputMethod;
  rimeUserData = pkgs.rime-deploy.override {
    inherit (cfg) framework;
    inherit (cfg) terminalEnglishApps;
  };
in
{
  options.desktop.inputMethod = {
    framework = lib.mkOption {
      type = lib.types.enum [
        "fcitx5"
        "ibus"
      ];
      default = "ibus";
      description = "The active desktop input method frontend.";
    };

    terminalEnglishApps = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "kitty"
        "Alacritty"
        "alacritty"
        "foot"
        "neovide"
        "org.wezfurlong.wezterm"
        "org.gnome.Console"
        "gnome-terminal-server"
        "com.raggesilver.BlackBox"
      ];
      description = "Rime app ids/classes that should default to ASCII mode.";
    };
  };

  config = {
    time.timeZone = "Asia/Shanghai";

    # Build the fully deployed Rime data as part of the system closure so the
    # first Rime launch does not need to run rime_deployer at runtime.
    system.build.rimeUserData = rimeUserData;
    system.extraDependencies = lib.mkAfter [ rimeUserData ];

    i18n.inputMethod = {
      enable = true;
      type = cfg.framework;
    }
    // lib.optionalAttrs (cfg.framework == "fcitx5") {
      fcitx5 = {
        addons = with pkgs; [
          fcitx5-gtk
          qt6Packages.fcitx5-qt
          fcitx5-rime
          qt6Packages.fcitx5-chinese-addons
          librime
          librime-lua
          librime-octagram
        ];
        # GNOME Wayland primarily integrates third-party IMEs via the ibus frontend.
        # Keep fcitx5's own Wayland frontend disabled here so Gtk/Qt/XWayland apps
        # continue to use the better-supported IM module path on GNOME.
        waylandFrontend = false;
      };
    }
    // lib.optionalAttrs (cfg.framework == "ibus") {
      ibus = {
        engines = with pkgs.ibus-engines; [ rime ];
        panel = "${pkgs.kdePackages.plasma-desktop}/libexec/kimpanel-ibus-panel";
        waylandFrontend = false;
      };
    };
  };
}
