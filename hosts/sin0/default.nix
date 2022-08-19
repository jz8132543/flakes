{ config, pkgs, modulesPath, suites, profiles, ... }: {
  imports =
    suites.server ++
    (with profiles; [
      services.acme
      services.traefik
      services.k3s
    ]) ++ (with profiles.users; [
      tippy
    ]);

  environment.systemPackages = with pkgs;[

  ];

  networking.hostName = "sin0";
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "/dev/vda";
  };
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/136735fa-5cc1-470f-9359-ee736e42f844";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/168D-B0CB";
      fsType = "vfat";
    };
  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "virtio_blk" ];
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
        address = [ "128.199.121.90/18" "2400:6180:0:d0::1223:1001/64" ];
        gateway = [ "128.199.64.0" "2400:6180:0:d0::1" ];
      };
      ens4 = {
        matchConfig = { Name = "ens4"; };
        address = [ "10.104.0.2/20" ];
      };
    };
  };
}
