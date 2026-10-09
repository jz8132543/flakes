{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.optimize.brutal;

  # 从 sing-geoip 的 rule-set 中解包出大陆 IPv4 与 IPv6 CIDR 列表
  chinaCidrs =
    pkgs.runCommand "china-cidrs"
      {
        nativeBuildInputs = [
          pkgs.sing-box
          pkgs.jq
        ];
      }
      ''
        mkdir -p $out
        sing-box rule-set decompile -o cn.json ${pkgs.sing-geoip}/share/sing-box/rule-set/geoip-cn.srs
        jq -r '.rules[0].ip_cidr[]' cn.json | grep -v ':' > $out/ipv4.txt
        jq -r '.rules[0].ip_cidr[]' cn.json | grep ':' > $out/ipv6.txt
        rm -f cn.json
      '';

  # 私网与保留网段 (在 !cn 模式下同样保护为默认拥塞控制，不走 Brutal)
  privateCidrsV4 = pkgs.writeText "private-ipv4.txt" ''
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    224.0.0.0/4
  '';

  privateCidrsV6 = pkgs.writeText "private-ipv6.txt" ''
    ::1/128
    fc00::/7
    fe80::/10
    ff00::/8
  '';

  tcpBrutalKmod =
    inputs.tcp-brutal.outputs.lib.${pkgs.system}.mkTcpBrutal
      config.boot.kernelPackages.kernel;

  applyScript = pkgs.writeShellScriptBin "tcp-brutal-apply-rules" ''
    set -euo pipefail

    # 1. 确保内核模块已加载 (支持免重启 insmod 热加载)
    if [ ! -w /proc/net/tcp_brutal/rules ]; then
      ${pkgs.kmod}/bin/modprobe brutal 2>/dev/null || true
    fi
    if [ ! -w /proc/net/tcp_brutal/rules ]; then
      MODULE_PATH=$(find ${tcpBrutalKmod}/lib/modules -name "*brutal.ko*" 2>/dev/null | head -n 1)
      if [ -n "$MODULE_PATH" ]; then
        ${pkgs.kmod}/bin/insmod "$MODULE_PATH" 2>/dev/null || true
      fi
    fi
    if [ ! -w /proc/net/tcp_brutal/rules ]; then
      echo "ERROR: /proc/net/tcp_brutal/rules is not writable. Is tcp-brutal module loaded?" >&2
      exit 1
    fi

    # 2. 计算字节速率 (rate = Mbps * 1,000,000 / 8)
    RATE_MBPS=${toString cfg.bandwidth}
    RATE_BYTES=$(( RATE_MBPS * 1000000 / 8 ))
    TARGET="${cfg.target}"
    DEFAULT_CC=$(${pkgs.procps}/bin/sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "bbr")
    [ -z "$DEFAULT_CC" ] && DEFAULT_CC="bbr"

    echo "Applying TCP Brutal rules (target: $TARGET) with rate: ''${RATE_MBPS} Mbps (''${RATE_BYTES} B/s, fallback CC: ''${DEFAULT_CC})..."

    # 3. 获取 IPv4 / IPv6 默认网关与出口网卡
    DEV_V4=$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    VIA_V4=$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')

    DEV_V6=$(${pkgs.iproute2}/bin/ip -6 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    VIA_V6=$(${pkgs.iproute2}/bin/ip -6 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')

    exec 3> /proc/net/tcp_brutal/rules

    if [ "$TARGET" = "cn" ]; then
      # ── 模式 A: cn (境外服务器向大陆客户端加速) ──────────────────────────
      ${lib.optionalString cfg.enableIpv4 ''
        if [ -n "$DEV_V4" ]; then
          echo "Configuring IPv4 China destinations via dev $DEV_V4 (via: $VIA_V4)..."
          while IFS= read -r cidr; do
            [ -z "$cidr" ] && continue
            echo "add $cidr rate=$RATE_BYTES" >&3
          done < "${chinaCidrs}/ipv4.txt"

          if [ -n "$VIA_V4" ]; then
            ${pkgs.gawk}/bin/awk -v via="$VIA_V4" -v dev="$DEV_V4" \
              '{print "route replace", $0, "via", via, "dev", dev, "congctl lock brutal proto 233"}' \
              "${chinaCidrs}/ipv4.txt" | ${pkgs.iproute2}/bin/ip -4 -batch -
          else
            ${pkgs.gawk}/bin/awk -v dev="$DEV_V4" \
              '{print "route replace", $0, "dev", dev, "congctl lock brutal proto 233"}' \
              "${chinaCidrs}/ipv4.txt" | ${pkgs.iproute2}/bin/ip -4 -batch -
          fi
        else
          echo "Notice: No default IPv4 route found, skipping IPv4."
        fi
      ''}

      ${lib.optionalString cfg.enableIpv6 ''
        if [ -n "$DEV_V6" ]; then
          echo "Configuring IPv6 China destinations via dev $DEV_V6 (via: $VIA_V6)..."
          while IFS= read -r cidr; do
            [ -z "$cidr" ] && continue
            echo "add $cidr rate=$RATE_BYTES" >&3
          done < "${chinaCidrs}/ipv6.txt"

          if [ -n "$VIA_V6" ]; then
            ${pkgs.gawk}/bin/awk -v via="$VIA_V6" -v dev="$DEV_V6" \
              '{print "route replace", $0, "via", via, "dev", dev, "congctl lock brutal proto 233"}' \
              "${chinaCidrs}/ipv6.txt" | ${pkgs.iproute2}/bin/ip -6 -batch -
          else
            ${pkgs.gawk}/bin/awk -v dev="$DEV_V6" \
              '{print "route replace", $0, "dev", dev, "congctl lock brutal proto 233"}' \
              "${chinaCidrs}/ipv6.txt" | ${pkgs.iproute2}/bin/ip -6 -batch -
          fi
        else
          echo "Notice: No default IPv6 route found, skipping IPv6."
        fi
      ''}
    else
      # ── 模式 B: !cn (国内服务器向境外 VPS/代理节点加速) ──────────────────
      # 原理：利用 LPM (最长前缀匹配)。
      # 1. 全局 0.0.0.0/1 和 128.0.0.0/1 (及 ::/1, 8000::/1) 走 brutal；
      # 2. 所有大陆 CIDR 及局域网/保留私网 CIDR 显式指定锁定为系统的 default CC (如 bbr)，不走 brutal；
      # 3. 从而完美实现“仅非大陆境外目标走 Brutal，国内目标与内网保留正常 BBR/CUBIC”。
      ${lib.optionalString cfg.enableIpv4 ''
        if [ -n "$DEV_V4" ]; then
          echo "Configuring IPv4 global !cn destinations via dev $DEV_V4 (via: $VIA_V4)..."
          echo "add 0.0.0.0/1 rate=$RATE_BYTES" >&3
          echo "add 128.0.0.0/1 rate=$RATE_BYTES" >&3

          # 全局双 /1 锁定 brutal
          if [ -n "$VIA_V4" ]; then
            ${pkgs.iproute2}/bin/ip -4 route replace 0.0.0.0/1 via "$VIA_V4" dev "$DEV_V4" congctl lock brutal proto 233
            ${pkgs.iproute2}/bin/ip -4 route replace 128.0.0.0/1 via "$VIA_V4" dev "$DEV_V4" congctl lock brutal proto 233
          else
            ${pkgs.iproute2}/bin/ip -4 route replace 0.0.0.0/1 dev "$DEV_V4" congctl lock brutal proto 233
            ${pkgs.iproute2}/bin/ip -4 route replace 128.0.0.0/1 dev "$DEV_V4" congctl lock brutal proto 233
          fi

          # 大陆与私网保留网段显式锁定为默认 CC，排除在 brutal 之外
          cat "${chinaCidrs}/ipv4.txt" "${privateCidrsV4}" | if [ -n "$VIA_V4" ]; then
            ${pkgs.gawk}/bin/awk -v via="$VIA_V4" -v dev="$DEV_V4" -v cc="$DEFAULT_CC" \
              '{print "route replace", $0, "via", via, "dev", dev, "congctl lock", cc, "proto 233"}' | \
              ${pkgs.iproute2}/bin/ip -4 -batch -
          else
            ${pkgs.gawk}/bin/awk -v dev="$DEV_V4" -v cc="$DEFAULT_CC" \
              '{print "route replace", $0, "dev", dev, "congctl lock", cc, "proto 233"}' | \
              ${pkgs.iproute2}/bin/ip -4 -batch -
          fi
        fi
      ''}

      ${lib.optionalString cfg.enableIpv6 ''
        if [ -n "$DEV_V6" ]; then
          echo "Configuring IPv6 global !cn destinations via dev $DEV_V6 (via: $VIA_V6)..."
          echo "add ::/1 rate=$RATE_BYTES" >&3
          echo "add 8000::/1 rate=$RATE_BYTES" >&3

          if [ -n "$VIA_V6" ]; then
            ${pkgs.iproute2}/bin/ip -6 route replace ::/1 via "$VIA_V6" dev "$DEV_V6" congctl lock brutal proto 233
            ${pkgs.iproute2}/bin/ip -6 route replace 8000::/1 via "$VIA_V6" dev "$DEV_V6" congctl lock brutal proto 233
          else
            ${pkgs.iproute2}/bin/ip -6 route replace ::/1 dev "$DEV_V6" congctl lock brutal proto 233
            ${pkgs.iproute2}/bin/ip -6 route replace 8000::/1 dev "$DEV_V6" congctl lock brutal proto 233
          fi

          cat "${chinaCidrs}/ipv6.txt" "${privateCidrsV6}" | if [ -n "$VIA_V6" ]; then
            ${pkgs.gawk}/bin/awk -v via="$VIA_V6" -v dev="$DEV_V6" -v cc="$DEFAULT_CC" \
              '{print "route replace", $0, "via", via, "dev", dev, "congctl lock", cc, "proto 233"}' | \
              ${pkgs.iproute2}/bin/ip -6 -batch -
          else
            ${pkgs.gawk}/bin/awk -v dev="$DEV_V6" -v cc="$DEFAULT_CC" \
              '{print "route replace", $0, "dev", dev, "congctl lock", cc, "proto 233"}' | \
              ${pkgs.iproute2}/bin/ip -6 -batch -
          fi
        fi
      ''}
    fi

    # ── 额外自定义 CIDR ──────────────────────────────────────────────
    ${lib.concatMapStringsSep "\n" (cidr: ''
      echo "add ${cidr} rate=$RATE_BYTES" >&3
      if echo "${cidr}" | grep -q ':'; then
        if [ -n "$DEV_V6" ]; then
          if [ -n "$VIA_V6" ]; then
            ${pkgs.iproute2}/bin/ip -6 route replace ${cidr} via $VIA_V6 dev $DEV_V6 congctl lock brutal proto 233
          else
            ${pkgs.iproute2}/bin/ip -6 route replace ${cidr} dev $DEV_V6 congctl lock brutal proto 233
          fi
        fi
      else
        if [ -n "$DEV_V4" ]; then
          if [ -n "$VIA_V4" ]; then
            ${pkgs.iproute2}/bin/ip -4 route replace ${cidr} via $VIA_V4 dev $DEV_V4 congctl lock brutal proto 233
          else
            ${pkgs.iproute2}/bin/ip -4 route replace ${cidr} dev $DEV_V4 congctl lock brutal proto 233
          fi
        fi
      fi
    '') cfg.extraCidrs}

    exec 3>&-
    echo "TCP Brutal rules successfully applied!"
  '';

  stopScript = pkgs.writeShellScriptBin "tcp-brutal-flush-rules" ''
    if [ -w /proc/net/tcp_brutal/rules ]; then
      echo "flush" > /proc/net/tcp_brutal/rules || true
    fi
    ${pkgs.iproute2}/bin/ip -4 route flush proto 233 || true
    ${pkgs.iproute2}/bin/ip -6 route flush proto 233 || true
    echo "TCP Brutal rules flushed."
  '';
in
{
  imports = [
    inputs.tcp-brutal.nixosModules.default
  ];

  options.optimize.brutal = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable TCP Brutal acceleration.";
    };

    target = lib.mkOption {
      type = lib.types.enum [
        "cn"
        "!cn"
      ];
      default = "cn";
      description = ''
        Target destination traffic to accelerate with TCP Brutal:
        - "cn": Accelerate traffic destined for Mainland China (for overseas servers sending to China).
        - "!cn": Accelerate traffic destined for outside Mainland China (for domestic China servers sending overseas).
      '';
    };

    bandwidth = lib.mkOption {
      type = lib.types.int;
      default =
        if (config.environment.networkTune.realBandwidth or 0) > 0 then
          config.environment.networkTune.realBandwidth
        else if (config.environment.networkTune.bandwidth or 0) > 0 then
          config.environment.networkTune.bandwidth
        else
          55;
      description = "Target pacing rate in Mbps (defaults to environment.networkTune.realBandwidth or 55).";
    };

    enableIpv4 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to accelerate IPv4 destinations.";
    };

    enableIpv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to accelerate IPv6 destinations if an IPv6 default route exists.";
    };

    extraCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "1.0.0.0/10" ];
      description = "Additional CIDRs to accelerate with TCP Brutal.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 自动开启 tcp-brutal 内核模块和 brutalctl
    boot.tcp-brutal.enable = lib.mkDefault true;

    # 系统级服务：网络在线后秒级批量下发规则与路由
    systemd.services.tcp-brutal-china-rules = {
      description = "Apply TCP Brutal acceleration rules (target: ${cfg.target})";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${applyScript}/bin/tcp-brutal-apply-rules";
        ExecStop = "${stopScript}/bin/tcp-brutal-flush-rules";
      };
    };
  };
}
