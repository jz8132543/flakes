{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.derp ];
  systemd.services.derper.serviceConfig.Environment =
    lib.mkForce "HOSTNAME=ts.${config.networking.domain}";
  services = {
    headscale = {
      enable = true;
      port = config.ports.headscale;
      # group = "acme";
      settings = {
        # TODO
        server_url = "https://ts.${config.networking.domain}";
        metrics_listen_addr = "localhost:${toString config.ports.headscale_metrics}";
        grpc_listen_addr = "localhost:${toString config.ports.headscale_grpc}";
        grpc_allow_insecure = true;
        # tls_cert_path = "${config.security.acme.certs."main".directory}/full.pem";
        # tls_key_path = "${config.security.acme.certs."main".directory}/key.pem";
        database = {
          debug = true;
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
          # server = {
          #   enabled = true;
          #   region_id = 900;
          #   hostname = "ts.${config.networking.domain}";
          #   region_code = "HS";
          #   region_name = "HeadScale";
          #   stunonly = false;
          # };
        };
        policy.path = "/run/credentials/headscale.service/acl.json";
      };
    };
  };
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      headscale = {
        # rule = "Host(`ts.${config.networking.domain}`) && PathPrefix(`/`)";
        rule = "Host(`ts.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "headscale";
        # priority = 500;
      };
      # headscale_metrics = {
      #   rule = "Host(`ts.${config.networking.domain}`) && PathPrefix(`/metrics`)";
      #   entryPoints = ["https"];
      #   service = "headscale_metrics";
      # };
      # headscale_grpc = {
      #   rule = "Host(`ts.${config.networking.domain}`) && PathPrefix(`/headscale.`)";
      #   entryPoints = [ "https" ];
      #   service = "headscale_grpc";
      # };
    };
    services = {
      headscale.loadBalancer = {
        passHostHeader = true;
        # servers = [
        #   { url = "https://ts.${config.networking.domain}:${toString config.services.headscale.port}"; }
        # ];
        # servers = [ { url = "https://ts.${config.networking.domain}:${toString config.services.headscale.port}"; } ];
        servers = [ { url = "http://localhost:${toString config.services.headscale.port}"; } ];
      };
      # headscale_metrics.loadBalancer = {
      #   passHostHeader = true;
      #   servers = [{url = "http://${toString config.services.headscale.settings.metrics_listen_addr}/metrics";}];
      # };
      # headscale_grpc.loadBalancer = {
      #   passHostHeader = true;
      #   servers = [ { url = "https://:${toString config.services.headscale.settings.grpc_listen_addr}"; } ];
      #   # servers = [ { url = "https://ts.${config.networking.domain}:${toString config.services.headscale.settings.grpc_listen_addr}"; } ];
      # };
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
