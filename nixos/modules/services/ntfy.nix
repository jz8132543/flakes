{
  config,
  nixosModules,
  ...
}: {
  imports = [nixosModules.services.restic];

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${config.networking.domain}";
      listen-http = "127.0.0.1:${toString config.ports.ntfy}";
      behind-proxy = true;
      cache-file = "/var/lib/ntfy-sh/cache.db";
      auth-file = "/var/lib/ntfy-sh/auth.db";
      auth-default-access = "deny-all";
      attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
      enable-login = true;
      enable-reservations = true;
      upstream-base-url = "https://ntfy.sh";
    };
  };

  systemd.services.ntfy-sh.serviceConfig.RuntimeDirectory = ["ntfy-sh"];
  services.restic.backups.borgbase.paths = [
    config.services.ntfy-sh.settings.auth-file
  ];

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      nfty = {
        rule = "Host(`ntfy.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "nfty";
      };
    };
    services = {
      nfty.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.ntfy}";}];
      };
    };
  };
}
