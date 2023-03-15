{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sr_mod" "virtio_blk" ];
  boot.kernelModules = [ "kvm-intel" ];
  swapDevices = [ { device = "/nix/swapfile"; size = 10240; } ];
}
