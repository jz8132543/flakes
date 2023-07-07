{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = ["ata_piix" "virtio_pci" "virtio_scsi" "sr_mod" "virtio_blk"];
  boot.kernelModules = ["kvm-intel"];
  boot.kernelParams = ["biosdevname=0" "net.ifnames=0"];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking = {
    interfaces.eth0 = {
      useDHCP = true;
      ipv6.addresses = [
        {
          address = "2606:fc40:0:b38::1";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway6 = {
      address = "2606:fc40:0:b00::1";
      interface = "eth0";
    };
  };
  fileSystems = {
    "/mnt/minio" = {
      fsType = "xfs";
      device = lib.mkForce "/dev/disk/by-partlabel/MINIO";
    };
  };
}
