{
  pkgs,
  config,
  nixosModules,
  ...
}:
let
  certDir = config.security.acme.certs."main".directory;
in
{
  imports = [ nixosModules.services.acme ];
  sops.secrets = {
    "traefik/cloudflare_token" = { };
    "traefik/KID" = { };
    "traefik/HMAC" = { };
  };
  networking.firewall.allowedTCPPorts = [ 8445 ];
  networking.firewall.allowedUDPPorts = [ 8445 ];
  systemd.services.tuic = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Restart = "always";
      User = "acme";
      ExecStart = "${pkgs.tuic}/bin/tuic-server -c ${config.sops.templates."tuic-config".path}";
      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_BIND_SERVICE"
      ];
    };
  };
  sops.secrets = {
    "proxy/uuid" = {
      restartUnits = [ "tuic.service" ];
    };
    "proxy/passwd" = {
      restartUnits = [ "tuic.service" ];
    };
  };
  sops.templates.tuic-config = {
    owner = "acme";
    content = builtins.toJSON {
      server = "[::]:8445";
      users = {
        "${config.sops.placeholder."proxy/uuid"}" = config.sops.placeholder."proxy/passwd";
      };
      certificate = "${certDir}/fullchain.pem";
      private_key = "${certDir}/key.pem";
      congestion_control = "new_reno";
      zero_rtt_handshake = true;
      alpn = [
        "h3"
        "spdy/3.1"
      ];
      log_level = "info";
    };
  };

  # environment.global-persistence = {
  #   directories = [
  #     "/etc/tuic"
  #   ];
  # };
}
