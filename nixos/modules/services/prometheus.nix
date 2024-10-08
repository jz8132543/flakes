{
  config,
  nixosModules,
  ...
}:
let
  cfg = config.services.prometheus;
  targets = [
    "hydra.dora.im"
    "fra0.dora.im"
    "ams0.dora.im"
    "dfw0.dora.im"
  ];
in
{
  imports = [
    nixosModules.services.telegraf
  ];
  services.prometheus = {
    enable = true;
    webExternalUrl = "https://${config.networking.fqdn}/prom";
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "7d";
    globalConfig = {
      scrape_interval = "1m";
      evaluation_interval = "1m";
    };
    scrapeConfigs = [
      {
        job_name = "metrics";
        scheme = "https";
        static_configs = [ { inherit targets; } ];
      }
      {
        job_name = "traefik";
        scheme = "https";
        metrics_path = "/traefik";
        static_configs = [ { inherit targets; } ];
      }
    ];
    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "metrics";
            rules = [
              {
                alert = "NodeDown";
                expr = "up == 0";
                for = "3m";
                annotations = {
                  summary = "node {{ $labels.host }} down for job {{ $labels.job }}";
                };
              }
              {
                alert = "UnitFailed";
                expr = "systemd_units_active_code == 3";
                for = "1m";
                annotations = {
                  summary = "unit {{ $labels.name }} on {{ $labels.host }} failed";
                };
              }
              {
                alert = "DNSError";
                expr = "dns_query_result_code != 0";
                for = "5m";
                annotations = {
                  summary = "dns query for {{ $labels.domain }} IN {{ $labels.record_type }} on {{ $labels.host }} via {{ $labels.server }} failed with rcode {{ $labels.rcode }}";
                };
              }
              {
                alert = "OOM";
                expr = "mem_available_percent < 20";
                annotations = {
                  summary = ''node {{ $labels.host }} low in memory, {{ $value | printf "%.2f" }} percent available'';
                };
              }
              {
                alert = "DiskFull";
                expr = "disk_used_percent { path = '/nix' } > 80";
                annotations = {
                  summary = ''node {{ $labels.host }} disk full, {{ $value | printf "%.2f" }} percent used'';
                };
              }
              {
                alert = "TraefikError";
                expr = "traefik_config_reloads_failure_total > 0";
                annotations = {
                  summary = "traefik on node {{ $labels.host }} failed to reload config";
                };
              }
            ];
          }
        ];
      })
    ];
    alertmanagers = [
      {
        static_configs = [
          {
            targets = [ "127.0.0.1:8009" ];
          }
        ];
      }
    ];
  };

  services.traefik = {
    dynamicConfigOptions = {
      http = {
        routers = {
          prometheus = {
            rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/prom`)";
            entryPoints = [ "https" ];
            service = "prometheus";
          };
        };
        services = {
          prometheus.loadBalancer.servers = [
            {
              url = "http://${cfg.listenAddress}:${builtins.toString cfg.port}";
            }
          ];
        };
      };
    };
  };
}
