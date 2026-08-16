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
      nixosModules.optimize.fakehttp
      nixosModules.optimize.network-desktop
      nixosModules.services.ddns
      nixosModules.services.traefik
      nixosModules.optimize.dev
    ];

  services.microsocks = {
    enable = true;
    ip = "0.0.0.0";
  };

  systemd.services.microsocks.serviceConfig = {
    IPAddressAllow = [
      "100.64.0.0/10"
      "fd7a:115c:a1e0::/48"
      "127.0.0.0/8"
      "::1/128"
    ];
    IPAddressDeny = "any";
  };
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 1080 ];

  # environment.isCN = true;
  environment.systemPackages = with pkgs; [
    lenovo-legion
    efibootmgr
  ];
  desktop.nvidia = {
    mode = "offload";
  };

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

}
