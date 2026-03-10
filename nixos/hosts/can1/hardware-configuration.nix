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
    "virtio_scsi"
    "sd_mod"
  ];

  utils.disk = "/dev/sda";
  networkConfig.DHCP = "yes";

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
