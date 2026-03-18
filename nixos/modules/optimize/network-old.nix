{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkDefault
    types
    ;

  cfg = config.environment.networkOmnitt;

  clamp =
    lo: hi: value:
    if value < lo then
      lo
    else if value > hi then
      hi
    else
      value;

  clampFloat =
    lo: hi: value:
    if value < lo then
      lo
    else if value > hi then
      hi
    else
      value;

  toInt = value: builtins.floor value;
  toFloat = value: value * 1.0;
  sqrt =
    value:
    let
      abs = x: if x < 0 then -x else x;
      next = guess: (guess + value / guess) / 2.0;
      loop = guess: if abs (guess * guess - value) < 0.000001 then guess else loop (next guess);
    in
    if value <= 0 then 0 else loop (if value > 1 then value / 2.0 else 1.0);

  mbToBytes = mb: mb * 1024 * 1024;
  mbpsToBytesPerSecond = mbps: mbps * 1024 * 1024 / 8;
  bdpBytes = mbps: latencyMs: toInt ((mbpsToBytesPerSecond mbps * latencyMs) / 1000.0);

  sigmoidCurve =
    x: steepness: midpoint:
    clampFloat 0.0 1.0 (0.5 + ((x - midpoint) * steepness / 10.0));
  exponentialCurve =
    x: base: multiplier:
    multiplier * (1.0 + ((x - 1.0) * (base - 1.0)));
  queueTheoryCurve =
    x: factor: divisor:
    factor / (1.0 - divisor) * x;

  gamingProfile = memoryMB: {
    responsiveness =
      if memoryMB <= 256 then
        2.5
      else if memoryMB <= 512 then
        2.2
      else if memoryMB <= 1024 then
        2.0
      else
        1.8;
    jitterTolerance =
      if memoryMB <= 256 then
        0.2
      else if memoryMB <= 512 then
        0.25
      else
        0.3;
    burstHandling =
      if memoryMB <= 256 then
        0.5
      else if memoryMB <= 512 then
        0.6
      else
        0.7;
    memoryEfficiency =
      if memoryMB <= 256 then
        0.8
      else if memoryMB <= 512 then
        0.9
      else
        1.0;
    bufferAggression =
      if memoryMB <= 256 then
        0.6
      else if memoryMB <= 512 then
        0.7
      else
        0.8;
    queueDepthPreference =
      if memoryMB <= 256 then
        0.6
      else if memoryMB <= 512 then
        0.7
      else
        0.8;
    connectionDensity =
      if memoryMB <= 256 then
        1.0
      else if memoryMB <= 1024 then
        1.2
      else
        1.5;
    windowScaling = {
      baseMultiplier =
        if memoryMB <= 256 then
          1.0
        else if memoryMB <= 1024 then
          1.2
        else
          1.4;
      latencySensitivity = 1.5;
      maxScale =
        if memoryMB <= 256 then
          3
        else if memoryMB <= 1024 then
          4
        else
          6;
    };
    curves = {
      bufferCurve = {
        steepness = 4;
        midpoint = 0.3;
      };
      latencyCurve = {
        sensitivity = 2;
      };
    };
  };

  commonSysctls = qdisc: congestionControl: {
    "kernel.pid_max" = 65535;
    "kernel.panic" = 1;
    "kernel.sysrq" = 1;
    "kernel.core_pattern" = "core_%e";
    "kernel.printk" = "3 4 1 3";
    "kernel.numa_balancing" = 0;
    "kernel.sched_autogroup_enabled" = 0;
    "net.core.default_qdisc" = qdisc;
    "net.ipv4.tcp_congestion_control" = congestionControl;
    "net.ipv4.tcp_timestamps" = 1;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 10;
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_max_tw_buckets" = 32768;
    "net.ipv4.tcp_sack" = 1;
    "net.ipv4.tcp_abort_on_overflow" = 0;
    "net.ipv4.tcp_stdurg" = 0;
    "net.ipv4.tcp_rfc1337" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.ip_local_port_range" = "1024 65535";
    "net.ipv4.ip_no_pmtu_disc" = 0;
    "net.ipv4.route.gc_timeout" = 100;
    "net.ipv4.neigh.default.gc_stale_time" = 120;
    "net.ipv4.neigh.default.gc_thresh3" = 8192;
    "net.ipv4.neigh.default.gc_thresh2" = 4096;
    "net.ipv4.neigh.default.gc_thresh1" = 1024;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.default.arp_announce" = 2;
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_ignore" = 1;
  };

  mkSysctls =
    args:
    (commonSysctls args.qdisc args.congestionControl)
    // {
      "net.core.rmem_max" = args.rmemMax;
      "net.core.wmem_max" = args.wmemMax;
      "net.core.rmem_default" = args.rmemDefault;
      "net.core.wmem_default" = args.wmemDefault;
      "net.ipv4.tcp_rmem" = "4096 ${toString args.rmemDefault} ${toString args.rmemMax}";
      "net.ipv4.tcp_wmem" = "4096 ${toString args.wmemDefault} ${toString args.wmemMax}";
      "net.core.somaxconn" = args.somaxconn;
      "net.core.optmem_max" = args.optmemMax;
      "net.ipv4.tcp_fastopen" = args.tcpFastOpen;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_notsent_lowat" = args.tcpNotsentLowat;
      "net.ipv4.tcp_window_scaling" = 1;
      "net.ipv4.tcp_adv_win_scale" = args.tcpAdvWinScale;
      "net.ipv4.tcp_moderate_rcvbuf" = args.tcpModerateRcvbuf;
      "net.ipv4.tcp_no_metrics_save" = args.tcpNoMetricsSave;
      "net.ipv4.tcp_max_syn_backlog" = args.tcpMaxSynBacklog;
      "net.ipv4.tcp_max_orphans" = args.tcpMaxOrphans;
      "net.ipv4.tcp_synack_retries" = args.tcpSynAckRetries;
      "net.ipv4.tcp_syn_retries" = args.tcpSynRetries;
      "net.ipv4.tcp_fack" = args.tcpFack;
      "net.ipv4.tcp_limit_output_bytes" = args.tcpLimitOutputBytes;
      "net.ipv4.tcp_reordering" = args.tcpReordering;
      "net.ipv4.tcp_retrans_collapse" = args.tcpRetransCollapse;
      "net.ipv4.tcp_ecn" = args.tcpEcn;
      "net.ipv4.tcp_ecn_fallback" = args.tcpEcnFallback;
      "net.ipv4.tcp_keepalive_time" = args.tcpKeepaliveTime;
      "net.ipv4.tcp_keepalive_intvl" = args.tcpKeepaliveIntvl;
      "net.ipv4.tcp_keepalive_probes" = args.tcpKeepaliveProbes;
      "net.ipv4.tcp_fin_timeout" = args.tcpFinTimeout;
      "vm.swappiness" = args.vmSwappiness;
      "vm.dirty_ratio" = args.vmDirtyRatio;
      "vm.dirty_background_ratio" = args.vmDirtyBackgroundRatio;
      "vm.panic_on_oom" = 1;
      "vm.overcommit_memory" = 1;
      "vm.min_free_kbytes" = args.vmMinFreeKbytes;
      "net.core.netdev_max_backlog" = args.netdevMaxBacklog;
    };

  calcV1 =
    bandwidth: latencyMs: memoryMB: congestionControl: qdisc:
    let
      base = lib.max (toInt ((bandwidth * 1024 * 1024 / 8) * latencyMs / 1000.0)) 16384;
      vmMinFree = clamp 32768 1048576 (mbToBytes memoryMB / 16);
    in
    mkSysctls {
      inherit qdisc congestionControl;
      rmemMax = 2 * base;
      wmemMax = base;
      rmemDefault = 87380;
      wmemDefault = 65536;
      somaxconn = 32768;
      optmemMax = 81920;
      tcpFastOpen = 3;
      tcpNotsentLowat = 16384;
      tcpAdvWinScale = 2;
      tcpModerateRcvbuf = 1;
      tcpNoMetricsSave = 0;
      tcpMaxSynBacklog = 8192;
      tcpMaxOrphans = 32768;
      tcpSynAckRetries = 2;
      tcpSynRetries = 3;
      tcpFack = 1;
      tcpLimitOutputBytes = 0;
      tcpReordering = 0;
      tcpRetransCollapse = 0;
      tcpEcn = 0;
      tcpEcnFallback = 1;
      tcpKeepaliveTime = 60;
      tcpKeepaliveIntvl = 10;
      tcpKeepaliveProbes = 6;
      tcpFinTimeout = 15;
      vmSwappiness = 10;
      vmDirtyRatio = 40;
      vmDirtyBackgroundRatio = 10;
      vmMinFreeKbytes = vmMinFree;
      netdevMaxBacklog = 16384;
    };

  calcV2 =
    bandwidth: realbandwith: latencyMs: _memoryMB: congestionControl: qdisc:
    let
      ratio = clampFloat 1.0 2.0 (1.5 * sqrt (bandwidth / realbandwith));
      bdp = bdpBytes (lib.min (bandwidth * ratio) realbandwith) latencyMs;
      vmMinFree = toInt (clampFloat 131072.0 2097152.0 (bdp / 2.0));
      defaultSize = lib.max 131072 (toInt (bdp / 2));
      backlog = toInt (clampFloat 2000.0 8000.0 (builtins.ceil (bdp / 131072.0)));
      synBacklog = toInt (clampFloat 4096.0 32768.0 (builtins.ceil (bdp / 65536.0)));
    in
    mkSysctls {
      inherit qdisc congestionControl;
      rmemMax = lib.max (bdp * 4) 32768;
      wmemMax = lib.max (bdp * 2) 32768;
      rmemDefault = defaultSize;
      wmemDefault = defaultSize;
      somaxconn = toInt (clampFloat 512.0 4096.0 (builtins.ceil (bdp / 262144.0)));
      optmemMax = toInt (clampFloat 4096.0 131072.0 (bdp / 4.0));
      tcpFastOpen = 3;
      tcpNotsentLowat = 4096;
      tcpAdvWinScale = 3;
      tcpModerateRcvbuf = 0;
      tcpNoMetricsSave = 0;
      tcpMaxSynBacklog = synBacklog;
      tcpMaxOrphans = 131072;
      tcpSynAckRetries = 1;
      tcpSynRetries = 2;
      tcpFack = 0;
      tcpLimitOutputBytes = 0;
      tcpReordering = 0;
      tcpRetransCollapse = 0;
      tcpEcn = 0;
      tcpEcnFallback = 1;
      tcpKeepaliveTime = 60;
      tcpKeepaliveIntvl = 10;
      tcpKeepaliveProbes = 6;
      tcpFinTimeout = 10;
      vmSwappiness = 10;
      vmDirtyRatio = 20;
      vmDirtyBackgroundRatio = 5;
      vmMinFreeKbytes = vmMinFree;
      netdevMaxBacklog = backlog;
    };

  calcV25 =
    bandwidth: realbandwith: latencyMs: _memoryMB: congestionControl: qdisc:
    let
      ratio = clampFloat 1.0 2.0 (1.25 * sqrt (bandwidth / realbandwith));
      bdp = bdpBytes (lib.min (bandwidth * ratio) realbandwith) latencyMs;
      vmMinFree = toInt (clampFloat 65536.0 1048576.0 (bdp / 2.0));
      defaultSize = lib.max 87380 (toInt (bdp / 2));
      backlog = toInt (clampFloat 2000.0 8000.0 (builtins.ceil (bdp / 131072.0)));
      synBacklog = toInt (clampFloat 2048.0 16384.0 (builtins.ceil (bdp / 65536.0)));
    in
    mkSysctls {
      inherit qdisc congestionControl;
      rmemMax = lib.max (bdp * 3) 32768;
      wmemMax = lib.max (bdp * 3 / 2) 32768;
      rmemDefault = defaultSize;
      wmemDefault = defaultSize;
      somaxconn = 2048;
      optmemMax = toInt (clampFloat 4096.0 65536.0 (bdp / 4.0));
      tcpFastOpen = 3;
      tcpNotsentLowat = 4096;
      tcpAdvWinScale = 2;
      tcpModerateRcvbuf = 1;
      tcpNoMetricsSave = 0;
      tcpMaxSynBacklog = synBacklog;
      tcpMaxOrphans = 65536;
      tcpSynAckRetries = 2;
      tcpSynRetries = 2;
      tcpFack = 0;
      tcpLimitOutputBytes = 0;
      tcpReordering = 0;
      tcpRetransCollapse = 0;
      tcpEcn = 0;
      tcpEcnFallback = 1;
      tcpKeepaliveTime = 60;
      tcpKeepaliveIntvl = 10;
      tcpKeepaliveProbes = 6;
      tcpFinTimeout = 10;
      vmSwappiness = 10;
      vmDirtyRatio = 10;
      vmDirtyBackgroundRatio = 5;
      vmMinFreeKbytes = vmMinFree;
      netdevMaxBacklog = backlog;
    };

  calcV3 =
    bandwidth: realbandwith: latencyMs: memoryMB: congestionControl: qdisc:
    let
      memoryBoost =
        if memoryMB <= 256 then
          0.1
        else if memoryMB <= 512 then
          0.125
        else
          0.15;
      ratio = clampFloat 1.0 5.0 (2.0 * sqrt (bandwidth / realbandwith) * (memoryMB / 40.0));
      bdp = bdpBytes (lib.min (bandwidth * ratio) (realbandwith * 2)) latencyMs;
      vmMinFree = toInt (clampFloat 32768.0 1048576.0 ((bdp / 1024.0) * memoryBoost));
      defaultSize = lib.max 87380 (toInt (bdp / 2));
      backlog = toInt (clampFloat 2000.0 4000.0 (builtins.ceil (bdp / 131072.0)));
      synBacklog = toInt (clampFloat 2048.0 16384.0 (builtins.ceil (bdp / 65536.0)));
    in
    mkSysctls {
      inherit qdisc congestionControl;
      rmemMax = lib.max (bdp * 4) 131072;
      wmemMax = lib.max (bdp * 2) 131072;
      rmemDefault = defaultSize;
      wmemDefault = defaultSize;
      somaxconn = 4096;
      optmemMax = toInt (clampFloat 4096.0 65536.0 (bdp / 4.0));
      tcpFastOpen = 3;
      tcpNotsentLowat = 4096;
      tcpAdvWinScale = 2;
      tcpModerateRcvbuf = 1;
      tcpNoMetricsSave = 1;
      tcpMaxSynBacklog = synBacklog;
      tcpMaxOrphans = 65536;
      tcpSynAckRetries = 2;
      tcpSynRetries = 3;
      tcpFack = 1;
      tcpLimitOutputBytes = 0;
      tcpReordering = 64;
      tcpRetransCollapse = 1;
      tcpEcn = 0;
      tcpEcnFallback = 1;
      tcpKeepaliveTime = 60;
      tcpKeepaliveIntvl = 10;
      tcpKeepaliveProbes = 6;
      tcpFinTimeout = 10;
      vmSwappiness = 5;
      vmDirtyRatio = 5;
      vmDirtyBackgroundRatio = 2;
      vmMinFreeKbytes = vmMinFree;
      netdevMaxBacklog = backlog;
    };

  calcV4 =
    bandwidth: realbandwith: latencyMs: memoryMB: rampUpRate: congestionControl: qdisc:
    let
      curveFactor = clampFloat 0.3 2.0 (sigmoidCurve rampUpRate 4.0 0.3);
      latencyCurve = clampFloat 0.8 5.0 (exponentialCurve (latencyMs / 120.0) 2.0 1.0);
      ratio = clampFloat 1.0 5.0 (2.0 * sqrt (bandwidth / realbandwith) * curveFactor);
      bdp = bdpBytes (lib.min (bandwidth * ratio) (realbandwith * 2)) latencyMs;
      queueFactor = clampFloat 0.3 2.0 (queueTheoryCurve (memoryMB / 65536.0) 1.0 0.8);
      rmemMax = lib.max (toInt (bdp * 4 * latencyCurve)) 262144;
      wmemMax = lib.max (toInt (bdp * 2 * latencyCurve)) 262144;
      defaultSize = lib.max 87380 (toInt (bdp / 2));
      backlog = toInt (clampFloat 2000.0 4000.0 (builtins.ceil (bdp / 131072.0)));
      synBacklog = toInt (clampFloat 2048.0 16384.0 (builtins.ceil (bdp / 65536.0)));
      vmMinFree = toInt (clampFloat 131072.0 1048576.0 (bdp / 1024.0));
    in
    mkSysctls {
      inherit qdisc congestionControl;
      inherit rmemMax;
      inherit wmemMax;
      rmemDefault = defaultSize;
      wmemDefault = defaultSize;
      somaxconn = 4096;
      optmemMax = toInt (clampFloat 4096.0 65536.0 (bdp / 4.0));
      tcpFastOpen = 3;
      tcpNotsentLowat = 4096;
      tcpAdvWinScale = toInt (clampFloat 2.0 8.0 (queueFactor * 2.0));
      tcpModerateRcvbuf = 1;
      tcpNoMetricsSave = 0;
      tcpMaxSynBacklog = synBacklog;
      tcpMaxOrphans = 65536;
      tcpSynAckRetries = 2;
      tcpSynRetries = 3;
      tcpFack = 0;
      tcpLimitOutputBytes = 0;
      tcpReordering = 0;
      tcpRetransCollapse = 0;
      tcpEcn = 0;
      tcpEcnFallback = 1;
      tcpKeepaliveTime = 60;
      tcpKeepaliveIntvl = 10;
      tcpKeepaliveProbes = 6;
      tcpFinTimeout = 10;
      vmSwappiness = 5;
      vmDirtyRatio = 5;
      vmDirtyBackgroundRatio = 2;
      vmMinFreeKbytes = vmMinFree;
      netdevMaxBacklog = backlog;
    };

  calcV5 =
    bandwidth: realbandwith: latencyMs: memoryMB: rampUpRate: aggressiveMode: congestionControl: qdisc:
    let
      gaming = gamingProfile memoryMB;
      ratio = bandwidth / realbandwith;
      bandwidthFactor = clampFloat 1.0 2.0 (1.5 * sqrt ratio);
      bdp = bdpBytes (lib.min (bandwidth * bandwidthFactor) realbandwith) latencyMs;
      ratioPenalty = if ratio > 1.0 then lib.max 0.3 (1.0 / sqrt (lib.min ratio 100.0)) else 1.0;
      ratioPenalty2 = if latencyMs > 200 then lib.min 1.0 (1.2 * ratioPenalty) else ratioPenalty;
      baseP = toInt (builtins.ceil (bdp / 1000.0));
      memoryCap = if memoryMB <= 256 then 4194304 else 8388608;
      rmemMaxBase = toInt (lib.max memoryCap (1.5 * memoryMB * ratioPenalty2 * baseP));
      curveFactor1 = clampFloat 0.3 2.0 (
        sigmoidCurve rampUpRate gaming.curves.bufferCurve.steepness gaming.curves.bufferCurve.midpoint
        * (gaming.responsiveness / 2.0)
      );
      latencyFactor = clampFloat 0.8 5.0 (
        exponentialCurve (latencyMs / 120.0) gaming.curves.latencyCurve.sensitivity 1.0
        * curveFactor1
        * gaming.responsiveness
      );
      advWinScaleFactor = clampFloat 1.0 (toFloat gaming.windowScaling.maxScale) (
        (latencyFactor / gaming.windowScaling.latencySensitivity)
        * gaming.windowScaling.baseMultiplier
        * (1.0 + bdp / 65535.0 / 4.0)
      );
      rmemMax = lib.max (toInt (rmemMaxBase * (if aggressiveMode then 2 else 1))) memoryCap;
      wmemMax = lib.max memoryCap (toInt rmemMaxBase);
      defaultSize = 524288;
      netdevMaxBacklog =
        if aggressiveMode then
          toInt (lib.min (6 * memoryMB) (6000 + toInt ((bdp / 1048576.0) * 5.0)))
        else
          toInt (lib.min (4 * memoryMB) (4000 + toInt ((bdp / 1048576.0) * 4.0)));
      somaxconn = if aggressiveMode then 32768 else 16384;
      tcpMaxSynBacklog =
        if aggressiveMode then
          toInt (lib.min (somaxconn / 2) (3000 + toInt ((bdp / 1048576.0) * 5.0)))
        else
          toInt (lib.min (somaxconn / 2) (2000 + toInt ((bdp / 1048576.0) * 3.0)));
      tcpNotsentLowat = if aggressiveMode then 32768 else 16384;
      tcpMem =
        if aggressiveMode then
          "${toString (512 * memoryMB)} ${toString (768 * memoryMB)} ${toString (1024 * memoryMB)}"
        else
          "${toString (384 * memoryMB)} ${toString (512 * memoryMB)} ${toString (768 * memoryMB)}";
      tcpAdvWinScale = toInt (clampFloat 2.0 8.0 (builtins.ceil (curveFactor1 * advWinScaleFactor)));
      tcpLimitOutputBytes = if aggressiveMode then toInt (bdp * 2) else toInt (bdp + 524288);
      vmMinFree =
        if aggressiveMode then lib.max 262144 (64 * memoryMB) else lib.max 131072 (32 * memoryMB);
      vmSwappiness = if aggressiveMode then 1 else 5;
      qdiscFinal = if aggressiveMode then "fq" else qdisc;
      tcpFastOpen = 3;
      tcpModerateRcvbuf = if aggressiveMode then 0 else 1;
      tcpNoMetricsSave = if aggressiveMode then 1 else 0;
      tcpSynRetries = if aggressiveMode then 2 else 3;
      tcpSynAckRetries = 2;
      tcpFack = 1;
      tcpReordering = if aggressiveMode then 64 else 96;
      tcpRetransCollapse = 1;
      tcpEcn = 0;
      tcpEcnFallback = 1;
      tcpKeepaliveTime = if aggressiveMode then 1200 else 600;
      tcpKeepaliveIntvl = if aggressiveMode then 60 else 30;
      tcpKeepaliveProbes = 3;
      tcpFinTimeout = if aggressiveMode then 30 else 15;
      vmDirtyRatio = 5;
      vmDirtyBackgroundRatio = 2;
    in
    mkSysctls {
      inherit
        qdiscFinal
        congestionControl
        rmemMax
        wmemMax
        ;
      qdisc = qdiscFinal;
      rmemDefault = defaultSize;
      wmemDefault = defaultSize;
      inherit netdevMaxBacklog;
      inherit somaxconn;
      optmemMax = toInt (lib.min 163840 (160 * memoryMB));
      inherit tcpFastOpen;
      inherit tcpNotsentLowat;
      inherit tcpAdvWinScale;
      inherit tcpModerateRcvbuf;
      inherit tcpNoMetricsSave;
      inherit tcpMaxSynBacklog;
      tcpMaxOrphans = 32768;
      inherit tcpSynAckRetries;
      inherit tcpSynRetries;
      inherit tcpFack;
      inherit tcpLimitOutputBytes;
      inherit tcpReordering;
      inherit tcpRetransCollapse;
      inherit tcpEcn;
      inherit tcpEcnFallback;
      inherit tcpKeepaliveTime;
      inherit tcpKeepaliveIntvl;
      inherit tcpKeepaliveProbes;
      inherit tcpFinTimeout;
      inherit vmSwappiness;
      inherit vmDirtyRatio;
      inherit vmDirtyBackgroundRatio;
      vmMinFreeKbytes = vmMinFree;
      "net.ipv4.tcp_mem" = tcpMem;
      "net.core.busy_read" = if aggressiveMode then 50 else 0;
      "net.core.busy_poll" = if aggressiveMode then 50 else 0;
      "kernel.sched_min_granularity_ns" = if aggressiveMode then 3000000 else 5000000;
    };

  sysctls =
    if cfg.version == "v1" then
      calcV1 cfg.bandwith cfg.latencyMs cfg.memoryMB cfg.congestionControl cfg.qdisc
    else if cfg.version == "v2" then
      calcV2 cfg.bandwith cfg.realbandwith cfg.latencyMs cfg.memoryMB cfg.congestionControl cfg.qdisc
    else if cfg.version == "v25" then
      calcV25 cfg.bandwith cfg.realbandwith cfg.latencyMs cfg.memoryMB cfg.congestionControl cfg.qdisc
    else if cfg.version == "v3" then
      calcV3 cfg.bandwith cfg.realbandwith cfg.latencyMs cfg.memoryMB cfg.congestionControl cfg.qdisc
    else if cfg.version == "v4" then
      calcV4 cfg.bandwith cfg.realbandwith cfg.latencyMs cfg.memoryMB cfg.rampUpRate cfg.congestionControl
        cfg.qdisc
    else
      calcV5 cfg.bandwith cfg.realbandwith cfg.latencyMs cfg.memoryMB cfg.rampUpRate cfg.aggressiveMode
        cfg.congestionControl
        cfg.qdisc;

  sysctlText =
    builtins.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "${name} = ${toString value}") sysctls
    )
    + "\n";
