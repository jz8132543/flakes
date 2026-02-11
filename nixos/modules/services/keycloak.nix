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
      passwordFile = "/dev/null"; # Required by NixOS module assertion, but PostgreSQL uses trust auth
    };
    settings = {
      hostname = "sso.dora.im";
      proxy-headers = "xforwarded";
      http-enabled = true;
      http-host = "127.0.0.1";
      http-port = config.ports.keycloak;
    };
    realmFiles = [ config.sops.templates."keycloak-realm-dora".path ];
  };
  virtualisation.podman.enable = true;
  virtualisation.oci-containers = {
    backend = "podman";
    containers.dirsrv = {
      image = "quay.io/389ds/dirsrv:latest";
      ports = [ "${toString config.ports.ldap}:3389" ];
      volumes = [ "/var/lib/389ds:/data" ];
      environmentFiles = [ config.sops.templates."dirsrv-env".path ];
      environment = {
        DS_SUFFIX_NAME = "dc=dora,dc=im";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/389ds 0755 root root -"
  ];
  sops.templates."keycloak-realm-dora" = {
    mode = "0444";
    content = ''
      {
        "realm": "users",
        "enabled": true,
        "smtpServer": {
          "host": "${config.environment.smtp_host}",
          "port": "${toString config.environment.smtp_port}",
          "from": "noreply@dora.im",
          "auth": "true",
          "user": "noreply@dora.im",
          "password": "${config.sops.placeholder."mail/noreply"}",
          "ssl": "false",
          "starttls": "true"
        },
        "clients": [
          {
            "clientId": "jellyfin",
            "name": "Jellyfin Media Server",
            "enabled": true,
            "protocol": "openid-connect",
            "clientAuthenticatorType": "client-secret",
            "secret": "${config.sops.placeholder."jellyfin/oidc_client_secret"}",
            "redirectUris": [
              "https://jellyfin.dora.im/sso/OID/redirect/jellyfin"
            ],
            "webOrigins": [
              "https://jellyfin.dora.im"
            ],
            "publicClient": false,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true
          }
        ],
        "userFederationProviders": [
          {
            "displayName": "LDAP",
            "providerName": "ldap",
            "config": {
              "priority": "0",
              "editMode": "WRITABLE",
              "fullSyncPeriod": "86400",
              "changedSyncPeriod": "300",
              "cachePolicy": "DEFAULT",
              "importEnabled": "true",
              "enabled": "true",
              "vendor": "rhds",
              "connectionUrl": "ldap://localhost:${toString config.ports.ldap}",
              "usersDn": "ou=People,dc=dora,dc=im",
              "bindDn": "cn=Directory Manager",
              "bindCredential": "${config.sops.placeholder."password"}",
              "pagination": "true",
              "syncRegistrations": "true"
            }
          }
        ]
      }
    '';
  };
  sops.templates."dirsrv-env".content = ''
    DS_DM_PASSWORD=${config.sops.placeholder."password"}
  '';
  sops.secrets = {
    "mail/noreply" = { };
    "jellyfin/oidc_client_secret" = { };
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
        servers = [ { url = "http://localhost:389"; } ];
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
    "/var/lib/389ds/"
  ];
  systemd.services."restic-backups-borgbase" = {
    # requires = ["lldap.service"];
    # after = [ "lldap.service" ];
    after = [ "podman-dirsrv.service" ];
  };
}
