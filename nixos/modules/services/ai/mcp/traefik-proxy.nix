# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/traefik-proxy.nix
#
# Traefik 路由规则（IBM ContextForge）
#
# 路由：
#   mcp.dora.im        → ContextForge Web UI（管理面板）
#   mcp.dora.im/api/*  → ContextForge REST API
#   mcp.dora.im/mcp/*  → Virtual MCP 端点（供 Dify 调用）
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  ...
}:
let
  cfg = config.services.ai.mcp;
  mcpApiPort = config.ports.mcp-contextforge-api;
  mcpUiPort = config.ports.mcp-contextforge-ui;
in
{
  services.traefik.proxies = {
    # ── UI 路由（低优先级兜底）────────────────────────────────────
    contextforge-ui = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString mcpUiPort}";
      priority = 1;
    };

    # ── API/MCP 路由（高优先级，精确前缀匹配）────────────────────
    contextforge-api = {
      rule = "Host(`${cfg.domain}`) && (PathPrefix(`/api`) || PathPrefix(`/mcp`) || PathPrefix(`/v1`))";
      target = "http://127.0.0.1:${toString mcpApiPort}";
      priority = 10;
    };
  };
}
