{
  config,
  lib,
  inputs,
  nixosModules,
  pkgs,
  ...
}:
let
  inherit (lib)
    escapeShellArgs
    mkEnableOption
    mkForce
    mkIf
    mkMerge
    mkOption
    optionals
    types
    ;

  cfg = config.services.easytierMesh;
  envName = "easytier.env";
  settingsFormat = pkgs.formats.toml { };
  wsPort = config.ports.easytier-ws;
  easytierTraefikRule = "Host(`${cfg.bootstrap.host}`) || Host(`${config.networking.fqdn}`)";

  listenerUris = [
    "ws://0.0.0.0:${toString wsPort}"
    # "quic://0.0.0.0:${toString cfg.protocols.quic.port}"
    "quic://0.0.0.0:${toString cfg.protocols.quic.port}"
    "quic://[::]:${toString cfg.protocols.quic.port}"
    "faketcp://[::]:${toString cfg.protocols.faketcp.port}"
    # "faketcp://0.0.0.0:${toString cfg.protocols.faketcp.port}"
  ];

  mappedListenerUris = lib.concatMap (host: [
    "wss://${host}:${toString cfg.protocols.wss.port}"
    "quic://${host}:${toString cfg.protocols.quic.port}"
    "faketcp://${host}:${toString cfg.protocols.faketcp.port}"
  ]) cfg.publicHosts;

  bootstrapPeers = [
    "wss://${cfg.bootstrap.host}:444"
    "quic://${cfg.bootstrap.host}:444"
    # "faketcp://${cfg.bootstrap.host}:${toString cfg.protocols.faketcp.port}"
    "faketcp://${cfg.bootstrap.host}:11014"
  ];

  commonArgs = [
    "--dev-name"
    cfg.devName
    "--default-protocol"
    "wss"
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
    "--enable-kcp-proxy=true"
    "--disable-kcp-input=false"
    "--enable-quic-proxy=true"
    "--disable-quic-input=false"
    "--disable-udp-hole-punching=false"
    "--disable-tcp-hole-punching=false"
    "--disable-sym-hole-punching=false"
    "--disable-relay-kcp=false"
    "--proxy-forward-by-system=true"
  ]
  ++ optionals cfg.enableExitNode [ "--enable-exit-node=true" ]
  ++ optionals (cfg.exitNode != null) [
    "--exit-nodes"
    cfg.exitNode
  ]
  ++ optionals (cfg.proxyNetworks != [ ]) [
    "--proxy-networks"
    (lib.concatStringsSep "," cfg.proxyNetworks)
  ]
  ++ lib.concatMap (listener: [
    "--mapped-listeners"
    listener
  ]) mappedListenerUris
  ++ cfg.extraArgs;

  generatedConfig = settingsFormat.generate "easytier.toml" (
    lib.filterAttrsRecursive (_: v: v != { }) (
      lib.filterAttrsRecursive (_: v: v != null) {
        hostname = config.networking.hostName;
        inherit (cfg) ipv4;
        dhcp = cfg.ipv4 == null;
        listeners = listenerUris;
        peer = map (uri: { inherit uri; }) (if cfg.role == "bootstrap" then [ ] else bootstrapPeers);
        network_identity = {
          network_name = cfg.networkName;
        };
      }
    )
  );
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

    devName = mkOption {
      type = types.str;
      default = "easytier0";
    };

    publicHosts = mkOption {
      type = types.listOf types.str;
      default = [
        config.networking.fqdn
        "et.${config.networking.domain}"
      ];
      description = ''
        Public hostnames or IPs other peers should use to reach this node
        directly. Used to generate EasyTier --mapped-listeners announcements.
      '';
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
        description = "Optional bootstrap preparation logic run before easytier starts on bootstrap nodes.";
      };
    };

    protocols = {
      wss.port = mkOption {
        type = types.port;
        default = config.ports.easytier-traefik-wss;
        description = "Public TCP port exposed by Traefik for EasyTier WSS.";
      };

      quic.port = mkOption {
        type = types.port;
        default = cfg.protocols.wss.port;
        description = "EasyTier QUIC listener port. Defaults to the same numeric port as WSS.";
      };

      faketcp.port = mkOption {
        type = types.port;
        default = config.ports.easytier-faketcp;
        description = "EasyTier FakeTCP listener port.";
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

      sops.secrets."${cfg.secretSopsKey}" = {
        restartUnits = [ "easytier.service" ];
      };

      sops.templates."${envName}".content = ''
        ET_NETWORK_SECRET=${config.sops.placeholder."${cfg.secretSopsKey}"}
      '';

      services.easytier = {
        enable = true;
        allowSystemForward = true;
        package = lib.mkDefault (
          inputs.latest.legacyPackages.${pkgs.stdenv.hostPlatform.system}.easytier.override {
            withQuic = true;
          }
        );
      };

      systemd.services.easytier = {
        aliases = [ "easytier-mesh.service" ];
        description = "EasyTier Daemon";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          config.services.easytier.package
          iproute2
          bash
        ];
        preStart = lib.mkIf (
          cfg.role == "bootstrap" && cfg.bootstrap.preStartText != ""
        ) cfg.bootstrap.preStartText;
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = [ config.sops.templates."${envName}".path ];
          StateDirectory = "easytier/easytier";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/easytier/easytier";
          ExecStart = escapeShellArgs (
            [
              "${config.services.easytier.package}/bin/easytier-core"
              "-c"
              generatedConfig
            ]
            ++ commonArgs
          );
          Restart = mkForce "always";
          RestartSec = mkForce "2s";
          AmbientCapabilities = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
            "CAP_NET_BIND_SERVICE"
          ];
          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
            "CAP_NET_BIND_SERVICE"
          ];
          PrivateDevices = false;
          PrivateUsers = false;
          RestrictAddressFamilies = "AF_INET AF_INET6 AF_NETLINK AF_PACKET";
        };
      };

      networking.firewall = {
        trustedInterfaces = [ cfg.devName ];
        allowedTCPPorts = [
          cfg.protocols.wss.port
          cfg.protocols.faketcp.port
        ];
        allowedUDPPorts = [
          cfg.protocols.quic.port
          cfg.protocols.faketcp.port
        ];
      };

      boot.kernel.sysctl = {
        "net.ipv4.conf.all.forwarding" = mkForce true;
        "net.ipv4.ip_forward" = mkForce 1;
        "net.ipv6.conf.all.forwarding" = mkForce 1;
      };

      services.traefik.proxies.easytier-rpc = {
        rule = "(Host(`${config.networking.fqdn}`) || Host(`et.${config.networking.domain}`)) && (Path(`/et`) || PathPrefix(`/et/`))";
        target = "http://${cfg.rpcPortal}";
        middlewares = [
          "auth"
          "easytier-rpc-stripprefix"
        ];
      };

      services.traefik.dynamicConfigOptions.http.middlewares.easytier-rpc-stripprefix.stripPrefix.prefixes =
        [ "/et" ];
    }

    {
      services.traefik.staticConfigOptions.entryPoints.easytier = {
        address = ":${toString cfg.protocols.wss.port}";
        transport.respondingTimeouts = {
          readTimeout = 180;
          writeTimeout = 180;
          idleTimeout = 180;
        };
        http.tls = if config.environment.isNAT then true else { certresolver = "zerossl"; };
      };

      services.traefik.proxies.easytier-wss = {
        rule = easytierTraefikRule;
        target = "http://127.0.0.1:${toString wsPort}";
        entryPoints = [ "easytier" ];
      };
    }

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
