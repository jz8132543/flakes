{
  lib,
  config,
  ...
}: let
  cfg = config.services.traefik.dynamicConfigOptions.http.routers;
in
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
    config = {
      # services.traefik.dynamicConfigOptions.http.routers = attrsets.updateManyAttrsByPath [
      #   lists.forEach
      #   (attrsets.mapAttrsToList (name: value: name) cfg)
      #   (x: {
      #     path = [x "entryPoints"];
      #     update = old: old ++ ["https-alt"];
      #   })
      # ];
      # if config.environment.isNAT
      # then
      networking.nftables.ruleset = ''
        table ip nat {
          chain prerouting {
            type nat hook prerouting priority 0; policy accept;
            tcp dport ${toString config.environment.altHTTP} redirect to 80
            tcp dport ${toString config.environment.altHTTPS} redirect to 443
          }

          chain postrouting {
            type nat hook postrouting priority 0; policy accept;
          }
        }
      '';
      networking.firewall.allowedTCPPorts = with config.environment; [altHTTPS altHTTP];
      networking.firewall.allowedUDPPorts = with config.environment; [altHTTPS];
    };
  }
