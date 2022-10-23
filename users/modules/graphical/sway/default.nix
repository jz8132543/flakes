{ pkgs, config, nixosConfig, lib, ... }:

let
  inherit (config.lib.formats.rasi) mkLiteral;
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
        { command = "swaymsg workspace 1"; }
        { command = "swaync"; }
        { command = "fcitx5 -d"; }
        { command = "foot"; }
        { command = "telegram-desktop"; }
        { command = "thunderbird"; }
        { command = "firefox"; }
      ];
      assigns = {
        "1" = [{ app_id = "foot"; }];
        "2" = [{ app_id = "firefox"; }];
        "3" = [{ app_id = "telegramdesktop"; }];
        "10" = [{ class = "thunderbird"; }];
        "9" = [{ app_id = "qemu"; }];
      };
      window.commands = [
        {
          criteria = { title = "Firefox — Sharing Indicator"; };
          command = "floating enable, kill";
        }
        {
          criteria = { urgent = "latest"; };
          command = "focus";
        }
      ];
      focus.newWindow = "focus";
      window.border = 0;
      gaps.inner = 10;
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
          "${modifier}+space" = "exec ${pkgs.rofi}/bin/rofi -show drun -run-command '{cmd}'";
          "${modifier}+Shift+l" = "exec loginctl lock-session";
          "${modifier}+0" = "workspace number 10";
          "${modifier}+shift+s" = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp -d)\" - | ${pkgs.wl-clipboard}/bin/wl-copy --type image/png";
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
    # mako = {
    #   enable = true;
    #   anchor = "bottom-right";
    #   layer = "overlay";

    #   backgroundColor = "#e5e7eb";
    #   progressColor = "source #d1d5db";
    #   textColor = "#334155";
    #   padding = "15,20";
    #   margin = "0,10,10,0";

    #   borderSize = 1;
    #   borderColor = "#d1d5db";
    #   borderRadius = 4;

    #   defaultTimeout = 10000;
    #   extraConfig = ''
    #     on-button-right=exec ${pkgs.mako}/bin/makoctl menu -n "$id" ${pkgs.rofi}/bin/rofi -dmenu -p 'action: '
    #     [urgency=high]
    #       ignore-timeout=1
    #       background-color=#fecaca
    #       progress-color=source #fca5a5
    #       border-color=#fca5a5
    #     [org/gnome/desktop/interface]
    #       cursor-theme='breeze_cursors'
    #   '';
    # };
    swaylock.settings = {
      show-failed-attempts = true;
      daemonize = true;
      scaling = "fill";
      image = "${bg}";
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
          font = "JetBrains Mono:size=11";
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
