{
  config,
  pkgs,
  ...
}: {
  systemd.services.derper = {
    serviceConfig = {
      Restart = "always";
      DynamicUser = true;
      ExecStart = "${pkgs.tailscale-derp}/bin/derper -a ':${toString config.ports.derp}' --hostname='${config.networking.fqdn}' -c /tmp/derper.conf -verify-clients";
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
        servers = [{url = "http://localhost:${toString config.ports.derp}";}];
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
  networking.firewall.allowedTCPPorts = [3478];
  networking.firewall.allowedUDPPorts = [3478];
}
