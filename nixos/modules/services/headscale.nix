{config, ...}: {
  services = {
    headscale = {
      enable = true;
      port = config.ports.headscale;
      settings = {
        server_url = "https://headscale.dora.im";
        metrics_listen_addr = "localhost:${toString config.ports.headscale_metrics}";
        grpc_listen_addr = "localhost:${toString config.ports.headscale_grpc}";
        grpc_allow_insecure = true;
        dns_config = {
          # override_local_dns = true;
          base_domain = "dora.im";
          magic_dns = true;
          domains = ["dora.im" "ts.dora.im" "users.dora.im"];
          nameservers = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          extra_records = [
            {
              name = "m.dora.im";
              type = "A";
              value = "100.64.0.2";
            }
            {
              name = "postgres.dora.im";
              type = "A";
              value = "100.64.0.1";
            }
          ];
        };
        logtail = {
          enabled = false;
        };
        log = {
          level = "warn";
        };
        ip_prefixes = [
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ];
        derp = {
          paths = ["/run/credentials/headscale.service/map.yaml"];
          urls = [];
        };
        # acl_policy_path = "/run/credentials/headscale.service/acl.yaml";
      };
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      headscale = {
        rule = "Host(`headscale.dora.im`) && PathPrefix(`/`)";
        entryPoints = ["https"];
        service = "headscale";
      };
      headscale_metrics = {
        rule = "Host(`headscale.dora.im`) && PathPrefix(`/metrics`)";
        entryPoints = ["https"];
        service = "headscale_metrics";
      };
      headscale_grpc = {
        rule = "Host(`headscale.dora.im`) && PathPrefix(`/headscale`)";
        entryPoints = ["https"];
        service = "headscale_grpc";
      };
    };
    services = {
      headscale.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.services.headscale.port}";}];
      };
      headscale_metrics.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://${toString config.services.headscale.settings.metrics_listen_addr}/metrics";}];
      };
      headscale_grpc.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "https://${toString config.services.headscale.settings.grpc_listen_addr}";}];
      };
    };
  };
  systemd.services.headscale.serviceConfig = {
    TimeoutStopSec = "5s";
    LoadCredential = [
      "map.yaml:/etc/headscale/map.yaml"
      "acl.yaml:/etc/headscale/acl.yaml"
    ];
  };
  environment.systemPackages = [config.services.headscale.package];
  services.restic.backups.borgbase.paths = [
    "/etc/headscale/map.yaml"
    "/etc/headscale/acl.yaml"
  ];
  environment.global-persistence = {
    directories = [
      "/etc/headscale"
    ];
  };
}
