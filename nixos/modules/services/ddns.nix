{config, ...}: {
  sops.secrets = {
    "traefik/cloudflare_token" = {};
  };
  services.ddclient = {
    enable = true;
    interval = "5min";
    username = "token";
    passwordFile = config.sops.secrets."traefik/cloudflare_token".path;
    protocol = "cloudflare";
    zone = config.networking.domain;
    domains = [config.networking.fqdn];
    ssl = true;
    use = "web,web=ifconfig.me/ip";
    verbose = true;
  };
}
