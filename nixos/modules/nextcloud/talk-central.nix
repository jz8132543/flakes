{
  config,
  lib,
  pkgs,
  ...
}:
let
  data = import ./data.nix;
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

    natsListen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "IP address or wildcard on which NATS will listen.";
    };

    natsPort = lib.mkOption {
      type = lib.types.port;
      default = data.nats.port;
      description = "NATS client communication port.";
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
      type = lib.types.listOf lib.types.attrs;
      default = data.edgeNodes;
      description = "List of edge signaling/TURN nodes in the cluster (default from data.nix).";
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
    # ── 1. NATS 公网 TLS + 认证消息总线 ─────────────────────────
    # 凭据由 sops template 渲染，完全隔离于 Nix store 之外；
    # 证书复用 ACME "main" 通配符证书，nats 服务加入 acme 组并配置证书续期重载。
    sops.templates."nats.conf" = {
      content = ''
        listen: "${cfg.natsListen}:${toString cfg.natsPort}"
        server_name: "nats-${config.networking.hostName}"
        jetstream: "disabled"
        tls: {
          cert_file: "${config.security.acme.certs."main".directory}/fullchain.pem"
          key_file: "${config.security.acme.certs."main".directory}/key.pem"
          timeout: 5
        }
        authorization: {
          user: "spreed"
          password: "${config.sops.placeholder."nextcloud/nats-credentials"}"
        }
      '';
      owner = "nats";
      group = "acme";
      mode = "0400";
    };

    services.nats = {
      enable = true;
      # 凭据由 sops template 在运行时渲染，跳过构建期静态校验
      validateConfig = false;
    };

    systemd.services.nats = {
      after = [ "sops-nix.service" ];
      serviceConfig = {
        SupplementaryGroups = [ "acme" ];
        ExecStart = lib.mkForce "${pkgs.nats-server}/bin/nats-server -c ${
          config.sops.templates."nats.conf".path
        }";
      };
    };

    # ACME 证书续期后重载 NATS 服务
    security.acme.certs."main".reloadServices = [ "nats.service" ];

    # 防火墙：仅放行 NATS TLS 端口（显式禁用并不再放行 6222 cluster 端口）
    networking.firewall.allowedTCPPorts = [
      cfg.natsPort
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
        # 本地信令通过 TLS + 运行时凭据接入 NATS
        nats.url = [
          "tls://spreed:${
            config.sops.placeholder."nextcloud/nats-credentials"
          }@127.0.0.1:${toString cfg.natsPort}"
        ];
        http.listen = "127.0.0.1:${toString config.ports.nextcloud-talk-hpb}";
      };
    };

    systemd.services.nextcloud-spreed-signaling = lib.mkIf cfg.enableLocalSignaling {
      after = [
        "nats.service"
        "sops-nix.service"
      ];
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
    # 注释：
    # 关于 TURN 凭据 TTL：
    # 上游 Nextcloud Talk (nextcloud-app-spreed) 在 lib/Config.php:516 中硬编码了 24 小时有效时间：
    #   $timestamp = $this->timeFactory->getTime() + 86400; // FIXME add the TTL to the response and properly reconnect then
    # 目前上游不支持通过配置项修改为 7 天，因此维持 24 小时刷新机制。
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

        # ── 确保全局高清与信令集群配置生效 ──
        ${occ}/bin/nextcloud-occ config:app:set spreed signaling_mode --value "external" || echo "Warning: failed to set signaling_mode to external" >&2 || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_video_resolution --value "7680" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_video_framerate --value "180" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_video_bitrate --value "200000000" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_screen_resolution --value "7680" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_screen_framerate --value "180" || true
        ${occ}/bin/nextcloud-occ config:app:set spreed max_screen_bitrate --value "200000000" || true

        # ── 清理未在当前期望配置中的废弃信令服务器 ──
        EXPECTED_SERVERS="${lib.optionalString cfg.enableLocalSignaling "wss://${cfg.localSignalingHost} "}${
          lib.concatMapStringsSep " " (
            node:
            lib.optionalString (node.hasSignaling or true)
              "https://${node.fqdn}${
                lib.optionalString (node.edgePort or (node.port or null) != null)
                  ":${toString (if node.edgePort != null then node.edgePort else node.port)}"
              }/standalone-signaling/"
          ) cfg.edgeNodes
        }"

        ${occ}/bin/nextcloud-occ talk:signaling:list --output=json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.servers[]?.server // empty' \
          | while read -r srv; do
              case " $EXPECTED_SERVERS " in
                *" $srv "*) ;; # 期望节点，保留
                *)
                  echo "Removing obsolete signaling server: $srv"
                  ${occ}/bin/nextcloud-occ talk:signaling:delete "$srv" || echo "Warning: failed to delete signaling server $srv" >&2 || true
                  ;;
              esac
            done

        # ── 清理未在当前期望配置中的废弃 STUN 服务器 ──
        EXPECTED_STUN="${
          lib.concatMapStringsSep " " (
            node: lib.optionalString (node.hasTurn or true) "${node.fqdn}:${toString data.turn.port}"
          ) cfg.edgeNodes
        }"

        ${occ}/bin/nextcloud-occ talk:stun:list --output=json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.[] // empty' \
          | while read -r srv; do
              case " $EXPECTED_STUN " in
                *" $srv "*) ;; # 期望节点，保留
                *)
                  echo "Removing obsolete stun server: $srv"
                  ${occ}/bin/nextcloud-occ talk:stun:delete "$srv" || echo "Warning: failed to delete stun server $srv" >&2 || true
                  ;;
              esac
            done

        # ── 清理未在当前期望配置中的废弃 TURN 服务器 ──
        EXPECTED_TURN="${
          lib.concatMapStringsSep " " (
            node:
            lib.optionalString (node.hasTurn or true
            ) "${node.fqdn}:${toString data.turn.port} ${node.fqdn}:${toString data.turn.tlsPort}"
          ) cfg.edgeNodes
        }"

        ${occ}/bin/nextcloud-occ talk:turn:list --output=json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.[] | "\(.schemes) \(.server) \(.protocols)"' \
          | while read -r schemes srv protocols; do
              case " $EXPECTED_TURN " in
                *" $srv "*) ;; # 期望节点，保留
                *)
                  echo "Removing obsolete turn server: $schemes $srv $protocols"
                  ${occ}/bin/nextcloud-occ talk:turn:delete "$schemes" "$srv" "$protocols" || echo "Warning: failed to delete turn server $srv" >&2 || true
                  ;;
              esac
            done

        # ── 确保 Nextcloud Talk 信令模式为 conversation_cluster（同房间固定同一信令/MCU 节点，解决视频通话黑屏/转圈）──
        CURRENT_MODE="$(${occ}/bin/nextcloud-occ config:app:get spreed signaling_mode 2>/dev/null || true)"
        if [ "$CURRENT_MODE" != "conversation_cluster" ]; then
          echo "Setting Talk signaling_mode to conversation_cluster..."
          ${occ}/bin/nextcloud-occ config:app:set spreed signaling_mode --value=conversation_cluster || echo "Warning: failed to set signaling_mode to conversation_cluster" >&2 || true
        fi

        # ── 注册中心本地信令服务（若启用）──
        ${lib.optionalString cfg.enableLocalSignaling ''
          LOCAL_SIG_URL="wss://${cfg.localSignalingHost}"
          if ! ${occ}/bin/nextcloud-occ talk:signaling:list 2>/dev/null | grep -Fq "$LOCAL_SIG_URL"; then
            ${occ}/bin/nextcloud-occ talk:signaling:add "$LOCAL_SIG_URL" "$SIGNALING_SECRET" --verify || echo "Warning: failed to register local signaling server" >&2 || true
          fi
        ''}

        # ── 注册所有边缘节点 ──
        ${lib.concatMapStringsSep "\n" (
          node:
          let
            portNum = if (node.edgePort or null) != null then node.edgePort else (node.port or null);
            inboundFromForeign = node.inboundFromForeign or true;
          in
          ''
            # --- 节点: ${node.name} (${node.fqdn}) ---
            ${lib.optionalString (node.hasSignaling or true) ''
              EDGE_SIG_URL="https://${node.fqdn}${
                lib.optionalString (portNum != null) ":${toString portNum}"
              }/standalone-signaling/"
              if ! ${occ}/bin/nextcloud-occ talk:signaling:list 2>/dev/null | grep -Fq "$EDGE_SIG_URL"; then
                ${
                  if inboundFromForeign then
                    ''
                      echo "Adding signaling server: $EDGE_SIG_URL (with --verify)..."
                      ${occ}/bin/nextcloud-occ talk:signaling:add "$EDGE_SIG_URL" "$SIGNALING_SECRET" --verify || echo "Warning: talk:signaling:add with --verify failed for ${node.name}" >&2 || true
                    ''
                  else
                    ''
                      echo "Notice: 节点 ${node.name} inboundFromForeign=false，跳过 --verify（该节点无法从国外中心直接探测，Talk 面板可能显示 Error，属预期）"
                      ${occ}/bin/nextcloud-occ talk:signaling:add "$EDGE_SIG_URL" "$SIGNALING_SECRET" || echo "Warning: talk:signaling:add without --verify failed for ${node.name}" >&2 || true
                    ''
                }
              fi
            ''}

            ${lib.optionalString (node.hasTurn or true) ''
              # 注册 STUN
              if ! ${occ}/bin/nextcloud-occ talk:stun:list --output=json 2>/dev/null | grep -Fq "${node.fqdn}:${toString data.turn.port}"; then
                ${occ}/bin/nextcloud-occ talk:stun:add "${node.fqdn}:${toString data.turn.port}" || echo "Warning: failed to add stun server ${node.fqdn}" >&2 || true
              fi

              # 注册 TURN (UDP/TCP ${toString data.turn.port})
              if ! ${occ}/bin/nextcloud-occ talk:turn:list --output=json 2>/dev/null | grep -Fq "${node.fqdn}:${toString data.turn.port}"; then
                ${occ}/bin/nextcloud-occ talk:turn:add turn "${node.fqdn}:${toString data.turn.port}" udp,tcp --secret="$TURN_SECRET" || echo "Warning: failed to add turn server ${node.fqdn}" >&2 || true
              fi

              # 注册 TURNS (TLS TCP ${toString data.turn.tlsPort})
              if ! ${occ}/bin/nextcloud-occ talk:turn:list --output=json 2>/dev/null | grep -Fq "${node.fqdn}:${toString data.turn.tlsPort}"; then
                ${occ}/bin/nextcloud-occ talk:turn:add turns "${node.fqdn}:${toString data.turn.tlsPort}" tcp --secret="$TURN_SECRET" || echo "Warning: failed to add turns server ${node.fqdn}" >&2 || true
              fi
            ''}
          ''
        ) cfg.edgeNodes}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
