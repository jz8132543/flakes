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
      default = 67108864; # 64MiB
      description = "Maximum TCP socket buffer size in bytes for high-BDP lossy link";
    };

    clampMssInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional interface name to clamp MSS (leave null for standard physical MTU 1500)";
    };

    clampMss = mkOption {
      type = types.int;
      default = 1240;
      description = "Target MSS if clamping is explicitly enabled";
    };
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl = {
      # 1. 全局排队调度与拥塞控制: FQ + BBR (直连公网与抗随机丢包的核心)
      "net.core.default_qdisc" = mkDefault "fq";
      "net.ipv4.tcp_congestion_control" = mkDefault "bbr";

      # 2. 扩充 Socket 缓冲区 (针对国际长距离、高延迟大 BDP 链路)
      "net.core.rmem_max" = mkDefault cfg.maxBufferBytes;
      "net.core.wmem_max" = mkDefault cfg.maxBufferBytes;
      "net.ipv4.tcp_rmem" = mkDefault "4096 87380 ${toString cfg.maxBufferBytes}";
      "net.ipv4.tcp_wmem" = mkDefault "4096 65536 ${toString cfg.maxBufferBytes}";
      "net.core.rmem_default" = mkDefault 262144;
      "net.core.wmem_default" = mkDefault 262144;

      # 3. 启用 TCP 窗口缩放 (RFC 1323) 与时间戳
      "net.ipv4.tcp_window_scaling" = mkDefault 1;
      "net.ipv4.tcp_timestamps" = mkDefault 1;

      # 4. 抗丢包关键策略：选择性确认 (SACK) 与快速恢复
      "net.ipv4.tcp_sack" = mkDefault 1;
      "net.ipv4.tcp_dsack" = mkDefault 1;
      # RACK (RFC 8985): 基于纳秒/微秒时间戳的丢包精准判定，不依赖重传冗余 ACK
      "net.ipv4.tcp_recovery" = mkDefault 1;
      # 尾部丢包探测 (TLP) 与早期重传
      "net.ipv4.tcp_early_retrans" = mkDefault 3;
      "net.ipv4.tcp_reordering" = mkDefault 3;

      # 5. 空闲连接策略: 保持长连接活跃，禁用慢启动重启
      "net.ipv4.tcp_slow_start_after_idle" = mkDefault 0;
      "net.ipv4.tcp_keepalive_time" = mkDefault 60;
      "net.ipv4.tcp_keepalive_intvl" = mkDefault 10;
      "net.ipv4.tcp_keepalive_probes" = mkDefault 5;

      # 6. 重试衰减: 避免弱网死连接长久占用文件句柄
      "net.ipv4.tcp_retries2" = mkDefault 8;
      "net.ipv4.tcp_syn_retries" = mkDefault 4;
      "net.ipv4.tcp_synack_retries" = mkDefault 4;

      # 7. 控制 Socket 发送低水位，避免 FQ 队列暴涨 (防 Bufferbloat)
      "net.ipv4.tcp_notsent_lowat" = mkDefault 131072;

      # 8. PMTU 黑洞探测 (标准公网 MTU 1500 自动探测)
      "net.ipv4.tcp_mtu_probing" = mkDefault 1;
      "net.ipv4.tcp_base_mss" = mkDefault 1024;

      # 9. 高并发连接队列容量
      "net.core.somaxconn" = mkDefault 32768;
      "net.core.netdev_max_backlog" = mkDefault 16384;
      "net.ipv4.tcp_max_syn_backlog" = mkDefault 8192;
      "net.ipv4.tcp_tw_reuse" = mkDefault 1;
    };

    networking.firewall.extraCommands = mkIf (cfg.clampMssInterface != null) ''
      iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss} || true
      iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN -i ${cfg.clampMssInterface} -j TCPMSS --set-mss ${toString cfg.clampMss} || true
    '';
  };
}
