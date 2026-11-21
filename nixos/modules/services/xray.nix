{
  needProxy ? false,
  xrayPort ? 8555,
  proxyHosts ? [
    "fra0.dora.im"
    "tyo0.dora.im"
    "sjc0.dora.im"
  ],
  serverName ? "speedtest.dora.im",
  core ? "sing-box-extended",
  xhttpPath ? "/speedtest",
  xhttpMode ? "stream-one",
  xPaddingBytes ? "100-1000",
  xPaddingObfsMode ? true,
  xPaddingPlacement ? "header",
  xPaddingHeader ? "X-Padding",
  xPaddingMethod ? "repeat-x",
  # A small pool balances TCP loss isolation against weak-node socket/TLS costs.
  # Keep the request budget high to amortize handshakes on high-RTT paths.
  # Keep maxConcurrency unset: Extended/Xray reject it with maxConnections.
  xhttpXmux ? {
    maxConnections = "3-4";
    hMaxRequestTimes = "1800-3000";
    hMaxReusableSecs = "1800-3000";
    hKeepAlivePeriod = 30;
  },
  # Packet-up batching and pacing only; these do not recover lost packets.
  # Ranges are plain integers (bytes for sizes, milliseconds for intervals);
  # `badoption.Range[int]` rejects unit suffixes such as "512k". These settings
  # are inactive in stream-one, which has no separate upload POSTs to pace.
  xhttpUplinkChunkSize ? "524288-1048576",
  xhttpScMaxEachPostBytes ? "524288-1048576",
  xhttpScMinPostsIntervalMs ? "10-30",
  realityMaxTimeDifference ? "1m",
  healthCheckUrl ? "https://www.gstatic.com/generate_204",
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
  isExtended = core == "sing-box-extended";
  serviceName = if isXray then "xray" else "sing-box";
  useHealthCheckedBalancer = needProxy && builtins.length proxyHosts > 1;
  selfData = config.lib.self.data or (lib.importJSON ../../../lib/data/data.json);
  dn42Data = selfData.dn42 or { };
  ownDn42Ipv4 = config.services.dn42.ipv4 or dn42Data.ipv4 or "172.20.232.0/26";
  ownDn42Ipv6 = config.services.dn42.ipv6 or dn42Data.ipv6 or "fd53:90fd:4bb6::/48";
  # SOCKS binds the wildcard so it stays reachable on every overlay interface
  # without enumerating addresses. Exposure is controlled entirely by the
  # firewall: the port is deliberately absent from the global allow lists, and
  # `trustedInterfaces` below admits only the overlay interfaces.
  # Interface-scoped trust is preferred over address ranges: these ranges are
  # used by nothing else, and a wildcard keeps future mesh interfaces covered.
  tailscaleInterface = config.services.tailscale.interfaceName or "tailscale0";
  overlayTrustedInterfaces = [
    tailscaleInterface
    "dn42"
    "dn42x-*"
    "dn42m-*"
  ];
  # Tailscale addresses are tailnet-assigned, so the CGNAT/ULA ranges stand in
  # for them in the in-process guard.
  tailscaleIpv4Range = "100.64.0.0/10";
  tailscaleIpv6Range = "fd7a:115c:a1e0::/48";

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
    tailscaleIpv4Range
    tailscaleIpv6Range
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
  # Pool limits and uplink pacing are client-only; do not impose them on the
  # server transport. `congestion_controller`/`cwnd` are deliberately omitted:
  # Extended only applies them on the HTTP/3 path, and REALITY forces HTTP/2.
  xhttpClientSettings = lib.recursiveUpdate xhttpSettings {
    extra = {
      xmux = xhttpXmux;
      uplinkChunkSize = xhttpUplinkChunkSize;
      scMaxEachPostBytes = xhttpScMaxEachPostBytes;
      scMinPostsIntervalMs = xhttpScMinPostsIntervalMs;
    };
  };
  singBoxXhttpTransport = {
    type = "xhttp";
    host = serverName;
    path = xhttpPath;
    mode = xhttpMode;
    x_padding_bytes = xPaddingBytes;
    x_padding_obfs_mode = xPaddingObfsMode;
    x_padding_placement = xPaddingPlacement;
    x_padding_header = xPaddingHeader;
    x_padding_method = xPaddingMethod;
  };
  # Pool limits and uplink pacing are client-only; do not impose them on the
  # server transport. `congestion_controller`/`cwnd` are deliberately omitted:
  # Extended only applies them on the HTTP/3 path, and REALITY forces HTTP/2.
  singBoxXhttpClientTransport = singBoxXhttpTransport // {
    xmux = {
      max_connections = xhttpXmux.maxConnections;
      h_max_request_times = xhttpXmux.hMaxRequestTimes;
      h_max_reusable_secs = xhttpXmux.hMaxReusableSecs;
      h_keep_alive_period = xhttpXmux.hKeepAlivePeriod;
    };
    uplink_chunk_size = xhttpUplinkChunkSize;
    sc_max_each_post_bytes = xhttpScMaxEachPostBytes;
    sc_min_posts_interval_ms = xhttpScMinPostsIntervalMs;
  };
  xrayConfig = {
    log = {
      access = "none";
      error = "none";
      loglevel = "none";
    };
    inbounds = [
      {
        tag = "vless-in";
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
    ]
    ++ lib.optionals socks [
      {
        tag = "socks-in";
        listen = "::";
        port = socksPort;
        protocol = "socks";
        settings = {
          auth = "password";
          accounts = [
            {
              user = "proxy";
              pass = config.sops.placeholder."xray/uuid";
            }
          ];
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
          xhttpSettings = xhttpClientSettings;
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
                inboundTag = [ "vless-in" ];
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
        "sing-box-extended"
      ];
      message = "xray.nix: core must be xray, sing-box-extended or sing-box";
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

  # Legacy sing-box rollback requires the subscription to switch to TCP + Vision.
  # Templates contain only placeholders in the store; credentials are rendered at runtime.
  sops.templates."sing-box-config.json" = lib.mkIf (!isXray) {
    mode = "0400";
    restartUnits = [ "sing-box.service" ];
    content = builtins.toJSON {
      log.disabled = true;
      # Typed DNS syntax is required by 1.14; use the host's configured resolver.
      dns = {
        servers = [
          {
            type = "local";
            tag = "local";
          }
        ];
        final = "local";
      };

      inbounds = [
        (
          {
            type = "vless";
            tag = "vless-in";
            listen = "::";
            listen_port = xrayPort;
            users = [
              (
                {
                  name = "default";
                  uuid = config.sops.placeholder."xray/uuid";
                }
                // lib.optionalAttrs (!isExtended) { flow = "xtls-rprx-vision"; }
              )
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
              }
              // lib.optionalAttrs isExtended {
                # Needs synchronized host clocks; this does not stop immediate replay.
                max_time_difference = realityMaxTimeDifference;
              };
            };
          }
          // lib.optionalAttrs isExtended {
            decryption = "none";
            transport = singBoxXhttpTransport;
          }
        )
      ]
      ++ lib.optionals socks [
        {
          type = "socks";
          tag = "socks-in";
          listen = "::";
          listen_port = socksPort;
          users = [
            {
              username = "proxy";
              password = config.sops.placeholder."xray/uuid";
            }
          ];
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
        (lib.imap0 (
          i: host:
          {
            tag = "proxy-${toString i}";
            type = "vless";
            server = host;
            server_port = 8555;
            uuid = config.sops.placeholder."xray/uuid";
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
          }
          // (
            if isExtended then
              {
                encryption = "none";
                transport = singBoxXhttpClientTransport;
              }
            else
              { flow = "xtls-rprx-vision"; }
          )
        ) proxyHosts)
        ++ lib.optionals useHealthCheckedBalancer [
          {
            type = "urltest";
            tag = "proxy-balancer";
            outbounds = lib.imap0 (i: _: "proxy-${toString i}") proxyHosts;
            url = healthCheckUrl;
            interval = "1m";
          }
        ]
      );

      # 服务端路由优化：
      # 1. 严格限制 SOCKS5 仅允许本机及自身 DN42 段访问，非授权流量直接阻断
      # 2. 需要代理时仅使用纯内存前缀后缀匹配，不加载庞大的外部数据库
      route = {
        default_domain_resolver = "local";
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
          # Resolve first so domain names cannot bypass public-inbound IP guards.
          # Trusted SOCKS keeps its existing access to loopback and DN42 targets.
          ++ [
            {
              inbound = [ "vless-in" ];
              action = "resolve";
              server = "local";
            }
            {
              inbound = [ "vless-in" ];
              ip_is_private = true;
              action = "reject";
            }
          ]
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
  services.sing-box = {
    enable = !isXray;
    package = lib.mkIf isExtended pkgs.nur.repos.ataraxiasjel.sing-box-extended;
  };

  # Go's soft budget excludes socket buffers and some process memory. Retain
  # headroom below the cgroup limits; host-specific overrides still take priority.
  systemd.services.${serviceName} = {
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
      # Normal GC pacing avoids spending scarce CPU on aggressive collections;
      # GOMEMLIMIT provides a soft runtime budget, not an RSS or connection cap.
      GOGC = lib.mkDefault "100";
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
      ExecStart = "${pkgs.systemd}/bin/systemctl restart ${serviceName}.service";
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
    # SOCKS binds the wildcard, so the firewall is the only thing keeping it off
    # the public interfaces. The port is deliberately NOT in allowedTCPPorts /
    # allowedUDPPorts; these interfaces are trusted wholesale instead, which
    # covers every mesh port and future interfaces without per-port rules.
    # These address ranges are used by nothing else, so interface trust is safe.
    trustedInterfaces = overlayTrustedInterfaces;
  };
}
