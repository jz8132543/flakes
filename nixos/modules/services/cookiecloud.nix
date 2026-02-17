{
  config,
  nixosModules,
  ...
}:
let
  domain = "cookie.${config.networking.domain}";
  port = config.ports.cookiecloud;
in
{
  imports = [ nixosModules.services.traefik ];

  virtualisation.oci-containers.containers.cookiecloud = {
    image = "easychen/cookiecloud:latest";
    ports = [ "${toString port}:8088" ];
    # CookieCloud is a simple Go server that uses local file storage (SQLlite/LevelDB).
    # It does NOT support PostgreSQL.
    environment = {
      # Add any other config if needed, but CookieCloud is very minimal.
      # You can pre-set the admin port or other settings if the image supports it.
    };
    volumes = [
      "/var/lib/cookiecloud:/data/api/data"
    ];
  };

  services.traefik.proxies.cookiecloud = {
    rule = "Host(`${domain}`)";
    target = "http://localhost:${toString port}";
  };

  environment.global-persistence.directories = [
    "/var/lib/cookiecloud"
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/cookiecloud 0755 root root -"
  ];
}
