{
  self,
  inputs,
  lib,
  config,
  ...
}: let
  mountOptions = {mountOptions = ["discard" "noatime" "nodiratime" "ssd_spread" "compress-force=zstd" "space_cache=v2"];};
in {
  imports = [
    inputs.disko.nixosModules.disko
  ];
  disko.enableConfig = true;
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "${config.utils.disk}";
      content = {
        type = "table";
        format = "gpt";
        partitions = [
          {
            name = "bios_grub";
            start = "0";
            end = "1MiB";
            part-type = "primary";
            flags = ["bios_grub"];
          }
          {
            name = "EFI";
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
            start = "210M";
            end = "100%";
            part-type = "primary";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "/nix" = mountOptions;
                "/persist" =
                  mountOptions
                  // {
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
      options = ["defaults" "mode=755"];
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
