{
  needProxy ? false,
  xrayPort ? 8555,
  proxyHosts ? [
    "fra0.dora.im"
    "tyo0.dora.im"
    "sjc0.dora.im"
  ],
  serverName ? "speedtest.dora.im",
  core ? "xray",
  xhttpPath ? "/speedtest",
  xhttpMode ? "stream-one",
  xPaddingBytes ? "100-1000",
  xPaddingObfsMode ? true,
  xPaddingPlacement ? "header",
  xPaddingHeader ? "X-Padding",
  xPaddingMethod ? "repeat-x",
  healthCheckUrl ? "https://speedtest.dora.im/generate_204",
  ss ? false,
  socks ? true,
  socksPort ? 1080,
}:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  isXray = core == "xray";
  primaryTag = if ss then "ss-in" else "vless-in";
  useHealthCheckedBalancer = needProxy && builtins.length proxyHosts > 1;
  selfData = config.lib.self.data or (lib.importJSON ../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };
  ownDn42Ipv4 = config.services.dn42.ipv4 or dn42Data.ipv4 or "172.20.232.0/26";
  ownDn42Ipv6 = config.services.dn42.ipv6 or dn42Data.ipv6 or "fd53:90fd:4bb6::/48";

  # 将 IPv4 CIDR 动态转换为对应双栈 socket 下的 IPv4-mapped IPv6 CIDR（掩码 + 96）
  toMappedV6 =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      ip = lib.elemAt parts 0;
    in
    if builtins.length parts == 2 then
      "::ffff:${ip}/${toString ((lib.toInt (lib.elemAt parts 1)) + 96)}"
    else
      "::ffff:${ip}/128";

  ownDn42Ipv4Mapped = toMappedV6 ownDn42Ipv4;
  socksSources = [
    ownDn42Ipv4
    ownDn42Ipv6
    "127.0.0.0/8"
    "::1/128"
  ];
  # Xray normalizes mapped addresses to IPv4 and rejects mapped CIDR masks > 32.
  singBoxSocksSources = socksSources ++ [
    ownDn42Ipv4Mapped
    (toMappedV6 "127.0.0.0/8")
  ];
  proxyDomains = [
    "skk.moe"
    "openai.com"
    "chatgpt.com"
    "oaistatic.com"
    "oaiusercontent.com"
    "claude.ai"
    "anthropic.com"
  ];
  proxyRoute =
    if useHealthCheckedBalancer then
      { balancerTag = "proxy-balancer"; }
    else
      { outboundTag = "proxy-0"; };
  xhttpSettings = {
    host = serverName;
    path = xhttpPath;
    mode = xhttpMode;
    # Mihomo does not fill Xray's obfs-mode defaults; use explicit shared values.
    extra = {
      inherit
        xPaddingBytes
        xPaddingObfsMode
        xPaddingPlacement
        xPaddingHeader
        xPaddingMethod
        ;
    };
  };
  xrayConfig = {
    log.loglevel = if config.environment.minimal or false then "warning" else "info";
    inbounds = [
      (
        if ss then
          {
            tag = primaryTag;
            listen = "::";
            port = xrayPort;
            protocol = "shadowsocks";
            settings = {
              method = "2022-blake3-aes-128-gcm";
              password = config.sops.placeholder."xray/uuid";
              network = "tcp,udp";
            };
          }
        else
          {
            tag = primaryTag;
            listen = "::";
            port = xrayPort;
            protocol = "vless";
            settings = {
              clients = [ { id = config.sops.placeholder."xray/uuid"; } ];
              decryption = "none";
            };
            streamSettings = {
              network = "xhttp";
              security = "reality";
              inherit xhttpSettings;
              realitySettings = {
                target = "${serverName}:443";
                serverNames = [ serverName ];
                privateKey = config.sops.placeholder."xray/private_key";
                shortIds = [ config.sops.placeholder."xray/short_id" ];
              };
            };
          }
      )
    ]
    ++ lib.optionals socks [
      {
        tag = "socks-in";
        listen = "::";
        port = socksPort;
        protocol = "socks";
        settings = {
          auth = "noauth";
          udp = true;
        };
      }
    ];
    outbounds = [
      {
        tag = "direct";
        protocol = "freedom";
      }
      {
        tag = "block";
        protocol = "blackhole";
      }
    ]
    ++ lib.optionals needProxy (
      lib.imap0 (i: host: {
        tag = "proxy-${toString i}";
        protocol = "vless";
        settings = {
          address = host;
          port = 8555;
          id = config.sops.placeholder."xray/uuid";
          encryption = "none";
        };
        streamSettings = {
          network = "xhttp";
          security = "reality";
          inherit xhttpSettings;
          realitySettings = {
            inherit serverName;
            fingerprint = "chrome";
            password = config.sops.placeholder."xray/public_key";
            shortId = config.sops.placeholder."xray/short_id";
          };
        };
      }) proxyHosts
    );
    routing = {
      domainStrategy = "AsIs";
      # Only authorized SOCKS sources may reach either proxy or direct routes.
      rules =
        lib.optionals needProxy (
          [
            (
              {
                type = "field";
                inboundTag = [ primaryTag ];
                domain = map (domain: "domain:${domain}") proxyDomains;
              }
              // proxyRoute
            )
          ]
          ++ lib.optionals socks [
            (
              {
                type = "field";
                inboundTag = [ "socks-in" ];
                source = socksSources;
                domain = map (domain: "domain:${domain}") proxyDomains;
              }
              // proxyRoute
            )
          ]
        )
        ++ lib.optionals socks [
          {
            type = "field";
            inboundTag = [ "socks-in" ];
            source = socksSources;
            outboundTag = "direct";
          }
          {
            type = "field";
            inboundTag = [ "socks-in" ];
            outboundTag = "block";
          }
        ];
    }
    // lib.optionalAttrs useHealthCheckedBalancer {
      balancers = [
        {
          tag = "proxy-balancer";
          selector = [ "proxy-" ];
          strategy.type = "leastPing";
          # Do not bypass the requested proxy route when every relay is down.
          fallbackTag = "block";
        }
      ];
    };
  }
  // lib.optionalAttrs useHealthCheckedBalancer {
    observatory = {
      subjectSelector = [ "proxy-" ];
      probeUrl = healthCheckUrl;
      probeInterval = "1m";
      enableConcurrency = true;
    };
  };
