{ config, pkgs, ... }:
{
  services.plex = {
    enable = true;
    package = pkgs.plex-pass;
    openFirewall = true;
    # user = "media";
    # group = "media";
    dataDir = "/var/lib/plex";
  };

  environment.systemPackages = with pkgs; [
    # libav
    # libva
    # libva-utils
    # radeontop
  ];

  services.traefik.proxies.plex = {
    rule = "Host(`plex.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.plex}";
  };
}
