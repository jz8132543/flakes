{
  config,
  lib,
  ...
}:
let
  sshPorts = lib.unique (
    [
      22
      (config.ports.ssh or 1022)
    ]
    ++ lib.filter (p: p != 80 && p != 443) (
      lib.mapAttrsToList (_: h: h.port) (config.programs.ssh.customHosts or { })
    )
  );
in
{
  config = lib.mkIf config.services.mihomo.enable {
    networking.nftables.tables.mihomo-process-bypass = {
      family = "inet";
      content = ''
        chain route_output {
          type route hook output priority mangle; policy accept;

          meta skuid 998 counter meta mark set meta mark | 0x1

          # 放行 SSH 端口直连，强制走主路由表绕过 Meta TUN，避免被 DNS 反查劫持至 CDN 边缘池
          ${lib.optionalString (sshPorts != [ ]) ''
            tcp dport { ${
              lib.concatMapStringsSep ", " toString sshPorts
            } } counter meta mark set meta mark | 0x1
          ''}
        }
      '';
    };
  };
}
