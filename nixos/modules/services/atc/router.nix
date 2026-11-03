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
  controls = filter builtins.isAttrs (data.controlNodes or [ ]);
  origins = controls ++ (filter builtins.isAttrs (data.originNodes or [ ]));
  nsHosts = data.nsHosts or [ data.nsHost ];
  controlNode = findFirst (n: n.name == config.networking.hostName) null controls;
  selfNode = findFirst (n: n.name == config.networking.hostName) controlNode data.edgeNodes;
  selfIpv4 = if selfNode != null then selfNode.ipv4 or null else null;
  selfIpv6 = if selfNode != null then selfNode.ipv6 or null else null;
  addresses = n: {
    ipv4 = n.ipv4 or null;
    ipv6 = n.ipv6 or null;
  };
  python = pkgs.python3.withPackages (ps: [ ps.dnslib ]);

  # Whitelist public routing data; no Ops credentials enter this derivation.
  steeringConfig = pkgs.writeText "atc-steering.json" (
    builtins.toJSON {
      zone = "cdn.${domain}";
      nameservers = map (n: "${n}.${domain}") nsHosts;
      admin = "admin.${domain}";
      ttl = cfg.dns.ttl;
      edges = map (n: (addresses n) // { inherit (n) name weight; }) data.edgeNodes;
      origins = listToAttrs (map (n: nameValuePair n.name (addresses n)) origins);
      inherit (data) services;
      apex_origin = cfg.steering.apexOrigin;
      origin_bypass_services = cfg.steering.originBypassServices;
      dns_port = cfg.steering.port;
      status_port = cfg.steering.statusPort;
      poll_interval = cfg.steering.pollInterval;
      poll_budget = cfg.steering.pollBudget;
      http_timeout = cfg.steering.httpTimeout;
      max_age = cfg.steering.maxAge;
      recovery_successes = cfg.steering.recoverySuccesses;
      slow_start = cfg.steering.slowStartSeconds;
    }
  );
  corefile = pkgs.writeText "Corefile" ''
    cdn.${domain}:${toString cfg.dns.port} {
        bind ${concatStringsSep " " cfg.dns.listenAddresses}
        forward . 127.0.0.1:${toString cfg.steering.port} {
            max_concurrent 256
        }
        errors
        ${optionalString cfg.dns.log "log"}
    }
  '';
in
{
  options.services.atc.router = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run the CoreDNS front door and local authoritative CDN scheduler (not the Apache Java Traffic Router).";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.coredns;
      description = "CoreDNS public DNS front door package.";
    };
    dns = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = (optional (selfIpv4 != null) selfIpv4) ++ (optional (selfIpv6 != null) selfIpv6);
        description = "Public addresses from cdn.controlNodes/edgeNodes to bind.";
      };
      port = mkOption {
        type = types.port;
        default = 53;
        description = "Public UDP and TCP DNS port.";
      };
      ttl = mkOption {
        type = types.ints.between 1 300;
        default = 30;
        description = "DNS TTL. Effective weights expand repeated address records; recursive resolvers may deduplicate them.";
      };
      log = mkOption {
        type = types.bool;
        default = false;
        description = "Enable CoreDNS query logging.";
      };
    };
    steering = {
      port = mkOption {
        type = types.port;
        default = 5354;
        description = "Loopback-only authoritative UDP/TCP DNS port.";
      };
      statusPort = mkOption {
        type = types.port;
        default = 9131;
        description = "Loopback-only HTTP /status and /metrics port.";
      };
      apexOrigin = mkOption {
        type = types.nullOr types.str;
        default = if length controls == 1 then (head controls).name else null;
        description = "Explicit control origin for apex fallback; defaults only when there is exactly one control node. Null means SERVFAIL on empty apex pool.";
      };
      originBypassServices = mkOption {
        type = types.listOf types.str;
        default = data.originOnlyServices or [ ];
        example = [ "chat" ];
        description = "Service labels to route directly to their data.services origin, including while edges are healthy. Defaults to generated cdn.originOnlyServices; supports migration of temporary chat bypasses.";
      };
      pollInterval = mkOption {
        type = types.ints.between 1 60;
        default = 5;
        description = "Seconds between background health snapshots.";
      };
      pollBudget = mkOption {
        type = types.ints.between 1 30;
        default = 3;
        description = "Total wall-clock seconds allowed for one bounded-concurrency snapshot poll.";
      };
      httpTimeout = mkOption {
        type = types.ints.between 1 10;
        default = 1;
        description = "HTTP socket timeout in seconds within the total poll budget.";
      };
      maxAge = mkOption {
        type = types.ints.between 5 120;
        default = 20;
        description = "Maximum age of CrStates lastPoll, edge cdn.sampled_at and in-memory snapshots; missing/malformed/stale data always fail closed.";
      };
      recoverySuccesses = mkOption {
        type = types.ints.between 1 20;
        default = 3;
        description = "Consecutive fresh successful samples required per address family before readmission.";
      };
      slowStartSeconds = mkOption {
        type = types.ints.between 1 600;
        default = 60;
        description = "Seconds to gradually ramp a recovered edge to its bounded performance weight.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          all (n: isInt n.weight && n.weight >= 1) data.edgeNodes
          && foldl' (sum: n: sum + n.weight) 0 data.edgeNodes <= 256;
        message = "services.atc.router: weights must be positive integers totaling at most 256 repeated DNS records.";
      }
      {
        assertion = selfNode != null && cfg.dns.listenAddresses != [ ];
        message = "services.atc.router: current host must have public addresses in cdn.controlNodes/edgeNodes.";
      }
      {
        assertion = nsHosts != [ ] && all (h: any (n: n.name == h) (controls ++ data.edgeNodes)) nsHosts;
        message = "services.atc.router: nameservers must be configured control/edge nodes.";
      }
      {
        assertion = cfg.steering.apexOrigin == null || any (n: n.name == cfg.steering.apexOrigin) controls;
        message = "services.atc.router: apexOrigin must be an explicitly configured control node.";
      }
      {
        assertion = all (
          s: data.services ? ${s} && any (n: n.name == data.services.${s}) origins
        ) cfg.steering.originBypassServices;
        message = "services.atc.router: every bypass service must map to a configured control/origin node.";
      }
      {
        assertion =
          cfg.steering.pollBudget <= cfg.steering.pollInterval
          && cfg.steering.maxAge > cfg.steering.pollInterval + cfg.steering.pollBudget;
        message = "services.atc.router: pollBudget must not exceed pollInterval; maxAge must exceed pollInterval + pollBudget.";
      }
      {
        assertion =
          length (unique [
            cfg.dns.port
            cfg.steering.port
            cfg.steering.statusPort
          ]) == 3;
        message = "services.atc.router: DNS and status ports must be distinct.";
      }
    ];
    networking.firewall.allowedUDPPorts = [ cfg.dns.port ];
    networking.firewall.allowedTCPPorts = [ cfg.dns.port ];
    users.users.trafficrouter = {
      isSystemUser = true;
      group = "trafficrouter";
      description = "Local CDN authoritative DNS scheduler";
    };
    users.groups.trafficrouter = { };
    environment.etc."traffic_router/Corefile".source = corefile;
    environment.etc."traffic_router/steering.json".source = steeringConfig;

    systemd.services.atc-dns-steering = {
      description = "ATC authoritative DNS and background health sampler";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "simple";
        User = "trafficrouter";
        Group = "trafficrouter";
        ExecStart = "${python}/bin/python3 ${./steering.py} /etc/traffic_router/steering.json";
        Restart = "always";
        RestartSec = "2s";
        TimeoutStopSec = "5s";
        MemoryMax = "128M";
        TasksMax = 96;
        LimitNOFILE = 4096;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
      restartTriggers = [
        steeringConfig
        ./steering.py
      ];
    };
    systemd.services.traffic-router = {
      description = "CoreDNS CDN public DNS front door";
      after = [
        "network-online.target"
        "atc-dns-steering.service"
      ];
      wants = [
        "network-online.target"
        "atc-dns-steering.service"
      ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "simple";
        User = "trafficrouter";
        Group = "trafficrouter";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        Restart = "always";
        RestartSec = "2s";
        MemoryMax = "128M";
        LimitNOFILE = 4096;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ExecStart = "${cfg.package}/bin/coredns -conf /etc/traffic_router/Corefile";
      };
      restartTriggers = [ corefile ];
    };
  };
}
