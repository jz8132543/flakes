{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.kernel-relay;

  tcpMappings = filter (m: m.protocol == "tcp" || m.protocol == "both") cfg.mappings;
  udpMappings = filter (m: m.protocol == "udp" || m.protocol == "both") cfg.mappings;

  mkMapName =
    m:
    strings.sanitizeDerivationName (
      if m.name != "" then m.name else "${m.remoteAddr}-${toString m.listenPort}"
    );

  renderTcpBlock =
    m:
    let
      safeName = mkMapName m;
    in
    ''
            map_name=${escapeShellArg safeName}
            remote_addr=${escapeShellArg m.remoteAddr}
            listen_port=${toString m.listenPort}
            remote_port=${toString m.remotePort}
            ip_family=${escapeShellArg m.ipFamily}
            cache_file="$CACHE_DIR/$map_name.addr"
            resolved_ip=""
            resolved_family=""

            if [ "$ip_family" = "ipv4" ] || [ "$ip_family" = "both" ]; then
              resolved_ip=$(getent ahostsv4 "$remote_addr" 2>/dev/null | awk 'NR==1 {print $1}') || true
              [ -n "$resolved_ip" ] && resolved_family="ipv4"
            fi

            if [ -z "$resolved_ip" ] && { [ "$ip_family" = "ipv6" ] || [ "$ip_family" = "both" ]; }; then
              resolved_ip=$(getent ahostsv6 "$remote_addr" 2>/dev/null | awk 'NR==1 {print $1}') || true
              [ -n "$resolved_ip" ] && resolved_family="ipv6"
            fi

            if [ -z "$resolved_ip" ] && [ -f "$cache_file" ]; then
              resolved_ip=$(cat "$cache_file")
              case "$resolved_ip" in
                *:*) resolved_family="ipv6" ;;
                *) resolved_family="ipv4" ;;
              esac
              echo "Using cached IP for $map_name -> $resolved_ip" >&2
            fi

            if [ -z "$resolved_ip" ]; then
              echo "Failed to resolve $remote_addr for $map_name" >&2
              unresolved=1
            else
              printf '%s\n' "$resolved_ip" > "$cache_file.new"
              mv "$cache_file.new" "$cache_file"

              bind_addr="0.0.0.0"
              bind_opts=""
              server_addr="$resolved_ip"
              if [ "$ip_family" = "ipv6" ] || { [ "$ip_family" = "both" ] && [ "$resolved_family" = "ipv6" ]; }; then
                bind_addr="[::]"
                bind_opts=" v4v6"
                server_addr="[$resolved_ip]"
              fi

              cat >> "$HAPROXY_TMP" <<EOF
      listen kr_${safeName}
        bind ''${bind_addr}:''${listen_port}''${bind_opts}
        mode tcp
        option tcplog
        option dontlognull
        option redispatch
        option tcpka
        option clitcpka
        option srvtcpka
        ${optionalString cfg.haproxy.useSplice "option splice-auto"}
        timeout connect ${cfg.haproxy.timeoutConnect}
        timeout client ${cfg.haproxy.timeoutClient}
        timeout server ${cfg.haproxy.timeoutServer}
        timeout client-fin ${cfg.haproxy.timeoutFin}
        timeout server-fin ${cfg.haproxy.timeoutFin}
        timeout tunnel ${cfg.haproxy.timeoutTunnel}
        retries ${toString cfg.haproxy.retries}
        server s1 ''${server_addr}:''${remote_port}
      EOF
            fi
    '';

  renderUdpBlock =
    m:
    let
      safeName = mkMapName m;
    in
    ''
      map_name=${escapeShellArg safeName}
      remote_addr=${escapeShellArg m.remoteAddr}
      listen_port=${toString m.listenPort}
      remote_port=${toString m.remotePort}
      ip_family=${escapeShellArg m.ipFamily}
      cache_file="$CACHE_DIR/$map_name.addr"
      resolved_ip=""
      resolved_family=""

      if [ "$ip_family" = "ipv4" ] || [ "$ip_family" = "both" ]; then
        resolved_ip=$(getent ahostsv4 "$remote_addr" 2>/dev/null | awk 'NR==1 {print $1}') || true
        [ -n "$resolved_ip" ] && resolved_family="ipv4"
      fi

      if [ -z "$resolved_ip" ] && { [ "$ip_family" = "ipv6" ] || [ "$ip_family" = "both" ]; }; then
        resolved_ip=$(getent ahostsv6 "$remote_addr" 2>/dev/null | awk 'NR==1 {print $1}') || true
        [ -n "$resolved_ip" ] && resolved_family="ipv6"
      fi

      if [ -z "$resolved_ip" ] && [ -f "$cache_file" ]; then
        resolved_ip=$(cat "$cache_file")
        case "$resolved_ip" in
          *:*) resolved_family="ipv6" ;;
          *) resolved_family="ipv4" ;;
        esac
        echo "Using cached IP for UDP $map_name -> $resolved_ip" >&2
      fi

      if [ -z "$resolved_ip" ]; then
        echo "Failed to resolve UDP target $remote_addr for $map_name" >&2
        unresolved=1
      else
        printf '%s\n' "$resolved_ip" > "$cache_file.new"
        mv "$cache_file.new" "$cache_file"

        if [ "$resolved_family" = "ipv4" ]; then
          V4_UDP_ADDRS+="$resolved_ip "
          ${
            if m.protocol == "both" then
              ''
                V4_UDP_PREROUTE+="    udp dport $listen_port dnat to $resolved_ip:$remote_port\n"
              ''
            else
              ''
                V4_UDP_PREROUTE+="    ${m.protocol} dport $listen_port dnat to $resolved_ip:$remote_port\n"
              ''
          }
        else
          V6_UDP_ADDRS+="$resolved_ip "
          ${
            if m.protocol == "both" then
              ''
                V6_UDP_PREROUTE+="    udp dport $listen_port dnat to [$resolved_ip]:$remote_port\n"
              ''
            else
              ''
                V6_UDP_PREROUTE+="    ${m.protocol} dport $listen_port dnat to [$resolved_ip]:$remote_port\n"
              ''
          }
        fi
      fi
    '';

  reloadScript = pkgs.writeShellScript "kernel-relay-haproxy-reload" ''
    set -euo pipefail
    pidfile="/run/kernel-relay/haproxy.pid"
    old_pids=""
    if [ -f "$pidfile" ]; then
      old_pids=$(cat "$pidfile" || true)
    fi

    if [ -z "$old_pids" ]; then
      exit 0
    fi

    exec ${pkgs.haproxy}/bin/haproxy -W -db -f /run/kernel-relay/haproxy.cfg -p "$pidfile" -sf $old_pids
  '';

  relayScript = pkgs.writeShellScript "kernel-relay-update" ''
        set -euo pipefail

        CACHE_DIR="/run/kernel-relay/cache"
        HAPROXY_FILE="/run/kernel-relay/haproxy.cfg"
        HAPROXY_TMP="/run/kernel-relay/haproxy.cfg.new"
        HAPROXY_PID="/run/kernel-relay/haproxy.pid"
        HAPROXY_HASH_FILE="$CACHE_DIR/hash"
        NFT_FILE="/run/kernel-relay/udp.nft"
        NFT_TMP="/run/kernel-relay/udp.nft.new"
        mkdir -p "$CACHE_DIR"
        rm -f "$HAPROXY_TMP" "$NFT_TMP"

        force=0
        reload=0
        for arg in "''${@:-}"; do
          case "$arg" in
            --force) force=1 ;;
            --reload) reload=1 ;;
          esac
        done

        unresolved=0
        V4_UDP_PREROUTE=""
        V4_UDP_ADDRS=""
        V6_UDP_PREROUTE=""
        V6_UDP_ADDRS=""

        cat > "$HAPROXY_TMP" <<EOF
    global
      log stdout format raw local0
      master-worker
      maxconn ${toString cfg.haproxy.maxConn}
      nbthread ${toString cfg.haproxy.nbThreads}
      stats socket /run/kernel-relay/haproxy.sock mode 660 level admin expose-fd listeners
      tune.bufsize ${toString cfg.haproxy.bufsize}

    defaults
      mode tcp
      log global
      option tcplog
      option dontlognull
      option redispatch
      option tcpka
      option clitcpka
      option srvtcpka
    ${optionalString cfg.haproxy.useSplice "  option splice-auto"}
      timeout connect ${cfg.haproxy.timeoutConnect}
      timeout client ${cfg.haproxy.timeoutClient}
      timeout server ${cfg.haproxy.timeoutServer}
      timeout tunnel ${cfg.haproxy.timeoutTunnel}
      timeout client-fin ${cfg.haproxy.timeoutFin}
      timeout server-fin ${cfg.haproxy.timeoutFin}
      retries ${toString cfg.haproxy.retries}
    EOF

        ${concatMapStringsSep "\n" renderTcpBlock tcpMappings}

        if [ "${cfg.udpFallback}" = "nftables" ] && [ ${toString (builtins.length udpMappings)} -gt 0 ]; then
          ${concatMapStringsSep "\n" renderUdpBlock udpMappings}
        fi

        if [ "$unresolved" -ne 0 ]; then
          echo "At least one mapping could not be resolved." >&2
          if [ "$force" -eq 1 ]; then
            exit 1
          fi
          rm -f "$HAPROXY_TMP" "$NFT_TMP"
          exit 0
        fi

        # Validate haproxy config before touching the live files.
        if ! ${pkgs.haproxy}/bin/haproxy -c -f "$HAPROXY_TMP" >/dev/null 2>&1; then
          echo "ERROR: haproxy config validation failed." >&2
          cat "$HAPROXY_TMP" >&2
          exit 1
        fi

        DEFAULT_DEV=$(ip -4 route show default 2>/dev/null | head -n1 | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
        [ -z "$DEFAULT_DEV" ] && DEFAULT_DEV="eth0"
        LOCAL_IP4=$(ip -4 addr show dev "$DEFAULT_DEV" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
        LOCAL_IP6=$(ip -6 addr show dev "$DEFAULT_DEV" | awk '/inet6 / && !/fe80/ {print $2}' | cut -d/ -f1 | head -n1)

        V4_NAT_RULE=""
        if [ -n "$V4_UDP_ADDRS" ]; then
          V4_CLEAN_SET=$(echo "$V4_UDP_ADDRS" | xargs echo | tr ' ' ',')
          if [ -n "$LOCAL_IP4" ]; then
            V4_NAT_RULE="    ip daddr { $V4_CLEAN_SET } snat to $LOCAL_IP4"
          else
            V4_NAT_RULE="    ip daddr { $V4_CLEAN_SET } masquerade"
          fi
        fi

        V6_NAT_RULE=""
        if [ -n "$V6_UDP_ADDRS" ]; then
          V6_CLEAN_SET=$(echo "$V6_UDP_ADDRS" | xargs echo | tr ' ' ',')
          if [ -n "$LOCAL_IP6" ]; then
            V6_NAT_RULE="    ip6 daddr { $V6_CLEAN_SET } snat to $LOCAL_IP6"
          else
            V6_NAT_RULE="    ip6 daddr { $V6_CLEAN_SET } masquerade"
          fi
        fi

        # Generate UDP fallback rules only when needed.
        if [ -n "$V4_UDP_PREROUTE" ] || [ -n "$V6_UDP_PREROUTE" ]; then
          cat > "$NFT_TMP" <<NFTEOF
    table ip kernel_relay_udp
    delete table ip kernel_relay_udp
    table ip kernel_relay_udp {
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ct state invalid drop
    $(printf '%b' "$V4_UDP_PREROUTE")
      }

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
    $(printf '%b' "$V4_NAT_RULE")
      }
    }
    NFTEOF

          if [ -n "$V6_UDP_PREROUTE" ]; then
            cat >> "$NFT_TMP" <<NFT6EOF

    table ip6 kernel_relay_udp6
    delete table ip6 kernel_relay_udp6
    table ip6 kernel_relay_udp6 {
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ct state invalid drop
    $(printf '%b' "$V6_UDP_PREROUTE")
      }

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
    $(printf '%b' "$V6_NAT_RULE")
      }
    }
    NFT6EOF
          fi

          if ! nft -c -f "$NFT_TMP" >/dev/null 2>&1; then
            echo "ERROR: nftables UDP fallback validation failed." >&2
            cat "$NFT_TMP" >&2
            exit 1
          fi
        fi

        NEW_HASH="$(
          {
            sha256sum "$HAPROXY_TMP"
            [ -f "$NFT_TMP" ] && sha256sum "$NFT_TMP"
          } | sha256sum | awk '{print $1}'
        )"
        OLD_HASH=""
        [ -f "$HAPROXY_HASH_FILE" ] && OLD_HASH=$(cat "$HAPROXY_HASH_FILE")

        if [ "$NEW_HASH" = "$OLD_HASH" ] && [ "$force" -eq 0 ]; then
          echo "No relay config changes detected, skipping reload."
          rm -f "$HAPROXY_TMP" "$NFT_TMP"
          exit 0
        fi

        mv "$HAPROXY_TMP" "$HAPROXY_FILE"
        if [ -f "$NFT_TMP" ]; then
          nft -f "$NFT_TMP"
          mv "$NFT_TMP" "$NFT_FILE"
        else
          nft delete table ip kernel_relay_udp 2>/dev/null || true
          nft delete table ip6 kernel_relay_udp6 2>/dev/null || true
          rm -f "$NFT_FILE"
        fi

        printf '%s\n' "$NEW_HASH" > "$HAPROXY_HASH_FILE"

        if [ "$reload" -eq 1 ]; then
          ${pkgs.systemd}/bin/systemctl reload kernel-relay.service
        fi
  '';

  cleanupScript = pkgs.writeShellScript "kernel-relay-cleanup" ''
    nft delete table ip kernel_relay_udp 2>/dev/null || true
    nft delete table ip6 kernel_relay_udp6 2>/dev/null || true
    rm -f /run/kernel-relay/udp.nft /run/kernel-relay/haproxy.cfg /run/kernel-relay/haproxy.cfg.new
    echo "Done."
  '';
