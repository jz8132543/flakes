{
  lib,
  config,
  ...
}:
let
  cfg = config.services.linyaps;
  isDesktop = config.services.xserver.enable || config.services.gnome.core-shell.enable;
in
{
  services.linyaps = {
    enable = lib.mkDefault isDesktop;
  };

  systemd.user.services.linyaps-upgrade = lib.mkIf cfg.enable {
    description = "Upgrade installed Linyaps applications";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe cfg.package} upgrade";
    };
  };

  systemd.user.timers.linyaps-upgrade = lib.mkIf cfg.enable {
    description = "Weekly upgrade of installed Linyaps applications";
    wantedBy = [ "default.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      Unit = "linyaps-upgrade.service";
    };
  };
}
