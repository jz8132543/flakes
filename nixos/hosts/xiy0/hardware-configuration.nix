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
          address = "172.26.1.17";
          prefixLength = 24;
        }
      ];
    };
    interfaces.ens19 = {
      ipv4.addresses = [
        {
          address = "10.0.2.91";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "172.26.1.254";
      interface = "ens18";
    };
  };

  utils.disk = "/dev/sda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
