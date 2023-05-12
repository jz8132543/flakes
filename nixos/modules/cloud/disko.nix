{ self, lib, config, ... }:
let
  mountOptions = { mountOptions = [ "discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2" ]; };
in
{
  imports = [
    self.nixosModules.disko
  ];
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
            end = "200MiB";
            fs-type = "fat32";
            bootable = true;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          }
          {
            name = "NIXOS";
            type = "partition";
            start = "210M";
            end = "100%";
            part-type = "primary";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
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
    # nodev = {
    #   "/" = {
    #     fsType = "tmpfs";
    #     mountOptions = [ "defaults" "mode=755" ];
    #   };
    # };
  };

  fileSystems = {
    "/" = {
      fsType = "tmpfs";
      options = [ "defaults" "mode=755" ];
    };
    "/boot" = {
      device = lib.mkForce "/dev/disk/by-partlabel/EFI";
    };

    "/nix" = {
      device = lib.mkForce "/dev/disk/by-partlabel/NIXOS";
    };

    "/nix/persist" = {
      device = lib.mkForce "/dev/disk/by-partlabel/NIXOS";
      neededForBoot = true;
    };
  };

  boot.loader.grub = {
    enable = true;
    device = "${config.utils.disk}";
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
  };
}
