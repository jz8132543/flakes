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
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  utils.disk = "/dev/sda";
  networking = {
    usePredictableInterfaceNames = false;

    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "94.249.174.75";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a0e:6a80:3:b60::";
          prefixLength = 64;
        }
      ];
    };

    defaultGateway = {
      address = "94.249.174.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
  };
}
