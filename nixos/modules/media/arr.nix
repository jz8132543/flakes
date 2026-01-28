{
  ...
}:
{
  # Enable the Arr stack
  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  services.bazarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
    # Prowlarr doesn't strictly need media group but good for backups/consistency if needed
  };

  # Ensure simple permissions fix for Arr apps
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" ];
  users.users.bazarr.extraGroups = [ "media" ];

  users.groups.media = { };
}
