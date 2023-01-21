{ config, pkgs, ... }:

{
  sops.secrets.v2ray = {
    format = "binary";
    owner = config.systemd.services.v2ray.serviceConfig.User;
    sopsFile = config.sops.secretsDir + /v2ray.keytab;
  };

  services = {
    v2ray = {
      enable = true;
      configFile = config.sops.secrets.v2ray.path;
    };
    nginx = {
      enable = true;
      virtualHosts."test.dora.im" = {
        forceSSL = true;
        useACMEHost = "dora.im";
        listen = [{
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }];
        locations = {
          "/" = { proxyPass = "https://mirrors.mit.edu/"; };
          "/Ray/" = {
            proxyPass = "http://127.0.0.1:10001";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_redirect off;
              proxy_set_header Connection "upgrade";
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };
        };
      };
    };
  };
}
