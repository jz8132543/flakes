{
  lib,
  ...
}:
{
  disko.devices.disk.main.content.partitions.NIXOS.content = lib.mkForce {
    type = "filesystem";
    format = "ext4";
    mountpoint = "/";
    mountOptions = [ "noatime" ];
  };

  boot.supportedFilesystems = [
    "ext4"
    "vfat"
  ];
}
