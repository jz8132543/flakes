{
  nixosModules,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      ../../modules/base/modules/easytier-member.nix
      nixosModules.optimize.fakehttp
      nixosModules.optimize.network-desktop
      nixosModules.services.traefik
      nixosModules.optimize.dev
    ];

  # environment.isCN = true;

  environment.systemPackages = with pkgs; [
    lenovo-legion
    efibootmgr
  ];
  boot.kernelPackages = lib.mkOverride 0 pkgs.linuxPackages;
  # services.create_ap = {
  #   enable = true;
  #   settings = {
  #     INTERNET_IFACE = "wlp4s0";
  #     WIFI_IFACE = "wlp4s0";
  #     SSID = "ARX8";
  #     PASSPHRASE = "qwertyut";
  #     # HIDDEN = 1;
  #     IEEE80211AX = 1;
  #     FREQ_BAND = 5;
  #   };
  # };
  # };

  # Media services removed - use nue0 for media server

  services.easytierMesh.member = {
    enable = true;
    bootstrapHost = "et.${config.networking.domain}";
    ipv4 = "10.144.0.22/24";
    lowResource = false;
    latencyFirst = true;
    privateMode = true;
  };
}
