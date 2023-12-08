{
  pkgs,
  lib,
  ...
}: let
  extensionPkgs = with pkgs.gnomeExtensions; [
    gsconnect
    appindicator
    dash-to-dock
    clipboard-history
    upower-battery
    alphabetical-app-grid
    caffeine
    customize-ibus
    # fcitx5
    kimpanel
  ];
  gtkThemes = pkgs.symlinkJoin {
    name = "gtk-themes";
    paths = with pkgs; [
      adw-gtk3
    ];
  };
  inherit (lib.hm.gvariant) mkArray mkTuple mkString mkUint32 mkDouble type;
in {
  home.packages =
    extensionPkgs
    ++ (with pkgs; [
      blackbox-terminal
      capitaine-cursors
    ]);

  programs.chromium.extensions = [
    "gphhapmejobijbbhgpjhcjognlahblep" # GNOME Shell integration
    "jfnifeihccihocjbfcfhicmmgpjicaec" # GSConnect
  ];
  # Remove initial setup dialog
  home.file.".config/gnome-initial-setup-done".text = "yes";

  # themes
  home.file.".local/share/themes".source = "${gtkThemes}/share/themes";

  dconf.settings = lib.mkMerge [
    {
      # "org/gnome/mutter" = {
      #   experimental-features = ["scale-monitor-framebuffer"];
      # };
      # Do not sleep when ac power connected
      "org/gnome/settings-daemon/plugins/power" = {
        power-button-action = "nothing";
        sleep-inactive-ac-type = "nothing";
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = mkString "NEXT";
        # https://www.reddit.com/r/gnome/comments/wencxw/almost_solved_i_wish_gnome_would_have_a_way_to/
        command = mkString "dbus-send --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:true";
        name = mkString "Power off monitor";
      };
      "org/gnome/desktop/wm/keybindings" = {
        # switch-input-source = mkArray (type.string) [mkString "Shift_L" mkString "Shift_R"];
        # switch-input-source = ["Shift_L" "Shift_R"];
      };
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (p: p.extensionUuid) extensionPkgs;
        disabled-extensions = [];
        favorite-apps = lib.mkBefore [
          "org.gnome.Console.desktop"
          "org.gnome.Nautilus.desktop"
          "firefox.desktop"
          "chromium-browser.desktop"
          "gnome-system-monitor.desktop"
          "code.desktop"
          "steam-hidpi.desktop"
        ];
        welcome-dialog-last-shown-version = "43.1";
      };
      "org/gnome/desktop/interface" = {
        scaling-factor = mkUint32 2;
        text-scaling-factor = mkDouble 0.75;

        gtk-theme = "adw-gtk3";
        cursor-theme = "capitaine-cursors";
        cursor-size = 24;
        clock-show-weekday = true;
        show-battery-percentage = true;
        locate-pointer = true;
        enable-hot-corners = false;
      };
      "org/gnome/desktop/input-sources" = {
        sources = mkArray (type.tupleOf [type.string type.string]) [
          (mkTuple [(mkString "xkb") (mkString "us")])
          (mkTuple [(mkString "ibus") (mkString "rime")])
        ];
      };
      "org/gnome/shell/extensions/customize-ibus" = {
        use-custom-font = true;
        custom-font = "sans-serif 10";
        input-indicator-only-on-toggle = true;
        custom-theme = "/home/tippy/.config/ibus/rime/theme.css";
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

  home.activation.allowGdmReadFace = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.acl}/bin/setfacl --modify=group:gdm:--x "$HOME"
  '';

  # gsconnect association
  xdg.mimeApps.associations.added = {
    "x-scheme-handler/sms" = "org.gnome.Shell.Extensions.GSConnect.desktop";
    "x-scheme-handler/tel" = "org.gnome.Shell.Extensions.GSConnect.desktop";
  };

  home.global-persistence = {
    directories = [
      ".config/gsconnect"
    ];
  };
}
