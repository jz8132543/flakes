{
  config,
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.aria2
    nixosModules.services.podman
  ];
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = "/etc/mihomo/config.yaml";
  };
  systemd.services.mihomo.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat /var/lib/private/mihomo/GeoIP.dat"
    "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat /var/lib/private/mihomo/GeoSite.dat"
  ];
  programs = {
    # clash-verge = {
    #   enable = true;
    #   autoStart = true;
    #   tunMode = true;
    # };
  };
  environment.systemPackages = with pkgs; [
    qrcp
    android-tools
    # mihomo-party
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];
  environment.global-persistence = {
    directories = [
      "/etc/mihomo"
    ];
    user = {
      directories = [
        ".config/clash-verge"
      ];
    };
  };
}
