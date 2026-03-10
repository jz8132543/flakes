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
  networking.useDHCP = true;

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
