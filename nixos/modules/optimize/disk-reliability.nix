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

  disko.devices.disk.main.content.partitions.NIXOS.content.subvolumes."/rootfs".mountOptions =
    lib.mkForce
      [
        "noatime"
        "compress=no"
        "space_cache=v2"
        "commit=300"
        "ssd_spread"
        "thread_pool=1"
      ];

  disko.devices.disk.main.content.partitions.NIXOS.content.subvolumes."/nix".mountOptions =
    lib.mkForce
      [
        "noatime"
        "compress=no"
        "space_cache=v2"
        "commit=30"
        "flushoncommit"
        "ssd_spread"
        "thread_pool=1"
      ];

  disko.devices.disk.main.content.partitions.NIXOS.content.subvolumes."/persist".mountOptions =
    lib.mkForce
      [
        "noatime"
        "compress=no"
        "space_cache=v2"
        "commit=30"
        "flushoncommit"
        "ssd_spread"
        "thread_pool=1"
      ];

  # Prefer earlier, smaller writeback batches and a lower swap tendency so a
  # sudden power loss is less likely to leave a large dirty window behind.
  boot.kernel.sysctl = {
    "vm.dirty_background_bytes" = lib.mkOverride 40 (16 * 1024 * 1024);
    "vm.dirty_bytes" = lib.mkOverride 40 (64 * 1024 * 1024);
    "vm.dirty_writeback_centisecs" = lib.mkOverride 40 1500;
    "vm.dirty_expire_centisecs" = lib.mkOverride 40 3000;
    "vm.swappiness" = lib.mkOverride 40 60;
    "vm.page-cluster" = lib.mkOverride 40 0;
    "vm.min_free_kbytes" = lib.mkOverride 40 16384;
    "vm.watermark_scale_factor" = lib.mkOverride 40 240;
    "vm.watermark_boost_factor" = lib.mkOverride 40 0;
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
