{ lib, ... }:
with lib;
{
  options.services.atc.domains = mkOption {
    type = types.listOf types.str;
    default = [
      "cloud.dora.im"
      "jellyfin.dora.im"
      "zone.dora.im"
      "m.dora.im"
      "office.dora.im"
    ];
    description = "Global list of domain names accelerated by ATC CDN (shared across edge Traefik and router CoreDNS)";
  };
}
