{
  pkgs,
  lib,
  config,
  osConfig ? { },
  ...
}:
let
  # ▼▼▼ 在这里调整输入法的字体大小 ▼▼▼
  kimpanelFontSize = "26pt";
  # ▲▲▲ 在这里调整输入法的字体大小 ▲▲▲

  imFramework = lib.attrByPath [ "desktop" "inputMethod" "framework" ] "ibus" osConfig;
  extensionPkgs = with pkgs.gnomeExtensions; [
    appindicator
    dash-to-dock
    clipboard-history
    upower-battery
    alphabetical-app-grid
    system-monitor-next
    # caffeine
    user-themes
    blur-my-shell
    # fcitx5
    (kimpanel.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        sed -i -e '/isLookupTableVertical() {/,/}/c\    isLookupTableVertical() { return false; }' $out/share/gnome-shell/extensions/kimpanel@kde.org/extension.js
        echo ".kimpanel-box, .kimpanel-candidate-item, .kimpanel-preedit-text, .kimpanel-candidate-text { font-family: 'LXGW WenKai GB', 'LXGW WenKai', sans-serif !important; font-size: ${kimpanelFontSize} !important; }" >> $out/share/gnome-shell/extensions/kimpanel@kde.org/stylesheet.css
      '';
    }))
  ];

  inherit (lib.hm.gvariant)
    mkArray
    mkTuple
    mkString
    mkUint32
    type
    ;
  # Toggle the GNOME/Mutter display power state via DBus.
  # writeShellApplication ensures busctl and awk are always in PATH
  # without relying on the ambient system PATH.
  toggleScreen = pkgs.writeShellApplication {
    name = "gnome-toggle-screen";
    runtimeInputs = [
      pkgs.systemd # busctl
      pkgs.gawk
    ];
    text = ''
      STATE=$(busctl --user get-property \
        org.gnome.Mutter.DisplayConfig \
        /org/gnome/Mutter/DisplayConfig \
        org.gnome.Mutter.DisplayConfig PowerSaveMode \
        | awk '{print $2}')
      if [ "$STATE" = "1" ]; then
        busctl --user set-property \
          org.gnome.Mutter.DisplayConfig \
          /org/gnome/Mutter/DisplayConfig \
          org.gnome.Mutter.DisplayConfig PowerSaveMode i 0
      else
        busctl --user set-property \
          org.gnome.Mutter.DisplayConfig \
          /org/gnome/Mutter/DisplayConfig \
          org.gnome.Mutter.DisplayConfig PowerSaveMode i 1
      fi
    '';
  };
