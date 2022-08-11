{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "/dev/vda";
  };
  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" ];
      kernelModules = [ "nvme" ];
    };
    kernelParams = [ "console=ttyS0,115200n8" ];
  };

  networking = {
    useNetworkd = true;
    nameservers = [ "1.1.1.1" "1.0.0.1" ];
  };

  systemd.network = {
    enable = true;
    networks = {
      ens0 = {
        matchConfig = { Name = "ens0"; };
        address = [ "139.59.240.130/20" "2400:6180:0:d0::e88:d001/64" ];
        gateway = [ "139.59.240.1" "2400:6180:0:d0::1" ];
      };
      ens1 = {
        matchConfig = { Name = "ens1"; };
        address = [ "10.104.0.2/20" ];
      };
    };
  };

  services.openssh.enable = true;

  system.stateVersion = "22.11";
}
