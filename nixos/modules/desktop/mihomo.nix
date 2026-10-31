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
  systemd.services.mihomo = {
    after = [ "NetworkManager-wait-online.service" ];
    wants = [ "NetworkManager-wait-online.service" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "mihomo";
      Group = "mihomo";
      ExecStart = lib.mkForce "${lib.getExe pkgs.mihomo} -d /var/lib/mihomo -f \${CREDENTIALS_DIRECTORY}/config.yaml -ext-ui ${pkgs.metacubexd}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    serviceConfig.ExecStartPre =
      let
        wait-network = pkgs.writeShellApplication {
          name = "mihomo-wait-network";
          runtimeInputs = [ pkgs.iproute2 ];
          text = ''
            set -e
            tries=60
            while [ "$tries" -gt 0 ]; do
              if ip route show default >/dev/null 2>&1; then
                exit 0
              fi
              tries=$((tries - 1))
              sleep 1
            done
            echo "No default route after 60s, starting anyway" >&2
          '';
        };
      in
      [
        "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat /var/lib/mihomo/GeoIP.dat"
        "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat /var/lib/mihomo/GeoSite.dat"
        "${wait-network}/bin/mihomo-wait-network"
      ];
  };
  environment.global-persistence = {
    directories = [
      "/etc/mihomo"
    ];
  };
}
