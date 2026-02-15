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
        randomize_client_port = false;
        disable_check_updates = true;
        ephemeral_node_inactivity_timeout = "30m";
        node_update_check_interval = "10s";
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
            {
              name = "mysql.mag";
              type = "A";
              value = "100.64.0.1";
            }
            {
              name = "tv.mag";
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
  services.traefik.proxies = {
    headscale = {
      rule = "Host(`ts.${config.networking.domain}`)";
      target = "http://localhost:${toString config.services.headscale.port}";
    };
    headscale_metrics = {
      rule = "Host(`ts.${config.networking.domain}`) && PathPrefix(`/metrics`)";
      target = "http://${config.services.headscale.settings.metrics_listen_addr}";
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
