{
  config,
  lib,
  self,
  pkgs,
  ...
}:
let
  domain = "dash.${config.networking.domain}";
  inherit (self) hostNames;
  hostOptions = map (name: {
    text = name;
    value = name;
    selected = false;
  }) hostNames;
  hostsDashboard =
    let
      dashboard = builtins.fromJSON (builtins.readFile ./grafana-dashboards/hosts.json);
    in
    dashboard
    // {
      templating = dashboard.templating // {
        list = [
          {
            current = {
              text = [ "All" ];
              value = [ "$__all" ];
            };
            includeAll = true;
            multi = true;
            name = "hosts";
            options = hostOptions;
            query = lib.concatStringsSep "," hostNames;
            refresh = 0;
            regex = "";
            type = "custom";
          }
        ];
      };
    };
  dashboardsDir = pkgs.runCommand "grafana-dashboards" { } ''
        mkdir -p "$out"
        cp ${./grafana-dashboards/blackbox-exporter.json} "$out/blackbox-exporter.json"
        cp ${./grafana-dashboards/infrastructure.json} "$out/infrastructure.json"
        cp ${./grafana-dashboards/node-exporter-full.json} "$out/node-exporter-full.json"
        cp ${./grafana-dashboards/postgresql.json} "$out/postgresql.json"
        cp ${./grafana-dashboards/services.json} "$out/services.json"
        cat > "$out/hosts.json" <<'EOF'
    ${builtins.toJSON hostsDashboard}
    EOF
  '';
in
{
  sops.secrets = {
    "grafana/secret_key" = {
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
      dashboards.default_home_dashboard_path = "${dashboardsDir}/hosts.json";
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
            url = "http://127.0.0.1:${toString config.ports.victoriametrics}";
            uid = "prometheus-default";
            isDefault = true;
          }
        ];
      };
      dashboards.settings.providers = [
        {
          options.path = dashboardsDir;
        }
      ];
    };
  };

  services.traefik.proxies.grafana = {
    rule = "Host(`${domain}`)";
    target = "http://localhost:${toString config.ports.grafana}";
  };
}
