{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.livekitSuite;
  s = cfg.settings;
  primary = cfg.topology.primary;
  sdk = pkgs.fetchurl {
    url = "https://registry.npmjs.org/livekit-client/-/livekit-client-2.23.0.tgz";
    hash = "sha512-j9Kg86nJjBjNFUD+ukp2jwMCGa0k+YD5gU//RzAM+ZY3pbG631QCte7fQjwqWMmtBzhDJL9nKYuOLMv/9IbAxg==";
  };
  assets = pkgs.runCommand "livekit-suite-web" { } ''
    mkdir -p "$out"
    cp ${./frontend}/* "$out/"
    tar -xzf ${sdk} --strip-components=2 -C "$out" package/dist/livekit-client.umd.js
  '';
  base = pkgs.writeText "livekit-suite-web.json" (
    builtins.toJSON {
      settings = s.web;
      origin = "https://${cfg._meta.domain}${
        lib.optionalString (cfg._meta.httpsPort != 443) ":${toString cfg._meta.httpsPort}"
      }";
      turnTtl = s.turn.credentialTtl;
      public = {
        serverUrl = if primary == null then "" else primary.url;
        inherit (cfg.topology) nodes iceServers;
        inherit (s)
          media
          transport
          control
          room
          ;
      };
    }
  );
in
{
  options.services.livekitSuite.web.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };
  config = lib.mkMerge [
    { services.livekitSuite._meta.roles.web = cfg.web.enable; }
    (lib.mkIf cfg.web.enable {
      assertions = [
        {
          assertion = cfg._meta.domain != "";
          message = "LiveKit web needs _meta.domain.";
        }
      ];
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "livekit-suite-access" ''
          exec ${pkgs.python3}/bin/python3 ${./runtime.py} access ${lib.escapeShellArg cfg.secretFile}
        '')
      ];
      systemd.services.livekit-suite-web = {
        description = "LiveKit screen sharing frontend and authenticated token API";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.development "livekit-suite-development-secret.service";
        requires = lib.optional cfg.development "livekit-suite-development-secret.service";
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./runtime.py} web ${base} ${assets}";
          LoadCredential = [ "master:${cfg.secretFile}" ];
          DynamicUser = true;
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };
    })
  ];
}
