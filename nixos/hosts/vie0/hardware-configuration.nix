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
          address = "2a0a:4cc0:80:38bf:49e:6dff:fe2a:26c4";
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
