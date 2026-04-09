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

    ${lib.getExe pkgs.dasel} -i toml -o toml --root \
      --var sessionSecret=file:"$CREDENTIALS_DIRECTORY/sessionSecret" \
      "sessionSecret = $sessionSecret" \
      < ${autobrrConfigTemplate} \
      > "$STATE_DIRECTORY/config.toml"
  '';
in
{
  config = {
    services.autobrr = {
      enable = true;
      secretFile = config.sops.secrets."media/autobrr_session_token".path;
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
      ExecStartPre = lib.mkForce [ autobrrConfigScript ];
      ReadWritePaths = [
        "/data/.state/autobrr"
        "/var/lib/autobrr"
      ];
      UMask = "0002";
    };

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
