{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.openhands;
  proxyPort = config.ports.openhands-oauth;
  oauth2Proxy = lib.escapeShellArgs [
    "${pkgs.oauth2-proxy}/bin/oauth2-proxy"
    "--provider=keycloak-oidc"
    "--oidc-issuer-url=https://sso.${config.networking.domain}/realms/users"
    "--client-id=${cfg.oidc.clientId}"
    "--http-address=127.0.0.1:${toString proxyPort}"
    "--upstream=http://127.0.0.1:${toString config.ports.openhands}/"
    "--redirect-url=https://${cfg.domain}/oauth2/callback"
    "--authenticated-emails-file=${allowedUsers}"
    "--reverse-proxy=true"
    "--trusted-proxy-ip=127.0.0.1/32"
    "--code-challenge-method=S256"
    "--insecure-oidc-skip-nonce=false"
    "--pass-basic-auth=false"
    "--pass-user-headers=false"
    "--cookie-secure=true"
    "--cookie-samesite=lax"
    "--cookie-name=__Host-openhands_auth"
    "--session-cookie-minimal=true"
    "--exclude-logging-path=/oauth2/callback"
    "--skip-provider-button=true"
    "--proxy-websockets=true"
    "--upstream-timeout=1h"
    "--flush-interval=100ms"
    "--scope=openid email profile"
  ];
  startProxy = pkgs.writeShellScript "openhands-oauth2-proxy-start" ''
    if [ "''${#OAUTH2_PROXY_COOKIE_SECRET}" -gt 32 ]; then
      export OAUTH2_PROXY_COOKIE_SECRET="''${OAUTH2_PROXY_COOKIE_SECRET:0:32}"
    fi
    exec ${oauth2Proxy}
  '';
  allowedUsers = pkgs.writeText "openhands-oidc-users" ''
    i@${config.networking.domain}
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.openhands-oauth2-proxy = {
      description = "Keycloak OIDC ingress for OpenHands";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "sops-install-secrets.service"
        "podman-openhands.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "sops-install-secrets.service" ];
      serviceConfig = {
        DynamicUser = true;
        EnvironmentFile = config.sops.templates."openhands-oauth2-proxy.env".path;
        ExecStart = startProxy;
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        SystemCallFilter = [ "@system-service" ];
        MemoryMax = "128M";
        TasksMax = 64;
      };
    };

    services.traefik.proxies.openhands = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString proxyPort}";
      entryPoints = [ "https" ];
      middlewares = [ "openhands-security" ];
    };

    services.traefik.dynamicConfigOptions.http = lib.mkMerge [
      (lib.mkIf (cfg.aliasDomains != [ ]) {
        routers.openhands-aliases = {
          rule = lib.concatStringsSep " || " (map (domain: "Host(`${domain}`)") cfg.aliasDomains);
          entryPoints = [ "https" ];
          tls = { };
          middlewares = [ "openhands-canonical-domain" ];
          service = "noop@internal";
        };
        middlewares.openhands-canonical-domain.redirectRegex = {
          regex = "^https://[^/]+/(.*)$";
          replacement = "https://${cfg.domain}/$1";
          permanent = false;
        };
      })
      {
        middlewares.openhands-security.headers = {
          contentTypeNosniff = true;
          referrerPolicy = "no-referrer";
          stsSeconds = 31536000;
          customResponseHeaders.Cache-Control = "no-store";
        };
        serversTransports.openhands-stream.forwardingTimeouts = {
          dialTimeout = "10s";
          responseHeaderTimeout = "3600s";
          idleConnTimeout = "3600s";
          readIdleTimeout = "3600s";
          pingTimeout = "15s";
        };
        services.openhands.loadBalancer = {
          serversTransport = "openhands-stream";
          responseForwarding.flushInterval = "1ms";
        };
      }
    ];
  };
}
