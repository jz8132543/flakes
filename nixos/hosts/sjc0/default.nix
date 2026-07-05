{
  lib,
  nixosModules,
  pkgs,
  ...
}:
{
  imports = [
    nixosModules.cloud.options
  ]
  ++ nixosModules.users.tippy.all
  ++ [
    ./hardware-configuration.nix
    nixosModules.optimize.minimal
    nixosModules.optimize.ext4
    # nixosModules.optimize.fakehttp
    nixosModules.services.traefik
    nixosModules.services.derp
    # nixosModules.services.stun
    nixosModules.matrix.matrix-rtc
    (import nixosModules.services.xray {
      # needProxy = true;
    })
    # nixosModules.services.tuic
    # nixosModules.services.perplexica
    nixosModules.services.rustdesk
    # nixosModules.media.jellyfin
    # nixosModules.services.headscale
    # (import nixosModules.services.alist { })
  ];

  environment.networkTune = {
    enable = true;
    bandwidth = 500; # Mbps 单向
    realBandwidth = 500;
    rtt = 200; # ms，国际线路
    ram = 2048; # MB，可用内存
    cpus = 2; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };

  # sjc0 资源比 tyo0 宽裕，但 500M 线路不需要超大首包突发和 20M+ 待发积压。
  # 下载优先时保留足够爬坡空间，同时降低重传风暴和队列驻留风险。
  boot.kernel.sysctl = {
    "net.ipv4.tcp_limit_output_bytes" = lib.mkForce 4194304;
    "net.ipv4.tcp_notsent_lowat" = lib.mkForce 524288;
    "net.ipv4.tcp_pacing_ss_ratio" = lib.mkForce 320;
    "net.ipv4.tcp_pacing_ca_ratio" = lib.mkForce 120;
    "net.mptcp.enabled" = lib.mkForce 0;
  };

  systemd.services.sjc0-egress-tune = {
    description = "Apply sjc0 500M egress pacing";
    after = [
      "network-online.target"
      "set-initcwnd.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      coreutils
      gawk
      gnugrep
      iproute2
      procps
    ];
    script = ''
      set -euo pipefail

      IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
      [ -z "$IFACE" ] && exit 0

      DEF=$(ip -4 route show default dev "$IFACE" | head -n 1)
      MSS=$(echo "$DEF" | awk '{for(i=1;i<=NF;i++) if($i=="advmss"){print $(i+1); exit}}')
      [ -z "$MSS" ] && MSS=1460

      sysctl -w \
        net.ipv4.tcp_limit_output_bytes=4194304 \
        net.ipv4.tcp_notsent_lowat=524288 \
        net.ipv4.tcp_pacing_ss_ratio=320 \
        net.ipv4.tcp_pacing_ca_ratio=120 \
        net.mptcp.enabled=0 >/dev/null

      [ -n "$DEF" ] && ip route change $DEF initcwnd 512 initrwnd 1024 advmss "$MSS" || true

      tc qdisc replace dev "$IFACE" root fq maxrate 480mbit flow_limit 200 quantum 12000 initial_quantum 32768 || true

      echo "[sjc0-egress-tune] iface=$IFACE initcwnd=512 initrwnd=1024 fq_maxrate=480mbit"
    '';
  };
}
