{
  config,
  pkgs,
  ...
}:
{
  services.redis.servers.ntopng = {
    enable = true;
    port = 16381;
  };

  services.ntopng = {
    enable = true;
    interfaces = [ "any" ];
    httpPort = config.ports.ntopng;
    extraConfig = ''
      -r=127.0.0.1:16381
      -v=/ntopng
    '';
  };

  services.traefik.proxies.ntopng = {
    rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/ntopng`)";
    target = "http://localhost:${toString config.services.ntopng.httpPort}";
  };

  systemd.services.ntopng = {
    after = [ "redis-ntopng.service" ];
    requires = [ "redis-ntopng.service" ];
    serviceConfig = {
      MemoryLimit = "2G";
      ExecStartPost = [
        "+${pkgs.bash}/bin/bash -c '${pkgs.ntopng}/bin/ntopng -r 127.0.0.1:16381 --create-user \"i:$(cat ${config.sops.secrets.password.path}):1\"'"
      ];
    };
  };

  sops.secrets.password = { };
}
