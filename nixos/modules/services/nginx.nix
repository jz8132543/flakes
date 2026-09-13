{
  config,
  lib,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.traefik
  ];

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = config.ports.nginx;
    virtualHosts."${config.networking.fqdn}" = {
      default = true;
    };
  };

  # 将 Host(fqdn) 的公网 HTTPS 请求经由 Traefik 代理至本地 Nginx
  services.traefik.proxies.fqdn-nginx = {
    rule = "Host(`${config.networking.fqdn}`)";
    target = "http://127.0.0.1:${toString config.ports.nginx}";
    priority = lib.mkDefault 10;
  };
}
