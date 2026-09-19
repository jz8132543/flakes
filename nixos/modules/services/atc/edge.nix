{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.atc.edge;
in
{
  imports = [ ./common.nix ];

  options.services.atc.edge = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "ATC Edge reverse proxy via Traefik SNI Passthrough";
    };

    upstream = mkOption {
      type = types.str;
      default = "nue0.dora.im:443";
      description = "Core origin server address:port";
    };

    domains = mkOption {
      type = types.listOf types.str;
      default = config.services.atc.domains;
      description = "List of domain names accelerated by ATC CDN";
    };
  };

  config = mkIf (cfg.enable && config.networking.hostName != "nue0") {
    services.traefik.enable = mkOverride 40 true;

    # 自动配置 Traefik TCP SNI 透明透传代理
    services.traefik.tcpProxies.atc-cdn = {
      rule = concatMapStringsSep " || " (d: "HostSNI(`${d}`)") cfg.domains;
      target = cfg.upstream;
      entryPoints = [ "https" ];
      passthrough = true;
      priority = 1000;
    };
  };
}
