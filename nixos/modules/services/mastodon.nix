{config, ...}: {
  services.mastodon = {
    enable = true;
    localDomain = "dora.im";
    # enableUnixSocket = false;
    mediaAutoRemove.olderThanDays = 3;
    vapidPublicKeyFile = config.sops.secrets."mastodon/VAPID_PUBLIC_KEY".path;
    vapidPrivateKeyFile = config.sops.secrets."mastodon/VAPID_PRIVATE_KEY".path;
    secretKeyBaseFile = config.sops.secrets."mastodon/SECRET_KEY_BASE".path;
    otpSecretFile = config.sops.secrets."mastodon/OTP_SECRET".path;
    smtp = {
      host = config.lib.self.data.mail.smtp;
      port = config.ports.smtp;
      passwordFile = config.sops.secrets."mastodon/mail".path;
      fromAddress = "mastodon@dora.im";
    };
    extraConfig = {
      WEB_DOMAIN = "zone.dora.im";
      DB_HOST = "postgres.dora.im";
      DB_PORT = "5432";
      OMNIAUTH_ONLY = "true";
      OIDC_ENABLED = "true";
      OIDC_DISPLAY_NAME = "sso.dora.im";
      OIDC_ISSUER = "https://sso.dora.im/realms/users";
      OIDC_DISCOVERY = "true";
      OIDC_SCOPE = "openid,profile,email";
      OIDC_UID_FIELD = "preferred_username";
      OIDC_REDIRECT_URI = "https://${config.services.mastodon.extraConfig.WEB_DOMAIN}/auth/auth/openid_connect/callback";
      OIDC_SECURITY_ASSUME_EMAIL_IS_VERIFIED = "true";
      OIDC_CLIENT_ID = "mastodon";
      S3_ENABLED = "true";
      S3_BUCKET = config.lib.self.data.mastodon.media.name;
      S3_HOSTNAME = config.lib.self.data.mastodon.media.host;
      S3_REGION = config.lib.self.data.mastodon.media.region.value;
    };
    extraEnvFiles = [config.sops.templates."mastodon-env".path];
  };

  sops.templates."mastodon-env" = {
    content = ''
      OIDC_CLIENT_SECRET=${config.sops.placeholder."mastodon/oidc-secret"}
      AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2_mastodon_media_key_id"}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2_mastodon_media_access_key"}
    '';
  };
  sops.secrets = {
    "mastodon/oidc-secret" = {owner = config.services.mastodon.user;};
    "mastodon/mail" = {owner = config.services.mastodon.user;};
    "mastodon/VAPID_PUBLIC_KEY" = {owner = config.services.mastodon.user;};
    "mastodon/VAPID_PRIVATE_KEY" = {owner = config.services.mastodon.user;};
    "mastodon/SECRET_KEY_BASE" = {owner = config.services.mastodon.user;};
    "mastodon/OTP_SECRET" = {owner = config.services.mastodon.user;};
  };
  sops.secrets."b2_mastodon_media_key_id".sopsFile = config.sops-file.get "terraform/common.yaml";
  sops.secrets."b2_mastodon_media_access_key".sopsFile = config.sops-file.get "terraform/common.yaml";

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = config.ports.nginx;
    virtualHosts."${config.services.mastodon.extraConfig.WEB_DOMAIN}" = {
      root = "${config.services.mastodon.package}/public/";
      locations."/system/".alias = "/var/lib/mastodon/public-system/";
      locations."/" = {
        tryFiles = "$uri @proxy";
      };
      locations."@proxy" = {
        proxyPass = "http://unix:/run/mastodon-web/web.socket";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header Proxy "";
        '';
      };
      locations."/api/v1/streaming/" = {
        proxyPass = "http://unix:/run/mastodon-streaming/streaming.socket";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header Proxy "";
        '';
      };
    };
  };
  systemd.services.nginx.serviceConfig.SupplementaryGroups = [
    config.services.mastodon.group
  ];
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      mastodon = {
        rule = "Host(`${config.services.mastodon.extraConfig.WEB_DOMAIN}`)";
        entryPoints = ["https"];
        service = "mastodon";
      };
    };
    services = {
      mastodon.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.nginx}";}];
      };
    };
  };
}