in
{
  options.environment.networkOmnitt = {
    enable = (mkEnableOption "Omnitt network tuning") // {
      default = true;
    };

    version = mkOption {
      type = types.enum [
        "v1"
        "v2"
        "v25"
        "v3"
        "v4"
        "v5"
      ];
      default = "v5";
      description = "Omnitt formula version.";
    };

    aggressiveMode = mkOption {
      type = types.bool;
      default = true;
      description = "Enable aggressive mode for the V5 branch.";
    };

    bandwith = mkOption {
      type = types.int;
      default = 1000;
      description = "Server bandwidth in Mbps.";
    };

    realbandwith = mkOption {
      type = types.int;
      default = 1000;
      description = "Local bandwidth in Mbps.";
    };

    latencyMs = mkOption {
      type = types.int;
      default = 100;
      description = "Network RTT in milliseconds.";
    };

    memoryMB = mkOption {
      type = types.int;
      default = 1024;
      description = "Available RAM in MB.";
    };

    rampUpRate = mkOption {
      type = types.float;
      default = 0.79;
      description = "Ramp-up curve factor.";
    };

    congestionControl = mkOption {
      type = types.enum [
        "bbr"
        "bbrv1"
        "cubic"
      ];
      default = "bbr";
      description = "TCP congestion control algorithm.";
    };

    qdisc = mkOption {
      type = types.enum [
        "fq"
        "cake"
        "fq_pie"
      ];
      default = "fq";
      description = "Default queuing discipline.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.bandwith > 0 && cfg.realbandwith > 0 && cfg.latencyMs > 0 && cfg.memoryMB > 0;
        message = "Omnitt network inputs must be positive.";
      }
      {
        assertion = cfg.rampUpRate >= 0.1 && cfg.rampUpRate <= 1.0;
        message = "environment.networkOmnitt.rampUpRate must be in the range 0.1..1.0.";
      }
    ];

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = mkDefault true;
      "net.ipv4.ip_forward" = mkDefault 1;
      "net.ipv6.conf.all.forwarding" = mkDefault 1;
    };

    environment.etc."sysctl.d/99-network-omnitt.conf".text = lib.mkForce sysctlText;
  };
}
