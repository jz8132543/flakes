{
  config,
  lib,
  pkgs,
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
      default = config.ports.zotero-sync;
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
    # 1. 自动预置 PostgreSQL 数据库与用户
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
        ALTERO_HOST = "127.0.0.1";
        ALTERO_PORT = toString cfg.port;
        ALTERO_DATABASE_URL = "postgresql+asyncpg://zotero@127.0.0.1:5432/zotero";
        ALTERO_STORAGE_PATH = "/data";
        ALTERO_PUBLIC_URL = "https://${zoteroHost}";
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

    # 5. SOPS 凭据引用与声明式初始化用户 (I)
    sops.secrets."password" = { };

    systemd.services.zotero-sync-server-init = {
      description = "Initialize Altero User and Password from SOPS";
      after = [ "podman-zotero-sync-server.service" ];
      requires = [ "podman-zotero-sync-server.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        podman
        coreutils
        gnugrep
        gawk
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # 等待 Altero 容器及内部数据库初始化完毕
        for i in $(seq 1 45); do
          if podman exec zotero-sync-server altero user list >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # 检查用户 I 是否已存在
        if ! podman exec zotero-sync-server altero user list 2>/dev/null | awk '{print $2}' | grep -qx "I"; then
          echo "==> Creating default Zotero sync user 'I'..."
          podman exec zotero-sync-server altero user add I --display-name "I"
          
          PASSWORD="$(cat "${config.sops.secrets."password".path}")"
          printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | podman exec -i zotero-sync-server altero user password I
          podman exec zotero-sync-server altero user admin I
          echo "==> User 'I' created, password set, and granted administrator privileges."
          echo "==> Note: Public registration is now permanently closed to external users."
        else
          echo "==> User 'I' already exists in Altero. Public registration remains closed."
        fi
      '';
    };
  };
}
