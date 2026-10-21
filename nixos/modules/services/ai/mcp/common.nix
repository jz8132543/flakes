# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/default.nix
#
# IBM ContextForge — MCP 注册中心与虚拟捆绑路由网关
#
# 定位：
#   整个服务器的 MCP (Model Context Protocol) 总线中枢：
#   • 集中注册所有 MCP Server（文件系统、数据库、API、工具等）
#   • 对外暴露 Virtual MCP 端点，供 Dify Workflow 调用
#   • 提供统一的 MCP Web 管理 UI（mcp.dora.im）
#
# 架构决策：
#   • ContextForge 核心为 Python + Next.js 混合应用，不适合 Nix 打包
#   • 使用 OCI 容器部署，但共享宿主机网络（--network=host）
#   • 数据库（PostgreSQL）使用原生 services.*
#   • 密钥通过 sops-nix 模板注入
#
# 导入方式（fra0/default.nix）：
#   imports = nixosModules.services.ai.mcp.all;
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.ai.mcp;

  # ── 连接变量（与 Dify 模块保持相同命名约定）──────────────────────
  pgHost = "127.0.0.1";
  pgPort = 5432;
  mcpPgUser = "contextforge";
  mcpPgDb = "contextforge";
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.postgres
    nixosModules.services.traefik
    # db-init.nix / containers.nix / traefik-proxy.nix 由 haumea all 聚合加载
  ];

  options.services.ai.mcp = {
    enable = lib.mkEnableOption "IBM ContextForge — MCP Registration Center & Virtual Routing Gateway";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "mcp.dora.im";
      description = "Public domain for ContextForge UI and API.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/ibm/mcp-context-forge:latest";
      description = ''
        ContextForge container image.
        IBM ContextForge 官方镜像 (GitHub Container Registry)。
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/contextforge";
      description = "Root data directory for ContextForge.";
    };
  };

  config = lib.mkMerge [
    # ── 透传连接变量给子模块（置于 mkIf 外部）────────────────────────
    {
      _module.args.mcpConnVars = {
        inherit
          pgHost
          pgPort
          mcpPgUser
          mcpPgDb
          ;
      };
    }

    # ── 主配置（受 enable 控制）──────────────────────────────────────────
    (lib.mkIf cfg.enable {
      # ── 数据目录 (容器内非 root 用户 10001:10001 需要写入权限) ──
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir}          0755 root  root  - -"
        "d ${cfg.dataDir}/config   0777 10001 10001 - -"
        "d ${cfg.dataDir}/data     0777 10001 10001 - -"
        "d ${cfg.dataDir}/logs     0777 10001 10001 - -"
      ];

      # ── 持久化 ───────────────────────────────────────────────────
      environment.global-persistence.directories = [
        cfg.dataDir
      ];

      # ── SOPS 密钥声明 ─────────────────────────────────────────────
      sops.secrets = {
        # ContextForge 应用密钥（JWT 签名、会话加密）
        "contextforge/secret_key" = { };
        # ContextForge 管理员密码（使用全局 password）
        "password" = { };
        # 可选：ContextForge 调用外部 MCP Server 所需的 API Key
        "contextforge/mcp_api_key" = { };
      };

      # ── sops template：含密文的环境文件 ──────────────────────────
      # 约束：ContextForge 强制要求 JWT_SECRET_KEY / AUTH_ENCRYPTION_SECRET >= 32 字符。
      # containers.nix 已配置 PASSWORD_POLICY_ENABLED=false 及 PASSWORD_MIN_LENGTH_PRIVILEGED=8，
      # 可直接使用 SOPS 全局主密码。
      sops.templates."contextforge-secret.env".content = ''
        JWT_SECRET_KEY=${config.sops.placeholder."contextforge/secret_key"}
        AUTH_ENCRYPTION_SECRET=${config.sops.placeholder."contextforge/secret_key"}
        PLATFORM_ADMIN_PASSWORD=${config.sops.placeholder."password"}
        DEFAULT_USER_PASSWORD=${config.sops.placeholder."password"}
        BASIC_AUTH_PASSWORD=${config.sops.placeholder."password"}
        SSO_KEYCLOAK_CLIENT_SECRET=${config.sops.placeholder."password"}
        MCP_API_KEY=${config.sops.placeholder."contextforge/mcp_api_key"}
      '';
    })
  ];
}
