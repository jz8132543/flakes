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
  boot.kernelParams = ["biosdevname=0" "net.ifnames=0" "console=tty0" "console=ttyS0,115200n8"];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 8172;
    }
  ];
  networking = {
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "92.222.239.79";
          prefixLength = 25;
        }
      ];
      ipv6.addresses = [
        {
          address = "2001:41d0:308:4800:d00::a";
          prefixLength = 72;
        }
      ];
    };
    defaultGateway = {
      address = "92.222.239.126";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "2001:41d0:308:4800::2";
      interface = "eth0";
    };
  };
}
