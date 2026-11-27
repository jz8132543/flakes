{
  PG ? "postgres.ts",
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
  ldapServicesDn = "uid=services,ou=people,dc=dora,dc=im";
  openhands = config.services.ai.openhands or { enable = false; };
  lobeChat = config.services.new-api.lobeChat or { enable = false; };
  openhandsClientReconcile = lib.optionalString openhands.enable ''
    openhands_secret="$(cat ${
      lib.escapeShellArg config.sops.secrets.${openhands.oidc.clientSecretKey}.path
    })"
    openhands_secret_sql="$(printf '%s' "$openhands_secret" | ${pkgs.gawk}/bin/awk '{gsub(/\047/, "\047\047"); print}')"

    {
      cat <<SQL
    update client
    set enabled = true,
        public_client = false,
        client_authenticator_type = 'client-secret',
        secret = '$openhands_secret_sql',
        standard_flow_enabled = true,
        direct_access_grants_enabled = false
    where realm_id = (select id from realm where name = 'users')
      and client_id = '${openhands.oidc.clientId}';

    insert into redirect_uris (client_id, value)
    select c.id, 'https://${openhands.domain}/oauth2/callback'
    from client c join realm r on r.id = c.realm_id
    where r.name = 'users' and c.client_id = '${openhands.oidc.clientId}'
      and not exists (
        select 1 from redirect_uris u
        where u.client_id = c.id
          and u.value = 'https://${openhands.domain}/oauth2/callback'
      );

    delete from redirect_uris u
    using client c, realm r
    where u.client_id = c.id and c.realm_id = r.id
      and r.name = 'users' and c.client_id = '${openhands.oidc.clientId}'
      and u.value <> 'https://${openhands.domain}/oauth2/callback';

    insert into web_origins (client_id, value)
    select c.id, 'https://${openhands.domain}'
    from client c join realm r on r.id = c.realm_id
    where r.name = 'users' and c.client_id = '${openhands.oidc.clientId}'
      and not exists (
        select 1 from web_origins o
        where o.client_id = c.id and o.value = 'https://${openhands.domain}'
      );
    SQL
    } | psql -h ${lib.escapeShellArg PG} -U keycloak -d keycloak -v ON_ERROR_STOP=1 -Atq
    unset openhands_secret openhands_secret_sql
  '';
