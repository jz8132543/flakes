{
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.enableConfig = true;
  disko.devices = {
    disk.main = {
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
  };

  boot.supportedFilesystems = [
    "ext4"
    "vfat"
  ];

  boot = {
    growPartition = lib.mkDefault true;
    loader = {
      timeout = 2;
      efi.efiSysMountPoint = "/boot/efi";
      grub = {
        enable = true;
        device = "${config.utils.disk}";
        efiSupport = lib.mkDefault true;
        efiInstallAsRemovable = lib.mkDefault true;
      };
    };
  };
}
