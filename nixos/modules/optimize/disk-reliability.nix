{
  config,
  lib,
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

  services.fstrim.enable = lib.mkDefault true;

  services.journald.extraConfig = lib.mkOverride 40 ''
    SystemMaxUse=64M
    RuntimeMaxUse=64M
    SystemKeepFree=256M
  '';
}
