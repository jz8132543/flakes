{
  config,
  ...
}:
{
  # Enable the Arr stack
  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  services.bazarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
    # Prowlarr doesn't strictly need media group but good for backups/consistency if needed
  };

  # Ensure simple permissions fix for Arr apps
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" ];
  users.users.bazarr.extraGroups = [ "media" ];

  users.groups.media = { };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      sonarr = {
        rule = "Host(`sonarr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "sonarr";
        # middlewares = [ "auth" ];
      };
      radarr = {
        rule = "Host(`radarr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "radarr";
        # middlewares = [ "auth" ];
      };
      prowlarr = {
        rule = "Host(`prowlarr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "prowlarr";
        # middlewares = [ "auth" ];
      };
      bazarr = {
        rule = "Host(`bazarr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "bazarr";
        # middlewares = [ "auth" ];
      };
    };
    services = {
      sonarr.loadBalancer.servers = [ { url = "http://localhost:${toString config.ports.sonarr}"; } ];
      radarr.loadBalancer.servers = [ { url = "http://localhost:${toString config.ports.radarr}"; } ];
      prowlarr.loadBalancer.servers = [ { url = "http://localhost:${toString config.ports.prowlarr}"; } ];
      bazarr.loadBalancer.servers = [ { url = "http://localhost:${toString config.ports.bazarr}"; } ];
    };
  };
}
