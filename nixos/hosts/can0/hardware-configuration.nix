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
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # utils.disk = "/dev/sda";
  # boot.loader.grub.device = lib.mkForce "nodev";
  networking.useDHCP = true;

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
