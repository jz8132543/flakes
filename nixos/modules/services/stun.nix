{ config, lib, ... }:
{
  sops.secrets = {
    "matrix/turn_shared_secret" = {
      mode = "0440";
      group = "acme";
    };
  };

  services.coturn = {
    enable = true;
    listening-port = 3479;
    use-auth-secret = true;
    static-auth-secret-file = config.sops.secrets."matrix/turn_shared_secret".path;
    realm = "${config.networking.fqdn}";
    min-port = 49152;
    max-port = 49262;
    no-cli = true;
    cert = "${config.security.acme.certs."main".directory}/fullchain.pem";
    pkey = "${config.security.acme.certs."main".directory}/key.pem";
    no-tcp-relay = true;
    extraConfig = ''
      listening-ip=0.0.0.0
      userdb=/var/lib/coturn/turnserver.db
      no-tlsv1
      no-tlsv1_1
      no-rfc5780
      no-stun-backward-compatibility
      response-origin-only-with-rfc5780
      no-multicast-peers
    '';
  };
  systemd.services.coturn.serviceConfig.StateDirectory = "coturn";
  systemd.services.coturn.serviceConfig.Group = lib.mkForce "acme";
  networking =
    let
      turn-ports = with config.services.coturn; [
        listening-port
        tls-listening-port
        alt-listening-port
        alt-tls-listening-port
      ];
    in
    {
      firewall = {
        allowedUDPPortRanges = with config.services.coturn; [
          {
            from = min-port;
            to = max-port;
          }
        ];
        allowedUDPPorts = turn-ports;
        allowedTCPPorts = turn-ports;
      };
    };
}
