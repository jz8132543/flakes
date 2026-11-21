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
  sops.secrets."livekit/master_secret" = {
    sopsFile = config.sops-file.get "common.yaml";
    restartUnits = map (name: "${name}.service") active;
  };
  services.livekitSuite = {
    secretFile = config.sops.secrets."livekit/master_secret".path;
    tls.external = true;
    interfaces = lib.mkDefault [ "eth0" ];
  };
  services.traefik = {
    staticConfigOptions.entryPoints.livekit-suite-turn-tls =
      lib.mkIf (cfg._meta.turnTlsPort != cfg.settings.turn.advertisedTlsPort)
        {
          address = ":${toString cfg._meta.turnTlsPort}";
        };
    proxies = {
      livekit-suite-signal = lib.mkIf cfg.sfu.enable {
        rule = "Host(`${cfg._meta.domain}`) && (PathPrefix(`${cfg._meta.signalingPath}/rtc`) || PathPrefix(`${cfg._meta.signalingPath}/twirp`))";
        target = "http://127.0.0.1:${toString s.server.signalingPort}";
        middlewares = lib.optional (cfg._meta.signalingPath != "") "livekit-suite-strip-signaling-prefix";
        priority = 100;
      };
      livekit-suite-web = lib.mkIf cfg.web.enable {
        rule = "Host(`${cfg._meta.domain}`)";
        target = "http://127.0.0.1:${toString s.web.port}";
        priority = 10;
      };
    };
    tcpProxies.livekit-suite-turn = lib.mkIf cfg.turn.enable {
      rule = "HostSNI(`${
        if cfg._meta.turnTlsPort != cfg.settings.turn.advertisedTlsPort then
          cfg._meta.domain
        else
          cfg._meta.turnDomain
      }`)";
      target = "127.0.0.1:${toString s.turn.proxyPort}";
      entryPoints =
        if cfg._meta.turnTlsPort != cfg.settings.turn.advertisedTlsPort then
          [ "livekit-suite-turn-tls" ]
        else
          [
            "https"
            "https-alt"
          ];
      tls = true;
      tlsOptions = "livekit-suite-turn";
    };
    dynamicConfigOptions = lib.mkMerge [
      (lib.mkIf cfg.turn.enable {
        tcp.services.livekit-suite-turn.loadBalancer.proxyProtocol.version = 2;
        tls.options.livekit-suite-turn.alpnProtocols = [ ];
      })
      (lib.mkIf (cfg._meta.signalingPath != "") {
        http.middlewares.livekit-suite-strip-signaling-prefix.stripPrefix.prefixes = [
          cfg._meta.signalingPath
        ];
      })
    ];
  };
  networking.firewall.allowedTCPPorts = lib.mkIf (
    cfg.turn.enable && cfg._meta.turnTlsPort != cfg.settings.turn.advertisedTlsPort
  ) [ cfg._meta.turnTlsPort ];
  systemd.services = lib.genAttrs active (_: {
    after = [
      "sops-install-secrets.service"
      "tailscaled.service"
    ];
    requires = [ "sops-install-secrets.service" ];
  });
}
