{ config, ... }:

{
  services = {
    nginx = {
      enable = true;
      virtualHosts."k3s.${config.networking.fqdn}" = {
        forceSSL = true;
        useACMEHost = "dora.im";
        listen = [{
          addr = "0.0.0.0";
          port = 6443;
          ssl = true;
        }];
        locations = { "/" = { proxyPass = "https://127.0.0.1:6444/"; }; };
      };
    };
  };
}
