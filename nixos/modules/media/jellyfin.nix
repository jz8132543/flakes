{
  config,
  nixosModules,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.services.jellyfin) user;
in
{
  imports = [ nixosModules.services.rclone ];
  services.jellyfin = {
    enable = true;
    group = "media";
  };

  users.users.${user} = {
    shell = pkgs.fish; # for media storage operation
    home = "/var/lib/jellyfin-media";
    createHome = true;
    extraGroups = [
      "video"
      "render"
      "media"
    ];
  };

  systemd.services.jellyfin = {
    after = [ "mount-alist.service" ];
    bindsTo = [ "mount-alist.service" ];
  };

  systemd.services.jellyfin-setup = {
    script = ''
      if [ -f network.xml ]; then
        ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace --update "/NetworkConfiguration/HttpServerPortNumber" --value "${toString config.ports.jellyfin}" network.xml
      fi
    '';
    path = with pkgs; [ xmlstarlet ];
    unitConfig = {
      ConditionPathExists = config.services.jellyfin.configDir;
    };
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = config.services.jellyfin.configDir;
      User = "jellyfin";
      Group = "jellyfin";
    };
    wantedBy = [ "jellyfin.service" ];
    before = [ "jellyfin.service" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      jellyfin = {
        rule = "Host(`jellyfin.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
      };
    };
    services = {
      jellyfin.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.jellyfin}"; } ];
      };
    };
  };

  systemd.tmpfiles.rules = [
    "Z '${config.services.jellyfin.dataDir}' 0777 jellyfin jellyfin - -"
    "Z '${config.users.users.jellyfin.home}' 0777 jellyfin jellyfin - -"
    "d '/mnt/alist' 0755 root root - -"
  ];

  # for vaapi support
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-utils
      vpl-gpu-rt # Base for newer Intel QuickSync
    ];
  };

  # https://jellyfin.org/docs/general/networking/index.html
  networking.firewall = {
    allowedUDPPorts = with config.ports; [
      jellyfin-auto-discovery-1
      jellyfin-auto-discovery-2
    ];
  };

  environment.global-persistence = {
    directories = [
      config.users.users.${user}.home
      config.services.jellyfin.dataDir
    ];
  };

  systemd.packages = with pkgs; [
    rclone
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
  ];
}
