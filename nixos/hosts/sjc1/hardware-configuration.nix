{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "sr_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  utils.disk = "/dev/vda";
  cloud.btrfsSwapPartition.enable = true;

  networking = {
    useDHCP = false;
    interfaces = {
      ens7.ipv4.addresses = [
        {
          address = "107.148.211.96";
          prefixLength = 25;
        }
      ];
      ens8.ipv4.addresses = [
        {
          address = "10.91.42.3";
          prefixLength = 23;
        }
      ];
    };
    defaultGateway = {
      address = "107.148.211.126";
      interface = "ens7";
    };
  };
}
