{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.atc.edge;
  domain = config.networking.domain;
  data = import ./data.nix;

  # Build one tcpProxy entry per service.
  # Edge nodes forward each SNI (e.g. `jellyfin.dora.im`) to the
  # corresponding upstream origin (e.g. `nue0.dora.im:443`).
  #
  # HTTP/80 is intentionally not proxied through the CDN:
  #   • ACME HTTP-01 challenges must reach the origin directly.
  #   • All origin servers redirect 80 → 443 unconditionally, so clients
  #     always end up on HTTPS before any user data is transferred.
  #   • Origin IP exposure on port 80 is acceptable given the above.
  # BREAKING: the old single-upstream `cfg.upstream` option is removed.
  tcpProxyEntries = mapAttrs (label: originHost: {
    # Rule matches the public-facing domain (e.g. jellyfin.dora.im).
    rule = "HostSNI(`${label}.${domain}`)";
    # Target is the origin's fully-qualified hostname.
    target = "${originHost}.${domain}:443";
    entryPoints = [ "https" ];
    passthrough = true;
    # Higher priority than any default catch-all rule.
    priority = 1000;
  }) data.services;
in
{
  options.services.atc.edge = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        ATC Edge: SNI-passthrough reverse proxy via Traefik.
        Enable on each edge node host. Services and their upstream origins
        are derived automatically from data.nix — no further options needed.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.traefik.enable = mkOverride 40 true;

    # Generate one independent TCP SNI-passthrough proxy per service.
    # Each service routes to its specific upstream origin (not a shared one).
    services.traefik.tcpProxies = tcpProxyEntries;
  };
}
