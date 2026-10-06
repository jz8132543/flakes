{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.atc.edge;
  domain = config.networking.domain;
  data = (importJSON ../../../../lib/data/data.json).cdn;
  tcpProxyEntries = mapAttrs (label: originHost: {
    rule = "HostSNI(`${label}.${domain}`)";
    target = "${originHost}.${domain}:443";
    entryPoints = [ "https" ];
    passthrough = true;
    priority = 1000;
  }) data.services;
in
{
  options.services.atc.edge.enable = mkOption {
    type = types.bool;
    default = true;
    description = "Enable per-service SNI passthrough routes from terraform/cdn.tf.";
  };

  config = mkIf cfg.enable {
    services.traefik.enable = mkOverride 40 true;
    services.traefik.tcpProxies = tcpProxyEntries;
  };
}
