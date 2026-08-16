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

  # 1. Create a dedicated microsocks user and group with a fixed UID
  users.users.microsocks = {
    isSystemUser = true;
    group = "microsocks";
    uid = 999;
    description = "User for microsocks proxy (fixed UID for mihomo bypass)";
  };
  users.groups.microsocks = {
    gid = 999;
  };

  # 2. Configure microsocks systemd service to use the fixed user
  systemd.services.microsocks = {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "microsocks";
      Group = "microsocks";
    };
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
