{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.zoteroSyncServer;
  domain = config.networking.domain;
  zoteroHost = "zotero.${domain}";
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
    nixosModules.services.postgres
  ];

  options.services.zoteroSyncServer = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Self-hosted Zotero Data Synchronization Server with PostgreSQL backend";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = "Internal port for Zotero sync server container.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/eseifert/altero:latest";
      description = "Container image for self-hosted Zotero server (Altero or zotero-sync-server).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/zotero-sync-server";
      description = "State and cache directory for zotero sync server.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 自动在 PostgreSQL 中创建 zotero 独立数据库与授权用户
    services.postgresql = {
      ensureDatabases = [ "zotero" ];
      ensureUsers = [
        {
          name = "zotero";
          ensureDBOwnership = true;
        }
      ];
    };

    # 2. 状态目录与持久化
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/data 0750 root root -"
    ];

    # 3. 运行轻量级 OCI 同步容器，直连 PostgreSQL
    virtualisation.oci-containers.containers.zotero-sync-server = {
      inherit (cfg) image;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
      ];
      environment = {
        PORT = toString cfg.port;
        DATABASE_URL = "postgres://zotero@127.0.0.1:5432/zotero";
        DATA_DIR = "/data";
      };
      volumes = [
        "${cfg.dataDir}/data:/data"
      ];
    };

    # 4. Traefik 公网反向代理与 HTTPS
    services.traefik.proxies.zotero-sync-server = {
      rule = "Host(`${zoteroHost}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
