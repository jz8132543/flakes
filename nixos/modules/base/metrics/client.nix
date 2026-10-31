{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.cluster-monitoring.client;
  selfData = config.lib.self.data or (lib.importJSON ../../../../lib/data/data.json);
  dn42Node = selfData.dn42.mesh.${config.networking.hostName} or { };
  # Registry version mirrors the flake revision (git commit time), not the
  # terraform build timestamp, so it only moves on real repo changes.
  dn42BuildTime = self.lastModified or self.lastModifiedDate or 0;
  dn42NodeRole = dn42Node.role or "internal";
  dn42NodeIsController = dn42Node.is_controller or false;
  dn42NodeId =
    dn42Node.id or (lib.head (
      ((selfData.hosts.${config.networking.hostName} or { }).host_indices or [ ]) ++ [ 0 ]
    ));

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

    OUT_DIR="''${DN42_PROM_OUT_DIR:-/run/prometheus-node-exporter}"
    STATE_DIR="''${DN42_PROM_STATE_DIR:-/run/dn42-prom-state}"
    SDWAN_STATE_DIR="''${DN42_SDWAN_STATE_DIR:-/var/lib/dn42-sdwan}"
    mkdir -p "$OUT_DIR" "$STATE_DIR"
    chmod 755 "$OUT_DIR" "$STATE_DIR" 2>/dev/null || true
    TMP_FILE="$OUT_DIR/dn42.prom.$$"
    FINAL_FILE="$OUT_DIR/dn42.prom"

    HOST="${config.networking.hostName}"

    # ── 0. SD-WAN 接口 → (peer, endpoint) 映射表（由 dn42-sdwan-agent 写入） ──
    # 优先使用 agent 的真实映射；文件缺失时回退到接口名解析。
    declare -A IFACE_PEER IFACE_EP
    EDGE_LABELS_FILE="$SDWAN_STATE_DIR/edge-labels"
    if [ -f "$EDGE_LABELS_FILE" ]; then
      while IFS=$'\t' read -r m_if m_peer m_ep; do
        if [ -n "$m_if" ] && [ -n "$m_peer" ]; then
          IFACE_PEER[$m_if]="$m_peer"
          IFACE_EP[$m_if]="$m_ep"
        fi
      done < "$EDGE_LABELS_FILE"
    fi

    resolve_edge() {
      local iface="$1" tgt
      if [ -n "''${IFACE_PEER[$iface]:-}" ]; then
        echo "''${IFACE_PEER[$iface]} ''${IFACE_EP[$iface]:-$iface}"
        return 0
      fi
      tgt="''${iface#dn42?-}"
      if [[ "$tgt" == *-* ]]; then tgt="''${tgt%-*}"; fi
      echo "$tgt $tgt"
    }

    # 1. Detect DN42 Loopback IP
    DN42_IP=$(ip -4 -o addr show dev dummy0 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true)
    [ -z "$DN42_IP" ] && DN42_IP=$(ip -4 -o addr show dev dn42 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true)
    [ -z "$DN42_IP" ] && DN42_IP=$(ip -4 -o addr show 2>/dev/null | awk '$4 ~ /^172\.(2[0-3]|20)\./ || $4 ~ /^10\./ {split($4,a,"/"); print a[1]; exit}' || true)
    [ -z "$DN42_IP" ] && DN42_IP="N/A"

    # 2. CPU Model, Cores, Load & Usage % (state-tracked)
    CORES=$(nproc 2>/dev/null || echo 1)
    CPU_MODEL=$(awk -F': ' '/^model name|^Model|^Hardware/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed -e 's/^[ \t]*//' || true)
    [ -z "$CPU_MODEL" ] && CPU_MODEL="$(uname -m)"
    # Prometheus label 值转义：反斜杠与双引号
    CPU_MODEL="''${CPU_MODEL//\\/\\\\}"
    CPU_MODEL="''${CPU_MODEL//\"/\\\"}"
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

    # 5b. Per-tunnel mesh interface bandwidth rate (Bytes/s, state-tracked)
    # 为每条 dn42x-* 子链路单独记账，供拓扑图边标签展示实时吞吐。
    MESH_RX_TOTAL=0; MESH_TX_TOTAL=0
    : > "$STATE_DIR/iface-bytes.new"
    declare -A PREV_IRX PREV_ITX
    if [ -f "$STATE_DIR/iface-bytes" ]; then
      while read -r p_if p_rx p_tx; do
        [ -n "$p_if" ] && PREV_IRX[$p_if]="$p_rx" && PREV_ITX[$p_if]="$p_tx"
      done < "$STATE_DIR/iface-bytes"
    fi
    PREV_IMS=0
    [ -f "$STATE_DIR/iface-bytes.ts" ] && read -r PREV_IMS < "$STATE_DIR/iface-bytes.ts" || true
    echo "$NOW_MS" > "$STATE_DIR/iface-bytes.ts"
    EDGE_RATE_FILE="$STATE_DIR/edge-rates"
    : > "$EDGE_RATE_FILE"
    while read -r i_if i_rx i_tx; do
      [ -z "$i_if" ] && continue
      echo "$i_if $i_rx $i_tx" >> "$STATE_DIR/iface-bytes.new"
      MESH_RX_TOTAL=$(( MESH_RX_TOTAL + i_rx ))
      MESH_TX_TOTAL=$(( MESH_TX_TOTAL + i_tx ))
      p_rx="''${PREV_IRX[$i_if]:-}"
      p_tx="''${PREV_ITX[$i_if]:-}"
      if [ -n "$p_rx" ] && [ -n "$p_tx" ] && [ "$NOW_MS" -gt "$PREV_IMS" ]; then
        i_rx_bps=$(awk -v d="$(( i_rx - p_rx ))" -v dt="$(( NOW_MS - PREV_IMS ))" 'BEGIN { printf "%.0f", (d > 0 ? d * 1000.0 / dt : 0) }')
        i_tx_bps=$(awk -v d="$(( i_tx - p_tx ))" -v dt="$(( NOW_MS - PREV_IMS ))" 'BEGIN { printf "%.0f", (d > 0 ? d * 1000.0 / dt : 0) }')
        read -r e_peer e_ep <<< "$(resolve_edge "$i_if")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$i_if" "$e_peer" "$e_ep" "$i_rx_bps" "$i_tx_bps" >> "$EDGE_RATE_FILE"
      fi
    done < <(awk -F'[: ]+' '
      $2 ~ /^dn42[xm]-/ && $3 ~ /^[0-9]+$/ { printf "%s %s %s\n", $2, $3, $11 }
    ' /proc/net/dev 2>/dev/null || true)
    mv -f "$STATE_DIR/iface-bytes.new" "$STATE_DIR/iface-bytes" 2>/dev/null || true

    # Mesh 汇总速率（bytes/s）
    PREV_MESH_MS=$NOW_MS; PREV_MESH_RX=0; PREV_MESH_TX=0
    [ -f "$STATE_DIR/mesh-net" ] && read -r PREV_MESH_MS PREV_MESH_RX PREV_MESH_TX < "$STATE_DIR/mesh-net" || true
    echo "$NOW_MS $MESH_RX_TOTAL $MESH_TX_TOTAL" > "$STATE_DIR/mesh-net" 2>/dev/null || true
    if [ "$NOW_MS" -gt "$PREV_MESH_MS" ]; then
      MESH_RX_BPS=$(awk -v d="$(( MESH_RX_TOTAL - PREV_MESH_RX ))" -v dt="$(( NOW_MS - PREV_MESH_MS ))" 'BEGIN { printf "%.0f", (d > 0 ? d * 1000.0 / dt : 0) }')
      MESH_TX_BPS=$(awk -v d="$(( MESH_TX_TOTAL - PREV_MESH_TX ))" -v dt="$(( NOW_MS - PREV_MESH_MS ))" 'BEGIN { printf "%.0f", (d > 0 ? d * 1000.0 / dt : 0) }')
    else
      MESH_RX_BPS=0; MESH_TX_BPS=0
    fi

    # Write out Prometheus metrics atomically
    {
      echo "# HELP dn42_node_info Node hardware metadata for topology graph"
      echo "# TYPE dn42_node_info gauge"
      echo "dn42_node_info{id=\"$HOST\",title=\"$HOST\",subTitle=\"$DN42_IP\",dn42_ip=\"$DN42_IP\",node_id=\"${toString dn42NodeId}\",build_time=\"${toString dn42BuildTime}\",role=\"${dn42NodeRole}\",is_controller=\"${
        if dn42NodeIsController then "true" else "false"
      }\",cpu_model=\"$CPU_DESC\",mem_total_gib=\"''${MEM_TOTAL_GIB}\",disk_total_gib=\"''${DISK_TOTAL_GIB}\"} 1"

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
      echo "# HELP dn42_edge_rx_bytes_per_sec Mesh tunnel interface RX rate in bytes/sec"
      echo "# TYPE dn42_edge_rx_bytes_per_sec gauge"
      echo "# HELP dn42_edge_tx_bytes_per_sec Mesh tunnel interface TX rate in bytes/sec"
      echo "# TYPE dn42_edge_tx_bytes_per_sec gauge"
      echo "# HELP dn42_edge_speed_bytes_per_sec Mesh tunnel interface combined rate in bytes/sec"
      echo "# TYPE dn42_edge_speed_bytes_per_sec gauge"
      echo "# HELP dn42_mesh_net_rx_bytes_per_sec Aggregate mesh tunnels RX rate in bytes/sec"
      echo "# TYPE dn42_mesh_net_rx_bytes_per_sec gauge"
      echo "# HELP dn42_mesh_net_tx_bytes_per_sec Aggregate mesh tunnels TX rate in bytes/sec"
      echo "# TYPE dn42_mesh_net_tx_bytes_per_sec gauge"

      # Mesh 汇总吞吐（物理网卡之外的专网总网速）
      echo "dn42_mesh_net_rx_bytes_per_sec{id=\"$HOST\"} $MESH_RX_BPS"
      echo "dn42_mesh_net_tx_bytes_per_sec{id=\"$HOST\"} $MESH_TX_BPS"

      # 每条隧道的实时吞吐（标签与 Babel 边指标一致：source/target/device）
      if [ -s "$EDGE_RATE_FILE" ]; then
        while IFS=$'\t' read -r r_if r_peer r_ep r_rx r_tx; do
          [ -z "$r_if" ] && continue
          r_lbl="id=\"$HOST->$r_peer\",source=\"$HOST\",target=\"$r_peer\",device=\"$r_if\",endpoint=\"$r_ep\""
          echo "dn42_edge_rx_bytes_per_sec{$r_lbl} $r_rx"
          echo "dn42_edge_tx_bytes_per_sec{$r_lbl} $r_tx"
          echo "dn42_edge_speed_bytes_per_sec{$r_lbl} $(( r_rx + r_tx ))"
        done < "$EDGE_RATE_FILE"
      fi

      if command -v birdc >/dev/null 2>&1 && (birdc show status >/dev/null 2>&1 || [ -S /run/bird/bird.ctl ] || [ -S /run/bird.ctl ]); then
        birdc show babel neighbors 2>/dev/null | awk -v src="$HOST" -v mapfile="$EDGE_LABELS_FILE" '
          BEGIN {
            if (mapfile != "") {
              while ((getline ml < mapfile) > 0) {
                nf = split(ml, mf, "\t");
                if (nf >= 2 && mf[1] != "") { peer[mf[1]] = mf[2]; ep[mf[1]] = (nf >= 3 ? mf[3] : mf[1]); }
              }
              close(mapfile);
            }
          }
          $2 ~ /^dn42[xm]-/ {
            iface = $2;
            # target 归一化为对端主机名（端点后缀移除），端点保留在 endpoint 标签
            tgt = iface;
            sub(/^dn42[xm]-/, "", tgt);
            epid = tgt;
            if (iface in peer) {
              tgt = peer[iface];
              epid = ep[iface];
            } else if (tgt ~ /-/) {
              sub(/-[^-]*$/, "", tgt);
            }
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
            lbl = sprintf("id=\"%s\",source=\"%s\",target=\"%s\",device=\"%s\",endpoint=\"%s\"", edge_id, src, tgt, iface, epid);
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
            # 主机矩阵/历史趋势面板所需的默认采集器（与 dn42_node_* 文本指标互补）
            "meminfo"
            "loadavg"
            "filesystem"
            "netdev"
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
      after = [ "NetworkManager-wait-online.service" ];
      wants = [ "NetworkManager-wait-online.service" ];
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
