{ lib, config, pkgs, modulesPath, suites, profiles, ... }: 

{
  imports = suites.server ++ (with profiles; [
    cloud
    services.acme
    services.traefik
  ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [  ];

  # Hardware
  boot.initrd.availableKernelModules =
    [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ "nvme" "kvm-amd" ];

  system.stateVersion = "22.11";
}
