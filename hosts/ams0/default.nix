{ config, lib, pkgs, modulesPath, suites, profiles, ... }: {

  imports = suites.server ++ (with profiles; [
    cloud
    services.acme
    services.traefik
  ]) ++ (with profiles.users; [ tippy ]);

  environment.systemPackages = with pkgs; [ ];

  boot.loader.grub = {
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input console
      terminal_output console
    '';
  };
  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "virtio_pci" "virtio_scsi" "virtio_blk" ];
      kernelModules = [ "nvme" ];
    };
    kernelParams = [ "console=ttyS0,115200n8" ];
    kernelModules = [ "kvm-amd" ];
  };

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  networking = {
    useNetworkd = true;
    defaultGateway6.address = "2001:bc8:1824:b3b::";
    nameservers =
      [ "2a01:4f9:c010:3f02::1" "2a01:4f8:c2c:123f::1" "2a00:1098:2c::1" ];
    interfaces.ens2 = {
      useDHCP = false;
      ipv6.addresses = [{
        address = "2001:bc8:1824:b3b::1";
        prefixLength = 64;
      }];
    };
  };

  system.stateVersion = "22.11";
}
