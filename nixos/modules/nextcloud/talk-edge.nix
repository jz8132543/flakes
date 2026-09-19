{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.nextcloud-talk-edge;
  domain = config.networking.domain;

  # ── 生成 Janus WebRTC Gateway 配置文件（不含 nat_1_1_mapping，由启动脚本动态填入）────
  janusConfigFile = pkgs.writeText "janus.jcfg" ''
    general: {
      configs_folder = "/run/janus/etc"
      plugins_folder = "${pkgs.janus-gateway}/lib/janus/plugins"
      transports_folder = "/run/janus/transports"
      events_folder = "${pkgs.janus-gateway}/lib/janus/events"
      log_to_stdout = true
      debug_level = 4
    }

    media: {
      rtp_port_range = "${toString cfg.rtpPortRange.min}-${toString cfg.rtpPortRange.max}"
    }

    nat: {
      # 排除虚拟内网网卡（如 Tailscale/Docker），防止将内网 IP 广播给公网客户端导致黑屏
      nic_ign = "tailscale0,docker0,nebula.mag,lo,dummy*,tun*,tap*"
      # nat_1_1_mapping 由 ExecStartPre 在运行时动态填入
      nat_1_1_mapping = "__PUBLIC_IP__"
      keep_private_host = true
      ignore_mdns = true
      stun_server = "${cfg.stunServer}"
      stun_port = ${toString cfg.stunPort}
      full_trickle = true
    }
  '';

  janusWsConfigFile = pkgs.writeText "janus.transport.websockets.jcfg" ''
    general: {
      json = "indented"
      ws = true
      ws_port = ${toString cfg.janusWsPort}
      ws_ip = "127.0.0.1"
    }
  '';
in
{
  imports = [
    nixosModules.services.nginx
    ./secrets.nix
  ];

  options.services.nextcloud-talk-edge = {
    enable = lib.mkEnableOption "Nextcloud Talk High Performance Backend Edge Node";

    enableIpv4 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable IPv4 for this edge node.";
    };

    enableIpv6 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable IPv6 for this edge node.";
    };

    edgeDomain = lib.mkOption {
      type = lib.types.str;
      default = config.networking.fqdn;
      description = "Public domain name of this edge node (e.g., sjc0.dora.im).";
    };

    edgePublicIp = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Real public IPv4 address or DDNS domain of this edge node.";
    };

    edgePublicIpv6 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Real public IPv6 address or DDNS domain of this edge node for WebRTC.";
    };

    centralNatsHost = lib.mkOption {
      type = lib.types.str;
      default = "nue0.${domain}";
      description = "Central node public domain or IP for NATS message bus.";
    };

    centralNatsPort = lib.mkOption {
      type = lib.types.port;
      default = 4222;
      description = "Port of the central NATS server.";
    };

    centralNextcloudUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cloud.${domain}";
      description = "Public URL of the central Nextcloud instance.";
    };

    spreedSecretFile = lib.mkOption {
      type = lib.types.path;
      default = config.sops.templates."nextcloud-talk-hpb-backend-secret".path;
      description = "Path to the Spreed shared backend secret.";
    };

    turnSecretFile = lib.mkOption {
      type = lib.types.path;
      default = config.sops.secrets."matrix/turn_shared_secret".path;
      description = "Path to the Coturn static-auth-secret file.";
    };

    janusWsPort = lib.mkOption {
      type = lib.types.port;
      default = 8188;
      description = "Local WebSocket port for Janus WebRTC Gateway.";
    };

    edgePort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Custom public HTTPS port if non-standard (e.g. 50569).";
    };

    enableCoturn = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to run Coturn STUN/TURN on this edge node.";
    };

    stunServer = lib.mkOption {
      type = lib.types.str;
      default = if cfg.enableCoturn then "127.0.0.1" else "stun.nextcloud.com";
      description = "STUN server for Janus WebRTC Gateway NAT traversal.";
    };

    stunPort = lib.mkOption {
      type = lib.types.port;
      default = if cfg.enableCoturn then 3479 else 3478;
      description = "STUN server port.";
    };

    rtpPortRange = {
      min = lib.mkOption {
        type = lib.types.port;
        default = 49152;
        description = "Minimum UDP port for WebRTC media streams and TURN relay.";
      };
      max = lib.mkOption {
        type = lib.types.port;
        default = 65535;
        description = "Maximum UDP port for WebRTC media streams and TURN relay.";
      };
    };

    # ── gRPC 原生集群配置 ───────────────────────────────────────
    enableCluster = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable gRPC mesh clustering for nextcloud-spreed-signaling.";
    };

    grpcPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "gRPC cluster communication port.";
    };

    clusterTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of remote gRPC target endpoints in the signaling cluster (e.g. ['cu.mag:9090']).";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── 1. Janus WebRTC SFU 服务 ────────────────────────────────
    users.users.janus = {
      isSystemUser = true;
      group = "janus";
      description = "Janus WebRTC Gateway daemon user";
    };
    users.groups.janus = { };

    systemd.services.janus-gateway = {
      description = "Janus WebRTC Gateway (SFU Media Server)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "janus";
        Group = "janus";
        RuntimeDirectory = "janus janus/etc janus/transports";
        RuntimeDirectoryMode = "0755";
        Restart = "always";
        RestartSec = "3s";
        LimitNOFILE = 65536;
        ExecStartPre = pkgs.writeShellScript "janus-setup-config" ''
          RESOLVED_IPV4=""
          RESOLVED_IPV6=""

          ${lib.optionalString cfg.enableIpv4 ''
            EDGE_PUBLIC_IP="${if cfg.edgePublicIp != null then cfg.edgePublicIp else ""}"
            if [ -n "$EDGE_PUBLIC_IP" ]; then
              if echo "$EDGE_PUBLIC_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                RESOLVED_IPV4="$EDGE_PUBLIC_IP"
              else
                RESOLVED_IPV4="$(${pkgs.bind.dnsutils}/bin/dig +short +timeout=5 +tries=3 A "$EDGE_PUBLIC_IP" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n1)"
                if [ -z "$RESOLVED_IPV4" ]; then
                  RESOLVED_IPV4="$(${pkgs.glibc}/bin/getent ahostsv4 "$EDGE_PUBLIC_IP" 2>/dev/null | awk 'NR==1{print $1}')"
                fi
                if [ -z "$RESOLVED_IPV4" ]; then
                  echo "ERROR: cannot resolve edgePublicIp '$EDGE_PUBLIC_IP' to an IPv4 address" >&2
                  exit 1
                fi
                echo "Resolved DDNS IPv4 $EDGE_PUBLIC_IP -> $RESOLVED_IPV4"
              fi
            fi
          ''}

          ${lib.optionalString cfg.enableIpv6 ''
            EDGE_PUBLIC_IPV6="${if cfg.edgePublicIpv6 != null then cfg.edgePublicIpv6 else ""}"
            if [ -n "$EDGE_PUBLIC_IPV6" ]; then
              if echo "$EDGE_PUBLIC_IPV6" | grep -qE ':'; then
                RESOLVED_IPV6="$EDGE_PUBLIC_IPV6"
              else
                RESOLVED_IPV6="$(${pkgs.bind.dnsutils}/bin/dig +short +timeout=5 +tries=3 AAAA "$EDGE_PUBLIC_IPV6" @1.1.1.1 2>/dev/null | grep -E ':' | tail -n1)"
                if [ -z "$RESOLVED_IPV6" ]; then
                  RESOLVED_IPV6="$(${pkgs.glibc}/bin/getent ahostsv6 "$EDGE_PUBLIC_IPV6" 2>/dev/null | awk 'NR==1{print $1}')"
                fi
                if [ -z "$RESOLVED_IPV6" ]; then
                  echo "ERROR: cannot resolve edgePublicIpv6 '$EDGE_PUBLIC_IPV6' to an IPv6 address" >&2
                  exit 1
                fi
                echo "Resolved DDNS IPv6 $EDGE_PUBLIC_IPV6 -> $RESOLVED_IPV6"
              fi
            fi
          ''}

          if [ -n "$RESOLVED_IPV4" ] && [ -n "$RESOLVED_IPV6" ]; then
            MAPPING_IP="$RESOLVED_IPV4,$RESOLVED_IPV6"
          elif [ -n "$RESOLVED_IPV6" ]; then
            MAPPING_IP="$RESOLVED_IPV6"
          elif [ -n "$RESOLVED_IPV4" ]; then
            MAPPING_IP="$RESOLVED_IPV4"
          else
            echo "ERROR: no public IP configured for Janus NAT mapping" >&2
            exit 1
          fi

          ${pkgs.gnused}/bin/sed "s/__PUBLIC_IP__/$MAPPING_IP/g" ${janusConfigFile} > /run/janus/etc/janus.jcfg
          install -m 0644 ${janusWsConfigFile} /run/janus/etc/janus.transport.websockets.jcfg
          ln -sf ${pkgs.janus-gateway}/lib/janus/transports/libjanus_websockets.so* /run/janus/transports/
        '';
        ExecStart = "${pkgs.janus-gateway}/bin/janus -F /run/janus/etc ${lib.optionalString cfg.enableIpv6 "-6 "} -o";
      };
    };

    # ── 1b. DDNS 监控：当 IP 是域名时，定期检测 IP 变化并热重启 Janus ──
    systemd.services.janus-ddns-watch =
      lib.mkIf
        (
          (
            cfg.enableIpv4
            && cfg.edgePublicIp != null
            && builtins.match "^([0-9]{1,3}\\.){3}[0-9]{1,3}$" cfg.edgePublicIp == null
          )
          || (
            cfg.enableIpv6
            && cfg.edgePublicIpv6 != null
            && builtins.match "^[0-9a-fA-F:]+$" cfg.edgePublicIpv6 == null
          )
        )
        {
          description = "Watch DDNS IP change for Janus nat_1_1_mapping and restart if needed";
          after = [
            "network-online.target"
            "janus-gateway.service"
          ];
          wants = [ "network-online.target" ];
          path = [
            pkgs.bind.dnsutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.coreutils
          ];
          script = ''
            NEED_RESTART=0

            ${lib.optionalString
              (
                cfg.enableIpv4
                && cfg.edgePublicIp != null
                && builtins.match "^([0-9]{1,3}\\.){3}[0-9]{1,3}$" cfg.edgePublicIp == null
              )
              ''
                NEW_IPV4="$(dig +short +timeout=5 +tries=3 A "${cfg.edgePublicIp}" @1.1.1.1 2>/dev/null \
                  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n1)"
                CURRENT_IPV4="$(grep 'nat_1_1_mapping' /run/janus/etc/janus.jcfg 2>/dev/null \
                  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
                if [ -n "$NEW_IPV4" ] && [ "$NEW_IPV4" != "$CURRENT_IPV4" ]; then
                  echo "DDNS IPv4 changed: $CURRENT_IPV4 -> $NEW_IPV4"
                  NEED_RESTART=1
                fi
              ''
            }

            ${lib.optionalString
              (
                cfg.enableIpv6
                && cfg.edgePublicIpv6 != null
                && builtins.match "^[0-9a-fA-F:]+$" cfg.edgePublicIpv6 == null
              )
              ''
                NEW_IPV6="$(dig +short +timeout=5 +tries=3 AAAA "${cfg.edgePublicIpv6}" @1.1.1.1 2>/dev/null \
                  | grep -E ':' | tail -n1)"
                CURRENT_IPV6="$(grep 'nat_1_1_mapping' /run/janus/etc/janus.jcfg 2>/dev/null \
                  | grep -oE '[0-9a-fA-F:]+' | grep ':' | head -n1)"
                if [ -n "$NEW_IPV6" ] && [ "$NEW_IPV6" != "$CURRENT_IPV6" ]; then
                  echo "DDNS IPv6 changed: $CURRENT_IPV6 -> $NEW_IPV6"
                  NEED_RESTART=1
                fi
              ''
            }

            if [ "$NEED_RESTART" = "1" ]; then
              echo "Restarting janus-gateway to apply new IP..."
              systemctl restart janus-gateway.service
            fi
          '';
          serviceConfig = {
            Type = "oneshot";
          };
        };

    systemd.timers.janus-ddns-watch =
      lib.mkIf
        (
          (
            cfg.enableIpv4
            && cfg.edgePublicIp != null
            && builtins.match "^([0-9]{1,3}\\.){3}[0-9]{1,3}$" cfg.edgePublicIp == null
          )
          || (
            cfg.enableIpv6
            && cfg.edgePublicIpv6 != null
            && builtins.match "^[0-9a-fA-F:]+$" cfg.edgePublicIpv6 == null
          )
        )
        {
          description = "Periodically check DDNS IP change for Janus";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnCalendar = "*:0/1";
            Persistent = true;
          };
        };

    # ── 2. Spreed 信令服务 (HPB) ────────────────────────────────
    services.nextcloud-spreed-signaling = {
      enable = true;
      hostName = cfg.edgeDomain;
      backends.nextcloud = {
        urls = [ cfg.centralNextcloudUrl ];
        secretFile = cfg.spreedSecretFile;
      };
      settings = {
        clients.internalsecretFile = config.sops.templates."nextcloud-talk-hpb-internal-secret".path;
        sessions = {
          hashkeyFile = "/run/nextcloud-spreed-signaling/hashkey";
          blockkeyFile = "/run/nextcloud-spreed-signaling/blockkey";
        };
        http.listen = "127.0.0.1:${toString config.ports.nextcloud-talk-hpb}";
        # 连接中心节点的 NATS 消息总线
        nats.url = [ "nats://${cfg.centralNatsHost}:${toString cfg.centralNatsPort}" ];
        # MCU 连接本机 Janus WebRTC SFU
        mcu = {
          type = "janus";
          url = "ws://127.0.0.1:${toString cfg.janusWsPort}";
        };
        # 客户端公网访问前缀
        appinfo.public_url = "https://${cfg.edgeDomain}${
          lib.optionalString (cfg.edgePort != null) ":${toString cfg.edgePort}"
        }/standalone-signaling/";

        # gRPC 集群节点间直连互联
        grpc = lib.optionalAttrs cfg.enableCluster {
          listen = "0.0.0.0:${toString cfg.grpcPort}";
          targettype = "static";
          targets = cfg.clusterTargets;
        };
      };
    };

    systemd.services.nextcloud-spreed-signaling = {
      after = [ "janus-gateway.service" ];
      requires = [ "janus-gateway.service" ];
      preStart = lib.mkBefore ''
        head -c 32 ${
          config.sops.templates."nextcloud-talk-hpb-hashkey".path
        } > /run/nextcloud-spreed-signaling/hashkey
        head -c 32 ${
          config.sops.templates."nextcloud-talk-hpb-blockkey".path
        } > /run/nextcloud-spreed-signaling/blockkey
        chmod 0400 /run/nextcloud-spreed-signaling/hashkey /run/nextcloud-spreed-signaling/blockkey
      '';
    };

    # ── 3. Coturn STUN & TURN 中继服务 ──────────────────────────
    services.coturn = lib.mkIf cfg.enableCoturn {
      enable = true;
      listening-port = lib.mkDefault 3479;
      tls-listening-port = lib.mkDefault 5349;
      use-auth-secret = lib.mkDefault true;
      static-auth-secret-file = lib.mkDefault cfg.turnSecretFile;
      realm = lib.mkForce cfg.edgeDomain;
      min-port = lib.mkForce cfg.rtpPortRange.min;
      max-port = lib.mkForce cfg.rtpPortRange.max;
      no-cli = lib.mkDefault true;
      cert = lib.mkDefault "${config.security.acme.certs."main".directory}/fullchain.pem";
      pkey = lib.mkDefault "${config.security.acme.certs."main".directory}/key.pem";
      no-tcp-relay = lib.mkDefault false;
      extraConfig = ''
        ${lib.optionalString (cfg.enableIpv4 && cfg.edgePublicIp != null) ''
          external-ip=${cfg.edgePublicIp}
          relay-ip=${cfg.edgePublicIp}
        ''}
        ${lib.optionalString (cfg.enableIpv6 && cfg.edgePublicIpv6 != null) ''
          external-ip=${cfg.edgePublicIpv6}
          relay-ip=${cfg.edgePublicIpv6}
        ''}
        no-loopback-peers
      '';
    };

    systemd.services.coturn = lib.mkIf cfg.enableCoturn {
      serviceConfig.StateDirectory = "coturn";
      serviceConfig.Group = lib.mkForce "acme";
    };

    # ── 4. Nginx 边缘反向代理（复用 https://{fqdn}）──────────────
    services.nginx.virtualHosts."${cfg.edgeDomain}".locations = {
      "/standalone-signaling/" = {
        proxyPass = "http://127.0.0.1:${toString config.ports.nextcloud-talk-hpb}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 86400s;
          proxy_send_timeout 86400s;
          proxy_buffering off;
          client_max_body_size 0;
        '';
      };
      "/standalone-signaling" = {
        return = "301 /standalone-signaling/";
      };
    };

    services.traefik.proxies.talk-edge-signaling = {
      rule = "Host(`${cfg.edgeDomain}`) && PathPrefix(`/standalone-signaling`)";
      target = "http://127.0.0.1:${toString config.ports.nginx}";
      priority = 100;
    };

    # ── 5. 防火墙端口放行 ────────────────────────────────────────
    networking.firewall = {
      allowedTCPPorts = [
        80
        443
      ]
      ++ lib.optionals cfg.enableCluster [
        cfg.grpcPort # gRPC 集群端口
      ]
      ++ lib.optionals cfg.enableCoturn [
        3479 # Coturn TURN TCP
        5349 # Coturn TURNS TCP
      ];
      allowedUDPPorts = lib.optionals cfg.enableCoturn [
        3479 # Coturn STUN/TURN UDP
        5349 # Coturn TURNS UDP
      ];
      # Janus WebRTC SFU 始终需要这个 UDP 端口范围用于媒体流（ICE），
      # 与是否启用 Coturn 无关。cu 节点 enableCoturn=false 时此范围仍必须放行！
      allowedUDPPortRanges = [
        {
          from = cfg.rtpPortRange.min;
          to = cfg.rtpPortRange.max;
        }
      ];
    };
  };
}
