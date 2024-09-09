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
      ./hardware-configuration.nix
      # nixosModules.services.fw-proxy
    ];
  # environment.isCN = true;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    efibootmgr
  ];
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
}
