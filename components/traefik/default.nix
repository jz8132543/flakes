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
            http.tls.certResolver = "le";
            http3 = { };
          };
        };
        certificatesResolvers.le.acme = {
          email = "blackhole@dora.im";
          keyType = "EC256";
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
