{
  nixosModules,
  pkgs,
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
      ../../modules/base/easytier.nix
      nixosModules.optimize.network-desktop
      nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      nixosModules.optimize.dev
      nixosModules.services.media.qbittorrent
    ];

  # hardware.microsoft-surface.kernelVersion = "stable";
  hardware.microsoft-surface = {
    # kernelVersion = "6.4.12";
    kernelVersion = "stable";
    # surface-control.enable = true;
    # ipts.enable = true;
  };

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

  environment.systemPackages = with pkgs; [
    efibootmgr
    v4l-utils
  ];

  services.easytierMesh = {
    enable = true;
    role = "member";
    bootstrap.host = "et.${config.networking.domain}";
    ipv4 = "10.144.0.21/24";
    lowResource = false;
    latencyFirst = true;
    privateMode = true;
  };
}
