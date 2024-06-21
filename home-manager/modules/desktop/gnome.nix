{
  pkgs,
  lib,
  config,
  ...
}: let
  extensionPkgs = with pkgs.gnomeExtensions; [
    gsconnect
    appindicator
    dash-to-dock
    clipboard-history
    upower-battery
    alphabetical-app-grid
    system-monitor-next
    # caffeine
    user-themes
    customize-ibus
    # fcitx5
    # kimpanel
  ];
  toTitle = str: "${lib.toUpper (lib.substring 0 1 str)}${lib.substring 1 (lib.stringLength str) str}";
  orchis-theme = pkgs.orchis-theme.override {
    tweaks = [config.home.catppuccin.tweak];
    # withWallpapers = true;
  };
  catppuccin-kvantum =
    pkgs.catppuccin-kvantum.override
    {
      accent = toTitle config.home.catppuccin.accent;
      variant = toTitle config.home.catppuccin.variant;
    };
  inherit (lib.hm.gvariant) mkArray mkTuple mkString mkUint32 mkDouble type;
in {
  home.packages =
    extensionPkgs
    ++ (with pkgs; [
      blackbox-terminal
      dolphin
      k3b
      orchis-theme
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
        power-button-action = "nothing";
        sleep-inactive-ac-type = "nothing";
      };
      "org.gnome.desktop.wm.keybindings" = {
        switch-to-workspace-right = ["<Control><Super>Right"];
        switch-to-workspace-left = ["<Control><Super>Left"];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = mkString "NEXT";
        # https://www.reddit.com/r/gnome/comments/wencxw/almost_solved_i_wish_gnome_would_have_a_way_to/
        command = mkString "dbus-send --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:true";
        name = mkString "Power off monitor";
      };
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (p: p.extensionUuid) extensionPkgs;
        disabled-extensions = [];
        last-selected-power-profile = "performance";
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
      "org/gnome/mutter" = {
        # Active Screen Edges
        # Drag windows against screen edges to resize them
        edge-tiling = true;
        dynamic-workspaces = true;
        center-new-windows = true;
        experimental-features = ["scale-monitor-framebuffer"];
      };
      "org/gnome/desktop/interface" = {
        scaling-factor = mkDouble 1.5;
        # text-scaling-factor = mkDouble 1.5;

        # gtk-theme = "adw-gtk3";
        # cursor-theme = "capitaine-cursors";
        cursor-size = 36 * config.wayland.dpi / 96;
        clock-show-weekday = true;
        show-battery-percentage = true;
        locate-pointer = true;
        enable-hot-corners = false;
      };
      "org/gnome/desktop/peripherals/keyboard" = {
        numlock-state = true;
      };
      "org/gnome/desktop/input-sources" = {
        sources = mkArray (type.tupleOf [type.string type.string]) [
          (mkTuple [(mkString "ibus") (mkString "rime")])
          # (mkTuple [(mkString "xkb") (mkString "us")])
        ];
      };
      "org/gnome/shell/extensions/customize-ibus" = {
        use-custom-font = true;
        custom-font = "sans-serif 10";
        input-indicator-only-on-toggle = true;
      };
      "org/gnome/shell/extensions/system-monitor" = {
        memory-display = false;
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
        dash-max-icon-size = 48 * config.wayland.dpi / 96;
        show-mounts = false;
        click-action = "focus-or-appspread";
        scroll-action = "switch-workspace";
        intellihide-mode = "ALL_WINDOWS";
        show-dock-urgent-notify = false;
        show-trash = false;
      };
      "org/gnome/shell/extensions/gsconnect" = {
        show-indicators = true;
        webbrowser-integration = true;
        nautilus-integration = true;
        show-battery = true;
      };
      "org/gnome/shell/extensions/user-theme" = {
        name = "Orchis-Light-${toTitle config.home.catppuccin.tweak}";
      };
      "org/gnome/Console" = {
        theme = "auto";
      };
      "ca/desrt/dconf-editor" = {
        show-warning = false;
      };
      "org/gnome/desktop/background" = {
        picture-uri = "file://${pkgs.wallpaper}/wallpaper.jpg";
        picture-uri-dark = "file://${pkgs.wallpaper}/wallpaper.jpg";
        primary-color = "#26a269";
        secondary-color = "#000000";
        color-shading-type = "solid";
        picture-options = "zoom";
      };
      "org/gnome/desktop/screensaver" = {
        picture-uri = "file://${pkgs.wallpaper}/wallpaper.jpg";
        primary-color = "#26a269";
        secondary-color = "#000000";
        color-shading-type = "solid";
        picture-options = "zoom";
      };
      "com/raggesilver/BlackBox" = {
        terminal-padding = mkTuple [(mkUint32 5) (mkUint32 5) (mkUint32 5) (mkUint32 5)];
        font = "monospace ${toString (10 * config.wayland.dpi / 96)}";
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

  gtk = {
    enable = true;
    theme = {
      name = "Orchis-Light-${toTitle config.home.catppuccin.tweak}";
      package = orchis-theme;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "capitaine-cursors-white";
      package = pkgs.capitaine-cursors;
    };
  };
  qt = {
    enable = true;
    # platformTheme = "gnome";
    # platformTheme = "qtct";
    style = {
      name = "kvantum";
      package = catppuccin-kvantum;
    };
  };
  home.sessionVariables = {
    QT_STYLE_OVERRIDE = lib.mkForce "kvantum";
    XCURSOR_THEME = config.dconf.settings."org/gnome/desktop/interface".cursor-theme;
    # Wayland variables
    CLUTTER_BACKEND = "wayland";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    WLR_NO_HARDWARE_CURSORS = "1";
  };
  xdg.configFile = {
    "Kvantum/kvantum.kvconfig".source = (pkgs.formats.ini {}).generate "kvantum.kvconfig" {
      General.theme = "Catppuccin-${toTitle config.home.catppuccin.variant}-${toTitle config.home.catppuccin.accent}";
    };
    "Kvantum/Catppuccin-${toTitle config.home.catppuccin.variant}-${toTitle config.home.catppuccin.accent}".source = "${catppuccin-kvantum.outPath}/share/Kvantum/Catppuccin-${toTitle config.home.catppuccin.variant}-${toTitle config.home.catppuccin.accent}";
    # "Kvantum/Catppuccin-${toTitle config.home.catppuccin.variant}-${toTitle config.home.catppuccin.accent}".source = "${catppuccin-kvantum.outPath}";
  };

  ## Create startwm.sh for XRDP
  home.file."startwm.sh".text = ''
    #!/usr/bin/env bash
    export DESKTOP_SESSION="gnome"
    export GDMSESSION="gnome"
    export XDG_CURRENT_DESKTOP="GNOME"
    export XDG_SESSION_DESKTOP="gnome"
    dbus-run-session -- gnome-shell
  '';
  home.file."startwm.sh".executable = true;

  home.global-persistence = {
    directories = [
      ".config/gsconnect"
      ".cache/gsconnect"
    ];
  };
  systemd.user.services.gsconnect-dconf = {
    Unit = {
      Description = "gsconnect-dconf";
      Wants = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Install = {WantedBy = ["graphical-session.target"];};
    Service = {
      Type = "simple";
      ExecStart = toString (pkgs.writeScript "gsconnect-dconf-start" ''
        #! ${pkgs.runtimeShell} -el
        ${pkgs.dconf}/bin/dconf load /org/gnome/shell/extensions/gsconnect/ < ${config.home.homeDirectory}/.config/gsconnect/gsconnect.dconf || true
      '');
      ExecStop = toString (pkgs.writeScript "gsconnect-dconf-stop" ''
        #! ${pkgs.runtimeShell} -el
        ${pkgs.dconf}/bin/dconf dump /org/gnome/shell/extensions/gsconnect/ > ${config.home.homeDirectory}/.config/gsconnect/gsconnect.dconf
      '');
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
      RemainAfterExit = "yes";
    };
  };
}
