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
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "FakeHTTP ISP whitelist QoS bypass";
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
      default = false;
      description = ''
        仅处理 IPv4 连接（推荐）。
        IPv6 方向的 ISP QoS 策略通常与 IPv4 不同，混淆不当可能影响连通性。
      '';
    };

    payloadFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "自定义二进制 payload 文件路径。一般建议使用 domainPool。";
    };

    domainPool = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # 字节/抖音系
        "creator.douyin.com"
        "p3-pc-sign.douyinpic.com"
        # 腾讯系
        "cloud.tencent.com"
        "www.weiyun.com"
        # B站
        "upos-sz-mirrorcos.bilivideo.com"
        "member.bilibili.com"
        "i0.hdslb.com"
        # 阿里系/其他网盘类
        "www.aliyundrive.com"
        "pan.quark.cn"
        "www.123pan.com"
        "pan.xunlei.com"
        "www.jianguoyun.com"
        "www.lanzoui.com"
        # 百度系
        "vd3.bdstatic.com"
        # 公共测速/教育网测试
        "www.speedtest.cn"
        "www.speedtest.net"
        "test.ustc.edu.cn"
        "speed.cloudflare.com"
        "fast.com"
      ];
      description = ''
        需要进行混淆的域名池。
        系统会在服务启动时使用 Python 的 SSL 模块自动捕获真实 TLS ClientHello，
        并生成带完整 Header 的 HTTP GET 请求，通过多个 -b 参数加载进 FakeHTTP。
        内置白名单剔除了运营商专有域名。
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

      path = [
        pkgs.netcat-gnu
        pkgs.openssl
        pkgs.coreutils
        pkgs.gnused
        pkgs.iptables
        pkgs.nftables
        pkgs.python3
      ];

      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      preStart = lib.mkIf (cfg.domainPool != [ ]) ''
        # ── 初始化目录，清理旧文件 ────────────────────────────────────────────
        mkdir -p /var/lib/fakehttp
        rm -f /var/lib/fakehttp/*.bin

        domains=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.domainPool)})

        cat <<'EOF' > /var/lib/fakehttp/generate_payloads.py
        import socket
        import ssl
        import threading
        import sys
        import os
        import time

        domains = sys.argv[1:]
        out_dir = "/var/lib/fakehttp"

        for domain in domains:
            # 1. HTTP Payload
            http_payload = f"GET / HTTP/1.1\r\nHost: {domain}\r\nConnection: close\r\n\r\n"
            with open(os.path.join(out_dir, f"http_{domain}.bin"), "wb") as f:
                f.write(http_payload.encode("utf-8"))

            # 2. TLS Payload Capture
            def dummy_server(port, result_box):
                try:
                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                        s.bind(('127.0.0.1', port))
                        s.listen(1)
                        s.settimeout(2.0)
                        conn, addr = s.accept()
                        with conn:
                            conn.settimeout(2.0)
                            data = conn.recv(4096)
                            if data:
                                result_box.append(data)
                except Exception as e:
                    pass

            for attempt in range(5):
                # find free port
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.bind(("", 0))
                    port = s.getsockname()[1]

                result_box = []
                server_thread = threading.Thread(target=dummy_server, args=(port, result_box))
                server_thread.start()

                time.sleep(0.1) # wait for server to listen

                try:
                    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                    context.maximum_version = ssl.TLSVersion.TLSv1_2
                    context.options |= ssl.OP_NO_TICKET
                    context.check_hostname = False
                    context.verify_mode = ssl.CERT_NONE
                    with socket.create_connection(('127.0.0.1', port), timeout=2.0) as sock:
                        with context.wrap_socket(sock, server_hostname=domain) as ssock:
                            pass
                except Exception as e:
                    # Expected to fail since dummy server doesn't complete SSL handshake
                    pass

                server_thread.join(timeout=3.0)

                if result_box and len(result_box[0]) > 0:
                    payload = result_box[0]
                    if len(payload) > 1200:
                        print(f"WARNING: Captured TLS ClientHello for {domain} is too large ({len(payload)} bytes > 1200), discarding.")
                        break # Skip this domain

                    with open(os.path.join(out_dir, f"tls_{domain}.bin"), "wb") as f:
                        f.write(payload)
                    print(f"Captured TLS ClientHello for {domain} ({len(payload)} bytes)")
                    break
                else:
                    print(f"TLS capture empty for {domain}, retry {attempt+1}/5...")
                    time.sleep(0.5)
            else:
                print(f"WARNING: Failed to capture TLS ClientHello for {domain} after 5 attempts, skipping.")

        EOF

        python3 /var/lib/fakehttp/generate_payloads.py "''${domains[@]}"

        # ── 汇总 ─────────────────────────────────────────────────────────────
        http_count=$(ls /var/lib/fakehttp/http_*.bin 2>/dev/null | wc -l)
        tls_count=$(ls /var/lib/fakehttp/tls_*.bin 2>/dev/null | wc -l)
        echo "Payload generation done: $http_count HTTP, $tls_count TLS payload(s) ready."
      '';

      serviceConfig = {
        StateDirectory = "fakehttp";
        StateDirectoryMode = "0755";
        Type = "simple";
        # 动态根据成功获取到的 payload 文件生成命令行参数
        # 调试模式：不带 -d，不带 -s，输出最终拼接的命令
        ExecStart = toString (
          pkgs.writeShellScript "start-fakehttp" ''
            args=(
              "${pkgs.fakehttp}/bin/fakehttp"
              "-s"
              # "-d" # 调试期间不进入后台
            )
            ${lib.optionalString (cfg.interface != null) ''args+=("-i" ${lib.escapeShellArg cfg.interface})''}
            ${lib.optionalString (cfg.interface == null) ''args+=("-a")''}
            ${lib.optionalString cfg.ipv4Only ''args+=("-4")''}
            args+=("-1" "-0")

            target_dir="/var/lib/fakehttp"
            if [ -d "$target_dir" ]; then
              for f in "$target_dir"/tls_*.bin; do
                [ -e "$f" ] || continue
                domain=''${f#*tls_}
                domain=''${domain%.bin}
                echo "Found TLS payload for $domain"
                args+=("-b" "$f" "-e" "$domain")
              done
              for f in "$target_dir"/http_*.bin; do
                [ -e "$f" ] || continue
                domain=''${f#*http_}
                domain=''${domain%.bin}
                echo "Found HTTP payload for $domain"
                args+=("-b" "$f" "-h" "$domain")
              done
            fi

            ${lib.optionalString (
              cfg.payloadFile != null
            ) ''args+=("-b" ${lib.escapeShellArg (toString cfg.payloadFile)})''}
            ${lib.optionalString (cfg.ttl != null) ''args+=("-t" ${lib.escapeShellArg (toString cfg.ttl)})''}
            args+=("-r" ${lib.escapeShellArg (toString cfg.repeat)})

            ${lib.concatMapStrings (arg: ''
              args+=( ${lib.escapeShellArg arg} )
            '') cfg.extraArgs}

            echo "Final command: ''${args[*]}"
            exec "''${args[@]}"
          ''
        );
        # 停止时清理防火墙规则
        ExecStop = "${pkgs.fakehttp}/bin/fakehttp -k";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "5min";
        # 需要 CAP_NET_ADMIN 来操作 nftables/iptables 及 NFQUEUE
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
          "CAP_SYS_NICE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
          "CAP_SYS_NICE"
        ];
        # 基础沙箱（不能用 PrivateNetwork，否则无法操作 netfilter）
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
  };
}
