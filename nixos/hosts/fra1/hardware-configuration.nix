{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = ["ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"];
  boot.kernelModules = ["kvm-amd"];
  utils.disk = "/dev/sda";
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "176.116.18.242";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a04:e8c0:18:619::";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "176.116.18.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
