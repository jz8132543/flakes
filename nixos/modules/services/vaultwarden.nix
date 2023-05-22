{
  config,
  lib,
  ...
}: {
  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    config = {
      domain = "https://vault.dora.im";
      databaseUrl = "postgresql:///vaultwarden";
      signupsAllowed = false;
      emergencyAccessAllowed = false;
      websocketEnabled = true;
      websocketAddress = "127.0.0.1";
      websocketPort = config.ports.vaultwarden-websocket;
      rocketAddress = "127.0.0.1";
      rocketPort = config.ports.vaultwarden-http;
      smtpHost = "smtp.dora.im";
      smtpFrom = "vault@dora.im";
      smtpPort = config.ports.smtp-starttls;
      smtpSecurity = "starttls";
      smtpUsername = "vault@dora.im";
    };
    environmentFile = config.sops.templates."vaultwarden-env".path;
  };
  sops.templates."vaultwarden-env".content = ''
    ADMIN_TOKEN=${config.sops.placeholder."vaultwarden/ADMIN_TOKEN"}
    SMTP_PASSWORD=${config.sops.placeholder."vaultwarden/mail"}
  '';
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      vault = {
        rule = "Host(`vault.dora.im`) && PathPrefix(`/`)";
        entryPoints = ["https"];
        service = "vault";
      };
      vault_ws = {
        rule = "Host(`vault.dora.im`) && PathPrefix(`/notifications/hub`)";
        entryPoints = ["https"];
        service = "vault_ws";
      };
    };
    services = {
      vault.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.vaultwarden-http}";}];
      };
      vault_ws.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.vaultwarden-websocket}";}];
      };
    };
  };
  environment.systemPackages = [config.services.headscale.package];
  environment.persistence."/nix/persist" = {
    directories = ["/var/lib/headscale"];
  };
}
