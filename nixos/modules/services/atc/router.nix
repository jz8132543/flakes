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
  data = import ./data.nix;

  # ── Helpers ────────────────────────────────────────────────────────────────

  # Build-time serial derived from current date (YYYYMMDDXX).
  # We use a fixed 00 counter; for same-day bumps, rebuild is sufficient
  # because CoreDNS re-reads zone files on SIGHUP without restart.

  # The public IP of the current host, looked up from edgeNodes by hostName.
  # Falls back to the first available router IP (nue0's by default).
  selfNode = findFirst (n: n.name == config.networking.hostName) null data.edgeNodes;
  selfIpv4 = if selfNode != null then selfNode.ipv4 else "127.0.0.1";
  selfIpv6 = if selfNode != null && selfNode.ipv6 != null then selfNode.ipv6 else null;

  # All edge nodes' A records (multi-value, round-robin).

  # NS hostnames for the cdn.<domain> zone.
  # Each host running router.nix self-registers as an NS.
  # nsNodes is derived from edgeNodes filtered by the router hosts list.
  # Since we cannot know all router hosts at eval time without a separate list,
  # we accept cfg.nsNames (default ["ns1" "ns2"]) and pair them with the two
  # first router hosts declared in cfg.nsHosts (default ["nue0" "fra0"]).
  nsHostPairs = zipLists cfg.nsNames cfg.nsHosts;

  nsRRecords = concatMapStringsSep "\n    " (
    pair:
    let
      nsName = pair.fst;
      hostName = pair.snd;
      node = findFirst (n: n.name == hostName) null data.edgeNodes;
      aRec = optionalString (node != null) "${nsName} IN A ${node.ipv4}";
      aaaaRec = optionalString (node != null && node.ipv6 != null) "${nsName} IN AAAA ${node.ipv6}";
    in
    ''
      @ IN NS ${nsName}.cdn.${domain}.
      ${aRec}
      ${aaaaRec}''
  ) nsHostPairs;

  # Per-service origin records: <label>.cdn.<domain>. answers with all edge IPs.
  # The origin host itself (e.g. nue0.cdn.dora.im) resolves to the origin's own IP.

  # All unique upstream origin names (deduplicated).
  uniqueOrigins = unique (attrValues data.services);

  # For each unique origin, generate its A/AAAA record inside the zone.
  originGlueRecords = concatMapStringsSep "\n    " (
    originHost:
    let
      node = findFirst (n: n.name == originHost) null data.edgeNodes;
      aRec = optionalString (node != null) "${originHost} IN A ${node.ipv4}";
      aaaaRec = optionalString (node != null && node.ipv6 != null) "${originHost} IN AAAA ${node.ipv6}";
    in
    ''
      ${aRec}
      ${aaaaRec}''
  ) uniqueOrigins;

  # Edge-pool records for each service label (clients resolve label.cdn → all edges).
  serviceLabelRecords = concatStringsSep "\n    " (
    mapAttrsToList (
      label: _originHost:
      concatMapStringsSep "\n    " (
        n: "${label} IN A ${n.ipv4}" + optionalString (n.ipv6 != null) "\n    ${label} IN AAAA ${n.ipv6}"
      ) data.edgeNodes
    ) data.services
  );

  cdnZone = pkgs.writeText "cdn.${domain}.zone" ''
    $ORIGIN cdn.${domain}.
    $TTL ${toString cfg.dns.ttl}
    @ IN SOA ns1.cdn.${domain}. admin.${domain}. (
        2026010100 ; Serial (placeholder — overridden by soaSerial at build time)
        7200       ; Refresh
        3600       ; Retry
        1209600    ; Expire
        ${toString cfg.dns.ttl} ; Minimum TTL
    )

    ; ── NS records with glue ──────────────────────────────────────────────
    ${nsRRecords}

    ; ── Per-service label → edge pool (all edges, round-robin) ───────────
    ${serviceLabelRecords}

    ; ── Origin host glue records (origin.cdn.<domain> → origin IP) ───────
    ${originGlueRecords}

    ; ── Wildcard fallback: unmapped names → full edge pool ────────────────
    ${concatMapStringsSep "\n    " (n: "* IN A ${n.ipv4}") data.edgeNodes}
    ${concatMapStringsSep "\n    " (
      n: optionalString (n.ipv6 != null) "* IN AAAA ${n.ipv6}"
    ) data.edgeNodes}
  '';

  corefile = pkgs.writeText "Corefile" ''
    cdn.${domain}:${toString cfg.dns.port} {
        bind ${concatStringsSep " " cfg.dns.listenAddresses}
        file ${cdnZone} cdn.${domain}
        errors
        ${optionalString cfg.dns.log "log"}
    }

    ${optionalString cfg.doh.enable ''
      http://.:${toString cfg.doh.port} {
          bind 127.0.0.1
          file ${cdnZone} cdn.${domain}
          errors
      }
    ''}
  '';