in
{
  assertions = [
    {
      assertion = lib.elem core [
        "xray"
        "sing-box"
      ];
      message = "xray.nix: core must be xray or sing-box";
    }
    {
      assertion = !isXray || lib.versionAtLeast config.services.xray.package.version "26.11.9";
      message = "xray.nix: REALITY requires Xray 26.11.9 or later";
    }
    {
      assertion = !needProxy || proxyHosts != [ ];
      message = "xray.nix: needProxy requires at least one proxy host";
    }
    {
      assertion = lib.elem xhttpMode [
        "stream-one"
        "stream-up"
        "packet-up"
      ];
      message = "xray.nix: unsupported XHTTP mode";
    }
    {
      assertion = lib.hasPrefix "/" xhttpPath;
      message = "xray.nix: XHTTP path must start with /";
    }
    {
      assertion = lib.hasPrefix "https://" healthCheckUrl;
      message = "xray.nix: health checks must use HTTPS";
    }
    {
      assertion = !socks || socksPort != xrayPort;
      message = "xray.nix: SOCKS and primary inbound ports must differ";
    }
  ];
  sops.secrets = {
    "xray/uuid" = {
      mode = "0400";
    };
    "xray/private_key" = {
      mode = "0400";
    };
    "xray/short_id" = {
      mode = "0400";
    };
    "xray/cf_tunnel_token" = {
      mode = "0400";
    };
    "xray/public_key" = {
      mode = "0400";
    };
  };

  sops.templates."xray-config.json" = lib.mkIf isXray {
    mode = "0400";
    restartUnits = [ "xray.service" ];
    content = builtins.toJSON xrayConfig;
  };

  # Rollback also requires the subscription transport to switch to TCP + Vision.
  # Templates contain only placeholders in the store; credentials are rendered at runtime.
  sops.templates."sing-box-config.json" = lib.mkIf (!isXray) {
    mode = "0400";
    restartUnits = [ "sing-box.service" ];
    content = builtins.toJSON {
      log = {
        disabled = false;
        level = if config.environment.minimal or false then "warn" else "info";
        timestamp = true;
      };

      inbounds =
        (
          if ss then
            [
              {
                type = "shadowsocks";
                tag = "ss-in";
                listen = "::";
                listen_port = xrayPort;
                method = "2022-blake3-aes-128-gcm";
                password = config.sops.placeholder."xray/uuid";
              }
            ]
          else
            [
              {
                type = "vless";
                tag = "vless-in";
                listen = "::";
                listen_port = xrayPort;
                users = [
                  {
                    name = "default";
                    uuid = config.sops.placeholder."xray/uuid";
                    flow = "xtls-rprx-vision";
                  }
                ];
                tls = {
                  enabled = true;
                  server_name = serverName;
                  reality = {
                    enabled = true;
                    handshake = {
                      server = serverName;
                      server_port = 443;
                    };
                    private_key = config.sops.placeholder."xray/private_key";
                    short_id = [
                      config.sops.placeholder."xray/short_id"
                    ];
                  };
                };
              }
            ]
        )
        ++ lib.optionals socks [
          {
            type = "socks";
            tag = "socks-in";
            listen = "::";
            listen_port = socksPort;
          }
        ];

      # 极致精简出站：纯 direct 直连，无冗余封装
      outbounds = [
        {
          type = "direct";
          tag = "direct";
        }
        {
          type = "block";
          tag = "block";
        }
      ]
      ++ lib.optionals needProxy (
        (lib.imap0 (i: host: {
          tag = "proxy-${toString i}";
          type = "vless";
          server = host;
          server_port = 8555;
          uuid = config.sops.placeholder."xray/uuid";
          flow = "xtls-rprx-vision";
          tls = {
            enabled = true;
            server_name = serverName;
            utls = {
              enabled = true;
              fingerprint = "chrome";
            };
            reality = {
              enabled = true;
              public_key = config.sops.placeholder."xray/public_key";
              short_id = config.sops.placeholder."xray/short_id";
            };
          };
        }) proxyHosts)
        ++ lib.optionals useHealthCheckedBalancer [
          {
            type = "urltest";
            tag = "proxy-balancer";
            outbounds = lib.imap0 (i: _: "proxy-${toString i}") proxyHosts;
            url = "https://cp.cloudflare.com/generate_204";
            interval = "1m";
          }
        ]
      );

      # 服务端路由优化：
      # 1. 严格限制 SOCKS5 仅允许本机及自身 DN42 段访问，非授权流量直接阻断
      # 2. 需要代理时仅使用纯内存前缀后缀匹配，不加载庞大的外部数据库
      route = {
        rules =
          (lib.optionals socks [
            {
              type = "logical";
              mode = "and";
              rules = [
                {
                  inbound = [ "socks-in" ];
                }
                {
                  invert = true;
                  source_ip_cidr = singBoxSocksSources;
                }
              ];
              outbound = "block";
            }
          ])
          ++ (lib.optionals needProxy [
            {
              domain_suffix = proxyDomains;
              outbound = if useHealthCheckedBalancer then "proxy-balancer" else "proxy-0";
            }
          ]);
        final = "direct";
      };
    };
  };

  services.xray = {
    enable = isXray;
    settingsFile = lib.mkIf isXray config.sops.templates."xray-config.json".path;
  };
  services.sing-box.enable = !isXray;

  # 4. 针对弱机（1CPU/256M 内存）深度调优 systemd 服务参数
  systemd.services.${core} = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    startLimitIntervalSec = lib.mkForce 0;
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "2s";
      MemoryMax = lib.mkDefault "192M";
      MemoryHigh = lib.mkDefault "150M";
      OOMScoreAdjust = lib.mkDefault (-500);
    }
    // lib.optionalAttrs (!isXray) {
      LoadCredential = "config.json:${config.sops.templates."sing-box-config.json".path}";
      ExecStart = lib.mkForce [
        ""
        "${lib.getExe config.services.sing-box.package} -D /var/lib/sing-box run -c \${CREDENTIALS_DIRECTORY}/config.json"
      ];
    };
    environment = {
      # 激进 GC 控制内存上限，避免低内存 VPS OOM
      GOGC = lib.mkDefault "50";
      GOMEMLIMIT = lib.mkDefault "128MiB";
    };
  };

  # 5. Traefik SNI Passthrough 保持对接
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
  };

  # 6. 定时重启
  systemd.timers = {
    proxy-restart = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        AccuracySec = "1s";
        Persistent = true;
      };
    };
  };
  systemd.services.proxy-restart = {
    description = "Trigger to restart proxy service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart ${core}.service";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      8443
      8444
      xrayPort
    ];
    allowedUDPPorts = [
      8443
      8444
      xrayPort
    ];
    # 针对 SOCKS5 服务实施网段级白名单：仅放行来自自身 DN42 网段与 Loopback 的访问
    extraCommands = lib.mkIf (socks && !config.networking.nftables.enable) ''
      iptables -A nixos-fw -p tcp --dport ${toString socksPort} -s ${ownDn42Ipv4} -j nixos-fw-accept 2>/dev/null || true
      iptables -A nixos-fw -p udp --dport ${toString socksPort} -s ${ownDn42Ipv4} -j nixos-fw-accept 2>/dev/null || true
      ip6tables -A nixos-fw -p tcp --dport ${toString socksPort} -s ${ownDn42Ipv6} -j nixos-fw-accept 2>/dev/null || true
      ip6tables -A nixos-fw -p udp --dport ${toString socksPort} -s ${ownDn42Ipv6} -j nixos-fw-accept 2>/dev/null || true
    '';
    extraInputRules = lib.mkIf (socks && config.networking.nftables.enable) ''
      ip saddr ${ownDn42Ipv4} tcp dport ${toString socksPort} counter accept
      ip saddr ${ownDn42Ipv4} udp dport ${toString socksPort} counter accept
      ip6 saddr ${ownDn42Ipv6} tcp dport ${toString socksPort} counter accept
      ip6 saddr ${ownDn42Ipv6} udp dport ${toString socksPort} counter accept
    '';
  };
}
