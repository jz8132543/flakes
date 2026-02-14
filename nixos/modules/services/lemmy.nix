{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  lib,
  ...
}:
{
  services.lemmy = {
    enable = true;
    database.host = PG;
    settings = {
      hostname = "lemmy.${config.networking.domain}";
      federation.enabled = true;
    };
  };
  services.traefik.proxies = {
    lemmy-ui = {
      rule = "Host(`lemmy.${config.networking.domain}`)";
      target = "http://localhost:${toString config.services.lemmy.ui.port}";
    };
    lemmy = {
      rule = "Host(`lemmy.${config.networking.domain}`) && (HeadersRegexp(`Accept`, `^application/`) || Method(`POST`) || PathPrefix(`/{path:(api|pictrs|feeds|nodeinfo|.well-known)}`))";
      target = "http://localhost:${toString config.services.lemmy.settings.port}";
    };
  };
  systemd.services.lemmy = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
