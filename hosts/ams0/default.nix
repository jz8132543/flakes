{ config, pkgs, modulesPath, suites, profiles, ... }: {
  imports =
    suites.server ++
    (with profiles; [
    ]) ++ (with profiles.users; [
      tippy
    ]);

  environment.systemPackages = with pkgs;[
  ];

  networking.hostName = "ams0";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input console
      terminal_output console
      '';
  };
  fileSystems."/boot" = { device = "/dev/disk/by-uuid/C957-9CB6"; fsType = "vfat"; };
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
      useDHCP = false;
      ipv6.addresses = [
        { address = "2001:bc8:1824:b3b::1"; prefixLength = 64; }
      ];
    };
  };

  system.stateVersion = "22.11";
}
