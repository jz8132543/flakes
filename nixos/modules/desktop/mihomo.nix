{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./mihomo-routing.nix ];

  users.groups.mihomo = { };
  users.users.mihomo = {
    isSystemUser = true;
    group = "mihomo";
    uid = 998;
  };

  services.mihomo = {
    enable = lib.mkDefault true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = "/etc/mihomo/config.yaml";
  };
  systemd.services.mihomo.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "mihomo";
    Group = "mihomo";
    ExecStart = lib.mkForce "${lib.getExe pkgs.mihomo} -d /var/lib/mihomo -f \${CREDENTIALS_DIRECTORY}/config.yaml -ext-ui ${pkgs.metacubexd}";
  };
  systemd.services.mihomo.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat /var/lib/mihomo/GeoIP.dat"
    "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat /var/lib/mihomo/GeoSite.dat"
  ];
  environment.global-persistence = {
    directories = [
      "/etc/mihomo"
    ];
  };
}
