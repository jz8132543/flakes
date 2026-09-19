{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.atc.router;

  cdnZone = pkgs.writeText "cdn.dora.im.zone" ''
    $ORIGIN cdn.dora.im.
    $TTL ${toString cfg.dns.ttl}
    @ IN SOA tr.dora.im. admin.dora.im. (
        2026091901 ; Serial
        7200       ; Refresh
        3600       ; Retry
        1209600    ; Expire
        ${toString cfg.dns.ttl} ; Minimum TTL
    )
    @ IN NS tr.dora.im.
    @ IN A ${cfg.originIp}
    @ IN AAAA ${cfg.originIpv6}

    ; Default Wildcard Fallback to nue0 Origin
    * IN A ${cfg.originIp}
    * IN AAAA ${cfg.originIpv6}

    ; Auto-generated mappings for all accelerated services from services.atc.domains
    ${concatMapStringsSep "\n" (
      d:
      let
        label = replaceStrings [ ".${config.networking.domain}" ".dora.im" ] [ "" "" ] d;
      in
      ''
        ${label} IN A ${cfg.originIp}
        ${label} IN AAAA ${cfg.originIpv6}
      ''
    ) config.services.atc.domains}
  '';

  trZone = pkgs.writeText "tr.dora.im.zone" ''
    $ORIGIN tr.dora.im.
    $TTL ${toString cfg.dns.ttl}
    @ IN SOA tr.dora.im. admin.dora.im. (
        2026091901 ; Serial
        7200       ; Refresh
        3600       ; Retry
        1209600    ; Expire
        ${toString cfg.dns.ttl} ; Minimum TTL
    )
    @ IN NS tr.dora.im.
    @ IN A ${cfg.originIp}
    @ IN AAAA ${cfg.originIpv6}
  '';

  corefile = pkgs.writeText "Corefile" ''
    cdn.dora.im:${toString cfg.dns.port} tr.dora.im:${toString cfg.dns.port} {
        bind ${concatStringsSep " " cfg.dns.listenAddresses}
        file ${cdnZone} cdn.dora.im
        file ${trZone} tr.dora.im
        errors
        log
    }

    ${optionalString cfg.doh.enable ''
      http://.:${toString cfg.doh.port} {
          bind 127.0.0.1
          file ${cdnZone} cdn.dora.im
          file ${trZone} tr.dora.im
          errors
      }
    ''}
  '';
in
{
  imports = [ ./common.nix ];

  options.services.atc.router = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Apache Traffic Control Traffic Router (DNS & DoH Steering)";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.coredns;
      description = "CoreDNS package to use for DNS steering";
    };

    originIp = mkOption {
      type = types.str;
      default = "185.216.178.70";
      description = "Default origin IPv4 address";
    };

    originIpv6 = mkOption {
      type = types.str;
      default = "2a03:4000:4f:92d::";
      description = "Default origin IPv6 address";
    };

    dns = {
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = [
          "185.216.178.70"
          "2a03:4000:4f:92d::"
        ];
        description = "Addresses to bind DNS server (public IPs to avoid collision with 127.0.0.1 dnsmasq)";
      };

      port = mkOption {
        type = types.port;
        default = 53;
        description = "DNS listening port";
      };

      ttl = mkOption {
        type = types.int;
        default = 60;
        description = "DNS response TTL in seconds";
      };
    };

    doh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable local DoH endpoint for Traefik termination";
      };

      port = mkOption {
        type = types.port;
        default = 5305;
        description = "Internal HTTP port for DoH queries";
      };
    };

    edgeNodes = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption { type = types.str; };
            ipv4 = mkOption { type = types.str; };
            ipv6 = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            region = mkOption {
              type = types.str;
              default = "AP";
            };
          };
        }
      );
      default = [
        {
          name = "tyo0";
          ipv4 = "45.66.130.158";
          region = "AP";
        }
        {
          name = "tyo1";
          ipv4 = "216.23.85.218";
          region = "AP";
        }
        {
          name = "hkg5";
          ipv4 = "216.23.94.148";
          region = "HK";
        }
        {
          name = "sjc0";
          ipv4 = "45.143.130.230";
          region = "US";
        }
        {
          name = "nue0";
          ipv4 = "185.216.178.70";
          ipv6 = "2a03:4000:4f:92d::";
          region = "EU";
        }
      ];
      description = "Configured edge nodes for traffic distribution";
    };
  };

  config = mkIf cfg.enable {
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
    environment.etc."traffic_router/zones/cdn.dora.im.zone".source = cdnZone;
    environment.etc."traffic_router/zones/tr.dora.im.zone".source = trZone;

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
        Restart = "always";
        RestartSec = "5s";
        MemoryMax = "256M";
        LimitNOFILE = 65536;
        ExecStart = "${cfg.package}/bin/coredns -conf /etc/traffic_router/Corefile";
      };
    };

    services.traefik.proxies.traffic-router-doh =
      mkIf (cfg.doh.enable && (config.services.traefik.enable or false))
        {
          rule = "Host(`tr.${config.networking.domain}`) && PathPrefix(`/dns-query`)";
          target = "http://127.0.0.1:${toString cfg.doh.port}";
        };
  };
}
