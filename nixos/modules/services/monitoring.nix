{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.cluster-monitoring.server;

  # Extract domain names from Traefik proxies rules: Host(`...`)
  extractHostFromRule =
    rule:
    let
      m = builtins.match ".*Host\\(`([^`]+)`\\).*" rule;
    in
    if m != null then builtins.head m else null;

  traefikProxyHosts = lib.unique (
    lib.filter (h: h != null) (
      lib.mapAttrsToList (_name: proxy: extractHostFromRule proxy.rule) config.services.traefik.proxies
    )
  );

  # Hosts to ignore in assertion (internal/localhost/regex rules)
  isInternalOrRegex =
    h:
    lib.hasInfix "localhost" h
    || lib.hasInfix "{" h
    || lib.hasInfix "*" h
    || lib.hasInfix "tailscale" h;

  # Node-specific subdomains like *.nue0.dora.im are private backend routes
  isNodeSpecific =
    h:
    lib.hasSuffix ".${config.networking.hostName}.${config.networking.domain}" h
    || lib.hasInfix ".${config.networking.hostName}." h;

  isPrimaryDomainPublic =
    h: lib.hasSuffix ".${config.networking.domain}" h || h == config.networking.domain;

  traefikPublicHosts = lib.filter (
    h: !isInternalOrRegex h && !isNodeSpecific h && isPrimaryDomainPublic h
  ) traefikProxyHosts;

  # Build list of blackbox targets
  hostEndpoints = map (name: "https://${name}.${config.networking.domain}") (self.hostNames or [ ]);
  allBlackboxTargets = lib.unique (hostEndpoints ++ cfg.publicEndpoints);

  # Target hostnames without scheme for comparison
  monitoredHostnames = map (
    target:
    let
      noProto = lib.removePrefix "https://" (lib.removePrefix "http://" target);
      parts = lib.splitString "/" noProto;
    in
    builtins.head parts
  ) allBlackboxTargets;

  unmonitoredHosts = lib.filter (
    host: !(builtins.elem host monitoredHostnames) && !(builtins.elem host cfg.exemptedEndpoints)
  ) traefikPublicHosts;
in
{
  options.services.cluster-monitoring.server = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable centralized monitoring server (VictoriaMetrics, vmalert, Alertmanager, Blackbox).";
    };

    publicEndpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "https://ts.${config.networking.domain}"
        "https://alist.${config.networking.domain}"
        "https://m.${config.networking.domain}"
        "https://zone.${config.networking.domain}"
        "https://search.${config.networking.domain}"
        "https://vault.${config.networking.domain}"
        "https://ntfy.${config.networking.domain}"
        "https://dash.${config.networking.domain}"
        "https://metrics.${config.networking.domain}"
        "https://${config.networking.domain}"
        "https://link.${config.networking.domain}"
        "https://memos.${config.networking.domain}"
        "https://pb.${config.networking.domain}"
        "https://reader.${config.networking.domain}"
        "https://api.${config.networking.domain}"
        "https://sub.${config.networking.domain}"
        "https://chat.${config.networking.domain}"
      ];
      description = "List of public HTTP(S) endpoints to monitor via blackbox_exporter.";
    };

    exemptedEndpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Subdomains that may be redirect-only, auth-heavy, or tested elsewhere
        "call.${config.networking.domain}"
        "admin.m.${config.networking.domain}"
        "mta-sts.${config.networking.domain}"
        "sso.${config.networking.domain}"
        "dns.${config.networking.domain}"
        "atuin.${config.networking.domain}"
        "code.${config.networking.domain}"
        "cookie.${config.networking.domain}"
        "cpa.${config.networking.domain}"
        "s.${config.networking.domain}"
        "cache.${config.networking.domain}"
        "ha.${config.networking.domain}"
        "hydra.${config.networking.domain}"
        "cloud.${config.networking.domain}"
        "couchdb.${config.networking.domain}"
        "office.${config.networking.domain}"
        "cdn.${config.networking.domain}"
        "zotero.${config.networking.domain}"
      ];
      description = "List of public endpoints exempted from compile-time blackbox assertion.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Assertion: ensure new public services are covered by blackbox ──
    assertions = [
      {
        assertion = unmonitoredHosts == [ ];
        message = ''
          The following Traefik public service endpoints are not included in blackbox monitoring:
            ${lib.concatStringsSep ", " unmonitoredHosts}
          Please add them to services.cluster-monitoring.server.publicEndpoints or exemptedEndpoints.
        '';
      }
    ];

    # ── 1. VictoriaMetrics (vmsingle) ──
    services.victoriametrics = {
      enable = true;
      listenAddress = "127.0.0.1:${toString config.ports.victoriametrics}";
      retentionPeriod = "90d";

      prometheusConfig = {
        scrape_configs = [
          {
            job_name = "blackbox";
            metrics_path = "/probe";
            params = {
              module = [ "http_2xx" ];
            };
            scrape_interval = "60s";
            static_configs = [
              {
                targets = allBlackboxTargets;
              }
            ];
            relabel_configs = [
              {
                source_labels = [ "__address__" ];
                target_label = "__param_target";
              }
              {
                source_labels = [ "__param_target" ];
                target_label = "instance";
              }
              {
                target_label = "__address__";
                replacement = "127.0.0.1:${toString config.ports.blackbox-exporter}";
              }
            ];
          }
        ];
      };
    };

    # Traefik proxy for VictoriaMetrics protected by auth middleware
    services.traefik.proxies.victoriametrics = {
      rule = "Host(`metrics.${config.networking.domain}`)";
      target = "http://127.0.0.1:${toString config.ports.victoriametrics}";
      middlewares = [ "auth" ];
    };

    # ── 2. Blackbox Exporter ──
    services.prometheus.exporters.blackbox = {
      enable = true;
      port = config.ports.blackbox-exporter;
      listenAddress = "127.0.0.1";
      configFile = pkgs.writeText "blackbox.yml" (
        builtins.toJSON {
          modules = {
            http_2xx = {
              prober = "http";
              timeout = "10s";
              http = {
                valid_http_versions = [
                  "HTTP/1.1"
                  "HTTP/2.0"
                ];
                valid_status_codes = [ ]; # defaults to 2xx
                no_follow_redirects = false;
                fail_if_ssl = false;
                fail_if_not_ssl = true;
                tls_config = {
                  insecure_skip_verify = false;
                };
              };
            };
          };
        }
      );
    };

    # ── 3. vmalert ──
    services.vmalert.instances.default = {
      enable = true;
      settings = {
        "datasource.url" = "http://127.0.0.1:${toString config.ports.victoriametrics}";
        "notifier.url" = [
          "http://127.0.0.1:${toString config.ports.alertmanager}"
        ];
        "httpListenAddr" = "127.0.0.1:${toString config.ports.vmalert}";
        "evaluationInterval" = "30s";
      };
      rules = config.services.cluster-monitoring.alertRules;
    };

    # ── 4. Alertmanager ──
    sops.secrets."telegram/grafana_token" = {
      mode = "0400";
    };

    systemd.services.alertmanager.serviceConfig.LoadCredential = [
      "telegram_token:${config.sops.secrets."telegram/grafana_token".path}"
    ];

    services.prometheus.alertmanager = {
      enable = true;
      port = config.ports.alertmanager;
      listenAddress = "127.0.0.1";
      configuration = {
        route = {
          receiver = "telegram";
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
        };
        receivers = [
          {
            name = "telegram";
            telegram_configs = [
              {
                bot_token_file = "/run/credentials/alertmanager.service/telegram_token";
                chat_id = -5282327602;
                parse_mode = "HTML";
                send_resolved = true;
              }
            ];
          }
        ];
        inhibit_rules = [
          {
            source_matchers = [
              "alertname = HostDown"
              "severity = critical"
            ];
            target_matchers = [
              "severity =~ warning|info"
            ];
            equal = [ "instance" ];
          }
        ];
      };
    };
  };
}
