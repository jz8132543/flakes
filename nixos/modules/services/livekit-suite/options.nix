{ config, lib, ... }:
let
  cfg = config.services.livekitSuite;
  inherit (lib) mkOption types;
  defaults = import ./settings.nix;
  dataOptions =
    values:
    lib.mapAttrs (
      _: value:
      mkOption {
        type =
          if builtins.isAttrs value then
            types.submodule { options = dataOptions value; }
          else if builtins.isBool value then
            types.bool
          else if builtins.isInt value then
            types.ints.unsigned
          else if builtins.isFloat value then
            types.number
          else if builtins.isList value then
            types.listOf types.str
          else
            types.str;
        default = value;
        description = "LiveKit suite tuning parameter; see settings.nix.";
      }
    ) values;
  text =
    default:
    mkOption {
      type = types.str;
      inherit default;
    };
in
{
  options.services.livekitSuite = {
    settings = mkOption {
      type = types.submodule { options = dataOptions defaults; };
      default = { };
    };
    _meta = {
      enable = mkOption {
        type = types.bool;
        default = false;
        internal = true;
      };
      roles = lib.genAttrs [ "sfu" "turn" "web" "redis" ] (
        _:
        mkOption {
          type = types.bool;
          default = false;
          internal = true;
        }
      );
      publicIpv4 = text "";
      publicIpv6 = text "";
      domain = text "";
      httpsPort = mkOption {
        type = types.port;
        default = 443;
      };
      turnDomain = text "";
      region = text "";
      latitude = mkOption {
        type = types.number;
        default = 0;
      };
      longitude = mkOption {
        type = types.number;
        default = 0;
      };
      privateAddress = text "127.0.0.1";
      primary = mkOption {
        type = types.bool;
        default = false;
      };
      turnPort = mkOption {
        type = types.port;
        default = cfg.settings.turn.port;
        internal = true;
      };
      turnTlsPort = mkOption {
        type = types.port;
        default = cfg.settings.turn.advertisedTlsPort;
        internal = true;
      };
      redisPort = mkOption {
        type = types.port;
        default = cfg.settings.redis.port;
        internal = true;
      };
    };
    secretFile = mkOption {
      type = types.str;
      default = "/var/lib/livekit-suite/master-secret";
      description = "Runtime file containing the identical high-entropy master secret on all nodes; never a store path.";
    };
    development = mkOption {
      type = types.bool;
      default = false;
      description = "Generate a random persistent secret on this host for standalone development only.";
    };
    interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    redisAddress = text "";
    tls = {
      certFile = text "";
      keyFile = text "";
      external = mkOption {
        type = types.bool;
        default = false;
        description = "TURN TLS terminates at a local L4 proxy, forwarding to the plain TURN TCP listener.";
      };
    };
  };
  config.assertions = [
    {
      assertion =
        !cfg._meta.enable
        || (lib.hasPrefix "/" cfg.secretFile && !(lib.hasPrefix "/nix/store/" cfg.secretFile));
      message = "livekitSuite.secretFile must be an absolute runtime path outside the Nix store.";
    }
    {
      assertion = !cfg.development || cfg.secretFile == "/var/lib/livekit-suite/master-secret";
      message = "Development secret generation uses /var/lib/livekit-suite/master-secret.";
    }
  ];
}
