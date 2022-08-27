{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "/dev/vda";
  };
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/74dd579c-a377-487d-b8f7-bc7c6df13ba1";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/922E-54A6";
    fsType = "vfat";
  };
  boot = {
    initrd = {
      availableKernelModules =
        [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "virtio_blk" ];
      kernelModules = [ "nvme" ];
    };
  };

  networking = {
    useNetworkd = true;
    useDHCP = false;
    nameservers = [ "1.1.1.1" "1.0.0.1" ];
  };

  systemd.network = {
    enable = true;
    networks = {
      ens3 = {
        matchConfig = { Name = "ens3"; };
        address = [ "139.59.240.130/20" "2400:6180:0:d0::e88:d001/64" ];
        gateway = [ "139.59.240.1" "2400:6180:0:d0::1" ];
      };
      ens4 = {
        matchConfig = { Name = "ens4"; };
        address = [ "10.104.0.2/20" ];
      };
    };
  };

  services.openssh.enable = true;

  system.stateVersion = "22.11";
}
