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
  data = (importJSON ../../../../lib/data/data.json).cdn;
  inherit (data) nsHost;

  # Pinned GeoLite2-City snapshot. The database is replaceable through the
  # option below; updating this hash is an intentional rebuild-time update.
  defaultGeoIpDatabase = pkgs.fetchurl {
    url = "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb";
    hash = "sha256-/+2ydRyuFv3YhoFKbISAYzyRXsE2wVgspcn8WGH3gao=";
  };

  selfNode = findFirst (n: n.name == config.networking.hostName) null data.edgeNodes;
  nsNode = findFirst (n: n.name == nsHost) null data.edgeNodes;
  selfIpv4 = if selfNode != null then (selfNode.ipv4 or "127.0.0.1") else "127.0.0.1";
  selfIpv6 = if selfNode != null then (selfNode.ipv6 or null) else null;
  nsIpv4 = if nsNode != null then (nsNode.ipv4 or "127.0.0.1") else "127.0.0.1";
  nsIpv6 = if nsNode != null then (nsNode.ipv6 or null) else null;

  # CoreDNS's geoip/view plugins use continent codes. AP and HK share AS;
  # region remains in cdn.tf for future finer-grained policies.
  geoRegion =
    region:
    if
      elem region [
        "AP"
        "HK"
      ]
    then
      "AS"
    else if region == "EU" then
      "EU"
    else
      "NA";
  geoRegions = unique (map (n: geoRegion n.region) data.edgeNodes);
  nodesForRegion = region: filter (n: geoRegion n.region == region) data.edgeNodes;

  # Higher weight means more DNS answers from that node. The file plugin has
  # no weighted-record primitive, so represent weight with repeated RRs.
  weightedNodes =
    nodes:
    concatMap (n: genList (_: n) (n.weight or 1)) (
      filter (n: (n.ipv4 or null) != null && (n.weight or 1) > 0) nodes
    );
  addressRecords =
    name: nodes:
    concatMapStringsSep "\n    " (
      n:
      "${name} IN A ${n.ipv4}"
      + optionalString ((n.ipv6 or null) != null) "\n    ${name} IN AAAA ${n.ipv6}"
    ) (weightedNodes nodes);

  serviceLabels = unique ((attrNames data.services) ++ (attrValues data.services));

  soaSerial =
    let
      serialFile = pkgs.runCommand "atc-cdn-soa-serial" { } ''
        date -u +%Y%m%d%H > "$out"
      '';
    in
    removeSuffix "\n" (builtins.readFile serialFile);

  zoneFor =
    suffix: nodes:
    pkgs.writeText "cdn-${suffix}.${domain}.zone" ''
      $ORIGIN cdn.${domain}.
      $TTL ${toString cfg.dns.ttl}
      @ IN SOA ${nsHost}.${domain}. admin.${domain}. (
          ${soaSerial} ; UTC YYYYMMDDHH
          7200
          3600
          1209600
          ${toString cfg.dns.ttl}
      )

      @ IN NS ${nsHost}.${domain}.
      ; DoH is served at the zone apex by the NS host.
      @ IN A ${nsIpv4}
      ${optionalString (nsIpv6 != null) "@ IN AAAA ${nsIpv6}"}

      ; Service labels and origin labels are edge-pool aliases.
      ${concatMapStringsSep "\n    " (label: addressRecords label nodes) serviceLabels}

      ; Unmapped names fall back to this view's edge pool.
      ${addressRecords "*" nodes}
    '';

  defaultZone = zoneFor "default" data.edgeNodes;

  geoipBlock = optionalString cfg.geoip.enable ''
    geoip ${cfg.geoip.databaseFile} {
        edns-subnet
    }
    metadata
  '';

  regexDomain = replaceStrings [ "." ] [ "\\." ] domain;
  regionExpr = region: "metadata('geoip/continent/code') == '${region}'";

  templateRecords =
    type: nodes:
    let
      records = weightedNodes nodes;
      addressRecordsForType =
        if type == "A" then
          filter (n: (n.ipv4 or null) != null) records
        else
          filter (n: (n.ipv6 or null) != null) records;
      answer = type: address: ''answer "{{ .Name }} ${toString cfg.dns.ttl} IN ${type} ${address}"'';
    in
    concatStringsSep "\n        " (
      map (n: answer type (if type == "A" then n.ipv4 else n.ipv6)) addressRecordsForType
    );

  templateFor =
    match: nodes: optionalExpr:
    let
      exprLine = optionalString (optionalExpr != null) "expr ${optionalExpr}";
      templateForType =
        type:
        let
          hasAddress = any (n: (if type == "A" then (n.ipv4 or null) else (n.ipv6 or null)) != null) nodes;
        in
        optionalString hasAddress ''
          template IN ${type} cdn.${domain} {
              match "${match}"
              ${exprLine}
              ${templateRecords type nodes}
          }
        '';
    in
    templateForType "A" + templateForType "AAAA";

  regionalTemplates = concatMapStringsSep "\n" (
    region:
    let
      nodes = nodesForRegion region;
    in
    (concatMapStringsSep "\n" (
      label: templateFor "^${label}\\.cdn\\.${regexDomain}\\.$" nodes (regionExpr region)
    ) serviceLabels)
    + templateFor "^.*\\.cdn\\.${regexDomain}\\.$" nodes (regionExpr region)
  ) geoRegions;

  defaultTemplates = concatStringsSep "\n" (
    (map (label: templateFor "^${label}\\.cdn\\.${regexDomain}\\.$" data.edgeNodes null) serviceLabels)
    ++ [ (templateFor "^.*\\.cdn\\.${regexDomain}\\.$" data.edgeNodes null) ]
  );

  corefile = pkgs.writeText "Corefile" ''
    cdn.${domain}:${toString cfg.dns.port} {
        bind ${concatStringsSep " " cfg.dns.listenAddresses}
        ${geoipBlock}
        # GeoIP metadata is consumed by template rules below. A single server
        # block is intentional: CoreDNS cannot bind multiple identical listeners.
        ${regionalTemplates}
        # Clients without a usable GeoIP result, and unknown continents, use all edges.
        ${defaultTemplates}
        file ${defaultZone} cdn.${domain}
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
      description = "Run authoritative CoreDNS for cdn.<networking.domain>.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.coredns;
      description = "CoreDNS package with geoip, metadata and view when GeoIP is enabled.";
    };

    dns = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default =
          (optional (selfIpv4 != "127.0.0.1") selfIpv4)
          ++ (optional (selfIpv6 != null) selfIpv6)
          ++ [
            "127.0.0.1"
            "::1"
          ];
        defaultText = "Current host's public addresses from terraform/cdn.tf";
        description = "Addresses on which authoritative DNS listens.";
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
        description = "Enable CoreDNS query logging; disabled by default.";
      };
    };

    geoip = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GeoIP2 continent views; databaseFile must exist on the host.";
      };

      databaseFile = mkOption {
        type = types.path;
        default = defaultGeoIpDatabase;
        description = "MaxMind GeoLite2 City/GeoIP2 database path.";
      };
    };

    doh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable DoH at https://cdn.<domain>/dns-query.";
      };

      port = mkOption {
        type = types.port;
        default = 5305;
        description = "Internal HTTP port for DoH, bound to loopback.";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.dns-over-https;
        description = "DoH HTTP server package. It forwards DNS queries to the local authoritative CoreDNS listener.";
      };

      upstream = mkOption {
        type = types.str;
        default = "tcp:127.0.0.1:53";
        description = "DoH upstream DNS endpoint. Keep this pointed at local CoreDNS to preserve ECS-based GeoIP steering.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = selfNode != null;
        message = "services.atc.router: networking.hostName must be present in terraform/cdn.tf cdn_edge_nodes.";
      }
      {
        assertion = nsNode != null;
        message = "services.atc.router: cdn.nsHost must be present in terraform/cdn.tf cdn_edge_nodes.";
      }
      {
        assertion = all (n: (n.ipv4 or null) != null) data.edgeNodes;
        message = "services.atc.router: every cdn_edge_nodes entry must resolve to an A record in terraform/hosts.tf.";
      }
      {
        assertion = all (origin: any (n: n.name == origin) data.edgeNodes) (attrValues data.services);
        message = "services.atc.router: every CDN service origin must be present in cdn_edge_nodes.";
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
      "d /var/lib/traffic_router 0750 trafficrouter trafficrouter -"
    ];

    environment.etc."traffic_router/Corefile".source = corefile;

    environment.etc."traffic_router/doh-server.conf".text = ''
      listen = [ "127.0.0.1:${toString cfg.doh.port}" ]
      local_addr = ""
      cert = ""
      key = ""
      path = "/dns-query"
      upstream = [ "${cfg.doh.upstream}" ]
      timeout = 5
      tries = 2
      verbose = false
      log_guessed_client_ip = false
      ecs_allow_non_global_ip = false
      ecs_use_precise_ip = false
    '';

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

    systemd.services.traffic-router-doh = {
      description = "DNS-over-HTTPS frontend for the ATC authoritative DNS server";
      after = [ "traffic-router.service" ];
      wants = [ "traffic-router.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "trafficrouter";
        Group = "trafficrouter";
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "128M";
        LimitNOFILE = 16384;
        ExecStart = "${cfg.doh.package}/bin/doh-server -conf /etc/traffic_router/doh-server.conf";
      };
    };

    services.traefik.proxies.traffic-router-doh =
      mkIf (cfg.doh.enable && (config.services.traefik.enable or false))
        {
          rule = "Host(`cdn.${domain}`) && PathPrefix(`/dns-query`)";
          target = "http://127.0.0.1:${toString cfg.doh.port}";
          entryPoints = [ "https" ];
        };
  };
}
