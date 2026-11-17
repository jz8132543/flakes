{
  nixosModules,
  pkgs,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      nixosModules.services.networking.dn42.mesh
      ./hardware-configuration.nix
      ./hardware.nix
      nixosModules.optimize.network-desktop
      nixosModules.optimize.brutal
      nixosModules.services.traefik
      nixosModules.optimize.dev
      nixosModules.services.qbittorrent
      # nixosModules.services.microsocks
    ];

  optimize.brutal.target = "!cn";

  # Font/cursor DPI hint, not a compositor output mode or fractional scale.
  home-manager.users.tippy.wayland.dpi = 192;

  desktop.nvidia = {
    mode = "sync";
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
  environment.networkTune.cca = "bbr";

  environment.systemPackages = with pkgs; [
    efibootmgr
    pciutils
    usbutils
    v4l-utils
    # ms365
    # nemo-with-extensions
    # nemo-fileroller
    # cinnamon.nemo
    # cinnamon.nemo-fileroller
  ];
}
