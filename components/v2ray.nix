{ config, pkgs, ... }:

{
  services = {
    v2ray = {
      enable = true;
      configFile = config.sops.secrets.v2ray.path;
    };
    traefik.dynamicConfigOptions.http = {
      routers.v2ray = {
        rule = "Host(`test.dora.im`) && PathPrefix(`/efa31d86-5756-40a6-96b5-a134fbc70410`)";
        entryPoints = [ "https" ];
        service = "v2ray";
      };
      services.v2ray.loadBalancer = {
        passHostHeader = true;
        servers = [{ url = "http://localhost:10001"; }];
      };
    };
    # nginx = {
    #   enable = true;
    #   virtualHosts."test.dora.im" = {
    #     forceSSL = true;
    #     useACMEHost = "dora.im";
    #     listen = [{
    #       addr = "0.0.0.0";
    #       port = 8443;
    #       ssl = true;
    #     }];
    #     locations = {
    #       "/" = { proxyPass = "https://mirrors.mit.edu/"; };
    #       "/Ray/" = {
    #         proxyPass = "http://127.0.0.1:10001";
    #         proxyWebsockets = true;
    #         extraConfig = ''
    #           proxy_redirect off;
    #           proxy_set_header Connection "upgrade";
    #           proxy_set_header Host $host;
    #           proxy_set_header X-Real-IP $remote_addr;
    #           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #         '';
    #       };
    #     };
    #   };
    # };
  };
  systemd.services.v2ray = {
    serviceConfig = {
      ExecStart = [
        ""
        (pkgs.writeShellScript "start" ''
          ${pkgs.v2ray}/bin/v2ray run -config $CREDENTIALS_DIRECTORY/config
        '')
      ];
      LoadCredential = "config:${config.sops.secrets.v2ray.path}";
    };
  };
}