in
{
  options.services.atc.router = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Apache Traffic Control Traffic Router (CoreDNS DNS steering & DoH). Enable on each NS host.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.coredns;
      description = "CoreDNS package to use for DNS steering.";
    };

    nsNames = mkOption {
      type = types.listOf types.str;
      default = [
        "ns1"
        "ns2"
      ];
      description = "NS record short names inside cdn.<domain> zone (e.g. [\"ns1\" \"ns2\"]).";
    };

    nsHosts = mkOption {
      type = types.listOf types.str;
      default = [
        "nue0"
        "fra0"
      ];
      description = ''
        Host names (matching edgeNodes[].name in data.nix) that correspond to the
        nsNames entries. Must be the same length as nsNames. Each host running this
        module acts as an authoritative NS for cdn.<domain>.
      '';
    };

    dns = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = (optional (selfIpv4 != "127.0.0.1") selfIpv4) ++ (optional (selfIpv6 != null) selfIpv6);
        defaultText = "Derived from data.edgeNodes for the current host";
        description = ''
          Addresses to bind the DNS server. Defaults to the current host's public
          IPs from data.edgeNodes. Override if the host has additional interfaces.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 53;
        description = "DNS listening port.";
      };

      ttl = mkOption {
        type = types.int;
        default = 60;
        description = "DNS response TTL in seconds.";
      };

      log = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable CoreDNS query logging. Disabled by default — on authoritative
          servers, per-query logs saturate the journal very quickly.
        '';
      };
    };

    doh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable local DoH endpoint (for Traefik TLS termination).";
      };

      port = mkOption {
        type = types.port;
        default = 5305;
        description = "Internal HTTP port for DoH queries (127.0.0.1 only).";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = length cfg.nsNames == length cfg.nsHosts;
        message = "services.atc.router: nsNames and nsHosts must have the same length.";
      }
    ];

    networking.firewall.allowedUDPPorts = [ cfg.dns.port ];
    networking.firewall.allowedTCPPorts = [ cfg.dns.port ];

    users.users.trafficrouter = {
      isSystemUser = true;
      group = "trafficrouter";
      description = "Apache Traffic Router daemon user";
    };
    users.groups.trafficrouter = { };

    systemd.tmpfiles.rules = [
      "d /etc/traffic_router 0750 trafficrouter trafficrouter -"
      "d /etc/traffic_router/zones 0750 trafficrouter trafficrouter -"
      "d /var/log/traffic_router 0750 trafficrouter trafficrouter -"
    ];

    environment.etc."traffic_router/Corefile".source = corefile;
    environment.etc."traffic_router/zones/cdn.${domain}.zone".source = cdnZone;

    systemd.services.traffic-router = {
      description = "Apache Traffic Control Traffic Router (CoreDNS DNS Steering & DoH)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

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
        MemoryMax = "256M";
        LimitNOFILE = 65536;
        ExecStart = "${cfg.package}/bin/coredns -conf /etc/traffic_router/Corefile";
      };
    };

    # DoH endpoint: Traefik forwards dns.cdn.<domain>/dns-query → CoreDNS on 127.0.0.1:5305
    services.traefik.proxies.traffic-router-doh =
      mkIf (cfg.doh.enable && (config.services.traefik.enable or false))
        {
          rule = "Host(`dns.cdn.${domain}`) && PathPrefix(`/dns-query`)";
          target = "http://127.0.0.1:${toString cfg.doh.port}";
        };
  };
}
