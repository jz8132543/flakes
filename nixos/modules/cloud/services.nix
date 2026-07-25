{
  config,
  pkgs,
  lib,
  ...
}:
let
  isBtrfs = (config.disko.devices.disk.main.content.partitions.NIXOS.content.type or "") == "btrfs";
in
{
  services.btrfs.autoScrub = lib.mkIf isBtrfs {
    enable = true;
    fileSystems = [
      config.fileSystems."/nix".device
    ];
  };
  systemd.timers = lib.mkIf isBtrfs {
    btrfsBalance = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        AccuracySec = "1d";
        Persistent = true;
      };
    };
  };
  systemd.services = lib.mkIf isBtrfs {
    btrfsBalance = {
      serviceConfig = {
        Type = "exec";
        Nice = 19;
        IOSchedulingClass = "idle";
        script = ''
          ${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=30,limit=3 /
          ${pkgs.btrfs-progs}/bin/btrfs balance start -musage=30,limit=3 /
        '';
      };
    };
  };
}
