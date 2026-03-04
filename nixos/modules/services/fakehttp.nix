{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.fakehttp;
in
{
  # ─────────────────────────────────────────────────────────────────────────
  # services.fakehttp
  #
  # 原理：TCP 三次握手完成后，用极低 TTL 发送一个伪造 HTTP GET 包，
  #       Host 字段填写运营商白名单内的测速域名（如 www.speedtest.cn）。
  #       该包 TTL 耗尽后在运营商 DPI 路由处被丢弃，目标服务器收不到，
  #       但 ISP 已见到"合法 HTTP 请求"并解除对该连接的限速。
  #
  # 仅适用于从本机"发出"的出站连接（-1 模式）。
  # 如要对"入站"连接解限速，需在对端（用户侧路由器）运行，而非服务器。
  # ─────────────────────────────────────────────────────────────────────────

  options.services.fakehttp = {
    enable = lib.mkEnableOption "FakeHTTP ISP whitelist QoS bypass";

    httpHost = lib.mkOption {
      type = lib.types.str;
      default = "www.speedtest.cn";
      description = ''
        用于 HTTP 混淆的白名单域名（DPI 检测 Host 字段）。
        - 电信/移动：www.speedtest.cn（最常见）
        - 江苏联通：speedtest.jsinfo.net（联通自营测速域名）
        建议通过 nexttrace/mtr 确认 ISP QoS 路由跳数后再调整 ttl。
      '';
    };

    httpsHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        用于 HTTPS/TLS ClientHello SNI 混淆的白名单域名（TCP 443 端口有效）。
        null 表示不启用 HTTPS 混淆，仅使用 HTTP 混淆。
      '';
    };

    ttl = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        伪造包的 TTL 值。null 表示使用 FakeHTTP 自动估算（推荐）。
        如需手动指定：用 nexttrace / mtr 追踪路由，找到 ISP DPI 路由所在跳数。
        一般地市级：3；省级：4；骨干网：5-6。
      '';
    };

    repeat = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = ''
        重复发送伪造包的次数（-r 参数）。
        部分情况下单次发送不一定命中所有 DPI 节点，增加到 2-3 可提高成功率。
      '';
    };

    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        只作用于指定的网络接口。null 表示作用于所有接口（-a）。
        建议指定 WAN 口，如 eth0，避免干扰 loopback 和内网流量。
      '';
    };

    ipv4Only = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        仅处理 IPv4 连接（推荐）。
        IPv6 方向的 ISP QoS 策略通常与 IPv4 不同，混淆不当可能影响连通性。
      '';
    };

    payloadFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        用于混淆的自定义二进制 payload 文件路径（-b 参数）。
        如果设置了此项，将使用该文件中的原始内容作为 TCP 混淆负载，
        这通常比单纯设置 -h 域名更难被运营商识别（可以使用 Wireshark 抓取真实请求导出）。
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "传递给 fakehttp 的额外命令行参数。";
    };
  };

  config = lib.mkIf cfg.enable {
    # FakeHTTP 使用 nftables NFQUEUE，确保 nftables 已启用
    networking.nftables.enable = lib.mkDefault true;

    # 加载 nfqueue 内核模块（FakeHTTP 依赖）
    boot.kernelModules = [ "nfnetlink_queue" ];

    systemd.services.fakehttp = {
      description = "FakeHTTP — ISP whitelist QoS bypass via HTTP obfuscation";
      documentation = [ "https://github.com/MikeWang000000/FakeHTTP" ];

      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "forking";
        # FakeHTTP 以守护进程模式运行（-d），自行 fork 后台
        ExecStart = lib.concatStringsSep " " (
          [
            "${pkgs.fakehttp}/bin/fakehttp"
            "-d" # 守护进程模式
            "-s" # 静默（日志写 journald 即可）
          ]
          ++ (if cfg.interface != null then [ "-i ${lib.escapeShellArg cfg.interface}" ] else [ "-a" ])
          ++ (lib.optional cfg.ipv4Only "-4")
          ++ [ "-1" ] # 出站方向
          ++ (
            if cfg.payloadFile != null then
              [ "-b ${lib.escapeShellArg (toString cfg.payloadFile)}" ]
            else
              [ "-h ${lib.escapeShellArg cfg.httpHost}" ]
          )
          ++ (lib.optional (cfg.httpsHost != null) "-e ${lib.escapeShellArg cfg.httpsHost}")
          ++ (lib.optional (cfg.ttl != null) "-t ${toString cfg.ttl}")
          ++ [ "-r ${toString cfg.repeat}" ]
          ++ cfg.extraArgs
        );
        # 停止时清理防火墙规则
        ExecStop = "${pkgs.fakehttp}/bin/fakehttp -k";
        Restart = "on-failure";
        RestartSec = "5s";
        # 需要 CAP_NET_ADMIN 来操作 nftables/iptables 及 NFQUEUE
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
        # 基础沙箱（不能用 PrivateNetwork，否则无法操作 netfilter）
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
  };
}
