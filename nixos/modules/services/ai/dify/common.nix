# ─────────────────────────────────────────────────────────────────────────────
# services/ai/dify/default.nix
#
# Dify — 开源 AI 应用开发平台
#
# 架构决策：
#   • 基础设施层（PostgreSQL、Redis、Qdrant、Traefik）使用 NixOS 原生 services.*
#   • 业务层（web、api、worker、sandbox）使用 OCI 容器（podman rootless）
#   • 启动拓扑：PG/Redis/Qdrant → dify-db-init.service → OCI containers
#   • 密钥通过 sops-nix 模板注入，绝不明文落入 Nix Store
#
# 导入方式（fra0/default.nix）：
#   imports = nixosModules.services.ai.dify.all;
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.ai.dify;

  # ── 顶层连接变量（约束：禁止在子模块硬编码 localhost）────────────────────
  pgHost = "127.0.0.1";
  pgPort = 5432;
  difyPgUser = "dify";
  difyPgDb = "dify";

  # Redis 连接（原生 services.redis）
  redisHost = "127.0.0.1";
  redisPort = config.ports.dify-redis;

  # Qdrant 连接（原生 services.qdrant）
  qdrantHost = "127.0.0.1";
  qdrantPort = config.ports.dify-qdrant;

  # 内部服务端口（宿主机 loopback，避免暴露到公网）
  apiPort = config.ports.dify-api;
  webPort = config.ports.dify-web;
  sandboxPort = config.ports.dify-sandbox;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.postgres
    nixosModules.services.traefik
    nixosModules.services.restic
    # 注意：db-init.nix / containers.nix / traefik-proxy.nix / backup.nix
    # 由 haumea rake 系统通过 nixosModules.services.ai.dify.all 自动聚合加载，
    # 无需在此显式 import（否则会被双重加载）
  ];

  options.services.ai.dify = {
    enable = lib.mkEnableOption "Dify AI Application Platform";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "chat.dora.im";
      description = "Public domain for Dify Web UI.";
    };

    # ── 镜像版本管理（统一从此处修改，无需深入子文件）────────────────────
    image = {
      api = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/langgenius/dify-api:1.3.1";
        description = "Dify API / Worker container image.";
      };
      web = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/langgenius/dify-web:1.3.1";
        description = "Dify Web (Next.js) container image.";
      };
      sandbox = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/langgenius/dify-sandbox:0.2.10";
        description = "Dify Sandbox (code executor) container image.";
      };
    };

    # ── 可选：对接外部 Rerank 模型（BGE-reranker 等）────────────────────
    rerankApiBase = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Rerank model API base URL (e.g. http://127.0.0.1:8000).
        Leave empty to disable rerank integration.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/dify";
      description = "Root data directory for Dify volumes.";
    };
  };

  config = lib.mkMerge [
    # ── 透传连接变量给子模块（通过 _module.args）─────────────────────────
    # 置于 mkIf 外部，保证子模块在任何 enable 状态下都能正确接收参数
    {
      _module.args.difyConnVars = {
        inherit
          pgHost
          pgPort
          difyPgUser
          difyPgDb
          redisHost
          redisPort
          qdrantHost
          qdrantPort
          apiPort
          webPort
          sandboxPort
          ;
      };
    }

    # ── 主配置（受 enable 控制）──────────────────────────────────────────
    (lib.mkIf cfg.enable {
      # ── Qdrant 向量数据库（改为 OCI 容器，避免本地编译问题）────────────
      virtualisation.oci-containers.containers.qdrant = {
        image = "docker.io/qdrant/qdrant:v1.18.2";
        autoStart = true;
        extraOptions = [
          "--network=host"
          "--pull=missing"
        ];
        environment = {
          QDRANT__SERVICE__HOST = qdrantHost;
          QDRANT__SERVICE__HTTP_PORT = toString qdrantPort;
          QDRANT__SERVICE__GRPC_PORT = toString config.ports.dify-qdrant-grpc;
          QDRANT__STORAGE__STORAGE_PATH = "${cfg.dataDir}/qdrant/storage";
          QDRANT__TELEMETRY_DISABLED = "true";
        };
        volumes = [
          "${cfg.dataDir}/qdrant/storage:/qdrant/storage"
        ];
      };

      # Qdrant 容器的 systemd 依赖
      systemd.services.podman-qdrant = {
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
      };

      # ── Redis（独立实例，与系统其它 Redis 隔离）────────────────────────
      services.redis.servers."dify" = {
        enable = true;
        bind = redisHost;
        port = redisPort;
        # 纯内存缓存，不需要 AOF 持久化（Celery 队列可以在重启后重建）
        save = [ ]; # 关闭 RDB snapshot
        appendOnly = false;
      };

      # ── PostgreSQL 扩展（在全局 PG 实例上按需加载）────────────────────
      # vector 扩展用于 Dify 自身的 embedding 存储（备用）
      # pg_search 已由全局 postgres 模块启用
      services.postgresql = {
        # 不使用 ensureDatabases / ensureUsers，由 dify-db-init.service 手动管理
        # extensions 以 mkMerge 方式追加，与全局 postgres.nix 的 [pgvector pg_search] 合并
        extensions = ps: with ps; [ pgvector ];
      };

      # ── 数据目录 tmpfiles ───────────────────────────────────────────
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir}                      0750 root root - -"
        "d ${cfg.dataDir}/storage              0750 root root - -"
        "d ${cfg.dataDir}/qdrant              0750 root root - -"
        "d ${cfg.dataDir}/qdrant/storage      0750 root root - -"
      ];

      # ── 持久化（impermanence）─────────────────────────────────────
      environment.global-persistence.directories = [
        cfg.dataDir
      ];

      # ── SOPS 密钥声明 ──────────────────────────────────────────────
      # 密钥路径约定：secrets/dify/<key>
      # 在 secrets/<host>.yaml 中定义，通过 sops-nix 解密到 /run/secrets/
      sops.secrets = {
        # Dify 应用密钥（SECRET_KEY，用于 JWT/加密）
        "dify/secret_key" = { };
        # CPA/NewAPI 网关 API Key（用于 Dify 调用 LLM）
        "cpa/api_key" = { };
      };

      # ── sops template：生成含密文的 env 文件（不进 Nix Store）────────
      sops.templates."dify-secret.env".content = ''
        SECRET_KEY=${config.sops.placeholder."dify/secret_key"}
        OPENAI_API_KEY=${config.sops.placeholder."cpa/api_key"}
      '';
    })
  ];
}
