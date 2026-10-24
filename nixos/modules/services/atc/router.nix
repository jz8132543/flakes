{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.router;
  domain = config.networking.domain;
  data = (builtins.fromJSON (builtins.readFile ../../../../lib/data/data.json)).cdn;
  nsHosts =
    data.nsHosts or (
      if data ? nsHost then [ data.nsHost ] else (data.controlNodeNames or [ config.networking.hostName ])
    );
  primaryNsHost = head nsHosts;

  controlNode = findFirst (
    c: (if builtins.isAttrs c then c.name else c) == config.networking.hostName
  ) null (data.controlNodes or [ ]);
  controlIpv4 =
    if controlNode != null && builtins.isAttrs controlNode then (controlNode.ipv4 or null) else null;
  controlIpv6 =
    if controlNode != null && builtins.isAttrs controlNode then (controlNode.ipv6 or null) else null;

  selfNode = findFirst (n: n.name == config.networking.hostName) null data.edgeNodes;
  selfIpv4 =
    if controlIpv4 != null then
      controlIpv4
    else
      (if selfNode != null then (selfNode.ipv4 or "127.0.0.1") else "127.0.0.1");
  selfIpv6 =
    if controlIpv6 != null then
      controlIpv6
    else
      (if selfNode != null then (selfNode.ipv6 or null) else null);

  defaultGeoIpDatabase = pkgs.fetchurl {
    url = "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb";
    hash = "sha256-/+2ydRyuFv3YhoFKbISAYzyRXsE2wVgspcn8WGH3gao=";
  };

  serviceLabels = unique ((attrNames data.services) ++ (attrValues data.services));

  dynamicZonePath = "/var/lib/traffic_router/cdn.${domain}.zone";

  # ── CoreDNS 配置文件 ─────────────────────────────────────────────────────────
  corefile = pkgs.writeText "Corefile" ''
    cdn.${domain}:${toString cfg.dns.port} {
        bind ${concatStringsSep " " cfg.dns.listenAddresses}
        file ${dynamicZonePath} cdn.${domain} {
            reload 5s
        }
        errors
        ${optionalString cfg.dns.log "log"}
    }
  '';

  # ── 默认兜底 Zone 文件 ────────────────────────────────────────────────────────
  defaultZone = pkgs.writeText "cdn.${domain}.zone.default" ''
    $ORIGIN cdn.${domain}.
    $TTL ${toString cfg.dns.ttl}
    @ IN SOA ${primaryNsHost}.${domain}. admin.${domain}. (
        2026102401 ; Serial
        7200
        3600
        1209600
        ${toString cfg.dns.ttl}
    )

    ${concatMapStringsSep "\n" (h: "@ IN NS ${h}.${domain}.") nsHosts}

    ; Edge nodes (Static Fallback Pool)
    ${concatMapStringsSep "\n" (node: ''
      @ IN A ${node.ipv4}
      ${node.name} IN A ${node.ipv4}
      ${optionalString ((node.ipv6 or null) != null) ''
        @ IN AAAA ${node.ipv6}
        ${node.name} IN AAAA ${node.ipv6}
      ''}
    '') data.edgeNodes}

    ; Service labels alias to zone apex
    ${concatMapStringsSep "\n" (label: "${label} IN CNAME @") serviceLabels}
    * IN CNAME @
  '';

  # ── 动态健康选路与故障摘除脚本 ──────────────────────────────────────────────
  updateDnsScript = pkgs.writeShellScript "atc-dynamic-dns" ''
    set -euo pipefail

    ZONE_FILE="${dynamicZonePath}"
    TMP_FILE="''${ZONE_FILE}.tmp"
    CRCONFIG="/var/lib/traffic_monitor/crconfig.backup"
    EDGE_NODES_JSON='${builtins.toJSON data.edgeNodes}'
    SERVICE_LABELS='${builtins.toJSON serviceLabels}'
    TTL="${toString cfg.dns.ttl}"
    DOMAIN="${domain}"
    PRIMARY_NS="${primaryNsHost}.${domain}."
    NS_HOSTS="${concatMapStringsSep " " (h: "${h}.${domain}.") nsHosts}"

    mkdir -p "$(dirname "$ZONE_FILE")"

    # 1. 从 Traffic Monitor crconfig 获取在线边缘节点
    ONLINE_NODES=()
    if [ -s "$CRCONFIG" ]; then
      while IFS= read -r host; do
        if [ -n "$host" ] && [ "$host" != "null" ]; then
          ONLINE_NODES+=("$host")
        fi
      done < <(${pkgs.jq}/bin/jq -r '
        .contentServers // {} |
        to_entries[] |
        select(.value.status == "REPORTED" or .value.status == "ONLINE") |
        select((.value.routingDisabled // 0) == 0) |
        .key
      ' "$CRCONFIG" 2>/dev/null || true)
    fi

    # 2. 如果 TM 未完成首轮探测或无节点上报，使用全部配置节点兜底，绝不丢弃 DNS 响应
    if [ ''${#ONLINE_NODES[@]} -eq 0 ]; then
      while IFS= read -r host; do
        if [ -n "$host" ] && [ "$host" != "null" ]; then
          ONLINE_NODES+=("$host")
        fi
      done < <(echo "$EDGE_NODES_JSON" | ${pkgs.jq}/bin/jq -r '.[].name')
    fi

    # 3. 构造最新 DNS Zone 记录
    SERIAL=$(date -u +%Y%m%d%H)
    {
      echo "\$ORIGIN cdn.''${DOMAIN}."
      echo "\$TTL ''${TTL}"
      echo "@ IN SOA ''${PRIMARY_NS} admin.''${DOMAIN}. ("
      echo "    ''${SERIAL} ; Serial"
      echo "    7200"
      echo "    3600"
      echo "    1209600"
      echo "    ''${TTL}"
      echo ")"
      echo ""
      for ns in $NS_HOSTS; do
        echo "@ IN NS ''${ns}"
      done
      echo ""
      echo "; Healthy Active Edge Nodes (Managed by Traffic Monitor)"
      for node in "''${ONLINE_NODES[@]}"; do
        NODE_DATA=$(echo "$EDGE_NODES_JSON" | ${pkgs.jq}/bin/jq -c --arg n "$node" '.[] | select(.name == $n)')
        if [ -n "$NODE_DATA" ]; then
          V4=$(echo "$NODE_DATA" | ${pkgs.jq}/bin/jq -r '.ipv4 // empty')
          V6=$(echo "$NODE_DATA" | ${pkgs.jq}/bin/jq -r '.ipv6 // empty')
          WEIGHT=$(echo "$NODE_DATA" | ${pkgs.jq}/bin/jq -r '.weight // 1')

          # 性能加权展开 (高权重节点响应频次更高)
          for ((i=0; i<WEIGHT; i++)); do
            if [ -n "$V4" ]; then
              echo "@ IN A ''${V4}"
              echo "''${node} IN A ''${V4}"
            fi
            if [ -n "$V6" ]; then
              echo "@ IN AAAA ''${V6}"
              echo "''${node} IN AAAA ''${V6}"
            fi
          done
        fi
      done

      echo ""
      echo "; CDN Service Endpoints Aliases"
      while IFS= read -r label; do
        if [ -n "$label" ]; then
          echo "''${label} IN CNAME @"
        fi
      done < <(echo "$SERVICE_LABELS" | ${pkgs.jq}/bin/jq -r '.[]')
      echo "* IN CNAME @"
    } > "$TMP_FILE"

    # 原子写入，保证 CoreDNS reload 期间读到的文件完整有效
    mv -f "$TMP_FILE" "$ZONE_FILE"
    chmod 0644 "$ZONE_FILE"
  '';
in
{
  options.services.atc.router = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run Apache Traffic Control Traffic Router (CoreDNS DNS Steering Engine).";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.coredns;
      description = "CoreDNS package providing high-performance DNS steering.";
    };

    dns = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = (optional (selfIpv4 != "127.0.0.1") selfIpv4) ++ (optional (selfIpv6 != null) selfIpv6);
        defaultText = "Current host's public addresses from terraform/cdn.tf";
        description = "Public IP addresses on which Traffic Router DNS listens.";
      };

      port = mkOption {
        type = types.port;
        default = 53;
        description = "DNS listening port.";
      };

      ttl = mkOption {
        type = types.int;
        default = 30;
        description = "DNS response TTL in seconds for fast failover.";
      };

      log = mkOption {
        type = types.bool;
        default = false;
        description = "Enable CoreDNS query logging.";
      };
    };

    geoip = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Load MaxMind GeoIP2 database.";
      };

      databaseFile = mkOption {
        type = types.path;
        default = defaultGeoIpDatabase;
        description = "Path to GeoLite2 City database.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = controlNode != null || selfNode != null;
        message = "services.atc.router: networking.hostName must be present in controlNodes or cdn_edge_nodes.";
      }
      {
        assertion = all (
          h:
          any (n: (if builtins.isAttrs n then n.name else n) == h) (
            (data.controlNodes or [ ]) ++ (data.edgeNodes or [ ])
          )
        ) nsHosts;
        message = "services.atc.router: all cdn.nsHosts entries must be present in controlNodes or cdn_edge_nodes.";
      }
    ];

    networking.firewall.allowedUDPPorts = [ cfg.dns.port ];
    networking.firewall.allowedTCPPorts = [ cfg.dns.port ];

    users.users.trafficrouter = {
      isSystemUser = true;
      group = "trafficrouter";
      description = "Apache Traffic Router daemon user";
      extraGroups = [ "trafficops" ];
    };
    users.groups.trafficrouter = { };

    systemd.tmpfiles.rules = [
      "d /etc/traffic_router 0750 trafficrouter trafficrouter -"
      "d /var/lib/traffic_router 0755 trafficrouter trafficrouter -"
    ];

    environment.etc."traffic_router/Corefile".source = corefile;

    # ── Traffic Router 服务 (CoreDNS 智能调度引擎) ───────────────────────────
    systemd.services.traffic-router = {
      description = "Apache Traffic Control Traffic Router (CoreDNS Steering Engine)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        mkdir -p /var/lib/traffic_router
        if [ ! -f "${dynamicZonePath}" ]; then
          cp -f "${defaultZone}" "${dynamicZonePath}"
          chmod 0644 "${dynamicZonePath}"
        fi
      '';
      serviceConfig = {
        Type = "simple";
        User = "trafficrouter";
        Group = "trafficrouter";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        Restart = "on-failure";
        RestartSec = "5s";
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
        MemoryMax = "128M";
        LimitNOFILE = 65536;
        ExecStart = "${cfg.package}/bin/coredns -conf /etc/traffic_router/Corefile";
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
      };
      restartTriggers = [ corefile ];
    };

    # ── 动态健康选路定时同步服务 ─────────────────────────────────────────────
    # 定期读取 Traffic Monitor 的健康检查产物 /var/lib/traffic_monitor/crconfig.backup，
    # 自动摘除异常/离线节点，CoreDNS 5 秒内热重载生效。
    systemd.services.atc-dynamic-dns = {
      description = "ATC Dynamic DNS Health & Steering Sync";
      after = [
        "network-online.target"
        "traffic-router.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "trafficrouter";
        Group = "trafficrouter";
        ExecStart = "${updateDnsScript}";
      };
    };

    systemd.timers.atc-dynamic-dns = {
      description = "Periodic timer for ATC dynamic DNS health sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5s";
        OnUnitActiveSec = "10s";
        RandomizedDelaySec = "2s";
      };
    };
  };
}
