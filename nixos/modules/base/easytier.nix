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
  easytierTraefikRule = "PathPrefix(`/`)";

  listenerUris = [
    "ws://0.0.0.0:${toString wsPort}"
    # "quic://0.0.0.0:${toString cfg.protocols.quic.port}"
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
    # "wss://${cfg.bootstrap.host}:${toString cfg.protocols.wss.port}"
    # "quic://${cfg.bootstrap.host}:${toString cfg.protocols.quic.port}"
    # "faketcp://${cfg.bootstrap.host}:${toString cfg.protocols.faketcp.port}"
    "wss://${cfg.bootstrap.host}:444"
    "quic://${cfg.bootstrap.host}:444"
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

  # Overlay transport packets are marked and steered into a dedicated routing
  # table. That table is rebuilt from the host's current default routes, so the
  # underlay always follows real uplinks instead of another tunnel or a local
  # transparent proxy such as Mihomo TUN.
  overlayTransportMark = "0x1";
  overlayRoutingTable = "8991";
  overlayRoutingPriority = "8990";
  tailscaleInterface = "tailscale0";
  tailscaleTransportUdpPorts = lib.optionals config.services.tailscale.enable [
    3478
    config.services.tailscale.port
  ];
  easytierTransportUdpPorts = [ cfg.protocols.quic.port ];
  easytierTransportTcpPorts = [
    cfg.protocols.wss.port
    cfg.protocols.faketcp.port
  ];
  overlayTransportUdpPorts = tailscaleTransportUdpPorts ++ easytierTransportUdpPorts;
  overlayIsolationAfterUnits = [
    "network-online.target"
    "nftables.service"
    "easytier.service"
  ]
  ++ lib.optionals config.services.mihomo.enable [ "mihomo.service" ]
  ++ lib.optionals config.services.tailscale.enable [ "tailscaled.service" ];

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

      networking.nftables = {
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
        tables.easytier-underlay-isolation = {
          family = "inet";
          content = ''
            # Filled dynamically by the helper service below. Keeping it in the
            # ruleset makes the active uplinks visible in `nft list ruleset`.
            set wan_ifaces {
              type ifname
            }

            chain route_output {
              type route hook output priority mangle; policy accept;

              # Identify overlay transport sockets early. Once marked, policy
              # routing can pin them to a routing table that only contains real
              # default uplinks instead of whatever a proxy/TUN installs.
              ${lib.optionalString (overlayTransportUdpPorts != [ ]) ''
                udp dport { ${
                  lib.concatMapStringsSep ", " toString overlayTransportUdpPorts
                } } counter meta mark set meta mark | ${overlayTransportMark}
                udp sport { ${
                  lib.concatMapStringsSep ", " toString overlayTransportUdpPorts
                } } counter meta mark set meta mark | ${overlayTransportMark}
              ''}
              ${lib.optionalString (easytierTransportTcpPorts != [ ]) ''
                tcp dport { ${
                  lib.concatMapStringsSep ", " toString easytierTransportTcpPorts
                } } counter meta mark set meta mark | ${overlayTransportMark}
                tcp sport { ${
                  lib.concatMapStringsSep ", " toString easytierTransportTcpPorts
                } } counter meta mark set meta mark | ${overlayTransportMark}
              ''}
            }

            chain output {
              type filter hook output priority filter; policy accept;

              # Hard-stop recursive encapsulation: overlay transport must never
              # be sent into another overlay device.
              meta mark & ${overlayTransportMark} == ${overlayTransportMark} oifname "${tailscaleInterface}" counter reject with icmpx type admin-prohibited
              meta mark & ${overlayTransportMark} == ${overlayTransportMark} oifname "${cfg.devName}" counter reject with icmpx type admin-prohibited

              # Positive visibility for the real uplinks currently discovered by
              # the helper service. Other traffic still falls back to normal
              # policy, but marked overlay transport is already constrained by
              # the dedicated routing table below.
              meta mark & ${overlayTransportMark} == ${overlayTransportMark} oifname @wan_ifaces counter accept
            }
          '';
        };
      };

      systemd.services.easytier-underlay-isolation = {
        description = "Pin EasyTier and Tailscale transport to real uplinks";
        after = overlayIsolationAfterUnits;
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.iproute2
          pkgs.nftables
        ];
        script = ''
          set -eu

          table_id=${overlayRoutingTable}
          priority=${overlayRoutingPriority}
          mark=${overlayTransportMark}
          nft_table="inet easytier-underlay-isolation"
          nft_set="wan_ifaces"

          collect_defaults() {
            local family="$1"

            # Copy every currently active default route from `main`. This keeps
            # multiple uplinks working without requiring manual interface names.
            ip -o "-$family" route show table main default \
              | awk '
                {
                  route = ""
                  for (i = 1; i <= NF; i++) {
                    if ($i == "proto" || $i == "metric" || $i == "expires") {
                      break
                    }
                    route = route (route == "" ? "" : OFS) $i
                  }
                  if (route != "") {
                    print route
                  }
                }
              '
          }

          mapfile -t v4_defaults < <(collect_defaults 4)
          mapfile -t v6_defaults < <(collect_defaults 6)
          mapfile -t wan_ifaces < <(
            {
              printf '%s\n' "''${v4_defaults[@]}"
              printf '%s\n' "''${v6_defaults[@]}"
            } \
              | awk '
                $0 != "" {
                  for (i = 1; i <= NF; i++) {
                    if ($i == "dev" && (i + 1) <= NF) {
                      print $(i + 1)
                    }
                  }
                }
              ' \
              | sort -u
          )

          have_v4_defaults=false
          have_v6_defaults=false
          if ((''${#v4_defaults[@]} > 0)); then
            have_v4_defaults=true
          fi
          if ((''${#v6_defaults[@]} > 0)); then
            have_v6_defaults=true
          fi

          # Rebuild the policy-routing table from scratch on every run so link
          # changes, DHCP renewals, and gateway flips never leave stale state.
          while ip -4 rule del fwmark "$mark/$mark" lookup "$table_id" priority "$priority" 2>/dev/null; do :; done
          while ip -6 rule del fwmark "$mark/$mark" lookup "$table_id" priority "$priority" 2>/dev/null; do :; done
          ip -4 route flush table "$table_id" || true
          if [ "$have_v6_defaults" = true ]; then
            ip -6 route flush table "$table_id" || true
          fi

          if [ "$have_v4_defaults" = true ]; then
            for route in "''${v4_defaults[@]}"; do
              # Each array element is one complete default route copied from
              # `main`, so preserve it as a single shell word and let `ip`
              # parse the embedded fields itself.
              ip -4 route add table "$table_id" $route
            done
            ip -4 rule add fwmark "$mark/$mark" lookup "$table_id" priority "$priority"
          fi

          if [ "$have_v6_defaults" = true ]; then
            for route in "''${v6_defaults[@]}"; do
              ip -6 route add table "$table_id" $route
            done
            ip -6 rule add fwmark "$mark/$mark" lookup "$table_id" priority "$priority"
          fi

          if nft list table $nft_table >/dev/null 2>&1; then
            nft flush set $nft_table $nft_set
            if ((''${#wan_ifaces[@]} > 0)); then
              wan_ifaces_literal=$(printf '"%s", ' "''${wan_ifaces[@]}")
              wan_ifaces_literal="{ ''${wan_ifaces_literal%, } }"
              nft add element $nft_table $nft_set "$wan_ifaces_literal"
            fi
          fi
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      systemd.timers.easytier-underlay-isolation = {
        description = "Refresh EasyTier underlay isolation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "45s";
          OnUnitActiveSec = "2min";
          Unit = "easytier-underlay-isolation.service";
        };
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
        forwardedHeaders.insecure = true;
        proxyProtocol.insecure = true;
        transport.respondingTimeouts = {
          readTimeout = 180;
          writeTimeout = 180;
          idleTimeout = 180;
        };
        http.tls = { };
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
