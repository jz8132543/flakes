{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkForce
    mkIf
    mkOption
    optionals
    types
    ;
  cfg = config.services.easytierMesh.member;
  envName = "easytier-member.env";
  instanceName = "mesh";

  listenerUris =
    optionals cfg.protocols.tcp.enable [ "tcp://0.0.0.0:${toString cfg.protocols.tcp.port}" ]
    ++ optionals cfg.protocols.udp.enable [ "udp://0.0.0.0:${toString cfg.protocols.udp.port}" ]
    ++ optionals cfg.protocols.faketcp.enable [
      "faketcp://0.0.0.0:${toString cfg.protocols.faketcp.port}"
    ]
    ++ optionals cfg.protocols.wss.enable [ "wss://0.0.0.0:${toString cfg.protocols.wss.port}" ];

  allowedTcpPorts =
    optionals cfg.protocols.tcp.enable [ cfg.protocols.tcp.port ]
    ++ optionals cfg.protocols.faketcp.enable [ cfg.protocols.faketcp.port ]
    ++ optionals cfg.protocols.wss.enable [ cfg.protocols.wss.port ];

  allowedUdpPorts =
    optionals cfg.protocols.udp.enable [ cfg.protocols.udp.port ]
    ++ optionals cfg.protocols.quic.enable [ cfg.protocols.quic.port ];

  bootstrapPeers =
    (optionals (cfg.bootstrapHost != null) (
      optionals cfg.protocols.wss.enable [
        "wss://${cfg.bootstrapHost}:${toString cfg.protocols.wss.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.tcp.enable [
        "tcp://${cfg.bootstrapHost}:${toString cfg.protocols.tcp.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.udp.enable [
        "udp://${cfg.bootstrapHost}:${toString cfg.protocols.udp.bootstrapPort}"
      ]
      ++ optionals cfg.protocols.faketcp.enable [
        "faketcp://${cfg.bootstrapHost}:${toString cfg.protocols.faketcp.bootstrapPort}"
      ]
    ))
    ++ cfg.bootstrapPeers
    ++ cfg.extraPeers;

  commonArgs = [
    "--dev-name"
    cfg.devName
    "--default-protocol"
    cfg.defaultProtocol
    "--latency-first=${if cfg.latencyFirst then "true" else "false"}"
    "--private-mode=${if cfg.privateMode then "true" else "false"}"
    "--multi-thread=true"
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
    "--disable-kcp-input=true"
    "--enable-quic-proxy=${if cfg.protocols.quic.enable then "true" else "false"}"
    "--disable-quic-input=false"
    "--quic-listen-port"
    (toString cfg.protocols.quic.port)
    "--disable-udp-hole-punching=false"
    "--disable-tcp-hole-punching=false"
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
  options.services.easytierMesh.member = {
    enable = (mkEnableOption "EasyTier mesh member") // {
      default = true;
    };

    networkName = mkOption {
      type = types.str;
      default = "dora-mesh";
    };

    secretSopsKey = mkOption {
      type = types.str;
      default = "easytier/network_secret";
    };

    bootstrapHost = mkOption {
      type = types.nullOr types.str;
      default = "et.${config.networking.domain}";
      description = "Convenience bootstrap host. Set to null if you only want to use bootstrapPeers.";
    };

    defaultProtocol = mkOption {
      type = types.enum [
        "faketcp"
        "wss"
        "quic"
        "tcp"
        "udp"
      ];
      default = "wss";
    };

    bootstrapPeers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Additional peer URIs used only by this machine to join the mesh.
      '';
      example = [
        "wss://et.dora.im:443"
        "faketcp://et.dora.im:11011"
      ];
    };

    ipv4 = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Static EasyTier address. Leave null to use DHCP-style auto assignment.";
    };

    devName = mkOption {
      type = types.str;
      default = "easytier0";
    };

    protocols = {
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
          default = false;
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
          default = config.ports.https;
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

      kcp = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
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
      description = "Virtual EasyTier IPv4 address of the exit node to use.";
    };

    overlayCIDR = mkOption {
      type = types.str;
      default = "10.144.0.0/24";
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

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.protocols.wss.enable
          || cfg.protocols.quic.enable
          || cfg.protocols.tcp.enable
          || cfg.protocols.udp.enable
          || cfg.protocols.faketcp.enable;
        message = "At least one EasyTier transport/proxy path should remain enabled.";
      }
      {
        assertion =
          (cfg.defaultProtocol != "wss" || cfg.protocols.wss.enable)
          && (cfg.defaultProtocol != "quic" || cfg.protocols.quic.enable)
          && (cfg.defaultProtocol != "tcp" || cfg.protocols.tcp.enable)
          && (cfg.defaultProtocol != "udp" || cfg.protocols.udp.enable)
          && (cfg.defaultProtocol != "faketcp" || cfg.protocols.faketcp.enable);
        message = "services.easytierMesh.member.defaultProtocol must match an enabled protocol.";
      }
    ];

    sops.secrets."${cfg.secretSopsKey}" = {
      restartUnits = [ "easytier-${instanceName}.service" ];
    };

    sops.templates."${envName}".content = ''
      ET_NETWORK_SECRET=${config.sops.placeholder."${cfg.secretSopsKey}"}
    '';

    services.easytier = {
      enable = true;
      allowSystemForward = cfg.proxyForwardBySystem;
      instances."${instanceName}" = {
        environmentFiles = [ config.sops.templates."${envName}".path ];
        settings = {
          hostname = config.networking.hostName;
          network_name = cfg.networkName;
          inherit (cfg) ipv4;
          dhcp = cfg.ipv4 == null;
          listeners = listenerUris;
          peers = bootstrapPeers;
        };
        extraArgs = commonArgs;
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

    services.traefik.proxies.easytier-member-rpc = mkIf (config.services.traefik.enable or false) {
      rule = "Host(`${config.networking.fqdn}`) && (Path(`/et`) || PathPrefix(`/et/`))";
      target = "http://${cfg.rpcPortal}";
      middlewares = [
        "auth"
        "easytier-member-rpc-stripprefix"
      ];
    };

    services.traefik.dynamicConfigOptions.http.middlewares.easytier-member-rpc-stripprefix.stripPrefix.prefixes =
      [
        "/et"
      ];
  };
}
