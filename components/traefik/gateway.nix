{ lib, config, ... }:
with lib;{
  config = {
    services.traefik = {
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
            http3 = { };
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
          tlsChallenge = { };
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
          minVersion = "VersionTLS12";
          sniStrict = true;
        };
        http = {
          routers = {
            ping = {
              rule = "Host(`${config.networking.fqdn}`) && Path(`/`)";
              entryPoints = [ "https" ];
              service = "ping@internal";
            };
            traefik = {
              rule = "Host(`${config.networking.fqdn}`) && Path(`/traefik`)";
              entryPoints = [ "https" ];
              service = "prometheus@internal";
            };
          };
        };
      };
    };
  };
}
