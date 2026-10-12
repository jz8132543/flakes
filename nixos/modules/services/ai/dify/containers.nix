# ─────────────────────────────────────────────────────────────────────────────
# services/ai/dify/containers.nix
#
# Dify OCI 容器定义（基于 rootless podman）
#
# 容器拓扑：
#   ┌─────────────────────────────────────────────────────┐
#   │  dify-api    (Dify Flask API + migrations)          │ :apiPort
#   │  dify-worker (Celery worker，共享 API 镜像)          │ 无对外端口
#   │  dify-web    (Next.js 前端)                          │ :webPort
#   │  dify-sandbox (代码沙箱执行器)                       │ :sandboxPort (仅内网)
#   └─────────────────────────────────────────────────────┘
#
# 所有容器使用 --network=host 以便访问：
#   • 宿主机原生 PG/Redis/Qdrant（loopback）
#   • ContextForge MCP 总线（loopback）
#   • CPA/NewAPI 网关（loopback）
#
# 启动顺序约束：
#   dify-db-init.service → podman-dify-{api,worker,web,sandbox}.service
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  difyConnVars,
  ...
}:
let
  cfg = config.services.ai.dify;

  inherit (difyConnVars)
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

  # ── 共享环境变量（API 与 Worker 完全一致）─────────────────────────────
  commonApiEnv = {
    # ── 运行模式 ────────────────────────────────────────────────────────
    MODE = "api";
    LOG_LEVEL = "INFO";
    DEBUG = "false";
    FLASK_DEBUG = "false";

    # ── PostgreSQL ───────────────────────────────────────────────────
    DB_HOST = pgHost;
    DB_PORT = toString pgPort;
    DB_USERNAME = difyPgUser;
    DB_PASSWORD = ""; # 内网 trust，密码为空
    DB_DATABASE = difyPgDb;

    # ── Redis (Celery 消息队列 & 缓存) ──────────────────────────────
    REDIS_HOST = redisHost;
    REDIS_PORT = toString redisPort;
    REDIS_PASSWORD = "";
    REDIS_DB = "0";
    CELERY_BROKER_URL = "redis://${redisHost}:${toString redisPort}/1";
    BROKER_USE_SSL = "false";

    # ── 向量数据库：使用原生 Qdrant ──────────────────────────────────
    VECTOR_STORE = "qdrant";
    QDRANT_URL = "http://${qdrantHost}:${toString qdrantPort}";
    QDRANT_API_KEY = ""; # 内网无需认证
    QDRANT_CLIENT_TIMEOUT = "20";

    # ── 文件存储（本地卷，由 restic 备份）───────────────────────────
    STORAGE_TYPE = "local";
    STORAGE_LOCAL_PATH = "/app/api/storage";

    # ── 代码沙箱 ─────────────────────────────────────────────────────
    CODE_EXECUTION_ENDPOINT = "http://${toString "127.0.0.1"}:${toString sandboxPort}";
    CODE_EXECUTION_API_KEY = "dify-sandbox-secret"; # 内网 token，非关键密钥
    CODE_MAX_NUMBER = "9223372036854775807";
    CODE_MIN_NUMBER = "-9223372036854775808";

    # ── Dify 对外访问地址 ─────────────────────────────────────────────
    CONSOLE_WEB_URL = "https://${cfg.domain}";
    CONSOLE_API_URL = "https://${cfg.domain}";
    SERVICE_API_URL = "https://${cfg.domain}";
    APP_WEB_URL = "https://${cfg.domain}";

    # ── SSE / 流式响应：禁用响应缓冲 ────────────────────────────────
    # Traefik 已配置 3600s 超时，此处也禁用服务端缓冲
    HTTP_REQUEST_MAX_CONNECT_TIMEOUT = "10";
    HTTP_REQUEST_MAX_READ_TIMEOUT = "60";
    HTTP_REQUEST_MAX_WRITE_TIMEOUT = "20";

    # ── 邮件（可选，留空则禁用）─────────────────────────────────────
    MAIL_TYPE = "";
    MAIL_DEFAULT_SEND_FROM = "";

    # ── 统一大模型网关（NewAPI）──────────────────────────────────────
    # 配置 NewAPI 作为默认供应商
    OPENAI_API_BASE = "http://127.0.0.1:${toString config.ports.new-api}/v1";
    # 允许配置多个模型提供商（用户可以在 UI 中添加更多）
    MODEL_PROVIDER = "openai"; # 默认使用 OpenAI 兼容接口

    # ── Rerank 模型对接预留位 ─────────────────────────────────────────
    # 若 rerankApiBase 非空则注入；否则 Dify 内部会使用默认配置
    RERANK_API_URL = lib.optionalString (cfg.rerankApiBase != "") cfg.rerankApiBase;

    # ── ContextForge MCP 总线（同宿主机 loopback）────────────────────
    # Dify Workflow Plugin 通过此地址调用 Virtual MCP 端点
    MCP_GATEWAY_URL = "http://127.0.0.1:${toString config.ports.mcp-contextforge-api}";

    # ── 安全 ─────────────────────────────────────────────────────────
    WEB_API_CORS_ALLOW_ORIGINS = "*";
    CONSOLE_CORS_ALLOW_ORIGINS = "*";
  };

  # ── 统一 systemd 依赖声明（所有容器共用）────────────────────────────
  mkContainerDeps = extraAfter: {
    after = [
      "dify-db-init.service"
      "redis-dify.service" # services.redis.servers."dify" 生成的 unit 名
      "qdrant.service" # 原生 NixOS services.qdrant
      "sops-install-secrets.service"
    ]
    ++ extraAfter;
    requires = [
      "dify-db-init.service"
      "redis-dify.service"
      "qdrant.service" # 原生 NixOS services.qdrant
    ];
    wantedBy = [ "multi-user.target" ];
  };
