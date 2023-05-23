{ config
, pkgs
, lib
, ...
}:
let
  image = "ghcr.io/goauthentik/server:latest";
  mkAuthentikContainer =
    { cmd
    , dependsOn ? [ ]
    ,
    }: {
      inherit cmd dependsOn image;
      environment = {
        # AUTHENTIK_REDIS__HOST = "127.0.0.1";
        # AUTHENTIK_REDIS__PORT = "6379";
        # AUTHENTIK_REDIS__DB = "authentik";
        AUTHENTIK_LISTEN__HTTP = "127.0.0.1:${toString config.ports.authentik}";
        AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:0";
        AUTHENTIK_LISTEN__METRICS = "127.0.0.1:${toString config.ports.authentik_metrics}";
        AUTHENTIK_POSTGRESQL__HOST = "postgres.dora.im";
        AUTHENTIK_POSTGRESQL__PORT = "5432";
        AUTHENTIK_POSTGRESQL__NAME = "authentik";
        AUTHENTIK_POSTGRESQL__USER = "authentik";
        AUTHENTIK_SECRET_KEY = config.sops.secrets."authentik/secret-key".path;
        AUTHENTIK_ERROR_REPORTING__ENABLED = "true";
      };
      extraOptions = [
        "--network=host"
      ];
    };
in
{
  sops.secrets."authentik/secret-key" = { };
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.containers = {
    authentik-server = mkAuthentikContainer {
      cmd = [ "server" ];
    };
    authentik-worker = mkAuthentikContainer {
      cmd = [ "worker" ];
      dependsOn = [ "authentik-server" ];
    };
  };
  services.redis.servers."" = {
    enable = true;
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      authentik = {
        rule = "Host(`sso.dora.im`) && PathPrefix(`/`)";
        entryPoints = [ "https" ];
        service = "authentik";
      };
      authentik_metrics = {
        rule = "Host(`sso.dora.im`) && PathPrefix(`/metrics`)";
        entryPoints = [ "https" ];
        service = "authentik_metrics";
      };
    };
    services = {
      authentik.loadBalancer = {
        passHostHeader = true;
        servers = [{ url = "http://localhost:${toString config.ports.authentik}"; }];
      };
      authentik_metrics.loadBalancer = {
        passHostHeader = true;
        servers = [{ url = "http://localhost:${toString config.ports.authentik_metrics}"; }];
      };
    };
  };
}
