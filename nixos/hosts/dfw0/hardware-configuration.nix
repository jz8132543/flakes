{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "virtio_pci"
    "virtio_scsi"
    "sr_mod"
    "virtio_blk"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  # utils.disk = "/dev/vdb";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.ens17 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "154.40.40.139";
          prefixLength = 25;
        }
      ];
    };
    defaultGateway = "154.40.40.254";
  };
}
