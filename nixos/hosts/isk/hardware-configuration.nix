{
  lib,
  modulesPath,
  config,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/desktop/nvidia.nix
  ];
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "sr_mod"
    "xhci_pci"
    "usb_storage"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  utils.disk = "/dev/sda";

  # NVIDIA Configuration
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Prevent laptop from sleeping on lid close
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  networking = {
    useNetworkd = lib.mkForce true;
    useDHCP = false;
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "yes";
      address = [ "192.168.1.111/24" ];
      routes = [ { Gateway = "192.168.1.1"; } ];
    };
  };

  systemd.services.ethtool-offload = {
    description = "Disable TX checksumming on primary interface";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ethtool-offload" ''
        IFACE=$(${pkgs.iproute2}/bin/ip -o link show | ${pkgs.gawk}/bin/awk -F': ' '/en/ {print $2}' | head -n1)
        if [ -n "$IFACE" ]; then
          ${pkgs.ethtool}/bin/ethtool -K $IFACE tx-checksumming off
        fi
      '';
    };
  };

  hardware.nvidia-container-toolkit.enable = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

}
