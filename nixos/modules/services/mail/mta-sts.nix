{
  config,
  pkgs,
  ...
}: let
  mtaStsDir = pkgs.writeTextDir ".well-known/mta-sts.txt" ''
    version: STSv1
    mode: enforce
    max_age: 604800
    mx: *.dora.im
  '';
in {
  services.nginx.enable = true;
  services.nginx.virtualHosts.maddy-mta-sts = {
    listen = [
      {
        addr = "127.0.0.1";
        port = config.ports.mta-sts;
      }
    ];
    root = mtaStsDir;
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      mta-sts = {
        rule = "Host(`mta-sts.dora.im`)";
        entryPoints = ["https"];
        service = "mta-sts";
      };
    };
    services = {
      mta-sts.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.mta-sts}";}];
      };
    };
  };
}
