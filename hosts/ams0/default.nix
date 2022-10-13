{ config, lib, pkgs, modulesPath, suites, profiles, ... }: {

  imports = suites.server ++ (with profiles; [
    cloud
    services.acme
    services.traefik
  ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [ ];

  boot.loader.grub = {
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input console
      terminal_output console
    '';
  };
  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "virtio_pci" "virtio_scsi" "virtio_blk" ];
      kernelModules = [ "nvme" ];
    };
    kernelParams = [ "console=ttyS0,115200n8" ];
    kernelModules = [ "kvm-amd" ];
  };

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.cloud-init.network.enable = true;

  system.stateVersion = "22.11";
}
