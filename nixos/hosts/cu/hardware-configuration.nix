{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_blk"
  ];

  # utils.disk = "/dev/sda";
  utils.btrfsMixed = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.105.0.56";
          prefixLength = 20;
        }
      ];
      ipv6.addresses = [
        {
          address = "2409:8a00:2640:4e01:6666:0016:3efc:9adf";
          prefixLength = 64;
        }
        {
          address = "2408:8207:25b1:2701:6666:0016:3efc:9adf";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = "10.105.0.254";
    defaultGateway6 = {
      address = "fe80::2e8:2cff:feae:bd65";
      interface = "eth0";
    };
  };

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
}
