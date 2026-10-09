{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cluster-monitoring.client;

  # Build list of scrape targets dynamically
  nodeTarget = {
    job_name = "node";
    static_configs = [
      {
        targets = [ "127.0.0.1:${toString config.ports.node-exporter}" ];
        labels = {
          instance = config.networking.hostName;
          inherit (cfg) tier;
        };
      }
    ];
  };

  postgresTarget = lib.optional (cfg.tier == "standard" && config.services.postgresql.enable) {
    job_name = "postgres";
    static_configs = [
      {
        targets = [ "127.0.0.1:${toString config.ports.postgres-exporter}" ];
        labels = {
          instance = config.networking.hostName;
          release = "postgres-exporter";
        };
      }
    ];
  };

  redisTarget =
    lib.optional (cfg.tier == "standard" && (config.services.redis.servers or { }) != { })
      {
        job_name = "redis";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString config.ports.redis-exporter}" ];
            labels = {
              instance = config.networking.hostName;
            };
          }
        ];
      };

  synapseTarget =
    lib.optional (cfg.tier == "standard" && (config.services.matrix-synapse.enable or false))
      {
        job_name = "synapse";
        metrics_path = "/_synapse/metrics";
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString config.ports.matrix-metrics}" ];
            labels = {
              instance = config.networking.hostName;
            };
          }
        ];
      };

  traefikTarget = lib.optional (cfg.tier == "standard" && (config.services.traefik.enable or false)) {
    job_name = "traefik";
    metrics_path = "/metrics";
    static_configs = [
      {
        targets = [ "127.0.0.1:${toString config.ports.traefik-metrics}" ];
        labels = {
          instance = config.networking.hostName;
        };
      }
    ];
  };

  allScrapeConfigs = [
    nodeTarget
  ]
  ++ postgresTarget
  ++ redisTarget
  ++ synapseTarget
  ++ traefikTarget
  ++ cfg.extraScrapeTargets;

  vmagentScrapeConfig = pkgs.writeText "vmagent-promscrape.json" (
    builtins.toJSON {
      global = {
        scrape_interval = "60s";
      };
      scrape_configs = allScrapeConfigs;
    }
  );

  # Generate textfile content for nix-registry metadata
  nixRegistryPromText =
    (lib.concatMapAttrsStringSep "\n" (
      name: value:
      ''nix_registry{name="${name}",rev="${value.flake.rev or "dirty"}"} ${
        toString (value.flake.lastModified or 0)
      }''
    ) config.nix.registry)
    + "\n";
in
{
  options.services.cluster-monitoring.client = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable cluster monitoring client (node_exporter + vmagent).";
    };

    tier = lib.mkOption {
      type = lib.types.enum [
        "minimal"
        "standard"
      ];
      default = "standard";
      description = "Client monitoring tier. Minimal uses restricted collectors and lower memory limits.";
    };

    remoteWriteUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://metrics.${config.networking.domain}/api/v1/write";
      description = "VictoriaMetrics remote write URL.";
    };

    basicAuthUsername = lib.mkOption {
      type = lib.types.str;
      default = "vmagent";
      description = "Basic Auth username for vmagent remote write.";
    };

    extraScrapeTargets = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Additional scrape targets for local vmagent.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Nix registry textfile exporter for node_exporter
    environment.etc."node-exporter-textfiles/nix-registry.prom".text = nixRegistryPromText;

    # 2. Node exporter configuration based on tier
    services.prometheus.exporters.node = {
      enable = true;
      port = config.ports.node-exporter;
      listenAddress = "127.0.0.1";
      enabledCollectors =
        if cfg.tier == "minimal" then
          [
            "cpu"
            "meminfo"
            "loadavg"
            "filesystem"
            "netdev"
            "systemd"
            "textfile"
          ]
        else
          [
            "systemd"
            "textfile"
          ];
      extraFlags = [
        "--collector.textfile.directory=/etc/node-exporter-textfiles"
      ]
      ++ lib.optionals (cfg.tier == "minimal") [
        "--no-collector.cpu.info"
        "--no-collector.cpu.guest"
        "--collector.systemd.unit-include=^(sys-.*|systemd-.*|sshd|networking|tailscaled|prometheus-vmagent|vmagent).*\\.service$"
      ];
    };

    systemd.services.prometheus-node-exporter.serviceConfig = lib.mkIf (cfg.tier == "minimal") {
      MemoryMax = "40M";
    };

    # Firewall: allow access only on tailscale0 interface (for internal direct debugging)
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      config.ports.node-exporter
    ];

    # 3. Automatic service awareness (standard tier)
    services.prometheus.exporters.redis =
      lib.mkIf (cfg.tier == "standard" && (config.services.redis.servers or { }) != { })
        {
          enable = true;
          port = config.ports.redis-exporter;
          listenAddress = "127.0.0.1";
        };

    # Inject synapse metrics listener if synapse is enabled
    services.matrix-synapse.settings.listeners =
      lib.mkIf (cfg.tier == "standard" && (config.services.matrix-synapse.enable or false))
        [
          {
            bind_addresses = [ "127.0.0.1" ];
            port = config.ports.matrix-metrics;
            tls = false;
            type = "metrics";
            resources = [ ];
          }
        ];

    # 4. vmagent remote write with Basic Auth
    sops.secrets."monitoring/vmagent_password" = {
      mode = "0400";
    };

    systemd.services.prometheus-vmagent = {
      description = "Push node metrics to VictoriaMetrics with Basic Auth";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.victoriametrics}/bin/vmagent"
          "-promscrape.config=${vmagentScrapeConfig}"
          "-remoteWrite.url=${cfg.remoteWriteUrl}"
          "-remoteWrite.basicAuth.username=${cfg.basicAuthUsername}"
          "-remoteWrite.basicAuth.passwordFile=%d/vmagent_password"
          "-remoteWrite.tmpDataPath=%C/prometheus-vmagent/remote_write_tmp"
        ];
        LoadCredential = [
          "vmagent_password:${config.sops.secrets."monitoring/vmagent_password".path}"
        ];
        Restart = "always";
        RestartSec = "10s";
        DynamicUser = true;
        CacheDirectory = "prometheus-vmagent";
        StateDirectory = "prometheus-vmagent";
      };
    };
  };
}
