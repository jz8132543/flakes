{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.livekitSuite;
  s = cfg.settings.turn;
  base = pkgs.writeText "livekit-suite-turn.json" (
    builtins.toJSON {
      inherit (cfg._meta) publicIpv4 publicIpv6 turnDomain;
      inherit (cfg) tls;
      settings = s;
    }
  );
  service = mode: {
    description = "Authenticated Coturn ${mode} relay";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
    ]
    ++ lib.optional cfg.development "livekit-suite-development-secret.service";
    requires = lib.optional cfg.development "livekit-suite-development-secret.service";
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./runtime.py} ${mode} ${base} ${lib.getExe' pkgs.coturn "turnserver"}";
      LoadCredential = [
        "master:${cfg.secretFile}"
      ]
      ++ lib.optionals (!cfg.tls.external) [
        "tls-cert:${cfg.tls.certFile}"
        "tls-key:${cfg.tls.keyFile}"
      ];
      DynamicUser = true;
      RuntimeDirectory = "livekit-suite-${mode}";
      Environment = "SUITE_RUNTIME=/run/livekit-suite-${mode}";
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
in
{
  options.services.livekitSuite.turn.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };
  config = lib.mkMerge [
    { services.livekitSuite._meta.roles.turn = cfg.turn.enable; }
    (lib.mkIf cfg.turn.enable {
      assertions = [
        {
          assertion = cfg._meta.turnDomain != "";
          message = "TURN TLS needs _meta.turnDomain.";
        }
        {
          assertion = cfg.tls.external || (cfg.tls.certFile != "" && cfg.tls.keyFile != "");
          message = "TURN requires runtime TLS cert/key files or a configured external L4 TLS proxy.";
        }
        {
          assertion = s.relayStart <= s.relayEnd;
          message = "Invalid TURN relay range.";
        }
        {
          assertion =
            !cfg.tls.external
            || (
              s.proxyRelayStart <= s.proxyRelayEnd
              && (s.proxyRelayEnd < s.relayStart || s.relayEnd < s.proxyRelayStart)
            );
          message = "TURN proxy relay pool must be ordered and disjoint from the ordinary TURN pool.";
        }
      ];
      networking.firewall = {
        allowedUDPPorts = [ s.port ];
        allowedTCPPorts = [ s.port ] ++ lib.optional (!cfg.tls.external) s.tlsPort;
        allowedUDPPortRanges = [
          {
            from = s.relayStart;
            to = s.relayEnd;
          }
        ]
        ++ lib.optional cfg.tls.external {
          from = s.proxyRelayStart;
          to = s.proxyRelayEnd;
        };
      };
      networking.nftables = lib.mkIf cfg.tls.external {
        enable = true;
        tables.livekit-suite-turn = {
          family = "inet";
          content = ''
            chain proxy_guard {
              type filter hook input priority -10; policy accept;
              iifname != "lo" tcp dport ${toString s.proxyPort} drop
            }
          '';
        };
      };
      systemd.services.livekit-suite-turn = service "turn";
      systemd.services.livekit-suite-turn-proxy = lib.mkIf cfg.tls.external (service "turn-proxy");
    })
  ];
}
