{ config
, lib
, pkgs
, modulesPath
, ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [ "ata_piix" "virtio_pci" "virtio_scsi" "sr_mod" "virtio_blk" ];
  boot.kernelModules = [ "kvm-intel" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
