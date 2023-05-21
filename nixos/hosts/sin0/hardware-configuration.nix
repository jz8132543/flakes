{ config
, lib
, pkgs
, modulesPath
, ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    defaultGateway = "128.199.64.1";
    defaultGateway6 = "2400:6180:0:d0::1";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address = "128.199.121.90"; prefixLength = 18; }
          { address = "10.15.0.5"; prefixLength = 16; }
        ];
        ipv6.addresses = [
          { address = "2400:6180:0:d0::1223:1001"; prefixLength = 64; }
          { address = "fe80::984c:faff:fee5:d166"; prefixLength = 64; }
        ];
        ipv4.routes = [{ address = "128.199.64.1"; prefixLength = 32; }];
        ipv6.routes = [{ address = "2400:6180:0:d0::1"; prefixLength = 128; }];
      };

    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="9a:4c:fa:e5:d1:66", NAME="eth0"
    ATTR{address}=="82:a1:94:ed:56:34", NAME="eth1"
  '';
}
