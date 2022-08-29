{ config, pkgs, modulesPath, suites, profiles, ... }: 

let

  btrfsSubvol = device: subvol: extraConfig: lib.mkMerge [
    {
      inherit device;
      fsType = "btrfs";
      options = [ "subvol=${subvol}" "compress=zstd" ];
    }
    extraConfig
  ];

  btrfsSubvolMain = btrfsSubvol "/dev/disk/by-uuid/c1f57d9c-07fe-4e03-8ad9-25b72130133b";
in{
  imports = suites.server ++ (with profiles; [
    services.acme
    services.v2ray
    services.traefik
    services.k3s
  ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [ kubernetes-helm ];

  networking.hostName = "tyo0";
  # Hardware
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules =
    [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" "kvm-amd" ];

  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      "/dev/disk/by-uuid/c1f57d9c-07fe-4e03-8ad9-25b72130133b"
    ];
  };

  fileSystems."/" = btrfsSubvolMain "@root" { neededForBoot = true; };
  fileSystems."/persist" = btrfsSubvolMain "@persist" { neededForBoot = true; };
  fileSystems."/var/log" = btrfsSubvolMain "@var-log" { neededForBoot = true; };
  fileSystems."/nix" = btrfsSubvolMain "@nix" { neededForBoot = true; };
  fileSystems."/swap" = btrfsSubvolMain "@swap" { };
  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/630C-8974";
      fsType = "vfat";
    };
  swapDevices =
    [{
      device = "/swap/swapfile";
    }];

  system.stateVersion = "22.11";
}
