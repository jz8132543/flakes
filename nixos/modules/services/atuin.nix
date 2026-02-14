{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.atuin;
in
{
  services.atuin = {
    enable = true;
    host = "127.0.0.1";
    port = config.ports.atuin;
    database.uri = "postgresql://atuin@${PG}/atuin";
    openRegistration = false;
  };
  services.traefik.proxies.atuin = {
    rule = "Host(`atuin.${config.networking.domain}`)";
    target = "http://localhost:${toString cfg.port}";
  };
  systemd.services."atuin" = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
