{
  config,
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.acme ];
  systemd.services.derper = {
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Restart = "always";
      DynamicUser = true;
      ExecStart =
        # ExecStart = "${pkgs.tailscale}/bin/derp -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.turn-port} --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -verify-clients";
        # ExecStart = "${pkgs.tailscale}/bin/derp -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.derp-stun} --hostname='\${HOSTNAME}' -c /tmp/derper.conf -verify-clients";
        # ExecStart = "${pkgs.tailscale}/bin/derper -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.derp-stun} --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -verify-clients -dev";
        if !config.environment.isNAT then
          "${pkgs.tailscale}/bin/derp -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.derp-stun} --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -verify-clients -dev"
        else
          "${pkgs.tailscale}/bin/derp -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.derp-stun} -http-port='-1' --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -certdir '$CREDENTIALS_DIRECTORY' -certmode manual -verify-clients -dev";
      LoadCredential = [
        "${config.networking.fqdn}.crt:${config.security.acme.certs."main".directory}/full.pem"
        "${config.networking.fqdn}.key:${config.security.acme.certs."main".directory}/key.pem"
      ];
      # Environment = "HOSTNAME=${config.networking.fqdn}";
    };
    restartIfChanged = true;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  services.traefik.proxies.derp = {
    rule = "Host(`${config.networking.fqdn}`)";
    target = "http://localhost:${toString config.ports.derp}";
  };

  networking.firewall.allowedTCPPorts = [ config.ports.derp ];
  networking.firewall.allowedUDPPorts = [ config.ports.turn-port ];
}
