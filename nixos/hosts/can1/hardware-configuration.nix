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

  networking = {
    useDHCP = true;
    interfaces.ens18 = {
      ipv4.addresses = [
        {
          address = "192.168.11.67";
          prefixLength = 24;
        }
      ];
    };
    interfaces.ens19 = {
      ipv4.addresses = [
        {
          address = "192.168.11.67";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.11.1";
      interface = "ens18";
    };
  };

  utils.disk = "/dev/sda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
