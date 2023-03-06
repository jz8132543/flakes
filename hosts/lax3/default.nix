{ lib, config, pkgs, modulesPath, suites, profiles, ... }: 

{
  imports = suites.server ++ (with profiles; [
    cloud
  ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [  ];

  # Hardware
  boot.initrd.availableKernelModules = [ "ata_piix" "virtio_pci" "virtio_scsi" "sr_mod" "virtio_blk" ];
  boot.kernelModules = [ "kvm-intel" ];

  system.stateVersion = "23.05";
}
