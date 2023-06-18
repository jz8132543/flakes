{config, ...}: {
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      doraim = {
        rule = "Host(`dora.im`)";
        entryPoints = ["https"];
        service = "doraim";
      };
    };
    services = {
      doraim.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.nginx}";}];
      };
    };
  };

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = config.ports.nginx;
    virtualHosts."dora.im" = {
      # matrix
      locations."/.well-known/matrix/server".extraConfig = ''
        default_type application/json;
        return 200 '{ "m.server": "m.dora.im:443" }';
      '';
      locations."/.well-known/matrix/client".extraConfig = ''
        add_header Access-Control-Allow-Origin '*';
        default_type application/json;
        return 200 '{ "m.homeserver": { "base_url": "https://m.dora.im" } }';
      '';
      # mastodon
      locations."/.well-known/host-meta".extraConfig = ''
        return 301 https://zone.dora.im$request_uri;
      '';
      locations."/.well-known/webfinger".extraConfig = ''
        return 301 https://zone.dora.im$request_uri;
      '';
    };
  };
}
