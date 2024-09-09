{
  config,
  lib,
  ...
}:
let
  inherit (config.networking) enableIPv6;
in
with lib;
{
  sops.secrets = {
    "traefik/cloudflare_token" = { };
  };
  services.ddclient = {
    enable = true;
    interval = "5min";
    username = "token";
    passwordFile = config.sops.secrets."traefik/cloudflare_token".path;
    protocol = "cloudflare";
    zone = config.networking.domain;
    domains = [ config.networking.fqdn ];
    ssl = true;
    # use = "web,web=ifconfig.me/ip";
    extraConfig = mkMerge [
      (mkIf enableIPv6 ''
        usev6=webv6, webv6=https://ipv6.nsupdate.info/myip
      '')
      ''
        usev4=webv4, webv4=https://ipv4.nsupdate.info/myip
        max-interval=1d
      ''
    ];
    verbose = true;
  };
}
