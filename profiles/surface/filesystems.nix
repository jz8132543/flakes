{ config, pkgs, lib, ... }:
let
  device = "/dev/disk/by-partlabel/NIXOS";
  fsType = "btrfs";
  options = [ "noatime" "compress-force=zstd" "space_cache=v2" ];
in
{
  fileSystems = {
    "/" = {
      fsType = "tmpfs";
      options = [ "defaults" "mode=755" ];
    };

    "/boot" = {
      device = "/dev/disk/by-partlabel/EFI";
      fsType = "vfat";
    };

    "/nix" = {
      inherit device fsType;
      options = [ "subvol=nix" ] ++ options;
    };

    "/nix/persist" = {
      inherit device fsType;
      options = [ "subvol=persist" ] ++ options;
      neededForBoot = true;
    };
  };

  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
      };
      grub = {
        enable = true;
        configurationLimit = 10;
        efiSupport = true;
        device = "nodev";
      };
      timeout = 1;
    };
    supportedFilesystems = [ "vfat" "btrfs" "ntfs" ];
  };
}
