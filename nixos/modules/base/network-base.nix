{
  config,
  lib,
  ...
}:
{
  services.resolved.enable = false;

  # ── 1. SmartDNS 本地 DoH 客户端 ──────────────────────────────
  # 作为全系统的高性能安全 DNS 递归客户端，专门处理上游 DoH (DNS over HTTPS)
  # 监听本地 127.0.0.1:5335，不向局域网暴露。
  # 优先向上游纯净 DoH 服务器发起 TLS 加密查询，杜绝明文 UDP 53 嗅探与任何 DNS 污染。
  services.smartdns = {
    enable = true;
    bindPort = 5335;
    settings = {
      bind = "127.0.0.1:5335";

      # 上游主用 DoH 服务器（优先请求 Cloudflare 与 Google 纯净 DoH 接口）
      # 出站走 DN42 骨干网出国直达境外节点，彻底避免国内物理链路审查
      server-https = [
        "https://1.1.1.1/dns-query"
        "https://8.8.8.8/dns-query"
      ];

      # 允许正常解析 AAAA (IPv6) 记录，支持纯 IPv6 网站、教育网/校园网 IPv6 资源与专用节点。
      # 对于双栈域名（如 Google、Bilibili），底层通过本文件末尾配置的 gai.conf (RFC 6724 规则)
      # 自动使系统优先选择 IPv4，从而无缝享受 DN42 骨干网出国加速，同时兼顾 IPv6-only 站点的正常连通。
      force-AAAA-SOA = false;

      cache-size = 4096;
      prefetch-domain = true;
      serve-expired = true;
      log-level = "warn";
    };
  };

  # ── 2. Dnsmasq 本地前端与智能分流 / 降级 ────────────────────────
  # 监听标准端口 127.0.0.1:53，统一纳管本地解析与环境感知降级：
  # 1. 优先（队列首部）：通过 127.0.0.1#5335 走 SmartDNS DoH 纯净加密解析；
  # 2. 内部域名分流：*.dn42 走 Anycast，*.ts 走 Tailscale MagicDNS，*.et 走 EasyTier；
  # 3. 降级 Fallback：当处于校园网/酒店 Wi-Fi 强制 Web 认证门户（Captive Portal）等未登录断网环境时，
  #    DoH 因外网中断超时，strict-order 会自动 fallback 至 NetworkManager 从 DHCP 动态获取的局域网/校园网 DNS，
  #    确保校园网自动跳转登录页面秒级唤醒，登录成功外网恢复后秒级切回 DoH。
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    resolveLocalQueries = false;
    settings = {
      bind-dynamic = true;
      listen-address = "127.0.0.1";
      cache-size = 10000;
      no-negcache = true;
      strict-order = true; # 严格按顺序查询：首选 127.0.0.1#5335 (DoH)，超时故障时自动回退后续服务器

      # 队列首部：本地 SmartDNS DoH
      server = [
        "127.0.0.1#5335"
      ]
      ++ lib.optionals config.services.tailscale.enable [
        "/ts/100.100.100.100@tailscale0"
      ]
      ++ lib.optionals config.services.easytierMesh.enable [
        "/et/${config.services.easytierMesh.dnsServer}@${config.services.easytierMesh.devName}"
      ];

      # 若启用 NetworkManager（桌面/笔记本客户端环境），动态加载 DHCP 获得的校园网/局域网 DNS 文件作为 Fallback，并实时监听其变更
      no-poll = !config.networking.networkmanager.enable;
      no-resolv = !config.networking.networkmanager.enable;
    }
    // lib.optionalAttrs config.networking.networkmanager.enable {
      resolv-file = "/run/NetworkManager/resolv.conf";
    };
  };

  networking = {
    nameservers = [ "127.0.0.1" ];
    resolvconf.enable = false;
  };

  environment.etc."resolv.conf".text = ''
    ${
      if config.services.dnsmasq.enable then
        "nameserver 127.0.0.1"
      else
        "nameserver 1.1.1.1\n    nameserver 1.0.0.1"
    }
    search ${lib.concatStringsSep " " config.networking.search}
    options edns0
  '';

  # Prefer IPv4 when both address families are available.
  environment.etc."gai.conf".text = ''
    label  ::1/128       0
    label  ::ffff:0:0/96 1
    label  ::/0          2
    label  2002::/16     3
    label  ::/96         4
    precedence  ::1/128       50
    precedence  ::ffff:0:0/96  100
    precedence  ::/0          40
    precedence  2002::/16     30
    precedence  ::/96         20
  '';
}
