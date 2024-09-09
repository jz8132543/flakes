{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.sogo = {
    enable = true;
    timezone = "Asia/Shanghai";
    vhostName = "mail.dora.im";
    extraConfig = ''
      /* General Preferences */
      WOPort = "127.0.0.1:${toString config.ports.sogo}";
      WOWorkersCount = 8;
      SOGoMemcachedHost = "/run/memcached/memcached.sock";
      SOGoMailDomain = "dora.im";
      SOGoPageTitle = "Doraemon";
      /* Database Configuration */
      SOGoProfileURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_user_profile";
      OCSFolderInfoURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_folder_info";
      OCSSessionsFolderURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_sessions_folder";
      OCSEMailAlarmsFolderURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_alarms_folder";
      OCSStoreURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_store";
      OCSAclURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_acl";
      OCSCacheFolderURL = "postgresql://sogo@${config.lib.self.data.database}/sogo/sogo_cache_folder";
      /* Mail Server Configuration */
      SOGoMailingMechanism = "smtp";
      SOGoSMTPServer = "smtps://mail.dora.im:465";
      SOGoSMTPAuthenticationType = PLAIN;
      SOGoIMAPServer = "imaps://mail.dora.im:993";
      SOGoIMAPAclConformsToIMAPExt = YES;
      SOGoForceExternalLoginWithEmail = YES;
      /* Authentication using LDAP */
      SOGoUserSources = (
          {
              type = ldap;
              CNFieldName = cn;
              IDFieldName = uid;
              UIDFieldName = uid;
              baseDN = "ou=people,dc=dora,dc=im";
              bindDN = "uid=mail,ou=people,dc=dora,dc=im";
              bindFields = (uid,mail);
              bindPassword = "LDAP_BINDPW";
              canAuthenticate = YES;
              displayName = "Doraemon";
              hostname = "${config.lib.self.data.ldap}";
              id = public;
              isAddressBook = YES;
          }
      );
    '';
    configReplaces = {
      LDAP_BINDPW = config.sops.secrets."mail/ldap".path;
    };
  };
  systemd.services.sogo =
    let
      services = [
        "openldap.service"
        "dovecot2.service"
        "postgresql.service"
        "memcached.service"
      ];
    in
    {
      wants = lib.mkForce services;
      after = lib.mkForce services;
    };
  services.memcached = {
    enable = true;
    enableUnixSocket = true;
    extraOptions = [
      "-a"
      "0770"
    ];
  };
  users.users.sogo.extraGroups = [ "memcached" ];
  sops.secrets."mail/ldap" = { };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      sogo = {
        rule = "Host(`${config.services.sogo.vhostName}`)";
        entryPoints = [ "https" ];
        service = "sogo";
      };
    };
    services = {
      sogo.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.nginx}"; } ];
      };
    };
  };
  services.nginx = {
    enable = true;
    defaultHTTPListenPort = config.ports.nginx;
    virtualHosts."${config.services.sogo.vhostName}" = lib.mkForce {
      locations."/".extraConfig = ''
        rewrite ^ https://$server_name/SOGo;
        allow all;
      '';

      # For iOS 7
      locations."/principals/".extraConfig = ''
        rewrite ^ https://$server_name/SOGo/dav;
        allow all;
      '';

      locations."^~/SOGo".extraConfig = ''
        proxy_pass http://127.0.0.1:${toString config.ports.sogo};
        proxy_redirect http://127.0.0.1:${toString config.ports.sogo} default;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_set_header x-webobjects-server-protocol HTTP/1.0;
        proxy_set_header x-webobjects-remote-host 127.0.0.1;
        proxy_set_header x-webobjects-server-port $server_port;
        proxy_set_header x-webobjects-server-name $server_name;
        proxy_set_header x-webobjects-server-url $scheme://$host;
        proxy_connect_timeout 90;
        proxy_send_timeout 90;
        proxy_read_timeout 90;
        # proxy_buffer_size 4k;
        # proxy_buffers 4 32k;
        # proxy_busy_buffers_size 64k;
        # proxy_temp_file_write_size 64k;
        # client_max_body_size 50m;
        client_body_buffer_size 128k;
        # FIX
        client_max_body_size 0;
        proxy_buffer_size 128k;
        proxy_buffers 64 512k;
        proxy_busy_buffers_size 512k;
        proxy_temp_file_write_size 512k;
        break;
      '';

      locations."/SOGo.woa/WebServerResources/".extraConfig = ''
        alias ${pkgs.sogo}/lib/GNUstep/SOGo/WebServerResources/;
        allow all;
      '';

      locations."/SOGo/WebServerResources/".extraConfig = ''
        alias ${pkgs.sogo}/lib/GNUstep/SOGo/WebServerResources/;
        allow all;
      '';

      locations."~ ^/SOGo/so/ControlPanel/Products/([^/]*)/Resources/(.*)$".extraConfig = ''
        alias ${pkgs.sogo}/lib/GNUstep/SOGo/$1.SOGo/Resources/$2;
      '';

      locations."~ ^/SOGo/so/ControlPanel/Products/[^/]*UI/Resources/.*\\.(jpg|png|gif|css|js)$".extraConfig = ''
        alias ${pkgs.sogo}/lib/GNUstep/SOGo/$1.SOGo/Resources/$2;
      '';
    };
  };
}
