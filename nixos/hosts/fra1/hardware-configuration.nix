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
          address = "92.222.239.55";
          prefixLength = 32;
        }
      ];
      ipv6.addresses = [
        {
          address = "2001:41d0:308:4800:d00::a";
          prefixLength = 72;
        }
      ];
      ipv4.routes = [
        {
          address = "0.0.0.0";
          prefixLength = 0;
          via = "192.168.0.1";
          options.onlink = "";
        }
      ];
      ipv6.routes = [
        {
          address = "::";
          prefixLength = 0;
          via = "2001:41d0:308:4800::2";
          options.onlink = "";
        }
      ];
    };
    # defaultGateway6 = {
    #   address = "";
    #   interface = "eth0";
    # };
  };
}
