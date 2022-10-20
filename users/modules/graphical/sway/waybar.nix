{ pkgs, lib, ... }:

let
  battery = { name } : {
    bat = name;
    states = {
      warning = 30;
      critical = 15;
    };
    format = "{capacity}% {icon}";
    format-charging = "{capacity}% ";
    format-plugged = "{capacity}% ";
    format-alt = "{time} {icon}";
    format-icons = [ "" "" "" "" "" ];
  };
  media = { number } : {
    format = "{icon} {}";
    return-type = "json";
    max-length = 55;
    format-icons = {
      Playing = "";
      Paused = "";
    };
    exec = "mediaplayer ${toString number}";
    exec-if = "[ $(playerctl -l 2>/dev/null | wc -l) -ge ${toString (number + 1)} ]";
    interval = 1;
    on-click = "play-pause ${toString number}";
  };
in
with lib;
{
  height = 40;
  modules-left = [ "sway/workspaces" "sway/mode" ];
  modules-center = [ "sway/window" ];
  modules-right = [ "tray" "idle_inhibitor" "pulseaudio" "network" "memory" "cpu" "backlight" "battery" "clock" "custom/power" ];
  "sway/workspaces" = {
    all-outputs = true;
    format = "{icon}";
    format-icons = { "1" = ""; "2" = ""; "3" = ""; "4" = ""; default = ""; focused = ""; urgent = ""; };
  };
  tray = {
    spacing = 10;
  };
  clock = {
    tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
    format-alt = "{:%A, %d %b}";
  };
  cpu = {
    format = "{usage}% ";
  };
  memory = {
    format = "{}% ";
  };
  backlight = {
    format = "{icon}";
    format-alt = "{percent}% {icon}";
    format-alt-click = "click-right";
    format-icons = [ "○" "◐" "●" ];
    on-scroll-down = "light -U 10";
    on-scroll-up = "light -A 10";
  };
  battery = {
    format = "{capacity}% {icon}";
    format-alt = "{time} {icon}";
    format-charging = "{capacity}% ";
    format-icons = [ "" "" "" "" "" ];
    format-plugged = "{capacity}% ";
    states = { critical = 10; warning = 20; };
  };
  network = {
    format-wifi = "{essid} ({signalStrength}%) ";
    format-ethernet = "Ethernet ";
    format-linked = "Ethernet (No IP) ";
    format-disconnected = "Disconnected ";
    format-alt = "{bandwidthDownBytes}/{bandwidthUpBytes}";
    on-click-middle = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
  };
  pulseaudio = {
    scroll-step = 1;
    format = "{volume}% {icon} {format_source}";
    format-bluetooth = "{volume}% {icon} {format_source}";
    format-bluetooth-muted = " {icon} {format_source}";
    format-muted = " {format_source}";
    format-source = "{volume}% ";
    format-source-muted = "";
    format-icons = {
        headphone = "";
        hands-free = "";
        headset = "";
        phone = "";
        portable = "";
        car = "";
        default = [ "" "" "" ];
    };
    on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
  };
  idle_inhibitor = {
    format = "{icon}";
    format-icons = { activated = ""; deactivated = ""; };
  };
  "custom/power" = {
    format = "";
    on-click = "${pkgs.nwg-launchers}/bin/nwgbar -o 0.2";
    escape = true;
    tooltip = false;
  };
}
