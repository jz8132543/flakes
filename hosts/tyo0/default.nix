{ lib, config, pkgs, modulesPath, suites, profiles, ... }: 

{
  imports = suites.server ++ (with profiles; [
    cloud.filesystems
    cloud.common
    services.acme
    services.v2ray
    services.traefik
  ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [ kubernetes-helm ];

  networking.hostName = "tyo0";
  # Hardware
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules =
    [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" "kvm-amd" ];

  system.stateVersion = "22.11";
}
