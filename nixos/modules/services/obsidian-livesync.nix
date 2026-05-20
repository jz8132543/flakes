{
  config,
  lib,
  pkgs,
  nixosModules,
  ...
}:
let
  cfg = config.services.obsidianLiveSync;
  couchdbPort = 5984;
  couchdbDataDir = "/var/lib/obsidian-livesync/couchdb";
  couchdbHost = "127.0.0.1:${toString couchdbPort}";
  syncHost = "sync.${config.networking.domain}";
  publicUri = "https://${syncHost}";
  localIni = pkgs.writeText "obsidian-livesync-local.ini" ''
    [couchdb]
    single_node = true
    max_document_size = 50000000

    [chttpd]
    require_valid_user = true
    max_http_request_size = 4294967296

    [chttpd_auth]
    require_valid_user = true
    authentication_redirect = /_utils/session.html

    [httpd]
    WWW-Authenticate = Basic realm="couchdb"
    enable_cors = true

    [cors]
    origins = app://obsidian.md,capacitor://localhost,http://localhost,${publicUri}
    credentials = true
    headers = accept, authorization, content-type, origin, referer
    methods = GET, PUT, POST, HEAD, DELETE, OPTIONS
    max_age = 3600
  '';
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.restic
  ];

  options.services.obsidianLiveSync = {
    enable = lib.mkEnableOption "Obsidian LiveSync CouchDB backend";
    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "obsidiannotes";
      description = "CouchDB database name used by Obsidian LiveSync.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${couchdbDataDir} 0750 root root -"
    ];

    sops.secrets = {
      "obsidian-livesync/couchdb-user" = { };
      "obsidian-livesync/couchdb-password" = { };
    };

    sops.templates."obsidian-livesync-env" = {
      mode = "0440";
      owner = "root";
      content = ''
        COUCHDB_USER=${config.sops.placeholder."obsidian-livesync/couchdb-user"}
        COUCHDB_PASSWORD=${config.sops.placeholder."obsidian-livesync/couchdb-password"}
      '';
    };

    virtualisation.oci-containers.containers.obsidian-livesync = {
      image = "couchdb:3.5.0";
      extraOptions = [ "--network=host" ];
      environmentFiles = [ config.sops.templates."obsidian-livesync-env".path ];
      volumes = [
        "${couchdbDataDir}:/opt/couchdb/data"
        "${localIni}:/opt/couchdb/etc/local.d/10-local.ini:ro"
      ];
    };

    systemd.services.obsidian-livesync-init = {
      description = "Initialise CouchDB for Obsidian LiveSync";
      after = [
        "podman-obsidian-livesync.service"
        "network-online.target"
      ];
      requires = [ "podman-obsidian-livesync.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
      };
      environment = {
        COUCHDB_HOST = "http://${couchdbHost}";
        COUCHDB_DBNAME = cfg.databaseName;
        COUCHDB_USER_FILE = config.sops.secrets."obsidian-livesync/couchdb-user".path;
        COUCHDB_PASSWORD_FILE = config.sops.secrets."obsidian-livesync/couchdb-password".path;
      };
      script = ''
        set -euo pipefail

        couchdb_user="$(${pkgs.coreutils}/bin/cat "$COUCHDB_USER_FILE")"
        couchdb_password="$(${pkgs.coreutils}/bin/cat "$COUCHDB_PASSWORD_FILE")"
        until ${pkgs.curl}/bin/curl -fsS "$COUCHDB_HOST" >/dev/null; do
          ${pkgs.coreutils}/bin/sleep 2
        done

        ${pkgs.curl}/bin/curl -fsS -X PUT "$COUCHDB_HOST/_cluster_setup" \
          -H 'Content-Type: application/json' \
          -u "$couchdb_user:$couchdb_password" \
          -d '{"action":"enable_single_node","username":"'"$couchdb_user"'","password":"'"$couchdb_password"'","bind_address":"0.0.0.0","port":5984,"singlenode":true}' \
          || true

        ${pkgs.curl}/bin/curl -fsS -X PUT "$COUCHDB_HOST/_node/nonode@nohost/_config/httpd/enable_cors" \
          -H 'Content-Type: application/json' -u "$couchdb_user:$couchdb_password" -d '"true"' >/dev/null
        ${pkgs.curl}/bin/curl -fsS -X PUT "$COUCHDB_HOST/_node/nonode@nohost/_config/chttpd/enable_cors" \
          -H 'Content-Type: application/json' -u "$couchdb_user:$couchdb_password" -d '"true"' >/dev/null
        ${pkgs.curl}/bin/curl -fsS -X PUT "$COUCHDB_HOST/_node/nonode@nohost/_config/cors/origins" \
          -H 'Content-Type: application/json' -u "$couchdb_user:$couchdb_password" -d '"app://obsidian.md,capacitor://localhost,http://localhost,${publicUri}"' >/dev/null
        ${pkgs.curl}/bin/curl -fsS -X PUT "$COUCHDB_HOST/$COUCHDB_DBNAME" \
          -u "$couchdb_user:$couchdb_password" >/dev/null || true
      '';
    };

    services.restic.backups.borgbase.paths = [
      couchdbDataDir
    ];

    services.traefik.proxies.obsidian-livesync = {
      rule = "Host(`${syncHost}`)";
      target = "http://${couchdbHost}";
    };
  };
}
