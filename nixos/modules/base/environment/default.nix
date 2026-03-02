{ lib, ... }:
{
  options.environment.minimal = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether to enable minimal environment optimizations for low-resource servers.
      This includes aggressive compression, reduced IO frequency, and disabling non-essential services.
    '';
  };
}
