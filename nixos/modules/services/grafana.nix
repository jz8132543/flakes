{
  config,
  nixosModules,
  ...
}:
let
  domain = "dashboard.${config.networking.domain}";
in
{
  imports = [ nixosModules.services.acme ];

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = config.ports.grafana;
        inherit domain;
        root_url = "https://${domain}/";
        enforce_domain = true;
      };
      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets."grafana/admin_password".path}}";
        secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
        cookie_secure = true;
      };
      users = {
        default_theme = "dark";
        allow_sign_up = false;
      };
      "auth.anonymous" = {
        enabled = false;
      };
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      feature_toggles = {
        publicDashboards = true;
      };
    };

    # 预配置数据源
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString config.services.prometheus.port}";
          isDefault = true;
          editable = false;
        }
      ];

      # 预配置 Dashboard - 使用流行且维护良好的 Dashboard
      dashboards.settings.providers = [
        {
          name = "default";
          options.path = ./grafana-dashboards;
          disableDeletion = true;
        }
      ];
    };
  };

  # Grafana secrets
  sops.secrets = {
    "grafana/admin_password" = {
      owner = "grafana";
    };
    "grafana/secret_key" = {
      owner = "grafana";
    };
  };

  # Traefik 反向代理
  services.traefik.dynamicConfigOptions.http = {
    routers.grafana = {
      rule = "Host(`${domain}`)";
      entryPoints = [ "https" ];
      service = "grafana";
    };
    services.grafana.loadBalancer = {
      passHostHeader = true;
      servers = [ { url = "http://localhost:${toString config.ports.grafana}"; } ];
    };
  };
}
