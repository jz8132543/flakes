{
  config,
  pkgs,
  nixosModules,
  ...
}: {
  imports = [nixosModules.services.acme];
  systemd.services.derper = {
    path = [pkgs.iproute2];
    serviceConfig = {
      Restart = "always";
      DynamicUser = true;
      ExecStart =
        if !config.environment.isNAT
        then "${pkgs.tailscale}/bin/derper -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.derp-stun} --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -verify-clients -dev"
        else "${pkgs.tailscale}/bin/derper -a ':${toString config.ports.derp}' -stun-port ${toString config.ports.derp-stun} -http-port='-1' --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -certdir '$CREDENTIALS_DIRECTORY' -certmode manual -verify-clients -dev";
      LoadCredential = [
        "${config.networking.fqdn}.crt:${config.security.acme.certs."main".directory}/full.pem"
        "${config.networking.fqdn}.key:${config.security.acme.certs."main".directory}/key.pem"
      ];
    };
    restartIfChanged = true;
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      derp = {
        rule = "Host(`${config.networking.fqdn}`)";
        entryPoints = ["https"];
        service = "derp";
      };
    };
    services = {
      derp.loadBalancer = {
        passHostHeader = true;
        servers =
          if !config.environment.isNAT
          then [{url = "http://localhost:${toString config.ports.derp}";}]
          else [{url = "https://localhost:${toString config.ports.derp}";}];
      };
    };
  };

  # systemd.services.derper-watchdog = {
  #   script = ''
  #     while true; do
  #       if ! curl --silent --show-error --output /dev/null \
  #         https://shanghai.derp.li7g.com:${toString config.ports.derpPort}
  #       then
  #         echo "restart derper server"
  #         systemctl restart derper
  #       fi
  #       sleep 10
  #     done
  #   '';
  #   path = with pkgs; [curl];
  #   after = ["derper.service"];
  #   requiredBy = ["derper.service"];
  # };
  networking.firewall.allowedTCPPorts = [config.ports.derp];
  networking.firewall.allowedUDPPorts = [config.ports.derp-stun];
}
