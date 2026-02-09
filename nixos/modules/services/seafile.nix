{
  config,
  pkgs,
  ...
}:
let
  settingsFormat = pkgs.formats.ini { };
  seafdavSettings = {
    WEBDAV = {
      enabled = true;
      port = config.ports.seafile-dav;
      fastcgi = false;
      share_name = "/dav";
    };
  };
  seafdavConf = settingsFormat.generate "seafdav.conf" seafdavSettings; # hardcode it due to dynamicuser
in
{
  services.seafile = {
    enable = true;
    adminEmail = "i@dora.im";
    initialAdminPassword = "$env(ADMIN_PASSWORD)"; # send by expect script
    ccnetSettings = {
      General.SERVICE_URL = "https://box.dora.im";
    };
    seafileSettings = {
      fileserver = {
        host = "127.0.0.1";
        port = config.ports.seafile-file-server;
      };
      quota.default = 100;
      history.keep_days = 30;
      library_trash.expire_days = 30;
    };
    seahubExtraConf = ''
      DEBUG = True
      CSRF_TRUSTED_ORIGINS = ["box.dora.im"]
      from importlib.machinery import SourceFileLoader
      import os,sys
      sys.path.append(os.path.dirname("${config.sops.templates."seahubConf.py".path}"))
      from seahubConf import *
    '';
  };
  sops.templates."seahubConf.py" = {
    mode = "0444";
    content = ''
      SITE_NAME = "box.dora.im"
      SITE_TITLE = "Box"
      FILE_SERVER_ROOT = "https://box.dora.im/seafhttp"
      # OIDC
      ENABLE_OAUTH = True
      OAUTH_ENABLE_INSECURE_TRANSPORT = True
      OAUTH_CLIENT_ID = "seafile"
      OAUTH_CLIENT_SECRET = "${config.sops.placeholder."seafile/oidc-secret"}"
      OAUTH_REDIRECT_URL = 'https://box.dora.im/oauth/callback/'
      OAUTH_PROVIDER_DOMAIN   = 'sso.dora.im'
      OAUTH_AUTHORIZATION_URL = 'https://sso.dora.im/realms/users/protocol/openid-connect/auth'
      OAUTH_TOKEN_URL         = 'https://sso.dora.im/realms/users/protocol/openid-connect/token'
      OAUTH_USER_INFO_URL     = 'https://sso.dora.im/realms/users/protocol/openid-connect/userinfo'
      OAUTH_SCOPE = ["profile", "email", "openid"]
      OAUTH_ATTRIBUTE_MAP = {
          "id":    (False, "not used"),
          "name":  (False, "full name"),
          "email": (True, "email"),
      }
      # MAIL
      EMAIL_USE_TLS = True
      EMAIL_HOST = "${config.lib.self.data.mail.smtp}"
      EMAIL_HOST_USER = "noreply@dora.im"
      EMAIL_HOST_PASSWORD = "${config.sops.placeholder."mail/noreply"}"
      EMAIL_PORT = ${toString config.ports.smtp}
      DEFAULT_FROM_EMAIL = EMAIL_HOST_USER
      SERVER_EMAIL = EMAIL_HOST_USER
    '';
  };
  environment.etc."seafile/conf/seafdav.conf".source = seafdavConf;
  sops.secrets = {
    "seafile/oidc-secret" = { };
    "seafile/password" = { };

  };

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = config.ports.nginx;
    virtualHosts."box.dora.im" = {
      locations."/".proxyPass = "http://unix:/run/seahub/gunicorn.sock";
      locations."/seafhttp/" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.seafile-file-server}/";
        recommendedProxySettings = true;
      };
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      seafile = {
        rule = "Host(`box.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "seafile";
      };
    };
    services = {
      seafile.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.nginx}"; } ];
      };
    };
  };
  systemd.services.seahub = {
    serviceConfig.EnvironmentFile = config.sops.templates."seafile-env".path;
    restartTriggers = [
      config.sops.templates."seafile-env".file
    ];
  };
  sops.templates."seafile-env".content = ''
    ADMIN_PASSWORD=${config.sops.placeholder."seafile/password"}
  '';
}
