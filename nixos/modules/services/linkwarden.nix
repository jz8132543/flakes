{
  config,
  nixosModules,
  ...
}:
let
  domain = "link.${config.networking.domain}";
  port = config.ports.linkwarden;
  dbName = "linkwarden";
  dbUser = "linkwarden";
in
{
  imports = [
    nixosModules.services.traefik
    nixosModules.services.postgres
  ];

  services.postgresql = {
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
  };

  virtualisation.oci-containers.containers.linkwarden = {
    image = "ghcr.io/linkwarden/linkwarden:latest";
    extraOptions = [ "--network=host" ];
    environment = {
      DATABASE_URL = "postgresql://${dbUser}@localhost:5432/${dbName}";
      NEXTAUTH_URL = "https://${domain}";
      PORT = toString port;
      # NEXTAUTH_SECRET will be provided via EnvironmentFile
    };
    environmentFiles = [ config.sops.templates."linkwarden-env".path ];
  };

  sops.templates."linkwarden-env".content = ''
    NEXTAUTH_SECRET=${config.sops.placeholder."password"}
  '';

  services.traefik.proxies.linkwarden = {
    rule = "Host(`${domain}`)";
    target = "http://localhost:${toString port}";
  };

  # For browser integration automation:
  # Linkwarden extension can be pre-configured if we provide a way to inject settings.
  # However, most extensions don't support declarative config via the web server.
  # We can add a well-known or a simple landing page with instructions.

  # Persistence
  environment.global-persistence.directories = [
    "/var/lib/linkwarden"
  ];

  virtualisation.oci-containers.containers.linkwarden.volumes = [
    "/var/lib/linkwarden:/data"
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/linkwarden 0755 root root -"
  ];
}
