{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.cookiecloud;
  port = config.ports.cookiecloud;
in
{
  imports = [ nixosModules.services.traefik ];

  options.services.cookiecloud = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CookieCloud service.";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      default = "cookie.${config.networking.domain}";
      description = "Public domain for CookieCloud.";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://${cfg.domain}";
      description = "Public URL for CookieCloud.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.cookiecloud = {
      image = "easychen/cookiecloud:latest";
      ports = [ "${toString port}:8088" ];
      environment = { };
      volumes = [
        "/var/lib/cookiecloud:/data/api/data"
      ];
    };

    services.traefik.proxies.cookiecloud = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://localhost:${toString port}";
    };

    environment.global-persistence.directories = [
      "/var/lib/cookiecloud"
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/cookiecloud 0755 root root -"
    ];

    services.restic.backups.borgbase.paths = [
      "/var/lib/cookiecloud"
    ];
  };
}
