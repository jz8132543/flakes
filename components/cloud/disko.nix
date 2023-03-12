{ self, lib, config, ... }:
let
  mountOptions = { mountOptions = [ "discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2" ]; };
in
{
  imports = [
    self.nixosModules.disko
  ];
  options.utils.disk = lib.mkOption {
    type = types.string;
    default = "/dev/vda";
    description = "disko disk";
  };
  disko.enableConfig = true;
  disko.devices = {
    disk.vda = {
      type = "disk";
      device = "${config.utils.disk}";
      content = {
        type = "table";
        format = "gpt";
        partitions = [
          {
            name = "bios_grub";
            type = "partition";
            start = "0";
            end = "1M";
            part-type = "primary";
            flags = [ "bios_grub" ];
          }
	  {
            name = "EFI";
            type = "partition";
            start = "1MiB";
            end = "100MiB";
            fs-type = "fat32";
            bootable = true;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/efi";
            };
          }
          {
            name = "NIXOS";
            type = "partition";
            start = "1M";
            end = "100%";
            part-type = "primary";
            bootable = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/boot" = mountOptions;
                "/nix" = mountOptions;
                "/persist" = mountOptions // {
                  mountpoint = "/nix/persist";
                };
              };
            };
          }
        ];
      };
    };
    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [ "defaults" "mode=755" ];
      };
    };
  };

  fileSystems."/nix/persist".neededForBoot = true;
  boot.loader.grub = {
    enable = true;
    device = "${config.utils.disk}";
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
  };
}
