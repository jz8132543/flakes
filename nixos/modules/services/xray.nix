{
  needProxy ? false,
  proxyHost ? "127.0.0.1",
}:
{
  config,
  pkgs,
  ...
}:

let
  # 端口定义
  xrayPort = 8555;
  destSite = "${config.networking.fqdn}:443";
  serverName = config.networking.fqdn;
  fakeSnis = [
    "gateway.icloud.com"
    "www.apple.com"
    "images.apple.com"
    "appleid.apple.com"
    "swcdn.apple.com"
    "speedtest.cn"
    "speedtest.net"
  ];
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
      sniffing = {
        enabled = true;
        destOverride = [
          "http"
          "tls"
          "quic"
        ];
        routeOnly = true;
      };

      inbounds = [
        {
          port = xrayPort;
          listen = "0.0.0.0";
          protocol = "vless";
          # tag = "vless_reality";
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
              # 开启 TCP Fast Open，减少首次连接建立时的一个 RTT
              # tcpFastOpen = true;
              # 开启 MPTCP
              mptcp = true;
              # 应用层 keepalive，60s 探测一次，让内核 SO_KEEPALIVE 真正生效
              # 解决运营商 NAT 超时（卷 30分钟自动断开）
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
        {
          tag = "proxy";
          protocol = "vless";
          settings = {
            vnext = [
              {
                address = proxyHost; # 替换为 Server B 的真实 IP
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
              # tcpFastOpen = true;
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
        }
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
        rules = [
          # 规则：Copilot 和 OpenAI 流量走 Proxy
          (
            if needProxy then
              {
                type = "field";
                outboundTag = "proxy";
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
