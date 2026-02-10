{
  config,
  ...
}:
let
  hosts = [
    "nue0"
    "hkg4"
  ];
in
{
  services = {
    prometheus = {
      enable = true;
      globalConfig = {
        scrape_interval = "30s";
      };
      exporters = {
        node = {
          enable = true;
          port = 9011;
        };
      };
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
            }
          ];
        }
        {
          job_name = "grafana";
          scheme = "https";
          static_configs = [ { targets = [ "dash.${config.networking.domain}" ]; } ];
        }
        {
          job_name = "prometheus";
          scheme = "https";
          static_configs = [ { targets = [ "metrics.${config.networking.domain}" ]; } ];
        }
        {
          job_name = "headscale";
          scheme = "https";
          metrics_path = "/metrics";
          static_configs = [ { targets = [ "ts.${config.networking.domain}" ]; } ];
        }
        {
          job_name = "traefik";
          scheme = "https";
          metrics_path = "/traefik";
          static_configs = [
            {
              targets = [
                "nue0.${config.networking.domain}"
                "hkg4.${config.networking.domain}"
                # "sso.dora.im"
                # "alist.dora.im"
                # "searx.dora.im"
                # "zone.dora.im"
                # "matrix.dora.im"
                # "vault.dora.im"
                # "grafana.dora.im"
                # "ntfy.dora.im"
                # "dora.im"
              ];
            }
          ];
        }
        {
          job_name = "hosts";
          scheme = "http";
          static_configs = map (hostname: {
            targets = [
              "${hostname}:${toString config.services.prometheus.exporters.node.port}"
              "${hostname}:${toString config.services.prometheus.exporters.nix-registry.port}"
            ];
            labels.instance = hostname;
          }) hosts;
        }
        {
          job_name = "blackbox";
          scheme = "http";
          metrics_path = "/probe";
          params.module = [ "http_2xx" ];
          static_configs = [
            {
              targets = [
                "https://ts.${config.networking.domain}"
                "https://alist.${config.networking.domain}"
                "https://m.${config.networking.domain}"
                "https://zone.${config.networking.domain}"
                "https://searx.${config.networking.domain}"
                "https://vault.${config.networking.domain}"
                "https://ntfy.${config.networking.domain}"
                "https://sso.${config.networking.domain}"
              ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "127.0.0.1:${toString config.ports.blackbox-exporter}";
            }
          ];
        }
        {
          job_name = "postgres";
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString config.ports.postgres-exporter}" ];
              labels = {
                release = "postgres-exporter";
                kubernetes_namespace = "nixos";
              };
            }
          ];
        }
      ];
      extraFlags =
        let
          prometheus = config.services.prometheus.package;
        in
        [
          "--web.console.templates=${prometheus}/etc/prometheus/consoles"
          "--web.console.libraries=${prometheus}/etc/prometheus/console_libraries"
        ];

    };
    traefik.dynamicConfigOptions.http = {
      routers.prometheus = {
        rule = "Host(`metrics.${config.networking.domain}`)";
        service = "prometheus";
        entryPoints = [ "https" ];
        priority = 99;
      };
      services.prometheus.loadBalancer.servers = [
        { url = "http://127.0.0.1:${toString config.services.prometheus.port}"; }
      ];
    };
  };
}
