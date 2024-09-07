{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = ["ata_piix" "virtio_pci" "virtio_scsi" "sr_mod" "virtio_blk"];
  # utils.disk = "/dev/sda";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    # useDHCP = false;
    # useNetworkd = true;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "123.254.105.134";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "123.254.105.158";
  };

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096;
    }
  ];
}
