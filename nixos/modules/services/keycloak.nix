{
  PG ? "127.0.0.1",
  ...
}:
{
  config,
  lib,
  pkgs,
  nixosModules,
  ...
}:
let
  ldapUri = "ldaps://ldap.dora.im";
  bootstrapLdapUri = "ldap://127.0.0.1:3389";
  ldapBindDn = "cn=Directory Manager";
  ldapBaseDn = "dc=dora,dc=im";
  ldapUsersDn = "ou=people,dc=dora,dc=im";
  ldapMailDn = "uid=mail,ou=people,dc=dora,dc=im";
in
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
      ports = [ "127.0.0.1:3389:3389" ];
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
              "connectionUrl": "${ldapUri}",
              "usersDn": "${ldapUsersDn}",
              "bindDn": "${ldapBindDn}",
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
    "mail/ldap" = { };
    "mail/noreply" = { };
    "jellyfin/oidc_client_secret" = { };
    "password" = {
      mode = "0444";
    };
  };
  services.traefik.proxies.keycloak = {
    rule = "Host(`sso.dora.im`)";
    target = "http://localhost:${toString config.ports.keycloak}";
  };

  services.traefik.tcpProxies.ldap = {
    rule = "HostSNI(`*`)";
    target = "localhost:3389"; # Internal 389ds port
    entryPoints = [ "ldap" ];
    tls = true;
  };

  systemd.services.keycloak-ldap-bootstrap = {
    description = "Bootstrap Keycloak LDAP base entries";
    after = [ "podman-dirsrv.service" ];
    requires = [ "podman-dirsrv.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      coreutils
      openldap
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
            set -eu

            bind_password="$(${pkgs.coreutils}/bin/cat ${
              lib.escapeShellArg config.sops.secrets."password".path
            })"
            mail_password="$(${pkgs.coreutils}/bin/cat ${
              lib.escapeShellArg config.sops.secrets."mail/ldap".path
            })"

            for attempt in $(seq 1 60); do
              if ldapsearch -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password" -b ${lib.escapeShellArg ldapBaseDn} -s base '(objectClass=*)' dn >/dev/null 2>&1; then
                break
              fi
              if [ "$attempt" -eq 60 ]; then
                echo "389ds did not become ready" >&2
                exit 1
              fi
              ${pkgs.coreutils}/bin/sleep 1
            done

            if ! ldapsearch -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password" -b ${lib.escapeShellArg ldapUsersDn} -s base '(objectClass=organizationalUnit)' dn >/dev/null 2>&1; then
              cat <<EOF | ldapadd -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password"
      dn: ${ldapUsersDn}
      objectClass: top
      objectClass: organizationalUnit
      ou: people
      EOF
            fi

            if ! ldapsearch -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password" -b ${lib.escapeShellArg ldapMailDn} -s base '(objectClass=inetOrgPerson)' dn >/dev/null 2>&1; then
              cat <<EOF | ldapadd -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password"
      dn: ${ldapMailDn}
      objectClass: top
      objectClass: person
      objectClass: organizationalPerson
      objectClass: inetOrgPerson
      uid: mail
      cn: mail
      sn: mail
      mail: mail@dora.im
      userPassword: $mail_password
      EOF
            fi
    '';
  };

  systemd.services.keycloak-ldap-reconcile = {
    description = "Reconcile Keycloak LDAP federation config";
    after = [
      "postgresql.service"
      "keycloak-ldap-bootstrap.service"
    ];
    requires = [ "keycloak-ldap-bootstrap.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      coreutils
      postgresql
      gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu

      bind_password="$(${pkgs.coreutils}/bin/cat ${
        lib.escapeShellArg config.sops.secrets."password".path
      })"
      bind_password_sql="$(${pkgs.coreutils}/bin/printf '%s' "$bind_password" | ${pkgs.gawk}/bin/awk '{gsub(/\047/, "\047\047"); print}')"

      psql -h 127.0.0.1 -U keycloak -d keycloak -v ON_ERROR_STOP=1 -Atq -c "
        update component_config
        set value = '${ldapUri}'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'connectionUrl';

        update component_config
        set value = '${ldapUsersDn}'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'usersDn';

        update component_config
        set value = '${ldapBindDn}'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'bindDn';

        update component_config
        set value = '$bind_password_sql'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'bindCredential';

        update component_config
        set value = 'true'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'importEnabled';

        update component_config
        set value = 'rhds'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'vendor';

        update component_config
        set value = '86400'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'fullSyncPeriod';

        update component_config
        set value = '300'
        where component_id = (
          select c.id
          from component c
          join realm r on r.id = c.realm_id
          where r.name = 'users'
            and c.provider_type = 'org.keycloak.storage.UserStorageProvider'
            and c.provider_id = 'ldap'
          limit 1
        )
        and name = 'changedSyncPeriod';
      "
    '';
  };

  systemd.services.keycloak = {
    after = [
      "postgresql.service"
      "tailscaled.service"
      "keycloak-ldap-bootstrap.service"
      "keycloak-ldap-reconcile.service"
    ];
    requires = [
      "keycloak-ldap-bootstrap.service"
      "keycloak-ldap-reconcile.service"
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
