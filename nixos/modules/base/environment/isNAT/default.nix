{
  lib,
  config,
  ...
}:
with lib;
{
  options.environment = {
    isNAT = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable NAT mode.
      '';
    };
    altHTTPS = mkOption {
      type = types.int;
      default = 8443;
      description = ''
        The port of https alt
      '';
    };
    altHTTP = mkOption {
      type = types.int;
      default = 8080;
      description = ''
        The port of http alt
      '';
    };
  };
  config = {
    # networking =
    #   if config.environment.isNAT
    #   then {
    #     nftables.ruleset = ''
    #       table inet nat {
    #         chain prerouting {
    #           type nat hook prerouting priority 0; policy accept;
    #           tcp dport ${toString config.environment.altHTTP} redirect to 80
    #           # tcp dport ${toString config.environment.altHTTPS} redirect to 443
    #           # udp dport ${toString config.environment.altHTTPS} redirect to 443
    #           tcp dport 443 redirect to ${toString config.environment.altHTTPS}
    #           udp dport 443 redirect to ${toString config.environment.altHTTPS}
    #         }
    #         # chain output {
    #         #   type nat hook output priority 0; policy accept;
    #         #   tcp dport ${toString config.environment.altHTTP} redirect to 80
    #         #   # tcp dport ${toString config.environment.altHTTPS} redirect to 443
    #         #   # udp dport ${toString config.environment.altHTTPS} redirect to 443
    #         #   tcp dport 443 daddr 127.0.0.1 redirect to ${toString config.environment.altHTTPS}
    #         #   udp dport 443 daddr 127.0.0.1 redirect to ${toString config.environment.altHTTPS}
    #         # }
    #         chain postrouting {
    #           type nat hook postrouting priority 0; policy accept;
    #         }
    #       }
    #     '';
    #     firewall.allowedTCPPorts = with config.environment; [altHTTPS altHTTP];
    #     firewall.allowedUDPPorts = with config.environment; [altHTTPS];
    #   }
    #   else {};
    # services.traefik.staticConfigOptions.entryPoints.https =
    #   if config.environment.isNAT
    #   then {address = lib.mkForce ":${toString config.environment.altHTTPS}";}
    #   else {};
    services.traefik.staticConfigOptions.entryPoints =
      if config.environment.isNAT then
        {
          https-alt = {
            address = ":${toString config.environment.altHTTPS}";
            asDefault = true;
            inherit (config.services.traefik.staticConfigOptions.entryPoints.https)
              forwardedHeaders
              proxyProtocol
              transport
              http
              ;
          };
        }
      else
        { };
  };
}
