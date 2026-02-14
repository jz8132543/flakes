{
  config,
  pkgs,
  nixosModules,
  lib,
  ...
}:
with lib;
{
  imports = [ nixosModules.services.acme ];

  options.services.traefik = {
    proxies = mkOption {
      default = { };
      description = "Simple reverse proxy configuration defining both router and service.";
      type = types.attrsOf (
        types.submodule (
          { ... }:
          {
            options = {
              rule = mkOption {
                type = types.str;
                description = "Traefik router rule.";
              };
              target = mkOption {
                type = types.str;
                description = "Target URL for the service.";
              };
              middlewares = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "List of middlewares for the router.";
              };
            };
          }
        )
      );
    };
  };

  config = {
    users.users.traefik.extraGroups = [ "acme" ];
    networking.firewall.allowedTCPPorts = [
      80
      443
      8443
    ];
    services.nginx = {
      enable = true;
      defaultHTTPListenPort = config.ports.nginx;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      # recommendedTlsSettings = true;
      # resolver.addresses = config.networking.nameservers;
      # sslDhparam = config.security.dhparams.params.nginx.path;
      clientMaxBodySize = "1000m";
      eventsConfig = ''
        worker_connections 4096;
        multi_accept on;
      '';
      appendConfig = ''
        worker_processes auto;
        worker_rlimit_nofile 65535;
      '';
      commonHttpConfig = ''
        # Add HSTS header with preloading to HTTPS requests.
        # Adding this header to HTTP requests is discouraged
        server_names_hash_bucket_size 128;
        proxy_headers_hash_max_size 1024;
        proxy_headers_hash_bucket_size 256;
        # client_max_body_size 0;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        # Trust Traefik and common private networks
        set_real_ip_from  127.0.0.1;
        set_real_ip_from  10.0.0.0/8;
        set_real_ip_from  172.16.0.0/12;
        set_real_ip_from  192.168.0.0/16;
        real_ip_header    X-Forwarded-For;
        real_ip_recursive on;
      '';
    };
    services.traefik = {
      enable = true;
      dynamic.dir = "/var/lib/traefik/dynamic";
      staticConfigOptions = {
        log = {
          level = "DEBUG";
          filePath = "/var/lib/traefik/traefik.log";
        };
        accessLog = {
          filePath = "/var/lib/traefik/access.log";
        };
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
            # asDefault = true;
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
          };
          https-alt = {
            address = ":8443";
            # asDefault = true;
            forwardedHeaders.insecure = true;
            proxyProtocol.insecure = true;
            transport = {
              respondingTimeouts = {
                readTimeout = 180;
                writeTimeout = 180;
                idleTimeout = 180;
              };
            };
            http.tls = if config.environment.isNAT then true else { certresolver = "zerossl"; };
            http3 = { };
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
          entryPoint = "https";
          manualRouting = true;
        };
        metrics = {
          prometheus = {
            addRoutersLabels = true;
            entryPoint = "https";
            manualRouting = true;
          };
        };
        api = {
          dashboard = true;
          disableDashboardAd = true;
          insecure = false;
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
          # minVersion = "VersionTLS13";
          # sniStrict = true;
        };
        http = {
          middlewares.limit.buffering = {
            maxRequestBodyBytes = 4 * 1024 * 1024;
            maxResponseBodyBytes = 4 * 1024 * 1024;
          };
          routers = mkMerge [
            (mapAttrs (name: value: {
              inherit (value) rule middlewares;
              service = name;
            }) config.services.traefik.proxies)
            {
              ping = {
                rule = "Host(`${config.networking.fqdn}`) && Path(`/ping`)";
                service = "ping@internal";
                entryPoints = [
                  "http"
                  "https"
                  "https-alt"
                ];
              };
              traefik-internal-metrics = {
                rule = "Host(`${config.networking.fqdn}`) && Path(`/metrics`)";
                service = "prometheus@internal";
                entryPoints = [ "https" ]; # Internal services still benefit from explicit binding
              };
              traefik-dashboard = {
                rule = "Host(`${config.networking.fqdn}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))";
                service = "api@internal";
                entryPoints = [
                  "http"
                  "https"
                  "https-alt"
                ];
                middlewares = [ "auth" ];
                tls = { }; # Enable TLS to ensure it matches the HTTPS entrypoint correctly
              };
            }
          ];
          services = mapAttrs (_name: value: {
            loadBalancer.servers = [ { url = value.target; } ];
          }) config.services.traefik.proxies;
          middlewares = {
            auth.basicauth = {
              usersFile = config.sops.secrets."traefik/TRAEFIK_AUTH".path;
              removeHeader = true;
            };
            strip-prefix = {
              stripPrefixRegex.regex = [ "/[^/]+/" ];
            };
          };
        };
      };
    };

    systemd.services.traefik-certs-dumper = {
      after = [ "traefik.service" ];
      path = with pkgs; [ openssl ];
      wantedBy = [ "multi-user.target" ];

      description = "Dump certificates generated by traefik to a destination folder";
      serviceConfig =
        let
          user = config.systemd.services.traefik.serviceConfig.User;
          group = config.systemd.services.traefik.serviceConfig.Group;
          certsPath = "/var/lib/traefik/acme.json";
          destination = "/var/lib/traefik-certs";
        in
        {
          User = user;
          Group = group;
          ExecStart = "${pkgs.traefik-certs-dumper}/bin/traefik-certs-dumper file --watch --domain-subdir=true --version v2 --source ${certsPath} --dest ${destination} --post-hook 'chmod -R +r ${destination}'";
          ExecStartPre = [
            "+${pkgs.coreutils}/bin/chown -R ${group}:${user} ${destination}"
            "+${pkgs.coreutils}/bin/chmod -R 0755 ${destination}"
          ];
          PermissionsStartOnly = true;
          LimitNOFILE = "1048576";
          PrivateTmp = "true";
          PrivateDevices = "true";
          ProtectHome = "true";
          ProtectSystem = "strict";
          StateDirectory = "traefik-certs";
        };
    };

    systemd.tmpfiles.rules = [
      "d '/var/lib/traefik' 0770 traefik traefik - -"
      "d '/var/lib/traefik-certs' 0770 traefik traefik - -"
      "f '/var/lib/traefik/acme.json' 0600 traefik traefik - -"
    ];

    systemd.services.traefik.serviceConfig.EnvironmentFile = [
      config.sops.templates."traefik-env".path
    ];
    sops.secrets = {
      "traefik/cloudflare_token" = {
        owner = "traefik";
      };
      "traefik/KID" = {
        owner = "traefik";
      };
      "traefik/hmacEncoded" = {
        owner = "traefik";
      };
      "traefik/TRAEFIK_AUTH" = {
        owner = "traefik";
      };
    };
    systemd.services.traefik.serviceConfig = {
      WatchdogSec = lib.mkForce "30s";
      StartLimitIntervalSec = lib.mkForce "0"; # Disable start limit for better recovery
    };
    sops.templates.traefik-env.content = ''
      CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."traefik/cloudflare_token"}
      TRAEFIK_AUTH=${config.sops.placeholder."traefik/TRAEFIK_AUTH"}
      KID=${config.sops.placeholder."traefik/KID"}
      HMAC='${config.sops.placeholder."traefik/hmacEncoded"}'
    '';
  };
}
