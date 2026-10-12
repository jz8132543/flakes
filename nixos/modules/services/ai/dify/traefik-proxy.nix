# ─────────────────────────────────────────────────────────────────────────────
# services/ai/dify/traefik-proxy.nix
#
# Traefik 路由规则（Dify）
#
# 路由策略：
#   chat.dora.im          → dify-web  (Next.js, SSE 长连接)
#   chat.dora.im/api/*    → dify-api  (REST API)
#   chat.dora.im/console/api/* → dify-api
#   chat.dora.im/v1/*     → dify-api  (Service API)
#
# SSE 超时策略（防止 AI 流式回复被 Traefik 中断）：
#   • 单独为 Dify API 路由配置 respondingTimeouts >= 3600s
#   • 通过 serversTransport 自定义超时（覆盖全局 180s 默认值）
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  difyConnVars,
  ...
}:
let
  cfg = config.services.ai.dify;
  inherit (difyConnVars) apiPort webPort;
in
{
  services.traefik = {
    # ── Web 前端路由（低优先级，兜底所有 chat.dora.im 请求）──────────
    proxies.dify-web = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString webPort}";
      priority = 1; # 低优先级：被 API 路由覆盖
    };

    # ── API 路由（高优先级，精确匹配 API 路径前缀）──────────────────
    proxies.dify-api = {
      rule = "Host(`${cfg.domain}`) && (PathPrefix(`/api`) || PathPrefix(`/console/api`) || PathPrefix(`/v1`) || PathPrefix(`/files`))";
      target = "http://127.0.0.1:${toString apiPort}";
      priority = 10; # 高于 dify-web
    };
  };

  # ── 为 Dify API 创建独立的 ServersTransport（超长 SSE 超时）────────
  # Traefik 动态配置中注入自定义 transport，覆盖全局 180s
  services.traefik.dynamicConfigOptions.http = {
    serversTransports.dify-sse = {
      # SSE 流式响应：至少 3600s（1小时）不超时
      responseHeaderTimeout = "3600s";
      # 与上游保持长连接
      dialKeepAlive = "30s";
      dialTimeout = "10s";
    };

    # 为 dify-api 服务绑定自定义 transport
    services.dify-api = {
      loadBalancer = {
        servers = [ { url = "http://127.0.0.1:${toString apiPort}"; } ];
        # 绑定上面定义的 SSE-aware transport
        serversTransport = "dify-sse";
        # 禁用响应缓冲，保证 SSE 实时推送
        responseForwarding.flushInterval = "1ms";
      };
    };
  };
}
