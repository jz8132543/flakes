{ pkgs, config, ... }:
let
  derperPort = config.ports.https;
  hostname = config.networking.hostName;
  user = "ts";
in
{
  systemd.services.derper = {
    script = ''
      ${pkgs.tailscale-derp}/bin/derper \
        -a ":${toString derperPort}" \
        -http-port "-1" \
        --hostname="${hostname}.${user}.dora.im" \
        -certdir "$CREDENTIALS_DIRECTORY" \
        -certmode manual \
        -verify-clients
    '';
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.service" ];
  };
  systemd.services.derper-watchdog = {
    script = ''
      while true; do
        if ! curl --silent --show-error --output /dev/null \
          https://${hostname}.${user}.dora.im:${toString derperPort}
        then
          echo "restart derper server"
          systemctl restart derper
        fi
        sleep 10
      done
    '';
    path = with pkgs; [ curl ];
    after = [ "derper.service" ];
    requiredBy = [ "derper.service" ];
  };
  services.traefik.dynamicConfigOptions.http = {
    routers.derp = {
      rule = "Host(`${hostname}.dora.im` && Path(`/derp`)";
      entryPoints = [ "https" ];
      service = "derp";
    };
    services.derp.loadBalancer = {
      passHostHeader = true;
      servers = [{ url = "http://127.0.0.1:${derperPort}"; }];
    };
  };
  networking.firewall.allowedTCPPorts = [
    derperPort
  ];
  networking.firewall.allowedUDPPorts = [
    3478
  ];
}
