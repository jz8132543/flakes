{
  PG ? "127.0.0.1",
  ...
}:
{
  config,
  lib,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.acme
    nixosModules.services.restic
  ];
  # systemd.tmpfiles.rules = [
  #   "d ' /var/lib/private/lldap/' 0700 lldap lldap - -"
  # ];

  networking.firewall.allowedTCPPorts = [ config.ports.ldap ];
  services.keycloak = {
    enable = true;
    database = {
      type = "postgresql";
      host = PG;
      useSSL = false;
      passwordFile = "/dev/null";
    };
    settings = {
      hostname = "sso.dora.im";
      proxy-headers = "xforwarded";
      http-enabled = true;
      http-host = "127.0.0.1";
      http-port = config.ports.keycloak;
    };
    # realmFiles = [ config.sops.templates."keycloak-realm-dora".path ];
  };
  # services.openldap = {
  #   enable = true;
  #   # urlList = [ "ldaps://0.0.0.0:636" ];
  #   urlList = [
  #     "ldapi:///"
  #     "ldaps:///"
  #   ];
  #   # urlList = [ "ldap://0.0.0.0:389" ];
  #
  #   settings = {
  #     attrs = {
  #       "olcTLSCertificateFile" = "/var/lib/traefik-certs/ldap.dora.im/certificate.crt";
  #       "olcTLSCertificateKeyFile" = "/var/lib/traefik-certs/ldap.dora.im/privatekey.key";
  #       olcLogLevel = [
  #         "stats2"
  #         "config"
  #         "acl"
  #       ];
  #       # SSL
  #       olcTLSProtocolMin = "3.3";
  #       olcTLSCipherSuite = "DEFAULT:!kRSA:!kDHE";
  #     };
  #     children = {
  #       "cn=schema".includes = [
  #         "${pkgs.openldap}/etc/schema/core.ldif"
  #         "${pkgs.openldap}/etc/schema/cosine.ldif"
  #         "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
  #       ];
  #
  #       "olcDatabase={1}mdb".attrs = {
  #         objectClass = [
  #           "olcDatabaseConfig"
  #           "olcMdbConfig"
  #         ];
  #         olcDatabase = "{1}mdb";
  #         olcDbDirectory = "/var/lib/openldap/data";
  #         olcSuffix = "dc=dora,dc=im"; # 根域名
  #         olcRootDN = "cn=admin,dc=dora,dc=im"; # 管理员 DN
  #         olcRootPW.path = config.sops.secrets."password".path;
  #         olcAccess = [
  #           ''
  #             {0}to attrs=userPassword
  #               by self write
  #               by dn.exact="cn=admin,dc=dora,dc=im" write
  #               by anonymous auth
  #               by * none
  #           ''
  #           ''
  #             {1}to *
  #               by dn.exact="cn=admin,dc=dora,dc=im" write
  #               by * read
  #           ''
  #         ];
  #       };
  #     };
  #   };
  # };
  # environment.etc."openldap/init-base.ldif".text = ''
  #   dn: dc=dora,dc=im
  #   objectClass: top
  #   objectClass: dcObject
  #   objectClass: organization
  #   o: Dora Directory
  #   dc: dora
  #
  #   dn: ou=users,dc=dora,dc=im
  #   objectClass: organizationalUnit
  #   ou: users
  # '';
  #
  # systemd.services.openldap-init = {
  #   description = "Initialize OpenLDAP base entries (dc=dora,dc=im and ou=users)";
  #   after = [ "openldap.service" ];
  #   wants = [ "openldap.service" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = lib.mkForce ''
  #       set -e
  #
  #       # 如果 Base DN 已存在则跳过
  #       if ldapsearch -x -H ldaps://127.0.0.1:636 \
  #           -D "cn=admin,dc=dora,dc=im" -w "$(cat ${config.sops.secrets."password".path})" \
  #           -b "dc=dora,dc=im" "(objectClass=*)" >/dev/null 2>&1; then
  #         echo "Base DN exists, skipping initialization."
  #         exit 0
  #       fi
  #
  #       # 创建基础条目
  #       ldapadd -x -H ldaps://127.0.0.1:636 \
  #         -D "cn=admin,dc=dora,dc=im" -w "$(cat ${config.sops.secrets."password".path})" \
  #         -f /etc/openldap/init-base.ldif
  #     '';
  #     Restart = "on-failure";
  #     RestartSec = "3s";
  #   };
  #   wantedBy = [ "multi-user.target" ];
  # };
  # services.lldap = {
  #   enable = true;
  #   settings = rec {
  #     http_host = "localhost";
  #     http_port = config.ports.lldap;
  #     ldap_port = config.ports.ldap;
  #     ldap_base_dn = "dc=dora,dc=im";
  #     database_url = "postgresql://lldap@${PG}/lldap";
  #     ldap_user_dn = "sync";
  #     ldap_user_pass_file = "/run/credentials/lldap.service/password";
  #     bindDn = "cn=sync,${ldap_base_dn}";
  #     bindPasswordFile = config.sops.secrets."password".path;
  #     # force_ldap_user_pass_reset = true;
  #     # force_update_private_key = true;
  #     # jwt_secret_file = config.sops.secrets."lldap/jwt_secret".path;
  #     ldaps_options = {
  #       enabled = true;
  #       port = config.ports.ldaps;
  #       cert_file = "${config.security.acme.certs."main".directory}/cert.pem";
  #       key_file = "${config.security.acme.certs."main".directory}/key.pem";
  #     };
  #     verbose = true;
  #   };
  #   environmentFile = config.sops.templates."lldap-env".file;
  #   environment = {
  #     # LLDAP_FORCE_UPDATE_PRIVATE_KEY = "true";
  #     # LLDAP_FORCE_LDAP_USER_PASS_RESET = "true";
  #   };
  # };
  # systemd.services.lldap = {
  #   serviceConfig = {
  #     AmbientCapabilities = "CAP_NET_BIND_SERVICE";
  #     SupplementaryGroups = [ "acme" ];
  #     Restart = "always";
  #     # EnvironmentFile = config.sops.templates."lldap-env".path;
  #     LoadCredential = [
  #       "jwt-secret:${config.sops.secrets."lldap/jwt_secret".path}"
  #       "password:${config.sops.secrets."password".path}"
  #     ];
  #   };
  #   # restartTriggers = [
  #   #   config.sops.templates."lldap-env".file
  #   # ];
  # };
  # sops.templates."lldap-env" = {
  #   mode = "0444";
  #   content = ''
  #     LLDAP_JWT_SECRET_FILE=/run/credentials/lldap.service/jwt-secret
  #     LLDAP_SERVER_KEY_SEED=${config.sops.placeholder."lldap/LLDAP_SERVER_KEY_SEED"}
  #     # LLDAP_FORCE_UPDATE_PRIVATE_KEY=true
  #     # LLDAP_FORCE_LDAP_USER_PASS_RESET=true
  #   '';
  # };
  # sops.templates."keycloak-realm-dora" = {
  #   mode = "0444";
  #   content = ''
  #     {
  #       "realm": "users",
  #       "enabled": true,
  #       "userFederationProviders": [
  #         {
  #           "displayName": "LDAP",
  #           "providerName": "ldap",
  #           "config": {
  #             "priority": "0",
  #             "fullSyncPeriod": "86400",
  #             "changedSyncPeriod": "3600",
  #             "cachePolicy": "DEFAULT",
  #             "importEnabled": "true",
  #             "enabled": "true",
  #             "vendor": "other",
  #             "connectionUrl": "ldaps://ldap.dora.im:636",
  #             "usersDn": "ou=users,dc=dora,dc=im",
  #             "bindDn": "cn=admin,dc=dora,dc=im",
  #             "bindCredential": "",
  #             "useTruststoreSpi": "ldapsOnly",
  #             "pagination": "true"
  #           }
  #         }
  #       ]
  #     }
  #   '';
  # };
  sops.secrets = {
    "lldap/LLDAP_SERVER_KEY_SEED" = { };
    "lldap/jwt_secret" = {
      mode = "0444";
    };
    "password" = {
      mode = "0444";
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      keycloak = {
        rule = "Host(`sso.dora.im`)";
        entryPoints = [ "https" ];
        service = "keycloak";
      };
      ldap = {
        rule = "Host(`ldap.dora.im`)";
        entryPoints = [ "https" ];
        service = "ldap";
      };
    };
    services = {
      keycloak.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.keycloak}"; } ];
      };
      ldap.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.lldap}"; } ];
        # servers = [ { address = "127.0.0.1:389"; } ];
        # server.port = 389;
      };
    };
  };
  systemd.services.keycloak = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    serviceConfig.Restart = lib.mkForce "always";
  };
  services.restic.backups.borgbase.paths = [
    # "/var/lib/private/lldap/"
    "/var/lib/openldap/"
  ];
  systemd.services."restic-backups-borgbase" = {
    # requires = ["lldap.service"];
    # after = [ "lldap.service" ];
    after = [ "openldap.service" ];
  };
}
