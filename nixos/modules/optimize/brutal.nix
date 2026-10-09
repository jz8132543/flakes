{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.optimize.brutal;

  # 从 sing-geoip 的 rule-set 中高效解包出大陆 IPv4 与 IPv6 CIDR 列表
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

  applyScript = pkgs.writeShellScriptBin "tcp-brutal-apply-china-rules" ''
    set -euo pipefail

    # 1. 确保内核模块已加载
    ${pkgs.kmod}/bin/modprobe brutal 2>/dev/null || true
    if [ ! -w /proc/net/tcp_brutal/rules ]; then
      echo "ERROR: /proc/net/tcp_brutal/rules is not writable. Is tcp-brutal module loaded?" >&2
      exit 1
    fi

    # 2. 计算字节速率 (rate = Mbps * 1,000,000 / 8)
    RATE_MBPS=${toString cfg.bandwidth}
    RATE_BYTES=$(( RATE_MBPS * 1000000 / 8 ))
    echo "Applying TCP Brutal Mainland China rules with rate: ''${RATE_MBPS} Mbps (''${RATE_BYTES} B/s)..."

    # 3. 获取 IPv4 / IPv6 默认网关与出口网卡
    DEV_V4=$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    VIA_V4=$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')

    DEV_V6=$(${pkgs.iproute2}/bin/ip -6 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    VIA_V6=$(${pkgs.iproute2}/bin/ip -6 route show default | ${pkgs.gawk}/bin/awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')

    # 4. 批量向 /proc/net/tcp_brutal/rules 写入规则 (保持单次 write 长度 <= 256)
    exec 3> /proc/net/tcp_brutal/rules

    ${lib.optionalString cfg.enableIpv4 ''
      if [ -n "$DEV_V4" ]; then
        echo "Configuring IPv4 China destinations via dev $DEV_V4 (via: $VIA_V4)..."
        while IFS= read -r cidr; do
          [ -z "$cidr" ] && continue
          echo "add $cidr rate=$RATE_BYTES" >&3
        done < "${chinaCidrs}/ipv4.txt"

        # 批量下发内核路由 (proto 233, congctl lock brutal)
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

  stopScript = pkgs.writeShellScriptBin "tcp-brutal-flush-china-rules" ''
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
      description = "Whether to enable TCP Brutal acceleration for Mainland China traffic.";
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
      description = "Whether to accelerate Mainland China IPv4 destinations.";
    };

    enableIpv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to accelerate Mainland China IPv6 destinations if an IPv6 default route exists.";
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
      description = "Apply TCP Brutal acceleration rules for Mainland China";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${applyScript}/bin/tcp-brutal-apply-china-rules";
        ExecStop = "${stopScript}/bin/tcp-brutal-flush-china-rules";
      };
    };
  };
}
