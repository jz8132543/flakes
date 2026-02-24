{
  modulesPath,
  lib,
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
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Basic networking - DHCP by default
  networking.useDHCP = true;

  # Setup the disk for deployment (assume /dev/vda for qemu virtio_blk)
  # Though the actual format etc is done by dd over the raw image.
  utils.disk = "/dev/vda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 32768;
    }
  ];
  nix.gc.automatic = lib.mkForce true;
}
