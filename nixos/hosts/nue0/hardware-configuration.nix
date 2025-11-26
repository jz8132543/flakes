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
    "virtio_pci"
    "uhci_hcd"
    "sr_mod"
    "virtio_blk"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  utils.disk = "/dev/vda";
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.ens3 = {
      useDHCP = true;
      # ipv4.addresses = [
      #   {
      #     address = "176.116.18.242";
      #     prefixLength = 24;
      #   }
      # ];
      ipv6.addresses = [
        {
          address = "2a03:4000:4f:92d::";
          prefixLength = 64;
        }
      ];
    };
    # defaultGateway = {
    #   address = "176.116.18.1";
    #   interface = "eth0";
    # };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "ens3";
    };
  };
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 32768;
    }
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  nix.gc.automatic = lib.mkForce false;
}
