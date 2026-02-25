{
  PG ? "postgres.mag",
  ...
}:
{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.nextcloud;
in
{
  imports = [
    (import nixosModules.services.office { })
  ];
  systemd.tmpfiles.rules = [
    "d '${config.users.users.nextcloud.home}/' 0700 nextcloud nextcloud - -"
    "Z '${config.users.users.nextcloud.home}/' 0700 nextcloud nextcloud - -"
  ];
  services.collabora-online.settings = {
    remote_font_config.url = "https://${config.services.nextcloud.hostName}/apps/richdocuments/settings/fonts.json";
    storage.wopi = {
      "@allow" = true;
      host = [ config.services.nextcloud.hostName ];
    };
  };
  systemd.services.nextcloud-setup = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    serviceConfig.Restart = lib.mkForce "on-failure";
  };
  users.users.nextcloud.uid = config.ids.uids.nextcloud;
  systemd.services.nextcloud-setup.serviceConfig = {
    RequiresMountsFor = [ "/var/lib/nextcloud" ];
  };
  systemd.services.nextcloud-config-collabora =
    let
      inherit (config.services.nextcloud) occ;

      wopi_url = "http://[::1]:${toString config.ports.office}";
      public_wopi_url = "https://${config.services.collabora-online.settings.server_name}";
      wopi_allowlist = lib.concatStringsSep "," [
        "127.0.0.1"
        "::1"
      ];
    in
    {
      wantedBy = [ "multi-user.target" ];
      after = [
        "nextcloud-setup.service"
        "coolwsd.service"
      ];
      requires = [ "coolwsd.service" ];
      script = ''
        ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_url --value ${lib.escapeShellArg wopi_url}
        ${occ}/bin/nextcloud-occ config:app:set richdocuments public_wopi_url --value ${lib.escapeShellArg public_wopi_url}
        ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_allowlist --value ${lib.escapeShellArg wopi_allowlist}
        ${occ}/bin/nextcloud-occ richdocuments:setup
      '';
      serviceConfig = {
        Type = "oneshot";
      };
    };
  services.nextcloud = {
    enable = true;
    hostName = "cloud.${config.networking.domain}";
    https = true;
    enableImagemagick = true;
    appstoreEnable = true;
    maxUploadSize = "10G";
    configureRedis = true;
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      dbhost = PG;
      adminuser = "root";
      adminpassFile = config.sops.secrets."password".path;
    };
    settings = {
      # trusted_domains = [
      #   "nextcloud.ts.li7g.com"
      #   "nextcloud.dn42.li7g.com"
      # ];
      "overwrite.cli.url" = "https://${config.services.nextcloud.hostName}/";
      "upgrade.disable-web" = true;
      maintenance_window_start = 2;
      default_phone_region = "CN";
      mail_smtpmode = "smtp";
      mail_smtphost = "${config.environment.smtp_host}";
      # mail_smtpport = config.ports.smtp-starttls;
      mail_from_address = "noreply";
      mail_domain = "${config.networking.domain}";
      mail_smtpauth = true;
      mail_smtpname = "noreply@dora.im";
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
      ## oidc-login
      # allow_user_to_change_display_name = false;
      lost_password_link = "disabled";
      oidc_login_provider_url = "https://sso.dora.im/realms/users";
      oidc_login_client_id = "nextcloud";
      oidc_login_auto_redirect = false;
      oidc_login_end_session_redirect = false;
      oidc_login_button_text = "Log in with KeyCloak";
      oidc_login_hide_password_form = true;
      oidc_login_use_id_token = true;
      oidc_login_attributes = {
        id = "preferred_username";
        name = "name";
        mail = "email";
        groups = "groups";
      };
      oidc_login_default_group = "oidc";
      oidc_login_use_external_storage = false;
      oidc_login_scope = "openid profile email";
      oidc_login_disable_registration = false;
    };
    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
      "opcache.revalidate_freq" = "5";
      "opcache.jit" = "1255";
      "opcache.jit_buffer_size" = "128M";
    };
    secretFile = config.sops.templates."nextcloud-secret-config".path;
    # notify_push = {
    #   enable = true;
    #   bendDomainToLocalhost = true;
    #   logLevel = "info";
    # };
    extraAppsEnable = true;
    extraApps = with config.services.nextcloud.package.packages.apps; {
      inherit
        calendar
        contacts
        cookbook
        cospend
        deck
        gpoddersync # podcasts sync service
        # nextpod (see below)
        notes
        richdocuments # Collabora Online for Nextcloud - https://apps.nextcloud.com/apps/richdocuments
        tasks
        twofactor_webauthn
        oidc_login
        ;
    };
  };
  sops.templates."nextcloud-secret-config" = {
    content = builtins.toJSON {
      mail_smtppassword = config.sops.placeholder."mail/noreply";
      oidc_login_client_secret = config.sops.placeholder."nextcloud/oidc-secret";
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
    mode = "0444";
    # owner = "nextcloud";
  };

  sops.secrets."nextcloud/oidc-secret" = {
    restartUnits = [ "nextcloud-setup.service" ];
  };
  services.traefik.proxies.nextcloud = {
    rule = "Host(`cloud.${config.networking.domain}`)";
    target = "http://localhost:${toString config.services.nginx.defaultHTTPListenPort}";
    middlewares = [ "nextcloud" ];
  };

  services.traefik.dynamicConfigOptions.http.middlewares.nextcloud = {
    headers.customRequestHeaders.Host = "${cfg.hostName}";
  };
}
