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

    # "/" = {
    #   inherit device fsType;
    #   options = [ "subvol=@ROOT" ] ++ options;
    # };

    "/boot/efi" = {
      device = "/dev/disk/by-partlabel/EFI";
      fsType = "vfat";
    };

    "/nix" = {
      inherit device fsType;
      options = [ "subvol=@nix" ] ++ options;
    };

    "/boot" = {
      inherit device fsType;
      options = [ "subvol=@boot" ] ++ options;
    };

    "/persist" = {
      inherit device fsType;
      options = [ "subvol=@persist" ] ++ options;
      neededForBoot = true;
    };

    "/swap" = {
      inherit device fsType;
      options = [ "subvol=@swap" ] ++ options;
    };
  };

  boot = {
    loader = {
      efi = {
        efiSysMountPoint = "/boot/efi";
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

  # swapDevices = [ { device = "/swap/swapfile"; size = 1024; } ];
}
