{ config, pkgs, lib, ... }:
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

    "/boot/efi" = {
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
    initrd.postDeviceCommands = pkgs.lib.mkBefore ''
      if [ ! -f "/dev/vda" ]; then
        if [ -f "/dev/sda" ]; then
          for i in {"",1,2,3}
          do
            ln -s /dev/sda$i /dev/vda$i
          done
        fi
      fi
      mkdir -p /mnt
      mount /dev/disk/by-partlabel/NIXOS /mnt
      chattr -i /var/empty
      rm -rf /mnt/@ROOT/*
      btrfs subvolume delete -C /mnt/@ROOT
      btrfs subvolume create /mnt/@ROOT
    '';
    loader = {
      efi = {
        efiSysMountPoint = "/boot/efi";
      };
      grub = {
        enable = true;
        configurationLimit = 10; # It limits max entires to 10
        efiSupport = true;
        efiInstallAsRemovable = true;
        device = "/dev/vda";
        theme = lib.mkDefault pkgs.libsForQt5.breeze-grub;
        gfxmodeEfi = lib.mkDefault "text";
        gfxmodeBios = lib.mkDefault "text";
        gfxpayloadEfi = lib.mkDefault "1920x1080";
        gfxpayloadBios = lib.mkDefault "1920x1080";
      };
      timeout = 1;
    };
    supportedFilesystems = [ "vfat" "btrfs" ];
    kernelPackages = pkgs.linuxPackages_latest;
  };

  environment.global-persistence = {
    enable = true;
    root = "/persist";
  };

  # swapDevices = [ { device = "/swap/swapfile"; size = 1024; } ];
}
