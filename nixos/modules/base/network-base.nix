{
  config,
  lib,
  ...
}:
let
  dn42Domain =
    if config.services ? dn42 && config.services.dn42 ? domain then
      config.services.dn42.domain
    else
      "dora.dn42";
in
{
  services.resolved.enable = false;

  # ── 1. SmartDNS 本地 DoH 客户端 ──────────────────────────────
  # 作为全系统的高性能安全 DNS 递归客户端，专门处理上游 DoH (DNS over HTTPS)
  # 监听本地 127.0.0.1:5335，不向局域网暴露。
  # 国内外机器通用：全并发向上游发起测速查询，哪个最快采用哪个。
  # 国外机器 1.1.1.1/8.8.8.8 秒级直出纯净结果；国内机器 223.5.5.5/doh.pub 秒级响应彻底避免超时卡死。
  services.smartdns = {
    enable = true;
    bindPort = 5335;
    settings = {
      bind = "127.0.0.1:5335";

      # 上游主用 DoH 服务器（全量并发竞速，不设 -fallback，谁快用谁）
      server-https = [
        "https://1.1.1.1/dns-query"
        "https://8.8.8.8/dns-query"
        "https://223.5.5.5/dns-query"
        "https://doh.pub/dns-query"
      ];

      # 普通上游服务器（全量并发竞速，专网分组独立隔离）
      server = [
        "1.1.1.1"
        "8.8.8.8"
        "223.5.5.5"
        "119.29.29.29"
        # ── DN42 专网解析上游 ──
        # dora.dn42: 优先自建 CoreDNS 权威 (172.20.232.1)，超时回退 Anycast
        # *.dn42: 官方 Anycast 根与递归服务器 (172.20.0.53 / 172.23.0.53)
        "172.20.232.1 -group dn42-auth -exclude-default-group"
        "172.20.0.53 -group dn42 -exclude-default-group"
        "172.23.0.53 -group dn42 -exclude-default-group"
      ]
      ++ lib.optionals config.services.tailscale.enable [
        # ── Tailscale MagicDNS 上游 ──
        "100.100.100.100 -group tailscale -exclude-default-group"
      ];

      nameserver = [
        "/${dn42Domain}/dn42-auth"
        "/${dn42Domain}/dn42"
        "/dn42/dn42"
      ]
      ++ lib.optionals config.services.tailscale.enable [
        "/ts/tailscale"
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
  # 1. 优先（队列首部）：通过 127.0.0.1#5335 走 SmartDNS 并发纯净/极速解析；
  # 2. 内部域名分流：dora.dn42 走自建+Anycast，*.dn42 走 Anycast，*.ts 走 Tailscale MagicDNS，*.et 走 EasyTier；
  # 3. 降级 Fallback：当处于校园网/酒店 Wi-Fi 强制 Web 认证门户（Captive Portal）等未登录断网环境时，
  #    自动 fallback 至 NetworkManager 从 DHCP 动态获取的局域网/校园网 DNS。
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    resolveLocalQueries = false;
    settings = {
      bind-dynamic = true;
      listen-address = "127.0.0.1";
      cache-size = 10000;
      no-negcache = true;
      strict-order = false; # 并发/自适应最优响应，不再机械等待单一节点超时阻断网络

      # 队列首部：本地 SmartDNS DoH
      server = [
        "127.0.0.1#5335"
        "/${dn42Domain}/172.20.232.1"
        "/${dn42Domain}/172.20.0.53"
        "/dn42/172.20.0.53"
        "/dn42/172.23.0.53"
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
