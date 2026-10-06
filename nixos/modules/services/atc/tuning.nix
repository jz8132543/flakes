{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.atc.tuning;
in
{
  options.services.atc.tuning = {
    enable = mkEnableOption "Aggressive BBR and loss-tolerant kernel network tuning for ATC center node";

    maxBufferBytes = mkOption {
      type = types.int;
      default = 67108864; # 64 MiB
      description = "Maximum TCP socket buffer size in bytes for high-BDP lossy links.";
    };

    clampMssInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional interface name to clamp TCP MSS (leave null for standard 1500-MTU paths).";
    };

    clampMss = mkOption {
      type = types.int;
      default = 1240;
      description = "Target MSS value when clamping is enabled.";
    };
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl = {
      # 1. Queuing discipline & congestion control: FQ + BBR
      "net.core.default_qdisc" = mkDefault "fq";
      "net.ipv4.tcp_congestion_control" = mkDefault "bbr";

      # 2. Socket buffer sizes for long-distance, high-BDP international links
      "net.core.rmem_max" = mkDefault cfg.maxBufferBytes;
      "net.core.wmem_max" = mkDefault cfg.maxBufferBytes;
      "net.ipv4.tcp_rmem" = mkDefault "4096 87380 ${toString cfg.maxBufferBytes}";
      "net.ipv4.tcp_wmem" = mkDefault "4096 65536 ${toString cfg.maxBufferBytes}";
      "net.core.rmem_default" = mkDefault 262144;
      "net.core.wmem_default" = mkDefault 262144;

      # 3. TCP window scaling (RFC 1323) and timestamps
      "net.ipv4.tcp_window_scaling" = mkDefault 1;
      "net.ipv4.tcp_timestamps" = mkDefault 1;

      # 4. Loss recovery: SACK + DSACK + RACK (RFC 8985) + TLP
      "net.ipv4.tcp_sack" = mkDefault 1;
      "net.ipv4.tcp_dsack" = mkDefault 1;
      "net.ipv4.tcp_recovery" = mkDefault 1; # RACK
      "net.ipv4.tcp_early_retrans" = mkDefault 3; # TLP
      "net.ipv4.tcp_reordering" = mkDefault 3;

      # 5. Idle connection policy: keep-alive + no slow-start-after-idle
      "net.ipv4.tcp_slow_start_after_idle" = mkDefault 0;
      "net.ipv4.tcp_keepalive_time" = mkDefault 60;
      "net.ipv4.tcp_keepalive_intvl" = mkDefault 10;
      "net.ipv4.tcp_keepalive_probes" = mkDefault 5;

      # 6. Retry limits: release stale connections faster on weak links
      "net.ipv4.tcp_retries2" = mkDefault 8;
      "net.ipv4.tcp_syn_retries" = mkDefault 4;
      "net.ipv4.tcp_synack_retries" = mkDefault 4;

      # 7. Prevent FQ queue from bloating (anti-bufferbloat)
      "net.ipv4.tcp_notsent_lowat" = mkDefault 131072;

      # 8. PMTU black-hole detection
      "net.ipv4.tcp_mtu_probing" = mkDefault 1;
      "net.ipv4.tcp_base_mss" = mkDefault 1024;

      # 9. High-concurrency connection queues
      "net.core.somaxconn" = mkDefault 32768;
      "net.core.netdev_max_backlog" = mkDefault 16384;
      "net.ipv4.tcp_max_syn_backlog" = mkDefault 8192;

      # 10. TIME_WAIT reuse: helpful for outbound connections from the proxy,
      # has no effect for listening sockets (per-RFC, kernel ignores it for
      # inbound SYNs). Kept for the proxy's upstream-facing connections.
      "net.ipv4.tcp_tw_reuse" = mkDefault 1;
    };

    # MSS clamping for tunnelled or small-MTU interfaces.
    # Applied symmetrically on both POSTROUTING (egress) and PREROUTING (ingress)
    # for both IPv4 and IPv6. Errors are NOT silenced — if the rules fail,
    # we want to know (firewall reload will surface them).
    networking.firewall.extraCommands = mkIf (cfg.clampMssInterface != null) ''
      iptables  -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss}
      iptables  -t mangle -A PREROUTING  -p tcp --tcp-flags SYN,RST SYN -i ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss}
      ip6tables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss}
      ip6tables -t mangle -A PREROUTING  -p tcp --tcp-flags SYN,RST SYN -i ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss}
    '';

    networking.firewall.extraStopCommands = mkIf (cfg.clampMssInterface != null) ''
      iptables  -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss} 2>/dev/null || true
      iptables  -t mangle -D PREROUTING  -p tcp --tcp-flags SYN,RST SYN -i ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss} 2>/dev/null || true
      ip6tables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss} 2>/dev/null || true
      ip6tables -t mangle -D PREROUTING  -p tcp --tcp-flags SYN,RST SYN -i ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss} 2>/dev/null || true
    '';
  };
}
