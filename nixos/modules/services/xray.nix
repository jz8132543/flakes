{
  needProxy ? false,
  xrayPort ? 8555,
  proxyHosts ? [
    "nue0.dora.im"
    "tyo0.dora.im"
  ],
  serverName ? "gateway.icloud.com",
  ss ? false,
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  destSite = "${serverName}:443";
  useHealthCheckedBalancer = needProxy && builtins.length proxyHosts > 1;
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
    content = builtins.toJSON (
      {
        log = {
          # access = "console";
          # error = "console";
          # dnsLog = false;
          # loglevel = "debug";
        };

        inbounds =
          if ss then
            [
              {
                port = xrayPort;
                listen = "0.0.0.0";
                protocol = "shadowsocks";
                settings = {
                  method = "2022-blake3-aes-128-gcm";
                  password = config.sops.placeholder."xray/uuid";
                };
              }
            ]
          else
            [
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
                      id = config.sops.placeholder."xray/uuid";
                    }
                  ];
                  decryption = "none";
                };
                streamSettings = {
                  network = "xhttp";
                  security = "reality";
                  xhttpSettings = {
                    mode = "auto"; # 服务端推荐 auto，自适应客户端握手
                    host = serverName;
                    path = "/";
                  };
                  realitySettings = {
                    show = false;
                    target = destSite;
                    xver = 0;
                    serverNames = [ serverName ];
                    privateKey = config.sops.placeholder."xray/private_key";
                    shortIds = [ config.sops.placeholder."xray/short_id" ];
                  };
                };
              }
            ];

        outbounds = [
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
                address = host;
                port = 8555;
                users = [
                  {
                    id = config.sops.placeholder."xray/uuid";
                    encryption = "none";
                  }
                ];
              }
            ];
          };
          streamSettings = {
            network = "xhttp";
            security = "reality";
            xhttpSettings = {
              mode = "packet-up"; # 核心：上传打碎成短请求，下载保持长连接，对抗流量分析
              host = serverName;
              path = "/";
            };
            realitySettings = {
              fingerprint = "ios";
              inherit serverName;
              publicKey = config.sops.placeholder."xray/public_key";
              shortId = config.sops.placeholder."xray/short_id";
              alpn = [ "h3" ];
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
            };
          }
          {
            tag = "block";
            protocol = "blackhole";
          }
        ];

        routing = {
          domainStrategy = "IPIfNonMatch";
          balancers = lib.optionals needProxy [
            {
              tag = "proxy-balancer";
              selector = [ "proxy-" ];
              strategy = {
                type = if useHealthCheckedBalancer then "leastPing" else "random";
              };
            }
          ];
          rules = [
            (
              if needProxy then
                {
                  type = "field";
                  balancerTag = "proxy-balancer";
                  domain = [
                    "skk.moe"
                    "geosite:openai"
                    "geosite:anthropic"
                    "domain:chatgpt.com"
                    "domain:oaistatic.com"
                    "domain:oaiusercontent.com"
                    "domain:claude.ai"
                    "domain:anthropic.com"
                  ];
                }
              else
                {
                  type = "field";
                  outboundTag = "direct";
                  network = "udp,tcp";
                }
            )
            {
              type = "field";
              outboundTag = "block";
              domain = [ "geosite:category-ads-all" ];
            }
            {
              type = "field";
              outboundTag = "direct";
              network = "udp,tcp";
            }
          ];
        };
      }
      // lib.optionalAttrs useHealthCheckedBalancer {
        observatory = {
          subjectSelector = [ "proxy-" ];
          probeURL = "https://cp.cloudflare.com/generate_204";
          probeInterval = "1m";
        };
      }
    );
  };

  # 3. 启动 Xray 服务并指向生成的配置文件
  services.xray = {
    enable = true;
    # 这一步至关重要，让 systemd 使用 sops 渲染后的文件
    settingsFile = config.sops.templates."xray-config.json".path;
  };

  # services.traefik.tcpProxies = {
  services.traefik.dynamicConfigOptions.tcp = {
    routers.xray = {
      entryPoints = [
        "https"
        "https-alt"
      ];
      service = "xray";
      tls.passthrough = true;
      rule = "HostSNI(`${serverName}`)";
    };

    services.xray.loadbalancer.servers = [ { address = "127.0.0.1:${toString xrayPort}"; } ];
    # xray = {
    #   rule = "HostSNI(`" + serverName + "`)";
    #   target = "127.0.0.1:${toString xrayPort}";
    #   tls.passthrough = true;
    #   entryPoints = [
    #     "https"
    #     "https-alt"
    #   ];
    #   # tls = true;
    # };
  };

  # 确保 Xray 能读到 geo 数据库
  systemd.services.xray = {
    startLimitIntervalSec = lib.mkForce 0;
    serviceConfig = {
      # 让 xray 的 fd 上限跟随稳定连接预算，避免用户态先于内核变瓶颈。
      # LimitNOFILE = xrayLimitNOFILE;
      # 进程失败或被 OOM 杀死后自动重启（正常退出不重启）。
      Restart = lib.mkForce "on-failure";
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
    xrayPort
  ];
  networking.firewall.allowedUDPPorts = [
    8443
    8444
    xrayPort
  ];
}
