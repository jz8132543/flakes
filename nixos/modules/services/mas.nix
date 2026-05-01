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
  domain = "m.dora.im";
  dbName = "matrix-authentication-service";
  dbUser = dbName;
  stateDir = "/var/lib/matrix-authentication-service";
  secretsDir = "${stateDir}/secrets";
  signingKeysDir = "${secretsDir}/keys";
  configFile = config.sops.templates."matrix-authentication-service-config".path;
in
{
  imports = [
    nixosModules.services.traefik
  ];

  sops.templates."matrix-authentication-service-config" = {
    owner = "matrix-authentication-service";
    content = builtins.toJSON {
      http = {
        public_base = "https://${domain}";
        listeners = [
          {
            name = "web";
            resources = [
              { name = "discovery"; }
              { name = "human"; }
              { name = "oauth"; }
              { name = "compat"; }
              {
                name = "graphql";
                playground = false;
                undocumented_oauth2_access = false;
              }
              {
                name = "assets";
                path = "${pkgs.matrix-authentication-service}/share/assets";
              }
            ];
            binds = [
              {
                host = "127.0.0.1";
                port = config.ports.mas;
              }
            ];
          }
        ];
      };

      database = {
        uri = "postgresql://${dbUser}@${PG}/${dbName}";
      };

      matrix = {
        kind = "synapse";
        homeserver = "dora.im";
        secret_file = config.sops.secrets."matrix/registration_shared_secret".path;
        endpoint = "http://127.0.0.1:${toString config.ports.matrix}";
      };

      passwords = {
        enabled = false;
      };

      account = {
        password_registration_enabled = false;
      };

      upstream_oauth2 = {
        providers = [
          {
            id = "01HFVBY12TMNTYTBV8W921M5FA";
            human_name = "Keycloak";
            issuer = "https://sso.dora.im/realms/users";
            client_id = "matrix-authentication-service";
            client_secret = config.sops.placeholder."matrix/oidc-secret";
            token_endpoint_auth_method = "client_secret_basic";
            pkce_method = "always";
            scope = "openid profile email";
            claims_imports = {
              localpart = {
                action = "require";
                template = "{{ user.preferred_username }}";
              };
              displayname = {
                action = "suggest";
                template = "{{ user.name }}";
              };
              email = {
                action = "suggest";
                template = "{{ user.email }}";
              };
            };
          }
        ];
      };
    };
  };

  users.groups.matrix-authentication-service = { };
  users.users.matrix-authentication-service = {
    isSystemUser = true;
    group = "matrix-authentication-service";
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 matrix-authentication-service matrix-authentication-service -"
    "d ${secretsDir} 0700 matrix-authentication-service matrix-authentication-service -"
    "d ${signingKeysDir} 0700 matrix-authentication-service matrix-authentication-service -"
  ];

  systemd.services.matrix-authentication-service = {
    description = "Matrix Authentication Service";
    after = [
      "postgresql.service"
      "keycloak.service"
    ];
    wants = [
      "postgresql.service"
      "keycloak.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      coreutils
      openssl
    ];
    serviceConfig = {
      User = "matrix-authentication-service";
      Group = "matrix-authentication-service";
      StateDirectory = "matrix-authentication-service";
      Restart = "always";
      ExecStart = "${lib.getExe' pkgs.matrix-authentication-service "mas-cli"} --config ${configFile} server";
    };
    preStart = ''
      set -eu

      install -d -m 0700 ${lib.escapeShellArg secretsDir}
      install -d -m 0700 ${lib.escapeShellArg signingKeysDir}

      if [ ! -s ${lib.escapeShellArg "${secretsDir}/encryption"} ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > ${lib.escapeShellArg "${secretsDir}/encryption"}
      fi

      if [ ! -s ${lib.escapeShellArg "${signingKeysDir}/rsa.pem"} ]; then
        ${pkgs.openssl}/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ${lib.escapeShellArg "${signingKeysDir}/rsa.pem"}
      fi

      chmod 0600 ${lib.escapeShellArg "${secretsDir}/encryption"} ${lib.escapeShellArg "${signingKeysDir}/rsa.pem"}
    '';
  };

  services.traefik.proxies.mas = {
    rule = "Host(`m.dora.im`) && (Path(`/.well-known/openid-configuration`) || Path(`/.well-known/webfinger`) || Path(`/.well-known/change-password`) || PathPrefix(`/account`) || PathPrefix(`/login`) || PathPrefix(`/logout`) || PathPrefix(`/register`) || PathPrefix(`/oauth2`) || PathPrefix(`/upstream`) || PathPrefix(`/recover`) || PathPrefix(`/reauth`) || PathPrefix(`/add-email`) || PathPrefix(`/verify-email`) || PathPrefix(`/change-password`) || PathPrefix(`/consent`) || PathPrefix(`/link`) || PathPrefix(`/device`) || PathPrefix(`/complete-compat-sso`) || PathPrefix(`/graphql`) || PathPrefix(`/assets`))";
    target = "http://localhost:${toString config.ports.mas}";
  };
}
