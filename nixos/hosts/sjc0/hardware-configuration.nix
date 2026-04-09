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
    "ahci"
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  utils.disk = "/dev/sda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "45.143.130.241";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "2604:a840:100:2e9::a";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = "45.143.130.254";
    defaultGateway6 = {
      address = "2604:a840:100::abcd:1";
      interface = "eth0";
    };
  };

  hardware.enableRedistributableFirmware = lib.mkForce false;
}
