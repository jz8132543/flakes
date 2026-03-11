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

  boot.loader.grub.device = lib.mkForce "nodev";
  utils.disk = "/dev/sda";

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
