{ config, ... }:
{
  services.murmur =
    let
      certDir = config.security.acme.certs."main".directory;
    in
    {
      enable = true;
      bandwidth = 320000;
      bonjour = true;
      registerName = "mumble.${config.networking.domain}";
      welcometext = "<br />Welcome to <b>mumble.${config.networking.domain}</b>";
      sslCert = "${certDir}/cert.pem";
      sslKey = "${certDir}/key.pem";
    };
}
