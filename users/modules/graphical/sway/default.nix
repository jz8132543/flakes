{ pkgs, config, nixosConfig, lib, ... }:

let
  inherit (config.lib.formats.rasi) mkLiteral;
  bg = pkgs.fetchurl {
    url = "https://github.com/KubqoA/dotfiles/raw/main/hosts/unacorda/assets/bg.jpg";
    name = "bg.jpg";
    sha256 = "14ghivp54wl6rb194x5q70ccv52qk69sn9460j50piz5ghasmxsb";
  };
in

lib.mkIf (nixosConfig.environment.graphical.enable && nixosConfig.environment.graphical.manager == "sway") {
  wayland.windowManager.sway = {
    enable = true;
    extraOptions = [ "--unsupported-gpu" ];
    wrapperFeatures.gtk = true;
    config = {
      modifier = "Mod4";
      terminal = "alacritty";
      startup = [
        { command = "swaymsg workspace 1"; }
        { command = "swaync"; }
        { command = "fcitx5 -d"; }
        { command = "alacritty"; }
        { command = "telegram-desktop"; }
        { command = "thunderbird"; }
        { command = "firefox"; }
      ];
      assigns = {
        "1" = [{ app_id = "Alacritty"; }];
        "2" = [{ app_id = "firefox"; }];
        "3" = [{ app_id = "org.telegram.desktop"; }];
        "9" = [{ app_id = "qemu"; }];
        "10" = [{ class = "thunderbird"; }];
      };
      window.commands = [
        {
          criteria = { title = "Firefox — Sharing Indicator"; };
          command = "floating enable, kill";
        }
        {
          criteria = { title = "^Picture-in-Picture$"; };
          command = "floating enable; sticky enable";
        }
        {
          criteria = { class = ".*.exe"; };
          command = "inhibit_idle fullscreen; floating enable; border none";
        }
        {
          criteria = { title = "MAX - Chromium"; };
          command = "floating enable; sticky enable; border pixel 1";
        }
        {
          criteria = { window_role = "bubble"; };
          command = "floating enable";
        }
        {
          criteria = { window_role = "pop-up"; };
          command = "floating enable";
        }
        {
          criteria = { window_role = "dialog"; };
          command = "floating enable";
        }
        {
          criteria = { window_type = "dialog"; };
          command = "floating enable";
        }
      ];
      focus.newWindow = "focus";
      window.border = 0;
      gaps = {
        inner = 5;
        outer = 5;
        smartGaps = true;
      };
      keybindings =
        let
          modifier = config.wayland.windowManager.sway.config.modifier;
        in
        lib.mkOptionDefault {
          "${modifier}+h" = "focus left";
          "${modifier}+j" = "workspace prev";
          "${modifier}+k" = "workspace next";
          "${modifier}+l" = "focus right";
          "${modifier}+s" = "split toggle";
          "${modifier}+b" = null;
          "${modifier}+v" = null;
          "${modifier}+w" = null;
          "${modifier}+n" = "exec ${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
          "${modifier}+space" = "exec ${pkgs.rofi}/bin/rofi -show run -run-command '{cmd}'";
          "${modifier}+Shift+l" = "exec loginctl lock-session";
          "${modifier}+0" = "workspace number 10";
          "${modifier}+shift+s" = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp -d)\" - | ${pkgs.wl-clipboard}/bin/wl-copy --type image/png";
          "${modifier}+ctrl+space" = "floating toggle";
          "${modifier}+ctrl+t" = "sticky toggle";
          "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
          "XF86MonBrightnessUp" = "exec ${pkgs.light}/bin/light -A 10";
          "XF86MonBrightnessDown" = "exec ${pkgs.light}/bin/light -U 10";
          "XF86AudioRaiseVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
          "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
          "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };
      input = {
        "type:keyboard" = {
          xkb_options = "caps:swapescape,caps:escape";
        };
        "type:touchpad" = {
          natural_scroll = "enabled";
          tap = "enabled";
          dwt = "enabled";
        };
      };
      output = {
        "*" = {
          bg = "${bg} fill";
        };
      };
      bars = [ ];
    };
    extraSessionCommands = ''
      export XCURSOR_THEME=breeze_cursors
      export WLR_NO_HARDWARE_CURSORS=1
    '';
  };
  programs = {
    swaylock.settings = {
      show-failed-attempts = true;
      daemonize = true;
      scaling = "fill";
      image = "${bg}";
    };
    waybar = {
      enable = true;
      settings = [ (import ./waybar.nix { inherit pkgs; }) ];
      style = builtins.readFile ./waybar.css;
      systemd.enable = true;
    };
    alacritty = {
      enable = true;
      settings = {
        import = [ ./alacritty.yml ];
        font = { size = 12.0; };
        shell = {
          program = "${pkgs.tmux}/bin/tmux";
          args = [ "new-session" "-t" "main" ];
        };
        window.opacity = 0.8;
      };
    };
    rofi = {
      enable = true;
      plugins = [
        pkgs.rofi-emoji
        pkgs.rofi-calc
        pkgs.rofi-power-menu
      ];
      extraConfig = {
        modi = "drun";
        show-icons = true;
        sort = true;
        # matching = "fuzzy";
      };
      theme = "rounded-blue-dark.rasi";
    };
  };
  home.file.".config/rofi/rounded-blue-dark.rasi".source = ./rounded-blue-dark.rasi;
  xdg = {
    enable = true;
  };
  services = {
    swayidle = {
      enable = true;
      timeouts = [
        { timeout = 900; command = "${pkgs.swaylock}/bin/swaylock"; }
        { timeout = 905; command = ''swaymsg "output * dpms off"''; resumeCommand = ''swaymsg "output * dpms on"''; }
      ];
      events = [
        { event = "lock"; command = "${pkgs.swaylock}/bin/swaylock"; }
      ];
    };
  };
  systemd.user = {
    targets.sway-session.Unit.Wants = [ "xdg-desktop-autostart.target" ];
  };
}
