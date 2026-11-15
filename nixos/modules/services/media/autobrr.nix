{
  config,
  lib,
  pkgs,
  ...
}:
let
  autobrrConfigFormat = pkgs.formats.toml { };
  autobrrConfigTemplate = autobrrConfigFormat.generate "autobrr.toml" config.services.autobrr.settings;
  autobrrConfigScript = pkgs.writeShellScript "autobrr-config" ''
    set -euo pipefail

    secret="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/sessionSecret")"
    printf 'sessionSecret = "%s"\n' "$secret" > "$STATE_DIRECTORY/config.toml"
    ${pkgs.coreutils}/bin/cat ${autobrrConfigTemplate} >> "$STATE_DIRECTORY/config.toml"
    ${pkgs.coreutils}/bin/chmod 0600 "$STATE_DIRECTORY/config.toml"
  '';
in
{
  config = {
    services.autobrr = {
      enable = true;
      # secretFile removed (deprecated)
      settings = {
        host = "0.0.0.0";
        port = config.ports.autobrr;
        baseUrl = "";
        database = {
          type = "sqlite";
          dsn = "/data/.state/autobrr/autobrr.db";
        };
      };
    };

    systemd.services.autobrr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "autobrr";
      Group = lib.mkForce "media";
      # TODO: Remove this credential bridge when the upstream module supports the SOPS session secret directly.
      LoadCredential = [ "sessionSecret:${config.sops.secrets."media/autobrr_session_token".path}" ];
      ExecStartPre = lib.mkForce [ autobrrConfigScript ];
      ReadWritePaths = [
        "/data/.state/autobrr"
        "/var/lib/autobrr"
      ];
      UMask = "0002";
    };
    systemd.services.autobrr.after = [ "sops-install-secrets.service" ];
    systemd.services.autobrr.requires = [ "sops-install-secrets.service" ];
    sops.secrets."media/autobrr_session_token".restartUnits = [ "autobrr.service" ];

    users.users.autobrr = {
      isSystemUser = true;
      group = "media";
      uid = config.ids.uids.autobrr;
      home = "/var/lib/autobrr";
      createHome = true;
    };
    users.groups.autobrr.gid = config.ids.gids.autobrr;

  };
}
