{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../services/restic.nix
  ];

  config = {
    disko.devices.disk.main.content.partitions.NIXOS.content.subvolumes = {
      "/rootfs".mountOptions = lib.mkOverride 40 [
        "noatime"
        "compress=zstd:1"
        "space_cache=v2"
        "commit=30"
        "flushoncommit"
        "ssd_spread"
      ];
      "/nix".mountOptions = lib.mkOverride 40 [
        "noatime"
        "compress=zstd:1"
        "space_cache=v2"
        "commit=30"
        "flushoncommit"
        "ssd_spread"
      ];
      "/persist".mountOptions = lib.mkOverride 40 [
        "noatime"
        "compress=zstd:1"
        "space_cache=v2"
        "commit=30"
        "flushoncommit"
        "ssd_spread"
      ];
      "/boot".mountOptions = lib.mkOverride 40 [
        "noatime"
        "compress=zstd:1"
        "space_cache=v2"
        "commit=30"
        "flushoncommit"
        "ssd_spread"
      ];
      "/swap".mountOptions = lib.mkOverride 40 [
        "noatime"
        "nodatacow"
        "commit=30"
      ];
    };

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
  };
}