in
{
  home.packages =
    extensionPkgs
    ++ [
      toggleScreen
    ]
    ++ (with pkgs; [
      blackbox-terminal
      kdePackages.dolphin
      gnome-tweaks
      seahorse
    ])
    ++ [
      pkgs.whitesur-gtk-theme
      pkgs.whitesur-icon-theme
    ];

  programs.chromium.extensions = [
    "gphhapmejobijbbhgpjhcjognlahblep" # GNOME Shell integration
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
      "org/gnome/desktop/wm/keybindings" = {
        switch-to-workspace-right = [ "<Control><Super>Right" ];
        switch-to-workspace-left = [ "<Control><Super>Left" ];
        move-to-workspace-right = [ "<Control><Shift><Super>Right" ];
        move-to-workspace-left = [ "<Control><Shift><Super>Left" ];
        switch-input-source =
          if imFramework == "ibus" then
            [
              "<Control>space"
            ]
          else
            [ ];
        switch-input-source-backward = [ ];
      };
      "org/gnome/settings-daemon/plugins/media-keys" = {
        control-center = [ ];
        control-center-static = [ ];
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/toggle-screen/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = mkString "NEXT";
        # https://www.reddit.com/r/gnome/comments/wencxw/almost_solved_i_wish_gnome_would_have_a_way_to/
        command = mkString "dbus-send --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:true";
        name = mkString "Power off monitor";
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/toggle-screen" = {
        binding = mkString "XF86PowerOff";
        # Nix store path — no escaping issues.
        command = mkString "${toggleScreen}/bin/gnome-toggle-screen";
        name = mkString "Toggle Screen (Power Key)";
      };
      "org/gnome/settings-daemon/plugins/housekeeping" = {
        donation-reminder-enabled = false;
      };
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (p: p.extensionUuid) extensionPkgs;
        disabled-extensions = [ ];
        disable-extension-version-validation = true;
        last-selected-power-profile = "performance";
        favorite-apps = lib.mkBefore [
          "org.gnome.Console.desktop"
          "org.gnome.Nautilus.desktop"
          "firefox.desktop"
          "chromium-browser.desktop"
          "chromium.desktop"
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
        experimental-features = [
          "scale-monitor-framebuffer"
          "variable-refresh-rate"
          "xwayland-native-scaling"
        ];
      };
      "org/gnome/desktop/interface" = {
        # scaling-factor = 1.0 * config.wayland.dpi / 96;
        # text-scaling-factor = mkDouble 1.5;

        # gtk-theme = "adw-gtk3";
        # cursor-theme = "capitaine-cursors";
        # cursor-size = 36 * config.wayland.dpi / 96;
        clock-show-weekday = true;
        show-battery-percentage = true;
        locate-pointer = true;
        enable-hot-corners = false;
      };
      "org/gnome/desktop/peripherals/keyboard" = {
        numlock-state = true;
      };
      "org/gnome/desktop/input-sources" = {
        sources =
          mkArray
            (type.tupleOf [
              type.string
              type.string
            ])
            (
              if imFramework == "ibus" then
                [
                  (mkTuple [
                    (mkString "xkb")
                    (mkString "us")
                  ])
                  (mkTuple [
                    (mkString "ibus")
                    (mkString "rime")
                  ])
                ]
              else
                [
                  (mkTuple [
                    (mkString "ibus")
                    (mkString "rime")
                  ])
                ]
            );
        per-window = imFramework == "ibus";
        # keyd handles remapping below the compositor, so leave GNOME XKB tweaks empty.
        xkb-options = mkArray type.string [ ];
      };

      # IBus general: use global engine to avoid the first-keystroke
      # passthrough bug ('shi' -> 's'+'hi') when switching windows.
      "desktop/ibus/general" = {
        use-global-engine = true;
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
        # dash-max-icon-size = 48 * config.wayland.dpi / 96;
        show-mounts = false;
        click-action = "focus-or-appspread";
        scroll-action = "switch-workspace";
        autohide = true;
        dock-fixed = false;
        intellihide = false;
        intellihide-mode = "ALL_WINDOWS";
        show-dock-urgent-notify = false;
        show-trash = false;
      };
      "org/gnome/shell/extensions/user-theme" = {
        name = "WhiteSur-Light";
      };
      # Enable blur-my-shell for premium transparent top bar
      "org/gnome/shell/extensions/blur-my-shell/panel" = {
        blur = true;
        brightness = 0.9;
        sigma = 30;
      };
      "org/gnome/shell/extensions/kimpanel" = {
        font = "LXGW WenKai 26";
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
        terminal-padding = mkTuple [
          (mkUint32 5)
          (mkUint32 5)
          (mkUint32 5)
          (mkUint32 5)
        ];
        # font = "monospace ${toString (10 * config.wayland.dpi / 96)}";
        theme-light = "Tomorrow";
        theme-dark = "Tomorrow Night";
        show-menu-button = false;
      };
    }
  ];

  home.activation.allowGdmReadFace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.acl}/bin/setfacl --modify=group:gdm:--x "$HOME"
  '';

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  gtk = {
    enable = true;
    theme = {
      name = "WhiteSur-Light-solid";
      package = pkgs.whitesur-gtk-theme;
    };
    iconTheme = {
      name = "WhiteSur-light";
      package = pkgs.whitesur-icon-theme;
    };
    cursorTheme = {
      name = "capitaine-cursors-white";
      package = pkgs.capitaine-cursors;
    };
  };
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };
  home.sessionVariables = {
    # QT_STYLE_OVERRIDE = lib.mkForce "kvantum";
    XCURSOR_THEME = config.dconf.settings."org/gnome/desktop/interface".cursor-theme;
    # Wayland variables
    CLUTTER_BACKEND = "wayland";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    # QT_QPA_PLATFORM = "wayland;xcb";
    WLR_NO_HARDWARE_CURSORS = "1";
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
      ".config/kdeconnect"
      ".local/share/keyrings"
    ];
  };
  # Override GNOME's IBus systemd service to use kimpanel-ibus-panel.
  # GNOME's built-in unit hardcodes "--panel disable", which bypasses the
  # NixOS ibus.panel option entirely. kimpanel-ibus-panel bridges IBus to the
  # kimpanel@kde.org GNOME Shell extension (which runs inside GNOME Shell and
  # can correctly position candidate popups on Wayland).
  systemd.user.services."org.freedesktop.IBus.session.GNOME" = lib.mkForce {
    Unit = {
      Description = "IBus Daemon for GNOME (kimpanel)";
      CollectMode = "inactive-or-failed";
      Requisite = [ "gnome-session-initialized.target" ];
      After = [ "gnome-session-initialized.target" ];
      PartOf = [ "gnome-session-initialized.target" ];
      Before = [ "gnome-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "org.freedesktop.IBus";
      ExecStart = [
        "${pkgs.bash}/bin/bash -c 'exec /run/current-system/sw/bin/ibus-daemon --panel ${pkgs.kdePackages.plasma-desktop}/libexec/kimpanel-ibus-panel $([ \"$XDG_SESSION_TYPE\" = \"x11\" ] && echo \"--xim\")'"
      ];
      Restart = "on-abnormal";
      TimeoutStopSec = 5;
      Slice = "session.slice";
    };
    Install = {
      WantedBy = [ "gnome-session.target" ];
    };
  };

  # Automatically switch to external monitor only when one is connected
  systemd.user.services."auto-external-monitor" = {
    Unit = {
      Description = "Automatically switch to external monitor only";
      PartOf = [ "gnome-session-initialized.target" ];
      After = [ "gnome-session-initialized.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "auto-external-monitor" ''
        # Listen to Mutter DisplayConfig signals
        ${pkgs.dbus}/bin/dbus-monitor --session "type='signal',interface='org.gnome.Mutter.DisplayConfig',member='MonitorsChanged'" | grep --line-buffered "member=MonitorsChanged" | \
        while read -r line; do
          # Give GNOME time to stabilize the display state
          sleep 1
          HAS_EXTERNAL=$(${pkgs.systemd}/bin/busctl --user get-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig HasExternalMonitor | awk '{print $2}')
          if [ "$HAS_EXTERNAL" = "true" ]; then
            ${pkgs.gnome-randr}/bin/gnome-randr modify --output eDP-1 --off
          else
            ${pkgs.gnome-randr}/bin/gnome-randr modify --output eDP-1 --on
          fi
        done
      '';
      Restart = "always";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "gnome-session.target" ];
    };
  };
}
