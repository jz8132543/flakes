{
  config,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.acme ];
  config.users.users.traefik.extraGroups = [ "acme" ];
  config.networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  config.networking.firewall.allowedUDPPorts = [ 443 ];
  config.services.traefik = {
    enable = true;
    staticConfigOptions = {
      entryPoints = {
        http = {
          address = ":80";
          forwardedHeaders.insecure = true;
          proxyProtocol.insecure = true;
          http.redirections.entryPoint = {
            to = "https";
            scheme = "https";
            permanent = false;
          };
          # asDefault = true;
        };
        https = {
          address = ":443";
          forwardedHeaders.insecure = true;
          proxyProtocol.insecure = true;
          transport = {
            # lifeCycle = {
            #   requestAcceptGraceTimeout = 0;
            #   graceTimeOut = 5;
            # };
            respondingTimeouts = {
              readTimeout = 180;
              writeTimeout = 180;
              idleTimeout = 180;
            };
          };
          http.tls = if config.environment.isNAT then true else { certresolver = "zerossl"; };
          http3 = { };
          # asDefault = true;
        };
      };
      certificatesResolvers.zerossl.acme = {
        # caServer = "https://acme.zerossl.com/v2/DV90";
        email = "blackhole@dora.im";
        storage = "/var/lib/traefik/acme.json";
        keyType = "EC256";
        dnsChallenge = {
          provider = "cloudflare";
        };
      };
      ping = {
        manualRouting = true;
      };
      metrics = {
        prometheus = {
          addRoutersLabels = true;
          manualRouting = true;
        };
      };
      api = {
        dashboard = true;
        disableDashboardAd = true;
        insecure = true;
      };
      serversTransport = {
        insecureSkipVerify = true;
      };
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
            # entryPoints = ["https"];
            service = "ping@internal";
          };
          traefik = {
            rule = "Host(`${config.networking.fqdn}`) && Path(`/traefik`)";
            # entryPoints = ["https"];
            service = "prometheus@internal";
          };
          api = {
            rule = "Host(`${config.networking.fqdn}`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))";
            # entrypoints = ["https"];
            service = "api@internal";
            middlewares = "auth";
          };
        };
        middlewares = {
          # https://tool.oschina.net/htpasswd
          auth.basicauth = {
            users = "{{ env `TRAEFIK_AUTH` }}";
            removeheader = true;
          };
          strip-prefix = {
            stripprefixregex.regex = "/[^/]+/";
          };
        };
      };
      # defaultConfig = {
      #   enable = false;
      #   value = {
      #     http.middlewares = {
      #       strip-prefix = {
      #         stripprefixregex.regex = "/[^/]+/";
      #       };
      #     };
      #   };
      # };
    };
  };
  config.systemd.services.traefik.serviceConfig.EnvironmentFile = [
    config.sops.templates."traefik-env".path
  ];
  config.sops.secrets = {
    "traefik/cloudflare_token" = { };
    "traefik/KID" = { };
    "traefik/hmacEncoded" = { };
    "traefik/TRAEFIK_AUTH" = { };
  };
  config.sops.templates.traefik-env.content = ''
    CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."traefik/cloudflare_token"}
    TRAEFIK_AUTH=${config.sops.placeholder."traefik/TRAEFIK_AUTH"}
    KID=${config.sops.placeholder."traefik/KID"}
    HMAC='${config.sops.placeholder."traefik/hmacEncoded"}'
  '';
}
