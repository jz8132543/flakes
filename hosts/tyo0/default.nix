{ config, pkgs, modulesPath, suites, profiles, ... }: {
  imports =
    suites.server ++
    (with profiles; [
      services.acme
      services.v2ray
      services.traefik
      services.k3s
    ]) ++ (with profiles.users; [
      tippy
    ]);

  environment.systemPackages = with pkgs;[
    kubernetes-helm
  ];

  networking.hostName = "tyo0";
  # Hardware
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" "kvm-amd" ];
  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  swapDevices = [
    { device = "/dev/vda2"; }
    { device = "/swapfile"; size = 1024; }
  ];

  system.stateVersion = "22.11";
}
