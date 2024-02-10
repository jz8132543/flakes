{lib, ...}:
with lib; {
  options.environment.isNAT = lib.mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to enable NAT mode.
    '';
  };
}
