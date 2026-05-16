{
  config,
  pkgs,
  lib,
  matrixRtcHosts,
  nixosModules,
  ...
}:
let
  domain = "m.dora.im";
  synapseClientId = "01J0YJ8F7Q8X2V6K9M4T1A3BCD";
  dbName = "matrix-authentication-service";
  dbUser = dbName;
  databaseHost = config.services.matrix.databaseHost or "postgres.mag";
  stateDir = "/var/lib/matrix-authentication-service";
  secretsDir = "${stateDir}/secrets";
  signingKeysDir = "${secretsDir}/keys";
  turnListeningPort = 3479;
  turnTlsPort = 5349;
  turnUris = lib.concatMap (hostName: [
    "turn:${hostName}.dora.im:${toString turnListeningPort}?transport=udp"
    "turn:${hostName}.dora.im:${toString turnListeningPort}?transport=tcp"
    "turns:${hostName}.dora.im:${toString turnTlsPort}?transport=udp"
    "turns:${hostName}.dora.im:${toString turnTlsPort}?transport=tcp"
  ]) matrixRtcHosts;
  configFile = config.sops.templates."matrix-authentication-service-config".path;
in
{
  imports = [
    nixosModules.services.traefik
  ];

  sops.secrets."matrix/turn_shared_secret" = {
    mode = "0440";
    owner = "matrix-synapse";
    group = "acme";
  };

  services.matrix-synapse.settings = {
    turn_uris = turnUris;
    turn_user_lifetime = "1h";
    turn_shared_secret = config.sops.placeholder."matrix/turn_shared_secret";
  };

  sops.templates."matrix-authentication-service-config" = {
    owner = "matrix-authentication-service";
    content = builtins.toJSON {
      secrets = {
        encryption = config.sops.placeholder."matrix/mas-encryption";
        keys = [
          {
            kid = "rsa";
            key_file = "${signingKeysDir}/rsa.pem";
          }
        ];
      };

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
        uri = "postgresql://${dbUser}@${databaseHost}/${dbName}";
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
            client_id = "matrix";
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

      clients = [
        {
          client_id = synapseClientId;
          client_auth_method = "client_secret_basic";
          client_secret = config.sops.placeholder."matrix/registration_shared_secret";
          redirect_uris = [
            "https://${domain}/_synapse/client/oidc/callback"
          ];
        }
      ];
    };
  };

  users.groups.matrix-authentication-service = { };
  users.users.matrix-authentication-service = {
    isSystemUser = true;
    group = "matrix-authentication-service";
  };

  sops.secrets."matrix/mas-encryption" = {
    owner = "matrix-authentication-service";
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
    rule = "Host(`m.dora.im`) && (Path(`/.well-known/openid-configuration`) || Path(`/.well-known/webfinger`) || Path(`/.well-known/change-password`) || PathPrefix(`/account`) || PathPrefix(`/authorize`) || PathPrefix(`/login`) || PathPrefix(`/logout`) || PathPrefix(`/register`) || PathPrefix(`/oauth2`) || PathPrefix(`/upstream`) || PathPrefix(`/recover`) || PathPrefix(`/reauth`) || PathPrefix(`/add-email`) || PathPrefix(`/verify-email`) || PathPrefix(`/change-password`) || PathPrefix(`/consent`) || PathPrefix(`/link`) || PathPrefix(`/device`) || PathPrefix(`/complete-compat-sso`) || PathPrefix(`/graphql`) || PathPrefix(`/assets`))";
    target = "http://localhost:${toString config.ports.mas}";
  };
}
