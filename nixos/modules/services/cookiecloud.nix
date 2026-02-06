{
  config,
  nixosModules,
  ...
}:
let
  domain = "cookiecloud.${config.networking.domain}";
  port = config.ports.cookiecloud;
in
{
  imports = [ nixosModules.services.traefik ];

  virtualisation.oci-containers.containers.cookiecloud = {
    image = "easychen/cookiecloud:latest";
    ports = [ "${toString port}:8088" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.cookiecloud = {
      rule = "Host(`${domain}`)";
      entryPoints = [ "https" ];
      service = "cookiecloud";
    };
    services.cookiecloud.loadBalancer.servers = [
      { url = "http://localhost:${toString port}"; }
    ];
  };

  environment.global-persistence.directories = [
    "/var/lib/cookiecloud"
  ];
  # CookieCloud might need a volume for data persistence if it stores anything.
  # Looking at typical docker usage: -v /path/to/data:/data/api/data
  # Let's add it.
  virtualisation.oci-containers.containers.cookiecloud.volumes = [
    "/var/lib/cookiecloud:/data/api/data"
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/cookiecloud 0755 root root -"
  ];
}
