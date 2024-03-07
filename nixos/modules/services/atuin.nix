{PG ? "postgres.dora.im", ...}: {
  config,
  lib,
  ...
}: let
  cfg = config.services.atuin;
in {
  services.atuin = {
    enable = true;
    host = "127.0.0.1";
    port = config.ports.atuin;
    database.uri = "postgresql://atuin@${PG}/atuin";
    openRegistration = false;
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      atuin = {
        rule = "Host(`atuin.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "atuin";
      };
    };
    services = {
      atuin.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString cfg.port}";}];
      };
    };
  };
  systemd.services."atuin" = {
    after = ["postgresql.service" "tailscaled.service"];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
