{
  config,
  pkgs,
  ...
}:
{
  services = {
    headscale = {
      enable = true;
      port = config.ports.headscale;
      settings = {
        # TODO
        server_url = "https://ts.dora.im";
        metrics_listen_addr = "localhost:${toString config.ports.headscale_metrics}";
        grpc_listen_addr = "localhost:${toString config.ports.headscale_grpc}";
        grpc_allow_insecure = true;
        database = {
          type = "sqlite3";
          sqlite.path = "/var/lib/headscale/db.sqlite";
        };
        dns = {
          override_local_dns = true;
          base_domain = "mag";
          magic_dns = true;
          inherit (config.environment) domains;
          nameservers.global = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          extra_records = [
            {
              name = "m.mag";
              type = "A";
              value = "100.64.0.2";
            }
            {
              name = "m-admin.mag";
              type = "A";
              value = "100.64.0.2";
            }
            {
              name = "postgres.mag";
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
        prefixes = {
          v4 = "100.64.0.0/10";
          v6 = "fd7a:115c:a1e0::/48";
        };
        derp = {
          paths = [ "/run/credentials/headscale.service/map.yaml" ];
          urls = [ ];
        };
        policy.path = "/run/credentials/headscale.service/acl.json";
      };
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      headscale = {
        rule = "Host(`ts.dora.im`) && PathPrefix(`/`)";
        entryPoints = [ "https" ];
        service = "headscale";
      };
      # headscale_metrics = {
      #   rule = "Host(`ts.dora.im`) && PathPrefix(`/metrics`)";
      #   entryPoints = ["https"];
      #   service = "headscale_metrics";
      # };
      headscale_grpc = {
        rule = "Host(`ts.dora.im`) && PathPrefix(`/headscale.`)";
        entryPoints = [ "https" ];
        service = "headscale_grpc";
      };
    };
    services = {
      headscale.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.services.headscale.port}"; } ];
        # servers = [{url = "http://localhost:${toString config.ports.headscale_metrics}";}];
      };
      # headscale_metrics.loadBalancer = {
      #   passHostHeader = true;
      #   servers = [{url = "http://${toString config.services.headscale.settings.metrics_listen_addr}/metrics";}];
      # };
      headscale_grpc.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "https://${toString config.services.headscale.settings.grpc_listen_addr}"; } ];
      };
    };
  };
  systemd.services.headscale.serviceConfig = {
    TimeoutStopSec = "5s";
    LoadCredential = [
      "map.yaml:/etc/headscale/map.yaml"
      "acl.json:/etc/headscale/acl.json"
    ];
  };
  environment.systemPackages = [
    config.services.headscale.package
    pkgs.sqlite
  ];
  services.restic.backups.borgbase.paths = [
    "/etc/headscale/map.yaml"
    "/etc/headscale/acl.json"
    "/var/lib/headscale"
  ];
  environment.global-persistence = {
    directories = [
      "/etc/headscale"
    ];
  };
}
