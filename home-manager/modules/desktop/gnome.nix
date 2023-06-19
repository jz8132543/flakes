{
  pkgs,
  lib,
  osConfig,
  ...
}: let
  extensionPkgs = with pkgs.gnomeExtensions; [
    gsconnect
    appindicator
    dash-to-dock
    clipboard-history
    kimpanel
    customize-ibus
  ];
  inherit (lib.hm.gvariant) mkArray mkTuple mkString mkUint32 type;
in {
  home.packages =
    extensionPkgs
    ++ (with pkgs; [
      blackbox-terminal
    ]);

  programs.chromium.extensions = [
    "gphhapmejobijbbhgpjhcjognlahblep" # GNOME Shell integration
    "jfnifeihccihocjbfcfhicmmgpjicaec" # GSConnect
  ];
  # Remove initial setup dialog
  home.file.".config/gnome-initial-setup-done".text = "yes";

  dconf.settings = lib.mkMerge [
    {
      # Do not sleep when ac power connected
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type = "nothing";
      };
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (p: p.extensionUuid) extensionPkgs;
        disabled-extensions = [];
        favorite-apps = lib.mkBefore [
          "com.raggesilver.BlackBox.desktop"
          "org.gnome.Nautilus.desktop"
          "firefox.desktop"
          "chromium-browser.desktop"
          "gnome-system-monitor.desktop"
          "code.desktop"
        ];
        welcome-dialog-last-shown-version = "43.1";
      };
      "org/gnome/desktop/interface" = {
        clock-show-weekday = true;
        show-battery-percentage = true;
        locate-pointer = true;
        enable-hot-corners = false;
      };
      "org/gnome/desktop/input-sources" = {
        sources = mkArray (type.tupleOf [type.string type.string]) [
          # (mkTuple [(mkString "xkb") (mkString "us")])
          (mkTuple [(mkString "ibus") (mkString "rime")])
        ];
      };
      "org/gnome/shell/extensions/customize-ibus" = {
        input-indicator-only-on-toggle = true;
        use-candidate-opacity = true;
        candidate-opacity = mkUint32 210;
        use-custom-font = true;
        custom-font = "sans-serif 10";
        enable-custom-theme = true;
        enable-custom-theme-dark = true;
        custom-theme = "${osConfig.lib.self.path}/conf/ibus/snow-storm-light.css";
        # custom-theme-dark = "${osConfig.lib.self.path}/conf/ibus/snow-storm-light.css";
        custom-theme-dark = "${osConfig.lib.self.path}/conf/ibus/polar-night-dark.css";
      };
      "desktop/ibus/general" = {
        use-system-keyboard-layout = true;
      };
      "org/gnome/desktop/wm/preferences" = {
        action-middle-click-titlebar = "lower";
        focus-new-windows = "smart";
      };
      "org/gnome/system/location" = {
        enabled = true;
      };
      # just use the standard touchpad and mouse speed
      "org/gnome/desktop/peripherals/mouse" = {
        speed = 0;
      };
      "org/gnome/desktop/peripherals/touchpad" = {
        speed = 0;
        natural-scroll = true;
        tap-to-click = true;
      };
      "org/gnome/desktop/calendar" = {
        show-weekdate = true;
      };
      "org/gnome/shell/extensions/dash-to-dock" = {
        apply-custom-theme = true;
        custom-theme-shrink = true;
        dash-max-icon-size = 32;
        show-mounts = false;
        click-action = "focus-or-appspread";
        scroll-action = "switch-workspace";
        intellihide-mode = "ALL_WINDOWS";
        show-dock-urgent-notify = false;
        show-trash = false;
      };
      "org/gnome/shell/extensions/gsconnect" = {
        show-indicators = true;
      };
      "org/gnome/Console" = {
        theme = "auto";
      };
      "ca/desrt/dconf-editor" = {
        show-warning = false;
      };
      "org/gnome/desktop/background" = {
        picture-uri = "file://${pkgs.gnome.gnome-backgrounds}/share/backgrounds/gnome/symbolic-l.webp";
        picture-uri-dark = "file://${pkgs.gnome.gnome-backgrounds}/share/backgrounds/gnome/symbolic-d.webp";
        primary-color = "#26a269";
        secondary-color = "#000000";
        color-shading-type = "solid";
        picture-options = "zoom";
      };
      "org/gnome/desktop/screensaver" = {
        picture-uri = "file://${pkgs.gnome.gnome-backgrounds}/share/backgrounds/gnome/symbolic-l.webp";
        primary-color = "#26a269";
        secondary-color = "#000000";
        color-shading-type = "solid";
        picture-options = "zoom";
      };
      "com/raggesilver/BlackBox" = {
        terminal-padding = mkTuple [(mkUint32 5) (mkUint32 5) (mkUint32 5) (mkUint32 5)];
        font = "monospace 10";
        theme-light = "Tomorrow";
        theme-dark = "Tomorrow Night";
        show-menu-button = false;
      };
    }
  ];

  home.global-persistence = {
    directories = [
      # ".config/dconf"
      ".config/goa-1.0" # gnome accounts
      ".config/gnome-boxes"
      ".local/share/keyrings"
      ".local/share/applications"
      ".local/share/Trash"
      ".local/share/webkitgtk" # gnome accounts
      ".local/share/backgrounds"
      ".local/share/gnome-boxes"
      ".local/share/icc" # user icc files
      ".cache/tracker3"
      ".cache/thumbnails"
      ".config/gsconnect"
    ];
    files = [
      ".face"
      ".config/monitors.xml"
    ];
  };
}
