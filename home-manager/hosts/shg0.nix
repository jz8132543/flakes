{
  config,
  lib,
  osConfig,
  ...
}:
{
  nix.settings = {
    substituters = lib.mkForce [ "https://mirrors.ustc.edu.cn/nix-channels/store" ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };

  sops.age.keyFile = "/nix/config/keys.txt";

  services.derp = {
    enable = true;
    hostname = osConfig.networking.fqdn;
    port = 10043;
    stunPort = 3440;
    certMode = "manual";
    certDir = "${config.services.acme.directory}/certificates";
  };

  services.microsocks = {
    enable = true;
    port = osConfig.ports.seedboxProxyPort;
    bindInterface = null;
    bindAddr = "0.0.0.0";
  };

  services.acme = {
    enable = true;
    certs."main" = {
      domain = "*.dora.im";
      aliasNames = [ osConfig.networking.fqdn ];
    };
  };
}
