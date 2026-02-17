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
    listening-port = 3479; # Move to 3479 to avoid conflict with derp on 3478
    tls-listening-port = 5349;
    use-auth-secret = true;
    static-auth-secret-file = config.sops.secrets."matrix/turn_shared_secret".path;
    realm = "dora.im";
    min-port = 49152;
    max-port = 49262;
    no-cli = true;
    cert = "${config.security.acme.certs."main".directory}/fullchain.pem";
    pkey = "${config.security.acme.certs."main".directory}/key.pem";
    # Matrix needs relaying
    no-tcp-relay = false;
    extraConfig = ''
      # listening-ip=0.0.0.0
      # external-ip=YOUR_PUBLIC_IP # If behind NAT, but on VPS it's usually fine
      userdb=/var/lib/coturn/turnserver.db
      no-tlsv1
      no-tlsv1_1
      # no-rfc5780 # Often needed for some clients
      # no-stun-backward-compatibility
      # response-origin-only-with-rfc5780
      no-multicast-peers
      secure-stun
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
