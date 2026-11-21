{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  options.desktop = {
    loginManager = lib.mkOption {
      type = lib.types.enum [
        "noctalia"
      ];
      default = "noctalia";
      description = "Noctalia Greeter owns the desktop login seat.";
    };
    defaultSession = lib.mkOption {
      type = lib.types.enum [
        "umbriel"
        "gnome"
      ];
      default = "umbriel";
      description = "Initial desktop session. The archived GNOME session remains optional.";
    };
    gnome.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.desktop.defaultSession != "umbriel";
      description = "Restore the complete archived GNOME configuration, optionally alongside Umbriel.";
    };
    umbriel.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.desktop.defaultSession == "umbriel";
      description = "Enable the Umbriel compositor and its user configuration.";
    };
  };

  config = {
    services.desktopManager.plasma6.enable = lib.mkForce false;
    services.displayManager.sddm.enable = lib.mkForce false;
    services.displayManager.gdm.enable = lib.mkForce false;
    services.displayManager.autoLogin.enable = lib.mkForce false;
    services.journald.settings.Journal.Storage = "persistent";
    services.displayManager.noctalia-greeter = lib.mkIf (config.desktop.loginManager == "noctalia") {
      enable = true;
      settings = {
        session.default = config.services.displayManager.defaultSession;
        user.default = "tippy";
        keyboard = {
          layout = "us";
          options = "caps:swapescape";
        };
        cursor = {
          theme = "MacTahoe-dark-cursors";
          path = "${pkgs.mactahoe.cursors}/share/icons";
          size = 24;
        };
        appearance = {
          scheme = "Noctalia";
          theme_mode = "light";
          font_family = "Inter";
          hide_logo = false;
          password_style = "default";
          power_buttons_position = "bottom-right";
          scheme_selector_position = "top-right";
          wallpaper = {
            path =
              if config.desktop.noctalia.enable && config.desktop.noctalia.showcase.enable then
                "${pkgs.wallpaper.showcase}/wallpaper.png"
              else
                "${pkgs.wallpaper}/wallpaper.jpg";
            fill_mode = "crop";
            blur = 0.0;
            tint = 0.0;
          };
        };
        clock = {
          enabled = true;
          position = "above-panel";
          time_format = "{:%H:%M}";
          date_format = "%A, %B %d";
          time_font_size = 48;
          date_font_size = 14;
        };
        idle.timeout = 300;
      };
    };
    environment.global-persistence.directories = [
      {
        directory = "/var/log/journal";
        group = "systemd-journal";
        mode = "2755";
      }
    ]
    ++ lib.optionals (config.desktop.loginManager == "noctalia") [
      {
        directory = "/var/lib/noctalia-greeter";
        user = config.services.greetd.settings.default_session.user;
        group = "greeter";
        mode = "0750";
      }
    ];
    services.displayManager.defaultSession =
      {
        gnome = "gnome";
        umbriel = "umbriel";
      }
      .${config.desktop.defaultSession};

    assertions = [
      {
        assertion = !(config.services.greetd.enable && config.services.displayManager.sddm.enable);
        message = "Noctalia Greeter and SDDM must not own the login seat simultaneously.";
      }
      {
        assertion = config.desktop.defaultSession != "gnome" || config.desktop.gnome.enable;
        message = "The default GNOME session requires desktop.gnome.enable.";
      }
      {
        assertion = config.desktop.defaultSession != "umbriel" || config.desktop.umbriel.enable;
        message = "The default Umbriel session requires desktop.umbriel.enable.";
      }
    ];
  };
}
