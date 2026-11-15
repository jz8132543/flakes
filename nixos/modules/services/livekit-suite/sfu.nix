{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.livekitSuite;
  s = cfg.settings;
  inherit (cfg) topology;
  redis =
    if cfg.redisAddress != "" then
      cfg.redisAddress
    else if builtins.length topology.redisNodes == 1 then
      let
        node = builtins.head topology.redisNodes;
      in
      "${node.privateAddress}:${toString node.redisPort}"
    else
      throw "LiveKit suite requires exactly one Redis primary or an explicit redisAddress (independent Redis instances are not a mesh).";
  base = pkgs.writeText "livekit-suite-sfu.json" (
    builtins.toJSON {
      port = s.server.signalingPort;
      bind_addresses = [ "127.0.0.1" ];
      region = cfg._meta.region;
      redis.address = redis;
      rtc = {
        tcp_port = s.server.tcpPort;
        port_range_start = s.server.udpPortStart;
        port_range_end = s.server.udpPortEnd;
        use_external_ip = cfg._meta.publicIpv4 == "" && cfg._meta.publicIpv6 == "";
        node_ip = if cfg._meta.publicIpv4 != "" then cfg._meta.publicIpv4 else cfg._meta.publicIpv6;
        interfaces.includes = cfg.interfaces;
        stun_servers = map (node: "${node.turnDomain}:${toString node.turnPort}") topology.turnNodes;
        turn_servers = topology.turnServers;
        packet_buffer_size_video = s.server.packetBufferVideo;
        packet_buffer_size_audio = s.server.packetBufferAudio;
        pli_throttle = s.server.pliThrottle;
        congestion_control = s.server.congestionControl;
        allow_tcp_fallback = s.server.allowTcpFallback;
      };
      room = s.room // {
        enabled_codecs = map (codec: { mime = codec; }) (
          [
            "audio/opus"
            "audio/red"
            "video/rtx"
          ]
          ++ map (codec: "video/${codec}") s.media.video.codecPriority
        );
      };
      audio.active_red_encoding = s.media.voice.red;
      node_selector = s.server.nodeSelector // {
        regions = lib.unique (
          map (node: {
            name = node.region;
            lat = node.latitude;
            lon = node.longitude;
          }) topology.sfuNodes
        );
      };
      logging = {
        level = "info";
        json = true;
      };
    }
  );
in
{
  options.services.livekitSuite.sfu.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };
  config = lib.mkMerge [
    { services.livekitSuite._meta.roles.sfu = cfg.sfu.enable; }
    (lib.mkIf cfg.sfu.enable {
      assertions = [
        {
          assertion = cfg._meta.domain != "";
          message = "LiveKit SFU needs a TLS signaling domain in _meta.domain.";
        }
        {
          assertion = s.server.nodeSelector.kind != "regionaware" || cfg._meta.region != "";
          message = "Region-aware LiveKit selection requires a nonempty _meta.region.";
        }
        {
          assertion = s.server.udpPortStart <= s.server.udpPortEnd;
          message = "Invalid LiveKit UDP range.";
        }
      ];
      networking.firewall = {
        allowedTCPPorts = [ s.server.tcpPort ];
        allowedUDPPortRanges = [
          {
            from = s.server.udpPortStart;
            to = s.server.udpPortEnd;
          }
        ];
      };
      systemd.services.livekit-suite-sfu = {
        description = "LiveKit distributed SFU";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.development "livekit-suite-development-secret.service";
        requires = lib.optional cfg.development "livekit-suite-development-secret.service";
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./runtime.py} sfu ${base} ${lib.getExe pkgs.livekit}";
          LoadCredential = [ "master:${cfg.secretFile}" ];
          DynamicUser = true;
          RuntimeDirectory = "livekit-suite-sfu";
          Environment = "SUITE_RUNTIME=/run/livekit-suite-sfu";
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          LimitNOFILE = 1048576;
        };
      };
    })
  ];
}
