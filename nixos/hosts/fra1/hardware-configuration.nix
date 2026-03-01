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
    "sr_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  utils.disk = "/dev/sda";
  networking.defaultGateway = {
    address = "176.116.18.1";
    interface = "eth0";
  };
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "eth0";
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  nix.gc.automatic = lib.mkForce false;
}
