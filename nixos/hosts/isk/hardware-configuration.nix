{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  boot.initrd.availableKernelModules = ["uhci_hcd" "ehci_pci" "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"];
  boot.kernelModules = ["kvm-intel"];
  utils.disk = "/dev/sda";
  networking = {
    nat = {
      enable = true;
      # dmzHost = "192.168.1.111";
    };
    interfaces.enp6s18 = {
      useDHCP = true;
      ipv4.addresses = [
        {
          address = "192.168.1.111";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "enp6s18";
    };
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
