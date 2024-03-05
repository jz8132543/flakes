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
      AltHTTPS = mkOption {
        type = types.int;
        default = 8443;
        description = ''
          The port of https alt
        '';
      };
      AltHTTP = mkOption {
        type = types.int;
        default = 8080;
        description = ''
          The port of http alt
        '';
      };
      services.traefik.dynamicConfigOptions.http.routers =
        # if config.environment.isNAT
        # then
        mkOption {
          type = types.attrsOf (types.submodule ({config, ...}: {
            freeformType = types.attrsOf types.list;
            config.entryPoints = ["https-alt"];
            options.entryPoints = mkOption {
              type = types.listOf types.str;
              default = ["https-alt"];
            };
          }));
        };
      # else {};
    };
    config = {
      networking.firewall.allowedTCPPorts = with config.environment; [AltHTTPS AltHTTP];
      networking.firewall.allowedUDPPorts = with config.environment; [AltHTTPS];
    };
  }
