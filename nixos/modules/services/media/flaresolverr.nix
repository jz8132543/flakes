# FlareSolverr - Cloudflare Bypass Proxy
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/flaresolverr.nix
{ ... }:
{
  services.flaresolverr = {
    enable = true;
    port = 8191;
  };
}
