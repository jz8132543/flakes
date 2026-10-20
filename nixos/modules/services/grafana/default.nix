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

  # dn42-topology.json 与 hosts.json 共用同一份 Material ECharts 拓扑面板（视图 A），
  # 在此从 hosts.json 单一数据源注入，避免两份 JSON 重复维护；
  # nodeGraph（视图 B）保留 JSON 原生的 Layered/Force/Grid 布局能力。
  topologyDashboard =
    let
      base = builtins.fromJSON (builtins.readFile ./grafana-dashboards/dn42-topology.json);
      echartsPanel =
        let
          sourcePanels =
            (builtins.fromJSON (builtins.readFile ./grafana-dashboards/hosts.json)).panels or [ ];
          found = lib.findFirst (p: (p.type or "") == "volkovlabs-echarts-panel") null sourcePanels;
        in
        if found == null then
          null
        else
          found
          // {
            id = 301;
            gridPos = {
              h = 16;
              w = 24;
              x = 0;
              y = 23;
            };
          };
      # 将 nodeGraph (y=5..23) 之后的面板整体下移 16 行，为 ECharts 视图腾出空间
      shiftedPanels =
        if echartsPanel == null then
          base.panels
        else
          map (
            p:
            if (p.gridPos.y or 0) >= 23 then
              p
              // {
                gridPos = (p.gridPos or { }) // {
                  y = (p.gridPos.y or 0) + 16;
                };
              }
            else
              p
          ) base.panels;
    in
    base
    // {
      panels = shiftedPanels ++ lib.optionals (echartsPanel != null) [ echartsPanel ];
    };
  dashboardsDir = pkgs.runCommand "grafana-dashboards" { } ''
        mkdir -p "$out"
        cp ${./grafana-dashboards/blackbox-exporter.json} "$out/blackbox-exporter.json"
        cat > "$out/dn42-topology.json" <<'EOF'
    ${builtins.toJSON topologyDashboard}
    EOF
        cp ${./grafana-dashboards/infrastructure.json} "$out/infrastructure.json"
        cp ${./grafana-dashboards/node-exporter-full.json} "$out/node-exporter-full.json"
        cp ${./grafana-dashboards/postgresql.json} "$out/postgresql.json"
        cp ${./grafana-dashboards/services.json} "$out/services.json"
        cp ${./grafana-dashboards/traefik.json} "$out/traefik.json"
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
      prometheus
      grafana-piechart-panel
      grafana-clock-panel
      volkovlabs-echarts-panel
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