in
{
  options.services.kernel-relay = {
    enable = mkEnableOption "TCP relay via haproxy with optional nftables UDP fallback";

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
        Enable nftables flowtable acceleration for established UDP fallback flows.
        This only affects the optional nftables UDP path, not the haproxy TCP path.
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

    udpFallback = mkOption {
      type = types.enum [
        "nftables"
        "none"
      ];
      default = "nftables";
      description = "How to handle UDP mappings when using the haproxy relay backend.";
    };

    haproxy = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable the haproxy TCP relay backend.";
          };

          nbThreads = mkOption {
            type = types.ints.positive;
            default = 1;
            description = "Number of haproxy worker threads.";
          };

          maxConn = mkOption {
            type = types.ints.positive;
            default = 32768;
            description = "haproxy maxconn.";
          };

          bufsize = mkOption {
            type = types.ints.positive;
            default = 32768;
            description = "haproxy tune.bufsize.";
          };

          timeoutConnect = mkOption {
            type = types.str;
            default = "10s";
          };

          timeoutClient = mkOption {
            type = types.str;
            default = "1h";
          };

          timeoutServer = mkOption {
            type = types.str;
            default = "1h";
          };

          timeoutTunnel = mkOption {
            type = types.str;
            default = "1h";
          };

          timeoutFin = mkOption {
            type = types.str;
            default = "30s";
          };

          retries = mkOption {
            type = types.ints.positive;
            default = 3;
          };

          useSplice = mkOption {
            type = types.bool;
            default = true;
            description = "Enable haproxy splice acceleration when available.";
          };
        };
      };
      default = { };
      description = "haproxy relay tuning options.";
    };
  };

  config = mkIf (cfg.enable && cfg.haproxy.enable) {
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = mkDefault 1;
      "net.ipv6.conf.all.forwarding" = mkDefault 1;
      "net.ipv4.tcp_keepalive_time" = mkDefault 60;
      "net.ipv4.tcp_keepalive_intvl" = mkDefault 10;
      "net.ipv4.tcp_keepalive_probes" = mkDefault 5;
      "net.ipv4.tcp_mtu_probing" = mkDefault 1;
    };

    networking.firewall.allowedTCPPorts = map (m: m.listenPort) tcpMappings;
    networking.firewall.allowedUDPPorts = map (m: m.listenPort) udpMappings;

    systemd.services.kernel-relay = {
      description = "TCP relay via haproxy with UDP nftables fallback";
      after = [
        "network-online.target"
      ]
      ++ optionals (cfg.udpFallback == "nftables") [ "nftables.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        haproxy
        nftables
        glibc.getent
        coreutils
        gawk
        iproute2
        systemd
      ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "2s";
        RuntimeDirectory = "kernel-relay";
        LimitNOFILE = toString (cfg.haproxy.maxConn * 4);
        ExecStartPre = "${relayScript} --force";
        ExecStart = "${pkgs.haproxy}/bin/haproxy -W -db -f /run/kernel-relay/haproxy.cfg -p /run/kernel-relay/haproxy.pid";
        ExecReload = "${reloadScript}";
        ExecStopPost = "${cleanupScript}";
      };
    };

    systemd.services.kernel-relay-ddns = {
      description = "Re-resolve DNS for kernel-relay and reload if changed";
      after = [ "kernel-relay.service" ];
      requires = [ "kernel-relay.service" ];

      path = with pkgs; [
        haproxy
        nftables
        glibc.getent
        coreutils
        gawk
        iproute2
        systemd
      ];

      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "kernel-relay";
        ExecStart = "${relayScript} --reload";
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
