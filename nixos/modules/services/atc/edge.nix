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

  # Filter out services where the origin compute node is this machine.
  # If the current node is the origin (e.g. fra0 hosting jellyfin), generating
  # a Traefik TCP proxy with target fra0.dora.im:443 would create a self-loop
  # and intercept traffic meant for local HTTP/HTTPS services.
  remoteServices = filterAttrs (
    _label: originHost:
    originHost != config.networking.hostName && originHost != "${config.networking.hostName}.${domain}"
  ) data.services;

  # Port 443 L4 TCP SNI Passthrough:
  # 1. Edge nodes terminate no TLS; certificates remain strictly on the origin host.
  # 2. Port 80 is not proxied through edge nodes:
  #    - ACME TLS certificates are issued via DNS-01 challenge (Cloudflare), not HTTP-01.
  #    - Port 80 has no TLS handshake/SNI, requiring L7 HTTP termination to inspect Host.
  #    - Traefik on all nodes already redirects port 80 to 443 automatically.
  #    - Once upgraded to HTTPS/443, all client traffic is steered to edge nodes.
  tcpProxyEntries = mapAttrs (label: originHost: {
    rule = "HostSNI(`${label}.${domain}`)";
    target = "${originHost}.${domain}:443";
    entryPoints = [ "https" ];
    passthrough = true;
    priority = 1000;
  }) remoteServices;
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
