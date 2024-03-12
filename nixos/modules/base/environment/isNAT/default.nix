{
  lib,
  config,
  ...
}:
with lib; {
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
  config.networking =
    if config.environment.isNAT
    then {
      nftables.ruleset = ''
        table inet nat {
          chain prerouting {
            type nat hook prerouting priority 0; policy accept;
            tcp dport ${toString config.environment.altHTTP} redirect to 80
            tcp dport ${toString config.environment.altHTTPS} redirect to 443
            udp dport ${toString config.environment.altHTTPS} redirect to 443
          }
          chain output {
            type nat hook output priority 0; policy accept;
            tcp dport ${toString config.environment.altHTTP} redirect to 80
            tcp dport ${toString config.environment.altHTTPS} redirect to 443
            udp dport ${toString config.environment.altHTTPS} redirect to 443
          }

          chain postrouting {
            type nat hook postrouting priority 0; policy accept;
          }
        }
      '';
      firewall.allowedTCPPorts = with config.environment; [altHTTPS altHTTP];
      firewall.allowedUDPPorts = with config.environment; [altHTTPS];
    }
    else {};
}
