{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = ["ata_piix" "virtio_pci" "virtio_scsi" "sr_mod"];
  boot.kernelModules = ["kvm-amd"];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  utils.disk = "/dev/sda";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16384;
    }
  ];
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "37.114.42.18";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a00:ccc1:102:25f::";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "37.114.42.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
  };
}
