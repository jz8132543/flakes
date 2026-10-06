{ lib, ... }:
with lib;
{
  options.environment.domains = lib.mkOption {
    type = types.listOf types.str;
    default = [ "ts" ];
    description = ''
      tailscale search domains.
    '';
  };
}
