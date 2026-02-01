{ ... }:
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
    jellyfin = 600;
    jellyseerr = 601;
    sonarr = 602;
    radarr = 603;
    prowlarr = 604;
    lidarr = 605;
    sabnzbd = 606;
    recyclarr = 607;
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
    media = 600;
    jellyfin = 600;
    jellyseerr = 601;
    sonarr = 602;
    radarr = 603;
    prowlarr = 604;
    lidarr = 605;
    sabnzbd = 606;
    recyclarr = 607;
  };
}
