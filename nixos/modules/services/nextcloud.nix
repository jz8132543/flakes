{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.nextcloud;
in
{
  services.nextcloud = {
    enable = true;
    hostName = "cloud.${config.networking.domain}";
    https = true;
    enableImagemagick = true;
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      dbhost = PG;
      adminpassFile = config.sops.secrets."password".path;
    };
    settings = {
      # trusted_domains = [
      #   "nextcloud.ts.li7g.com"
      #   "nextcloud.dn42.li7g.com"
      # ];
      default_phone_region = "CN";
      mail_smtpmode = "smtp";
      mail_smtphost = "${config.environment.smtp_host}";
      # mail_smtpport = config.ports.smtp-starttls;
      mail_from_address = "nextcloud";
      mail_domain = "${config.networking.domain}";
      mail_smtpauth = true;
      mail_smtpname = "nextcloud@${config.networking.domain}";
      # https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html#enabledpreviewproviders
      enabledPreviewProviders = [
        # double slash to escape

        # default endabled providers
        "OC\\Preview\\BMP"
        "OC\\Preview\\GIF"
        "OC\\Preview\\JPEG"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\PNG"
        "OC\\Preview\\TXT"
        "OC\\Preview\\XBitmap"

        # additional providers
        "OC\\Preview\\Image"
        "OC\\Preview\\HEIC"
        "OC\\Preview\\TIFF"
        "OC\\Preview\\Movie"
      ];

      # memories
      "memories.vod.disable" = false; # enable video transcoding
      "memories.vod.vaapi" = true;
    };
    secretFile = config.sops.templates."nextcloud-secret-config".path;
    notify_push = {
      enable = true;
      bendDomainToLocalhost = true;
      logLevel = "info";
    };
  };
  sops.templates."nextcloud-secret-config" = {
    content = builtins.toJSON {
      mail_smtppassword = config.sops.placeholder."nextcloud/mail_password";
    };
    owner = "nextcloud";
  };
  environment.systemPackages = with pkgs; [
    ffmpeg
  ];
  # services.restic.backups.minio.paths = [ cfg.home ];

  systemd.services.phpfpm-nextcloud.serviceConfig = {
    # allow access to VA-API device
    PrivateDevices = lib.mkForce false;
  };

  sops.secrets."password" = {
    restartUnits = [ "nextcloud-setup.service" ];
    owner = "nextcloud";
  };
  sops.secrets."nextcloud/mail_password" = {
    restartUnits = [ "nextcloud-setup.service" ];
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      nextcloud = {
        rule = "Host(`cloud.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        middlewares = [
          "local@file"
          "nextcloud@file"
        ];
        service = "nextcloud";
      };
    };
    middlewares.nextcloud = {
      headers.customRequestHeaders.Host = "${cfg.hostName}";
    };
    services = {
      nextcloud.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.services.nginx.defaultHTTPListenPort}"; } ];
      };
    };
  };
}
