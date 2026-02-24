{
  config,
  osConfig,
  ...
}:
{
  sops.age.keyFile = "/nix/config/keys.txt";

  services.derp = {
    enable = true;
    hostname = osConfig.networking.fqdn;
    port = 50568;
    stunPort = 50569;
    certMode = "manual";
    certDir = "${config.services.acme.directory}/certificates";
  };

  services.acme = {
    enable = true;
    certs."main" = {
      domain = "*.dora.im";
      aliasNames = [ osConfig.networking.fqdn ];
    };
  };
}
