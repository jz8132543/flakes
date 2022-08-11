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
    defaultGateway6.address = "2001:bc8:1824:b3b::";
    nameservers = [ "2a01:4f9:c010:3f02::1" "2a01:4f8:c2c:123f::1" "2a00:1098:2c::1" ];
    interfaces.ens2 = {
      useDHCP = true;
      ipv6.addresses = [
        { address = "2001:bc8:1824:b3b::1"; prefixLength = 64; }
      ];
      ipv4.routes = [
        { address = "169.254.42.42"; prefixLength = 32; }
      ];
    };
  };

  services.openssh.enable = true;

  system.stateVersion = "22.11";
}
