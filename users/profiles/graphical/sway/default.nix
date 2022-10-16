{ pkgs, config, lib, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    extraOptions = [ "--unsupported-gpu" ];
    wrapperFeatures.gtk = true;
    config = {
      modifier = "Mod4";
      terminal = "systemd-run-app foot";
      startup = [
        { command = "systemd-run-app foot"; }
      ];
      assigns = {
        "1" = [{ app_id = "foot"; }];
        "2" = [{ app_id = "firefox"; }];
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
          "${modifier}+j" = "focus down";
          "${modifier}+k" = "focus up";
          "${modifier}+l" = "focus right";
          "${modifier}+s" = "split toggle";
          "${modifier}+b" = null;
          "${modifier}+v" = null;
          "${modifier}+w" = null;
          "${modifier}+d" = "exec ${pkgs.rofi}/bin/rofi -show run -run-command 'systemd-run-app {cmd}'";
          "${modifier}+Shift+l" = "exec loginctl lock-session";
          "${modifier}+space" = null;
          "Print" = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" $HOME/Pictures/screenshot-$(date +\"%Y-%m-%d-%H-%M-%S\").png";
          "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
        };

    };
  };
  programs = {
    sway = {
      enable = true;
      extraPackages = with pkgs; [
        swaylock
        swayidle
      ];
    };
  };
  home.packages = with pkgs; [
    systemd-run-app
  ];
}
