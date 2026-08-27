{
  nixosModules,
  lib,
  pkgs,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      ./hardware.nix
      nixosModules.optimize.network-desktop
      nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.optimize.dev
      nixosModules.services.qbittorrent
      # nixosModules.services.microsocks
    ];

  # hardware.microsoft-surface = {
  #   kernelVersion = "longterm";
  # };
  services.iptsd.enable = lib.mkForce false;

  desktop.nvidia = {
    mode = "sync";
  };

  desktop.winapps = {
    kvm = {
      enable = true;
      enableVirtIO = true;
      enableCdrom = false;
    };
    docker = {
      enable = true;
      enableVirtIO = true;
      enableCdrom = true;
    };
  };

  users.users.tippy.extraGroups = [ "surface-control" ];

  # services.create_ap = {
  #   enable = true;
  #   settings = {
  #     INTERNET_IFACE = "wlp1s0";
  #     WIFI_IFACE = "wlp1s0";
  #     SSID = "ARX8";
  #     PASSPHRASE = "qwertyut";
  #     # HIDDEN = 1;
  #     IEEE80211AX = 1;
  #     FREQ_BAND = 5;
  #   };
  # };

  # environment.isCN = true;

  # environment.networkTune.cca = "bbr";
  environment.systemPackages = with pkgs; [
    efibootmgr
    pciutils
    surface-control
    usbutils
    v4l-utils
  ];

  desktop.kdeconnect.customDomains = [
    "op13.mag"
    "opap.mag"
  ];

}
