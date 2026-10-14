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
  mcpPort = config.ports.mcp-contextforge-api;
in
{
  services.traefik.proxies = {
    contextforge = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString mcpPort}";
    };
  };
}
