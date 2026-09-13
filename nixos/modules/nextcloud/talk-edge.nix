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

  # ── 生成 Janus WebRTC Gateway 配置文件 ───────────────────────
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
      # ⚠️ 踩坑防护：必须排除虚拟内网网卡（如 Tailscale/Docker），防止将内网 IP 广播给公网客户端导致黑屏
      nic_ign = "tailscale0,docker0,nebula.mag,lo,dummy*,tun*,tap*"
      nat_1_1_mapping = "${cfg.edgePublicIp}"
      ignore_mdns = true
      stun_server = "${cfg.stunServer}"
      stun_port = ${toString cfg.stunPort}
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

    edgeDomain = lib.mkOption {
      type = lib.types.str;
      default = config.networking.fqdn;
      description = "Public domain name of this edge node (e.g., sjc0.dora.im).";
    };

    edgePublicIp = lib.mkOption {
      type = lib.types.str;
      description = "Real public IPv4 address of this edge node.";
    };

    centralInternalIp = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.1";
      description = "Central node IP in the virtual overlay network (Tailscale).";
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
      default = if cfg.enableCoturn then 3479 else 443;
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
      after = [ "network.target" ];
      serviceConfig = {
        User = "janus";
        Group = "janus";
        RuntimeDirectory = "janus janus/etc janus/transports";
        RuntimeDirectoryMode = "0755";
        Restart = "always";
        RestartSec = "3s";
        LimitNOFILE = 65536;
        ExecStartPre = pkgs.writeShellScript "janus-setup-config" ''
          install -m 0644 ${janusConfigFile} /run/janus/etc/janus.jcfg
          install -m 0644 ${janusWsConfigFile} /run/janus/etc/janus.transport.websockets.jcfg
          ln -sf ${pkgs.janus-gateway}/lib/janus/transports/libjanus_websockets.so* /run/janus/transports/
        '';
        ExecStart = "${pkgs.janus-gateway}/bin/janus -F /run/janus/etc -N -o";
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
        nats.url = [ "nats://${cfg.centralInternalIp}:4222" ];
        # MCU 连接本机 Janus WebRTC SFU
        mcu = {
          type = "janus";
          url = "ws://127.0.0.1:${toString cfg.janusWsPort}";
        };
        # 客户端公网访问前缀
        appinfo.public_url = "https://${cfg.edgeDomain}${
          lib.optionalString (cfg.edgePort != null) ":${toString cfg.edgePort}"
        }/standalone-signaling/";
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
        external-ip=${cfg.edgePublicIp}
        relay-ip=${cfg.edgePublicIp}
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
      ++ lib.optionals cfg.enableCoturn [
        3479 # Coturn TURN TCP
        5349 # Coturn TURNS TCP
      ];
      allowedUDPPorts = lib.optionals cfg.enableCoturn [
        3479 # Coturn STUN/TURN UDP
        5349 # Coturn TURNS UDP
      ];
      allowedUDPPortRanges = lib.optionals cfg.enableCoturn [
        {
          from = cfg.rtpPortRange.min;
          to = cfg.rtpPortRange.max;
        }
      ];
    };
  };
}
