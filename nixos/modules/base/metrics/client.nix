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
    honor_labels = true;
    static_configs = [
      {
        targets = [ "127.0.0.1:${toString config.ports.node-exporter}" ];
        labels = {
          instance = config.networking.hostName;
          host = config.networking.hostName;
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

  dn42PromScript = pkgs.writeShellScript "dn42-prom-collector" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          bash
          coreutils
          gawk
          gnugrep
          gnused
          procps
          iproute2
          bird2
          util-linux
        ]
      )
    }"

    OUT_DIR="/run/prometheus-node-exporter"
    STATE_DIR="/run/dn42-prom-state"
    mkdir -p "$OUT_DIR" "$STATE_DIR"
    chmod 755 "$OUT_DIR" "$STATE_DIR" 2>/dev/null || true
    TMP_FILE="$OUT_DIR/dn42.prom.$$"
    FINAL_FILE="$OUT_DIR/dn42.prom"

    HOST="${config.networking.hostName}"

    # 1. Detect DN42 Loopback IP
    DN42_IP=$(ip -4 -o addr show dev dummy0 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true)
    [ -z "$DN42_IP" ] && DN42_IP=$(ip -4 -o addr show dev dn42 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true)
    [ -z "$DN42_IP" ] && DN42_IP=$(ip -4 -o addr show 2>/dev/null | awk '$4 ~ /^172\.(2[0-3]|20)\./ || $4 ~ /^10\./ {split($4,a,"/"); print a[1]; exit}' || true)
    [ -z "$DN42_IP" ] && DN42_IP="N/A"

    # 2. CPU Model, Cores, Load & Usage % (state-tracked)
    CORES=$(nproc 2>/dev/null || echo 1)
    CPU_MODEL=$(awk -F': ' '/^model name|^Model|^Hardware/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed -e 's/"/\\"/g' -e 's/^[ \t]*//' || true)
    [ -z "$CPU_MODEL" ] && CPU_MODEL="$(uname -m)"
    CPU_DESC="''${CPU_MODEL} (''${CORES}C)"
    LOAD1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.0")

    read -r CPU_TOTAL CPU_IDLE < <(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null || echo "0 0")
    PREV_CPU_TOTAL=0; PREV_CPU_IDLE=0
    [ -f "$STATE_DIR/cpu" ] && read -r PREV_CPU_TOTAL PREV_CPU_IDLE < "$STATE_DIR/cpu" || true
    echo "$CPU_TOTAL $CPU_IDLE" > "$STATE_DIR/cpu" 2>/dev/null || true
    DIFF_TOTAL=$(( CPU_TOTAL - PREV_CPU_TOTAL ))
    DIFF_IDLE=$(( CPU_IDLE - PREV_CPU_IDLE ))
    if [ "$DIFF_TOTAL" -gt 0 ]; then
      CPU_PCT=$(awk -v dt="$DIFF_TOTAL" -v di="$DIFF_IDLE" 'BEGIN { pct = (1.0 - (di / dt)) * 100.0; if (pct < 0) pct = 0; if (pct > 100) pct = 100; printf "%.1f", pct }')
    else
      CPU_PCT="0.0"
    fi

    # 3. Memory Total, Used (GiB) & %
    read -r MEM_TOTAL_GIB MEM_USED_GIB MEM_PCT < <(awk '
      /^MemTotal:/ { t=$2 }
      /^MemAvailable:/ { a=$2 }
      END {
        if (t > 0) {
          u = t - a;
          printf "%.1f %.2f %.1f\n", t/1048576, u/1048576, (u/t)*100
        } else {
          print "0.0 0.0 0.0"
        }
      }
    ' /proc/meminfo 2>/dev/null || echo "0.0 0.0 0.0")

    # 4. Persistent Disk Storage (/persist or /)
    DISK_TARGET="/"
    if command -v mountpoint >/dev/null 2>&1 && mountpoint -q /persist 2>/dev/null; then
      DISK_TARGET="/persist"
    fi
    read -r DISK_TOTAL_GIB DISK_USED_GIB DISK_PCT < <(df -B1 "$DISK_TARGET" 2>/dev/null | awk 'NR==2 {
      t = $2 / 1073741824;
      u = $3 / 1073741824;
      p = ($2 > 0) ? ($3 / $2) * 100 : 0;
      printf "%.1f %.2f %.1f\n", t, u, p
    }' || echo "0.0 0.0 0.0")

    # 5. Physical Network Bandwidth Rate (Bytes/s, state-tracked)
    NOW_MS=$(date +%s%3N 2>/dev/null || date +%s000)
    read -r RX_BYTES TX_BYTES < <(awk -F'[: ]+' '
      $2 !~ /^(lo|dn42.*|xfrm.*|veth.*|docker.*|br-.*|virbr.*|podman.*|mihomo.*|tun.*|tailscale.*)$/ && $3 ~ /^[0-9]+$/ {
        rx += $3; tx += $11
      }
      END { printf "%.0f %.0f\n", rx, tx }
    ' /proc/net/dev 2>/dev/null || echo "0 0")
    PREV_MS=$NOW_MS; PREV_RX=$RX_BYTES; PREV_TX=$TX_BYTES
    [ -f "$STATE_DIR/net" ] && read -r PREV_MS PREV_RX PREV_TX < "$STATE_DIR/net" || true
    echo "$NOW_MS $RX_BYTES $TX_BYTES" > "$STATE_DIR/net" 2>/dev/null || true
    DT_MS=$(( NOW_MS - PREV_MS ))
    if [ "$DT_MS" -gt 100 ]; then
      RX_BPS=$(awk -v d="$(( RX_BYTES - PREV_RX ))" -v dt="$DT_MS" 'BEGIN { printf "%.0f", (d > 0 ? d * 1000.0 / dt : 0) }')
      TX_BPS=$(awk -v d="$(( TX_BYTES - PREV_TX ))" -v dt="$DT_MS" 'BEGIN { printf "%.0f", (d > 0 ? d * 1000.0 / dt : 0) }')
    else
      RX_BPS=0; TX_BPS=0
    fi

    # Write out Prometheus metrics atomically
    {
      echo "# HELP dn42_node_info Node hardware metadata for topology graph"
      echo "# TYPE dn42_node_info gauge"
      echo "dn42_node_info{id=\"$HOST\",title=\"$HOST\",subTitle=\"$DN42_IP\",dn42_ip=\"$DN42_IP\",cpu_model=\"$CPU_DESC\",mem_total_gib=\"''${MEM_TOTAL_GIB}\",disk_total_gib=\"''${DISK_TOTAL_GIB}\"} 1"

      echo "# HELP dn42_node_meta_info Legacy node hardware metadata for backwards compatibility"
      echo "# TYPE dn42_node_meta_info gauge"
      echo "dn42_node_meta_info{id=\"$HOST\",host=\"$HOST\",title=\"$HOST\",subTitle=\"$DN42_IP\",dn42_ip=\"$DN42_IP\",cpu_model=\"$CPU_DESC\",mem_total_gib=\"''${MEM_TOTAL_GIB} GiB\",disk_total_gib=\"''${DISK_TOTAL_GIB} GiB\"} 1"

      echo "# HELP dn42_node_cpu_percent Node CPU usage percentage"
      echo "# TYPE dn42_node_cpu_percent gauge"
      echo "dn42_node_cpu_percent{id=\"$HOST\"} $CPU_PCT"
      echo "dn42_node_cpu_usage_percent{id=\"$HOST\",host=\"$HOST\"} $CPU_PCT"

      echo "# HELP dn42_node_load1 Node 1-minute load average"
      echo "# TYPE dn42_node_load1 gauge"
      echo "dn42_node_load1{id=\"$HOST\"} $LOAD1"

      echo "# HELP dn42_node_mem_percent Node memory usage percentage"
      echo "# TYPE dn42_node_mem_percent gauge"
      echo "dn42_node_mem_percent{id=\"$HOST\"} $MEM_PCT"
      echo "dn42_node_mem_usage_percent{id=\"$HOST\",host=\"$HOST\"} $MEM_PCT"

      echo "# HELP dn42_node_mem_used_gib Node memory used in GiB"
      echo "# TYPE dn42_node_mem_used_gib gauge"
      echo "dn42_node_mem_used_gib{id=\"$HOST\",host=\"$HOST\"} $MEM_USED_GIB"

      echo "# HELP dn42_node_disk_percent Node disk usage percentage"
      echo "# TYPE dn42_node_disk_percent gauge"
      echo "dn42_node_disk_percent{id=\"$HOST\"} $DISK_PCT"
      echo "dn42_node_disk_usage_percent{id=\"$HOST\",host=\"$HOST\"} $DISK_PCT"

      echo "# HELP dn42_node_disk_used_gib Node disk used in GiB"
      echo "# TYPE dn42_node_disk_used_gib gauge"
      echo "dn42_node_disk_used_gib{id=\"$HOST\",host=\"$HOST\"} $DISK_USED_GIB"

      echo "# HELP dn42_node_net_rx_bytes_per_sec Physical network RX rate in bytes/sec"
      echo "# TYPE dn42_node_net_rx_bytes_per_sec gauge"
      echo "dn42_node_net_rx_bytes_per_sec{id=\"$HOST\"} $RX_BPS"

      echo "# HELP dn42_node_net_tx_bytes_per_sec Physical network TX rate in bytes/sec"
      echo "# TYPE dn42_node_net_tx_bytes_per_sec gauge"
      echo "dn42_node_net_tx_bytes_per_sec{id=\"$HOST\"} $TX_BPS"

      echo "# HELP dn42_edge_up Active Babel neighbor link"
      echo "# TYPE dn42_edge_up gauge"
      echo "# HELP dn42_edge_rtt_ms Babel neighbor RTT in milliseconds"
      echo "# TYPE dn42_edge_rtt_ms gauge"
      echo "# HELP dn42_edge_loss_percent Babel neighbor packet loss percentage"
      echo "# TYPE dn42_edge_loss_percent gauge"
      echo "# HELP dn42_edge_metric Babel neighbor route metric"
      echo "# TYPE dn42_edge_metric gauge"
      echo "# HELP dn42_edge_routes Babel neighbor route count"
      echo "# TYPE dn42_edge_routes gauge"

      if command -v birdc >/dev/null 2>&1 && (birdc show status >/dev/null 2>&1 || [ -S /run/bird/bird.ctl ] || [ -S /run/bird.ctl ]); then
        birdc show babel neighbors 2>/dev/null | awk -v src="$HOST" '
          $2 ~ /^dn42[xm]-/ {
            iface = $2;
            tgt = iface;
            sub(/^dn42[xm]-/, "", tgt);
            metric = ($3 ~ /^[0-9]+$/) ? $3 : 65535;
            routes = ($4 ~ /^[0-9]+$/) ? $4 : 0;
            hellos = $5;

            loss = 0.0;
            if (split(hellos, h, "/") == 2) {
              if (h[2] > 0) loss = (1.0 - (h[1] / h[2])) * 100.0;
            } else if (hellos ~ /^[0-9]+$/) {
              if (hellos < 16) loss = (1.0 - (hellos / 16.0)) * 100.0;
            }
            if (loss < 0) loss = 0.0;

            rtt = 0.0;
            for (i = NF; i >= 6; i--) {
              if ($i ~ /^[0-9]+(\.[0-9]+)?$/) {
                rtt = $i;
                break;
              }
            }

            edge_id = src "->" tgt;
            lbl = sprintf("id=\"%s\",source=\"%s\",target=\"%s\",device=\"%s\"", edge_id, src, tgt, iface);
            printf "dn42_edge_up{%s} 1\n", lbl;
            printf "dn42_edge_rtt_ms{%s} %s\n", lbl, rtt;
            printf "dn42_edge_loss_percent{%s} %.1f\n", lbl, loss;
            printf "dn42_edge_metric{%s} %s\n", lbl, metric;
            printf "dn42_edge_routes{%s} %s\n", lbl, routes;

            # Backwards compatibility metrics
            printf "dn42_babel_link_up{%s} 1\n", lbl;
            printf "dn42_babel_link_rtt_ms{%s} %s\n", lbl, rtt;
            printf "dn42_babel_link_loss_percent{%s} %.1f\n", lbl, loss;
            printf "dn42_babel_link_metric{%s} %s\n", lbl, metric;
            printf "dn42_babel_link_routes{%s} %s\n", lbl, routes;
          }
        ' || true
      fi
    } > "$TMP_FILE"

    chmod 644 "$TMP_FILE" 2>/dev/null || true
    mv -f "$TMP_FILE" "$FINAL_FILE"
    mkdir -p /etc/node-exporter-textfiles 2>/dev/null || true
    cp -f "$FINAL_FILE" /etc/node-exporter-textfiles/dn42.prom 2>/dev/null || true
  '';
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

    # 2. Setup /run/prometheus-node-exporter directory and symlink nix-registry.prom
    systemd.tmpfiles.rules = [
      "d /run/prometheus-node-exporter 0755 root root -"
      "L+ /run/prometheus-node-exporter/nix-registry.prom - - - - ${pkgs.writeText "nix-registry.prom" nixRegistryPromText}"
    ];

    # 3. Node exporter configuration based on tier
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
            "cpu"
          ];
      extraFlags = [
        "--collector.textfile.directory=/run/prometheus-node-exporter"
      ]
      ++ (
        if cfg.tier == "minimal" then
          [
            "--no-collector.cpu.info"
            "--no-collector.cpu.guest"
            "--collector.systemd.unit-include=^(sys-.*|systemd-.*|sshd|networking|tailscaled|prometheus-vmagent|vmagent).*\\.service$"
          ]
        else
          [
            "--collector.cpu.info"
          ]
      );
    };

    # 4. Pure Bash periodic collector for DN42 Babel topology and host metrics
    systemd.services.dn42-prom-collector = {
      description = "Collect DN42 Babel & Hardware Metrics for Prometheus Node Exporter";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = dn42PromScript;
      };
    };

    systemd.timers.dn42-prom-collector = {
      description = "Timer for DN42 Babel & Hardware Metrics Collector";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "15s";
        AccuracySec = "1s";
      };
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
