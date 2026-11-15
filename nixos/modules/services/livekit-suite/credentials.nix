{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.livekitSuite;
in
{
  config = lib.mkIf cfg.development {
    systemd.services.livekit-suite-development-secret = {
      description = "Standalone LiveKit development secret";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "livekit-suite";
        UMask = "0077";
      };
      script = ''
        if [ ! -s /var/lib/livekit-suite/master-secret ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/livekit-suite/master-secret
        fi
      '';
    };
  };
}
