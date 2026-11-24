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
  imports = [
    ./mihomo-routing.nix
    ./mihomo-subscription.nix
  ];

  # Selectable so a fork kernel can be trialled without editing this module.
  # "mihomo" is the upstream kernel; "mihomo-smart" is the NUR fork.
  options.mihomoKernel = lib.mkOption {
    type = lib.types.enum [
      "mihomo"
      "mihomo-smart"
    ];
    default = "mihomo";
    description = "Kernel binary used by mihomo.service.";
  };

  config =
    let
      mihomoPackage =
        if config.mihomoKernel == "mihomo-smart" then pkgs.nur.repos.zerozawa.mihomo-smart else pkgs.mihomo;
    in
    {
      users.groups.mihomo = { };
      users.users.mihomo = {
        isSystemUser = true;
        group = "mihomo";
        uid = 998;
      };

      services.mihomo = {
        enable = lib.mkDefault true;
        # 覆盖上游模块的默认包，使订阅更新脚本的 PATH、webui 及其他引用
        # 全部指向同一内核；只改 ExecStart 会让校验仍用上游二进制。
        package = lib.mkForce mihomoPackage;
        tunMode = true;
        webui = pkgs.metacubexd;
        configFile = "/etc/mihomo/config.yaml";
      };
      services.traefik.proxies.mihomo-dashboard = lib.mkIf config.services.mihomo.enable {
        rule = "Host(`mihomo.${config.networking.domain}`)";
        target = "http://127.0.0.1:9090/ui/";
        middlewares = [ "auth" ];
        homepage = {
          title = "Mihomo Dashboard";
          category = "Network";
          icon = "mihomo.png";
          description = "Local proxy and traffic controls";
          href = "http://127.0.0.1:9090/ui/";
        };
      };
      # Keep the persistent workdir writable even when subscription updates are disabled.
      # Only the directory is public; credentials and new files retain their private modes.
      systemd.tmpfiles.rules = [ "d /etc/mihomo 0777 mihomo mihomo -" ];
      systemd.services.mihomo = {
        after = [ "NetworkManager-wait-online.service" ];
        wants = [ "NetworkManager-wait-online.service" ];
        startLimitIntervalSec = 0;
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "mihomo";
          Group = "mihomo";
          # mihomo-smart 把学习状态（cache.db）、模型（Model.bin）、
          # ASN.mmdb 与采样 CSV 全部写在 -d 指定的工作目录。
          # 该目录必须是持久化的，否则每次重启都退回冷启动状态、
          # 已收敛的节点权重全部丢失，因此指向 /etc/mihomo。
          ExecStart = lib.mkForce "${lib.getExe mihomoPackage} -d /etc/mihomo -f ${configPath} -ext-ui ${pkgs.metacubexd}";
          # ProtectSystem=strict also applies to ExecStartPre; chmod alone cannot fix EROFS.
          ReadWritePaths = [ "/etc/mihomo" ];
          Restart = "always";
          RestartSec = 5;
          TimeoutStartSec = "75s";
          ExecStartPre =
            let
              wait-network = pkgs.writeShellApplication {
                name = "mihomo-wait-network";
                runtimeInputs = [ pkgs.iproute2 ];
                text = ''
                  set -e
                  tries=60
                  while [ "$tries" -gt 0 ]; do
                    # ip exits successfully even when no routes exist. Only the
                    # main table counts: the TUN's own default cannot bootstrap it.
                    if [ -n "$(ip -4 route show table main default)" ] ||
                       [ -n "$(ip -6 route show table main default)" ]; then
                      exit 0
                    fi
                    tries=$((tries - 1))
                    sleep 1
                  done
                  echo "No default route after 60s; retrying startup" >&2
                  exit 1
                '';
              };
            in
            [
              # Geo 数据同样落在持久化工作目录，供 smart 的 ASN 维度学习复用。
              "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat /etc/mihomo/GeoIP.dat"
              "${pkgs.coreutils}/bin/ln -sf ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat /etc/mihomo/GeoSite.dat"
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
    };
}
