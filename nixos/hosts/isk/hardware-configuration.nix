{
  lib,
  modulesPath,
  pkgs,
  ...
}: let
  netdev = "enp6s18";
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  boot.initrd.availableKernelModules = ["uhci_hcd" "ehci_pci" "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" "e1000" "e1000e"];
  boot.kernelModules = ["kvm-intel"];
  utils.disk = "/dev/sda";
  networking = {
    interfaces.${netdev} = {
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
      interface = netdev;
    };
    localCommands = ''
      ${pkgs.ethtool}/bin/ethtool -K ${netdev} tx-checksumming off
    '';
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
