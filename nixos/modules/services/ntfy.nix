{
  config,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.restic ];

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${config.networking.domain}";
      listen-http = ":${toString config.ports.ntfy}";
      cache-file = "/var/lib/ntfy-sh/cache.db";
      auth-file = "/var/lib/ntfy-sh/auth.db";
      auth-default-access = "deny-all";
      behind-proxy = true;
      attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
      enable-login = true;
      enable-reservations = true;
      upstream-base-url = "https://ntfy.sh";
    };
  };
  systemd.services.ntfy-sh.serviceConfig = {
    WorkingDirectory = "/var/lib/ntfy-sh";
    StateDirectory = "ntfy-sh";
  };
  # services.ntfy-sh = {
  #   enable = true;
  #   settings = {
  #     base-url = "https://ntfy.${config.networking.domain}";
  #     listen-http = ":${toString config.ports.ntfy}";
  #     behind-proxy = true;
  #     # cache-file = "/var/lib/ntfy-sh/cache.db";
  #     # auth-file = "/var/lib/ntfy-sh/auth.db";
  #     auth-default-access = "deny-all";
  #     # attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
  #     # enable-login = true;
  #     # enable-reservations = true;
  #     # upstream-base-url = "https://ntfy.sh";
  #   };
  # };
  #
  # systemd.services.ntfy-sh.serviceConfig.RuntimeDirectory = ["ntfy-sh"];
  services.restic.backups.borgbase.paths = [
    config.services.ntfy-sh.settings.auth-file
  ];

  services.traefik.proxies.nfty = {
    rule = "Host(`ntfy.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.ntfy}";
  };
}
