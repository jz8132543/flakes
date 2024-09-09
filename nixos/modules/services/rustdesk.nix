{ config, ... }:
{
  services.rustdesk-server = {
    enable = true;
    openFirewall = true;
    relayIP = config.networking.fqdn;
  };
}
