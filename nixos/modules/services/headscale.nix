{
  config,
  pkgs,
  ...
}: {
  services = {
    headscale = {
      enable = true;
      port = 8085;
      address = "127.0.0.1";
      settings = {
        server_url = "https://headscale.dora.im";
        metrics_listen_addr = "localhost:8095";
        # grpc_listen_addr = "localhost:50443";
        # grpc_allow_insecure = true;
        dns_config = {
          override_local_dns = true;
          base_domain = "dora.im";
          magic_dns = true;
          domains = ["dora.im" "ts.dora.im"];
          nameservers = [
            "9.9.9.9"
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
          urls = [""];
        };
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
    };
  };
  systemd.services.headscale.serviceConfig = {
    TimeoutStopSec = "5s";
    LoadCredential = [
      "map.yaml:/etc/headscale/map.yaml"
    ];
  };
  environment.systemPackages = [config.services.headscale.package pkgs.tailscale-derpprobe];
  environment.global-persistence = {
    directories = [
      "/etc/headscale"
    ];
  };
}
