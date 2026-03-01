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
    "sr_mod"
    "virtio_blk"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  utils.disk = "/dev/vda";
  # defaultGateway = {
  #   address = "176.116.18.1";
  #   interface = "eth0";
  # };
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "ens3";
  };
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 32768;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  nix.gc.automatic = lib.mkForce false;
}
