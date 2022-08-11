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
    interfaces.ens0 = {
      useDHCP = false;
      ipv6.addresses = [
        { address = "2400:6180:0:d0::e88:d001"; prefixLength = 64; }
      ];
      ipv4.routes = [
        { address = "139.59.240.130"; prefixLength = 20; }
      ];
    };
    interfaces.ens1 = {
      useDHCP = false;
      ipv4.routes = [
        { address = "10.104.0.2"; prefixLength = 20; }
      ];
    };
  };

  services.openssh.enable = true;

  system.stateVersion = "22.11";
}
