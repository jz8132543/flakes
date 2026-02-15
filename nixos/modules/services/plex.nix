{ config, pkgs, ... }:
let
  plexPass = pkgs.plex.override {
    plexRaw = pkgs.plexRaw.overrideAttrs (_old: rec {
      version = "1.41.4.9463-630c9f557";
      src = pkgs.fetchurl {
        url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_amd64.deb";
        sha256 = "aa14f01ff0e6f09123981653c11e43fffa71305719e0e23a8e16ce4914ad9180";
      };
    });
  };
in
{
  services.plex = {
    enable = true;
    package = plexPass;
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
