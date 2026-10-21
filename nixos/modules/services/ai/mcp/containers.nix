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

  # API/UI 端口（ContextForge 单服务同时承载 UI 与 API，由 ports 统一管理）
  mcpApiPort = config.ports.mcp-contextforge-api;
in
{
  virtualisation.oci-containers.containers.contextforge = {
    inherit (cfg) image;
    autoStart = true;
    extraOptions = [
      "--network=host"
    ];

    environment = {
      # ── 数据库 (psycopg3 驱动要求 postgresql+psycopg://) ────────────
      DATABASE_URL = "postgresql+psycopg://${mcpPgUser}@${pgHost}:${toString pgPort}/${mcpPgDb}";

      # ── 服务绑定 ──────────────────────────────────────────────────
      HOST = "0.0.0.0";
      PORT = toString mcpApiPort;

      # ── 对外访问地址 ──────────────────────────────────────────────
      APP_DOMAIN = "https://${cfg.domain}";

      # ── 管理员账户 (邮箱认证) ─────────────────────────────────────
      PLATFORM_ADMIN_EMAIL = "i@${config.networking.domain}";
      BASIC_AUTH_USER = "i";

      # ── Keycloak SSO 单点登录 ─────────────────────────────────────
      SSO_ENABLED = "true";
      SSO_KEYCLOAK_ENABLED = "true";
      SSO_KEYCLOAK_BASE_URL = "https://sso.${config.networking.domain}";
      SSO_KEYCLOAK_REALM = "users";
      SSO_KEYCLOAK_CLIENT_ID = "mcp-gateway";

      # ── 跨网关路由域名白名单 ───────────────────────────────────────
      UAID_ALLOWED_DOMAINS = "[ \"${cfg.domain}\" ]";

      # ── UI 与 API 启用 ────────────────────────────────────────────
      MCPGATEWAY_UI_ENABLED = "true";
      MCPGATEWAY_ADMIN_API_ENABLED = "true";

      # ── MCP 网关与 SSRF 白名单（允许与同宿主机及局域网 MCP Server 通信）─
      SSRF_PROTECTION_ENABLED = "true";
      SSRF_ALLOW_LOCALHOST = "true";
      SSRF_ALLOW_PRIVATE_NETWORKS = "true";

      # ── 运行环境与日志 ────────────────────────────────────────────
      ENVIRONMENT = "production";
      LOG_LEVEL = "info";
      # ── 密码安全策略控制 ───────────────────────────────────────
      PASSWORD_POLICY_ENABLED = "false"; # 完全关闭密码复杂度与规则检查（允许任意密码）
      ADMIN_REQUIRE_PASSWORD_CHANGE_ON_BOOTSTRAP = "false"; # 禁用初次登录强制改密
      PASSWORD_CHANGE_ENFORCEMENT_ENABLED = "false"; # 关闭强制密码修改检查
      PASSWORD_MIN_LENGTH_USER = "8"; # 普通用户最小长度
      PASSWORD_MIN_LENGTH_PRIVILEGED = "8"; # 管理员最小长度（默认22，调小以防容器启动校验）
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
      "keycloak.service"
    ];
    wants = [
      "keycloak.service"
    ];
    requires = [
      "contextforge-db-init.service"
    ];
    wantedBy = [ "multi-user.target" ];
  };
}
