{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  upstreamKeybinds =
    (builtins.fromTOML (builtins.readFile "${inputs.umbriel}/examples/config.toml")).keybinds;
in
{
  imports = [ inputs.umbriel.homeModules.default ];

  config = lib.mkIf osConfig.desktop.umbriel.enable {
    window-manager = {
      enable = lib.mkDefault true;
      sessionTarget = lib.mkDefault "umbriel-session.target";
    };
    programs.noctalia.settings = lib.mkIf osConfig.desktop.noctalia.enable {
      shell = {
        umbriel_overview_type_to_launch_enabled = lib.mkDefault true;
        umbriel_overview_close_on_launch_enabled = lib.mkDefault true;
      };
      # Our optional include is declared below; no hook may rewrite config.toml.
      theme.templates.user.umbriel = {
        input_path = lib.mkDefault "${config.programs.noctalia.package}/share/noctalia/assets/templates/umbriel/umbriel.toml";
        output_path = lib.mkDefault "$XDG_CONFIG_HOME/umbriel/noctalia.toml";
      };
    };
    # Umbriel's autostart owns Fcitx; do not start a second daemon for this session.
    # Retain the upstream desktop entry for any other installed session.
    xdg.configFile."autostart/org.fcitx.Fcitx5.desktop" =
      lib.mkIf (osConfig.desktop.inputMethod.framework == "fcitx5")
        {
          source = pkgs.runCommand "fcitx5-session-autostart.desktop" { } ''
            install -m 0644 ${osConfig.i18n.inputMethod.package}/etc/xdg/autostart/org.fcitx.Fcitx5.desktop "$out"
            printf '\nNotShowIn=Umbriel;umbriel;\n' >> "$out"
          '';
        };
    programs.umbriel = {
      enable = true;
      package = osConfig.programs.umbriel.package;
      settings = {
        include = {
          files = [ "${config.programs.umbriel.package}/share/umbriel/effects/border/pulse/effect.toml" ];
          optional.files = [ "noctalia.toml" ];
        };
        general = {
          # Noctalia is a Type=notify service bound to umbriel-session.target.
          autostart = lib.optional (
            osConfig.desktop.inputMethod.framework == "fcitx5"
          ) "${osConfig.i18n.inputMethod.package}/bin/fcitx5 -d";
          xwayland = true;
          xwayland_native_resolution = lib.mkDefault true;
        };
        environment = {
          NIXOS_OZONE_WL = "1";
          MOZ_ENABLE_WAYLAND = "1";
          ELECTRON_OZONE_PLATFORM_HINT = "wayland";
          XCURSOR_THEME = "MacTahoe-dark-cursors";
          XCURSOR_SIZE = "24";
          QT_QPA_PLATFORMTHEME = "gtk3";
        }
        // lib.optionalAttrs (osConfig.desktop.inputMethod.framework == "fcitx5") {
          QT_IM_MODULE = "fcitx";
          SDL_IM_MODULE = "fcitx";
          XMODIFIERS = "@im=fcitx";
        };
        layout = {
          mode = "scrolling";
          gap = 0;
          extent_presets = [
            0.333
            0.5
            0.667
            1.0
          ];
          scrolling.default_extent_fraction = 0.5;
        };
        input = {
          keyboard = {
            layout = "us";
            options = "caps:swapescape";
            numlock_toggle = true;
          };
          touchpad = {
            tap = true;
            natural_scroll = true;
            disable_while_typing = true;
          };
          focus = {
            follows_mouse = "sloppy";
            follows_mouse_max_scroll = 0.0;
          };
          cursor = {
            theme = "MacTahoe-dark-cursors";
            size = 24;
            hide_when_typing = true;
          };
        };
        appearance = {
          corner_radius = 12;
          border_width = 1;
          blur = {
            enabled = true;
            optimized = true;
            passes = 3;
            radius = 10;
            contrast = 0.9;
            brightness = 0.9;
            saturation = 1.1;
          };
          shadow = {
            enabled = true;
            softness = 18;
          };
        };
        colors.border = {
          focused = "#292933";
          unfocused = "#1F2026";
        };
        effects = {
          border = "pulse";
          max_fps = 60;
        };
        # Avoid applying a second animation to Noctalia's animated layer surfaces.
        animation.layers.enabled = false;
        window_rule = [
          { blur = true; }
          {
            match.app_id = "^dev.noctalia.Noctalia$";
            default_floating = true;
            default_floating_size_px = {
              width = 1020;
              height = 900;
            };
          }
          {
            match.app_id = "^dev.noctalia.UmbrielSharePicker$";
            default_floating = true;
            default_floating_size_px = {
              width = 800;
              height = 600;
            };
          }
          {
            match.title = "^(Picture-in-Picture|Picture in picture)$";
            default_floating = true;
          }
          {
            match.app_id = "^kitty$";
            border_width = 0;
            outer_border_width = 0;
            border_effect = "off";
            blur = true;
            blur_optimized = false;
          }
        ];
        layer_rule = [
          {
            match.namespace = "^noctalia-(bar-.*|notification|dock|panel|attached-panel|osd|desktop-widget-.*)$";
            blur = true;
            blur_ignore_alpha = 0.05;
            blur_popups = true;
          }
          # The compositor masks bar blur by client alpha, leaving transparent gaps clear.
          {
            match.namespace = "^noctalia-bar-main$";
            blur = true;
            blur_ignore_alpha = 0.05;
            blur_optimized = false;
          }
          {
            match.namespace = "^noctalia-(panel|attached-panel|notification|osd)$";
            blur_optimized = false;
          }
        ];
        # Follow the locked upstream starting config, except for modifier-only taps.
        keybinds = builtins.removeAttrs upstreamKeybinds [
          "Mod"
          "Super"
        ];
      };
    };
    home.global-persistence.directories = lib.mkIf config.home.global-persistence.enabled [
      {
        directory = lib.removePrefix "${config.home.homeDirectory}/" "${config.xdg.configHome}/umbriel";
        mode = "0700";
      }
    ];
  };
}
