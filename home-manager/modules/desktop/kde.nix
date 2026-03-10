{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.desktop;
  toTitle =
    str: "${lib.toUpper (lib.substring 0 1 str)}${lib.substring 1 (lib.stringLength str) str}";
  orchis-theme = pkgs.orchis-theme.override {
    tweaks = [ config.home.catppuccin.tweak ];
  };
  accentColors = {
    blue = "137,180,250";
    cyan = "125,207,255";
    orange = "255,158,100";
    pink = "245,194,231";
    green = "166,227,161";
  };

  mkBarMonitor = label: sensor: color: {
    systemMonitor = {
      displayStyle = "org.kde.ksysguard.barchart";
      showLegend = false;
      showTitle = false;
      totalSensors = [ sensor ];
      sensors = [
        {
          name = sensor;
          inherit color label;
        }
      ];
      range = {
        from = 0;
        to = 100;
      };
    };
  };

  mkLineMonitor = sensorDefs: {
    systemMonitor = {
      displayStyle = "org.kde.ksysguard.linechart";
      showLegend = false;
      showTitle = false;
      totalSensors = map (sensor: sensor.name) sensorDefs;
      sensors = sensorDefs;
    };
  };
in
lib.mkIf (cfg.environment == "kde") {
  home.packages = with pkgs; [
    klassy
    kdePackages.partitionmanager
    kdePackages.plasma-browser-integration
    kdePackages.plasma-systemmonitor
    kdePackages.koi
    tela-circle-icon-theme
  ];

  gtk = {
    enable = true;
    theme = {
      name = "Orchis-Light-${toTitle config.home.catppuccin.tweak}";
      package = orchis-theme;
    };
    iconTheme = {
      name = "Tela-circle";
      package = pkgs.tela-circle-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "kde";
    style = {
      name = "klassy";
      package = pkgs.klassy;
    };
  };

  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

  programs.plasma = {
    enable = true;

    workspace = {
      clickItemTo = "select";
      theme = "kite-light";
      widgetStyle = "klassy";
      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
      };
      iconTheme = "Tela-circle";
      wallpaper = "${pkgs.wallpaper}/wallpaper.jpg";
      wallpaperBackground = {
        blur = true;
      };
    };

    fonts = {
      general = {
        family = "Noto Sans";
        pointSize = 10;
      };
      fixedWidth = {
        family = "JetBrainsMono Nerd Font Mono";
        pointSize = 10;
      };
      menu = {
        family = "Noto Sans";
        pointSize = 10;
      };
      small = {
        family = "Noto Sans";
        pointSize = 9;
      };
      toolbar = {
        family = "Noto Sans";
        pointSize = 10;
      };
      windowTitle = {
        family = "Noto Sans";
        pointSize = 10;
      };
    };

    hotkeys.commands = {
      "launch-kitty" = {
        key = "Meta+Return";
        command = "kitty";
        name = "Launch Kitty";
      };
      "launch-dolphin" = {
        key = "Meta+E";
        command = "dolphin";
        name = "Launch Dolphin";
      };
    };

    panels = [
      {
        location = "top";
        floating = true;
        alignment = "center";
        lengthMode = "fit";
        height = 38;
        widgets = [
          (mkBarMonitor "CPU" "cpu/all/usage" accentColors.blue)
          (mkBarMonitor "RAM" "memory/physical/usedPercent" accentColors.cyan)
          (mkBarMonitor "GPU" "gpu/gpu0/usage" accentColors.orange)
          (mkBarMonitor "TEMP" "cpu/all/averageTemperature" accentColors.pink)
          (mkLineMonitor [
            {
              name = "network/all/download";
              color = accentColors.green;
              label = "NET D";
            }
            {
              name = "network/all/upload";
              color = accentColors.blue;
              label = "NET U";
            }
          ])
          "org.kde.plasma.marginsseparator"
          {
            systemTray.items = {
              shown = [
                "org.kde.plasma.networkmanagement"
                "org.kde.plasma.bluetooth"
                "org.kde.plasma.volume"
                "org.kde.plasma.brightness"
                "org.kde.kdeconnect"
                "org.fcitx.Fcitx5"
              ];
            };
          }
          {
            digitalClock = {
              time.format = "24h";
              date.position = "besideTime";
              calendar.firstDayOfWeek = "monday";
            };
          }
        ];
      }
      {
        location = "bottom";
        floating = true;
        hiding = "dodgewindows";
        alignment = "center";
        lengthMode = "fit";
        height = 50;
        widgets = [
          {
            kickoff = {
              sortAlphabetically = true;
              icon = "nix-snowflake";
            };
          }
          {
            iconTasks = {
              launchers = [
                "applications:firefox.desktop"
                "applications:kitty.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:org.kde.plasma-systemmonitor.desktop"
                "applications:code.desktop"
              ];
            };
          }
        ];
      }
    ];

    kwin = {
      edgeBarrier = 0;
      cornerBarrier = false;
      effects = {
        blur = {
          enable = true;
          strength = 8;
          noiseStrength = 2;
        };
        translucency.enable = true;
        desktopSwitching.animation = "slide";
        windowOpenClose.animation = "glide";
      };
    };

    kscreenlocker = {
      autoLock = true;
      lockOnResume = true;
      timeout = 15;
      appearance.wallpaper = "${pkgs.wallpaper}/wallpaper.jpg";
    };

    powerdevil = {
      AC = {
        turnOffDisplay.idleTimeout = 20 * 60;
        dimDisplay.enable = false;
      };
      battery = {
        dimDisplay.enable = true;
        turnOffDisplay.idleTimeout = 10 * 60;
      };
    };

    configFile = {
      "dolphinrc"."General"."BrowseThroughArchives" = true;
      "dolphinrc"."General"."RememberOpenedTabs" = false;
      "kwinrc"."Desktops"."Number" = 6;
      "kwinrc"."Plugins"."slideEnabled" = true;
      "kwinrc"."Wayland"."InputMethod[$e]" = "${pkgs.fcitx5}/share/applications/org.fcitx.Fcitx5.desktop";
      "kwinrc"."Wayland"."VirtualKeyboardEnabled" = "true";
      "kdeglobals"."Icons"."Theme" = "Tela-circle";
    };
  };

  home.global-persistence = {
    directories = [ ".local/share/color-schemes" ];
  };
}
