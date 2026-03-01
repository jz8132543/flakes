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
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.defaultGateway = "10.105.0.254";
  networking.defaultGateway6 = {
    address = "fe80::2e8:2cff:feae:bd65";
    interface = "eth0";
  };

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
}
