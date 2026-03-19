{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkForce
    optionals
    types
    ;
  cfg = config.services.easytierMesh;
  easytierDomain = lib.removeSuffix "." cfg.tldDnsZone;
  envName = "easytier-mesh.env";
  instanceName = "mesh";
  easytierTraefikHosts = lib.unique [
    config.networking.fqdn
    "et.${config.networking.domain}"
  ];
  easytierTraefikRule = lib.concatMapStringsSep " || " (host: "Host(`${host}`)") easytierTraefikHosts;

  listenerUris =
    optionals cfg.protocols.ws.enable [ "ws://127.0.0.1:${toString cfg.protocols.ws.port}" ]
    ++ optionals cfg.protocols.quic.enable [ "quic://0.0.0.0:${toString cfg.protocols.quic.port}" ]
    ++ optionals cfg.protocols.faketcp.enable [
      "faketcp://0.0.0.0:${toString cfg.protocols.faketcp.port}"
    ];

  allowedTcpPorts = optionals cfg.protocols.faketcp.enable [ cfg.protocols.faketcp.port ];

  allowedUdpPorts = optionals cfg.protocols.quic.enable [ cfg.protocols.quic.port ];

  bootstrapPeers =
    (optionals (cfg.role == "member" && cfg.bootstrap.host != null) (
      optionals cfg.protocols.tcp.enable [
        "tcp://${cfg.bootstrap.host}:${toString cfg.protocols.tcp.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.udp.enable [
        "udp://${cfg.bootstrap.host}:${toString cfg.protocols.udp.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.faketcp.enable [
        "faketcp://${cfg.bootstrap.host}:${toString cfg.protocols.faketcp.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.wss.enable [
        "wss://${cfg.bootstrap.host}:${toString cfg.protocols.wss.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.quic.enable [
        "quic://${cfg.bootstrap.host}:${toString cfg.protocols.quic.port}"
      ]
    ))
    ++ cfg.bootstrap.peers
    ++ cfg.extraPeers;

  commonArgs = [
    "--dev-name"
    cfg.devName
    "--default-protocol"
    cfg.defaultProtocol
    "--latency-first=${if cfg.latencyFirst then "true" else "false"}"
    "--private-mode=${if cfg.privateMode then "true" else "false"}"
    "--multi-thread=true"
    # Keep split DNS management in systemd-resolved under our control to avoid
    # EasyTier racing with the dedicated easytier-resolved helper.
    "--accept-dns=true"
    "--tld-dns-zone"
    cfg.tldDnsZone
    "--compression"
    "none"
    "--rpc-portal"
    cfg.rpcPortal
    "--bind-device=true"
    "--console-log-level"
    (if cfg.lowResource then "error" else "warn")
    "--file-log-level"
    "error"
    "--file-log-size"
    "8"
    "--file-log-count"
    "2"
    "--enable-kcp-proxy=${if cfg.protocols.kcp.enable then "true" else "false"}"
    "--disable-kcp-input=false"
    "--enable-quic-proxy=${if cfg.protocols.quic.enable then "true" else "false"}"
    "--disable-quic-input=false"
    "--quic-listen-port"
    (toString cfg.protocols.quic.port)
    "--disable-udp-hole-punching=false"
    "--disable-tcp-hole-punching=false"
    "--disable-sym-hole-punching=false"
    "--disable-relay-kcp=false"
  ]
  ++ optionals cfg.disableIPv6 [ "--disable-ipv6=true" ]
  ++ optionals cfg.enableExitNode [ "--enable-exit-node=true" ]
  ++ optionals (cfg.exitNode != null) [
    "--exit-nodes"
    cfg.exitNode
  ]
  ++ optionals (cfg.proxyNetworks != [ ]) [
    "--proxy-networks"
    (lib.concatStringsSep "," cfg.proxyNetworks)
  ]
  ++ optionals cfg.proxyForwardBySystem [ "--proxy-forward-by-system=true" ]
  ++ cfg.extraArgs;
in
{
  imports = [ nixosModules.services.traefik ];

  options.services.easytierMesh = {
    enable = (mkEnableOption "EasyTier mesh") // {
      default = true;
    };

    role = mkOption {
      type = types.enum [
        "bootstrap"
        "member"
      ];
      default = "member";
    };

    networkName = mkOption {
      type = types.str;
      default = "Doraemon";
    };

    secretSopsKey = mkOption {
      type = types.str;
      default = "easytier/network_secret";
    };

    ipv4 = mkOption {
      type = types.nullOr types.str;
      default = if cfg.role == "bootstrap" then "10.100.0.1" else null;
      description = "Static EasyTier address. Leave null to use DHCP-style auto assignment.";
    };

    defaultProtocol = mkOption {
      type = types.enum [
        "faketcp"
        "wss"
        "quic"
      ];
      default = "wss";
    };

    devName = mkOption {
      type = types.str;
      default = "easytier0";
    };

    publicHost = mkOption {
      type = types.str;
      default = config.networking.fqdn;
    };

    bootstrap = {
      host = mkOption {
        type = types.nullOr types.str;
        default = "et.${config.networking.domain}";
      };
      peers = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      preStartText = mkOption {
        type = types.lines;
        default = "";
        description = "Optional bootstrap preparation logic run before easytier-mesh starts on bootstrap nodes.";
      };
    };

    protocols = {
      ws = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        port = mkOption {
          type = types.port;
          default = config.ports.easytier-ws;
        };
        bootstrapPort = mkOption {
          type = types.port;
          default = config.ports.easytier-traefik-wss;
        };
      };
      tcp = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        port = mkOption {
          type = types.port;
          default = config.ports.easytier-tcp;
        };
        bootstrapPort = mkOption {
          type = types.port;
          default = config.ports.easytier-tcp;
        };
      };
      udp = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        port = mkOption {
          type = types.port;
          default = config.ports.easytier-udp;
        };
        bootstrapPort = mkOption {
          type = types.port;
          default = config.ports.easytier-udp;
        };
      };
      faketcp = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        port = mkOption {
          type = types.port;
          default = config.ports.easytier-faketcp;
        };
        bootstrapPort = mkOption {
          type = types.port;
          default = config.ports.easytier-faketcp;
        };
      };
      wss = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        port = mkOption {
          type = types.port;
          default = config.ports.easytier-wss;
        };
        bootstrapPort = mkOption {
          type = types.port;
          default = config.ports.easytier-traefik-wss;
        };
      };
      quic = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        port = mkOption {
          type = types.port;
          default = config.ports.easytier-quic;
        };
      };
      kcp.enable = mkOption {
        type = types.bool;
        default = true;
      };
    };

    latencyFirst = mkOption {
      type = types.bool;
      default = true;
    };

    privateMode = mkOption {
      type = types.bool;
      default = true;
    };

    lowResource = mkOption {
      type = types.bool;
      default = false;
    };

    disableIPv6 = mkOption {
      type = types.bool;
      default = false;
    };

    enableExitNode = mkOption {
      type = types.bool;
      default = true;
    };

    exitNode = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    overlayCIDR = mkOption {
      type = types.str;
      default = "10.100.0.0/24";
    };

    proxyNetworks = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    proxyForwardBySystem = mkOption {
      type = types.bool;
      default = true;
    };

    tldDnsZone = mkOption {
      type = types.str;
      default = "et.";
    };

    dnsServer = mkOption {
      type = types.str;
      default = "100.100.100.101";
      description = "EasyTier DNS server used for resolving mesh hostnames.";
    };

    rpcPortal = mkOption {
      type = types.str;
      default = "127.0.0.1:15888";
    };

    extraPeers = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking.networkmanager.unmanaged = [ cfg.devName ];

      assertions = [
        {
          assertion =
            cfg.protocols.ws.enable
            || cfg.protocols.wss.enable
            || cfg.protocols.quic.enable
            || cfg.protocols.faketcp.enable;
          message = "At least one EasyTier transport/proxy path should remain enabled.";
        }
        {
          assertion =
            (cfg.defaultProtocol != "wss" || cfg.protocols.wss.enable)
            && (cfg.defaultProtocol != "quic" || cfg.protocols.quic.enable)
            && (cfg.defaultProtocol != "faketcp" || cfg.protocols.faketcp.enable);
          message = "services.easytierMesh.defaultProtocol must match an enabled protocol.";
        }
      ];

      sops.secrets."${cfg.secretSopsKey}" = {
        restartUnits = [ "easytier.service" ];
      };

      sops.templates."${envName}".content = ''
        ET_NETWORK_SECRET=${config.sops.placeholder."${cfg.secretSopsKey}"}
      '';

      services.easytier = {
        enable = true;
        allowSystemForward = cfg.proxyForwardBySystem || cfg.enableExitNode;
        instances."${instanceName}" = {
          environmentFiles = [ config.sops.templates."${envName}".path ];
          settings = {
            hostname = config.networking.hostName;
            network_name = cfg.networkName;
            inherit (cfg) ipv4;
            dhcp = cfg.ipv4 == null;
            listeners = listenerUris;
            peers = if cfg.role == "bootstrap" then [ ] else bootstrapPeers;
          };
          extraArgs = commonArgs;
        };
      };

      systemd.services.easytier-mesh = {
        aliases = [ "easytier.service" ];
        after = lib.mkAfter [ "systemd-resolved.service" ];
        wants = lib.mkAfter [ "systemd-resolved.service" ];
        preStart = lib.mkIf (
          cfg.role == "bootstrap" && cfg.bootstrap.preStartText != ""
        ) cfg.bootstrap.preStartText;
        serviceConfig = {
          Restart = mkForce "always";
          RestartSec = mkForce "2s";
          AmbientCapabilities = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ];
          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ];
          PrivateDevices = false;
          PrivateUsers = false;
          RestrictAddressFamilies = "AF_INET AF_INET6 AF_NETLINK";
        };
      };

      systemd.services.easytier-resolved = {
        description = "Register EasyTier split DNS with systemd-resolved";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "easytier.service"
          "systemd-resolved.service"
        ];
        after = [
          "easytier.service"
          "systemd-resolved.service"
        ];
        partOf = [ "easytier.service" ];
        bindsTo = [ "easytier.service" ];
        path = [
          pkgs.systemd
          pkgs.iproute2
          pkgs.coreutils
        ];
        script = ''
          while true; do
            if ip link show dev ${cfg.devName} >/dev/null 2>&1; then
              ifindex="$(${pkgs.iproute2}/bin/ip -o link show ${cfg.devName} | ${pkgs.coreutils}/bin/cut -d: -f1 | ${pkgs.coreutils}/bin/tr -d ' ')"
              dns="${cfg.dnsServer}"
              dns_a="$(${pkgs.coreutils}/bin/echo "$dns" | ${pkgs.coreutils}/bin/cut -d. -f1)"
              dns_b="$(${pkgs.coreutils}/bin/echo "$dns" | ${pkgs.coreutils}/bin/cut -d. -f2)"
              dns_c="$(${pkgs.coreutils}/bin/echo "$dns" | ${pkgs.coreutils}/bin/cut -d. -f3)"
              dns_d="$(${pkgs.coreutils}/bin/echo "$dns" | ${pkgs.coreutils}/bin/cut -d. -f4)"

              ${pkgs.systemd}/bin/busctl call \
                org.freedesktop.resolve1 \
                /org/freedesktop/resolve1 \
                org.freedesktop.resolve1.Manager \
                SetLinkDNS \
                'ia(iay)' \
                "$ifindex" 1 2 4 "$dns_a" "$dns_b" "$dns_c" "$dns_d"

              ${pkgs.systemd}/bin/busctl call \
                org.freedesktop.resolve1 \
                /org/freedesktop/resolve1 \
                org.freedesktop.resolve1.Manager \
                SetLinkDomains \
                'ia(sb)' \
                "$ifindex" 1 ${easytierDomain} 1

              ${pkgs.systemd}/bin/busctl call \
                org.freedesktop.resolve1 \
                /org/freedesktop/resolve1 \
                org.freedesktop.resolve1.Manager \
                SetLinkDefaultRoute \
                'ib' \
                "$ifindex" false
            fi
            sleep 10
          done
        '';
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "2s";
          ExecStop = "${pkgs.runtimeShell} -lc '${pkgs.systemd}/bin/resolvectl revert ${cfg.devName} || true'";
        };
      };

      networking.firewall = {
        trustedInterfaces = [ cfg.devName ];
        allowedTCPPorts = allowedTcpPorts;
        allowedUDPPorts = allowedUdpPorts;
      };

      boot.kernel.sysctl = mkIf cfg.proxyForwardBySystem {
        "net.ipv4.conf.all.forwarding" = mkForce true;
        "net.ipv4.ip_forward" = mkForce 1;
        "net.ipv6.conf.all.forwarding" = mkForce 1;
      };

      networking.nftables = mkIf cfg.proxyForwardBySystem {
        enable = true;
        tables.easytier-forward = {
          family = "inet";
          content = ''
            chain forward {
              type filter hook forward priority filter; policy accept;
              iifname "${cfg.devName}" accept
              oifname "${cfg.devName}" accept
            }
          '';
        };
        tables.easytier-masq = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              oifname != "${cfg.devName}" ip saddr ${cfg.overlayCIDR} masquerade
            }
          '';
        };
      };

      services.traefik.proxies.easytier-rpc = mkIf (config.services.traefik.enable or false) {
        rule = "Host(`${config.networking.fqdn}`) && (Path(`/et`) || PathPrefix(`/et/`))";
        target = "http://${cfg.rpcPortal}";
        middlewares = [
          "auth"
          "easytier-rpc-stripprefix"
        ];
      };

      services.traefik.dynamicConfigOptions.http.middlewares.easytier-rpc-stripprefix.stripPrefix.prefixes =
        [
          "/et"
        ];
    }

    (mkIf ((config.services.traefik.enable or false) && cfg.protocols.ws.enable) {
      networking.firewall.allowedTCPPorts = [ config.ports.easytier-traefik-wss ];

      services.traefik.staticConfigOptions.entryPoints.easytier-wss = {
        address = ":${toString config.ports.easytier-traefik-wss}";
        forwardedHeaders.insecure = true;
        proxyProtocol.insecure = true;
        transport.respondingTimeouts = {
          readTimeout = 180;
          writeTimeout = 180;
          idleTimeout = 180;
        };
        http.tls = if config.environment.isNAT then true else { certresolver = "zerossl"; };
      };

      services.traefik.proxies.easytier-wss = {
        rule = easytierTraefikRule;
        target = "http://127.0.0.1:${toString cfg.protocols.ws.port}";
        entryPoints = [ "easytier-wss" ];
      };
    })

    (mkIf (cfg.role == "member") {
      systemd.services.easytier-watchdog = {
        description = "EasyTier Watchdog";
        after = [ "easytier.service" ];
        path = [
          pkgs.iputils
          pkgs.systemd
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "easytier-watchdog" ''
            if ! ping -c 3 -W 5 10.100.0.1 > /dev/null 2>&1; then
              systemctl restart easytier
            fi
          '';
        };
      };

      systemd.timers.easytier-watchdog = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "2m";
          RandomizedDelaySec = "20s";
          Unit = "easytier-watchdog.service";
        };
      };
    })
  ]);
}
