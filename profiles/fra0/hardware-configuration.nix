{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];
  utils.disk = "/dev/sda";
  networking = {
    interfaces.ens3 = {
      useDHCP = true;
      ipv6.addresses = [{ address = "2a00:0f48:1003:25bc:0000:0000:0000:0001"; prefixLength = 64; }];
      ipv6.routes = [{ address = "::"; prefixLength = 0; via = "2a00:0f48:1003:0000:0000:0000:0000:0001"; }];
    };
  };
}
