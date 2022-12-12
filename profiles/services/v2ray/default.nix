{ config, pkgs, ... }:

{
  sops.secrets.v2ray = {
    format = "binary";
    sopsFile = config.sops.secretsDir + /v2ray.keytab;
  };

  services = {
    v2ray = {
      enable = true;
      configFile = config.sops.secrets.v2ray.path;
    };
    nginx = {
      enable = true;
      virtualHosts."test.tippy.ml" = {
        forceSSL = true;
        useACMEHost = "tippy.ml";
        listen = [{
          addr = "0.0.0.0";
          port = 8443;
          ssl = true;
        }];
        locations = {
          "/" = { proxyPass = "https://mirrors.mit.edu/"; };
          "/Ray/" = {
            proxyPass = "http://127.0.0.1:10000";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };
        };
      };
    };
  };
}
