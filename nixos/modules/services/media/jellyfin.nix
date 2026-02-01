# Jellyfin Media Server
# Based on: https://github.com/Misterio77/nix-config/blob/main/hosts/merope/services/media/jellyfin.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.jellyfin = {
    enable = true;
    group = "media";
  };

  # Traefik reverse proxy
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      jellyfin = {
        rule = "Host(`jellyfin.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
      };
      # Access via tv.{domain}/jellyfin
      jellyfin-tv = {
        rule = "Host(`tv.${config.networking.domain}`) && PathPrefix(`/jellyfin`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
        middlewares = [ "jellyfin-stripprefix" ];
      };
      # Access via FQDN path: {fqdn}/jellyfin
      jellyfin-fqdn = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/jellyfin`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
        middlewares = [ "jellyfin-stripprefix" ];
      };
    };
    middlewares.jellyfin-stripprefix.stripPrefix.prefixes = [ "/jellyfin" ];
    services.jellyfin.loadBalancer = {
      passHostHeader = true;
      servers = [ { url = "http://localhost:${toString config.ports.jellyfin}"; } ];
    };
  };

  # Make config readable by jellyfin group (e.g. for jellyseerr integration)
  systemd = {
    tmpfiles.settings.jellyfinDirs = {
      "${config.services.jellyfin.dataDir}".d.mode = lib.mkForce "750";
    };
    services.jellyfin.serviceConfig.UMask = lib.mkForce "0027";
  };

  # Intel VAAPI hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-utils
      vpl-gpu-rt
    ];
  };

  # Jellyfin auto-discovery ports
  # https://jellyfin.org/docs/general/networking/index.html
  networking.firewall.allowedUDPPorts = with config.ports; [
    jellyfin-auto-discovery-1
    jellyfin-auto-discovery-2
  ];

  # Persistence
  environment.global-persistence.directories = [
    config.services.jellyfin.dataDir
  ];
}
