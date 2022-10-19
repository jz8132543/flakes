{ pkgs, config, nixosConfig, lib, ... }:

let
  bg = pkgs.fetchurl {
    url = "https://github.com/KubqoA/dotfiles/raw/main/hosts/unacorda/assets/bg.jpg";
    name = "bg.jpg";
    sha256 = "14ghivp54wl6rb194x5q70ccv52qk69sn9460j50piz5ghasmxsb";
  };
in

lib.mkIf (nixosConfig.environment.graphical.enable && nixosConfig.environment.graphical.manager == "sway" ) {
  wayland.windowManager.sway = {
    enable = true;
    extraOptions = [ "--unsupported-gpu" ];
    wrapperFeatures.gtk = true;
    config = {
      modifier = "Mod4";
      terminal = "foot";
      startup = [
        { command = "fcitx5 -d"; }
        { command = "foot"; }
        { command = "firefox"; }
        { command = "telegram-desktop"; }
        { command = "thunderbird"; }
      ];
      assigns = {
        "1" = [{ app_id = "foot"; }];
        "2" = [{ app_id = "firefox"; }];
        "3" = [{ app_id = "telegramdesktop"; }];
        "4" = [{ class = "thunderbird"; }];
        "5" = [{ app_id = "qemu"; }];
      };
      window.commands = [
        {
          criteria = { title = "Firefox — Sharing Indicator"; };
          command = "floating enable, kill";
        }
        {
          criteria = { app_id = "pavucontrol"; };
          command = "floating enable, sticky enable, resize set width 550 px height 600px, move position cursor, move down 35";
        }
        {
          criteria = { urgent = "latest"; };
          command = "focus";
        }
      ];
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
          "${modifier}+space" = "exec ${pkgs.rofi}/bin/rofi -show run -run-command '{cmd}'";
          "${modifier}+Shift+l" = "exec loginctl lock-session";
          "${modifier}+d" = null;
          "Print" = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" $HOME/Pictures/screenshot-$(date +\"%Y-%m-%d-%H-%M-%S\").png";
          "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
          "XF86MonBrightnessUp" = "exec ${pkgs.light}/bin/light -A 10";
          "XF86MonBrightnessDown" = "exec ${pkgs.light}/bin/light -U 10";
          "XF86AudioRaiseVolume" = "exec ${pkgs.alsa-utils}/bin/amixer set Master 5%+";
          "XF86AudioLowerVolume" = "exec ${pkgs.alsa-utils}/bin/amixer set Master 5%-";
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
  };
  programs = {
    mako = {
      enable = true;
      extraConfig = ''
        on-button-right=exec ${pkgs.mako}/bin/makoctl menu -n "$id" ${pkgs.rofi}/bin/rofi -dmenu -p 'action: '
      '';
    };
    swaylock.settings = {
      show-failed-attempts = true;
      daemonize = true;
      scaling = "fill";
    };
    waybar = {
      enable = true;
      settings = [ (import ./waybar.nix { inherit pkgs lib; }) ];
      style = builtins.readFile ./waybar.css;
      systemd.enable = true;
    };
    tmux = {
      enable = true;
      baseIndex = 1;
      escapeTime = 10;
      shell = "${pkgs.zsh}/bin/zsh";
      keyMode = "vi";
      terminal = "screen-256color";
      extraConfig = ''
        set -g status-position top
        set -g set-clipboard on
        set -g mouse on
        set -g status-right ""
        set -g renumber-windows on
        new-session -s main
      '';
    };
    foot = {
      enable = true;
      settings = {
        main = {
          shell = "${pkgs.tmux}/bin/tmux new-session -t main";
          font = "JetBrains Mono:size=10";
        };
        cursor = {
          color = "323d43 7fbbb3";
        };
        colors = {
          background = "323d43";
          foreground = "d8cacc";
          regular0 = "4a555b";
          regular1 = "e68183";
          regular2 = "a7c080";
          regular3 = "dbbc7f";
          regular4 = "7fbbb3";
          regular5 = "d699b6";
          regular6 = "83c092";
          regular7 = "d8caac";
          bright0 = "525c62";
          bright1 = "e68183";
          bright2 = "a7c080";
          bright3 = "dbbc7f";
          bright4 = "7fbbb3";
          bright5 = "d699b6";
          bright6 = "83c092";
          bright7 = "d8caac";
          selection-foreground = "3c474d";
          selection-background = "525c62";
        };
      };
    };
  };
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
