{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.kernel-relay;

  # ── 辅助函数：生成单个 mapping 的 DNS 解析 + nft 规则片段 ──────────
  #
  # 设计要点：
  #   1. 用 getent 解析域名，支持纯 IP 输入（直接命中）
  #   2. IPv4 / IPv6 分别解析，分别写入对应 family 的表
  #   3. 对比 /run/kernel-relay/cache/ 下的缓存文件，仅在 IP 变化时重载
  #   4. 一次性生成完整 ruleset 文件，用 nft -f 原子加载
  #
  mkResolveBlock =
    m:
    let
      label = if m.name != "" then m.name else "${m.remoteAddr}:${toString m.remotePort}";
    in
    ''
      # ── Mapping: ${label} (listen=${toString m.listenPort}) ──
      dest="${m.remoteAddr}"
      lport="${toString m.listenPort}"
      rport="${toString m.remotePort}"

      # Resolve IPv4 (if requested)
      if [[ "${m.ipFamily}" == "ipv4" || "${m.ipFamily}" == "both" ]]; then
        ip4=$(getent ahostsv4 "$dest" 2>/dev/null | head -n 1 | awk '{print $1}') || true
        if [ -n "$ip4" ] && [[ "$ip4" != 127.* ]]; then
          echo "  Found IPv4 for $dest → $ip4" >&2
          ${
            if m.protocol == "both" then
              ''
                V4_PREROUTE+="    tcp dport $lport dnat to $ip4:$rport\n"
                V4_PREROUTE+="    udp dport $lport dnat to $ip4:$rport\n"
              ''
            else
              ''
                V4_PREROUTE+="    ${m.protocol} dport $lport dnat to $ip4:$rport\n"
              ''
          }
          V4_POSTROUTE_ADDRS+="$ip4 "
          V4_RESOLVED+="$lport=$ip4:$rport "
        fi
      fi

      # Resolve IPv6 (if requested)
      if [[ "${m.ipFamily}" == "ipv6" || "${m.ipFamily}" == "both" ]]; then
        ip6=$(getent ahostsv6 "$dest" 2>/dev/null | head -n 1 | awk '{print $1}') || true
        if [ -n "$ip6" ] && [ "$ip6" != "::1" ]; then
          echo "  Found IPv6 for $dest → $ip6" >&2
          ${
            if m.protocol == "both" then
              ''
                V6_PREROUTE+="    tcp dport $lport dnat to [$ip6]:$rport\n"
                V6_PREROUTE+="    udp dport $lport dnat to [$ip6]:$rport\n"
              ''
            else
              ''
                V6_PREROUTE+="    ${m.protocol} dport $lport dnat to [$ip6]:$rport\n"
              ''
          }
          V6_POSTROUTE_ADDRS+="$ip6 "
          V6_RESOLVED+="$lport=[$ip6]:$rport "
        fi
      fi
    '';

  # ── 生成完整的 nft ruleset 脚本 ────────────────────────────────────
  relayScript = pkgs.writeShellScript "kernel-relay-update" ''
    set -euo pipefail

    CACHE_DIR="/run/kernel-relay/cache"
    RULESET_FILE="/run/kernel-relay/ruleset.nft"
    mkdir -p "$CACHE_DIR"

    # ── 收集解析结果 ──────────────────────────────────────────────
    V4_PREROUTE=""
    V4_POSTROUTE_ADDRS=""
    V4_RESOLVED=""
    V6_PREROUTE=""
    V6_POSTROUTE_ADDRS=""
    V6_RESOLVED=""

    echo "Resolving DNS for all mappings..."

    ${concatMapStringsSep "\n" mkResolveBlock cfg.mappings}

    # ── 检查是否有变化 ────────────────────────────────────────────
    CURRENT_HASH=$(echo "$V4_RESOLVED $V6_RESOLVED" | sha256sum | cut -d' ' -f1)
    CACHED_HASH=""
    [ -f "$CACHE_DIR/hash" ] && CACHED_HASH=$(cat "$CACHE_DIR/hash")

    if [ "$CURRENT_HASH" = "$CACHED_HASH" ] && [ "''${1:-}" != "--force" ]; then
      echo "No DNS changes detected, skipping reload."
      exit 0
    fi

    echo "Changes detected (or forced reload). Generating ruleset..."

    # ── 检测默认出口网卡与本地 IP (用于 SNAT 与 Flowtable) ─────────
    # 使用 SNAT 替代 Masquerade 可以减少内核在高并发下查找出口 IP 的开销
    DEFAULT_DEV=$(ip -4 route show default 2>/dev/null | head -n1 | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
    [ -z "$DEFAULT_DEV" ] && DEFAULT_DEV="eth0"

    LOCAL_IP4=$(ip -4 addr show dev "$DEFAULT_DEV" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
    LOCAL_IP6=$(ip -6 addr show dev "$DEFAULT_DEV" | awk '/inet6 / && !/fe80/ {print $2}' | cut -d/ -f1 | head -n1)

    echo "Using network device: $DEFAULT_DEV"
    echo "Local IPv4: $LOCAL_IP4, Local IPv6: $LOCAL_IP6"

    # ── 极致峰值优化：系统参数微调 ──────────────────────────────
    echo "Tuning conntrack for high-speed relay..."
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=1200 >/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close_wait=15 >/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_fin_wait=30 >/dev/null || true

    # ── 准备 NAT 规则 ──────────────────────────────────────────────
    V4_NAT_RULE=""
    if [ -n "$V4_POSTROUTE_ADDRS" ]; then
      V4_CLEAN_SET=$(echo $V4_POSTROUTE_ADDRS | xargs echo | tr ' ' ',')
      if [ -n "$LOCAL_IP4" ]; then
        V4_NAT_RULE="    ip daddr { $V4_CLEAN_SET } snat to $LOCAL_IP4"
      else
        V4_NAT_RULE="    ip daddr { $V4_CLEAN_SET } masquerade"
      fi
    fi

    V6_NAT_RULE=""
    if [ -n "$V6_POSTROUTE_ADDRS" ]; then
      V6_CLEAN_SET=$(echo $V6_POSTROUTE_ADDRS | xargs echo | tr ' ' ',')
      if [ -n "$LOCAL_IP6" ]; then
        V6_NAT_RULE="    ip6 daddr { $V6_CLEAN_SET } snat to $LOCAL_IP6"
      else
        V6_NAT_RULE="    ip6 daddr { $V6_CLEAN_SET } masquerade"
      fi
    fi

    # ── 生成 IPv4 表 ──────────────────────────────────────────────
    cat > "$RULESET_FILE" <<NFTEOF
    # Auto-generated by kernel-relay — $(date -Iseconds)
    # Do NOT edit manually.

    table ip kernel_relay
    delete table ip kernel_relay
    table ip kernel_relay {
    ${optionalString cfg.enableFlowtable ''
      flowtable ft {
        hook ingress priority -20
        devices = { $DEFAULT_DEV }
      }
    ''}

      chain forward {
        type filter hook forward priority -10; policy accept;
        # 1. 丢弃无效连接包
        ct state invalid drop
        # 2. TCP MSS Clamping
        tcp flags syn tcp option maxseg size set rt mtu
        # 3. Flowtable 加速
    ${optionalString cfg.enableFlowtable "    ct state established,related flow add @ft counter"}
      }

      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ct state invalid drop
    $(printf '%b' "$V4_PREROUTE")
      }

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        # 使用加速 NAT 规则
    $(printf '%b' "$V4_NAT_RULE")
      }
    }
    NFTEOF

    # ── 追加 IPv6 表 ──────────────────────────────────────────────
    if [ -n "$V6_PREROUTE" ]; then
    cat >> "$RULESET_FILE" <<NFT6EOF

    table ip6 kernel_relay6
    delete table ip6 kernel_relay6
    table ip6 kernel_relay6 {
    ${optionalString cfg.enableFlowtable ''
      flowtable ft6 {
        hook ingress priority -20
        devices = { $DEFAULT_DEV }
      }
    ''}

      chain forward {
        type filter hook forward priority -10; policy accept;
        ct state invalid drop
        tcp flags syn tcp option maxseg size set rt mtu
    ${optionalString cfg.enableFlowtable "    ct state established,related flow add @ft6 counter"}
      }

      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ct state invalid drop
    $(printf '%b' "$V6_PREROUTE")
      }

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        # 使用加速 NAT 规则
    $(printf '%b' "$V6_NAT_RULE")
      }
    }
    NFT6EOF
    fi

    # ── 原子加载 ──────────────────────────────────────────────────
    echo "Loading nftables ruleset..."
    if nft -f "$RULESET_FILE"; then
      echo "$CURRENT_HASH" > "$CACHE_DIR/hash"
      echo "Successfully loaded kernel-relay rules."
      echo "Resolved mappings (v4): $V4_RESOLVED"
      echo "Resolved mappings (v6): $V6_RESOLVED"
    else
      echo "ERROR: Failed to load nftables ruleset!" >&2
      cat "$RULESET_FILE" >&2
      exit 1
    fi
  '';

  # ── 清理脚本 ────────────────────────────────────────────────────
  cleanupScript = pkgs.writeShellScript "kernel-relay-cleanup" ''
    echo "Cleaning up kernel-relay nftables tables..."
    nft delete table ip kernel_relay 2>/dev/null || true
    nft delete table ip6 kernel_relay6 2>/dev/null || true
    echo "Done."
  '';
