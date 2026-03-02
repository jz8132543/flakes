{
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # disko.devices.disk.main.imageSize = "8G";
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "ahci"
    "sd_mod"
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Basic networking - DHCP by default
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "e*";
      networkConfig.DHCP = "yes";
      address = [
        "82.40.41.218/24"
        "2a13:edc0:24:1d5::a/64"
      ];
      routes = [
        { Gateway = "82.40.41.1"; }
        { Gateway = "2a13:edc0:24::1"; }
      ];
    };
  };

  # Setup the disk for deployment (assume /dev/vda for qemu virtio_blk)
  # Though the actual format etc is done by dd over the raw image.
  utils.disk = "/dev/vda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 1024;
    }
  ];
  nix.gc.automatic = lib.mkForce true;
}
