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
  options.services.atc.edge = {
    enable = mkEnableOption "ATC Edge reverse proxy via Traefik SNI Passthrough";

    upstream = mkOption {
      type = types.str;
      default = "nue0.dora.im:443";
      description = "Core origin server address:port";
    };

    domains = mkOption {
      type = types.listOf types.str;
      default = [
        "cloud.dora.im"
        "jellyfin.dora.im"
        "zone.dora.im"
        "mastodon.dora.im"
        "m.dora.im"
        "matrix.dora.im"
      ];
      description = "List of domain names accelerated by ATC CDN";
    };
  };

  config = mkIf cfg.enable {
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
