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
      --redis=127.0.0.1:16381
      --http-prefix=/ntopng
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
        "+${pkgs.bash}/bin/bash -c '${pkgs.ntopng}/bin/ntopng --redis 127.0.0.1:16381 --http-port 0 --interface none --create-user \"i:$(cat ${config.sops.secrets.password.path}):1\"'"
      ];
    };
  };

  sops.secrets.password = { };
}
