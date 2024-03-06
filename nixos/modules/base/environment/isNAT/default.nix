{
  lib,
  config,
  ...
}: let
  cfg = config.services.traefik.dynamicConfigOptions.http.routers;
  jsonValue = with lib.types; let
    valueType =
      nullOr (oneOf [
        bool
        int
        float
        str
        (lazyAttrsOf valueType)
        (listOf valueType)
      ])
      // {
        description = "JSON value";
        emptyValue.value = {};
      };
  in
    valueType;
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
    };
    options.services.traefik.dynamicConfigOptions.http.routers =
      # if config.environment.isNAT
      # then
      mkOption {
        type = types.jsonValue (types.submodule ({config, ...}: {
          freeformType = types.jsonValue types.list;
          config.entryPoints = ["https-alt"];
          options.entryPoints = mkOption {
            type = types.listOf types.str;
            default = ["https-alt"];
          };
        }));
      };
    # else {};
    config = {
      networking.firewall.allowedTCPPorts = with config.environment; [AltHTTPS AltHTTP];
      networking.firewall.allowedUDPPorts = with config.environment; [AltHTTPS];
    };
  }
