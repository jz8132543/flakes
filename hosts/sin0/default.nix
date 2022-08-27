{ lib, config, pkgs, modulesPath, suites, profiles, ... }: 

let
  btrfsSubvol = device: subvol: extraConfig: lib.mkMerge [
    {
      inherit device;
      fsType = "btrfs";
      options = [ "subvol=${subvol}" "compress=zstd" ];
    }
    extraConfig
  ];
  btrfsSubvolMain = btrfsSubvol "/dev/disk/by-uuid/48503952-3b27-48a2-abfd-5a07a0a87e28";
in{
  imports =
    suites.server ++
    (with profiles; [
      services.acme
      services.traefik
      services.k3s
    ]) ++ (with profiles.users; [
      tippy
    ]);

  environment.systemPackages = with pkgs;[

  ];

  networking.hostName = "sin0";
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" ];
  boot.loader.grub = {
      enable = true;
      version = 2;
      device = "/dev/vda";
    };
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      "/dev/disk/by-uuid/48503952-3b27-48a2-abfd-5a07a0a87e28"
    ];
  };
  fileSystems."/" =
      {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "size=1G" "mode=755" ];
      };
    fileSystems."/persist" = btrfsSubvolMain "@persist" { neededForBoot = true; };
    fileSystems."/var/log" = btrfsSubvolMain "@var-log" { neededForBoot = true; };
    fileSystems."/nix" = btrfsSubvolMain "@nix" { neededForBoot = true; };
    fileSystems."/boot" =
      {
        device = "/dev/disk/by-uuid/E3E1-2EE5";
        fsType = "ext4";
      };
    swapDevices =
      [{
        device = "/dev/disk/by-uuid/6142d3f3-e44f-4a16-8d92-634e2ad033d9";
      }];
  };

  networking = {
    defaultGateway = "128.199.64.1";
    defaultGateway6 = "2400:6180:0:d0::1";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address="128.199.121.90"; prefixLength=18; }
          { address="10.15.0.5"; prefixLength=16; }
        ];
        ipv6.addresses = [
          { address="2400:6180:0:d0::1223:1001"; prefixLength=64; }
          { address="fe80::984c:faff:fee5:d166"; prefixLength=64; }
        ];
        ipv4.routes = [ { address = "128.199.64.1"; prefixLength = 32; } ];
        ipv6.routes = [ { address = "2400:6180:0:d0::1"; prefixLength = 128; } ];
      };

    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="9a:4c:fa:e5:d1:66", NAME="eth0"
    ATTR{address}=="82:a1:94:ed:56:34", NAME="eth1"
  '';
}
