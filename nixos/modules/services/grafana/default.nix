{
  config,
  pkgs,
  ...
}:
let
  domain = "dash.${config.networking.domain}";
in
{
  sops.secrets = {
    "grafana/secret_key" = {
      owner = "grafana";
    };
    "alertmanager/telegram_bot" = {
      owner = "grafana";
    };
    "password" = {
      mode = "0444";
    };
  };

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
        admin_user = "i";
        admin_email = "i@dora.im";
        secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
        admin_password = "$__file{${config.sops.secrets."password".path}}";
        cookie_secure = true;
      };
      users = {
        default_theme = "system";
        allow_sign_up = false;
      };
      "auth.anonymous".enabled = false;
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      dashboards.default_home_dashboard_path = "${./grafana-dashboards}/hosts.json";
    };

    declarativePlugins = with pkgs.grafanaPlugins; [
      grafana-piechart-panel
      grafana-clock-panel
    ];

    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "https://metrics.${config.networking.domain}";
            uid = "prometheus-default";
            isDefault = true;
          }
        ];
      };
      dashboards.settings.providers = [
        {
          options.path = ./grafana-dashboards;
        }
      ];
      alerting = {
        contactPoints.settings = {
          apiVersion = 1;
          contactPoints = [
            {
              name = "default";
              receivers = [
                {
                  uid = "telegram-default";
                  type = "telegram";
                  settings = {
                    bottoken = "$__file{${config.sops.secrets."alertmanager/telegram_bot".path}}";
                    chatid = "-5282327602";
                    parse_mode = "HTML";
                  };
                }
              ];
            }
          ];
        };
        policies.settings = {
          apiVersion = 1;
          policies = [
            {
              receiver = "default";
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "4h";
            }
          ];
        };
        rules.settings = {
          apiVersion = 1;
          groups = [
            {
              name = "default";
              folder = "alerts";
              interval = "1m";
              orgId = 1;
              rules = [
                {
                  title = "Low disk";
                  uid = "low-disk-alert";
                  notification_settings.receiver = "default";
                  annotations = {
                    summary = "{{ $labels.instance }} is low on storage";
                    description = "{{ $labels.device }} at {{ $labels.instance }} is below 10% capacity.";
                  };
                  condition = "B";
                  execErrState = "KeepLast";
                  noDataState = "KeepLast";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "prometheus-default";
                      model = {
                        refId = "A";
                        intervalMs = 1000;
                        expr = "avg by (device, instance) (node_filesystem_free_bytes / node_filesystem_size_bytes)";
                        instant = true;
                        range = false;
                        legendFormat = "__auto";
                        maxDataPoints = 43200;
                      };
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                        type = "threshold";
                        expression = "A";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        conditions = [
                          {
                            type = "query";
                            query.params = [ "B" ];
                            evaluator = {
                              type = "lt";
                              params = [ 0.1 ];
                            };
                            operator.type = "and";
                            reducer.type = "last";
                          }
                        ];
                      };
                    }
                  ];
                }
              ];
            }
          ];
        };
      };
    };
  };

  services.traefik.proxies.grafana = {
    rule = "Host(`${domain}`)";
    target = "http://localhost:${toString config.ports.grafana}";
  };
}
