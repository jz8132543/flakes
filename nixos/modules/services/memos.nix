{
  config,
  nixosModules,
  ...
}:
let
  domain = "memos.${config.networking.domain}";
  port = config.ports.memos;
  dbName = "memos";
  dbUser = "memos";
  dbHost = "127.0.0.1";
in
{
  imports = [
    nixosModules.services.postgres
    nixosModules.services.traefik
  ];

  sops.secrets."memos/oidc_client_secret" = { };

  services.postgresql = {
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
  };

  services.memos = {
    enable = true;
    settings = {
      MEMOS_MODE = "prod";
      MEMOS_ADDR = "127.0.0.1";
      MEMOS_PORT = toString port;
      MEMOS_DATA = config.services.memos.dataDir;
      MEMOS_DRIVER = "postgres";
      MEMOS_DSN = "postgresql://${dbUser}@${dbHost}/${dbName}?sslmode=disable";
      MEMOS_INSTANCE_URL = "https://${domain}";
    };
  };

  systemd.services.memos = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  services.traefik.proxies.memos = {
    rule = "Host(`${domain}`)";
    target = "http://127.0.0.1:${toString port}";
  };

  # systemd.services."memos-oauth-seed" = {
  #   description = "Seed Memos OIDC identity provider";
  #   after = [ "memos.service"  ];
  #   requires = [ "memos.service" ];
  #   wantedBy = [ "multi-user.target" ];
  #   path = with pkgs; [ coreutils postgresql ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   script = ''
  #     set -eu
  #
  #     client_secret="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.sops.secrets."memos/oidc_client_secret".path})"
  #     config_json="{\"clientId\":\"memos\",\"clientSecret\":\"$client_secret\",\"authUrl\":\"https://sso.dora.im/realms/users/protocol/openid-connect/auth\",\"tokenUrl\":\"https://sso.dora.im/realms/users/protocol/openid-connect/token\",\"userInfoUrl\":\"https://sso.dora.im/realms/users/protocol/openid-connect/userinfo\",\"scopes\":[\"openid\",\"profile\",\"email\"],\"fieldMapping\":{\"identifier\":\"sub\",\"displayName\":\"name\",\"email\":\"email\",\"avatarUrl\":\"picture\"}}"
  #
  #     for attempt in $(seq 1 60); do
  #       if psql -h ${dbHost} -U ${dbUser} -d ${dbName} -v ON_ERROR_STOP=1 -Atq -c 'SELECT 1 FROM idp LIMIT 1;' >/dev/null 2>&1; then
  #         break
  #       fi
  #       if [ "$attempt" -eq 60 ]; then
  #         echo "memos database did not become ready" >&2
  #         exit 1
  #       fi
  #       ${pkgs.coreutils}/bin/sleep 1
  #     done
  #
  #     psql -h ${dbHost} -U ${dbUser} -d ${dbName} -v ON_ERROR_STOP=1 -c "INSERT INTO idp (uid, name, type, identifier_filter, config) VALUES ('${idpUid}', '${idpName}', 'OAUTH2', \$\$, '$config_json') ON CONFLICT (uid) DO UPDATE SET name = EXCLUDED.name, type = EXCLUDED.type, identifier_filter = EXCLUDED.identifier_filter, config = EXCLUDED.config;"
  #   '';
  # };

  environment.global-persistence.directories = [
    config.services.memos.dataDir
  ];
}
