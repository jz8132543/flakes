{
  lib,
  nixosModules,
  pkgs,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ [
      ./hardware-configuration.nix
      nixosModules.optimize.minimal
      # nixosModules.optimize.fakehttp
      nixosModules.services.traefik
      # nixosModules.services.derp
      (import nixosModules.services.xray {
      })
    ];

  environment.networkTune = {
    enable = true;
    bandwidth = 500; # Mbps 单向
    realBandwidth = 450;
    rtt = 200; # ms，国际线路
    ram = 334; # MB，可用内存
    cpus = 1; # vCPU 数
    highLoss = true; # 高丢包国际线路
  };

  # 低 CPU 版本：尽早让 userspace OOM 管理器介入，避免等到内核真正 OOM 才处理。
  services.earlyoom = {
    freeMemThreshold = 15;
    freeSwapThreshold = 15;
    freeMemKillThreshold = 7;
    freeSwapKillThreshold = 7;
    reportInterval = 3600;
  };

  # 给 xray 单独设内存压力阈值，让它在接近上限时先被 cgroup 回收/节流。
  systemd.services.xray.serviceConfig = {
    MemoryHigh = "180M";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "60%";
    OOMScoreAdjust = -900;
  };

  # tyo0 只有 1 vCPU / 334 MiB，可用内存非常紧。
  # 这台机器上更需要抑制首包突发和每连接待发积压，避免 socket 压力把系统推入 swap/allocstall。
  boot.kernel.sysctl = {
    "net.ipv4.tcp_limit_output_bytes" = lib.mkForce 2097152;
    "net.ipv4.tcp_notsent_lowat" = lib.mkForce 262144;
    "net.ipv4.tcp_pacing_ss_ratio" = lib.mkForce 300;
    "net.ipv4.tcp_pacing_ca_ratio" = lib.mkForce 120;
    "net.mptcp.enabled" = lib.mkForce 0;
    "net.netfilter.nf_conntrack_max" = lib.mkForce 65536;
  };

  systemd.services.tyo0-egress-tune = {
    description = "Apply tyo0 low-resource egress pacing";
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
        net.ipv4.tcp_limit_output_bytes=2097152 \
        net.ipv4.tcp_notsent_lowat=262144 \
        net.ipv4.tcp_pacing_ss_ratio=300 \
        net.ipv4.tcp_pacing_ca_ratio=120 \
        net.mptcp.enabled=0 \
        net.netfilter.nf_conntrack_max=65536 >/dev/null

      [ -n "$DEF" ] && ip route change $DEF initcwnd 256 initrwnd 512 advmss "$MSS" || true

      tc qdisc replace dev "$IFACE" root fq maxrate 420mbit flow_limit 200 quantum 12000 initial_quantum 32768 || true

      echo "[tyo0-egress-tune] iface=$IFACE initcwnd=256 initrwnd=512 fq_maxrate=420mbit"
    '';
  };
}
