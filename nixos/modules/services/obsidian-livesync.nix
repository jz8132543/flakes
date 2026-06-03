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
      "d ${couchdbDataDir} 0750 ${config.services.couchdb.user} ${config.services.couchdb.group} -"
      "d ${couchdbDataDir}/view_indexes 0750 ${config.services.couchdb.user} ${config.services.couchdb.group} -"
    ];

    services.couchdb = {
      enable = true;
      package = pkgs.couchdb3;
      bindAddress = "127.0.0.1";
      port = couchdbPort;
      databaseDir = couchdbDataDir;
      viewIndexDir = "${couchdbDataDir}/view_indexes";
      extraConfigFiles = [
        config.sops.templates."obsidian-livesync-admin".path
        localIni
      ];
    };

    sops.templates."obsidian-livesync-admin" = {
      mode = "0440";
      owner = config.services.couchdb.user;
      content = ''
        [admins]
        obsidian = ${config.sops.placeholder."password"}
      '';
    };

    systemd.services.obsidian-livesync-init = {
      description = "Initialise CouchDB for Obsidian LiveSync";
      after = [
        "couchdb.service"
        "network-online.target"
      ];
      requires = [ "couchdb.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
      };
      environment = {
        COUCHDB_HOST = "http://127.0.0.1:${toString couchdbPort}";
        COUCHDB_DBNAME = cfg.databaseName;
        COUCHDB_USER = "obsidian";
        COUCHDB_PASSWORD_FILE = config.sops.secrets."password".path;
      };
      script = ''
        set -euo pipefail

        couchdb_user="$COUCHDB_USER"
        couchdb_password="$(${pkgs.coreutils}/bin/cat "$COUCHDB_PASSWORD_FILE")"
        until ${pkgs.curl}/bin/curl -fsS "$COUCHDB_HOST" >/dev/null; do
          ${pkgs.coreutils}/bin/sleep 2
        done

        ${pkgs.curl}/bin/curl -fsS -X PUT "$COUCHDB_HOST/$COUCHDB_DBNAME" \
          -u "$couchdb_user:$couchdb_password" >/dev/null || true
      '';
    };

    services.restic.backups.borgbase.paths = [
      couchdbDataDir
    ];

    services.traefik.proxies.obsidian-livesync = {
      rule = "Host(`${syncHost}`)";
      target = "http://127.0.0.1:${toString couchdbPort}";
    };
  };
}
