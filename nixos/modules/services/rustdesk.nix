{ config, ... }:
{
  services.rustdesk-server = {
    enable = true;
    openFirewall = true;
    signal.relayHosts = [ config.networking.fqdn ];
  };
}
