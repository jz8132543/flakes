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
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "ahci"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  utils.disk = "/dev/sda";
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "e*";
      networkConfig.DHCP = "yes";
      address = [
        "213.145.82.205/25"
        "2a12:6e40:eff7:36::a/64"
      ];
      routes = [
        { Gateway = "213.145.82.129"; }
        { Gateway = "2a12:6e40:eff7::1"; }
      ];
    };
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
