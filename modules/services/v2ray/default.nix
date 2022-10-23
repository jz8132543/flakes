{ config, pkgs, ... }:

{ config, options, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.v2ray;
in
{
  options.modules.services.v2ray = {
    enable = _.mkBoolOpt false;
  };
} //
mkIf cfg.enable {
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
      virtualHosts."test.tippic.eu.org" = {
        forceSSL = true;
        useACMEHost = "tippic.eu.org";
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
