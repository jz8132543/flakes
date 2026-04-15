{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
let
  cfg = config.services.matrix-rtc;
  synapseServerName = config.services.matrix-synapse.settings.server_name;
  livekitRuntimeDirectory = "matrix-rtc-livekit";
  jwtRuntimeDirectory = "matrix-rtc-jwt";
  livekitKeysFile = "/run/${livekitRuntimeDirectory}/livekit.keys";
  jwtKeysFile = "/run/${jwtRuntimeDirectory}/livekit.keys";
  turnSharedSecretPath = config.sops.secrets."matrix/turn_shared_secret".path;
  livekitConfigFile = pkgs.writeText "matrix-rtc-livekit.yaml" ''
        audio:
          active_red_encoding: true

        room:
          enabled_codecs:
    ${lib.concatMapStringsSep "\n" (mime: "        - mime: ${mime}") [
      "audio/opus"
      "audio/red"
      "video/av1"
      "video/vp9"
      "video/vp8"
      "video/h264"
      "video/rtx"
    ]}
  '';
  livekitSetupScript = pkgs.writeShellScript "matrix-rtc-livekit-setup" ''
    install -d -m 0700 "$RUNTIME_DIRECTORY"
    printf '%s: %s\n' ${lib.escapeShellArg cfg.livekitApiKey} "$(cat "$CREDENTIALS_DIRECTORY/turn_shared_secret")" > ${livekitKeysFile}
    chmod 0400 ${livekitKeysFile}
  '';
  jwtSetupScript = pkgs.writeShellScript "matrix-rtc-jwt-setup" ''
    install -d -m 0700 "$RUNTIME_DIRECTORY"
    printf '%s: %s\n' ${lib.escapeShellArg cfg.livekitApiKey} "$(cat "$CREDENTIALS_DIRECTORY/turn_shared_secret")" > ${jwtKeysFile}
    chmod 0400 ${jwtKeysFile}
  '';
in
{
  imports = [ nixosModules.services.traefik ];

  options.services.matrix-rtc = {
    enable = lib.mkEnableOption "MatrixRTC LiveKit backend";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.fqdn;
      description = "Public hostname used for the MatrixRTC backend.";
    };

    jwtPort = lib.mkOption {
      type = lib.types.port;
      default = 8070;
    };

    livekitHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 7880;
    };

    livekitIceTcpPort = lib.mkOption {
      type = lib.types.port;
      default = 7881;
    };

    livekitIceUdpRangeStart = lib.mkOption {
      type = lib.types.port;
      default = 50000;
    };

    livekitIceUdpRangeEnd = lib.mkOption {
      type = lib.types.port;
      default = 60000;
    };

    fullAccessHomeservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optionals config.services.matrix-synapse.enable [ synapseServerName ];
      description = "Homeservers that may auto-create LiveKit rooms; defaults to the local Matrix Synapse server_name when Synapse is enabled.";
    };

    livekitApiKey = lib.mkOption {
      type = lib.types.str;
      default = "matrixrtc";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.mkIf (!config.services.matrix-synapse.enable) {
      "matrix/turn_shared_secret" = { };
    };

    services.traefik.proxies = {
      matrixrtc-jwt = {
        rule = "Host(`${cfg.hostName}`) && PathPrefix(`/livekit/jwt`)";
        target = "http://127.0.0.1:${toString cfg.jwtPort}";
        middlewares = [ "matrixrtc-jwt-stripprefix" ];
      };
      matrixrtc-sfu = {
        rule = "Host(`${cfg.hostName}`) && PathPrefix(`/livekit/sfu`)";
        target = "http://127.0.0.1:${toString cfg.livekitHttpPort}";
        middlewares = [ "matrixrtc-sfu-stripprefix" ];
      };
    };

    services.traefik.dynamicConfigOptions.http.middlewares = {
      matrixrtc-jwt-stripprefix.stripPrefix.prefixes = [ "/livekit/jwt" ];
      matrixrtc-sfu-stripprefix.stripPrefix.prefixes = [ "/livekit/sfu" ];
    };

    systemd.services."matrix-rtc-livekit" = {
      description = "MatrixRTC LiveKit SFU";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = true;
      serviceConfig = {
        DynamicUser = true;
        Restart = "always";
        RestartSec = "5s";
        RuntimeDirectory = livekitRuntimeDirectory;
        LoadCredential = [ "turn_shared_secret:${turnSharedSecretPath}" ];
        ExecStartPre = "${livekitSetupScript}";
        ExecStart = "${lib.getExe pkgs.livekit} --bind 127.0.0.1 --key-file ${livekitKeysFile} --config ${livekitConfigFile}";
      };
    };

    systemd.services."matrix-rtc-jwt" = {
      description = "MatrixRTC authorization service";
      after = [
        "network-online.target"
        "matrix-rtc-livekit.service"
      ];
      wants = [
        "network-online.target"
        "matrix-rtc-livekit.service"
      ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = true;
      serviceConfig = {
        DynamicUser = true;
        Restart = "always";
        RestartSec = "5s";
        RuntimeDirectory = jwtRuntimeDirectory;
        LoadCredential = [ "turn_shared_secret:${turnSharedSecretPath}" ];
        ExecStartPre = "${jwtSetupScript}";
        Environment = [
          "LIVEKIT_URL=wss://${cfg.hostName}/livekit/sfu"
          "LIVEKIT_KEY_FILE=${jwtKeysFile}"
          "LIVEKIT_JWT_BIND=127.0.0.1:${toString cfg.jwtPort}"
          "LIVEKIT_FULL_ACCESS_HOMESERVERS=${lib.concatStringsSep "," cfg.fullAccessHomeservers}"
        ];
        ExecStart = lib.getExe pkgs.lk-jwt-service;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.livekitIceTcpPort ];
    networking.firewall.allowedUDPPortRanges = [
      {
        from = cfg.livekitIceUdpRangeStart;
        to = cfg.livekitIceUdpRangeEnd;
      }
    ];
  };
}
