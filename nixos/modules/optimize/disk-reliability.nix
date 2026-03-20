{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.btrfs.autoScrub = {
    enable = lib.mkOverride 40 true;
    interval = lib.mkOverride 40 "monthly";
    fileSystems = lib.mkDefault [
      config.fileSystems."/nix".device
    ];
  };

  systemd.timers.btrfsBalance.enable = lib.mkForce false;
  systemd.services.btrfsBalance.enable = lib.mkForce false;

  systemd.services.btrfsMetadataDup = {
    description = "Convert Btrfs metadata/system chunks to DUP profile";
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    path = [ pkgs.btrfs-progs ];
    script = ''
      btrfs fi balance start -mconvert=dup -sconvert=dup -musage=0 -susage=0 /
    '';
  };

  systemd.timers.btrfsMetadataDup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      RandomizedDelaySec = "6h";
      Persistent = true;
    };
  };

  services.fstrim.enable = lib.mkDefault true;

  services.journald.extraConfig = lib.mkOverride 40 ''
    SystemMaxUse=64M
    RuntimeMaxUse=64M
    SystemKeepFree=256M
  '';
}
