{
  nixosModules,
  pkgs,
  ...
}: {
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.desktop.all
    ++ [
      ./hardware-configuration.nix
      # nixosModules.services.fw-proxy
    ];

  microsoft-surface = {
    # kernelVersion = "6.4.12";
    # surface-control.enable = true;
    # ipts.enable = true;
  };

  services.create_ap = {
    enable = true;
    settings = {
      INTERNET_IFACE = "wlp1s0";
      WIFI_IFACE = "wlp1s0";
      SSID = "ARX8";
      PASSPHRASE = "qwertyut";
      # HIDDEN = 1;
      IEEE80211AX = 1;
      FREQ_BAND = 5;
    };
  };

  environment.isCN = true;

  environment.systemPackages = with pkgs; [
    efibootmgr
  ];
}
