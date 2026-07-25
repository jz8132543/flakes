{
  config,
  lib,
  ...
}:
{
  disko.enableConfig = true;
  disko.devices.disk.main = lib.mkForce {
    imageSize = "6G";
    type = "disk";
    device = "${config.utils.disk}";
    content = {
      type = "gpt";
      partitions = {
        BIOS = {
          label = "BIOS";
          size = "1M";
          type = "EF02";
        };
        EFI = {
          label = "EFI";
          size = "200M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/efi";
          };
        };
        NIXOS = {
          label = "NIXOS";
          end = "-0";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };

  boot.supportedFilesystems = [
    "ext4"
    "vfat"
  ];
}
