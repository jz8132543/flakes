{
  config,
  nixosModules,
  ...
}:
let
  cfg = config.services.prometheus;

  # 所有云服务器目标
  targets = [
    "ams0.dora.im"
    "dfw0.dora.im"
    "hkg4.dora.im"
    "fra1.dora.im"
    "vie0.dora.im"
    "nue0.dora.im"
  ];
in
{
  imports = [
    nixosModules.services.telegraf
    nixosModules.services.ntfy
  ];

  services.prometheus = {
    enable = true;
    webExternalUrl = "https://${config.networking.fqdn}/prom";
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "30d";
    globalConfig = {
      scrape_interval = "30s";
      evaluation_interval = "30s";
    };

    scrapeConfigs = [
      # 系统指标 (通过 telegraf)
      {
        job_name = "metrics";
        scheme = "https";
        static_configs = [ { inherit targets; } ];
      }
      # Traefik 指标
      {
        job_name = "traefik";
        scheme = "https";
        metrics_path = "/traefik";
        static_configs = [ { inherit targets; } ];
      }
      # PostgreSQL exporter (本地)
      {
        job_name = "postgres";
        static_configs = [ { targets = [ "localhost:${toString config.ports.postgres-exporter}" ]; } ];
      }
      # Prometheus 自身
      {
        job_name = "prometheus";
        static_configs = [ { targets = [ "localhost:${toString cfg.port}" ]; } ];
      }
    ];

    # 告警规则
    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "node-alerts";
            rules = [
              {
                alert = "NodeDown";
                expr = "up == 0";
                for = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "🔴 节点 {{ $labels.instance }} 离线";
                  description = "{{ $labels.job }} 任务的节点已离线超过3分钟";
                };
              }
              {
                alert = "HighCPU";
                expr = "100 - (avg by(host) (cpu_usage_idle)) > 90";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "⚠️ {{ $labels.host }} CPU 高负载";
                  description = ''CPU 使用率: {{ $value | printf "%.1f" }}%'';
                };
              }
              {
                alert = "LowMemory";
                expr = "mem_available_percent < 10";
                for = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "🔴 {{ $labels.host }} 内存不足";
                  description = ''可用内存仅 {{ $value | printf "%.1f" }}%'';
                };
              }
              {
                alert = "DiskFull";
                expr = "disk_used_percent { path = '/nix' } > 85";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "⚠️ {{ $labels.host }} 磁盘空间不足";
                  description = ''磁盘 /nix 使用率: {{ $value | printf "%.1f" }}%'';
                };
              }
            ];
          }
          {
            name = "service-alerts";
            rules = [
              {
                alert = "ServiceFailed";
                expr = "systemd_units_active_code == 3";
                for = "1m";
                labels.severity = "critical";
                annotations = {
                  summary = "🔴 服务 {{ $labels.name }} 崩溃";
                  description = "节点 {{ $labels.host }} 上的服务 {{ $labels.name }} 已失败";
                };
              }
              {
                alert = "TraefikError";
                expr = "increase(traefik_config_reloads_failure_total[5m]) > 0";
                for = "1m";
                labels.severity = "warning";
                annotations = {
                  summary = "⚠️ Traefik 配置重载失败";
                  description = "节点 {{ $labels.host }} 上的 Traefik 配置重载失败";
                };
              }
              {
                alert = "DNSError";
                expr = "dns_query_result_code != 0";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "⚠️ DNS 查询失败";
                  description = "域名 {{ $labels.domain }} 在 {{ $labels.server }} 查询失败，错误码 {{ $labels.rcode }}";
                };
              }
            ];
          }
          {
            name = "postgres-alerts";
            rules = [
              {
                alert = "PostgreSQLDown";
                expr = "pg_up == 0";
                for = "1m";
                labels.severity = "critical";
                annotations = {
                  summary = "🔴 PostgreSQL 不可用";
                  description = "PostgreSQL 实例 {{ $labels.instance }} 无法连接";
                };
              }
              {
                alert = "PostgreSQLHighConnections";
                expr = "pg_stat_activity_count > 100";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "⚠️ PostgreSQL 连接数过高";
                  description = "当前连接数: {{ $value }}";
                };
              }
            ];
          }
        ];
      })
    ];

    # Alertmanager 配置
    alertmanagers = [
      {
        static_configs = [
          {
            targets = [ "localhost:${toString config.ports.alertmanager}" ];
          }
        ];
      }
    ];

    # Alertmanager 服务 (整合到 prometheus 模块)
    alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = config.ports.alertmanager;
      webExternalUrl = "https://alertmanager.${config.networking.domain}";

      configuration = {
        global.resolve_timeout = "5m";

        route = {
          receiver = "ntfy-alerts";
          group_by = [
            "alertname"
            "host"
          ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";

          routes = [
            {
              match.severity = "critical";
              receiver = "ntfy-critical";
              group_wait = "10s";
              repeat_interval = "1h";
            }
          ];
        };

        receivers = [
          {
            name = "ntfy-alerts";
            webhook_configs = [
              {
                url = "http://localhost:${toString config.ports.ntfy}/alerts";
                send_resolved = true;
                http_config.basic_auth = {
                  username = "alertmanager";
                  password_file = config.sops.secrets."alertmanager/ntfy_password".path;
                };
              }
            ];
          }
          {
            name = "ntfy-critical";
            webhook_configs = [
              {
                url = "http://localhost:${toString config.ports.ntfy}/alerts?priority=urgent&tags=warning";
                send_resolved = true;
                http_config.basic_auth = {
                  username = "alertmanager";
                  password_file = config.sops.secrets."alertmanager/ntfy_password".path;
                };
              }
            ];
          }
        ];

        inhibit_rules = [
          {
            source_match.severity = "critical";
            target_match.severity = "warning";
            equal = [
              "alertname"
              "host"
            ];
          }
        ];
      };
    };
  };

  # Alertmanager secrets
  sops.secrets."alertmanager/ntfy_password" = { };

  # Traefik 路由
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      prometheus = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/prom`)";
        entryPoints = [ "https" ];
        service = "prometheus";
      };
      alertmanager = {
        rule = "Host(`alertmanager.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "alertmanager";
        middlewares = [ "auth" ];
      };
    };
    services = {
      prometheus.loadBalancer.servers = [
        { url = "http://${cfg.listenAddress}:${builtins.toString cfg.port}"; }
      ];
      alertmanager.loadBalancer.servers = [
        { url = "http://localhost:${toString config.ports.alertmanager}"; }
      ];
    };
  };
}
