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
      AUTHENTIK_REDIS__HOST = "fra0.dora.im";
      AUTHENTIK_REDIS__PORT = 6379;
      AUTHENTIK_REDIS__DB = "authentik";
      AUTHENTIK_POSTGRESQL__HOST = "fra0.dora.im";
      AUTHENTIK_POSTGRESQL__PORT = 5432;
      AUTHENTIK_POSTGRESQL__NAME = "authentik";
    };
    extraOptions = [
      "--network=host"
    ];
    environmentFiles = cfg.environmentFiles;
  };
in {
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
}
