{ config, pkgs, ... }:
let
  device = "/dev/disk/by-partlabel/NIXOS";
  fsType = "btrfs";
  options = [ "noatime" "compress-force=zstd" "space_cache=v2" ];
in
{
  fileSystems = {
    # "/" = {
    #   fsType = "tmpfs";
    #   options = [ "defaults" "mode=755" ];
    # };

    "/boot/EFI" = {
      device = "/dev/disk/by-partlabel/EFI";
      fsType = "vfat";
    };

    "/" = {
      inherit device fsType;
      options = [ "subvol=@ROOT" ] ++ options;
    };

    "/nix" = {
      inherit device fsType;
      options = [ "subvol=@nix" ] ++ options;
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
    postBootCommands = ''
      ${pkgs.gptfdisk}/bin/sgdisk -e -d 3 -n 3:0:0 -c 3:NIXOS -p /dev/vda
      ${pkgs.util-linux}/bin/partx -u /dev/vda
      btrfs filesystem resize max /nix
      if [ ! -f "/swap/swapfile" ]; then
        truncate -s 0 /swap/swapfile
        chattr +C /swap/swapfile
        btrfs property set /swap/swapfile compression none
        dd if=/dev/zero of=/swap/swapfile bs=1M count=1024
        chmod 0600 /swap/swapfile
        mkswap /swap/swapfile
      fi
      swapon /swap/swapfile
    '';
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/EFI";
      };
      grub = {
         efiSupport = true;
         # efiInstallAsRemovable = true;
         device = "/dev/vda";
      };
    };
  };

  # swapDevices = [ { device = "/swap/swapfile"; size = 1024; } ];
}
