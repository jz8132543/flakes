{
  config,
  lib,
  pkgs,
  ...
}:
let
  preparePublicSsh = config.services.mihomo.routing.proxyPublicSsh;
  sshPorts = lib.unique (
    [
      22
      (config.ports.ssh or 1022)
    ]
    ++ lib.filter (p: p != 80 && p != 443) (
      lib.mapAttrsToList (_: h: h.port) (config.programs.ssh.customHosts or { })
    )
  );
  policy = pkgs.writeText "mihomo-public-ssh-policy.json" (
    builtins.toJSON {
      ports = sshPorts;
      domain = config.networking.domain;
      dn42Domain = config.services.dn42.domain or "dn42";
    }
  );
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  prepareConfig = pkgs.writeShellScript "mihomo-prepare-runtime-policy" ''
    exec ${python}/bin/python3 ${./mihomo-runtime-policy.py} \
      "$CREDENTIALS_DIRECTORY/config.yaml" /run/mihomo/config.yaml ${policy}
  '';
  configPath =
    if preparePublicSsh then "/run/mihomo/config.yaml" else "\${CREDENTIALS_DIRECTORY}/config.yaml";
in
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
      ExecStart = lib.mkForce "${lib.getExe pkgs.mihomo} -d /var/lib/mihomo -f ${configPath} -ext-ui ${pkgs.metacubexd}";
      Restart = "on-failure";
      RestartSec = 5;
      ExecStartPre =
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
        ]
        ++ lib.optional preparePublicSsh "${prepareConfig}";
    }
    // lib.optionalAttrs preparePublicSsh {
      RuntimeDirectory = "mihomo";
      RuntimeDirectoryMode = "0700";
    };
  };
  environment.global-persistence = {
    directories = [
      "/etc/mihomo"
    ];
  };
}
