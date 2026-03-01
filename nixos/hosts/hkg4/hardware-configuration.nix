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
    "virtio_pci"
    "virtio_scsi"
    "sr_mod"
    "virtio_blk"
  ];
  # utils.disk = "/dev/sda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.defaultGateway = "123.254.105.158";

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
  hardware.enableRedistributableFirmware = lib.mkForce false;
}
