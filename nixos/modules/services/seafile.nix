{config, ...}: {
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
      quota.default = 2;
      history.keep_days = 30;
      library_trash.expire_days = 30;
    };
    seahubExtraConf = ''
      SITE_NAME = 'box.dora.im'
      SITE_TITLE = 'Box'
      FILE_SERVER_ROOT = 'https://box.dora.im/seafhttp'
    '';
  };

  services.nginx.virtualHosts."box.*" = {
    forceSSL = true;
    useACMEHost = "main";
    locations."/".proxyPass = "http://unix:/run/seahub/gunicorn.sock";
    locations."/seafhttp/" = {
      proxyPass = "http://127.0.0.1:${toString config.ports.seafile-file-server}/";
    };
  };

  systemd.services.seahub = {
    serviceConfig.EnvironmentFile = config.sops.templates."seahub-env".path;
    restartTriggers = [
      config.sops.templates."seahub-env".file
    ];
  };
  sops.templates."seahub-env".content = ''
    ADMIN_PASSWORD=${config.sops.placeholder."seahub_password"}
  '';
  sops.secrets."seahub_password" = {
    sopsFile = config.sops-file.terraform;
    restartUnits = ["seahub.service"];
  };
}
