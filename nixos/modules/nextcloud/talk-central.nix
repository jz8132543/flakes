{
  config,
  lib,
  ...
}:
let
  cfg = config.services.nextcloud-talk-central;
  occ = config.services.nextcloud.occ;
  domain = config.networking.domain;
in
{
  imports = [
    ./secrets.nix
  ];

  options.services.nextcloud-talk-central = {
    enable = lib.mkEnableOption "Nextcloud Talk High Performance Backend Central Controller";

    internalIp = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.1";
      description = "Virtual overlay network IP (Tailscale) on which NATS will listen.";
    };

    internalInterface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Network interface name for the internal overlay mesh.";
    };

    natsPort = lib.mkOption {
      type = lib.types.port;
      default = 4222;
      description = "NATS client communication port.";
    };

    natsClusterPort = lib.mkOption {
      type = lib.types.port;
      default = 6222;
      description = "NATS cluster routing port.";
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

    edgeNodes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Identifier for the edge node.";
            };
            fqdn = lib.mkOption {
              type = lib.types.str;
              description = "FQDN of the edge node (e.g., sjc0.dora.im).";
            };
            port = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = "Custom public HTTPS port if non-standard (e.g. 50569).";
            };
            publicIp = lib.mkOption {
              type = lib.types.str;
              description = "Public IPv4 of the edge node.";
            };
            hasSignaling = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this node provides Spreed signaling.";
            };
            hasTurn = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this node provides STUN/TURN services.";
            };
            verify = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to pass --verify when adding signaling server in OCC.";
            };
          };
        }
      );
      default = [
        {
          name = "sjc0";
          fqdn = "sjc0.${domain}";
          publicIp = "45.143.130.230";
          hasSignaling = true;
          hasTurn = true;
        }
      ];
      description = "List of edge signaling/TURN nodes in the cluster.";
    };

    enableLocalSignaling = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to also register/run a local HPB signaling instance on the central node.";
    };

    localSignalingHost = lib.mkOption {
      type = lib.types.str;
      default = "talk.${domain}";
      description = "Public domain for the central signaling server.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── 1. NATS 内部消息总线（绝不监听在 0.0.0.0）─────────────────
    services.nats = {
      enable = true;
      serverName = "nats-${config.networking.hostName}";
      settings = {
        # 严格绑定于虚拟内网 IP
        listen = "${cfg.internalIp}:${toString cfg.natsPort}";
        jetstream = lib.mkForce "disabled";
      };
    };

    # 防火墙：仅在虚拟内网网卡上放行 NATS 端口
    networking.firewall.interfaces."${cfg.internalInterface}".allowedTCPPorts = [
      cfg.natsPort
      cfg.natsClusterPort
    ];

    # ── 2. 中心可选本地 HPB 信令服务 ──────────────────────────────
    services.nextcloud-spreed-signaling = lib.mkIf cfg.enableLocalSignaling {
      enable = true;
      hostName = cfg.localSignalingHost;
      backends.nextcloud = {
        urls = [ "https://cloud.${domain}" ];
        secretFile = cfg.spreedSecretFile;
      };
      settings = {
        clients.internalsecretFile = config.sops.templates."nextcloud-talk-hpb-internal-secret".path;
        sessions = {
          hashkeyFile = "/run/nextcloud-spreed-signaling/hashkey";
          blockkeyFile = "/run/nextcloud-spreed-signaling/blockkey";
        };
        nats.url = [ "nats://${cfg.internalIp}:${toString cfg.natsPort}" ];
        http.listen = "127.0.0.1:${toString config.ports.nextcloud-talk-hpb}";
      };
    };

    systemd.services.nextcloud-spreed-signaling = lib.mkIf cfg.enableLocalSignaling {
      after = [ "nats.service" ];
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

    services.traefik.proxies = lib.mkIf cfg.enableLocalSignaling {
      nextcloud-talk-hpb = {
        rule = "Host(`${cfg.localSignalingHost}`)";
        target = "http://localhost:${toString config.ports.nextcloud-talk-hpb}";
      };
    };

    # ── 3. 声明式注册集群节点至 Nextcloud 核心（occ）────────────
    systemd.services.nextcloud-setup-talk-hpb = {
      description = "Declarative Nextcloud Talk HPB Cluster Registration";
      wantedBy = [ "multi-user.target" ];
      after = [
        "nextcloud-setup.service"
        "nats.service"
      ]
      ++ lib.optional cfg.enableLocalSignaling "nextcloud-spreed-signaling.service";
      requires = [ "nextcloud-setup.service" ];

      script = ''
        set -eu
        SIGNALING_SECRET="$(cat ${cfg.spreedSecretFile})"
        TURN_SECRET="$(cat ${cfg.turnSecretFile})"

        # ── 确保全局高清传输配置生效 ──
        ${occ}/bin/nextcloud-occ config:app:set spreed max_video_resolution --value "7680" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_video_framerate --value "180" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_video_bitrate --value "200000000" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_screen_resolution --value "7680" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_screen_framerate --value "180" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_screen_bitrate --value "200000000" || true

        # ── 注册中心本地信令服务（若启用）──
        ${lib.optionalString cfg.enableLocalSignaling ''
          LOCAL_SIG_URL="wss://${cfg.localSignalingHost}"
          if ! ${occ}/bin/nextcloud-occ talk:signaling:list 2>/dev/null | grep -Fq "$LOCAL_SIG_URL"; then
            ${occ}/bin/nextcloud-occ talk:signaling:add "$LOCAL_SIG_URL" "$SIGNALING_SECRET" --verify || true
          fi
        ''}

        # ── 注册所有边缘节点 ──
        ${lib.concatMapStringsSep "\n" (node: ''
          # --- 节点: ${node.name} (${node.fqdn}) ---
          ${lib.optionalString node.hasSignaling ''
            EDGE_SIG_URL="https://${node.fqdn}${
              lib.optionalString (node.port != null) ":${toString node.port}"
            }/standalone-signaling/"
            if ! ${occ}/bin/nextcloud-occ talk:signaling:list 2>/dev/null | grep -Fq "$EDGE_SIG_URL"; then
              ${occ}/bin/nextcloud-occ talk:signaling:add "$EDGE_SIG_URL" "$SIGNALING_SECRET" ${lib.optionalString node.verify "--verify"} || true
            fi
          ''}

          ${lib.optionalString node.hasTurn ''
            # 注册 STUN
            if ! ${occ}/bin/nextcloud-occ talk:stun:list --output=json 2>/dev/null | grep -Fq "${node.fqdn}:3479"; then
              ${occ}/bin/nextcloud-occ talk:stun:add "${node.fqdn}:3479" || true
            fi

            # 注册 TURN (UDP/TCP 3479)
            if ! ${occ}/bin/nextcloud-occ talk:turn:list --output=json 2>/dev/null | grep -Fq "${node.fqdn}:3479"; then
              ${occ}/bin/nextcloud-occ talk:turn:add turn "${node.fqdn}:3479" udp,tcp --secret="$TURN_SECRET" || true
            fi

            # 注册 TURNS (TLS TCP 5349)
            if ! ${occ}/bin/nextcloud-occ talk:turn:list --output=json 2>/dev/null | grep -Fq "${node.fqdn}:5349"; then
              ${occ}/bin/nextcloud-occ talk:turn:add turns "${node.fqdn}:5349" tcp --secret="$TURN_SECRET" || true
            fi
          ''}
        '') cfg.edgeNodes}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