in
{
  imports = [
    nixosModules.services.acme
    nixosModules.services.restic
  ];
  # systemd.tmpfiles.rules = [
  #   "d ' /var/lib/private/lldap/' 0700 lldap lldap - -"
  # ];

  networking.firewall.allowedTCPPorts = [
    config.ports.ldaps
  ];
  services.keycloak = {
    enable = true;
    plugins = [ pkgs.keycloak-themes-phasetwo ];
    database = {
      type = "postgresql";
      createLocally = false;
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
    realmFiles = [ "/run/credentials/keycloak.service/users-realm.json" ];
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
    mode = "0400";
    content = ''
      {
        "realm": "users",
        "enabled": true,
        "registrationAllowed": false,
        "loginTheme": "phasetwo-ui",
        "accountTheme": "phasetwo-ui",
        "adminTheme": "phasetwo-ui",
        "emailTheme": "phasetwo-ui",
        "smtpServer": {
          "host": "${config.environment.smtp_host}",
          "port": "${toString config.environment.smtp_port}",
          "from": "services@dora.im",
          "auth": "true",
          "user": "services@dora.im",
          "password": "${config.sops.placeholder."mail/services"}",
          "ssl": "false",
          "starttls": "true"
        },
        "clients": [
          {
            "clientId": "memos",
            "name": "Memos",
            "enabled": true,
            "protocol": "openid-connect",
            "clientAuthenticatorType": "client-secret",
            "secret": "${config.sops.placeholder."memos/oidc_client_secret"}",
            "redirectUris": [
              "https://memos.dora.im/auth/callback"
            ],
            "webOrigins": [
              "https://memos.dora.im"
            ],
            "publicClient": false,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": false
          },
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
          }${lib.optionalString lobeChat.enable ''
            ,
            ${builtins.toJSON {
              clientId = "lobechat";
              name = "LobeChat";
              enabled = true;
              protocol = "openid-connect";
              clientAuthenticatorType = "client-secret";
              secret = toString config.sops.placeholder."lobechat/keycloak_client_secret";
              redirectUris = [ "https://chat.dora.im/api/auth/callback/keycloak" ];
              webOrigins = [ "https://chat.dora.im" ];
              publicClient = false;
              standardFlowEnabled = true;
              directAccessGrantsEnabled = false;
            }}
          ''}${lib.optionalString openhands.enable ''
            ,
            ${builtins.toJSON {
              inherit (openhands.oidc) clientId;
              name = "OpenHands Agent Workspace";
              enabled = true;
              protocol = "openid-connect";
              clientAuthenticatorType = "client-secret";
              secret = toString config.sops.placeholder.${openhands.oidc.clientSecretKey};
              redirectUris = [ "https://${openhands.domain}/oauth2/callback" ];
              webOrigins = [ "https://${openhands.domain}" ];
              publicClient = false;
              standardFlowEnabled = true;
              directAccessGrantsEnabled = false;
            }}
          ''}
          , {
            "clientId": "mcp-gateway",
            "name": "IBM ContextForge MCP Gateway",
            "enabled": true,
            "protocol": "openid-connect",
            "clientAuthenticatorType": "client-secret",
            "secret": "${config.sops.placeholder."password"}",
            "redirectUris": [
              "https://mcp.dora.im/auth/sso/callback/keycloak",
              "https://mcp.dora.im/*"
            ],
            "webOrigins": [
              "https://mcp.dora.im"
            ],
            "publicClient": false,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true
          },
          {
            "clientId": "persona-engine",
            "name": "AI Companion Persona Engine",
            "enabled": true,
            "protocol": "openid-connect",
            "clientAuthenticatorType": "client-secret",
            "secret": "${config.sops.placeholder."password"}",
            "redirectUris": [
              "https://persona.dora.im/*"
            ],
            "webOrigins": [
              "https://persona.dora.im"
            ],
            "publicClient": false,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true
          },
          {
            "clientId": "astrbot",
            "name": "AstrBot QQ Bot WebUI",
            "enabled": true,
            "protocol": "openid-connect",
            "clientAuthenticatorType": "client-secret",
            "secret": "${config.sops.placeholder."password"}",
            "redirectUris": [
              "https://bot.dora.im/*"
            ],
            "webOrigins": [
              "https://bot.dora.im"
            ],
            "publicClient": false,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true
          }${
            lib.optionalString (config.services.new-api.oidc.enable or false) ''
              ,
              {
                "clientId": "new-api",
                "name": "New API",
                "enabled": true,
                "protocol": "openid-connect",
                "clientAuthenticatorType": "client-secret",
                "secret": "${config.sops.placeholder."new-api/oidc_client_secret"}",
                "redirectUris": [
                  "https://${config.services.new-api.domain or "api.dora.im"}/oauth/oidc/callback",
                  "https://${config.services.new-api.domain or "api.dora.im"}/*"
                ],
                "webOrigins": [
                  "https://${config.services.new-api.domain or "api.dora.im"}"
                ],
                "publicClient": false,
                "standardFlowEnabled": true,
                "directAccessGrantsEnabled": false
              }''
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
    "memos/oidc_client_secret" = { };
    "mail/services" = { };
    "jellyfin/oidc_client_secret" = { };
    "password" = {
      mode = "0444";
    };
  }
  // lib.optionalAttrs lobeChat.enable {
    "lobechat/keycloak_client_secret" = { };
  }
  // lib.optionalAttrs (config.services.new-api.oidc.enable or false) {
    "new-api/oidc_client_secret" = { };
  };
  services.traefik.proxies.keycloak = {
    rule = "Host(`sso.dora.im`)";
    target = "http://localhost:${toString config.ports.keycloak}";
    homepage = {
      title = "Keycloak";
      category = "Identity";
      icon = "keycloak.png";
      description = "Single sign-on and account management";
    };
  };

  services.traefik.tcpProxies.ldap = {
    rule = "HostSNI(`*`)";
    target = "localhost:3389"; # Internal 389ds port
    entryPoints = [ "ldap" ];
    tls = false;
  };
  services.traefik.tcpProxies.ldaps = {
    rule = "HostSNI(`ldap.${config.networking.domain}`)";
    target = "localhost:3389";
    entryPoints = [ "ldaps" ];
    tls = true;
  };
  services.traefik.staticConfigOptions.entryPoints = {
    ldaps.address = ":${toString config.ports.ldaps}";
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
            services_password="$(${pkgs.coreutils}/bin/cat ${
              lib.escapeShellArg config.sops.secrets."mail/services".path
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

            if ! ldapsearch -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password" -b ${lib.escapeShellArg ldapServicesDn} -s base '(objectClass=inetOrgPerson)' dn >/dev/null 2>&1; then
              cat <<EOF | ldapadd -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password"
      dn: ${ldapServicesDn}
      objectClass: top
      objectClass: person
      objectClass: organizationalPerson
      objectClass: inetOrgPerson
      uid: services
      cn: services
      sn: services
      mail: services@dora.im
      userPassword: $services_password
      EOF
            fi

            if ! ldapsearch -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password" -b "uid=i,${ldapUsersDn}" -s base '(objectClass=inetOrgPerson)' dn >/dev/null 2>&1; then
              cat <<EOF | ldapadd -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password"
      dn: uid=i,${ldapUsersDn}
      objectClass: top
      objectClass: person
      objectClass: organizationalPerson
      objectClass: inetOrgPerson
      uid: i
      cn: i
      sn: i
      mail: i@dora.im
      userPassword: $bind_password
      EOF
            else
              cat <<EOF | ldapmodify -x -H ${lib.escapeShellArg bootstrapLdapUri} -D ${lib.escapeShellArg ldapBindDn} -w "$bind_password"
      dn: uid=i,${ldapUsersDn}
      changetype: modify
      replace: userPassword
      userPassword: $bind_password
      EOF
            fi
    '';
  };

  systemd.services.keycloak-ldap-reconcile = {
    description = "Reconcile Keycloak LDAP federation config";
    after = [
      "keycloak-ldap-bootstrap.service"
      "sops-install-secrets.service"
    ];
    requires = [
      "keycloak-ldap-bootstrap.service"
      "sops-install-secrets.service"
    ];
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

      psql -h ${lib.escapeShellArg PG} -U keycloak -d keycloak -v ON_ERROR_STOP=1 -Atq -c "
        update realm
        set login_theme = 'phasetwo-ui',
            account_theme = 'phasetwo-ui',
            admin_theme = 'phasetwo-ui',
            email_theme = 'phasetwo-ui',
            registration_allowed = false
        where name = 'users';

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

      ${openhandsClientReconcile}
    '';
  };

  systemd.services.keycloak = {
    preStart = ''
      install -d -m 0700 /run/keycloak/data/import
      ln -sfn "$CREDENTIALS_DIRECTORY/users-realm.json" /run/keycloak/data/import/users-realm.json
    '';
    after = [
      "tailscaled.service"
      "keycloak-ldap-bootstrap.service"
      "keycloak-ldap-reconcile.service"
    ];
    requires = [
      "keycloak-ldap-bootstrap.service"
      "keycloak-ldap-reconcile.service"
    ];
    serviceConfig = {
      LoadCredential = [ "users-realm.json:${config.sops.templates."keycloak-realm-dora".path}" ];
      Restart = lib.mkForce "always";
    };
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
