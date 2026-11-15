{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.livekitSuite;
  base = pkgs.writeText "livekit-suite-redis.json" (
    builtins.toJSON {
      bind = cfg._meta.privateAddress;
      inherit (cfg.settings.redis) port maxMemory;
    }
  );
in
{
  options.services.livekitSuite.redis.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };
  config = lib.mkMerge [
    { services.livekitSuite._meta.roles.redis = cfg.redis.enable; }
    (lib.mkIf cfg.redis.enable {
      systemd.services.livekit-suite-redis = {
        description = "Private LiveKit Redis coordination primary";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.development "livekit-suite-development-secret.service";
        requires = lib.optional cfg.development "livekit-suite-development-secret.service";
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./runtime.py} redis ${base} ${lib.getExe' pkgs.redis "redis-server"}";
          LoadCredential = [ "master:${cfg.secretFile}" ];
          DynamicUser = true;
          RuntimeDirectory = "livekit-suite-redis";
          Environment = "SUITE_RUNTIME=/run/livekit-suite-redis";
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };
      # Deliberately no global firewall opening: allow this port only on the private VPN interface.
    })
  ];
}
