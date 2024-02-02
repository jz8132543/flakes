{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  boot.initrd.availableKernelModules = ["ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk"];
  boot.kernelModules = ["kvm-amd"];
  # utils.disk = "/dev/vdb";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
