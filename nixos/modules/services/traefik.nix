{
  lib,
  config,
  pkgs,
  ...
}:
{
  sops.secrets = {
    "traefik/KID" = { };
    "traefik/HMAC" = { };
    "traefik/hmacEncoded" = { };
    "traefik/cloudflare_token" = { };
    "traefik/TRAEFIK_AUTH" = { };
  };

  sops.templates."traefik-env" = {
    content = ''
      TRAEFIK_AUTH=${config.sops.placeholder."traefik/TRAEFIK_AUTH"}
      CF_DNS_API_TOKEN=${config.sops.placeholder."traefik/cloudflare_token"}
      LEGO_EAB_KID=${config.sops.placeholder."traefik/KID"}
      LEGO_EAB_HMAC_KEY=${config.sops.placeholder."traefik/hmacEncoded"}
    '';
    owner = "traefik";
  };

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      log = {
        level = "DEBUG";
      };
      entryPoints = {
        http = {
          address = ":${toString config.ports.http}";
          http.redirections.entryPoint = {
            to = "https";
            scheme = "https";
            permanent = true;
          };
          transport.respondingTimeouts = {
            readTimeout = 60;
            writeTimeout = 60;
            idleTimeout = 180;
          };
        };
        https = {
          address = ":${toString config.ports.https}";
          http.tls = if config.environment.isNAT then { } else { certResolver = "zerossl"; };
          http3 = { };
          transport.respondingTimeouts = {
            readTimeout = 60;
            writeTimeout = 60;
            idleTimeout = 180;
          };
        };
      };
      certificatesResolvers.zerossl.acme = {
        email = "mail@dora.im";
        storage = "/var/lib/traefik/acme_zerossl.json";
        eab = {
          kid = "{{ env `LEGO_EAB_KID` }}";
          hmacEncoded = "{{ env `LEGO_EAB_HMAC_KEY` }}";
        };
        dnsChallenge = {
          provider = "cloudflare";
          disablePropagationCheck = true;
        };
      };
      api = {
        dashboard = true;
        insecure = false;
      };
      serversTransport = {
        insecureSkipVerify = true;
      };
    };
    dynamic = {
      dir = "/var/lib/traefik/dynamic";
    };
    dynamicConfigOptions = {
      tls.certificates =
        if config.environment.isNAT then
          [
            {
              certFile = "${config.security.acme.certs."main".directory}/fullchain.pem";
              keyFile = "${config.security.acme.certs."main".directory}/key.pem";
            }
          ]
        else
          [ ];
      tls.options.default = {
        minVersion = "VersionTLS13";
        sniStrict = true;
      };
      http = {
        middlewares.limit.buffering = {
          maxRequestBodyBytes = 4 * 1024 * 1024;
          maxResponseBodyBytes = 4 * 1024 * 1024;
        };
        routers = {
          ping = {
            rule = "Host(`${config.networking.fqdn}`) && Path(`/ping`)";
            service = "ping@internal";
          };
          traefik = {
            rule = "Host(`${config.networking.fqdn}`) && Path(`/traefik`)";
            service = "prometheus@internal";
          };
          api = {
            rule = "Host(`${config.networking.fqdn}`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))";
            service = "api@internal";
            middlewares = [ "auth" ];
          };
        };
        middlewares = {
          dashboard-redirect.redirectRegex = {
            regex = "^https?://([^/]+)/?$";
            replacement = "https://$1/dashboard/";
            permanent = true;
          };
          auth.basicauth = {
            users = [ "{{ env `TRAEFIK_AUTH` }}" ];
            removeHeader = true;
          };
          strip-prefix = {
            stripPrefixRegex.regex = "/[^/]+/";
          };
        };
      };
    };
  };

  systemd.services.traefik-certs-dumper = {
    description = "Dump traefik certs to files";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "traefik-certs-dumper" ''
        set -euo pipefail
        mkdir -p /var/lib/traefik/certs
      ''}";
    };
  };

  systemd.services.traefik.serviceConfig.EnvironmentFile = lib.mkIf (!config.environment.isNAT) [
    config.sops.templates."traefik-env".path
  ];

  environment.global-persistence.directories = [ "/var/lib/traefik" ];

  systemd.tmpfiles.rules = [
    "d /var/lib/traefik 0755 traefik traefik -"
    "d /var/lib/traefik/dynamic 0755 traefik traefik -"
  ];
}
