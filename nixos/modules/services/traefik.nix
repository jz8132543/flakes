{
  lib,
  config,
  ...
}: {
  config.networking.firewall.allowedTCPPorts = [80 443];
  config.networking.firewall.allowedUDPPorts = [443];
  config.sops.secrets."traefik/cloudflare" = {};
  config.services.traefik = {
    enable = true;
    staticConfigOptions = {
      experimental.http3 = true;
      entryPoints = {
        http = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "https";
            scheme = "https";
            permanent = false;
          };
        };
        https = {
          address = ":443";
          http.tls.certResolver = "zerossl";
          http3 = {};
        };
      };
      certificatesResolvers.zerossl.acme = {
        caServer = "https://acme.zerossl.com/v2/DV90";
        email = "blackhole@dora.im";
        storage = "/var/lib/traefik/acme.json";
        keyType = "EC256";
        eab = {
          kid = "s5QsCWwCNdhUcJAUR1TfNA";
          hmacEncoded = "kcZnLYZstFNSf1HQQyaBhXWWikJRIxf3pVhgEg_21CiiaF36A4ADzUpt5KpwOzPuOpRCBkNd9oXrhsSirRm2lw";
        };
        dnsChallenge = {provider = "cloudflare";};
      };
      ping = {
        manualRouting = true;
      };
      metrics = {
        prometheus = {
          addRoutersLabels = true;
          manualRouting = true;
        };
      };
    };
    dynamicConfigOptions = {
      tls.options.default = {
        minVersion = "VersionTLS13";
        sniStrict = true;
      };
      http = {
        routers = {
          ping = {
            rule = "Host(`${config.networking.fqdn}`) && Path(`/ping`)";
            entryPoints = ["https"];
            service = "ping@internal";
          };
          traefik = {
            rule = "Host(`${config.networking.fqdn}`) && Path(`/traefik`)";
            entryPoints = ["https"];
            service = "prometheus@internal";
          };
        };
      };
    };
  };
  config.systemd.services.traefik.serviceConfig.EnvironmentFile = [config.sops.secrets."traefik/cloudflare".path];
}
