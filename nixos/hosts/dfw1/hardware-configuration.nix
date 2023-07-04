{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = ["ata_piix" "uhci_hcd" "virtio_pci" "virtio_blk"];
  boot.kernelModules = ["kvm-intel"];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
