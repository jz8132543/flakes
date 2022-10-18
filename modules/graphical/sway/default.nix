{ config, pkgs, lib, ... }:

lib.mkIf (config.environment.graphical.enable && config.environment.graphical.manager == "sway" ) {
  security.polkit.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
  systemd.services.greetd.serviceConfig = {
    ExecStartPre = "${pkgs.util-linux}/bin/kill -SIGRTMIN+21 1";
    ExecStopPost = "${pkgs.util-linux}/bin/kill -SIGRTMIN+20 1";
  };
  services = {
    greetd = {
      enable = true;
      package = pkgs.greetd.tuigreet;
      settings = {
        default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd sway";
      };
    };
    logind.lidSwitch = "ignore";
  };
  environment.sessionVariables = rec {
    "WLR_NO_HARDWARE_CURSORS" = "1";
    "AWS_METADATA_SERVICE_NUM_ATTEMPTS" = "1";
  };
  environment.global-persistence = {
    files = [
    ];
    directories = [
     "/etc/NetworkManager"
    ];
    user.directories = [
      ".config/fcitx5"
      ".mozilla"
      ".local/share/TelegramDesktop"
    ];
  };
}
