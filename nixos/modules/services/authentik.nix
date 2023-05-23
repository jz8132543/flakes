{
  config,
  pkgs,
  lib,
  ...
}: let
  image = "ghcr.io/goauthentik/server:2023.5.1";
  mkAuthentikContainer = {
    cmd,
    dependsOn ? [],
  }: {
    inherit cmd dependsOn image;
    environment = {
      AUTHENTIK_REDIS__HOST = "127.0.0.1";
      AUTHENTIK_REDIS__PORT = config.services.redis.servers.authentik.port;
      AUTHENTIK_REDIS__DB = "authentik";
      AUTHENTIK_POSTGRESQL__HOST = "postgres.dora.im";
      AUTHENTIK_POSTGRESQL__PORT = 5432;
      AUTHENTIK_POSTGRESQL__NAME = "authentik";
      AUTHENTIK_SECRET_KEY = config.sops.secrets."authentik/secret-key".path;
    };
    extraOptions = [
      "--network=host"
    ];
  };
in {
  sops.secrets."authentik/secret-key" = {};
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.containers = {
    authentik-server = mkAuthentikContainer {
      cmd = ["server"];
    };
    authentik-worker = mkAuthentikContainer {
      cmd = ["worker"];
      dependsOn = ["authentik-server"];
    };
  };
  services.redis.servers.authentik = {
    enable = true;
    port = 16380;
  };
}
