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
  };
  kdeMaterialYouColors = pkgs.python3Packages.kde-material-you-colors;

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

  frostedPanelWidget = {
    plasmaPanelColorizer = {
      general = {
        enable = true;
        hideWidget = true;
      };
      panelBackground = {
        originalBackground = {
          hide = true;
        };
        customBackground = {
          enable = true;
          colorSource = "system";
          system = {
            color = "background";
            colorSet = "header";
          };
          opacity = 0.72;
          radius = 24;
          outline = {
            colorSource = "system";
            system = {
              color = "focus";
              colorSet = "selection";
            };
            opacity = 0.22;
            width = 1;
          };
          shadow = {
            color = "#3a000000";
            size = 18;
            horizontalOffset = 0;
            verticalOffset = 4;
          };
        };
      };
      layout = {
        enable = true;
        backgroundMargin = {
          horizontal = 10;
          vertical = 8;
        };
      };
    };
  };
in
lib.mkIf (cfg.environment == "kde") {
  home.packages = with pkgs; [
    kdePackages.partitionmanager
    kdePackages.plasma-browser-integration
    kdePackages.plasma-systemmonitor
    kdePackages.koi
    plasma-panel-colorizer
    tela-circle-icon-theme
    kdeMaterialYouColors
  ];

  gtk = {
    enable = true;
    theme = {
      name = "Orchis-Light-${toTitle config.home.catppuccin.tweak}";
      package = orchis-theme;
    };
    iconTheme = {
      name = "Tela-circle-dark";
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
      name = "breeze";
      package = pkgs.kdePackages.breeze;
    };
  };

  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

  xdg.configFile."kde-material-you-colors/config.conf".text = ''
    [CUSTOM]
    monitor = 0
    iconslight = Tela-circle-light
    iconsdark = Tela-circle-dark
    disable_konsole = True
    use_startup_delay = True
    startup_delay = 4
    main_loop_delay = 2
    screenshot_delay = 900
    once_after_change = True
    scheme_variant = 6
    chroma_multiplier = 1.15
    tone_multiplier = 0.95
    manual_fetch = False
  '';

  systemd.user.services.kde-material-you-colors = {
    Unit = {
      Description = "Wallpaper-driven KDE Material You colors";
      Wants = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${kdeMaterialYouColors}/bin/kde-material-you-colors";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  programs.plasma = {
    enable = true;

    workspace = {
      clickItemTo = "select";
      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
      };
      iconTheme = "Tela-circle-dark";
      lookAndFeel = "org.kde.breezedark.desktop";
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
          frostedPanelWidget
          (mkBarMonitor "CPU" "cpu/all/usage" accentColors.blue)
          (mkBarMonitor "RAM" "memory/physical/usedPercent" accentColors.cyan)
          (mkBarMonitor "GPU" "gpu/gpu0/usage" accentColors.orange)
          (mkBarMonitor "TEMP" "cpu/all/averageTemperature" accentColors.pink)
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
          frostedPanelWidget
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
      "kdeglobals"."Icons"."Theme" = "Tela-circle-dark";
    };
  };

  home.global-persistence = {
    directories = [
      ".cache/kde-material-you-colors"
      ".config/kde-material-you-colors"
      ".local/share/color-schemes"
    ];
  };
}
