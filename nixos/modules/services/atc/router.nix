{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.router;
  domain = config.networking.domain;
  data = (builtins.fromJSON (builtins.readFile ../../../../lib/data/data.json)).cdn;
  nsHosts =
    data.nsHosts or (
      if data ? nsHost then [ data.nsHost ] else (data.controlNodeNames or [ config.networking.hostName ])
    );

  controlNode = findFirst (
    c: (if builtins.isAttrs c then c.name else c) == config.networking.hostName
  ) null (data.controlNodes or [ ]);
  controlIpv4 =
    if controlNode != null && builtins.isAttrs controlNode then (controlNode.ipv4 or null) else null;
  controlIpv6 =
    if controlNode != null && builtins.isAttrs controlNode then (controlNode.ipv6 or null) else null;

  selfNode = findFirst (n: n.name == config.networking.hostName) null data.edgeNodes;
  selfIpv4 =
    if controlIpv4 != null then
      controlIpv4
    else
      (if selfNode != null then (selfNode.ipv4 or "127.0.0.1") else "127.0.0.1");
  selfIpv6 =
    if controlIpv6 != null then
      controlIpv6
    else
      (if selfNode != null then (selfNode.ipv6 or null) else null);

  defaultGeoIpDatabase = pkgs.fetchurl {
    url = "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb";
    hash = "sha256-/+2ydRyuFv3YhoFKbISAYzyRXsE2wVgspcn8WGH3gao=";
  };

  trafficRouterConfigTemplate = pkgs.writeText "traffic_router.properties" ''
    # DNS Listener (always enabled)
    dns.port=${toString cfg.dns.port}
    dns.address=${concatStringsSep "," cfg.dns.listenAddresses}

    # HTTP Listener (HTTP steering - reduces redirect hops)
    http.port=${toString cfg.http.port}
    http.address=${concatStringsSep "," cfg.http.listenAddresses}

    # Traffic Ops
    traffic_ops.url=${cfg.trafficOpsUrl}
    traffic_ops.username=${cfg.trafficOpsUser}
    traffic_ops.insecure=${if cfg.trafficOpsInsecure then "true" else "false"}

    # Traffic Monitor (Health + Connection Time)
    traffic_monitor.enabled=true
    traffic_monitor.url=${cfg.trafficMonitorUrl}
    traffic_monitor.crconfig.file=/var/lib/traffic_monitor/crconfig.backup
    traffic_monitor.polling.interval=20000
    traffic_monitor.connection.timeout=5000
    traffic_monitor.connection.warning=1000

    # DNS Steering (GeoIP + Health-aware)
    dns.steering.enabled=true
    dns.steering.algorithm=LOAD_BALANCED
    dns.steering.ttl=${toString cfg.dns.ttl}

    # HTTP Steering (302 Redirect to best edge - single hop, no intermediate redirect)
    http.steering.enabled=true
    http.steering.algorithm=LOAD_BALANCED
    http.steering.max.redirects=3

    # GeoIP
    geolocation.database=${cfg.geoip.databaseFile}
    geolocation.enabled=${if cfg.geoip.enable then "true" else "false"}

    # Health Penalty (nodes with high connection time get lower weight)
    traffic_router.health.penalty.enabled=true
    traffic_router.health.penalty.threshold=300
    traffic_router.health.penalty.factor=0.5

    # Dynamic TTL: healthy nodes get higher TTL, degraded nodes get lower TTL
    dns.steering.dynamic.ttl.enabled=true
    dns.steering.dynamic.ttl.min=10
    dns.steering.dynamic.ttl.max=60

    # Logging
    log.location.error=stderr
    log.location.warning=stderr
    log.location.info=stdout
    log.location.debug=null
    log.location.event=stdout
  '';
in
{
  options.services.atc.router = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run Apache Traffic Control Traffic Router for CDN DNS/HTTP steering.";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      defaultText = "null";
      description = "Traffic Router package providing DNS and HTTP steering. Set to pkgs.traffic-router to enable.";
    };

    dns = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = (optional (selfIpv4 != "127.0.0.1") selfIpv4) ++ (optional (selfIpv6 != null) selfIpv6);
        defaultText = "Current host's public addresses from terraform/cdn.tf";
        description = "Addresses on which Traffic Router DNS listens.";
      };

      port = mkOption {
        type = types.port;
        default = 53;
        description = "DNS listening port.";
      };

      ttl = mkOption {
        type = types.int;
        default = 60;
        description = "DNS response TTL in seconds (informational; Traffic Router manages TTL internally).";
      };

      log = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Traffic Router DNS query logging; disabled by default.";
      };
    };

    http = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = [ "0.0.0.0" ];
        defaultText = "0.0.0.0";
        description = "Addresses on which Traffic Router HTTP steering listens. Enable HTTP steering to reduce redirect hops for CDN domains.";
      };

      port = mkOption {
        type = types.port;
        default = 80;
        description = "HTTP steering port. Traffic Router listens here for HTTP requests and returns 302 to the best edge node, avoiding extra redirect through Control Traefik.";
      };
    };

    trafficOpsUrl = mkOption {
      type = types.str;
      default =
        if (config.services.atc.ops.enable or false) then
          "https://127.0.0.1:${toString config.services.atc.ops.port}"
        else
          "https://ops.${config.networking.domain}";
      defaultText = "if ops.enable then local 127.0.0.1:port else https://ops.<networking.domain>";
      description = "Traffic Ops API URL for Traffic Router configuration.";
    };

    trafficOpsUser = mkOption {
      type = types.str;
      default = "t3c-sync";
      description = "Traffic Ops username for Traffic Router.";
    };

    trafficOpsInsecure = mkOption {
      type = types.bool;
      default = config.services.atc.ops.enable or false;
      defaultText = "true if ops.enable else false";
      description = "Skip certificate verification when connecting to Traffic Ops.";
    };

    trafficMonitorUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8087";
      description = "Traffic Monitor URL for health information.";
    };

    geoip = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Load the GeoIP2 database for GeoDNS steering.";
      };

      databaseFile = mkOption {
        type = types.path;
        default = defaultGeoIpDatabase;
        description = "MaxMind GeoLite2 City/GeoIP2 database path.";
      };
    };
  };

  config = mkIf (cfg.enable && (cfg.package != null)) {
    assertions = [
      {
        assertion = controlNode != null || selfNode != null;
        message = "services.atc.router: networking.hostName must be present in controlNodes or cdn_edge_nodes.";
      }
      {
        assertion = all (
          h:
          any (n: (if builtins.isAttrs n then n.name else n) == h) (
            (data.controlNodes or [ ]) ++ (data.edgeNodes or [ ])
          )
        ) nsHosts;
        message = "services.atc.router: all cdn.nsHosts entries must be present in controlNodes or cdn_edge_nodes.";
      }
      {
        assertion = all (n: (n.ipv4 or null) != null) data.edgeNodes;
        message = "services.atc.router: every cdn_edge_nodes entry must resolve to an A record in terraform/hosts.tf.";
      }
    ];

    networking.firewall.allowedUDPPorts = [ cfg.dns.port ];
    networking.firewall.allowedTCPPorts = [ cfg.dns.port ];

    systemd.tmpfiles.rules = [
      "d /etc/traffic_router 0750 trafficrouter trafficrouter -"
      "d /var/lib/traffic_router 0750 trafficrouter trafficrouter -"
      "d /var/lib/traffic_monitor 0750 trafficmonitor trafficmonitor -"
    ];

    environment.etc."traffic_router/traffic_router.properties".source = trafficRouterConfigTemplate;
    # Reuse the same sops secret definition as monitor.nix/ops.nix so that
    # trafficrouter (added to the trafficops group below) can read the password.
    sops.secrets."atc/ops_password" = {
      owner = "trafficops";
      group = "trafficops";
      mode = "0440";
    };

    users.users.trafficrouter = {
      isSystemUser = true;
      group = "trafficrouter";
      description = "Apache Traffic Router daemon user";
      extraGroups = [ "trafficops" ];
    };
    users.groups.trafficrouter = { };

    systemd.services.traffic-router = {
      description = "Apache Traffic Control Traffic Router (DNS & HTTP steering)";
      after = [
        "network-online.target"
        "traffic-monitor.service"
      ];
      wants = [
        "network-online.target"
        "traffic-monitor.service"
      ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        PASSWORD=""
        if [ -s "${config.sops.secrets."atc/ops_password".path}" ]; then
          PASSWORD="$(cat "${config.sops.secrets."atc/ops_password".path}" | tr -d '\r\n')"
        fi
        if [ -z "$PASSWORD" ]; then
          echo "Traffic Router Traffic Ops password is missing or empty" >&2
          exit 1
        fi

        mkdir -p /var/lib/traffic_router
        cp -f ${trafficRouterConfigTemplate} /etc/traffic_router/traffic_router.properties
        sed -i "s|traffic_ops.password=.*|traffic_ops.password=$PASSWORD|" /etc/traffic_router/traffic_router.properties
        chown trafficrouter:trafficrouter /etc/traffic_router/traffic_router.properties
        chmod 0600 /etc/traffic_router/traffic_router.properties
      '';
      serviceConfig = {
        Type = "simple";
        User = "trafficrouter";
        Group = "trafficrouter";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        Restart = "on-failure";
        RestartSec = "5s";
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
        MemoryMax = "512M";
        LimitNOFILE = 65536;
        ExecStart = "${cfg.package}/bin/traffic_router -conf /etc/traffic_router/traffic_router.properties";
      };
      restartTriggers = [ trafficRouterConfigTemplate ];
    };

    services.traefik.proxies.traffic-router =
      mkIf (config.services.traefik.enable or false && cfg.http.listenAddresses != [ ])
        {
          rule = "Host(`cdn.${domain}`)";
          target = "http://127.0.0.1:${toString cfg.http.port}";
          entryPoints = [
            "http"
            "https"
          ];
          priority = 50;
        };
  };
}