in
{
  options.services.kernel-relay = {
    enable = mkEnableOption "kernel-space NAT port forwarding via nftables (high performance)";

    mappings = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable label for this mapping (used in logs).";
            };
            listenPort = mkOption {
              type = types.port;
              description = "Local port to listen on.";
            };
            remoteAddr = mkOption {
              type = types.str;
              description = "Remote address (IP or hostname) to forward to. DNS is re-resolved periodically.";
            };
            remotePort = mkOption {
              type = types.port;
              description = "Remote port to forward to.";
            };
            protocol = mkOption {
              type = types.enum [
                "tcp"
                "udp"
                "both"
              ];
              default = "both";
              description = "Protocol(s) to forward.";
            };
            ipFamily = mkOption {
              type = types.enum [
                "ipv4"
                "ipv6"
                "both"
              ];
              default = cfg.ipFamily;
              description = "Which IP family to use for this specific mapping.";
            };
          };
        }
      );
      default = [ ];
      description = "List of port forwarding mappings.";
    };

    dnsInterval = mkOption {
      type = types.str;
      default = "3min";
      description = "How often to re-resolve DNS and check for changes.";
    };

    enableFlowtable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable nftables flowtable acceleration for established connections.
        This offloads forwarded packets from the full netfilter path,
        significantly reducing CPU overhead. Requires kernel ≥ 4.16.
        Hardware offload (if supported by NIC driver) requires ≥ 5.13.
      '';
    };

    ipFamily = mkOption {
      type = types.enum [
        "ipv4"
        "ipv6"
        "both"
      ];
      default = "both";
      description = "Default IP family for all mappings.";
    };
  };

  config = mkIf cfg.enable {
    # ── IP 转发 ───────────────────────────────────────────────────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = mkDefault 1;
      "net.ipv6.conf.all.forwarding" = mkDefault 1;
    };

    # ── 防火墙放行监听端口 ────────────────────────────────────────
    networking.firewall.allowedTCPPorts = map (m: m.listenPort) (
      filter (m: m.protocol == "tcp" || m.protocol == "both") cfg.mappings
    );
    networking.firewall.allowedUDPPorts = map (m: m.listenPort) (
      filter (m: m.protocol == "udp" || m.protocol == "both") cfg.mappings
    );

    # ── 主服务：启动时加载规则，停止时清理 ─────────────────────────
    systemd.services.kernel-relay = {
      description = "Kernel-space NAT relay via nftables";
      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        nftables
        glibc.getent
        coreutils
        gawk
        iproute2
        ethtool
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "kernel-relay";
        ExecStart = "${relayScript} --force";
        ExecStop = "${cleanupScript}";
      };
    };

    # ── DDNS 定时更新服务 ─────────────────────────────────────────
    systemd.services.kernel-relay-ddns = {
      description = "Re-resolve DNS for kernel-relay and reload if changed";
      after = [ "kernel-relay.service" ];
      requires = [ "kernel-relay.service" ];

      path = with pkgs; [
        nftables
        glibc.getent
        coreutils
        gawk
        iproute2
        ethtool
      ];

      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "kernel-relay";
        # 不传 --force，只在 DNS 变化时重载
        ExecStart = "${relayScript}";
      };
    };

    systemd.timers.kernel-relay-ddns = {
      description = "Timer for kernel-relay DNS re-resolution";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.dnsInterval;
        OnUnitActiveSec = cfg.dnsInterval;
        AccuracySec = "10s";
      };
    };
  };
}
