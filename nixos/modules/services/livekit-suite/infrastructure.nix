# Adapter for this repository's SOPS, Traefik and Tailscale conventions.
# Generic suite modules do not depend on those infrastructure-specific options.
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.livekitSuite;
  s = cfg.settings;
  active =
    lib.optional cfg.sfu.enable "livekit-suite-sfu"
    ++ lib.optional cfg.turn.enable "livekit-suite-turn"
    ++ lib.optional (cfg.turn.enable && cfg.tls.external) "livekit-suite-turn-proxy"
    ++ lib.optional cfg.redis.enable "livekit-suite-redis"
    ++ lib.optional cfg.web.enable "livekit-suite-web";
in
{
  sops.secrets.livekit_suite_master_secret = {
    terraformOutput.enable = true;
    restartUnits = map (name: "${name}.service") active;
  };
  services.livekitSuite = {
    secretFile = config.sops.secrets.livekit_suite_master_secret.path;
    tls.external = true;
    interfaces = lib.mkDefault [ "eth0" ];
  };
  services.traefik = {
    proxies = {
      livekit-suite-signal = lib.mkIf cfg.sfu.enable {
        rule = "Host(`${cfg._meta.domain}`) && (PathPrefix(`/rtc`) || PathPrefix(`/twirp`))";
        target = "http://127.0.0.1:${toString s.server.signalingPort}";
        priority = 100;
      };
      livekit-suite-web = lib.mkIf cfg.web.enable {
        rule = "Host(`${cfg._meta.domain}`)";
        target = "http://127.0.0.1:${toString s.web.port}";
        priority = 10;
      };
    };
    tcpProxies.livekit-suite-turn = lib.mkIf cfg.turn.enable {
      rule = "HostSNI(`${cfg._meta.turnDomain}`)";
      target = "127.0.0.1:${toString s.turn.proxyPort}";
      entryPoints = [
        "https"
        "https-alt"
      ];
      tls = true;
      tlsOptions = "livekit-suite-turn";
    };
    dynamicConfigOptions = lib.mkIf cfg.turn.enable {
      tcp.services.livekit-suite-turn.loadBalancer.proxyProtocol.version = 2;
      tls.options.livekit-suite-turn.alpnProtocols = [ ];
    };
  };
  systemd.services = lib.genAttrs active (_: {
    after = [
      "sops-install-secrets.service"
      "tailscaled.service"
    ];
    requires = [ "sops-install-secrets.service" ];
  });
}
