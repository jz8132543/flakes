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
    "virtio_scsi"
    "sr_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  utils.disk = "/dev/sda";
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 8192;
    }
  ];
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "109.71.253.195";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a0e:6a80:3:1e3::";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "109.71.253.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
  };
}