in
{
  # ────────────────────────────────────────────────────────────────────
  # OCI 容器定义
  # ────────────────────────────────────────────────────────────────────
  virtualisation.oci-containers.containers = {

    # ── dify-api ────────────────────────────────────────────────────
    dify-api = {
      image = cfg.image.api;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
        "--label=io.containers.autoupdate=registry"
      ];
      environment = commonApiEnv // {
        MODE = "api";
        PORT = toString apiPort;
        SERVER_WORKER_AMOUNT = "2"; # 6核机器，API 给 2 个 worker
        SERVER_WORKER_CLASS = "gevent";
        GUNICORN_TIMEOUT = "3600"; # 超过 3600s 的 SSE 由 Traefik 层维持
      };
      environmentFiles = [
        config.sops.templates."dify-secret.env".path
      ];
      volumes = [
        "${cfg.dataDir}/storage:/app/api/storage"
      ];
    };

    # ── dify-worker ─────────────────────────────────────────────────
    # Celery 异步任务处理（文档解析、向量化、工作流执行）
    dify-worker = {
      image = cfg.image.api; # 与 API 共享同一镜像，仅 MODE 不同
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
        "--label=io.containers.autoupdate=registry"
      ];
      environment = commonApiEnv // {
        MODE = "worker";
        # Celery 并发度：6核机器保留 2 核给 PG/系统
        CELERY_WORKER_AMOUNT = "4";
        CELERY_AUTO_SCALE = "true";
        CELERY_MAX_WORKERS = "4";
        CELERY_MIN_WORKERS = "1";
      };
      environmentFiles = [
        config.sops.templates."dify-secret.env".path
      ];
      volumes = [
        "${cfg.dataDir}/storage:/app/api/storage"
      ];
    };

    # ── dify-web ─────────────────────────────────────────────────────
    # Next.js 前端（SSR，直接访问 API 服务）
    dify-web = {
      image = cfg.image.web;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
        "--label=io.containers.autoupdate=registry"
      ];
      environment = {
        PORT = toString webPort;
        CONSOLE_API_URL = ""; # 留空：前端与 API 同域，由 Traefik 路由
        APP_API_URL = "";
        # SSE 流式传输：禁用 Next.js 响应缓冲
        NEXT_TELEMETRY_DISABLED = "1";
      };
    };

    # ── dify-sandbox ─────────────────────────────────────────────────
    # 代码执行沙箱（gVisor/seccomp 隔离）
    dify-sandbox = {
      image = cfg.image.sandbox;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--pull=missing"
        "--security-opt=seccomp=unconfined" # sandbox 内部自行管理 seccomp
      ];
      environment = {
        API_KEY = "dify-sandbox-secret";
        GIN_MODE = "release";
        WORKER_TIMEOUT = "15";
        ENABLE_NETWORK = "true";
        HTTP_PROXY = "";
        HTTPS_PROXY = "";
        SANDBOX_PORT = toString sandboxPort;
      };
    };
  };

  # ── Systemd 依赖拓扑注入 ─────────────────────────────────────────────
  systemd.services = {
    podman-dify-api = mkContainerDeps [ ];
    podman-dify-worker = mkContainerDeps [ "podman-dify-api.service" ];
    podman-dify-web = mkContainerDeps [ "podman-dify-api.service" ];
    podman-dify-sandbox = {
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
