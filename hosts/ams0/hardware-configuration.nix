{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };
  fileSystems."/boot" = { device = "/dev/disk/by-uuid/C957-9CB6"; fsType = "vfat"; };
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" ];
  boot.initrd.kernelModules = [ "nvme" ];
  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot = {
    loader.grub.extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input console
      terminal_output console
    '';
    initrd = {
      availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" ];
      kernelModules = [ "nvme" ];
    };
    kernelParams = [ "console=ttyS0,115200n8" ];
  };

  networking = {
    useDHCP = false;
    useNetworkd = true;
    interfaces.ens2.useDHCP = true;
  };

  services.openssh.enable = true;

  system.stateVersion = "22.11";
}
