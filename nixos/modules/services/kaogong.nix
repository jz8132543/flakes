{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.services.kaogong;
in
{
  imports = [
    inputs.kaogong.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    services.kaogong = {
      port = config.ports.kaogong or 3000;
      frontendDomain = "kaogong.${config.networking.domain or "localhost"}";
      adminPasswordFile = config.sops.secrets."password".path;
    };

    services.traefik.proxies.kaogong = lib.mkIf (config.services.traefik.enable or false) {
      rule = "Host(`kaogong.${config.networking.domain or "localhost"}`)";
      target = "http://127.0.0.1:${toString config.ports.nginx}";
    };
  };
}
