{
  config,
  lib,
  inputs,
  ...
}:
{
  imports = [
    inputs.grimmory-flake.nixosModules.grimmory
  ];

  services.mysql.enable = lib.mkForce true;
  services.grimmory = {
    enable = true;
    database.passwordFile = config.sops.secrets.password.path;
  };

  services.traefik.proxies.book = {
    rule = "Host(`book.${config.networking.domain}`)";
    target = "http://127.0.0.1:6060";
  };
}
