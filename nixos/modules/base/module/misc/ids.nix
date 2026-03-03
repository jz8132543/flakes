{ lib, ... }:
{
  ids.uids = {
    # human users
    tippy = 1000;

    # other users
    nixos = 1099;

    # service users
    # nix-access-tokens = 400; # not using
    # nixbuild = 401; # not using
    # tg-send = 402;
    # service-mail = 403;
    hydra-builder = 404;
    hydra-builder-client = 405;
    # windows = 406;
    steam = 407;
    nextcloud = 501;

    # nixflix media stack
    jellyfin = lib.mkForce 600;
    jellyseerr = lib.mkForce 601;
    sonarr = lib.mkForce 602;
    radarr = lib.mkForce 603;
    prowlarr = lib.mkForce 604;
    lidarr = lib.mkForce 605;
    sabnzbd = lib.mkForce 606;
    recyclarr = lib.mkForce 607;
    qbittorrent = lib.mkForce 608;
    bazarr = lib.mkForce 609;
    autobrr = lib.mkForce 610;
    iyuu = lib.mkForce 611;
  };
  ids.gids = {
    # service groups
    nix-access-tokens = 400;
    nixbuild = 401;
    tg-send = 402;
    service-mail = 403;
    hydra-builder = 404;
    hydra-builder-client = 405;
    windows = 406;
    steam = 407;

    # nixflix media stack
    media = lib.mkForce 600;
    jellyfin = lib.mkForce 600;
    jellyseerr = lib.mkForce 601;
    sonarr = lib.mkForce 602;
    radarr = lib.mkForce 603;
    prowlarr = lib.mkForce 604;
    lidarr = lib.mkForce 605;
    sabnzbd = lib.mkForce 606;
    recyclarr = lib.mkForce 607;
    qbittorrent = lib.mkForce 608;
    bazarr = lib.mkForce 609;
    autobrr = lib.mkForce 610;
    iyuu = lib.mkForce 611;
  };
}
