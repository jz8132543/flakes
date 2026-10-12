# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/containers.nix
#
# IBM ContextForge OCI 容器定义
#
# 单容器架构（ContextForge 将 UI + API + MCP 路由集于一体）：
#   • contextforge  — 核心服务（MCP 注册中心 + Virtual MCP API + Web UI）
#
# 网络策略：
#   --network=host：与宿主机共享网络栈，以便：
#     a) 访问原生 PG/Redis（loopback）
#     b) 被 Dify API 容器通过 loopback 访问（无需 Podman bridge）
#
# Dify 与 ContextForge 的联动：
#   Dify API 容器通过 MCP_GATEWAY_URL = "http://127.0.0.1:<mcpApiPort>"
#   调用 ContextForge 生成的 Virtual MCP 端点，实现 Workflow 工具链调用。
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  mcpConnVars,
  ...
}:
let
  cfg = config.services.ai.mcp;
  inherit (mcpConnVars)
    pgHost
    pgPort
    mcpPgUser
    mcpPgDb
    ;

  # API/UI 端口（由 ports 注册表统一管理）
  mcpApiPort = config.ports.mcp-contextforge-api;
  mcpUiPort = config.ports.mcp-contextforge-ui;
in
{
  virtualisation.oci-containers.containers.contextforge = {
    inherit (cfg) image;
    autoStart = true;
    extraOptions = [
      "--network=host"
      "--pull=missing"
      "--label=io.containers.autoupdate=registry"
    ];

    environment = {
      # ── 数据库 ────────────────────────────────────────────────────
      DATABASE_URL = "postgresql://${mcpPgUser}@${pgHost}:${toString pgPort}/${mcpPgDb}";
      DB_HOST = pgHost;
      DB_PORT = toString pgPort;
      DB_USER = mcpPgUser;
      DB_PASSWORD = ""; # 内网 trust
      DB_NAME = mcpPgDb;

      # ── 服务绑定 ──────────────────────────────────────────────────
      # API 端口（供 Dify 调用 Virtual MCP 端点）
      API_PORT = toString mcpApiPort;
      # Web UI 端口（管理界面，仅内网访问）
      UI_PORT = toString mcpUiPort;

      # ── 对外访问地址 ──────────────────────────────────────────────
      PUBLIC_URL = "https://${cfg.domain}";

      # ── MCP 网关配置 ──────────────────────────────────────────────
      # 允许注册的 MCP Server 来源（内网信任，允许所有）
      MCP_TRUSTED_ORIGINS = "127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10";

      # ── 日志 ──────────────────────────────────────────────────────
      LOG_LEVEL = "info";
      NODE_ENV = "production";

      # ── Dify 集成：向 Dify Workflow 暴露 Virtual MCP 端点 ─────────
      # ContextForge 将在此基础路径下注册所有虚拟 MCP 端点
      MCP_BASE_PATH = "/mcp";

      # ── 可选功能 ──────────────────────────────────────────────────
      TELEMETRY_ENABLED = "false";
    };

    environmentFiles = [
      config.sops.templates."contextforge-secret.env".path
    ];

    volumes = [
      "${cfg.dataDir}/config:/app/config"
      "${cfg.dataDir}/data:/app/data"
      "${cfg.dataDir}/logs:/app/logs"
    ];
  };

  # ── Systemd 启动拓扑 ───────────────────────────────────────────────
  systemd.services.podman-contextforge = {
    after = [
      "contextforge-db-init.service"
      "sops-install-secrets.service"
      "network-online.target"
    ];
    requires = [
      "contextforge-db-init.service"
    ];
    wantedBy = [ "multi-user.target" ];
  };
}
