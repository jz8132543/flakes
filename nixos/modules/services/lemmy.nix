{PG ? "postgres.dora.im", ...}: {
  config,
  lib,
  ...
}: {
  services.lemmy = {
    enable = true;
    database.host = PG;
    settings = {
      hostname = "lemmy.${config.networking.domain}";
      federation.enabled = true;
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      lemmy-ui = {
        rule = "Host(`lemmy.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "lemmy-ui";
      };
      lemmy = {
        rule = "Host(`lemmy.${config.networking.domain}`) && HeadersRegexp(`Accept`, `^application/`) || Host(`lemmy.${config.networking.domain}`) && Method(`POST`) || Host(`lemmy.${config.networking.domain}`) && PathPrefix(`/{path:(api|pictrs|feeds|nodeinfo|.well-known)}`)";
        entryPoints = ["https"];
        service = "lemmy";
      };
    };
    services = {
      lemmy-ui.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${config.services.lemmy.ui.port}";}];
      };
      lemmy.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${config.services.lemmy.settings.port}";}];
      };
    };
  };
  systemd.services.lemmy = {
    after = ["postgresql.service" "tailscaled.service"];
    serviceConfig.Restart = lib.mkForce "always";
  };
}
