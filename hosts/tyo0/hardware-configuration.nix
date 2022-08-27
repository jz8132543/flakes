{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules =
    [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" "kvm-amd" ];
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };
  swapDevices = [
    { device = "/dev/vda2"; }
    {
      device = "/swapfile";
      size = 1024;
    }
  ];
}
