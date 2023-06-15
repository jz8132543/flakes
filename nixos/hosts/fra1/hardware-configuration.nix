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
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  utils.disk = "/dev/sda";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "135.125.194.4";
          prefixLength = 27;
        }
      ];
      ipv6.addresses = [
        {
          address = "2001:41d0:700:508f::2872";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "135.125.189.254";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "2001:41d0:700:50ff:ff:ff:ff:ff";
      interface = "eth0";
    };
  };
}
