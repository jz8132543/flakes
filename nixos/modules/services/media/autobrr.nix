{
  config,
  ...
}:
{
  services.autobrr = {
    enable = true;
    secretFile = config.sops.secrets."autobrr/secret".path; # Mandatory session secret
    # Ensure it can access torrent clients if verified via group, usually not strictly required if over HTTP
    # openFirewall = true; # Autobrr listens on localhost by default usually
  };

  sops.secrets."autobrr/secret" = {
    # owner = "autobrr";
    # group = "autobrr";
    mode = "0444";
  };

  # systemd.tmpfiles.rules = [
  #   "f /var/lib/autobrr/session_secret 0400 autobrr autobrr - unsecure_dummy_session_secret_change_me"
  # ];

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      autobrr = {
        rule = "Host(`autobrr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "autobrr";
        # middlewares = [ "auth" ];
      };
    };
    services = {
      autobrr.loadBalancer.servers = [ { url = "http://localhost:${toString config.ports.autobrr}"; } ];
    };
  };
}
