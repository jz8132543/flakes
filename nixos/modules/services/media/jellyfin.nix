{
  config,
  nixosModules,
  pkgs,
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
    home = "/var/lib/data/media";
    createHome = true;
    extraGroups = [
      "video"
      "render"
      "media"
    ];
  };

  systemd.services.jellyfin = {
    # Removed strict dependency on mount-alist since we are using local storage now.
    # after = [ "mount-alist.service" ];
    # bindsTo = [ "mount-alist.service" ];
  };

  systemd.services.jellyfin-setup = {
    script = ''
      if [ -f config/network.xml ]; then
        ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace --update "/NetworkConfiguration/HttpServerPortNumber" --value "${toString config.ports.jellyfin}" config/network.xml
      fi

      install_plugin() {
        local NAME=$1
        local PACKAGE=$2
        local ZIP_REGEX=$3
        mkdir -p "plugins/$NAME"
        rm -rf "plugins/$NAME"/*
        find "$PACKAGE" -name "$ZIP_REGEX" -exec ${pkgs.unzip}/bin/unzip {} -d "plugins/$NAME" \;
        chown -R jellyfin:media "plugins/$NAME"
      }

      # Install Plugins
      install_plugin "SSO-Auth" "${pkgs.jellyfin-plugin-sso}" "sso-authentication_*.zip"
      install_plugin "Reports" "${pkgs.jellyfin-plugin-reports}" "reports_*.zip"
      install_plugin "Intro-Skipper" "${pkgs.jellyfin-plugin-intro-skipper}" "intro-skipper-*.zip"
    '';
    path = with pkgs; [
      xmlstarlet
      unzip
    ];
    unitConfig = {
      ConditionPathExists = config.services.jellyfin.configDir;
    };
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = config.services.jellyfin.configDir;
      User = config.services.jellyfin.user;
      Group = config.services.jellyfin.group;
    };
    wantedBy = [ "jellyfin.service" ];
    before = [ "jellyfin.service" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    middlewares.strip-media = {
      stripPrefix.prefixes = [ "/media" ];
    };
    routers = {
      jellyfin = {
        rule = "Host(`jellyfin.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyfin";
      };
      jellyfin-media = {
        rule = "Host(`jellyfin.${config.networking.domain}`) && PathPrefix(`/media`)";
        entryPoints = [ "https" ];
        service = "jellyfin-media";
        middlewares = [ "strip-media" ];
      };
      jellyseerr = {
        rule = "Host(`seerr.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "jellyseerr";
        # middlewares = [ "auth" ];
      };
    };
    services = {
      jellyfin.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.jellyfin}"; } ];
      };
      jellyfin-media.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.jellyfin-webdav}"; } ];
      };
    };
  };

  systemd.services.jellyfin-webdav = {
    description = "WebDAV server for Jellyfin media";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "jellyfin";
      Group = "media";
      ExecStart = pkgs.writeShellScript "jellyfin-webdav-start" ''
        ${pkgs.rclone}/bin/rclone serve webdav /var/lib/data/media \
          --addr :${toString config.ports.jellyfin-webdav} \
          --vfs-cache-mode writes \
          --user alist \
          --pass $(${pkgs.coreutils}/bin/cat ${config.sops.secrets."password".path})
      '';
    };
  };

  sops.secrets."password" = {
    # owner = "jellyfin";
    mode = "0444";
  };

  sops.secrets."jellyfin/oidc_client_secret" = {
    # owner = "jellyfin";
    # Use this file content in the SSO Plugin configuration
    mode = "0444";
  };

  # layout.nix handles creation of /var/lib/data/media
  systemd.tmpfiles.rules = [
    "d '${config.services.jellyfin.dataDir}' 0775 ${config.services.jellyfin.user} ${config.services.jellyfin.group} - -"
    "Z '${config.services.jellyfin.dataDir}' 0775 ${config.services.jellyfin.user} ${config.services.jellyfin.group} - -"
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
      "/var/lib/data/media" # Persist the media library
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
