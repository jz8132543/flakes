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
  modules-left = [ "sway/workspaces" "sway/mode" "custom/media#0" "custom/media#1" ];
  modules-center = [];
  modules-right = [ "tray" "pulseaudio" "network" "memory" "cpu" "backlight" "battery#bat0" "battery#bat1" "clock" "custom/power" ];
  "sway/workspaces" = {
    all-outputs = true;
    format = "{icon}";
    format-icons = {
      "1" = "";
      "2" = "";
      "3" = "";
      "4" = "";
      "5" = "";
      "6" = "";
      "7" = "";
      "9" = "";
      "10" = "";
      focused = "";
      urgent = "";
      default = "";
    };
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
  "battery#bat0" = battery { name = "BAT0"; };
  "battery#bat1" = battery { name = "BAT1"; };
  network = {
    format-wifi = "{essid} ({signalStrength}%) ";
    format-ethernet = "Ethernet ";
    format-linked = "Ethernet (No IP) ";
    format-disconnected = "Disconnected ";
    format-alt = "{bandwidthDownBits}/{bandwidthUpBits}";
    on-click-middle = "nm-connection-editor";
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
    on-click = "pavucontrol";
  };
  "custom/media#0" = (media { number = 0; });
  "custom/media#1" = (media { number = 1; });
  "custom/power" = {
    format = "";
    on-click = "nwgbar -o 0.2";
    escape = true;
    tooltip = false;
  };
}
