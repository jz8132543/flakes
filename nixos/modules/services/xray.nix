{
  needProxy ? false,
  proxyHosts ? [
    "nue0.dora.im"
    "tyo0.dora.im"
  ],
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # 端口定义
  xrayPort = 8555;
  tune = config.environment.networkTune;
  isBerserk = tune.profile == "berserk";
  connBudgetRam = tune.ram * (if isBerserk then 20 else 10);
  connBudgetCpu = tune.cpus * (if isBerserk then 18000 else 7000);
  connBudgetBw = tune.realBandwidth * (if isBerserk then 60 else 24);
  stableConnBudget = lib.max 4096 (
    lib.min 600000 (lib.min connBudgetRam (lib.min connBudgetCpu connBudgetBw))
  );
  xrayLimitNOFILE = lib.max 131072 (lib.min 1048576 (stableConnBudget * 4));
  fakeSnis = [
    "gateway.icloud.com"
    # "www.apple.com"
    # "images.apple.com"
    # "appleid.apple.com"
    # "swcdn.apple.com"
    # "speedtest.cn"
    # "speedtest.net"
  ];
  serverName = builtins.head fakeSnis;
  destSite = "${serverName}:443";
in
{
  sops.secrets = {
    "xray/uuid" = {
      mode = "0444";
    };
    "xray/private_key" = {
      mode = "0444";
    };
    "xray/short_id" = {
      mode = "0444";
    };
    "xray/cf_tunnel_token" = {
      mode = "0444";
    };
    "xray/public_key" = {
      mode = "0444";
    };
  };
  # 2. 使用 Template 动态生成 config.json
  # 这样生成的配置文件位于 /run/secrets/rendered/，不会进入 nix store
  sops.templates."xray-config.json" = {
    mode = "0444";
    restartUnits = [ "xray.service" ];
    content = builtins.toJSON {
      log = {
        loglevel = "warning";
      };

      observatory = {
        subjectSelector = [ "proxy-" ];
        probeURL = "https://cp.cloudflare.com/generate_204";
        probeInterval = "1m";
      };

      policy = lib.mkIf config.environment.minimal {
        system = {
          stats = {
            inboundUplink = false;
            inboundDownlink = false;
            outboundUplink = false;
            outboundDownlink = false;
          };
        };
      };

      inbounds = [
        {
          port = xrayPort;
          listen = "0.0.0.0";
          protocol = "vless";
          # tag = "vless_reality";
          # sniffing 必须放在 inbound 内（Xray v1.8+ 顶级 sniffing 被忽略）
          sniffing = {
            enabled = true;
            destOverride = [
              "http"
              "tls"
              "quic"
            ];
            routeOnly = true;
          };
          settings = {
            clients = [
              {
                # 这里的语法是 sops-nix template 的占位符
                id = config.sops.placeholder."xray/uuid";
                flow = "xtls-rprx-vision";
              }
            ];
            decryption = "none";
          };
          streamSettings = {
            network = "tcp";
            security = "reality";
            sockopt = {
              # 入站（国内客户端→本机）：保持 tcpFastOpen 关闭
              # 国内运营商/GFW 会丢弃/RST 带数据的 SYN 包，开启反而增加连接失败率
              # tcpFastOpen = true;
              mptcp = true;
              # 应用层 keepalive，解决运营商 NAT 30 分钟自动断开问题
              tcpKeepAliveInterval = 60;
            };
            realitySettings = {
              show = false;
              target = destSite;
              xver = 0;
              serverNames = [
                serverName
              ]
              ++ fakeSnis;
              privateKey = config.sops.placeholder."xray/private_key";
              shortIds = [ config.sops.placeholder."xray/short_id" ];
            };
          };
        }
      ];

      outbounds = [
        # 默认直连出口
        {
          tag = "direct";
          protocol = "freedom";
        }
      ]
      ++ (lib.imap0 (i: host: {
        tag = "proxy-${toString i}";
        protocol = "vless";
        settings = {
          vnext = [
            {
              address = host; # 替换为 Server B 的真实 IP
              port = 8555; # Server B 的监听端口
              users = [
                {
                  # 这里填 Server B 认可的 UUID
                  # 如果 A 和 B 共享同一个 secrets 文件，可以用同一个 placeholder
                  id = config.sops.placeholder."xray/uuid";
                  flow = "xtls-rprx-vision"; # 必须保留，以支持 Vision 流控
                  encryption = "none";
                }
              ];
            }
          ];
        };
        streamSettings = {
          network = "tcp";
          security = "reality";
          sockopt = {
            # 出站（本机→境外服务器）：开启 TFO 降低首包延迟（目标在境外，运营商干扰少）
            tcpFastOpen = true;
            # 禁用 Nagle 算法，有数据立刻转发，降低协议延迟（与内核 tcp_autocorking=0 协同）
            tcpNoDelay = true;
            mptcp = true;
            tcpKeepAliveInterval = 60;
          };
          realitySettings = {
            # iOS 指纺，模拟 iPhone/iPad 的 TLS 行为，比 chrome 更难被识别
            fingerprint = "ios";

            # 必须与 Server B inbound 中的 serverNames 保持一致
            serverName = builtins.head fakeSnis;

            # ⚠️ 重要：这里必须填 Server B 的『公鑰 Public Key』
            publicKey = config.sops.placeholder."xray/public_key";

            # 必须与 Server B inbound 中的 shortIds 保持一致
            shortId = config.sops.placeholder."xray/short_id";
          };
        };
      }) proxyHosts)
      ++ [
        {
          tag = "cf-tunnel";
          protocol = "wireguard";
          settings = {
            secretKey = config.sops.placeholder."xray/cf_tunnel_token";
            address = [
              # "162.159.192.10/32"
              # "2606:4700:d0::a29f:c00a/128"
              "172.16.0.2/32"
              "2606:4700:110:8ac0:1f3:b49f:5181:3855/128"
            ];
            peers = [
              {
                publicKey = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
                allowedIPs = [
                  "0.0.0.0/0"
                  "::/0"
                ];
                endpoint = "engage.cloudflareclient.com:2408";
              }
            ];
            reserved = [
              18
              11
              127
            ];
            mtu = 1280;
            # kernelMode = true;
          };
        }
        # 阻断出口
        {
          tag = "block";
          protocol = "blackhole";
        }
      ];

      routing = {
        domainStrategy = "IPIfNonMatch";
        balancers = [
          {
            tag = "proxy-balancer";
            selector = [ "proxy-" ];
            strategy = {
              type = "leastPing";
            };
          }
        ];
        rules = [
          # 规则：Copilot 和 OpenAI 流量走 Proxy
          (
            if needProxy then
              {
                type = "field";
                balancerTag = "proxy-balancer";
                domain = [
                  "skk.moe"
                  "geosite:category-ai-!cn"
                ];
              }
            else
              {
                type = "field";
                outboundTag = "direct";
                network = "udp,tcp";
              }
          )
          # 规则：屏蔽广告
          {
            type = "field";
            outboundTag = "block";
            domain = [ "geosite:category-ads-all" ];
          }
          # 规则：默认直连
          {
            type = "field";
            outboundTag = "direct";
            network = "udp,tcp";
          }
        ];
      };
    };
  };

  # 3. 启动 Xray 服务并指向生成的配置文件
  services.xray = {
    enable = true;
    # 这一步至关重要，让 systemd 使用 sops 渲染后的文件
    settingsFile = config.sops.templates."xray-config.json".path;
  };

  # 确保 Xray 能读到 geo 数据库
  systemd.services.xray = {
    serviceConfig = {
      # 让 xray 的 fd 上限跟随稳定连接预算，避免用户态先于内核变瓶颈。
      LimitNOFILE = xrayLimitNOFILE;
      # 进程退出后持续自动重启（包括 exit）。
      Restart = "always";
      RestartSec = "2s";
    };
    environment =
      let
        assets = pkgs.symlinkJoin {
          name = "v2ray-assets";
          paths = with pkgs; [
            v2ray-geoip
            v2ray-domain-list-community
          ];
        };
      in
      {
        V2RAY_LOCATION_ASSET = "${assets}/share/v2ray";
        XRAY_LOCATION_ASSET = "${assets}/share/v2ray";
      };
  };
  networking.firewall.allowedTCPPorts = [
    8443
    8444
    8555
  ];
  networking.firewall.allowedUDPPorts = [
    8443
    8444
    8555
  ];
}
